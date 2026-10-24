"""Flows declarativos no formato do Maestro, rodados pelo motor e sem rede.

O Maestro (mobile.dev, Apache 2.0) descreve um teste como lista de comandos em
YAML (`launchApp`, `tapOn`, `assertVisible`...) e esconde as esperas: procura o
elemento por ate 17 s (7 s se `optional`), toca e espera a hierarquia assentar
antes do proximo passo. Este modulo le o mesmo formato e roda com a mesma
semantica, sobre os adapters do proprio motor (adb e WebDriverAgent), para que
um flow escrito para o Maestro rode aqui e vice-versa.

O que fica de fora de proposito, e e recusado na validacao em vez de ignorado:
JavaScript (`runScript`, `evalScript`, `${expressao}`), comandos de IA e de
nuvem (`assertWithAI`, `extractTextWithAI`), web (`url`, `openLink`) e tudo que
ainda nao tem equivalente aqui. Nenhum caminho deste modulo abre conexao de
rede; o unico I/O e o do aparelho, por tras de `FlowDevice`.

Detalhes e comparacao em docs/research/maestro-modelo-de-automacao.md.
"""

from __future__ import annotations

import ast
import json
import re
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any

from mobaile.domain.errors import EngineError, InvalidInputError
from mobaile.domain.models import AutomationStep, UIElement
from mobaile.ports import FlowDevice
from mobaile.services.hierarchy import UIHierarchyParser

# Os mesmos prazos do Orchestra do Maestro (lookupTimeoutMs/optionalLookupTimeoutMs).
LOOKUP_TIMEOUT_S = 17.0
OPTIONAL_LOOKUP_TIMEOUT_S = 7.0
# waitForAnimationToEnd e scrollUntilVisible sem `timeout`, como no Maestro.
ANIMATION_TIMEOUT_S = 15.0
SCROLL_UNTIL_VISIBLE_TIMEOUT_S = 20.0
# extendedWaitUntil sem `timeout`: o Maestro exige o campo na pratica.
EXTENDED_WAIT_TIMEOUT_S = 10.0
# O Maestro compara a hierarquia ate 10 vezes, com 200 ms entre leituras.
SETTLE_TRIES = 10
SETTLE_INTERVAL_S = 0.2
POLL_INTERVAL_S = 0.3
MAX_RETRIES = 3
MAX_FLOW_DEPTH = 8
MAX_FLOW_BYTES = 512 * 1024
# eraseText sem quantidade apaga 50 caracteres, como no Maestro.
DEFAULT_ERASE = 50

_VAR = re.compile(r"\$\{([^}]*)\}")
_VAR_NAME = re.compile(r"[A-Za-z_]\w*")
_REGEX_FLAGS = re.IGNORECASE | re.DOTALL | re.MULTILINE

# Comandos que existem no Maestro e que este runner recusa, com o motivo.
_RECUSADOS = {
    "runScript": "JavaScript nao roda aqui (sem GraalJS)",
    "evalScript": "JavaScript nao roda aqui (sem GraalJS)",
    "assertTrue": "depende de expressao JavaScript",
    "assertWithAI": "usa a nuvem da mobile.dev",
    "assertNoDefectsWithAI": "usa a nuvem da mobile.dev",
    "extractTextWithAI": "usa a nuvem da mobile.dev",
    "openLink": "fluxo web ainda nao suportado",
}

_SELETOR_CHAVES = {"text", "id", "index", "point", "below", "above", "leftOf", "rightOf",
                   "childOf", "containsChild"}
_TAP_CHAVES = _SELETOR_CHAVES | {"optional", "retryTapIfNoChange", "waitToSettleTimeoutMs", "label"}


class FlowFailed(EngineError):
    """Um passo nao obrigatorio falhou: o flow para aqui."""


class FlowCancelled(EngineError):
    """`cancel()` foi pedido; nenhum passo novo comeca."""


# ------------------------------------------------------------------ modelo


@dataclass(frozen=True)
class Selector:
    text: str | None = None
    id: str | None = None
    index: int | None = None
    point: str | None = None
    below: Selector | None = None
    above: Selector | None = None
    left_of: Selector | None = None
    right_of: Selector | None = None
    child_of: Selector | None = None
    contains_child: Selector | None = None

    def describe(self) -> str:
        partes = []
        if self.text is not None:
            partes.append(f"texto ~ {self.text!r}")
        if self.id is not None:
            partes.append(f"id ~ {self.id!r}")
        if self.point is not None:
            partes.append(f"ponto {self.point}")
        for nome, sub in (("abaixo de", self.below), ("acima de", self.above),
                          ("a esquerda de", self.left_of), ("a direita de", self.right_of),
                          ("dentro de", self.child_of), ("contendo", self.contains_child)):
            if sub is not None:
                partes.append(f"{nome} [{sub.describe()}]")
        if self.index is not None:
            partes.append(f"indice {self.index}")
        return ", ".join(partes) or "qualquer elemento"


@dataclass(frozen=True)
class Step:
    """Um comando do flow, ja validado. So os campos do comando ficam preenchidos."""

    command: str
    selector: Selector | None = None
    text: str | None = None
    app_id: str | None = None
    optional: bool = False
    timeout_s: float | None = None
    count: int | None = None
    key: str | None = None
    direction: str | None = None
    start: str | None = None
    end: str | None = None
    duration_ms: int = 400
    clear_state: bool = False
    stop_first: bool = True
    retry_if_no_change: bool = False
    visible: bool = True
    when: dict[str, Any] | None = None
    max_retries: int = 1
    steps: tuple[Step, ...] = ()
    label: str | None = None
    source: str = ""

    def describe(self) -> str:
        if self.label:
            return self.label
        if self.command == "inputText":
            # Nunca o valor: pode ser senha, e a linha vira `flow.log`.
            return f"inputText ({len(self.text or '')} caracteres)"
        detalhe = self.selector.describe() if self.selector else (self.app_id or self.key or self.direction or "")
        comando = "assertNotVisible" if self.command == "assertVisible" and not self.visible else self.command
        return f"{comando} {detalhe}".strip()


@dataclass
class Flow:
    app_id: str | None
    name: str | None
    tags: tuple[str, ...]
    steps: tuple[Step, ...]
    on_start: tuple[Step, ...] = ()
    on_complete: tuple[Step, ...] = ()
    path: Path | None = None
    secrets: tuple[str, ...] = ()

    def summary(self) -> dict[str, Any]:
        return {
            "app_id": self.app_id,
            "name": self.name,
            "tags": list(self.tags),
            "steps": [s.describe() for s in self.steps],
        }


@dataclass
class FlowResult:
    success: bool
    message: str
    steps_run: int = 0
    failed_step: str | None = None
    log: list[str] = field(default_factory=list)


# ----------------------------------------------------------------- leitura


def _yaml():
    try:
        import yaml
    except ImportError as exc:  # pragma: no cover - depende do Python do usuario
        raise InvalidInputError(
            "Ler flow YAML precisa do PyYAML no Python do motor: python3 -m pip install PyYAML"
        ) from exc
    return yaml


def _substituir(valor: Any, env: dict[str, str], usados: set[str]) -> Any:
    """Troca `${NOME}` pelo valor de `env`. Expressao JavaScript e recusada."""
    if isinstance(valor, str):
        def troca(m: re.Match) -> str:
            nome = m.group(1).strip()
            if not _VAR_NAME.fullmatch(nome):
                raise InvalidInputError(f"Expressao ${{{nome}}} e JavaScript; so ${{VARIAVEL}} e suportado.")
            if nome not in env:
                raise InvalidInputError(f"Variavel ${{{nome}}} sem valor: passe em `env`.")
            usados.add(nome)
            return env[nome]
        return _VAR.sub(troca, valor)
    if isinstance(valor, list):
        return [_substituir(v, env, usados) for v in valor]
    if isinstance(valor, dict):
        return {k: _substituir(v, env, usados) for k, v in valor.items()}
    return valor


def _str_env(origem: Any, rotulo: str) -> dict[str, str]:
    if origem is None:
        return {}
    if not isinstance(origem, dict):
        raise InvalidInputError(f"`{rotulo}` precisa ser um mapa NOME: valor.")
    saida = {}
    for k, v in origem.items():
        if not isinstance(k, str) or not _VAR_NAME.fullmatch(k):
            raise InvalidInputError(f"Nome de variavel invalido em `{rotulo}`: {k!r}")
        saida[k] = "" if v is None else str(v)
    return saida


def parse_flow(
    text: str,
    *,
    path: Path | None = None,
    env: dict[str, str] | None = None,
    _depth: int = 0,
) -> Flow:
    """Le e valida um flow. Levanta `InvalidInputError` com o motivo, sem tocar aparelho.

    `env` (do chamador) vence o `env:` do cabecalho, como `maestro test -e`.
    Os valores usados em `${...}` voltam em `Flow.secrets`, para o log mascarar.
    """
    if len(text.encode("utf-8", errors="ignore")) > MAX_FLOW_BYTES:
        raise InvalidInputError("Flow grande demais.")
    yaml = _yaml()
    try:
        docs = [d for d in yaml.safe_load_all(text) if d is not None]
    except yaml.YAMLError as exc:
        raise InvalidInputError(f"YAML invalido: {exc}") from exc

    if len(docs) == 1 and isinstance(docs[0], list):
        config, comandos = {}, docs[0]
    elif len(docs) == 2 and isinstance(docs[0], dict) and isinstance(docs[1], list):
        config, comandos = docs
    else:
        raise InvalidInputError("Flow precisa de um cabecalho (appId...) e, depois de `---`, a lista de comandos.")

    desconhecidas = set(config) - {"appId", "name", "tags", "env", "onFlowStart", "onFlowComplete"}
    if "url" in desconhecidas:
        raise InvalidInputError("Flow web (`url`) ainda nao e suportado.")
    if desconhecidas:
        raise InvalidInputError(f"Cabecalho com chave nao suportada: {', '.join(sorted(desconhecidas))}")

    variaveis = {**_str_env(config.get("env"), "env"), **_str_env(env, "env do chamador")}
    leitor = _Leitor(path.parent if path else None, variaveis, _depth)
    cabecalho = {k: v for k, v in config.items() if k not in ("onFlowStart", "onFlowComplete")}
    config = {**config, **leitor.substituir(cabecalho)}
    tags = config.get("tags") or []
    if not isinstance(tags, list):
        raise InvalidInputError("`tags` precisa ser lista.")
    flow = Flow(
        app_id=_opt_str(config.get("appId"), "appId"),
        name=_opt_str(config.get("name"), "name"),
        tags=tuple(str(t) for t in tags),
        steps=leitor.lista(comandos, "flow"),
        on_start=leitor.lista(config.get("onFlowStart") or [], "onFlowStart"),
        on_complete=leitor.lista(config.get("onFlowComplete") or [], "onFlowComplete"),
        path=path,
    )
    flow.secrets = tuple(sorted(set(leitor.segredos), key=len, reverse=True))
    return flow


def load_flow(path: str | Path, env: dict[str, str] | None = None) -> Flow:
    alvo = Path(path).expanduser().resolve()
    if alvo.suffix.lower() not in (".yaml", ".yml"):
        raise InvalidInputError("Flow precisa ser .yaml ou .yml.")
    if not alvo.is_file():
        raise InvalidInputError(f"Flow nao encontrado: {alvo}")
    return parse_flow(alvo.read_text(encoding="utf-8"), path=alvo, env=env)


def _opt_str(valor: Any, rotulo: str) -> str | None:
    if valor is None:
        return None
    if isinstance(valor, (dict, list)):
        raise InvalidInputError(f"`{rotulo}` precisa ser texto.")
    return str(valor)


def _timeout(valor: Any, padrao: float | None) -> float | None:
    if valor is None:
        return padrao
    if isinstance(valor, bool) or not isinstance(valor, (int, float)) or valor < 0 or valor > 600_000:
        raise InvalidInputError(f"Timeout invalido (ms): {valor!r}")
    return float(valor) / 1000.0


class _Leitor:
    """Converte os comandos do YAML em `Step`, recusando o que nao suporta."""

    def __init__(self, base: Path | None, env: dict[str, str], depth: int):
        self.base = base
        self.env = env
        self.depth = depth
        self.segredos: list[str] = []

    def substituir(self, valor: Any, env: dict[str, str] | None = None) -> Any:
        """`${NOME}` -> valor. O valor usado entra nos segredos que o log mascara."""
        usados: set[str] = set()
        env = self.env if env is None else env
        saida = _substituir(valor, env, usados)
        self.segredos.extend(env[n] for n in usados)
        return saida

    def lista(self, comandos: Any, onde: str) -> tuple[Step, ...]:
        if not isinstance(comandos, list):
            raise InvalidInputError(f"`{onde}` precisa ser uma lista de comandos.")
        return tuple(self.comando(c, f"{onde}[{i + 1}]") for i, c in enumerate(comandos))

    def comando(self, bruto: Any, onde: str) -> Step:
        if isinstance(bruto, str):
            nome, args = bruto, None
        elif isinstance(bruto, dict) and len(bruto) == 1:
            nome, args = next(iter(bruto.items()))
        else:
            raise InvalidInputError(f"{onde}: cada item e um comando (`- tapOn: ...`).")
        if nome in _RECUSADOS:
            raise InvalidInputError(f"{onde}: `{nome}` nao e suportado: {_RECUSADOS[nome]}.")
        metodo = getattr(self, f"_c_{nome}", None)
        if metodo is None:
            raise InvalidInputError(f"{onde}: comando `{nome}` ainda nao e suportado pelo runner do Mo baile.")
        if nome in ("runFlow", "retry") and isinstance(args, dict):
            # `commands` espera: o `env` do bloco vale la dentro, por cima do flow.
            args = {k: (v if k == "commands" else self.substituir(v)) for k, v in args.items()}
        else:
            args = self.substituir(args)
        try:
            return metodo(args, onde)
        except InvalidInputError:
            raise
        except (TypeError, ValueError) as exc:
            raise InvalidInputError(f"{onde}: argumentos invalidos para `{nome}`: {exc}") from exc

    # --- seletor

    def seletor(self, bruto: Any, onde: str, chaves: set[str] = _SELETOR_CHAVES) -> tuple[Selector, dict]:
        if isinstance(bruto, (str, int, float)) and not isinstance(bruto, bool):
            return Selector(text=str(bruto)), {}
        if not isinstance(bruto, dict):
            raise InvalidInputError(f"{onde}: seletor precisa ser texto ou mapa.")
        sobra = set(bruto) - chaves
        if sobra:
            raise InvalidInputError(f"{onde}: propriedade nao suportada: {', '.join(sorted(sobra))}")
        rel = {}
        for chave, campo in (("below", "below"), ("above", "above"), ("leftOf", "left_of"),
                             ("rightOf", "right_of"), ("childOf", "child_of"), ("containsChild", "contains_child")):
            if chave in bruto:
                rel[campo] = self.seletor(bruto[chave], f"{onde}.{chave}")[0]
        indice = bruto.get("index")
        if indice is not None:
            indice = int(str(indice))
        ponto = bruto.get("point")
        if ponto is not None:
            _ponto_valido(str(ponto), onde)
        sel = Selector(
            text=None if bruto.get("text") is None else str(bruto["text"]),
            id=None if bruto.get("id") is None else str(bruto["id"]),
            index=indice,
            point=None if ponto is None else str(ponto),
            **rel,
        )
        extras = {k: bruto[k] for k in set(bruto) - _SELETOR_CHAVES}
        return sel, extras

    # --- comandos

    def _c_launchApp(self, args, onde):
        if args is None or isinstance(args, str):
            return Step("launchApp", app_id=args, source=onde)
        _chaves(args, {"appId", "clearState", "stopApp", "label"}, onde)
        return Step("launchApp", app_id=_opt_str(args.get("appId"), "appId"),
                    clear_state=bool(args.get("clearState", False)),
                    stop_first=bool(args.get("stopApp", True)), label=args.get("label"), source=onde)

    def _c_stopApp(self, args, onde):
        return Step("stopApp", app_id=_opt_str(args, "stopApp"), source=onde)

    def _c_clearState(self, args, onde):
        return Step("clearState", app_id=_opt_str(args, "clearState"), source=onde)

    def _c_tapOn(self, args, onde):
        sel, extras = self.seletor(args, onde, _TAP_CHAVES)
        return Step("tapOn", selector=sel, optional=bool(extras.get("optional", False)),
                    retry_if_no_change=bool(extras.get("retryTapIfNoChange", False)),
                    timeout_s=_timeout(extras.get("waitToSettleTimeoutMs"), None),
                    label=extras.get("label"), source=onde)

    def _c_inputText(self, args, onde):
        if isinstance(args, dict):
            _chaves(args, {"text", "label"}, onde)
            texto, rotulo = args.get("text"), args.get("label")
        else:
            texto, rotulo = args, None
        if texto is None or isinstance(texto, (dict, list)):
            raise InvalidInputError(f"{onde}: inputText precisa de texto.")
        texto = str(texto)
        self.segredos.append(texto)
        return Step("inputText", text=texto, label=rotulo, source=onde)

    def _c_eraseText(self, args, onde):
        if isinstance(args, dict):
            _chaves(args, {"charactersToErase", "label"}, onde)
            n = args.get("charactersToErase", DEFAULT_ERASE)
        else:
            n = DEFAULT_ERASE if args is None else args
        n = int(n)
        if not 0 <= n <= 1000:
            raise InvalidInputError(f"{onde}: eraseText fora da faixa: {n}")
        return Step("eraseText", count=n, source=onde)

    def _c_pressKey(self, args, onde):
        return Step("pressKey", key=str(args), source=onde)

    def _c_back(self, _args, onde):
        return Step("pressKey", key="Back", label="back", source=onde)

    def _c_hideKeyboard(self, _args, onde):
        return Step("pressKey", key="Escape", label="hideKeyboard", source=onde)

    def _visivel(self, args, onde, visivel):
        sel, extras = self.seletor(args, onde, _SELETOR_CHAVES | {"optional", "label"})
        return Step("assertVisible", selector=sel, visible=visivel,
                    optional=bool(extras.get("optional", False)), label=extras.get("label"), source=onde)

    def _c_assertVisible(self, args, onde):
        return self._visivel(args, onde, True)

    def _c_assertNotVisible(self, args, onde):
        return self._visivel(args, onde, False)

    def _c_extendedWaitUntil(self, args, onde):
        _chaves(args, {"visible", "notVisible", "timeout", "optional", "label"}, onde)
        if ("visible" in args) == ("notVisible" in args):
            raise InvalidInputError(f"{onde}: extendedWaitUntil precisa de `visible` ou de `notVisible`.")
        visivel = "visible" in args
        sel = self.seletor(args["visible" if visivel else "notVisible"], onde)[0]
        return Step("assertVisible", selector=sel, visible=visivel,
                    timeout_s=_timeout(args.get("timeout"), EXTENDED_WAIT_TIMEOUT_S),
                    optional=bool(args.get("optional", False)), label=args.get("label"), source=onde)

    def _c_waitForAnimationToEnd(self, args, onde):
        bruto = args.get("timeout") if isinstance(args, dict) else None
        return Step("waitForAnimationToEnd", timeout_s=_timeout(bruto, ANIMATION_TIMEOUT_S), source=onde)

    def _c_scroll(self, _args, onde):
        return Step("swipe", direction="UP", label="scroll", source=onde)

    def _c_swipe(self, args, onde):
        _chaves(args, {"direction", "start", "end", "duration", "label"}, onde)
        direcao = args.get("direction")
        if direcao is not None:
            direcao = str(direcao).upper()
            if direcao not in ("UP", "DOWN", "LEFT", "RIGHT"):
                raise InvalidInputError(f"{onde}: direcao invalida: {direcao}")
        elif not ("start" in args and "end" in args):
            raise InvalidInputError(f"{onde}: swipe precisa de `direction` ou de `start` e `end`.")
        for chave in ("start", "end"):
            if chave in args:
                _ponto_valido(str(args[chave]), onde)
        return Step("swipe", direction=direcao, start=_opt_str(args.get("start"), "start"),
                    end=_opt_str(args.get("end"), "end"), duration_ms=int(args.get("duration", 400)),
                    label=args.get("label"), source=onde)

    def _c_scrollUntilVisible(self, args, onde):
        _chaves(args, {"element", "direction", "timeout", "optional", "label"}, onde)
        direcao = str(args.get("direction", "DOWN")).upper()
        if direcao not in ("UP", "DOWN", "LEFT", "RIGHT"):
            raise InvalidInputError(f"{onde}: direcao invalida: {direcao}")
        return Step("scrollUntilVisible", selector=self.seletor(args["element"], onde)[0], direction=direcao,
                    timeout_s=_timeout(args.get("timeout"), SCROLL_UNTIL_VISIBLE_TIMEOUT_S),
                    optional=bool(args.get("optional", False)), label=args.get("label"), source=onde)

    def _c_runFlow(self, args, onde):
        if isinstance(args, str):
            args = {"file": args}
        _chaves(args, {"file", "commands", "when", "env", "label"}, onde)
        if ("file" in args) == ("commands" in args):
            raise InvalidInputError(f"{onde}: runFlow precisa de `file` ou de `commands`.")
        quando = self._quando(args.get("when"), onde)
        return Step("runFlow", steps=self._sub(args, onde), when=quando, label=args.get("label"), source=onde)

    def _c_retry(self, args, onde):
        _chaves(args, {"maxRetries", "file", "commands", "env", "label"}, onde)
        if ("file" in args) == ("commands" in args):
            raise InvalidInputError(f"{onde}: retry precisa de `file` ou de `commands`.")
        n = int(args.get("maxRetries", 1))
        if not 0 <= n <= MAX_RETRIES:
            raise InvalidInputError(f"{onde}: maxRetries vai de 0 a {MAX_RETRIES}.")
        return Step("retry", steps=self._sub(args, onde), max_retries=n, label=args.get("label"), source=onde)

    def _quando(self, bruto, onde):
        if bruto is None:
            return None
        _chaves(bruto, {"visible", "notVisible", "platform"}, onde)
        quando: dict[str, Any] = {}
        for chave in ("visible", "notVisible"):
            if chave in bruto:
                quando[chave] = self.seletor(bruto[chave], f"{onde}.when.{chave}")[0]
        if "platform" in bruto:
            quando["platform"] = str(bruto["platform"]).lower()
        return quando

    def _sub(self, args, onde) -> tuple[Step, ...]:
        env_local = _str_env(args.get("env"), "env")
        if "commands" in args:
            filho = _Leitor(self.base, {**self.env, **env_local}, self.depth)
            passos = filho.lista(args["commands"], f"{onde}.commands")
            self.segredos.extend(filho.segredos)
            return passos
        if self.depth + 1 > MAX_FLOW_DEPTH:
            raise InvalidInputError(f"{onde}: runFlow aninhado demais (ciclo?).")
        if self.base is None:
            raise InvalidInputError(f"{onde}: `file` so funciona em flow lido de arquivo.")
        alvo = (self.base / str(args["file"])).resolve()
        if alvo.suffix.lower() not in (".yaml", ".yml") or not alvo.is_file():
            raise InvalidInputError(f"{onde}: subflow nao encontrado: {args['file']}")
        sub = parse_flow(alvo.read_text(encoding="utf-8"), path=alvo,
                         env={**self.env, **env_local}, _depth=self.depth + 1)
        self.segredos.extend(sub.secrets)
        return sub.on_start + sub.steps + sub.on_complete


def _chaves(args: Any, permitidas: set[str], onde: str) -> None:
    if not isinstance(args, dict):
        raise InvalidInputError(f"{onde}: esperava um mapa de propriedades.")
    sobra = set(args) - permitidas
    if sobra:
        raise InvalidInputError(f"{onde}: propriedade nao suportada: {', '.join(sorted(sobra))}")


_PONTO = re.compile(r"\s*(\d+(?:\.\d+)?)(%?)\s*,\s*(\d+(?:\.\d+)?)(%?)\s*")


def _ponto_valido(texto: str, onde: str) -> None:
    m = _PONTO.fullmatch(texto)
    if not m or (m.group(2) and float(m.group(1)) > 100) or (m.group(4) and float(m.group(3)) > 100):
        raise InvalidInputError(f"{onde}: ponto invalido {texto!r}; use \"x,y\" ou \"x%,y%\".")


def resolve_point(texto: str, largura: int, altura: int) -> tuple[int, int]:
    m = _PONTO.fullmatch(texto)
    if not m:
        raise InvalidInputError(f"Ponto invalido: {texto!r}")
    x = float(m.group(1)) * largura / 100 if m.group(2) else float(m.group(1))
    y = float(m.group(3)) * altura / 100 if m.group(4) else float(m.group(3))
    return int(x), int(y)


# ----------------------------------------------------------------- selecao


def _regex(padrao: str) -> re.Pattern:
    try:
        return re.compile(padrao, _REGEX_FLAGS)
    except re.error:
        # Igual ao `toRegexSafe` do Maestro: regex invalida vira texto literal.
        return re.compile(re.escape(padrao), _REGEX_FLAGS)


def _casa(regex: re.Pattern, valor: str) -> bool:
    if not valor:
        return False
    achatado = valor.replace("\n", " ")
    return bool(regex.fullmatch(valor) or regex.fullmatch(achatado)
                or regex.pattern in (valor, achatado))


def _ancestrais(i: int, elementos: list[UIElement]) -> list[int]:
    saida = []
    pai = elementos[i].parent_idx
    while pai is not None and pai not in saida:
        saida.append(pai)
        pai = elementos[pai].parent_idx
    return saida


def select_elements(sel: Selector, elementos: list[UIElement]) -> list[int]:
    """Indices dos elementos que o seletor casa, na ordem em que o Maestro escolheria.

    Mesma receita do `buildFilter` do Orchestra: texto e id sao regex de
    casamento inteiro, sem caixa; dos casados fica o mais fundo (um rotulo
    dentro de um botao com o mesmo texto da o rotulo); filtros relativos
    depois; e sem `index`, clicavel vem primeiro.
    """
    candidatos = list(range(len(elementos)))
    basicos = sel.text is not None or sel.id is not None
    if sel.text is not None:
        rx = _regex(sel.text)
        candidatos = [i for i in candidatos
                      if _casa(rx, elementos[i].text) or _casa(rx, elementos[i].content_desc)]
    if sel.id is not None:
        rx = _regex(sel.id)
        candidatos = [i for i in candidatos
                      if (rid := elementos[i].resource_id)
                      and (rx.fullmatch(rid) or rx.fullmatch(rid.rsplit("/", 1)[-1]))]
    if basicos:
        conjunto = set(candidatos)
        tem_filho_casado = {a for i in candidatos for a in _ancestrais(i, elementos) if a in conjunto}
        candidatos = [i for i in candidatos if i not in tem_filho_casado]

    def ref(sub: Selector) -> list[int]:
        return select_elements(sub, elementos)

    def caixa(i: int) -> tuple[int, int, int, int]:
        return elementos[i].bounds

    for sub, fica, distancia in (
        (sel.below, lambda e, r: e[1] >= r[3], lambda e, r: e[1] - r[3]),
        (sel.above, lambda e, r: e[3] <= r[1], lambda e, r: r[1] - e[3]),
        (sel.right_of, lambda e, r: e[0] >= r[2], lambda e, r: e[0] - r[2]),
        (sel.left_of, lambda e, r: e[2] <= r[0], lambda e, r: r[0] - e[2]),
    ):
        if sub is None:
            continue
        refs = ref(sub)
        if not refs:
            return []
        r = caixa(refs[0])
        candidatos = sorted((i for i in candidatos if i != refs[0] and fica(caixa(i), r)),
                            key=lambda i, r=r, d=distancia: d(caixa(i), r))
    if sel.child_of is not None:
        pais = set(ref(sel.child_of))
        candidatos = [i for i in candidatos if pais.intersection(_ancestrais(i, elementos))]
    if sel.contains_child is not None:
        filhos = ref(sel.contains_child)
        pais_diretos = {elementos[f].parent_idx for f in filhos}
        candidatos = [i for i in candidatos if i in pais_diretos]

    if sel.index is not None:
        por_posicao = sorted(candidatos, key=lambda i: (caixa(i)[1], caixa(i)[0]))
        idx = sel.index if sel.index >= 0 else len(por_posicao) + sel.index
        return [por_posicao[idx]] if 0 <= idx < len(por_posicao) else []
    # Ordenacao estavel: entre clicaveis (e entre nao clicaveis) fica a ordem de distancia.
    return sorted(candidatos, key=lambda i: not elementos[i].clickable)


# ---------------------------------------------------------------- execucao


_DIRECOES = {
    # De onde para onde o dedo vai, em fracao da tela. `scroll` = dedo para cima.
    "UP": ((0.5, 0.7), (0.5, 0.3)),
    "DOWN": ((0.5, 0.3), (0.5, 0.7)),
    "LEFT": ((0.8, 0.5), (0.2, 0.5)),
    "RIGHT": ((0.2, 0.5), (0.8, 0.5)),
}
# scrollUntilVisible DOWN quer ver o que esta abaixo: o dedo sobe.
_ROLAGEM = {"DOWN": "UP", "UP": "DOWN", "LEFT": "RIGHT", "RIGHT": "LEFT"}


class FlowRunner:
    """Roda um `Flow` num `FlowDevice`, com as esperas do Maestro.

    `clock`, `sleep` e os prazos sao injetaveis para o teste rodar sem
    aparelho e sem esperar de verdade.
    """

    def __init__(
        self,
        device: FlowDevice,
        *,
        log: Callable[[str], None] = lambda _l: None,
        cancelled: Callable[[], bool] = lambda: False,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
        lookup_timeout_s: float = LOOKUP_TIMEOUT_S,
        optional_lookup_timeout_s: float = OPTIONAL_LOOKUP_TIMEOUT_S,
    ):
        self.device = device
        self._log = log
        self._cancelled = cancelled
        self._clock = clock
        self._sleep = sleep
        self.lookup_timeout_s = lookup_timeout_s
        self.optional_lookup_timeout_s = optional_lookup_timeout_s
        self._app_id: str | None = None
        self._segredos: tuple[str, ...] = ()
        self._linhas: list[str] = []

    def log(self, linha: str) -> None:
        for segredo in self._segredos:
            if len(segredo) >= 3:
                linha = linha.replace(segredo, "***")
        self._linhas.append(linha)
        self._log(linha)

    def run(self, flow: Flow) -> FlowResult:
        self._app_id = flow.app_id
        self._segredos = flow.secrets
        self._linhas = []
        nome = flow.name or (flow.path.name if flow.path else "flow")
        self.log(f"Flow {nome}: {len(flow.steps)} comandos, app {flow.app_id or '(nenhum)'}")
        feitos = 0
        falha: Step | None = None
        mensagem = "Flow executado com sucesso."
        sucesso = True
        try:
            for passo in flow.on_start:
                self._passo(passo, "onFlowStart")
            total = len(flow.steps)
            for n, passo in enumerate(flow.steps, start=1):
                falha = passo
                self._passo(passo, f"{n}/{total}")
                feitos += 1
            falha = None
        except FlowCancelled:
            sucesso, mensagem = False, "Flow cancelado."
        except (FlowFailed, EngineError) as exc:
            sucesso, mensagem = False, str(exc)
        finally:
            # Como no Maestro, onFlowComplete roda mesmo depois de falha.
            if flow.on_complete and not self._cancelled():
                try:
                    for passo in flow.on_complete:
                        self._passo(passo, "onFlowComplete")
                except (FlowCancelled, FlowFailed, EngineError) as exc:
                    self.log(f"onFlowComplete falhou: {exc}")
        self.log(("✔ " if sucesso else "✘ ") + mensagem)
        return FlowResult(sucesso, mensagem, feitos, falha.describe() if falha else None, list(self._linhas))

    # --- passos

    def _checar(self) -> None:
        if self._cancelled():
            raise FlowCancelled("Flow cancelado.")

    def _passo(self, passo: Step, posicao: str) -> None:
        self._checar()
        self.log(f"▶ [{posicao}] {passo.describe()}")
        try:
            getattr(self, f"_r_{passo.command}")(passo)
        except FlowFailed as exc:
            if passo.optional:
                self.log(f"  opcional, seguindo: {exc}")
                return
            raise FlowFailed(f"{passo.source or posicao}: {exc}") from exc

    def _xml(self) -> str:
        xml = self.device.hierarchy()
        if not xml:
            raise FlowFailed("o aparelho nao devolveu a hierarquia")
        return xml

    def _elementos(self, xml: str) -> list[UIElement]:
        elementos = UIHierarchyParser.parse_xml(xml)
        largura, altura = self.device.screen_size()
        if largura and altura:
            # Visivel = centro dentro da tela, como o assertVisible do Maestro exige.
            elementos = [e if 0 <= e.center[0] <= largura and 0 <= e.center[1] <= altura else
                         _invisivel(e) for e in elementos]
        return elementos

    def _procurar(self, sel: Selector, prazo_s: float) -> tuple[UIElement | None, str]:
        """Le a arvore ate o seletor casar ou o prazo acabar."""
        limite = self._clock() + prazo_s
        while True:
            self._checar()
            xml = self.device.hierarchy() or ""
            elementos = self._elementos(xml) if xml else []
            achados = [i for i in select_elements(sel, elementos) if elementos[i].area > 0]
            if achados:
                return elementos[achados[0]], xml
            if self._clock() >= limite:
                return None, xml
            self._sleep(POLL_INTERVAL_S)

    def _assentar(self, prazo_s: float | None = None) -> str | None:
        """Espera duas leituras seguidas iguais da hierarquia (waitForAppToSettle)."""
        anterior = self.device.hierarchy()
        limite = self._clock() + prazo_s if prazo_s else None
        for _ in range(SETTLE_TRIES if limite is None else 10_000):
            self._checar()
            self._sleep(SETTLE_INTERVAL_S)
            atual = self.device.hierarchy()
            if atual == anterior:
                return atual
            anterior = atual
            if limite is not None and self._clock() >= limite:
                break
        return anterior

    def _alvo(self, sel: Selector, optional: bool) -> tuple[tuple[int, int], str | None]:
        if sel.point is not None and sel.text is None and sel.id is None:
            largura, altura = self.device.screen_size()
            return resolve_point(sel.point, largura, altura), None
        prazo = self.optional_lookup_timeout_s if optional else self.lookup_timeout_s
        elemento, xml = self._procurar(sel, prazo)
        if elemento is None:
            raise FlowFailed(f"elemento nao encontrado em {prazo:.0f} s: {sel.describe()}")
        if sel.point is not None:
            # point junto com seletor e relativo ao elemento, como relativePoint.
            x1, y1, x2, y2 = elemento.bounds
            dx, dy = resolve_point(sel.point, x2 - x1, y2 - y1)
            return (x1 + dx, y1 + dy), xml
        return elemento.center, xml

    def _r_tapOn(self, passo: Step) -> None:
        (x, y), antes = self._alvo(passo.selector, passo.optional)
        for tentativa in range(2 if passo.retry_if_no_change else 1):
            if not self.device.tap(x, y):
                raise FlowFailed(f"o toque em ({x}, {y}) foi recusado pelo aparelho")
            depois = self._assentar(passo.timeout_s)
            if antes is None or depois != antes:
                return
            if tentativa == 0 and passo.retry_if_no_change:
                self.log("  a tela nao mudou; tocando de novo")

    def _r_inputText(self, passo: Step) -> None:
        if not self.device.type_text(passo.text or ""):
            raise FlowFailed("o aparelho recusou a digitacao")
        self._assentar()

    def _r_eraseText(self, passo: Step) -> None:
        for _ in range(passo.count or 0):
            self._checar()
            if not self.device.press_key("Backspace"):
                raise FlowFailed("o aparelho recusou apagar texto")
        self._assentar()

    def _r_pressKey(self, passo: Step) -> None:
        if not self.device.press_key(passo.key or ""):
            raise FlowFailed(f"tecla {passo.key!r} recusada ou desconhecida")
        self._assentar()

    def _r_assertVisible(self, passo: Step) -> None:
        prazo = passo.timeout_s or (self.optional_lookup_timeout_s if passo.optional else self.lookup_timeout_s)
        if passo.visible:
            elemento, _ = self._procurar(passo.selector, prazo)
            if elemento is None:
                raise FlowFailed(f"nao ficou visivel em {prazo:.0f} s: {passo.selector.describe()}")
            return
        limite = self._clock() + prazo
        while True:
            self._checar()
            elemento, _ = self._procurar(passo.selector, 0)
            if elemento is None:
                return
            if self._clock() >= limite:
                raise FlowFailed(f"continua visivel depois de {prazo:.0f} s: {passo.selector.describe()}")
            self._sleep(POLL_INTERVAL_S)

    def _r_waitForAnimationToEnd(self, passo: Step) -> None:
        self._assentar(passo.timeout_s)

    def _deslizar(self, direcao: str, duracao_ms: int) -> None:
        largura, altura = self.device.screen_size()
        (fx1, fy1), (fx2, fy2) = _DIRECOES[direcao]
        if not self.device.swipe(int(largura * fx1), int(altura * fy1), int(largura * fx2),
                                 int(altura * fy2), duracao_ms):
            raise FlowFailed("o aparelho recusou o deslize")

    def _r_swipe(self, passo: Step) -> None:
        if passo.direction:
            self._deslizar(passo.direction, passo.duration_ms)
        else:
            largura, altura = self.device.screen_size()
            x1, y1 = resolve_point(passo.start or "", largura, altura)
            x2, y2 = resolve_point(passo.end or "", largura, altura)
            if not self.device.swipe(x1, y1, x2, y2, passo.duration_ms):
                raise FlowFailed("o aparelho recusou o deslize")
        self._assentar()

    def _r_scrollUntilVisible(self, passo: Step) -> None:
        limite = self._clock() + (passo.timeout_s or SCROLL_UNTIL_VISIBLE_TIMEOUT_S)
        while True:
            elemento, _ = self._procurar(passo.selector, 0)
            if elemento is not None:
                return
            if self._clock() >= limite:
                raise FlowFailed(f"nao apareceu rolando a tela: {passo.selector.describe()}")
            self._deslizar(_ROLAGEM[passo.direction or "DOWN"], 600)
            self._assentar()

    def _app(self, passo: Step) -> str:
        app = passo.app_id or self._app_id
        if not app:
            raise FlowFailed("nenhum appId no comando nem no cabecalho do flow")
        return app

    def _r_launchApp(self, passo: Step) -> None:
        app = self._app(passo)
        if passo.stop_first:
            self.device.stop_app(app)
        if passo.clear_state and not self.device.clear_state(app):
            raise FlowFailed(f"nao foi possivel limpar o estado de {app}")
        if not self.device.launch_app(app):
            raise FlowFailed(f"nao foi possivel abrir {app}")
        self._assentar()

    def _r_stopApp(self, passo: Step) -> None:
        if not self.device.stop_app(self._app(passo)):
            raise FlowFailed("nao foi possivel parar o app")

    def _r_clearState(self, passo: Step) -> None:
        if not self.device.clear_state(self._app(passo)):
            raise FlowFailed("nao foi possivel limpar o estado do app")

    def _r_runFlow(self, passo: Step) -> None:
        quando = passo.when or {}
        if "platform" in quando and quando["platform"] != self.device.platform.lower():
            self.log("  pulado: outra plataforma")
            return
        if "visible" in quando and self._procurar(quando["visible"], 0)[0] is None:
            self.log("  pulado: condicao `visible` falsa")
            return
        if "notVisible" in quando and self._procurar(quando["notVisible"], 0)[0] is not None:
            self.log("  pulado: condicao `notVisible` falsa")
            return
        for sub in passo.steps:
            self._passo(sub, "  runFlow")

    def _r_retry(self, passo: Step) -> None:
        for tentativa in range(passo.max_retries + 1):
            try:
                for sub in passo.steps:
                    self._passo(sub, "  retry")
                return
            except FlowFailed as exc:
                if tentativa == passo.max_retries:
                    raise
                self.log(f"  tentativa {tentativa + 1} falhou ({exc}); repetindo")


class FlowThread(threading.Thread):
    """Roda um flow fora da fila RPC. `cancel()` impede o proximo passo de comecar."""

    def __init__(
        self,
        flow: Flow,
        device: FlowDevice,
        on_output: Callable[[str], None],
        on_finished: Callable[[bool, str], None],
    ):
        super().__init__(daemon=True, name="mobaile-maestro-flow")
        self.flow = flow
        self.on_finished = on_finished
        self._cancelado = threading.Event()
        self.runner = FlowRunner(device, log=on_output, cancelled=self._cancelado.is_set)
        self.result: FlowResult | None = None

    def cancel(self) -> None:
        self._cancelado.set()

    def run(self) -> None:
        try:
            self.result = self.runner.run(self.flow)
            sucesso, mensagem = self.result.success, self.result.message
        except Exception as exc:
            # So o tipo: a mensagem poderia repetir um texto digitado.
            sucesso, mensagem = False, f"Erro inesperado no flow: {type(exc).__name__}"
        self.on_finished(sucesso, mensagem)


def _invisivel(e: UIElement) -> UIElement:
    """Copia com area zero: fica na arvore (para parentesco), mas nunca e escolhida."""
    return replace(e, area=0)


# --------------------------------------------------------------- exportacao


_LOCATOR = re.compile(r"^\(AppiumBy\.(\w+),\s*(.+)\)$", re.DOTALL)
_XPATH_ATTR = re.compile(r"@(resource-id|text|content-desc|name|label|value)=(\"[^\"]*\"|'[^']*')")
_REGEX_ESPECIAIS = re.compile(r"([\\.^$*+?()\[\]{}|])")


def _literal_regex(texto: str) -> str:
    """Texto literal para um seletor do Maestro, que le `text`/`id` como regex."""
    return _REGEX_ESPECIAIS.sub(r"\\\1", texto)


def _yaml_str(texto: str) -> str:
    # String JSON e escalar YAML valido entre aspas duplas: nada do texto vira sintaxe.
    return json.dumps(texto, ensure_ascii=False)


def selector_from_step(passo: AutomationStep) -> dict[str, str]:
    """Seletor Maestro equivalente ao localizador que o ranking escolheu na gravacao."""
    m = _LOCATOR.match(passo.locator_value or "")
    if m:
        estrategia = m.group(1)
        try:
            valor = ast.literal_eval(m.group(2))
        except (ValueError, SyntaxError):
            valor = None
        if isinstance(valor, str) and valor:
            if estrategia == "ID":
                return {"id": _literal_regex(valor)}
            if estrategia == "ACCESSIBILITY_ID":
                # No iOS o accessibility id e o `name`, que o Maestro le como `id`.
                if passo.platform == "ios":
                    return {"id": _literal_regex(valor)}
                return {"text": _literal_regex(valor)}
            if estrategia == "XPATH":
                attrs = _XPATH_ATTR.findall(valor)
                if len(attrs) >= 1:
                    nome, literal = attrs[0]
                    conteudo = literal[1:-1]
                    if nome in ("resource-id", "name"):
                        return {"id": _literal_regex(conteudo)}
                    return {"text": _literal_regex(conteudo)}
    x, y = passo.coords or (0, 0)
    return {"point": f"{int(x)},{int(y)}"}


def _seletor_yaml(sel: dict[str, str]) -> str:
    if list(sel) == ["text"]:
        return _yaml_str(sel["text"])
    return "{" + ", ".join(f"{k}: {_yaml_str(v)}" for k, v in sel.items()) + "}"


def export_steps(
    passos: list[AutomationStep],
    *,
    app_id: str | None = None,
    name: str | None = None,
    launch: bool = True,
) -> tuple[str, list[str]]:
    """Escreve os passos gravados como flow do Maestro.

    O texto digitado nao vai para o arquivo: cada passo de digitacao vira
    `inputText: ${VARIAVEL}`, e a lista de variaveis volta junto, para quem
    roda passar os valores em `env` (como o Page Object recebe `texto`).
    """
    app = app_id or next((p.package for p in passos if p.package), None)
    linhas = []
    if app:
        linhas.append(f"appId: {_yaml_str(app)}")
    if name:
        linhas.append(f"name: {_yaml_str(name)}")
    linhas.append("---")
    if launch and app:
        linhas.append("- launchApp")
    variaveis: list[str] = []
    for passo in passos:
        rotulo = passo.element_name or passo.var_name
        linhas.append(f"# passo {passo.step_num}: {rotulo}".replace("\n", " "))
        linhas.append(f"- tapOn: {_seletor_yaml(selector_from_step(passo))}")
        if passo.action_type == "input":
            var = re.sub(r"\W", "_", passo.var_name or f"TEXTO_{passo.step_num}").upper()
            if not _VAR_NAME.fullmatch(var):
                var = f"TEXTO_{passo.step_num}"
            while var in variaveis:
                var += "_"
            variaveis.append(var)
            linhas.append(f"- inputText: ${{{var}}}")
    return "\n".join(linhas) + "\n", variaveis

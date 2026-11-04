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
import logging
import os
import re
import shutil
import tempfile
import threading
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape

from mobaile.config import settings
from mobaile.domain.errors import EngineError, InvalidInputError
from mobaile.domain.models import AutomationStep, LocatorStrategy, UIElement
from mobaile.ports import FlowDevice
from mobaile.security import logs_dir
from mobaile.services.hierarchy import UIHierarchyParser

logger = logging.getLogger(__name__)

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
# A arvore da ultima tela assentada serve a busca seguinte se tiver ate esta
# idade, contada do fim da leitura. Qualquer acao no aparelho a descarta.
SETTLED_CACHE_TTL_S = 2.0
MAX_RETRIES = 3
MAX_FLOW_DEPTH = 8
MAX_FLOW_BYTES = 512 * 1024
# eraseText sem quantidade apaga 50 caracteres, como no Maestro.
DEFAULT_ERASE = 50
# Tela com indicador de carregamento visivel nao conta como assentada: a arvore
# de um spinner fica parada e passaria nas duas leituras iguais. Depois deste
# limite o runner segue e diz isso no log, em vez de falhar.
LOADING_TIMEOUT_S = 5.0
# Alvo que mudou de lugar entre a busca e a tela assentada: leituras a cada
# 100 ms ate a caixa sair igual duas vezes (refreshElementUntilStable do Maestro).
BOUNDS_INTERVAL_S = 0.1
BOUNDS_TIMEOUT_S = 3.0
# Alvo desabilitado e campo sem foco: espera curta e depois age, com aviso.
ENABLED_TIMEOUT_S = 2.0
FOCUS_TIMEOUT_S = 3.0
# Depois do launchApp, quanto esperar o app chegar ao primeiro plano (Android).
LAUNCH_FOREGROUND_TIMEOUT_S = 10.0
# Espera pela ancora de um passo gravado. Opcional: ancora que nao aparece
# (conteudo que mudou) custa este tempo e um aviso, nunca a falha do flow.
ANCHOR_TIMEOUT_S = 5.0
ANCHOR_BREAKER = 2
# Pacotes do sistema que abrem por cima do app logo depois de abri-lo (pedido
# de permissao): o app abriu, e nao ha por que esperar mais.
_POR_CIMA_DO_APP = frozenset({"com.google.android.permissioncontroller", "com.android.permissioncontroller",
                              "com.google.android.packageinstaller", "com.android.packageinstaller"})
# Rastro das telas lidas: quantas telas diferentes por flow e quantas execucoes guardar.
TRACE_MAX_SCREENS = 60
TRACE_KEEP_RUNS = 5

# O que conta como indicador de carregamento: o rotulo que comeca com
# "Carregando", o id de carregamento (`pb_loading`, `shimmer_view`) ou a
# classe de progresso. Classe e id "progress" so valem com formato de spinner,
# quase quadrado: a barra horizontal e progresso determinado e pode ficar na
# tela para sempre (o nivel da bateria nas Configuracoes do Android e uma).
_INDICADOR_CLASSE = re.compile(r"ProgressBar|ActivityIndicator", re.IGNORECASE)
_INDICADOR_ID = re.compile(r"(^|[_.-])(loading|loader|spinner|shimmer|skeleton)([_.-]|$)", re.IGNORECASE)
_PROGRESSO_ID = re.compile(r"(^|[_.-])progress", re.IGNORECASE)
_INDICADOR_ROTULO = re.compile(r"(carregando|aguarde|loading)\b", re.IGNORECASE)

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
    # Fora do `repr`: pode ser senha, e um `logger.debug("%r", passo)` a vazaria.
    text: str | None = field(default=None, repr=False)
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
    # Toque por ponto vindo de uma gravacao: a classe do elemento que estava sob
    # o ponto. O runner so toca quando a mesma classe estiver la (ou no prazo).
    expect_class: str | None = None
    # Espera pela ancora de um passo gravado: a falha nao repete o seletor no
    # log (o texto da tela pode ser dado pessoal) e conta para o disjuntor.
    anchor: bool = False
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
    secrets: tuple[str, ...] = field(default=(), repr=False)

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


# Tudo o que o runner pede ao aparelho e que nao e leitura.
_ACOES_NO_APARELHO = frozenset({"tap", "type_text", "press_key", "swipe", "launch_app", "stop_app", "clear_state"})


class _AparelhoVigiado:
    """O `FlowDevice` do flow, com a ultima arvore lida e um aviso antes de cada acao.

    O aviso vem antes da chamada, e nao depois do sucesso: um toque que estoura
    o prazo pode ter chegado ao aparelho e mudado a tela.
    """

    def __init__(self, device: FlowDevice, antes_da_acao: Callable[[], None],
                 ao_ler: Callable[[str | None], None] = lambda _x: None):
        self._device = device
        self._antes_da_acao = antes_da_acao
        self._ao_ler = ao_ler
        self.ultima_leitura: str | None = None
        self.leituras = 0

    def hierarchy(self) -> str | None:
        self.ultima_leitura = self._device.hierarchy()
        self.leituras += 1
        self._ao_ler(self.ultima_leitura)
        return self.ultima_leitura

    def __getattr__(self, nome: str) -> Any:
        valor = getattr(self._device, nome)
        if nome not in _ACOES_NO_APARELHO:
            return valor

        def acao(*args: Any) -> Any:
            self._antes_da_acao()
            return valor(*args)

        return acao


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
        on_step: Callable[[int, int], None] = lambda _i, _t: None,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
        lookup_timeout_s: float = LOOKUP_TIMEOUT_S,
        optional_lookup_timeout_s: float = OPTIONAL_LOOKUP_TIMEOUT_S,
    ):
        self.device = _AparelhoVigiado(device, self._antes_da_acao, self._ao_ler)
        self._log = log
        self._cancelled = cancelled
        self._on_step = on_step
        self._clock = clock
        self._sleep = sleep
        self.lookup_timeout_s = lookup_timeout_s
        self.optional_lookup_timeout_s = optional_lookup_timeout_s
        self._app_id: str | None = None
        self._segredos: tuple[str, ...] = ()
        self._linhas: list[str] = []
        # Ultima tela assentada (arvore, fim da leitura) e a arvore lida antes da
        # ultima acao, para saber se a tela mudou.
        self._assentada: tuple[str, float] | None = None
        self._antes: str | None = None
        self._casaram = 0
        # Hora da ultima acao no aparelho: os prazos de busca contam dela.
        self._ultima_acao: float | None = None
        # As ultimas telas diferentes lidas no flow, com o segundo em que
        # chegaram: numa falha, interessa a tela do passo que falhou. Vai para
        # disco so pela `salvar_rastro`.
        self.rastro: deque[tuple[float, str]] = deque(maxlen=TRACE_MAX_SCREENS)
        # Ancoras que nao apareceram neste flow: na segunda, as outras deixam
        # de ser esperadas (conteudo dinamico custaria 5 s em todo passo).
        self._ancoras_perdidas = 0
        # Indicadores que ja estouraram `LOADING_TIMEOUT_S`: um ProgressBar que
        # nunca some nao cobra a espera de novo a cada passo.
        self._indicadores_vencidos: set[tuple[str, str, tuple[int, int, int, int]]] = set()
        self._inicio = 0.0
        # O que o passo atual esperou, para a linha "sincronia:" do log.
        self._motivos: list[str] = []

    def _antes_da_acao(self) -> None:
        self._assentada = None
        self._antes = self.device.ultima_leitura
        self._ultima_acao = self._clock()

    def _ao_ler(self, xml: str | None) -> None:
        if xml and (not self.rastro or self.rastro[-1][1] != xml):
            self.rastro.append((self._clock() - self._inicio, xml))

    def _motivo(self, texto: str) -> None:
        if texto not in self._motivos:
            self._motivos.append(texto)

    def _restante(self, prazo_s: float) -> float:
        """Como o Maestro: o prazo de busca conta da ultima acao, nao do fim da espera."""
        if self._ultima_acao is None:
            return prazo_s
        return max(0.0, prazo_s - (self._clock() - self._ultima_acao))

    def _mascarar(self, texto: str) -> str:
        """Troca por `***` o valor de cada `${VAR}` usado, inclusive como sai em `repr`
        e escapado num atributo XML (`&amp;`, `&quot;`), que e como sai no rastro."""
        for segredo in self._segredos:
            if len(segredo) >= 3:
                texto = (texto.replace(segredo, "***").replace(repr(segredo)[1:-1], "***")
                         .replace(escape(segredo, {'"': "&quot;", "'": "&apos;"}), "***")
                         .replace(escape(segredo, {'"': "&quot;"}), "***"))
        return texto

    def log(self, linha: str) -> None:
        linha = self._mascarar(linha)
        self._linhas.append(linha)
        self._log(linha)

    def run(self, flow: Flow) -> FlowResult:
        self._app_id = flow.app_id
        self._segredos = flow.secrets
        self._linhas = []
        self._assentada, self._antes = None, None
        self._ultima_acao = None
        self.rastro.clear()
        self._indicadores_vencidos = set()
        self._ancoras_perdidas = 0
        self._inicio = self._clock()
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
                # So aqui, e nao em `_passo`: onFlowStart, onFlowComplete e os
                # subpassos de runFlow/retry nao contam na barra do front.
                self._checar()
                self._on_step(n, total)
                inicio, leituras = self._clock(), self.device.leituras
                self._motivos = []
                try:
                    self._passo(passo, f"{n}/{total}")
                finally:
                    # Tambem no passo que falhou: e o que mais precisa da linha.
                    self._sincronia(self._clock() - inicio, self.device.leituras - leituras)
                feitos += 1
            falha = None
        except FlowCancelled:
            sucesso, mensagem = False, "Flow cancelado."
        except (FlowFailed, EngineError) as exc:
            sucesso, mensagem = False, str(exc)
        finally:
            # Como no Maestro, onFlowComplete roda mesmo depois de falha.
            if flow.on_complete and not self._cancelled():
                self._ultima_acao = self._clock()
                try:
                    for passo in flow.on_complete:
                        self._passo(passo, "onFlowComplete")
                except (FlowCancelled, FlowFailed, EngineError) as exc:
                    self.log(f"onFlowComplete falhou: {exc}")
        # A mensagem vai crua em `flow.finished` e pode trazer `selector.describe()`,
        # que repete o valor de `${VAR}`: passa pela mesma mascara do log.
        mensagem = self._mascarar(mensagem)
        self.log(("✔ " if sucesso else "✘ ") + mensagem)
        return FlowResult(sucesso, mensagem, feitos, self._mascarar(falha.describe()) if falha else None,
                          list(self._linhas))

    def _sincronia(self, segundos: float, leituras: int) -> None:
        """Quanto o passo esperou o aparelho e por que, numa linha do log."""
        linha = f"  sincronia: {_segundos(segundos)} · {leituras} leitura{'s' if leituras != 1 else ''}"
        self.log(linha + "".join(f" · {m}" for m in self._motivos))

    # --- passos

    def _checar(self) -> None:
        if self._cancelled():
            raise FlowCancelled("Flow cancelado.")

    def _passo(self, passo: Step, posicao: str) -> None:
        self._checar()
        if passo.anchor and self._ancoras_perdidas >= ANCHOR_BREAKER:
            return
        self.log(f"▶ [{posicao}] {passo.describe()}")
        try:
            getattr(self, f"_r_{passo.command}")(passo)
        except FlowFailed as exc:
            if passo.anchor:
                self._ancoras_perdidas += 1
                desliga = self._ancoras_perdidas == ANCHOR_BREAKER
                self.log("  a ancora do passo nao apareceu; seguindo"
                         + ("; as proximas ancoras deste flow nao serao esperadas" if desliga else ""))
                self._ultima_acao = self._clock()
                return
            if passo.optional:
                self.log(f"  opcional, seguindo: {exc}")
                # O tempo gasto procurando o opcional nao sai do prazo do passo seguinte.
                self._ultima_acao = self._clock()
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

    def _procurar(self, sel: Selector, prazo_s: float, *, usar_cache: bool = True) -> tuple[UIElement | None, str]:
        """Le a arvore ate o seletor casar ou o prazo acabar.

        A primeira volta usa a tela que a ultima espera assentou, em vez de
        le-la de novo; achar algo nela nao muda a tela, entao ela segue valendo
        ate a proxima acao. Ela cai se nao casar, se uma leitura nova vier
        diferente ou se passar da idade. Checagem negativa (`assertNotVisible`,
        `when`) passa `usar_cache=False`: decidir que algo sumiu pede a tela de agora.
        """
        limite = self._clock() + prazo_s
        cache = self._assentada if usar_cache else None
        leu = False
        while True:
            self._checar()
            if cache and self._clock() - cache[1] <= SETTLED_CACHE_TTL_S:
                xml = cache[0]
            else:
                cache = None
                xml = self.device.hierarchy() or ""
                if self._assentada and xml != self._assentada[0]:
                    self._assentada = None
            leu = leu or bool(xml)
            elementos = self._elementos(xml) if xml else []
            achados = [i for i in select_elements(sel, elementos) if elementos[i].area > 0]
            if achados:
                self._casaram = len(achados)
                return elementos[achados[0]], xml
            if cache:
                # A tela guardada nao casou: le a de agora antes de decidir,
                # inclusive com prazo 0 (scrollUntilVisible, checagem pontual).
                cache = self._assentada = None
                continue
            if self._clock() >= limite:
                if not leu:
                    raise FlowFailed(f"o aparelho nao devolveu a hierarquia em {prazo_s:.0f} s")
                return None, xml
            self._sleep(POLL_INTERVAL_S)

    def _assentada_agora(self, xml: str) -> str:
        self._assentada = (xml, self._clock())
        return xml

    def _assentar(self, prazo_s: float | None = None, *, uma_leitura: bool = True,
                  inicial: str | None = None) -> str | None:
        """Espera a tela parar e nao ter indicador de carregamento visivel.

        Parar e o waitForAppToSettle do Maestro: duas leituras seguidas iguais.
        So isso deixa passar a tela de carregamento, cuja arvore fica parada
        enquanto o spinner gira (no moto g55, tres leituras iguais de uma tela
        intermediaria). Por isso a tela com indicador visivel volta a ser lida
        ate ele sumir, por ate `LOADING_TIMEOUT_S`.
        """
        # Com prazo declarado (waitToSettleTimeoutMs, waitForAnimationToEnd), ele
        # vale para a espera inteira, indicador incluido.
        fim = self._clock() + prazo_s if prazo_s else None
        limite_indicador = min(LOADING_TIMEOUT_S, prazo_s) if prazo_s else LOADING_TIMEOUT_S
        desde = None
        while True:
            resta = max(SETTLE_INTERVAL_S, fim - self._clock()) if fim is not None else None
            xml = self._parada(resta, uma_leitura=uma_leitura, inicial=inicial)
            inicial = None
            indicador = _indicador(self._elementos(xml), self._indicadores_vencidos) if xml else None
            if indicador is None:
                if desde is not None:
                    self._motivo(f"indicador de carregamento sumiu em {_segundos(self._clock() - desde)}")
                return xml
            if desde is None:
                desde = self._clock()
            elif self._clock() - desde >= limite_indicador or (fim is not None and self._clock() >= fim):
                self._indicadores_vencidos.add(_assinatura(indicador))
                self.log(f"  seguiu sem prontidao: {_nome_do_indicador(indicador)} ainda visivel "
                         f"depois de {_segundos(self._clock() - desde)}; nesta tela ele nao sera mais esperado")
                return xml
            # A tela com indicador nao vale como assentada nem como a de antes da acao.
            self._assentada = None
            self._antes = xml
            self._checar()
            self._sleep(POLL_INTERVAL_S)

    def _parada(self, prazo_s: float | None, *, uma_leitura: bool, inicial: str | None) -> str | None:
        """Duas leituras seguidas iguais, ou a primeira igual a `inicial`.

        Quando o leitor ja espera a tela ficar ociosa (`reads_wait_for_idle`,
        o `uiautomator dump`), uma leitura basta, desde que a tela tenha mudado
        desde antes da acao: tela igual pode ser a antiga, ainda esperando rede.
        """
        anterior = inicial if inicial is not None else self.device.hierarchy()
        if (inicial is None and uma_leitura and prazo_s is None and anterior and anterior != self._antes
                and getattr(self.device, "reads_wait_for_idle", False)):
            return self._assentada_agora(anterior)
        limite = self._clock() + prazo_s if prazo_s else None
        for _ in range(SETTLE_TRIES if limite is None else 10_000):
            self._checar()
            self._sleep(SETTLE_INTERVAL_S)
            atual = self.device.hierarchy()
            if atual == anterior:
                return self._assentada_agora(atual) if atual else atual
            anterior = atual
            if limite is not None and self._clock() >= limite:
                break
        quanto = f"{prazo_s:.0f} s" if limite is not None else f"{SETTLE_TRIES} leituras"
        self.log(f"  seguiu sem prontidao: a tela nao parou em {quanto}")
        return anterior

    def _tela_pronta(self) -> str | None:
        """A tela assentada guardada, se ainda vale; senao, espera assentar."""
        if self._assentada and self._clock() - self._assentada[1] <= SETTLED_CACHE_TTL_S:
            return self._assentada[0]
        return self._assentar()

    def _alvo(self, sel: Selector, optional: bool,
              expect_class: str | None = None) -> tuple[tuple[int, int], str | None]:
        """Onde tocar e a tela de antes do toque, ja assentada."""
        prazo = self.optional_lookup_timeout_s if optional else self.lookup_timeout_s
        if sel.point is not None and sel.text is None and sel.id is None:
            largura, altura = self.device.screen_size()
            ponto = resolve_point(sel.point, largura, altura)
            return ponto, self._conferir_ponto(ponto, expect_class, self._restante(prazo))
        limite = self._clock() + self._restante(prazo)
        while True:
            elemento, xml = self._procurar(sel, max(0.0, limite - self._clock()))
            if elemento is None:
                raise FlowFailed(f"elemento nao encontrado em {prazo:.0f} s: {sel.describe()}")
            mirado = self._mirar(sel, elemento, xml)
            if mirado is not None:
                elemento, xml = mirado
                break
            if self._clock() >= limite:
                raise FlowFailed(f"o elemento sumiu antes do toque: {sel.describe()}")
        elemento, xml = self._esperar_habilitado(sel, elemento, xml)
        if self._casaram > 1:
            self.log(f"  aviso: {self._casaram} elementos casam com {sel.describe()}; tocando o primeiro")
        if sel.point is not None:
            # point junto com seletor e relativo ao elemento, como relativePoint.
            x1, y1, x2, y2 = elemento.bounds
            dx, dy = resolve_point(sel.point, x2 - x1, y2 - y1)
            return (x1 + dx, y1 + dy), xml
        return elemento.center, xml

    def _achar(self, sel: Selector, xml: str) -> tuple[int, list[UIElement]] | None:
        elementos = self._elementos(xml) if xml else []
        achados = [i for i in select_elements(sel, elementos) if elementos[i].area > 0]
        if not achados:
            return None
        self._casaram = len(achados)
        return achados[0], elementos

    def _mirar(self, sel: Selector, elemento: UIElement, xml: str) -> tuple[UIElement, str] | None:
        """Como o `Maestro.tap`: assenta a partir da tela da busca e acha o alvo de novo nela.

        Achado na tela assentada guardada, o alvo ja esta numa tela parada.
        Achado numa leitura avulsa, a tela pode estar no meio da transicao:
        toca-se nos bounds da tela assentada. Se o alvo mudou de lugar, espera a
        caixa sair igual duas vezes. `None` quando ele sumiu da tela assentada.
        """
        if self._assentada and self._assentada[0] == xml:
            return elemento, xml
        if (getattr(self.device, "reads_wait_for_idle", False) and xml != self._antes
                and _indicador(self._elementos(xml), self._indicadores_vencidos) is None):
            # O dump so devolve a arvore depois de 1 s de ocio: a mesma regra do
            # atalho do `_assentar`, sem pagar mais 2 s de leitura por toque.
            self._assentada_agora(xml)
            return elemento, xml
        assentada = self._assentar(inicial=xml) or ""
        achado = self._achar(sel, assentada)
        if achado is None:
            return None
        i, elementos = achado
        if elementos[i].bounds == elemento.bounds:
            return elementos[i], assentada
        self._motivo("o alvo andou; mirei de novo")
        caixa, atual = elementos[i], assentada
        limite = self._clock() + BOUNDS_TIMEOUT_S
        while self._clock() < limite:
            self._checar()
            self._sleep(BOUNDS_INTERVAL_S)
            leitura = self.device.hierarchy() or ""
            achado = self._achar(sel, leitura)
            if achado is None:
                return None
            i, elementos = achado
            if elementos[i].bounds == caixa.bounds:
                return elementos[i], leitura
            caixa, atual = elementos[i], leitura
        return caixa, atual

    def _esperar_habilitado(self, sel: Selector, elemento: UIElement, xml: str) -> tuple[UIElement, str]:
        """Alvo (ou um pai dele) com `enabled=false`: espera um pouco e toca com aviso."""
        achado = self._achar(sel, xml)
        if achado is None or not _desabilitado(*achado):
            return elemento, xml
        limite = self._clock() + ENABLED_TIMEOUT_S
        while self._clock() < limite:
            self._checar()
            self._sleep(POLL_INTERVAL_S)
            leitura = self.device.hierarchy() or ""
            novo = self._achar(sel, leitura)
            if novo is None:
                break
            achado, xml = novo, leitura
            if not _desabilitado(*achado):
                self._motivo("o alvo habilitou")
                return achado[1][achado[0]], xml
        self.log(f"  aviso: o alvo continua desabilitado depois de {ENABLED_TIMEOUT_S:.0f} s; tocando mesmo assim")
        return achado[1][achado[0]], xml

    def _conferir_ponto(self, ponto: tuple[int, int], classe: str | None, prazo_s: float) -> str | None:
        """Tela pronta antes de tocar uma coordenada.

        Com a classe gravada, espera tambem que o elemento sob o ponto seja da
        mesma classe, pela mesma regra da gravacao (`element_at`): e o que
        impede o toque na tela intermediaria, que nem o Maestro confere. No
        prazo, toca o ponto assim mesmo e diz o que havia la.
        """
        xml = self._tela_pronta()
        if classe is None:
            return xml
        inicio = self._clock()
        limite = inicio + prazo_s
        while True:
            sob = UIHierarchyParser.element_at(UIHierarchyParser.parse_xml(xml or ""), *ponto)
            achada = sob.class_name if sob else None
            if achada == classe:
                if self._clock() > inicio:
                    self._motivo(f"a classe gravada apareceu sob o ponto em {_segundos(self._clock() - inicio)}")
                return xml
            if self._clock() >= limite:
                self.log(f"  aviso: sob o ponto {ponto} esta {_curta(achada) or 'nada'}, e a gravacao tinha "
                         f"{_curta(classe)}; tocando o ponto mesmo assim")
                return xml
            self._assentada = None
            self._checar()
            self._sleep(POLL_INTERVAL_S)
            xml = self._assentar()

    def _esperar_foco(self) -> None:
        """Antes de digitar, um campo com foco: o `input text` do adb perde letras sem ele.

        So no Android: a arvore do WDA nao diz qual campo tem foco.
        """
        if self.device.platform != "android":
            return
        inicio = self._clock()
        limite = inicio + FOCUS_TIMEOUT_S
        xml = self._tela_pronta()
        while _focado(self._elementos(xml) if xml else []) is None:
            if self._clock() >= limite:
                self.log(f"  aviso: nenhum campo com foco em {FOCUS_TIMEOUT_S:.0f} s; digitando mesmo assim")
                return
            self._checar()
            self._sleep(POLL_INTERVAL_S)
            xml = self.device.hierarchy()
        if self._clock() > inicio:
            self._motivo(f"o campo ganhou foco em {_segundos(self._clock() - inicio)}")

    def _conferir_digitado(self, texto: str, xml: str | None) -> None:
        """So aviso: senha, mascara de CPF e autocorrecao mudam o que o campo mostra."""
        campo = _focado(self._elementos(xml)) if xml else None
        if campo is None or campo.password or not texto.strip():
            return
        if texto.strip() not in (campo.text or ""):
            self.log("  aviso: o campo com foco nao mostra o texto digitado "
                     "(mascara, autocorrecao ou caractere perdido)")

    def _r_tapOn(self, passo: Step) -> None:
        (x, y), antes = self._alvo(passo.selector, passo.optional, passo.expect_class)
        for tentativa in range(2 if passo.retry_if_no_change else 1):
            if not self.device.tap(x, y):
                raise FlowFailed(f"o toque em ({x}, {y}) foi recusado pelo aparelho")
            depois = self._assentar(passo.timeout_s)
            if antes is None or depois != antes:
                return
            if tentativa == 0 and passo.retry_if_no_change:
                self.log("  a tela nao mudou; tocando de novo")

    def _r_inputText(self, passo: Step) -> None:
        if passo.text is None:
            raise FlowFailed("passo de digitacao sem texto gravado; nada foi digitado")
        self._esperar_foco()
        if not self.device.type_text(passo.text):
            raise FlowFailed("o aparelho recusou a digitacao")
        self._conferir_digitado(passo.text, self._assentar())

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
        padrao = self.optional_lookup_timeout_s if passo.optional else self.lookup_timeout_s
        prazo = passo.timeout_s or padrao
        espera = passo.timeout_s or self._restante(padrao)
        if passo.visible:
            elemento, _ = self._procurar(passo.selector, espera)
            if elemento is None:
                raise FlowFailed(f"nao ficou visivel em {prazo:.0f} s: {passo.selector.describe()}")
            return
        limite = self._clock() + espera
        while True:
            self._checar()
            try:
                elemento, _ = self._procurar(passo.selector, 0, usar_cache=False)
            except FlowFailed:
                # Sem arvore nesta leitura (tela sem ocio, por exemplo): tenta ate o prazo.
                if self._clock() >= limite:
                    raise FlowFailed(f"o aparelho nao devolveu a hierarquia em {prazo:.0f} s") from None
                self._sleep(POLL_INTERVAL_S)
                continue
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
            try:
                elemento, _ = self._procurar(passo.selector, 0)
            except FlowFailed:
                # Uma leitura vazia (o dump sem ocio enquanto a tela anima) nao
                # derruba o passo: tenta de novo ate o prazo, sem rolar as cegas.
                if self._clock() >= limite:
                    raise
                self._motivo("leitura vazia; li de novo")
                self._sleep(POLL_INTERVAL_S)
                continue
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
        self._esperar_primeiro_plano(app)
        # Partida a frio e o pior caso da espera: segue com duas leituras iguais.
        self._assentar(uma_leitura=False)

    def _esperar_primeiro_plano(self, app: str) -> None:
        """O `monkey` volta antes de a activity abrir: espera o app em primeiro plano.

        Sem isso, as duas leituras iguais podiam ser as do launcher ainda na
        tela. So onde o aparelho diz o app em foco (`foreground_app`, o
        `mCurrentFocus` do Android); no prazo, segue com aviso.
        """
        consultar = getattr(self.device, "foreground_app", None)
        if consultar is None:
            return
        inicio = self._clock()
        while True:
            em_foco = consultar()
            if em_foco == app or em_foco in _POR_CIMA_DO_APP:
                if self._clock() > inicio:
                    # No onFlowStart nao ha linha `sincronia:`: vai direto para o log.
                    self.log(f"  o app abriu em {_segundos(self._clock() - inicio)}")
                return
            if self._clock() - inicio >= LAUNCH_FOREGROUND_TIMEOUT_S:
                self.log(f"  aviso: {app} nao ficou em primeiro plano em {LAUNCH_FOREGROUND_TIMEOUT_S:.0f} s "
                         f"(em foco: {em_foco or 'nada'}); seguindo")
                return
            self._checar()
            self._sleep(POLL_INTERVAL_S)

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
        if "visible" in quando and self._procurar(quando["visible"], 0, usar_cache=False)[0] is None:
            self.log("  pulado: condicao `visible` falsa")
            return
        if "notVisible" in quando and self._procurar(quando["notVisible"], 0, usar_cache=False)[0] is not None:
            self.log("  pulado: condicao `notVisible` falsa")
            return
        for sub in passo.steps:
            self._passo(sub, "  runFlow")

    def _r_retry(self, passo: Step) -> None:
        for tentativa in range(passo.max_retries + 1):
            # Cada tentativa tem o prazo inteiro, e nao o que sobrou da anterior.
            self._ultima_acao = self._clock()
            try:
                for sub in passo.steps:
                    self._passo(sub, "  retry")
                return
            except FlowFailed as exc:
                self._assentada = None
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
        on_step: Callable[[int, int], None] = lambda _i, _t: None,
    ):
        super().__init__(daemon=True, name="mobaile-maestro-flow")
        self.flow = flow
        self.on_output = on_output
        self.on_finished = on_finished
        self._cancelado = threading.Event()
        self.runner = FlowRunner(device, log=on_output, cancelled=self._cancelado.is_set, on_step=on_step)
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
        self._guardar_rastro(sucesso)
        self.on_finished(sucesso, mensagem)

    def _guardar_rastro(self, sucesso: bool) -> None:
        """As telas lidas vao para a pasta dos logs quando o flow falha (`MOBAILE_FLOW_TRACE`)."""
        modo = settings.flow_trace
        if not self.runner.rastro or modo == "nunca" or self._cancelado.is_set():
            return
        if sucesso and modo != "sempre":
            return
        try:
            pasta = salvar_rastro(self.runner.rastro, logs_dir() / "flow-rastro", self.runner._mascarar)
        except OSError as exc:
            logger.warning("Rastro do flow nao foi gravado: %s", exc)
            return
        self.on_output(f"Telas lidas no flow guardadas em {pasta}")


def _invisivel(e: UIElement) -> UIElement:
    """Copia com area zero: fica na arvore (para parentesco), mas nunca e escolhida."""
    return replace(e, area=0)


def _indicador(elementos: list[UIElement], ignorar: set | frozenset = frozenset()) -> UIElement | None:
    """O primeiro indicador de carregamento visivel na tela, se houver, fora os de `ignorar`."""
    for e in elementos:
        if e.area <= 0 or (ignorar and _assinatura(e) in ignorar):
            continue
        rid = e.resource_id.rsplit("/", 1)[-1]
        if _INDICADOR_ROTULO.match(e.text or "") or _INDICADOR_ROTULO.match(e.content_desc or ""):
            return e
        if rid and _INDICADOR_ID.search(rid):
            return e
        if (_INDICADOR_CLASSE.search(e.class_name) or (rid and _PROGRESSO_ID.search(rid))) and _quadrado(e):
            return e
    return None


def _assinatura(e: UIElement) -> tuple[str, str, tuple[int, int, int, int]]:
    return e.class_name, e.resource_id, e.bounds


def _quadrado(e: UIElement) -> bool:
    x1, y1, x2, y2 = e.bounds
    largura, altura = x2 - x1, y2 - y1
    return largura > 0 and altura > 0 and max(largura, altura) <= 2 * min(largura, altura)


def _nome_do_indicador(e: UIElement) -> str:
    rid = e.resource_id.rsplit("/", 1)[-1]
    return f"indicador de carregamento ({_curta(e.class_name)}{' ' + rid if rid else ''})"


def _focado(elementos: list[UIElement]) -> UIElement | None:
    return next((e for e in elementos if e.focused and e.area > 0), None)


def _desabilitado(i: int, elementos: list[UIElement]) -> bool:
    return not elementos[i].enabled or any(not elementos[a].enabled for a in _ancestrais(i, elementos))


def _curta(classe: str | None) -> str | None:
    return classe.rsplit(".", 1)[-1] if classe else classe


def _segundos(s: float) -> str:
    return f"{s:.1f} s".replace(".", ",")


_PASTA_DO_RASTRO = re.compile(r"\d{8}-\d{6}-")


def salvar_rastro(rastro: list[tuple[float, str]], base: Path, mascarar: Callable[[str], str] = lambda t: t) -> Path:
    """Grava as telas diferentes que um flow leu, para entender uma falha de sincronia.

    Fica so em disco local, numa pasta 0700 com arquivos 0600, com a mesma
    mascara do log (o valor de cada `${VAR}` vira `***`). Guarda as ultimas
    `TRACE_KEEP_RUNS` execucoes e apaga as mais velhas que ele mesmo criou.
    """
    if base.is_symlink():
        raise OSError(f"Pasta do rastro recusada (symlink): {base}")
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    if base.is_symlink() or not base.is_dir() or base.stat().st_uid != os.getuid():
        raise OSError(f"Pasta do rastro recusada: {base}")
    pasta = Path(tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S-"), dir=base))
    resumo = []
    for n, (segundo, xml) in enumerate(rastro, start=1):
        nome = f"{n:02d}-{segundo:07.2f}s-{len(xml)}B.xml"
        _gravar_privado(pasta / nome, mascarar(xml))
        resumo.append(f"{n:02d}  +{segundo:7.2f} s  {len(xml):>7} B  {nome}")
    _gravar_privado(pasta / "resumo.txt", "\n".join(resumo) + "\n")
    antigas = sorted((p for p in base.iterdir() if p.is_dir() and not p.is_symlink()
                      and _PASTA_DO_RASTRO.match(p.name)), key=lambda p: (p.stat().st_mtime_ns, p.name))
    for velha in antigas[:-TRACE_KEEP_RUNS]:
        if velha != pasta:
            shutil.rmtree(velha, ignore_errors=True)
    return pasta


def _gravar_privado(caminho: Path, texto: str) -> None:
    fd = os.open(caminho, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as arquivo:
        arquivo.write(texto)


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


# Texto do elemento sintetico que a gravacao cria para toque em area sem no.
_SINTETICO = re.compile(r"pos_\d+_\d+")


def selector_from_step(passo: AutomationStep) -> dict[str, str]:
    """Seletor Maestro equivalente ao localizador que o ranking escolheu na gravacao.

    Sem identidade estavel o passo vira o ponto gravado: estrategia `position`,
    xpath so com a classe (`//android.view.View`) e o elemento sintetico do toque
    em area vazia, cujo `pos_x_y` nao existe na tela.
    """
    m = None if passo.strategy == LocatorStrategy.POSITION else _LOCATOR.match(passo.locator_value or "")
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
                if len(attrs) >= 1 and not _SINTETICO.fullmatch(attrs[0][1][1:-1]):
                    nome, literal = attrs[0]
                    conteudo = literal[1:-1]
                    if nome in ("resource-id", "name"):
                        return {"id": _literal_regex(conteudo)}
                    return {"text": _literal_regex(conteudo)}
    x, y = passo.coords or (0, 0)
    return {"point": f"{int(x)},{int(y)}"}


def _ancora_valida(passo: AutomationStep, digitados: set[str]) -> dict[str, str] | None:
    """A ancora do passo como seletor (regex literal), ou `None`.

    Fica de fora a ancora que repete um texto digitado: no YAML ela viraria o
    valor em claro, e na reproducao seria a mesma coisa que o campo mostra.
    """
    if not passo.anchor or len(passo.anchor) != 1:
        return None
    chave, valor = next(iter(passo.anchor.items()))
    if chave not in ("id", "text") or not isinstance(valor, str) or not valor:
        return None
    if any(d in valor for d in digitados):
        return None
    return {chave: _literal_regex(valor)}


_ID_DE_SISTEMA = re.compile(r"(android|com\.android\.systemui):id/")
_EDITAVEL = re.compile(r"EditText|TextField|SearchField|AutoComplete|XCUIElementTypeTextView|Keyboard|"
                       r"XCUIElementTypeKey\b", re.IGNORECASE)


def _rotulo_estavel(texto: str) -> bool:
    """Curto, sem numero (preco, hora, contagem) e sem cara de e-mail."""
    return 2 <= len(texto) <= 40 and not re.search(r"\d|@", texto)


def choose_anchor(elementos: list[UIElement], alvo: UIElement | None) -> dict[str, str] | None:
    """Um elemento da tela da gravacao que diz "esta e a tela do passo" (SYNC-8).

    O mais perto do alvo, fora o proprio alvo, os pais e os filhos (esses ja
    estao no localizador do passo): o conteudo perto do alvo chega com ele, e o
    titulo da toolbar costuma aparecer antes, ainda na tela intermediaria. Vale
    primeiro o resource-id unico na tela; sem ele, o texto unico, curto e sem
    numero (preco, hora e contagem mudam a cada execucao). Nunca campo
    editavel nem senha, que podem ter dado pessoal, nem indicador de
    carregamento, nem elemento de outro pacote (teclado, barra do sistema).
    """
    if alvo is None or not elementos:
        return None
    tela = max(elementos, key=lambda e: e.area).bounds
    ax1, ay1, ax2, ay2 = alvo.bounds
    cx, cy = alvo.center
    ids: dict[str, int] = {}
    rotulos: dict[str, int] = {}
    for e in elementos:
        if e.resource_id:
            ids[e.resource_id] = ids.get(e.resource_id, 0) + 1
        for r in {e.text.strip(), e.content_desc.strip()} - {""}:
            rotulos[r] = rotulos.get(r, 0) + 1
    candidatos = []
    for e in elementos:
        x1, y1, x2, y2 = e.bounds
        if (e.area <= 0 or (x1 <= ax1 and y1 <= ay1 and x2 >= ax2 and y2 >= ay2)
                or (x1 >= ax1 and y1 >= ay1 and x2 <= ax2 and y2 <= ay2)):
            continue
        if not (tela[0] <= e.center[0] <= tela[2] and tela[1] <= e.center[1] <= tela[3]):
            continue
        if e.password or _EDITAVEL.search(e.class_name) or _indicador([e]) is not None:
            continue
        if alvo.package and e.package and e.package != alvo.package:
            continue
        distancia = abs(e.center[0] - cx) + abs(e.center[1] - cy)
        # No iOS o `name` sem identifier e o proprio rotulo: vale a regra do texto.
        id_e_rotulo = e.platform == "ios" and e.resource_id in (e.text, e.content_desc)
        if (e.resource_id and ids[e.resource_id] == 1 and not _ID_DE_SISTEMA.match(e.resource_id)
                and (not id_e_rotulo or _rotulo_estavel(e.resource_id))):
            candidatos.append((0, distancia, {"id": e.resource_id}))
            continue
        rotulo = (e.text or e.content_desc or "").strip()
        if _rotulo_estavel(rotulo) and rotulos.get(rotulo) == 1:
            candidatos.append((1, distancia, {"text": rotulo}))
    return min(candidatos, key=lambda c: (c[0], c[1]))[2] if candidatos else None


def _pacote_dos_passos(passos: list[AutomationStep]) -> str:
    """O pacote da maior parte dos passos: a gravacao pode comecar no launcher."""
    contagem: dict[str, int] = {}
    for p in passos:
        if p.package and p.package not in _POR_CIMA_DO_APP and p.package != "com.android.systemui":
            contagem[p.package] = contagem.get(p.package, 0) + 1
    return max(contagem, key=lambda k: contagem[k]) if contagem else ""


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
    # A gravacao le o campo depois da digitacao: um passo seguinte pode ter o
    # valor no rotulo ou no seletor de texto, inclusive escapado como regex.
    mascarar = _mascara_dos_digitados(passos)
    linhas = []
    if app:
        linhas.append(f"appId: {_yaml_str(app)}")
    if name:
        linhas.append(f"name: {_yaml_str(name)}")
    linhas.append("---")
    if launch and app:
        linhas.append("- launchApp")
    variaveis: list[str] = []
    digitados = set(_formas_do_digitado(passos))
    for passo in passos:
        rotulo = mascarar(passo.element_name or passo.var_name)
        linhas.append(f"# passo {passo.step_num}: {rotulo}".replace("\n", " "))
        # So a ancora por id vai para o arquivo: um texto da tela pode ser dado
        # pessoal (e-mail, nome, o resultado de uma busca), e o motor, nao a
        # pessoa, o escolheu. O texto fica so na reproducao, em memoria.
        ancora = _ancora_valida(passo, digitados)
        if ancora and list(ancora) == ["id"] and mascarar(ancora["id"]) == ancora["id"]:
            linhas += ["- extendedWaitUntil:", f"    visible: {_seletor_yaml(ancora)}",
                       f"    timeout: {int(ANCHOR_TIMEOUT_S * 1000)}", "    optional: true"]
        # A coordenada nunca carrega texto digitado, e mascara-la a quebraria.
        seletor = {k: v if k == "point" else mascarar(v) for k, v in selector_from_step(passo).items()}
        linhas.append(f"- tapOn: {_seletor_yaml(seletor)}")
        if passo.action_type == "input":
            var = re.sub(r"\W", "_", passo.var_name or f"TEXTO_{passo.step_num}").upper()
            if not _VAR_NAME.fullmatch(var):
                var = f"TEXTO_{passo.step_num}"
            while var in variaveis:
                var += "_"
            variaveis.append(var)
            linhas.append(f"- inputText: ${{{var}}}")
    return "\n".join(linhas) + "\n", variaveis


def _formas_do_digitado(passos: list[AutomationStep]) -> list[str]:
    """Cada texto digitado, literal e escapado como regex, do mais longo ao mais curto."""
    formas = {forma for p in passos if p.input_text and len(p.input_text) >= 3
              for forma in (p.input_text, _literal_regex(p.input_text))}
    return sorted(formas, key=len, reverse=True)


def _mascara_dos_digitados(passos: list[AutomationStep]) -> Callable[[str], str]:
    formas = _formas_do_digitado(passos)

    def mascarar(texto: str) -> str:
        for forma in formas:
            texto = texto.replace(forma, "***")
        return texto

    return mascarar


def flow_from_steps(passos: list[AutomationStep], *, abrir_app: bool = False) -> Flow:
    """Os passos gravados como `Flow`, para o `flow.run` reproduzir pelo localizador.

    Sem YAML nem `${VAR}`: o texto digitado vem do passo e so existe em memoria,
    em `secrets` para o log o mascarar. Cada passo gravado vira um item de topo
    (um `runFlow` sem condicao), para `flow.step` contar passo gravado. Passo sem
    localizador estavel toca o ponto gravado e diz isso no rotulo.

    Com `abrir_app`, o flow comeca com o app gravado aberto do zero (`launchApp`
    em `onFlowStart`, fora da contagem de passos): o primeiro passo deixa de
    depender da tela em que o aparelho estava.
    """
    if not passos:
        raise InvalidInputError("Nenhum passo gravado para executar.")
    digitados = set(_formas_do_digitado(passos))
    inicio: tuple[Step, ...] = ()
    if abrir_app:
        app = _pacote_dos_passos(passos)
        if not app:
            raise InvalidInputError("Os passos gravados nao dizem o pacote do app; rode sem abrir o app.")
        inicio = (Step("launchApp", app_id=app, label=f"abrir {app} do zero",
                       source="abrir o app"),)
    itens = []
    for passo in passos:
        seletor = selector_from_step(passo)
        rotulo = passo.element_name or passo.var_name or f"passo {passo.step_num}"
        acao = "digitar em" if passo.action_type == "input" else "tocar em"
        # O toque em area vazia (elemento sintetico `pos_x_y`) nao tem classe na arvore.
        classe = (passo.class_name or None) if "point" in seletor and not _SINTETICO.fullmatch(
            passo.element_name or "") else None
        subpassos = [Step("tapOn", selector=Selector(**seletor), expect_class=classe,
                          source=f"passo {passo.step_num}")]
        ancora = _ancora_valida(passo, digitados)
        if ancora:
            subpassos.insert(0, Step("assertVisible", selector=Selector(**ancora), optional=True, anchor=True,
                                     timeout_s=ANCHOR_TIMEOUT_S, label=f"esperar a tela do passo {passo.step_num}",
                                     source=f"passo {passo.step_num}"))
        if passo.action_type == "input":
            subpassos.append(Step("inputText", text=passo.input_text or None, source=f"passo {passo.step_num}"))
        nota = " (coordenada gravada: sem localizador estavel)" if "point" in seletor else ""
        itens.append(Step("runFlow", steps=tuple(subpassos), label=f"{acao} {rotulo}{nota}",
                          source=f"passo {passo.step_num}"))
    return Flow(app_id=None, name="passos gravados", tags=(), steps=tuple(itens), on_start=inicio,
                secrets=tuple(_formas_do_digitado(passos)))

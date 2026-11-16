"""Tela Início: o que mostrar e com o quê.

A Início deixou de ser o diagnóstico de instalação (que foi para a tela
Ambiente, alimentada por `setup.check`) e virou a tela de boas-vindas do dia
a dia. Quem decide o que ela mostra é este módulo, não o front
(docs/ARQUITETURA.md):

- `state`: `first_run` quando nenhuma plataforma é utilizável nesta máquina,
  `daily` quando pelo menos uma é;
- a contagem do ambiente ("11 de 12 prontos") e cada pendência com o que ela
  bloqueia (área e plataforma), para a Início avisar só onde atrapalha;
- os alvos que dá para usar (simuladores, emuladores e aparelhos), com o que
  cada um consegue fazer e o que o bloqueia;
- a plataforma sugerida na primeira vez;
- os recentes ("Continuar de onde parou") e as novidades da versão instalada.

Os recentes ficam num arquivo local (`recentes.json`), nunca na nuvem. O
motor não confere se cada arquivo ainda existe ao montar a tela: os caminhos
costumam estar em ~/Documents, e conferir faria o macOS pedir acesso à pasta
toda vez que o app abre. Quem tenta reabrir um item que sumiu tira o item da
lista (`home.forget_recent`).

Especificação: docs/design/home/README.md.
"""

from __future__ import annotations

import json
import logging
import os
import re
import sys
import tempfile
import threading
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from mobaile import __version__
from mobaile.services.setup import ANDROID, IOS, MOTOR, PAGE_OBJECTS, SetupService

logger = logging.getLogger(__name__)

FIRST_RUN = "first_run"
DAILY = "daily"

RECENT_KINDS = ("flow", "maestro", "report", "page_object")
RECENT_MAX = 20
RECENT_MAX_AGE_S = 30 * 24 * 3600
MAX_TARGETS = 6
WHATS_NEW_MAX = 4

# O que cada pendência obrigatória bloqueia: (área, plataforma). Área `*` é a
# plataforma inteira. Sem o Appium, o iOS ainda espelha; só toque, hierarquia
# e Page Objects param.
BLOCKS: dict[str, list[tuple[str, str]]] = {
    "adb": [("*", ANDROID)],
    "xcode": [("*", IOS)],
    "appium": [(PAGE_OBJECTS, IOS)],
}

# Alvo do instalador (`tools/setup/instalar-mac.sh`) de cada plataforma na
# Primeira vez. O Xcode vem da App Store; o resto do iOS é o Appium.
PLATFORM_INSTALL = {ANDROID: "android", IOS: "appium"}

# Nome curto de cada componente nos chips da Primeira vez ("adb encontrado").
SHORT_NAMES = {
    "adb": "adb", "emulator": "emulador", "scrcpy": "scrcpy", "uiautomator2": "UiAutomator2",
    "xcode": "Xcode", "appium": "Appium",
}


def data_dir() -> Path:
    """Onde o motor guarda o que é dele. Fora de ~/Documents de propósito."""
    override = os.environ.get("MOBAILE_DATA_DIR")
    if override:
        return Path(override).expanduser()
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Mo baile"
    return Path.home() / ".mobaile"


# ------------------------------------------------------------------ recentes


class RecentStore:
    """Até 20 itens dos últimos 30 dias, o mais recente primeiro.

    Um item é identificado pelo caminho: gravar o mesmo arquivo de novo só o
    traz para o topo, com o subtítulo novo.
    """

    def __init__(self, path: Path | None = None, *, clock: Callable[[], float] = time.time) -> None:
        self._path = path
        self._clock = clock
        self._lock = threading.Lock()

    @property
    def path(self) -> Path:
        return self._path or (data_dir() / "recentes.json")

    def _read(self) -> list[dict[str, Any]]:
        try:
            dados = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return []
        except (OSError, ValueError) as exc:
            logger.info("recentes.json ilegível, recomeçando: %s", exc)
            return []
        itens = dados.get("items") if isinstance(dados, dict) else None
        if not isinstance(itens, list):
            return []
        validos = []
        for item in itens:
            if (isinstance(item, dict) and item.get("kind") in RECENT_KINDS
                    and isinstance(item.get("path"), str) and isinstance(item.get("at"), (int, float))):
                validos.append(item)
        return validos

    def _write(self, itens: list[dict[str, Any]]) -> None:
        pasta = self.path.parent
        pasta.mkdir(parents=True, exist_ok=True)
        # Troca de uma vez: um app fechado no meio da gravação não deixa o
        # arquivo pela metade.
        fd, tmp = tempfile.mkstemp(dir=pasta, prefix=".recentes-", suffix=".json")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as arquivo:
                json.dump({"version": 1, "items": itens}, arquivo, ensure_ascii=False, indent=1)
            os.replace(tmp, self.path)
        except OSError:
            Path(tmp).unlink(missing_ok=True)
            raise

    def _fresh(self, itens: list[dict[str, Any]]) -> list[dict[str, Any]]:
        limite = self._clock() - RECENT_MAX_AGE_S
        return [i for i in itens if i["at"] >= limite][:RECENT_MAX]

    def items(self) -> list[dict[str, Any]]:
        with self._lock:
            return self._fresh(self._read())

    def record(self, kind: str, title: str, subtitle: str, path: str) -> bool:
        """Põe o item no topo. Falha de disco não derruba quem gravou o arquivo."""
        if kind not in RECENT_KINDS:
            raise ValueError(f"tipo de recente desconhecido: {kind}")
        novo = {"kind": kind, "title": title, "subtitle": subtitle, "path": str(path), "at": self._clock()}
        with self._lock:
            itens = [i for i in self._read() if i["path"] != novo["path"]]
            try:
                self._write(self._fresh([novo, *itens]))
            except OSError as exc:
                logger.warning("Não foi possível gravar os recentes: %s", exc)
                return False
        return True

    def forget(self, path: str) -> bool:
        with self._lock:
            itens = self._read()
            restantes = [i for i in itens if i["path"] != path]
            if len(restantes) == len(itens):
                return False
            try:
                self._write(restantes)
            except OSError as exc:
                logger.warning("Não foi possível gravar os recentes: %s", exc)
                return False
        return True


# ----------------------------------------------------------------- novidades

_SECTION = re.compile(r"^## \[(?P<version>[^\]]+)\]", re.M)
_BULLET = re.compile(r"^- (?P<text>.+?)(?=^- |^#|\Z)", re.M | re.S)
_LEAD = re.compile(r"^\*\*(?P<lead>.+?)\*\*")


def changelog_path() -> Path | None:
    """O CHANGELOG ao lado do motor: na raiz do repositório ou em
    `Contents/Resources` do app (o empacotamento copia para lá)."""
    override = os.environ.get("MOBAILE_CHANGELOG")
    if override:
        return Path(override)
    # engine/src/mobaile/services/home.py -> raiz do repositório, ou
    # Resources/engine/src/mobaile/services/home.py -> Resources.
    candidato = Path(__file__).resolve().parents[4] / "CHANGELOG.md"
    return candidato if candidato.is_file() else None


def whats_new(text: str, version: str) -> dict[str, Any] | None:
    """Até quatro tópicos da seção da versão: o título em negrito de cada
    item, ou a primeira frase quando o item não tem título."""
    secoes = list(_SECTION.finditer(text))
    for i, secao in enumerate(secoes):
        if secao.group("version") != version:
            continue
        fim = secoes[i + 1].start() if i + 1 < len(secoes) else len(text)
        corpo = text[secao.end():fim]
        itens = []
        for bullet in _BULLET.finditer(corpo):
            texto = " ".join(bullet.group("text").split())
            lead = _LEAD.match(texto)
            if lead:
                topico = lead.group("lead").rstrip(".")
            else:
                topico = re.split(r"(?<=[.:])\s", texto, maxsplit=1)[0].rstrip(".:")
            topico = topico.replace("`", "")
            if topico and topico not in itens:
                itens.append(topico)
            if len(itens) == WHATS_NEW_MAX:
                break
        return {"version": version, "items": itens} if itens else None
    return None


# ---------------------------------------------------------------------- tela


class HomeService:
    """Monta o `home.summary`. `setup` é uma função porque quem roda o motor
    (e o gerador de fixtures) pode trocar o `SetupService` depois."""

    def __init__(self, setup: Callable[[], SetupService], ios, adb, recents: RecentStore | None = None,
                 *, changelog: Callable[[], Path | None] = changelog_path, version: str = __version__) -> None:
        self._setup = setup
        self.ios = ios
        self.adb = adb
        self.recents = recents or RecentStore()
        self._changelog = changelog
        self._version = version

    # --------------------------------------------------------------- partes

    @staticmethod
    def _components(result: dict[str, Any]) -> dict[str, dict[str, Any]]:
        return {c["id"]: {**c, "group": g["id"]} for g in result["groups"] for c in g["components"]}

    @staticmethod
    def _environment(result: dict[str, Any]) -> dict[str, Any]:
        grupos = {g["id"]: g["components"] for g in result["groups"]}
        obrigatorios = {g: [c["state"] == "ok" for c in itens if c["required"]] for g, itens in grupos.items()}
        contam = [MOTOR, *SetupService.counted_platforms(obrigatorios)]
        itens = [c for g in contam for c in grupos.get(g, []) if c["required"]]
        pendentes = []
        for g in contam:
            for c in grupos.get(g, []):
                if not c["required"] or c["state"] == "ok":
                    continue
                pendentes.append({
                    "id": c["id"],
                    "title": c["label"],
                    "install": c["install"],
                    "link": c["link"],
                    "blocks": [
                        {"area": area, "platform": plataforma, "effect": c["needed_for"] or c["detail"]}
                        for area, plataforma in BLOCKS.get(c["id"], [("*", g)] if g in (ANDROID, IOS) else [])
                    ],
                })
        return {
            "ready": sum(1 for c in itens if c["state"] == "ok"),
            "total": len(itens),
            "pending": pendentes,
        }

    @staticmethod
    def _usable(comps: dict[str, dict[str, Any]], system: str) -> dict[str, bool]:
        """Plataforma utilizável: pelo menos o espelho funciona nela."""
        return {
            ANDROID: comps.get("adb", {}).get("state") == "ok",
            IOS: system == "macos" and comps.get("xcode", {}).get("state") == "ok",
        }

    @staticmethod
    def _capabilities(platform: str, comps: dict[str, dict[str, Any]], usable: dict[str, bool]) -> dict[str, bool]:
        espelho = usable[platform]
        toque = espelho and (platform == ANDROID or comps.get("appium", {}).get("state") == "ok")
        return {"mirror": espelho, "tap": toque, "record": toque}

    @staticmethod
    def _blocked_by(platform: str, environment: dict[str, Any]) -> list[str]:
        return [p["id"] for p in environment["pending"] if any(b["platform"] == platform for b in p["blocks"])]

    def _targets(self, comps, usable, environment, device_id: str | None, system: str) -> list[dict[str, Any]]:
        alvos: list[dict[str, Any]] = []

        def alvo(id_: str, nome: str, plataforma: str, kind: str, running: bool) -> dict[str, Any]:
            return {
                "id": id_, "name": nome, "platform": plataforma, "kind": kind,
                "running": running, "connected": id_ == device_id,
                "capabilities": self._capabilities(plataforma, comps, usable),
                "blocked_by": self._blocked_by(plataforma, environment),
            }

        if usable[ANDROID]:
            try:
                conectados = self.adb.list_devices_typed()
            except Exception as exc:  # adb instável não derruba a tela
                logger.info("Listagem de aparelhos Android falhou: %s", exc)
                conectados = []
            for d in conectados:
                kind = "emulator" if d.id.startswith("emulator-") else "physical"
                alvos.append(alvo(d.id, d.name or d.id, ANDROID, kind, True))
            ligados = any(a["kind"] == "emulator" for a in alvos)
            try:
                avds = self.adb.list_avds()
            except Exception as exc:
                logger.info("Listagem de AVDs falhou: %s", exc)
                avds = []
            # O nome do AVD não aparece no `adb devices`: com um emulador de pé,
            # os AVDs ficam de fora para não oferecer ligar o que já está ligado.
            if not ligados:
                alvos += [alvo(nome, nome.replace("_", " "), ANDROID, "emulator", False) for nome in avds]

        if usable[IOS] and system == "macos":
            try:
                simuladores = self.ios.list_all_simulators()
            except Exception as exc:  # sem Xcode, sem simulador
                logger.info("Listagem de simuladores falhou: %s", exc)
                simuladores = []
            # iPhones primeiro e o runtime mais novo primeiro: é o que se testa.
            simuladores = sorted(
                simuladores,
                key=lambda s: (not s.get("booted"), "iPhone" not in s.get("name", ""), _runtime_key(s.get("runtime"))),
            )
            vistos: set[str] = set()
            for s in simuladores:
                if s["name"] in vistos and not s.get("booted"):
                    continue
                vistos.add(s["name"])
                alvos.append(alvo(s["udid"], s["name"], IOS, "simulator", bool(s.get("booted"))))

        alvos.sort(key=lambda a: (not a["connected"], not a["running"], a["kind"] != "physical"))
        return alvos[:MAX_TARGETS]

    @staticmethod
    def _platforms(comps: dict[str, dict[str, Any]], result: dict[str, Any], usable: dict[str, bool],
                   system: str) -> list[dict[str, Any]]:
        """Os cartões da Primeira vez: o que já foi achado e o que falta."""
        cartoes = []
        for g in result["groups"]:
            if g["id"] not in (ANDROID, IOS):
                continue
            if g["id"] == IOS and system != "macos":
                continue
            prontos = sorted((c for c in g["components"] if c["state"] == "ok"), key=lambda c: not c["required"])
            achados = [f"{SHORT_NAMES.get(c['id'], c['label'])} encontrado" for c in prontos]
            faltam = [c["label"] for c in g["components"] if c["state"] != "ok" and c["required"]]
            cartoes.append({
                "platform": g["id"],
                "ready": usable[g["id"]] and not faltam,
                "found": achados[:2],
                "missing": faltam,
                "install": PLATFORM_INSTALL[g["id"]],
                "link": next((c["link"] for c in g["components"] if c["state"] != "ok" and c["required"]
                              and not c["install"] and c["link"]), None),
            })
        return cartoes

    @staticmethod
    def _suggested(platforms: list[dict[str, Any]], platform_in_use: str | None) -> str | None:
        if not platforms:
            return None
        return min(
            platforms,
            key=lambda p: (len(p["missing"]), p["platform"] != platform_in_use, p["platform"] != ANDROID),
        )["platform"]

    def _whats_new(self) -> dict[str, Any] | None:
        caminho = self._changelog()
        if caminho is None:
            return None
        try:
            return whats_new(caminho.read_text(encoding="utf-8"), self._version)
        except OSError:
            return None

    # ----------------------------------------------------------------- tudo

    def summary(self, platform_in_use: str | None = None, device_id: str | None = None) -> dict[str, Any]:
        setup = self._setup()
        resultado = setup.run(platform_in_use=platform_in_use)
        comps = self._components(resultado)
        usable = self._usable(comps, setup.system)
        ambiente = self._environment(resultado)
        plataformas = self._platforms(comps, resultado, usable, setup.system)
        return {
            "state": DAILY if any(usable.values()) else FIRST_RUN,
            "python": resultado["python"],
            "environment": ambiente,
            "platforms": plataformas,
            "suggested_platform": self._suggested(plataformas, platform_in_use),
            "targets": self._targets(comps, usable, ambiente, device_id, setup.system),
            "recent": self.recents.items(),
            "whats_new": self._whats_new(),
        }


def _runtime_key(runtime: str | None) -> tuple[int, ...]:
    """`iOS 18.2` ordena antes de `iOS 17.5` (negativo: mais novo primeiro)."""
    numeros = re.findall(r"\d+", runtime or "")
    return tuple(-int(n) for n in numeros) or (0,)

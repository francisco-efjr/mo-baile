"""Diagnostico real do ambiente.

Motivo de existir: a tela de estado vazio do front mostrava tres indicadores
por plataforma escritos no codigo, com um visto verde fixo em "Dispositivo
conectado". Ou seja, ela dizia que havia dispositivo conectado justamente
quando nao havia. Um diagnostico que mente e pior que nenhum, porque manda a
pessoa procurar o problema no lugar errado.

Cada checagem aqui executa de verdade e diz o que fazer quando falha.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from mobaile.config import settings
from mobaile.domain.errors import EngineError
from mobaile.domain.models import DaemonState

logger = logging.getLogger(__name__)


@dataclass
class Check:
    """Uma linha do cartao de diagnostico."""

    label: str
    state: DaemonState
    detail: str = ""
    # Identificador da acao que resolve, quando existe uma.
    action: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "state": self.state.value,
            "detail": self.detail,
            "action": self.action,
        }


@dataclass
class PlatformDiagnostics:
    platform: str
    title: str
    checks: list[Check] = field(default_factory=list)

    @property
    def ready(self) -> bool:
        return all(c.state is DaemonState.OK for c in self.checks)

    def to_dict(self) -> dict[str, Any]:
        return {
            "platform": self.platform,
            "title": self.title,
            "ready": self.ready,
            "checks": [c.to_dict() for c in self.checks],
        }


class DiagnosticsService:
    """Checagens de ambiente para as duas plataformas."""

    def __init__(self, adb, ios, appium=None):
        self.adb = adb
        self.ios = ios
        self.appium = appium

    # ------------------------------------------------------------------- iOS

    def ios_diagnostics(self) -> PlatformDiagnostics:
        checks: list[Check] = []

        if not self.ios.is_xcrun_available():
            checks.append(Check(
                "Ferramentas do Xcode", DaemonState.ERROR,
                "xcrun nao encontrado. Instale as Command Line Tools.",
            ))
            # Sem xcrun nada mais pode ser verificado.
            checks.append(Check("Simulador instalado", DaemonState.OFF, "depende do Xcode"))
            checks.append(Check("Simulador ligado", DaemonState.OFF, "depende do Xcode"))
            checks.append(Check("WebDriverAgent", DaemonState.OFF, "depende do simulador"))
            return PlatformDiagnostics("ios", "iOS · WebDriverAgent", checks)

        checks.append(Check("Ferramentas do Xcode", DaemonState.OK, "xcrun disponivel"))

        try:
            simuladores = self.ios.list_all_simulators()
        except EngineError as exc:
            simuladores = []
            logger.warning("Diagnostico iOS: %s", exc)

        if simuladores:
            checks.append(Check(
                "Simulador instalado", DaemonState.OK,
                f"{len(simuladores)} disponiveis",
            ))
        else:
            checks.append(Check(
                "Simulador instalado", DaemonState.ERROR,
                "Nenhum simulador instalado. Baixe um runtime pelo Xcode.",
            ))

        ligados = [s for s in simuladores if s["booted"]]
        if ligados:
            nomes = ", ".join(s["name"] for s in ligados[:2])
            checks.append(Check("Simulador ligado", DaemonState.OK, nomes))
        elif simuladores:
            checks.append(Check(
                "Simulador ligado", DaemonState.WARN,
                "Nenhum em execucao.", action="boot_simulator",
            ))
        else:
            checks.append(Check("Simulador ligado", DaemonState.OFF, "nao ha o que ligar"))

        if self.ios.is_wda_running():
            checks.append(Check("WebDriverAgent", DaemonState.OK, settings.wda_url))
        elif not ligados:
            checks.append(Check("WebDriverAgent", DaemonState.OFF, "ligue um simulador primeiro"))
        elif self.appium is None or not self.appium.is_installed:
            checks.append(Check(
                "WebDriverAgent", DaemonState.WARN,
                "Sem resposta, e o Appium nao foi encontrado. Instale com: npm i -g appium",
            ))
        else:
            # Quem sobe o WDA aqui e o Appium, entao a acao e "pedir ao Appium".
            estado_appium = "servidor no ar" if self.appium.is_running() else "servidor parado"
            checks.append(Check(
                "WebDriverAgent", DaemonState.WARN,
                f"Sem resposta em {settings.wda_url} ({estado_appium}). "
                "O espelho funciona; toque e hierarquia precisam dele.",
                action="start_wda",
            ))

        return PlatformDiagnostics("ios", "iOS · WebDriverAgent", checks)

    # --------------------------------------------------------------- Android

    def android_diagnostics(self) -> PlatformDiagnostics:
        checks: list[Check] = []

        if not self.adb.is_available():
            checks.append(Check(
                "ADB instalado", DaemonState.ERROR,
                "adb nao encontrado. Instale o Android SDK Platform Tools.",
            ))
            checks.append(Check("Dispositivo autorizado", DaemonState.OFF, "depende do adb"))
            checks.append(Check("Emulador disponivel", DaemonState.OFF, "depende do adb"))
            return PlatformDiagnostics("android", "Android · ADB", checks)

        checks.append(Check("ADB instalado", DaemonState.OK, self.adb.adb_path))

        dispositivos = self.adb.list_devices()
        prontos = [d for d in dispositivos if d[1] == "device"]
        pendentes = [d for d in dispositivos if d[1] != "device"]

        if prontos:
            checks.append(Check(
                "Dispositivo autorizado", DaemonState.OK,
                f"{len(prontos)} conectado(s)",
            ))
        elif pendentes:
            estados = ", ".join(sorted({d[1] for d in pendentes}))
            checks.append(Check(
                "Dispositivo autorizado", DaemonState.WARN,
                f"Conectado mas em '{estados}'. Aceite a depuracao USB no aparelho.",
            ))
        else:
            checks.append(Check(
                "Dispositivo autorizado", DaemonState.WARN,
                "Nenhum aparelho conectado.",
            ))

        avds = self.adb.list_avds()
        if prontos:
            checks.append(Check(
                "Emulador disponivel", DaemonState.OK,
                f"{len(avds)} AVD(s)" if avds else "usando aparelho fisico",
            ))
        elif avds:
            checks.append(Check(
                "Emulador disponivel", DaemonState.WARN,
                f"{len(avds)} AVD(s) parados.", action="boot_avd",
            ))
        else:
            checks.append(Check(
                "Emulador disponivel", DaemonState.ERROR,
                "Nenhum AVD criado. Crie um pelo Android Studio.",
            ))

        return PlatformDiagnostics("android", "Android · ADB", checks)

    # ------------------------------------------------------------------ tudo

    def run(self) -> dict[str, Any]:
        return {
            "ios": self.ios_diagnostics().to_dict(),
            "android": self.android_diagnostics().to_dict(),
        }

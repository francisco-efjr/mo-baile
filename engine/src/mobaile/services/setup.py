"""O que está instalado nesta máquina, e o que cada área do app precisa.

O `diagnostics` responde "dá para conectar um aparelho agora?" (simulador
ligado, aparelho autorizado, WDA no ar). Este módulo responde a pergunta de
antes, a de quem acabou de instalar o Mo baile: "o que falta instalar?". É o
que a tela Início mostra.

Regras:

- Só checagem barata: procurar binário, ler `package.json`, `find_spec`. Nada
  de subir Node, Xcode ou Appium para perguntar a versão. A tela Início
  repete a checagem toda vez que o app volta ao primeiro plano.
- Nenhum import pesado: Quartz e pymobiledevice3 são procurados com
  `find_spec`, sem carregar (ver `tests/unit/test_import_tardio.py`).
- O como-instalar mora nos scripts de `tools/setup/`. Aqui cada item diz só
  qual alvo do script resolve (`install`), ou qual página abrir (`link`)
  quando não há script que resolva, como o Xcode.
- A decisão de qual é o próximo passo e de quais áreas funcionam fica aqui, e
  não no front (docs/ARQUITETURA.md: regra em Python e em Swift é defeito).

Rodar sem o app, no Mac ou no Windows (lista o que está pronto e o que falta):

    python3 -m mobaile.services.setup
"""

from __future__ import annotations

import importlib.metadata
import importlib.util
import json
import os
import platform
import shutil
import sys
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from mobaile.domain.models import DaemonState

# Grupos, na ordem em que aparecem.
MOTOR = "motor"
ANDROID = "android"
IOS = "ios"
EXTRAS = "extras"

GROUP_TITLES = {
    MOTOR: "Motor",
    ANDROID: "Android",
    IOS: "iOS",
    EXTRAS: "Extras opcionais",
}

# Áreas do app. Os identificadores são os do contrato; o front traduz para as
# abas dele.
PAGE_OBJECTS = "page_objects"
NETWORK = "network"
ANALYTICS = "analytics"
REPORT = "report"

XCODE_APP_STORE = "macappstore://apps.apple.com/app/id497799835"
ANDROID_STUDIO = "https://developer.android.com/studio"
WINDOWS_USB_DRIVER = "https://developer.android.com/studio/run/win-usb"


def system_name() -> str:
    """`macos`, `windows` ou `linux`."""
    nome = platform.system()
    if nome == "Darwin":
        return "macos"
    if nome == "Windows":
        return "windows"
    return "linux"


@dataclass
class Component:
    """Uma linha do Ambiente na tela Início."""

    id: str
    group: str
    label: str
    state: DaemonState
    detail: str
    # Obrigatório para a plataforma do grupo. Opcional só melhora ou liga um
    # recurso extra, e nunca entra na contagem do que falta.
    required: bool = True
    # Alvo do script de instalação (`tools/setup/instalar-mac.sh <alvo>`).
    install: str | None = None
    # Página a abrir quando não há script que resolva.
    link: str | None = None
    # O que fica sem ele, para a linha dizer por que importa.
    needed_for: str = ""

    @property
    def ok(self) -> bool:
        return self.state is DaemonState.OK

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "label": self.label,
            "state": self.state.value,
            "detail": self.detail,
            "required": self.required,
            "install": self.install,
            "link": self.link,
            "needed_for": self.needed_for,
        }


@dataclass
class Probe:
    """Acesso ao sistema, trocável no teste."""

    which: Callable[[str], str | None] = shutil.which
    is_file: Callable[[str], bool] = os.path.isfile
    realpath: Callable[[str], str] = os.path.realpath
    find_spec: Callable[[str], Any] = importlib.util.find_spec
    version_of: Callable[[str], str | None] = field(default=None)  # type: ignore[assignment]
    read_text: Callable[[str], str | None] = field(default=None)  # type: ignore[assignment]
    home: str = field(default_factory=lambda: os.path.expanduser("~"))
    python_version: str = ".".join(str(n) for n in sys.version_info[:3])
    python_path: str = sys.executable
    environ: dict[str, str] = field(default_factory=lambda: dict(os.environ))

    def __post_init__(self) -> None:
        if self.version_of is None:
            self.version_of = _distribution_version
        if self.read_text is None:
            self.read_text = _read_text


def _distribution_version(nome: str) -> str | None:
    try:
        return importlib.metadata.version(nome)
    except importlib.metadata.PackageNotFoundError:
        return None


def _read_text(caminho: str) -> str | None:
    try:
        return Path(caminho).read_text(encoding="utf-8")
    except OSError:
        return None


def _package_version(probe: Probe, package_json: str) -> str | None:
    texto = probe.read_text(package_json)
    if not texto:
        return None
    try:
        return str(json.loads(texto).get("version") or "") or None
    except (ValueError, AttributeError):
        return None


class SetupService:
    """Checagem de instalação. Os adaptadores dão os caminhos que o motor usa
    de verdade: se o `adb` achado aqui não fosse o mesmo do resto do motor, a
    tela diria "pronto" para um recurso que falha."""

    def __init__(self, adb, appium, scrcpy, *, probe: Probe | None = None, system: str | None = None):
        self.adb = adb
        self.appium = appium
        self.scrcpy = scrcpy
        self.probe = probe or Probe()
        self.system = system or system_name()

    # ----------------------------------------------------------------- motor

    def _motor(self) -> list[Component]:
        versao = self.probe.python_version
        pacotes = []
        for nome in ("Pillow", "requests"):
            v = self.probe.version_of(nome)
            pacotes.append(f"{nome} {v}" if v else nome)
        return [Component(
            "python", MOTOR, f"Python {versao}", DaemonState.OK,
            f"{self.probe.python_path} · {' · '.join(pacotes)}",
            install="python",
        )]

    # --------------------------------------------------------------- Android

    def _android(self) -> list[Component]:
        itens: list[Component] = []
        if self.adb.is_available():
            itens.append(Component(
                "adb", ANDROID, "Android Platform Tools (adb)", DaemonState.OK, self.adb.adb_path,
                install="android",
            ))
        else:
            itens.append(Component(
                "adb", ANDROID, "Android Platform Tools (adb)", DaemonState.ERROR,
                "adb não encontrado. Sem ele, nenhuma área funciona no Android.",
                install="android", needed_for="tudo no Android",
            ))

        if self.adb.emulator_path:
            itens.append(Component(
                "emulator", ANDROID, "Emulador Android", DaemonState.OK, self.adb.emulator_path,
                required=False, link=ANDROID_STUDIO,
            ))
        else:
            itens.append(Component(
                "emulator", ANDROID, "Emulador Android", DaemonState.OFF,
                "Só para quem não usa aparelho físico. Vem com o Android Studio.",
                required=False, link=ANDROID_STUDIO, needed_for="emulador",
            ))

        if self.scrcpy.is_available():
            itens.append(Component(
                "scrcpy", ANDROID, "scrcpy", DaemonState.OK, f"{self.scrcpy.scrcpy_path} · espelho a 60 quadros",
                required=False, install="scrcpy",
            ))
        else:
            itens.append(Component(
                "scrcpy", ANDROID, "scrcpy", DaemonState.OFF,
                "Espelho em janela própria, a 60 quadros por segundo. Sem ele, o espelho do app funciona igual.",
                required=False, install="scrcpy", needed_for="espelho a 60 quadros",
            ))

        # Alguns aparelhos (Motorola, Android 14) devolvem o `uiautomator dump`
        # vazio; aí a hierarquia vem do Appium com o UiAutomator2.
        uia2 = os.path.join(self._appium_home(), "node_modules", "appium-uiautomator2-driver", "package.json")
        versao_uia2 = _package_version(self.probe, uia2)
        if versao_uia2:
            itens.append(Component(
                "uiautomator2", ANDROID, "Driver UiAutomator2 do Appium", DaemonState.OK,
                f"uiautomator2 {versao_uia2}", required=False, install="appium-android",
            ))
        else:
            itens.append(Component(
                "uiautomator2", ANDROID, "Driver UiAutomator2 do Appium", DaemonState.OFF,
                "Reserva para aparelhos em que o adb devolve a hierarquia vazia.",
                required=False, install="appium-android", needed_for="hierarquia em alguns aparelhos",
            ))

        if self.system == "windows":
            itens.append(Component(
                "usb_driver", ANDROID, "Driver USB do aparelho", DaemonState.WARN,
                "O Windows precisa do driver do fabricante (ou do Google USB Driver) para o adb ver o aparelho.",
                required=False, link=WINDOWS_USB_DRIVER, needed_for="aparelho físico por cabo",
            ))
        return itens

    # ------------------------------------------------------------------- iOS

    def _xcode(self) -> Component:
        if not self.probe.which("xcrun"):
            return Component(
                "xcode", IOS, "Xcode", DaemonState.ERROR,
                "Não instalado. O simulador e as ferramentas do iOS vêm com ele.",
                link=XCODE_APP_STORE, needed_for="tudo no iOS",
            )
        # `simctl` só vem com o Xcode completo; as Command Line Tools sozinhas
        # têm o xcrun, mas não o simulador. O Xcode escolhido no `xcode-select`
        # fica no link abaixo (Xcode-beta, Xcode em outra pasta), sem precisar
        # rodar o `xcode-select -p`.
        pastas = [
            self.probe.environ.get("DEVELOPER_DIR") or "",
            self.probe.realpath("/var/db/xcode_select_link"),
            "/Applications/Xcode.app/Contents/Developer",
        ]
        for developer in filter(None, pastas):
            if self.probe.is_file(os.path.join(developer, "usr/bin/simctl")):
                return Component("xcode", IOS, "Xcode", DaemonState.OK, f"simctl em {developer}", link=XCODE_APP_STORE)
        return Component(
            "xcode", IOS, "Xcode", DaemonState.ERROR,
            "Só as Command Line Tools estão instaladas. O simulador precisa do Xcode completo, da App Store.",
            link=XCODE_APP_STORE, needed_for="tudo no iOS",
        )

    def _appium_home(self) -> str:
        return self.probe.environ.get("APPIUM_HOME") or os.path.join(self.probe.home, ".appium")

    def _appium(self) -> Component:
        caminho = self.appium.locate_appium()
        if not caminho:
            node = self.probe.which("node")
            detalhe = "Appium não encontrado." if node else "Appium e Node.js não encontrados."
            return Component(
                "appium", IOS, "Appium com o driver XCUITest", DaemonState.ERROR,
                f"{detalhe} Toque, hierarquia e Page Objects no iOS dependem dele; o espelho funciona sem.",
                install="appium", needed_for="toque e hierarquia no iOS",
            )
        # O `appium` instalado pelo npm é um link para node_modules/appium/index.js
        # (ou para lib/main.js, conforme a versão): sobe até o package.json.
        versao = None
        for pasta in list(Path(self.probe.realpath(caminho)).parents)[:3]:
            versao = _package_version(self.probe, str(pasta / "package.json"))
            if versao:
                break
        driver = os.path.join(self._appium_home(), "node_modules", "appium-xcuitest-driver", "package.json")
        versao_driver = _package_version(self.probe, driver)
        rotulo_appium = f"Appium {versao}" if versao else "Appium"
        if not versao_driver:
            return Component(
                "appium", IOS, "Appium com o driver XCUITest", DaemonState.ERROR,
                f"{rotulo_appium} sem o driver XCUITest. Toque, hierarquia e Page Objects no iOS dependem dele.",
                install="appium", needed_for="toque e hierarquia no iOS",
            )
        # O `appium` é um script `#!/usr/bin/env node`. Aberto pelo Finder, o
        # app herda o PATH mínimo do launchd, e o Node do Homebrew pode não
        # estar nele: o Appium existe mas não sobe.
        if not self.probe.which("node"):
            return Component(
                "appium", IOS, "Appium com o driver XCUITest", DaemonState.WARN,
                f"{rotulo_appium} · xcuitest {versao_driver}, mas o Node.js não está no PATH do motor. "
                "Sem ele o Appium não sobe.",
                install="appium", needed_for="toque e hierarquia no iOS",
            )
        return Component(
            "appium", IOS, "Appium com o driver XCUITest", DaemonState.OK,
            f"{rotulo_appium} · xcuitest {versao_driver}", install="appium",
        )

    def _ios(self) -> list[Component]:
        if self.system != "macos":
            return [Component(
                "xcode", IOS, "iOS", DaemonState.OFF,
                "O iOS precisa de um Mac: o simulador e o WebDriverAgent só rodam no macOS.",
                required=False,
            )]
        return [self._xcode(), self._appium()]

    # ---------------------------------------------------------------- extras

    def _extras(self) -> list[Component]:
        itens: list[Component] = []
        if self.system == "macos":
            if self.probe.find_spec("pymobiledevice3") is not None:
                itens.append(Component(
                    "pymobiledevice3", EXTRAS, "pymobiledevice3", DaemonState.OK,
                    "Analytics e Rede de iPhone físico por cabo.", required=False, install="ios-device",
                ))
            else:
                itens.append(Component(
                    "pymobiledevice3", EXTRAS, "pymobiledevice3", DaemonState.OFF,
                    "Só para Analytics e Rede de iPhone físico por cabo. O simulador não precisa.",
                    required=False, install="ios-device", needed_for="iPhone físico por cabo",
                ))
            if self.probe.find_spec("Quartz") is not None:
                itens.append(Component(
                    "quartz", EXTRAS, "Escuta passiva de toques", DaemonState.OK,
                    "pyobjc-framework-Quartz instalado.", required=False, install="escuta",
                ))
            else:
                itens.append(Component(
                    "quartz", EXTRAS, "Escuta passiva de toques", DaemonState.OFF,
                    "Grava passos a partir do que você faz no simulador, sem clicar no espelho.",
                    required=False, install="escuta", needed_for="escuta passiva",
                ))
            if self.probe.which("swiftc") or self.probe.which("swift"):
                itens.append(Component(
                    "swift", EXTRAS, "Leitura de prints no Relatório", DaemonState.OK,
                    "Swift das Command Line Tools: o texto dos cards sai do print, sem rede.",
                    required=False, link=XCODE_APP_STORE,
                ))
            else:
                itens.append(Component(
                    "swift", EXTRAS, "Leitura de prints no Relatório", DaemonState.OFF,
                    "Importar cards a partir de prints precisa do Swift (Command Line Tools ou Xcode).",
                    required=False, link=XCODE_APP_STORE, needed_for="importar cards de prints",
                ))
        return itens

    # ----------------------------------------------------------------- áreas

    @staticmethod
    def _features(por_id: dict[str, Component], system: str) -> list[dict[str, Any]]:
        def estado(ok: bool, detalhe_ok: str, detalhe_falta: str, parcial: bool = False):
            if ok:
                return DaemonState.OK, detalhe_ok
            return (DaemonState.WARN if parcial else DaemonState.ERROR), detalhe_falta

        adb = por_id["adb"].ok
        xcode = por_id["xcode"].ok and system == "macos"
        appium = "appium" in por_id and por_id["appium"].ok
        # O proxy só configura Android. No iOS, a Rede vem do app em debug
        # num iPhone físico por cabo, lido pelo pymobiledevice3 (ADR 0004).
        cabo = "pymobiledevice3" in por_id and por_id["pymobiledevice3"].ok

        def plataformas(android: tuple, ios: tuple | None) -> list[dict[str, str]]:
            linhas = [{"platform": "android", "state": android[0].value, "detail": android[1]}]
            if ios is None:
                linhas.insert(0, {"platform": "ios", "state": DaemonState.OFF.value, "detail": "precisa de um Mac"})
            else:
                linhas.insert(0, {"platform": "ios", "state": ios[0].value, "detail": ios[1]})
            return linhas

        sem_mac = system != "macos"
        if xcode and appium:
            ios_po = (DaemonState.OK, "pronto")
        elif xcode:
            ios_po = (DaemonState.WARN, "só o espelho; falta o Appium")
        else:
            ios_po = (DaemonState.ERROR, "falta o Xcode")

        android_falta = "falta o adb"
        return [
            {
                "id": PAGE_OBJECTS,
                "platforms": plataformas(
                    estado(adb, "pronto", android_falta),
                    None if sem_mac else ios_po,
                ),
            },
            {
                "id": NETWORK,
                "platforms": plataformas(
                    estado(adb, "pronto", android_falta),
                    None if sem_mac else estado(
                        cabo, "iPhone físico por cabo", "só iPhone físico; falta o pymobiledevice3", parcial=True,
                    ),
                ),
            },
            {
                "id": ANALYTICS,
                "platforms": plataformas(
                    estado(adb, "pronto", android_falta),
                    None if sem_mac else estado(xcode, "simulador" + (" e iPhone físico" if cabo else ""), "falta o Xcode"),
                ),
            },
            {
                # Lê arquivos: spec e log exportado. Não depende de aparelho.
                "id": REPORT,
                "platforms": [{"platform": "any", "state": DaemonState.OK.value, "detail": "funciona sem aparelho"}],
            },
        ]

    # ------------------------------------------------------- próximo passo

    @staticmethod
    def _pending(grupos: dict[str, list[Component]]) -> list[Component]:
        """Obrigatórios que faltam, na ordem em que vale instalar.

        Uma plataforma que a pessoa não começou a montar (nenhum obrigatório
        dela instalado) não conta enquanto a outra estiver em uso: quem só
        testa Android não precisa ver o Appium como pendência para sempre.
        Numa máquina zerada as duas contam.
        """
        def faltam(grupo: str) -> list[Component]:
            return [c for c in grupos.get(grupo, []) if c.required and not c.ok]

        def em_uso(grupo: str) -> bool:
            return any(c.required and c.ok for c in grupos.get(grupo, []))

        plataformas = [g for g in (ANDROID, IOS) if any(c.required for c in grupos.get(g, []))]
        usadas = [g for g in plataformas if em_uso(g)]
        contam = usadas or plataformas
        pendentes = faltam(MOTOR)
        for grupo in contam:
            pendentes += faltam(grupo)
        return pendentes

    # ----------------------------------------------------------------- tudo

    def run(self, platform_in_use: str | None = None) -> dict[str, Any]:
        grupos = {
            MOTOR: self._motor(),
            ANDROID: self._android(),
            IOS: self._ios(),
            EXTRAS: self._extras(),
        }
        por_id = {c.id: c for itens in grupos.values() for c in itens}
        pendentes = self._pending(grupos)
        # A plataforma em uso na sessão vem primeiro no próximo passo.
        if platform_in_use in (ANDROID, IOS):
            pendentes.sort(key=lambda c: 0 if c.group in (MOTOR, platform_in_use) else 1)

        proximo = None
        if pendentes:
            c = pendentes[0]
            proximo = {"component": c.id, "label": c.label, "detail": c.detail,
                       "install": c.install, "link": c.link}

        return {
            "system": self.system,
            "python": {"version": self.probe.python_version, "path": self.probe.python_path},
            "groups": [
                {"id": g, "title": GROUP_TITLES[g], "components": [c.to_dict() for c in itens]}
                for g, itens in grupos.items() if itens
            ],
            "features": self._features(por_id, self.system),
            "pending": len(pendentes),
            "next_step": proximo,
        }


SYMBOLS = {"ok": "[ok]", "warn": "[!!]", "error": "[--]", "off": "[  ]", "busy": "[..]"}


def format_report(resultado: dict[str, Any]) -> str:
    """Texto para o terminal: o mesmo conteúdo da tela Início."""
    linhas = [f"Mo baile · ambiente ({resultado['system']})", ""]
    for grupo in resultado["groups"]:
        linhas.append(grupo["title"])
        for c in grupo["components"]:
            opcional = "" if c["required"] else " (opcional)"
            linhas.append(f"  {SYMBOLS.get(c['state'], '[??]')} {c['label']}{opcional}: {c['detail']}")
        linhas.append("")
    proximo = resultado["next_step"]
    if proximo:
        linhas.append(f"Próximo passo: {proximo['label']}.")
        if proximo["install"]:
            script = "instalar-windows.ps1" if resultado["system"] == "windows" else "instalar-mac.sh"
            linhas.append(f"  Rode o script tools/setup/{script} com o alvo '{proximo['install']}'.")
        elif proximo["link"]:
            linhas.append(f"  Veja {proximo['link']}")
    else:
        linhas.append("Tudo o que é obrigatório está instalado.")
    return "\n".join(linhas)


def main(argv: list[str] | None = None) -> int:
    from mobaile.adapters.adb import ADBBridge
    from mobaile.adapters.appium import AppiumBridge
    from mobaile.adapters.scrcpy import ScrcpyManager

    argumentos = argv if argv is not None else sys.argv[1:]
    resultado = SetupService(ADBBridge(), AppiumBridge(), ScrcpyManager()).run()
    if "--json" in argumentos:
        print(json.dumps(resultado, ensure_ascii=False, indent=2))
    else:
        print(format_report(resultado))
    return 1 if resultado["pending"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

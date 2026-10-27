"""`FlowDevice` sobre os adapters que o motor ja tem: adb no Android, WDA e simctl no iOS.

O runner de flow declarativo (`services/maestro_flow.py`) so conhece este
contrato. Tudo aqui e local: adb fala com o servidor do adb em localhost, o WDA
fica no `settings.wda_url` e o simctl e processo da propria maquina.
"""

from __future__ import annotations

import logging
import re
import subprocess
from collections.abc import Callable

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.domain.errors import InvalidInputError, ToolNotFoundError
from mobaile.security import validate_coordinate, validate_device_id, validate_keycode

logger = logging.getLogger(__name__)

# Pacote Android (`com.app.x`) ou bundle id iOS (`com.app.X-beta`). Vai para o
# shell do aparelho como argumento solto, entao so passa o que tem esse formato.
_APP_ID = re.compile(r"[A-Za-z][A-Za-z0-9_\-]*(\.[A-Za-z0-9_\-]+)+")

# Nomes de tecla do Maestro -> keycode Android.
ANDROID_KEYS = {
    "enter": 66, "back": 4, "home": 3, "backspace": 67, "delete": 67, "tab": 61,
    "escape": 111, "volume up": 24, "volume down": 25, "lock": 26, "power": 26,
    "remote dpad up": 19, "remote dpad down": 20, "remote dpad left": 21, "remote dpad right": 22,
    "remote dpad center": 23,
}


def validate_app_id(app_id: str) -> str:
    if not isinstance(app_id, str) or len(app_id) > 255 or not _APP_ID.fullmatch(app_id):
        raise InvalidInputError(f"appId invalido: {app_id!r}")
    return app_id


class AndroidFlowDevice:
    platform = "android"

    def __init__(
        self,
        adb: ADBBridge,
        serial: str,
        hierarchy: Callable[[], str | None] | None = None,
        backend: Callable[[], str | None] | None = None,
    ):
        self.adb = adb
        self.serial = validate_device_id(serial)
        # O servidor passa o leitor dele, que le pela sessao do Appium quando ha
        # uma aberta, e `backend`, que diz por onde saiu a ultima leitura.
        self._hierarchy = hierarchy or (lambda: adb.get_ui_hierarchy(self.serial))
        self._backend = backend or ((lambda: "adb") if hierarchy is None else (lambda: None))
        self._tamanho: tuple[int, int] | None = None

    @property
    def reads_wait_for_idle(self) -> bool:
        """A ultima leitura saiu do `uiautomator dump`, que so despeja a arvore
        depois de 1 s sem eventos de acessibilidade: ela ja e uma tela assentada."""
        return self._backend() == "adb"

    def _shell(self, *args: str, timeout: int = 10) -> bool:
        try:
            ret, _, err = self.adb._run_cmd(self.adb._device_args(self.serial, "shell", *args), timeout=timeout)
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.warning("adb shell %s falhou: %s", args[0], exc)
            return False
        if ret != 0:
            logger.warning("adb shell %s saiu com %s: %s", args[0], ret, err.decode(errors="ignore").strip())
        return ret == 0

    def hierarchy(self) -> str | None:
        return self._hierarchy()

    def screen_size(self) -> tuple[int, int]:
        if self._tamanho is None:
            self._tamanho = self.adb.get_screen_size(self.serial)
        return self._tamanho

    def tap(self, x: int, y: int) -> bool:
        return self.adb.tap(self.serial, x, y)

    def type_text(self, text: str) -> bool:
        return self.adb.type_text(self.serial, text)

    def press_key(self, key: str) -> bool:
        codigo = ANDROID_KEYS.get(key.strip().lower())
        return codigo is not None and self.adb.press_key(self.serial, validate_keycode(codigo))

    def swipe(self, x1: int, y1: int, x2: int, y2: int, duration_ms: int) -> bool:
        pontos = [str(validate_coordinate(v, "swipe")) for v in (x1, y1, x2, y2)]
        return self._shell("input", "swipe", *pontos, str(max(50, min(int(duration_ms), 10_000))))

    def launch_app(self, app_id: str) -> bool:
        # `monkey` com a categoria LAUNCHER abre a activity principal sem
        # precisar saber o nome dela, como o `launchApp` do Maestro faz.
        return self._shell("monkey", "-p", validate_app_id(app_id), "-c",
                           "android.intent.category.LAUNCHER", "1", timeout=15)

    def stop_app(self, app_id: str) -> bool:
        return self._shell("am", "force-stop", validate_app_id(app_id))

    def clear_state(self, app_id: str) -> bool:
        return self._shell("pm", "clear", validate_app_id(app_id), timeout=20)


class IOSFlowDevice:
    """Simulador iOS: arvore e toques pelo WDA, apps pelo simctl."""

    platform = "ios"

    def __init__(self, ios: IOSBridge, udid: str):
        self.ios = ios
        self.udid = validate_device_id(udid)

    def _wda(self, caminho: str, corpo: dict) -> bool:
        import requests

        sid = self.ios._ensure_session()
        if not sid:
            return False
        try:
            res = requests.post(f"{self.ios.wda_url}/session/{sid}{caminho}", json=corpo, timeout=10)
        except requests.RequestException as exc:
            logger.warning("WDA %s falhou: %s", caminho, exc)
            return False
        if res.status_code != 200:
            return False
        try:
            valor = res.json().get("value")
        except ValueError:
            return True
        # O WDA devolve 200 com o erro dentro de `value`.
        return not (isinstance(valor, dict) and valor.get("error"))

    def _simctl(self, *args: str) -> bool:
        try:
            proc = subprocess.run(["xcrun", "simctl", *args], capture_output=True, timeout=30, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            logger.warning("simctl %s falhou: %s", args[0], exc)
            return False
        return proc.returncode == 0

    def hierarchy(self) -> str | None:
        return self.ios.get_ui_hierarchy()

    def screen_size(self) -> tuple[int, int]:
        import requests

        try:
            res = requests.get(f"{self.ios.wda_url}/window/size", timeout=4)
            valor = res.json().get("value") or {}
            return int(valor.get("width", 0)), int(valor.get("height", 0))
        except (requests.RequestException, ValueError, AttributeError):
            return (0, 0)

    def tap(self, x: int, y: int) -> bool:
        return self.ios.tap(x, y)

    def type_text(self, text: str) -> bool:
        return self._wda("/wda/keys", {"value": list(text)})

    def press_key(self, key: str) -> bool:
        nome = key.strip().lower()
        if nome == "home":
            return self._wda("/wda/pressButton", {"name": "home"})
        teclas = {"enter": "\n", "backspace": "\b", "delete": "\b", "tab": "\t"}
        if nome in teclas:
            return self._wda("/wda/keys", {"value": [teclas[nome]]})
        # iOS nao tem `back` nem `escape` de sistema; o Maestro tambem recusa.
        return False

    def swipe(self, x1: int, y1: int, x2: int, y2: int, duration_ms: int) -> bool:
        return self._wda("/wda/dragfromtoforduration", {
            "fromX": x1, "fromY": y1, "toX": x2, "toY": y2, "duration": max(0.05, duration_ms / 1000),
        })

    def launch_app(self, app_id: str) -> bool:
        return self._simctl("launch", self.udid, validate_app_id(app_id))

    def stop_app(self, app_id: str) -> bool:
        return self._simctl("terminate", self.udid, validate_app_id(app_id))

    def clear_state(self, app_id: str) -> bool:
        # O simctl nao limpa dados de um app instalado; reinstalar fica com quem testa.
        logger.warning("clearState no iOS nao e suportado pelo simctl (%s).", app_id)
        return False

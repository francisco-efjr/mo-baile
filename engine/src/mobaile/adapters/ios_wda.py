import io
import json
import logging
import re
import shutil
import subprocess

import requests
from PIL import Image

from mobaile.config import settings
from mobaile.domain.errors import InvalidInputError, ToolNotFoundError
from mobaile.security import validate_device_id

logger = logging.getLogger(__name__)


class IOSBridge:
    def __init__(self, wda_url: str | None = None):
        self.wda_url = wda_url or settings.wda_url
        self.session_id: str | None = None
        # Sem I/O no construtor. A versao anterior abria sessao aqui, o que
        # travava a criacao do objeto por ate 6 s quando o WDA_URL apontava para
        # um host que engole pacotes. A sessao passa a ser criada no primeiro uso.

    def _ensure_session(self) -> str | None:
        if self.session_id:
            return self.session_id

        try:
            res = requests.get(f"{self.wda_url}/status", timeout=2)
            if res.status_code == 200:
                sid = res.json().get("sessionId")
                if sid:
                    self.session_id = sid
                    return self.session_id
        except Exception:
            pass

        try:
            res = requests.post(f"{self.wda_url}/session", json={"capabilities": {}}, timeout=4)
            if res.status_code == 200:
                data = res.json()
                sid = data.get("sessionId") or (data.get("value") or {}).get("sessionId")
                if sid:
                    self.session_id = sid
                    return self.session_id
        except Exception:
            pass

        return None

    def list_booted_simulators(self) -> list[tuple[str, str]]:
        try:
            cmd = ["xcrun", "simctl", "list", "devices"]
            proc = subprocess.run(cmd, capture_output=True, timeout=5)
            if proc.returncode != 0:
                return []

            output = proc.stdout.decode("utf-8", errors="ignore")
            booted_devices: list[tuple[str, str]] = []
            pattern = re.compile(r"^\s*(.*?)\s*\(([A-F0-9\-]+)\)\s*\(Booted\)", re.IGNORECASE)

            for line in output.splitlines():
                match = pattern.match(line)
                if match:
                    booted_devices.append((match.group(2).strip(), match.group(1).strip()))

            return booted_devices
        except Exception:
            return []

    def take_screenshot(self, device_udid: str = "booted") -> Image.Image | None:
        try:
            cmd = ["xcrun", "simctl", "io", device_udid, "screenshot", "-"]
            proc = subprocess.run(cmd, capture_output=True, timeout=6)
            if proc.returncode == 0 and proc.stdout:
                img = Image.open(io.BytesIO(proc.stdout)).convert("RGB")
                img.load()
                return img
        except Exception:
            pass
        return None

    def get_ui_hierarchy(self) -> str | None:
        try:
            res = requests.get(f"{self.wda_url}/source", timeout=6)
            if res.status_code == 200:
                data = res.json()
                xml_val = data.get("value")
                if isinstance(xml_val, str) and "XCUIElementType" in xml_val:
                    return xml_val
        except Exception:
            pass
        return None

    def tap(self, x: int, y: int) -> bool:
        sid = self._ensure_session()
        if not sid:
            return False

        try:
            res = requests.post(
                f"{self.wda_url}/session/{sid}/wda/tap",
                json={"x": x, "y": y},
                timeout=4,
            )
            if res.status_code == 200:
                return True
        except Exception:
            pass

        try:
            action_payload = {
                "actions": [
                    {
                        "type": "pointer",
                        "id": "finger1",
                        "parameters": {"pointerType": "touch"},
                        "actions": [
                            {"type": "pointerMove", "duration": 0, "x": x, "y": y},
                            {"type": "pointerDown", "button": 0},
                            {"type": "pause", "duration": 60},
                            {"type": "pointerUp", "button": 0},
                        ],
                    }
                ]
            }
            res = requests.post(
                f"{self.wda_url}/session/{sid}/actions",
                json=action_payload,
                timeout=4,
            )
            return res.status_code == 200
        except Exception:
            self.session_id = None
            return False

    # ------------------------------------------------------- ciclo do simulador

    def list_all_simulators(self) -> list[dict]:
        """Todos os simuladores instalados, ligados ou nao.

        `list_booted_simulators` so enxerga os que ja estao de pe, o que basta
        para espelhar mas nao para oferecer "abrir simulador" na interface.
        """
        try:
            proc = subprocess.run(
                ["xcrun", "simctl", "list", "devices", "--json"],
                capture_output=True, timeout=15, check=False,
            )
            if proc.returncode != 0:
                logger.warning("simctl list falhou: %s", proc.stderr.decode(errors="ignore")[:200])
                return []
            data = json.loads(proc.stdout.decode("utf-8", errors="ignore"))
        except FileNotFoundError:
            raise ToolNotFoundError("xcrun nao encontrado. Instale as Command Line Tools do Xcode.") from None
        except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
            logger.warning("Nao foi possivel listar simuladores: %s", exc)
            return []

        simuladores: list[dict] = []
        for runtime, devices in (data.get("devices") or {}).items():
            # "com.apple.CoreSimulator.SimRuntime.iOS-18-0" -> "iOS 18.0"
            rotulo = runtime.rsplit(".", 1)[-1].replace("iOS-", "iOS ").replace("-", ".")
            for device in devices:
                if not device.get("isAvailable", True):
                    continue
                simuladores.append({
                    "udid": device.get("udid", ""),
                    "name": device.get("name", ""),
                    "state": device.get("state", "Shutdown"),
                    "runtime": rotulo,
                    "booted": device.get("state") == "Booted",
                })
        # Ligados primeiro, depois por nome: e a ordem util num menu.
        simuladores.sort(key=lambda s: (not s["booted"], s["name"]))
        return simuladores

    def boot_simulator(self, udid: str, open_app: bool = True) -> tuple[bool, str]:
        """Liga o simulador e traz a janela do Simulator para a frente.

        Devolve `(ok, mensagem)`. Simulador ja ligado conta como sucesso: o
        usuario pediu "abre isso", e ele esta aberto.
        """
        udid = validate_device_id(udid)
        try:
            proc = subprocess.run(
                ["xcrun", "simctl", "boot", udid],
                capture_output=True, timeout=90, check=False,
            )
            erro = proc.stderr.decode("utf-8", errors="ignore").strip()
            ja_ligado = "current state: Booted" in erro or "Booted" in erro

            if proc.returncode != 0 and not ja_ligado:
                return False, erro or "simctl boot falhou sem mensagem."

            if open_app:
                # `simctl boot` sobe o runtime, mas nao mostra a janela.
                subprocess.run(["open", "-a", "Simulator"], capture_output=True, timeout=20, check=False)

            return True, "Simulador ja estava ligado." if ja_ligado else "Simulador iniciado."
        except FileNotFoundError:
            raise ToolNotFoundError("xcrun nao encontrado. Instale as Command Line Tools do Xcode.") from None
        except subprocess.TimeoutExpired:
            return False, "O simulador demorou demais para iniciar."
        except OSError as exc:
            return False, str(exc)

    def shutdown_simulator(self, udid: str) -> bool:
        try:
            proc = subprocess.run(
                ["xcrun", "simctl", "shutdown", validate_device_id(udid)],
                capture_output=True, timeout=30, check=False,
            )
            return proc.returncode == 0
        except (OSError, subprocess.TimeoutExpired, InvalidInputError) as exc:
            logger.warning("Nao foi possivel desligar o simulador: %s", exc)
            return False

    def is_wda_running(self) -> bool:
        """Checagem barata de disponibilidade do WebDriverAgent."""
        try:
            return requests.get(f"{self.wda_url}/status", timeout=2).status_code == 200
        except requests.RequestException:
            return False

    @staticmethod
    def is_xcrun_available() -> bool:
        return shutil.which("xcrun") is not None

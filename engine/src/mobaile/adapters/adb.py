"""Adapter do Android Debug Bridge.

Toda entrada externa (serial, coordenada, texto, keycode) passa por
`mobaile.security` antes de virar processo. Falhas viram log e valor de retorno
neutro para o chamador — o `except Exception: pass` mudo foi substituído por
registro em log, porque bug silencioso em automação custa mais caro que ruído.
"""

from __future__ import annotations

import io
import logging
import os
import re
import shutil
import subprocess
import threading

from PIL import Image

from mobaile.config import settings
from mobaile.domain.errors import InvalidInputError, ToolNotFoundError
from mobaile.domain.models import Device, Platform
from mobaile.security import (
    build_adb_input_text_args,
    validate_coordinate,
    validate_device_id,
    validate_keycode,
    validate_port,
)

logger = logging.getLogger(__name__)

# Instrumentacao ativa no `dumpsys activity processes`, como
# "ActiveInstrumentation{8de623b {dev.mobile.maestro.test/androidx.test.runner...}".
_INSTRUMENTACAO_ATIVA = re.compile(r"ActiveInstrumentation\{\S+ \{([A-Za-z0-9_.]+)/")

# O servidor UiAutomator2 do Appium tambem segura o UiAutomation, mas por ele o
# motor le a tela: nao e bloqueio.
_INSTRUMENTACAO_DO_APPIUM = "io.appium.uiautomator2.server"

# Screenshot de aparelho em alta resolução passa de 8 MB; o teto evita que um
# dispositivo com problema encha a memória do host.
MAX_SCREENSHOT_BYTES = 64 * 1024 * 1024


class ADBBridge:
    def __init__(self, adb_path: str | None = None):
        self.adb_path = adb_path or settings.adb_path or self._locate_adb()
        self.emulator_path = self._locate_emulator()
        # Nome de dump único por processo: evita corrida entre duas instâncias
        # do app e não deixa artefato previsível no dispositivo.
        self._dump_remote_path = f"/data/local/tmp/mobaile_dump_{os.getpid()}.xml"
        # Um dump por aparelho de cada vez. O arquivo remoto e o mesmo para o
        # processo inteiro, e o `rm -f` de um dump apagava o arquivo de outro
        # antes do `cat`: o flow e o inspetor do espelho leem ao mesmo tempo.
        self._dump_locks: dict[str, threading.Lock] = {}
        self._dump_locks_guard = threading.Lock()
        # Serial -> o ultimo dump foi morto com SIGKILL (137). So isso prova que
        # o aparelho nao tem `uiautomator dump`; timeout e tela sem ocio, nao.
        self.dump_killed: dict[str, bool] = {}
        # Serial -> pacote da instrumentacao de outra ferramenta (o driver do
        # Maestro, por exemplo) que segurava o UiAutomation no ultimo dump que
        # falhou. Com ela no ar, nem o dump nem o Appium conseguem ler a tela.
        self.dump_blocked_by: dict[str, str] = {}
        # Valores que o aparelho tinha antes de o proxy ser ligado, por serial.
        # O desmonte os devolve em vez de apagar: um proxy corporativo ou o
        # `captive_portal_mode` do aparelho nao pertencem a este motor.
        self._proxy_previous: dict[str, dict[str, str | None]] = {}

    # ------------------------------------------------------------------ setup

    @staticmethod
    def _locate_adb() -> str:
        candidates = [
            shutil.which("adb"),
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            os.path.expanduser("~/Library/Android/sdk/platform-tools/adb"),
        ]
        for path in candidates:
            if path and os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        logger.warning("adb não localizado nos caminhos conhecidos; usando PATH.")
        return "adb"

    @staticmethod
    def _locate_emulator() -> str | None:
        candidates = [
            shutil.which("emulator"),
            os.path.expanduser("~/Library/Android/sdk/emulator/emulator"),
        ]
        for path in candidates:
            if path and os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        return None

    def is_available(self) -> bool:
        """Metodo, e nao property, para casar com ScrcpyManager.is_available()."""
        return bool(shutil.which(self.adb_path) or os.path.isfile(self.adb_path))

    # ---------------------------------------------------------------- execução

    def _run_cmd(self, args: list[str], timeout: int = 15) -> tuple[int, bytes, bytes]:
        """Executa `adb <args>`. Nunca usa shell do host: argumentos vão em lista."""
        cmd = [self.adb_path, *args]
        try:
            proc = subprocess.run(
                cmd, capture_output=True, timeout=timeout, check=False
            )
        except FileNotFoundError as exc:
            raise ToolNotFoundError("adb não encontrado no sistema.", detail=str(exc)) from exc
        except PermissionError as exc:
            # Encontrado em QA: adb presente mas sem bit de execução (acontece
            # ao copiar o SDK entre máquinas, ou com binário em quarentena)
            # subia PermissionError crua até a fronteira RPC, que devolvia erro
            # interno com stack trace em vez de uma explicação.
            raise ToolNotFoundError(
                f"adb encontrado em {self.adb_path}, mas sem permissão de execução.",
                detail=str(exc),
            ) from exc
        except OSError as exc:
            raise ToolNotFoundError("Falha ao executar o adb.", detail=str(exc)) from exc
        return proc.returncode, proc.stdout, proc.stderr

    def _device_args(self, device_id: str, *rest: str) -> list[str]:
        return ["-s", validate_device_id(device_id), *rest]

    # ------------------------------------------------------------ dispositivos

    def list_devices(self) -> list[tuple[str, str]]:
        """Lista `(serial, estado)`. Seriais fora do formato esperado são descartados."""
        try:
            ret, stdout, stderr = self._run_cmd(["devices"])
            if ret != 0:
                logger.warning("adb devices falhou (%s): %s", ret, stderr.decode(errors="ignore").strip())
                return []
            devices: list[tuple[str, str]] = []
            for line in stdout.decode("utf-8", errors="ignore").strip().splitlines()[1:]:
                parts = line.strip().split()
                if len(parts) < 2:
                    continue
                try:
                    serial = validate_device_id(parts[0])
                except InvalidInputError:
                    logger.warning("Serial ADB fora do formato esperado, ignorado: %r", parts[0])
                    continue
                devices.append((serial, parts[1]))
            return devices
        except (ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.warning("Não foi possível listar dispositivos: %s", exc)
            return []

    def list_devices_typed(self) -> list[Device]:
        """Mesma listagem, já no modelo de domínio (usada pela fronteira RPC).

        O `adb` diz `device` assim que o `adbd` responde, o que num emulador
        acontece bem antes de a interface subir. Quem consumia essa lista
        selecionava o alvo, lia `screen.size` e capturava a tela nesse intervalo:
        o tamanho vinha errado e o quadro vinha rasgado, e nada relia depois.

        Por isso o estado `device` só é mantido quando `sys.boot_completed`
        confirma. Antes disso o alvo aparece como `booting`, que a interface já
        trata como "não pronto".
        """
        out: list[Device] = []
        for serial, state in self.list_devices():
            if state == "device" and not self.is_boot_completed(serial):
                state = "booting"
            out.append(
                Device(id=serial, name=self.get_device_model(serial), platform=Platform.ANDROID, state=state)
            )
        return out

    def is_boot_completed(self, device_id: str) -> bool:
        """O Android terminou de subir a interface?

        Falha de leitura conta como concluído: um aparelho físico que não
        responde ao getprop no tempo esperado nao pode sumir da lista por causa
        disso. O modo de errar escolhido e o menos danoso dos dois.
        """
        try:
            _, stdout, _ = self._run_cmd(
                self._device_args(device_id, "shell", "getprop", "sys.boot_completed"), timeout=5
            )
            return stdout.decode("utf-8", errors="ignore").strip() == "1"
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("sys.boot_completed indisponivel para %r: %s", device_id, exc)
            return True

    def get_device_model(self, device_id: str) -> str:
        try:
            _, stdout, _ = self._run_cmd(self._device_args(device_id, "shell", "getprop", "ro.product.model"))
            return stdout.decode("utf-8", errors="ignore").strip() or device_id
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("get_device_model falhou para %r: %s", device_id, exc)
            return device_id

    # -------------------------------------------------------------- captura

    def take_screenshot(self, device_id: str) -> Image.Image | None:
        """Captura a tela. Tenta o formato cru primeiro, por ser bem mais rapido.

        `screencap -p` faz o aparelho codificar o PNG, e essa codificacao domina
        o custo: medido num Motorola g55, 2,14 s contra 1,23 s do formato cru,
        apesar de o cru trafegar 10 MB contra 3 MB. Como o espelho reduz a
        imagem logo em seguida, pagar PNG no aparelho e desperdicio puro — e era
        quase um segundo por quadro.
        """
        img = self._screenshot_raw(device_id)
        if img is not None:
            return img
        return self._screenshot_png(device_id)

    def _screenshot_raw(self, device_id: str) -> Image.Image | None:
        """`screencap` sem `-p`: cabecalho curto seguido de RGBA cru."""
        try:
            ret, stdout, _ = self._run_cmd(
                self._device_args(device_id, "exec-out", "screencap"), timeout=15
            )
            if ret != 0 or len(stdout) < 16:
                return None
            largura = int.from_bytes(stdout[0:4], "little")
            altura = int.from_bytes(stdout[4:8], "little")
            if not (0 < largura <= 8192 and 0 < altura <= 8192):
                return None

            esperado = largura * altura * 4
            # O cabecalho ganhou um campo de espaco de cor no Android 13; aceitar
            # os dois tamanhos evita depender da versao do aparelho.
            for cabecalho in (16, 12):
                if len(stdout) - cabecalho == esperado:
                    return Image.frombuffer(
                        "RGBA", (largura, altura), stdout[cabecalho:], "raw", "RGBA", 0, 1
                    ).convert("RGB")
            logger.debug(
                "screencap cru com tamanho inesperado (%d bytes para %dx%d)", len(stdout), largura, altura
            )
            return None
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("Captura crua falhou para %r: %s", device_id, exc)
            return None
        except (OSError, ValueError) as exc:
            logger.debug("Captura crua nao pode ser lida para %r: %s", device_id, exc)
            return None

    def _screenshot_png(self, device_id: str) -> Image.Image | None:
        try:
            ret, stdout, _ = self._run_cmd(
                self._device_args(device_id, "exec-out", "screencap", "-p"), timeout=10
            )
            if ret != 0 or not stdout:
                return None
            if len(stdout) > MAX_SCREENSHOT_BYTES:
                logger.warning("Screenshot acima de %d bytes, descartado.", MAX_SCREENSHOT_BYTES)
                return None
            image_bytes = stdout
            # adb antigo em alguns aparelhos ainda converte LF em CRLF no exec-out.
            if image_bytes.startswith(b"\r\n"):
                image_bytes = image_bytes.replace(b"\r\n", b"\n")
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            img.load()
            return img
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("Falha ao capturar tela de %r: %s", device_id, exc)
        except (OSError, ValueError) as exc:
            logger.warning("Screenshot de %r não pôde ser decodificado: %s", device_id, exc)
        return None

    def get_ui_hierarchy(self, device_id: str) -> str | None:
        """Dump da hierarquia via comando encadeado com fallback seguro."""
        with self._dump_locks_guard:
            trava = self._dump_locks.setdefault(device_id, threading.Lock())
        with trava:
            return self._dump_hierarchy(device_id)

    def _dump_hierarchy(self, device_id: str) -> str | None:
        remote = self._dump_remote_path
        self.dump_killed[device_id] = False
        self.dump_blocked_by.pop(device_id, None)
        try:
            args = self._device_args(device_id)
            # Tenta executar dump + cat em uma única sessão para evitar overhead de subprocessos adicionais
            ret, stdout, _ = self._run_cmd(
                [*args, "shell", f"uiautomator dump {remote} >/dev/null 2>&1 && cat {remote}"],
                timeout=9,
            )
            if ret == 0 and stdout:
                xml_str = stdout.decode("utf-8", errors="ignore").strip()
                if "<hierarchy" in xml_str:
                    return xml_str

            if ret == 137:
                # 137 é SIGKILL. A causa vista num Motorola com Android 14 foi o
                # driver do Maestro esquecido no aparelho: o UiAutomation só
                # aceita um cliente, e o dump morre com "already registered".
                # Insistir no fallback apenas desperdiça 13 s.
                bloqueio = self._uiautomation_holder(device_id)
                if bloqueio:
                    logger.info("uiautomator dump de %r bloqueado pela instrumentacao %s.", device_id, bloqueio)
                    self.dump_blocked_by[device_id] = bloqueio
                    return None
                logger.debug("uiautomator dump morto com SIGKILL (137) em %r; abortando fallback.", device_id)
                self.dump_killed[device_id] = True
                return None

            # Fallback seguro para chamadas individuais caso o shell composto nao responda
            self._run_cmd([*args, "shell", "uiautomator", "dump", remote], timeout=8)
            ret, stdout, _ = self._run_cmd([*args, "shell", "cat", remote], timeout=5)
            if ret == 0 and stdout:
                xml_str = stdout.decode("utf-8", errors="ignore").strip()
                if "<hierarchy" in xml_str:
                    return xml_str
            bloqueio = self._uiautomation_holder(device_id)
            if bloqueio:
                logger.info("uiautomator dump de %r bloqueado pela instrumentacao %s.", device_id, bloqueio)
                self.dump_blocked_by[device_id] = bloqueio
            return None
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("Dump de hierarquia falhou para %r: %s", device_id, exc)
            return None
        finally:
            try:
                self._run_cmd(self._device_args(device_id, "shell", "rm", "-f", remote), timeout=4)
            except Exception as exc:
                logger.debug("Não foi possível remover o dump remoto %s: %s", remote, exc)

    def _uiautomation_holder(self, device_id: str) -> str | None:
        """Pacote de outra ferramenta cuja instrumentacao segura o UiAutomation.

        So e chamado depois de um dump que falhou, e custa uma ida ao aparelho.
        `None` quando nao ha instrumentacao, quando ela e a do Appium ou quando
        a consulta falha.
        """
        try:
            ret, stdout, _ = self._run_cmd(
                self._device_args(device_id, "shell", "dumpsys activity processes | grep ActiveInstrumentation"),
                timeout=5,
            )
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("Consulta de instrumentacao falhou para %r: %s", device_id, exc)
            return None
        if ret != 0:
            return None
        for pacote in _INSTRUMENTACAO_ATIVA.findall(stdout.decode("utf-8", errors="ignore")):
            if not pacote.startswith(_INSTRUMENTACAO_DO_APPIUM):
                return pacote
        return None

    # ---------------------------------------------------------------- entrada

    def tap(self, device_id: str, x: int, y: int) -> bool:
        try:
            args = self._device_args(
                device_id, "shell", "input", "tap",
                str(validate_coordinate(x, "x")), str(validate_coordinate(y, "y")),
            )
            ret, _, _ = self._run_cmd(args, timeout=5)
            return ret == 0
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.warning("Tap recusado em %r: %s", device_id, exc)
            return False

    def type_text(self, device_id: str, text: str) -> bool:
        """Digita no dispositivo.

        O texto vai como argumento único entre aspas simples para o shell do
        aparelho — sem isso, `;`, `&&` e `$(...)` seriam executados lá dentro.
        """
        try:
            args = self._device_args(device_id) + build_adb_input_text_args(text)
            ret, _, _ = self._run_cmd(args, timeout=5)
            return ret == 0
        except subprocess.TimeoutExpired as exc:
            # Nunca `str(exc)`: ele repete o `cmd`, com o texto digitado entre aspas.
            logger.warning("Digitação recusada em %r: %s após %s s", device_id, type(exc).__name__, exc.timeout)
            return False
        except (InvalidInputError, ToolNotFoundError) as exc:
            logger.warning("Digitação recusada em %r: %s", device_id, exc)
            return False

    def press_key(self, device_id: str, keycode: int) -> bool:
        try:
            args = self._device_args(
                device_id, "shell", "input", "keyevent", str(validate_keycode(keycode))
            )
            ret, _, _ = self._run_cmd(args, timeout=5)
            return ret == 0
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.warning("Keyevent recusado em %r: %s", device_id, exc)
            return False

    # -------------------------------------------------------------- emulador

    def list_avds(self) -> list[str]:
        if not self.emulator_path:
            return []
        try:
            proc = subprocess.run(
                [self.emulator_path, "-list-avds"],
                capture_output=True, timeout=5, check=False,
            )
            if proc.returncode == 0:
                return [ln.strip() for ln in proc.stdout.decode(errors="ignore").splitlines() if ln.strip()]
        except (OSError, subprocess.TimeoutExpired) as exc:
            logger.debug("Listagem de AVDs falhou: %s", exc)
        return []

    def start_avd(self, avd_name: str) -> bool:
        if not self.emulator_path:
            return False
        # O nome vem da nossa própria listagem, mas o formato é validado assim mesmo.
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", avd_name or ""):
            logger.warning("Nome de AVD inválido recusado: %r", avd_name)
            return False
        try:
            subprocess.Popen(
                [self.emulator_path, "-avd", avd_name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                # DEVNULL de proposito: sem isto o filho herda o stdin do
                # motor, que e o canal JSON-RPC, e passa a consumir as
                # linhas do protocolo. O sintoma e a chamada seguinte nunca
                # responder — no app, janela travada sem erro.
                stdin=subprocess.DEVNULL,
            )
            return True
        except OSError as exc:
            logger.warning("Não foi possível iniciar o AVD %r: %s", avd_name, exc)
            return False

    # ------------------------------------------------------------------ proxy

    def _get_global_setting(self, args: list[str], key: str) -> str | None:
        """Valor de `settings get global <key>`, ou `None` se nao ha valor."""
        ret, stdout, _ = self._run_cmd([*args, "shell", "settings", "get", "global", key], timeout=5)
        if ret != 0:
            return None
        value = stdout.decode("utf-8", errors="ignore").strip()
        return None if value in ("", "null") else value

    def setup_reverse_proxy(self, device_id: str, proxy_port: int = 8082) -> bool:
        """Aponta o proxy global do aparelho para o host via `adb reverse`.

        O `adb reverse` é deliberado: mantém o proxy escutando apenas em
        127.0.0.1 no host, sem expor a porta na rede local.
        """
        try:
            port = validate_port(proxy_port)
            args = self._device_args(device_id)
            ret_rev, _, err_rev = self._run_cmd([*args, "reverse", f"tcp:{port}", f"tcp:{port}"], timeout=5)
            if ret_rev != 0:
                logger.warning("adb reverse falhou em %r: %s", device_id, err_rev.decode(errors="ignore"))
                return False

            # Guarda o que o aparelho tinha, uma vez so: numa religacao o valor
            # atual ja e o nosso, e guardar de novo perderia o original.
            ours = f"127.0.0.1:{port}"
            if device_id not in self._proxy_previous:
                previous = {
                    "http_proxy": self._get_global_setting(args, "http_proxy"),
                    "captive_portal_mode": self._get_global_setting(args, "captive_portal_mode"),
                }
                if previous["http_proxy"] != ours:
                    self._proxy_previous[device_id] = previous

            # Desativa temporariamente a checagem de captive portal para evitar
            # que o Android (especialmente Motorola/AOSP) marque a rede como
            # 'sem internet' e desligue o roteamento ou migre para dados móveis.
            self._run_cmd([*args, "shell", "settings", "put", "global", "captive_portal_mode", "0"], timeout=5)

            ret_set, _, err_set = self._run_cmd(
                [*args, "shell", "settings", "put", "global", "http_proxy", f"127.0.0.1:{port}"], timeout=5
            )
            if ret_set != 0:
                logger.warning("Falha ao definir http_proxy em %r: %s", device_id, err_set.decode(errors="ignore"))
                # Rollback defensivo: desfaz a rota reversa e devolve o
                # captive_portal_mode ao que era (ou o apaga, se nao tinha).
                previous_portal = self._proxy_previous.pop(device_id, {}).get("captive_portal_mode")
                if previous_portal is not None:
                    self._run_cmd(
                        [*args, "shell", "settings", "put", "global", "captive_portal_mode", previous_portal],
                        timeout=5,
                    )
                else:
                    self._run_cmd([*args, "shell", "settings", "delete", "global", "captive_portal_mode"], timeout=5)
                self._run_cmd([*args, "reverse", "--remove", f"tcp:{port}"], timeout=5)
                return False

            return True
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.warning("Configuração de proxy falhou em %r: %s", device_id, exc)
            return False

    def teardown_reverse_proxy(self, device_id: str, proxy_port: int = 8082) -> bool:
        """Desfaz a configuração. Chamado também no encerramento da aplicação.

        Sem isso o aparelho fica com proxy apontando para uma porta morta e
        perde acesso à rede — o efeito colateral mais reclamado desse tipo de
        ferramenta.
        """
        try:
            port = validate_port(proxy_port)
            args = self._device_args(device_id)
            previous = self._proxy_previous.get(device_id, {})
            previous_proxy = previous.get("http_proxy")
            previous_portal = previous.get("captive_portal_mode")
            ok = True

            if previous_proxy and previous_proxy != ":0":
                ret, _, _ = self._run_cmd(
                    [*args, "shell", "settings", "put", "global", "http_proxy", previous_proxy], timeout=5
                )
                ok = ok and ret == 0
            else:
                self._run_cmd([*args, "shell", "settings", "put", "global", "http_proxy", ":0"], timeout=5)
                ret, _, _ = self._run_cmd([*args, "shell", "settings", "delete", "global", "http_proxy"], timeout=5)
                ok = ok and ret == 0
            self._run_cmd([*args, "shell", "settings", "delete", "global", "global_http_proxy_host"], timeout=5)
            self._run_cmd([*args, "shell", "settings", "delete", "global", "global_http_proxy_port"], timeout=5)

            if previous_portal is not None:
                ret, _, _ = self._run_cmd(
                    [*args, "shell", "settings", "put", "global", "captive_portal_mode", previous_portal], timeout=5
                )
            else:
                ret, _, _ = self._run_cmd(
                    [*args, "shell", "settings", "delete", "global", "captive_portal_mode"], timeout=5
                )
            ok = ok and ret == 0
            self._run_cmd([*args, "reverse", "--remove", f"tcp:{port}"], timeout=5)

            if ok:
                self._proxy_previous.pop(device_id, None)
            else:
                logger.warning("Desmonte do proxy em %r nao foi confirmado; o aparelho pode ter ficado configurado.", device_id)
            return ok
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.warning("Remoção de proxy falhou em %r: %s", device_id, exc)
            return False

    def is_proxy_configured(self, device_id: str) -> bool:
        try:
            ret, stdout, _ = self._run_cmd(
                self._device_args(device_id, "shell", "settings", "get", "global", "http_proxy"), timeout=5
            )
            if ret != 0:
                return False
            val = stdout.decode("utf-8", errors="ignore").strip()
            return bool(val and val not in (":0", "null"))
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("Consulta de proxy falhou em %r: %s", device_id, exc)
            return False

    # ------------------------------------------------------------------ tela

    def get_screen_size(self, device_id: str) -> tuple[int, int]:
        """Resolução física. Cai no padrão 1080x2400 quando o aparelho não responde."""
        try:
            ret, stdout, _ = self._run_cmd(self._device_args(device_id, "shell", "wm", "size"), timeout=5)
            if ret == 0 and stdout:
                matches = re.findall(r"(\d+)x(\d+)", stdout.decode("utf-8", errors="ignore"))
                if matches:
                    w, h = map(int, matches[-1])
                    if w > 0 and h > 0:
                        return (w, h)
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("wm size falhou em %r: %s", device_id, exc)
        return (1080, 2400)

    def get_digitizer_bounds(self, device_id: str) -> tuple[str | None, int | None, int | None]:
        """Descobre o `/dev/input/eventX` de toque e os máximos do digitalizador."""
        try:
            ret, stdout, _ = self._run_cmd(
                self._device_args(device_id, "shell", "getevent", "-p"), timeout=5
            )
            if ret != 0 or not stdout:
                return (None, None, None)
            current_dev = touch_dev = None
            max_x = max_y = None
            for line in stdout.decode("utf-8", errors="ignore").splitlines():
                if "add device" in line:
                    current_dev = line.split(":")[-1].strip()
                if ("0035" in line or "ABS_MT_POSITION_X" in line) and "max" in line:
                    m = re.search(r"max\s+(\d+)", line)
                    if m:
                        max_x = int(m.group(1))
                        touch_dev = current_dev
                if ("0036" in line or "ABS_MT_POSITION_Y" in line) and "max" in line:
                    m = re.search(r"max\s+(\d+)", line)
                    if m:
                        max_y = int(m.group(1))
            return (touch_dev, max_x, max_y)
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            logger.debug("getevent -p falhou em %r: %s", device_id, exc)
        return (None, None, None)

    def get_current_package(self, device_id: str) -> str | None:
        """Obtém o nome do pacote (package) do app atualmente em primeiro plano."""
        try:
            args = self._device_args(device_id)
            # Tenta via mCurrentFocus ou mFocusedApp (dumpsys window)
            ret, stdout, _ = self._run_cmd([*args, "shell", "dumpsys", "window"], timeout=5)
            if ret == 0 and stdout:
                text = stdout.decode("utf-8", errors="ignore")
                for line in text.splitlines():
                    if "mCurrentFocus" in line or "mFocusedApp" in line:
                        m = re.search(r"(?:u\d+\s+)?([a-zA-Z0-9_\.]+)/", line)
                        if m:
                            pkg = m.group(1).strip()
                            if pkg and not pkg.startswith("com.android.systemui") and not pkg.endswith("launcher") and not pkg.endswith("launcher3"):
                                return pkg

            # Alternativa via dumpsys activity
            ret, stdout, _ = self._run_cmd([*args, "shell", "dumpsys", "activity", "activities"], timeout=5)
            if ret == 0 and stdout:
                text = stdout.decode("utf-8", errors="ignore")
                for line in text.splitlines():
                    if "topResumedActivity" in line or "ResumedActivity" in line:
                        m = re.search(r"([a-zA-Z0-9_\.]+)/[a-zA-Z0-9_\.]+", line)
                        if m:
                            pkg = m.group(1).strip()
                            if pkg and not pkg.startswith("com.android.systemui") and not pkg.endswith("launcher") and not pkg.endswith("launcher3"):
                                return pkg
            return None
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
            logger.debug("Consulta do pacote atual falhou em %r: %s", device_id, exc)
            return None

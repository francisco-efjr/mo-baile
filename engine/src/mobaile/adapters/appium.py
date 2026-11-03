"""Adapter do servidor Appium.

Por que ele existe: no iOS, hierarquia e toque repassado dependem do
WebDriverAgent, e subir o WDA na mao exige o projeto Xcode dele. Quando o time
ja usa Appium, o caminho certo nao e reimplementar isso: e pedir ao Appium, que
instala, compila e mantem o WDA de pe como parte do ciclo de sessao do driver
XCUITest.

Dois detalhes que decidem se isso funciona na pratica:

1. **Sessao sem `app` nem `bundleId`.** O driver XCUITest aceita isso e deixa o
   simulador na tela inicial. E o que queremos: nao estamos testando um app,
   estamos pegando emprestada a gestao de ciclo de vida do WDA.

2. **`newCommandTimeout: 0`.** Sem isso o Appium encerra a sessao apos 60 s sem
   comando e derruba o WDA junto. O usuario veria o indicador ficar verde e
   voltar a vermelho sozinho, que e o tipo de sintoma que consome uma tarde.

3. **So em loopback.** O Appium escuta em `0.0.0.0` por padrao e nao tem
   autenticacao: subido sem `--address`, qualquer maquina da mesma rede
   comandava o aparelho conectado. O servidor proprio sobe em `127.0.0.1`, na
   porta da `APPIUM_URL`; se ela aponta para fora do loopback ou para a porta
   0 (o harness de QA), o motor nao sobe servidor nenhum.

`requests` e importado dentro de cada metodo que fala HTTP. Carregado no topo,
ele custava uns 45 ms em toda subida do motor, inclusive nas que nunca chegam a
falar com o Appium.
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING

from mobaile.config import settings
from mobaile.domain.errors import ToolNotFoundError
from mobaile.security import logs_dir, redact_url, validate_device_id

if TYPE_CHECKING:
    import requests

logger = logging.getLogger(__name__)

# Tempo maximo esperando o servidor Appium responder depois de iniciado.
SERVER_BOOT_TIMEOUT = 45.0
# Compilar e instalar o WDA na primeira vez e lento; nas seguintes, nem tanto.
WDA_SESSION_TIMEOUT = 300.0
# Porta padrao do Appium, para APPIUM_URL sem porta.
DEFAULT_APPIUM_PORT = 4723
# Nomes de loopback aceitos na APPIUM_URL. `localhost` resolve para os dois.
_LOOPBACK_HOSTS = frozenset({"127.0.0.1", "localhost", "::1"})


class AppiumBridge:
    """Conversa com o servidor Appium local."""

    def __init__(self, base_url: str | None = None, wda_url: str | None = None):
        self.base_url = (base_url or settings.appium_url).rstrip("/")
        self.wda_url = (wda_url or settings.wda_url).rstrip("/")
        # Qual plataforma e qual alvo a sessao aberta atende. Sem isto, uma
        # sessao de iOS seria reaproveitada para um pedido de Android.
        self.session_platform: str | None = None
        self.session_udid: str | None = None
        self.session_id: str | None = None
        self._process: subprocess.Popen | None = None
        # O motor atende filas em paralelo: `wda.start` e um `hierarchy.dump`
        # do Android podem pedir o Appium ao mesmo tempo. Sem este lock os dois
        # viam "fora do ar" e subiam dois servidores disputando a porta, ou
        # abriam duas sessoes e cada um gravava a sua em `session_*`. E
        # reentrante porque abrir sessao sobe o servidor antes.
        self._lock = threading.RLock()

    # ------------------------------------------------------------- descoberta

    @staticmethod
    def locate_appium() -> str | None:
        """Procura o binario do Appium nos lugares onde o npm costuma deixar."""
        candidates = [
            shutil.which("appium"),
            "/opt/homebrew/bin/appium",
            "/usr/local/bin/appium",
            os.path.expanduser("~/.npm-global/bin/appium"),
            os.path.expanduser("~/.nvm/versions/node/current/bin/appium"),
        ]
        for path in candidates:
            if path and Path(path).is_file() and os.access(path, os.X_OK):
                return path
        return None

    @property
    def is_installed(self) -> bool:
        return self.locate_appium() is not None

    def is_running(self) -> bool:
        """O servidor Appium esta no ar?"""
        import requests

        try:
            return requests.get(f"{self.base_url}/status", timeout=2).status_code == 200
        except requests.RequestException:
            return False

    def is_wda_running(self) -> bool:
        import requests

        try:
            return requests.get(f"{self.wda_url}/status", timeout=2).status_code == 200
        except requests.RequestException:
            return False

    # ------------------------------------------------------------- servidor

    def start_server(self) -> tuple[bool, str]:
        """Sobe o servidor Appium em segundo plano, se ainda nao estiver de pe."""
        with self._lock:
            return self._start_server_locked()

    def _local_endpoint(self) -> tuple[str, int] | None:
        """Endereco e porta do servidor proprio, ou `None` se nao cabe subir um.

        A porta vem da URL tal como esta: porta 0 e o jeito de dizer "nao fale
        com Appium nenhum" (o harness de QA usa), e trocar 0 por 4723 subiria
        o Appium real e esperaria a toa.
        """
        from urllib.parse import urlparse

        parsed = urlparse(self.base_url)
        try:
            port = parsed.port
        except ValueError:
            return None
        host = (parsed.hostname or "").lower()
        if host not in _LOOPBACK_HOSTS:
            return None
        if port is None:
            port = DEFAULT_APPIUM_PORT
        if port == 0:
            return None
        # O cliente fala com [::1] quando a URL diz ::1; os demais nomes chegam
        # ao 127.0.0.1.
        return ("::1" if host == "::1" else "127.0.0.1"), port

    @staticmethod
    def _open_log():
        """Abre `appium.log` na pasta de logs, so para o dono (0600)."""
        try:
            log_path = logs_dir() / "appium.log"
            # O_NOFOLLOW: nao escreve num symlink plantado no lugar do arquivo.
            fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        except OSError as exc:
            logger.warning("Log do Appium desligado: %s", exc)
            return subprocess.DEVNULL, Path("/dev/null")
        try:
            # Arquivo de versao anterior, ou criado sob outro umask, fica so com o dono.
            os.fchmod(fd, 0o600)
            return os.fdopen(fd, "a", encoding="utf-8"), log_path
        except OSError as exc:
            # Arquivo de outro dono: segue sem log, como antes, e sem vazar o descritor.
            os.close(fd)
            logger.warning("Log do Appium desligado: %s", exc)
            return subprocess.DEVNULL, Path("/dev/null")

    @staticmethod
    def _server_env(binary: str) -> dict[str, str]:
        """Ambiente do servidor com o `node` alcancavel.

        O `appium` do npm comeca com `#!/usr/bin/env node`. Aberto pelo Finder,
        o app herda um PATH sem o Homebrew nem o nvm, e o Appium morria com
        "env: node: No such file or directory". O `node` mora ao lado do
        `appium` que o npm instalou, entao a pasta dele vai na frente.
        """
        env = dict(os.environ)
        atual = [p for p in env.get("PATH", "").split(os.pathsep) if p]
        extras = [str(Path(binary).parent), "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = os.pathsep.join(dict.fromkeys([*extras, *atual]))
        # O driver UiAutomator2 acha o adb pelo ANDROID_HOME, que tambem so
        # existe no shell. O SDK padrao do Android Studio cobre o caso comum.
        if not env.get("ANDROID_HOME") and not env.get("ANDROID_SDK_ROOT"):
            sdk = Path.home() / "Library" / "Android" / "sdk"
            if (sdk / "platform-tools").is_dir():
                env["ANDROID_HOME"] = str(sdk)
        return env

    def _start_server_locked(self) -> tuple[bool, str]:
        if self.is_running():
            return True, "Servidor Appium ja estava no ar."

        endpoint = self._local_endpoint()
        if endpoint is None:
            return False, (
                f"Servidor Appium indisponivel em {redact_url(self.base_url)}. O Mo baile so "
                "sobe o Appium proprio em 127.0.0.1; com a APPIUM_URL apontando para "
                "outro lugar, suba o servidor por la."
            )
        address, port = endpoint

        binary = self.locate_appium()
        if not binary:
            raise ToolNotFoundError(
                "Appium nao encontrado. Instale com: npm i -g appium",
                detail="Procurado no PATH, no Homebrew e nos caminhos globais do npm.",
            )

        log_file, log_path = self._open_log()

        try:
            self._process = subprocess.Popen(
                [binary, "--address", address, "--port", str(port),
                 "--log-timestamp", "--local-timezone"],
                stdout=log_file,
                stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
                env=self._server_env(binary),
            )
        except OSError as exc:
            return False, f"Nao foi possivel iniciar o Appium: {exc}"
        finally:
            # O filho herdou o descritor; o nosso nao precisa ficar aberto.
            if log_file is not subprocess.DEVNULL:
                log_file.close()

        deadline = time.time() + SERVER_BOOT_TIMEOUT
        while time.time() < deadline:
            if self.is_running():
                return True, f"Servidor Appium iniciado. Log em {log_path}."
            if self._process.poll() is not None:
                return False, f"O Appium encerrou logo apos iniciar. Veja {log_path}."
            time.sleep(0.5)

        return False, f"O Appium nao respondeu em {SERVER_BOOT_TIMEOUT:.0f}s. Veja {log_path}."

    def stop_server(self) -> None:
        """So derruba o servidor se fomos nos que o subimos."""
        if not self._process:
            return
        try:
            self._process.terminate()
            self._process.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            try:
                self._process.kill()
            except OSError as exc:
                logger.warning("Processo do Appium nao encerrou: %s", exc)
        self._process = None

    # ---------------------------------------------------------------- sessao

    def _capabilities(self, udid: str, platform_version: str | None) -> dict:
        capabilities = {
            "platformName": "iOS",
            "appium:automationName": "XCUITest",
            "appium:udid": udid,
            # Sem app nem bundleId: a sessao sobe o WDA e deixa o simulador na
            # tela inicial, que e exatamente o que queremos.
            "appium:noReset": True,
            # Sem isto, o Appium encerra a sessao por inatividade e leva o WDA junto.
            "appium:newCommandTimeout": 0,
            "appium:wdaLocalPort": self._wda_port(),
            "appium:usePrebuiltWDA": False,
            "appium:shouldTerminateApp": False,
        }
        if platform_version:
            capabilities["appium:platformVersion"] = platform_version
        return capabilities

    def _android_capabilities(self, udid: str) -> dict:
        """Sessao UiAutomator2, equivalente Android da sessao XCUITest.

        Existe porque `uiautomator dump` falha em parte dos aparelhos — em
        Motorola com Android 14 ele e morto com SIGKILL e nao devolve nada. Sem
        hierarquia nao ha elemento para resolver, e a gravacao de passo do
        Android ficava sem gerar codigo enquanto a do iOS funcionava.
        """
        return {
            "platformName": "Android",
            "appium:automationName": "UiAutomator2",
            "appium:udid": udid,
            "appium:noReset": True,
            # Mesmo motivo do iOS: com o padrao de 60 s o Appium encerraria a
            # sessao por inatividade e derrubaria o servidor de UI junto.
            "appium:newCommandTimeout": 0,
            "appium:skipDeviceInitialization": False,
            "appium:disableWindowAnimation": True,
        }

    def ensure_android_session(self, udid: str) -> tuple[bool, str]:
        """Garante uma sessao UiAutomator2 para o aparelho informado."""
        udid = validate_device_id(udid)
        with self._lock:
            return self._ensure_android_session_locked(udid)

    def _ensure_android_session_locked(self, udid: str) -> tuple[bool, str]:
        import requests

        if self.session_id and self.session_platform == "android" and self.session_udid == udid:
            return True, "Sessao Android ja estava aberta."

        ok, mensagem = self.start_server()
        if not ok:
            return False, mensagem

        try:
            response = requests.post(
                f"{self.base_url}/session",
                json={"capabilities": {"alwaysMatch": self._android_capabilities(udid)}},
                timeout=WDA_SESSION_TIMEOUT,
            )
        except requests.Timeout:
            return False, "O Appium demorou demais para abrir a sessao Android."
        except requests.RequestException as exc:
            return False, f"Falha ao falar com o Appium: {exc}"

        if response.status_code not in (200, 201):
            return False, f"O Appium recusou a sessao Android: {self._extract_error(response)}"

        payload = response.json()
        self.session_id = payload.get("sessionId") or (payload.get("value") or {}).get("sessionId")
        self.session_platform = "android"
        self.session_udid = udid
        return True, "Sessao Android no ar."

    @staticmethod
    def _sessao_invalida(response) -> bool:
        """404 com `invalid session id`: so isso prova que o id caducou."""
        if response.status_code != 404:
            return False
        try:
            erro = ((response.json() or {}).get("value") or {}).get("error", "")
        except (ValueError, AttributeError):
            erro = ""
        return "invalid session" in str(erro).lower()

    def get_page_source(self) -> str | None:
        """XML da tela pela sessao aberta, seja Android ou iOS."""
        import requests

        # Lido uma vez, sem lock: segurar o lock durante a leitura prenderia o
        # dump atras de um `wda.start` de minutos. Um id que caducou no meio so
        # faz o Appium responder erro, que vira `None` aqui.
        session_id = self.session_id
        if not session_id:
            return None
        try:
            response = requests.get(f"{self.base_url}/session/{session_id}/source", timeout=30)
        except requests.RequestException as exc:
            logger.debug("Page source pelo Appium falhou: %s", exc)
            return None
        if self._sessao_invalida(response):
            # Sessao inexistente: o id em cache morreu (UiAutomator2 caiu,
            # aparelho foi desplugado). Sem limpar, `ensure_android_session`
            # respondia "ja estava aberta" para sempre. O lock so e tomado se
            # estiver livre: quem o segura esta abrindo outra sessao.
            if self._lock.acquire(blocking=False):
                try:
                    if self.session_id == session_id:
                        self.session_id = None
                        self.session_platform = None
                        self.session_udid = None
                finally:
                    self._lock.release()
            logger.debug("Sessao %s do Appium caducou; sera reaberta no proximo uso.", session_id)
            return None
        if response.status_code != 200:
            logger.debug("Page source pelo Appium respondeu %s", response.status_code)
            return None
        fonte = (response.json() or {}).get("value")
        return fonte if isinstance(fonte, str) and fonte.strip() else None

    def _wda_port(self) -> int:
        from urllib.parse import urlparse

        return urlparse(self.wda_url).port or 8100

    def ensure_wda(self, udid: str, platform_version: str | None = None) -> tuple[bool, str]:
        """Garante WebDriverAgent de pe para o simulador informado.

        Sobe o servidor Appium se preciso, abre a sessao XCUITest e espera a
        porta do WDA responder.
        """
        udid = validate_device_id(udid)
        with self._lock:
            return self._ensure_wda_locked(udid, platform_version)

    def _ensure_wda_locked(self, udid: str, platform_version: str | None) -> tuple[bool, str]:
        import requests


        if self.is_wda_running():
            return True, "WebDriverAgent ja estava respondendo."

        ok, mensagem = self.start_server()
        if not ok:
            return False, mensagem

        try:
            response = requests.post(
                f"{self.base_url}/session",
                json={"capabilities": {"alwaysMatch": self._capabilities(udid, platform_version)}},
                timeout=WDA_SESSION_TIMEOUT,
            )
        except requests.Timeout:
            return False, (
                "O Appium demorou demais para preparar o WebDriverAgent. "
                "Na primeira execucao ele compila o WDA, o que pode levar minutos."
            )
        except requests.RequestException as exc:
            return False, f"Falha ao falar com o Appium: {exc}"

        if response.status_code not in (200, 201):
            detalhe = self._extract_error(response)
            return False, f"O Appium recusou a sessao: {detalhe}"

        payload = response.json()
        self.session_id = payload.get("sessionId") or (payload.get("value") or {}).get("sessionId")
        self.session_platform = "ios"
        self.session_udid = udid

        # A sessao voltou, mas a porta do WDA pode levar um instante a mais.
        deadline = time.time() + 30
        while time.time() < deadline:
            if self.is_wda_running():
                return True, "WebDriverAgent no ar."
            time.sleep(0.5)

        return False, "A sessao do Appium abriu, mas o WebDriverAgent nao respondeu na porta esperada."

    @staticmethod
    def _extract_error(response: requests.Response) -> str:
        try:
            value = response.json().get("value") or {}
            return (value.get("message") or str(value))[:300]
        except ValueError:
            return response.text[:300] or f"HTTP {response.status_code}"

    def delete_session(self) -> bool:
        """Encerra a sessao. Isso derruba o WDA junto, por design do Appium."""
        import requests

        with self._lock:
            if not self.session_id:
                return True
            try:
                requests.delete(f"{self.base_url}/session/{self.session_id}", timeout=10)
            except requests.RequestException as exc:
                logger.warning("Nao foi possivel encerrar a sessao do Appium: %s", exc)
                return False
            finally:
                self.session_id = None
            return True

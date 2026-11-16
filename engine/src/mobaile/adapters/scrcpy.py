import atexit
import logging
import os
import shutil
import signal
import subprocess
import threading
import time
from collections import deque
from pathlib import Path

from mobaile.domain.errors import EngineError
from mobaile.security import validate_device_id

logger = logging.getLogger(__name__)

# O vídeo tem este tempo para fechar o MP4 depois do SIGINT.
RECORD_CLOSE_S = 15.0
# A gravação só começa quando o servidor do scrcpy conecta no aparelho. Ele
# anuncia isso com `[server] INFO: Device: …`, que chega pelo stdout na hora
# (vem do processo do servidor, não do buffer do scrcpy; o "Recording started"
# do próprio scrcpy só aparece no fim, porque o stdout dele vai bufferizado
# para o pipe). No emulador a linha sai em ~0,3-0,6 s; por USB pode passar.
RECORD_READY_TIMEOUT_S = 5.0
RECORD_READY_MARGIN_S = 0.2
RECORD_READY_MARKER = "[server] INFO: Device:"


class ScrcpyManager:
    def __init__(self, scrcpy_path: str | None = None):
        self.scrcpy_path = scrcpy_path or self._locate_scrcpy()
        self.process: subprocess.Popen | None = None
        self.current_device_id: str | None = None
        atexit.register(self.stop_mirror)

    def _locate_scrcpy(self) -> str | None:
        candidates = [
            shutil.which("scrcpy"),
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
        ]
        for path in candidates:
            if path and os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        return None

    def is_available(self) -> bool:
        return self.scrcpy_path is not None and os.path.isfile(self.scrcpy_path)

    def is_running(self) -> bool:
        if self.process is not None:
            if self.process.poll() is None:
                return True
            self.process = None
            self.current_device_id = None
        return False

    def build_command(
        self,
        device_id: str,
        title: str = "Mobile Recorder — Espelho Android",
        max_fps: int = 60,
        max_size: int = 1080,
        x: int | None = None,
        y: int | None = None,
        width: int = 380,
        height: int = 820,
        borderless: bool = True,
        always_on_top: bool = True,
    ) -> list[str]:
        if not self.scrcpy_path:
            raise FileNotFoundError("Binário do scrcpy não encontrado.")

        cmd = [
            self.scrcpy_path,
            "-s",
            device_id,
            f"--window-title={title}",
            f"--max-fps={max_fps}",
            f"--max-size={max_size}",
            "--stay-awake",
            "--no-audio",
            f"--window-width={width}",
            f"--window-height={height}",
        ]

        if x is not None:
            cmd.append(f"--window-x={x}")
        if y is not None:
            cmd.append(f"--window-y={y}")
        if borderless:
            cmd.append("--window-borderless")
        if always_on_top:
            cmd.append("--always-on-top")

        return cmd

    def start_mirror(
        self,
        device_id: str,
        title: str = "Mobile Recorder — Espelho Android",
        max_fps: int = 60,
        max_size: int = 1080,
        x: int | None = None,
        y: int | None = None,
        width: int = 380,
        height: int = 820,
        borderless: bool = True,
        always_on_top: bool = True,
    ) -> bool:
        if not self.is_available():
            return False

        if self.is_running():
            if (
                self.current_device_id == device_id
                and getattr(self, "_last_pos", None) == (x, y, width, height, borderless)
            ):
                return True
            self.stop_mirror()

        cmd = self.build_command(
            device_id=device_id,
            title=title,
            max_fps=max_fps,
            max_size=max_size,
            x=x,
            y=y,
            width=width,
            height=height,
            borderless=borderless,
            always_on_top=always_on_top,
        )

        try:
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                # DEVNULL de proposito: sem isto o filho herda o stdin do
                # motor, que e o canal JSON-RPC, e passa a consumir as
                # linhas do protocolo. O sintoma e a chamada seguinte nunca
                # responder — no app, janela travada sem erro.
                stdin=subprocess.DEVNULL,
            )
            self.current_device_id = device_id
            self._last_pos = (x, y, width, height, borderless)
            return True
        except Exception:
            self.process = None
            self.current_device_id = None
            return False

    def stop_mirror(self):
        if self.process is not None:
            try:
                if self.process.poll() is None:
                    self.process.terminate()
                    try:
                        self.process.wait(timeout=1.5)
                    except subprocess.TimeoutExpired:
                        self.process.kill()
            except Exception:
                pass
            finally:
                self.process = None
                self.current_device_id = None


class ScrcpyRecording:
    """`scrcpy --record` sem janela: grava direto no Mac, sem limite de tempo.

    Usado pela execução do projeto do dono (B1). Sem janela nem áudio, e sem
    repassar toque: só o vídeo. Para com SIGINT, para o MP4 fechar o índice.
    """

    def __init__(self, scrcpy_path: str, serial: str, target: Path) -> None:
        self.scrcpy_path = scrcpy_path
        self.serial = validate_device_id(serial)
        self.target = target
        self.warning: str | None = None
        # Epoch em que a gravação começou de fato (servidor conectado). A B4 usa
        # para alinhar os steps no vídeo.
        self.started_at: float | None = None
        self._process: subprocess.Popen | None = None
        # As últimas linhas de stdout e stderr, para explicar uma falha. Uma
        # thread por pipe drena: cheio, ele travaria o scrcpy no meio do vídeo.
        self._tail_lines: deque[str] = deque(maxlen=20)
        self._ready = threading.Event()
        self._drains: list[threading.Thread] = []

    def command(self) -> list[str]:
        return [self.scrcpy_path, "-s", self.serial, "--no-playback", "--no-window", "--no-audio",
                f"--record={self.target}"]

    def _drain(self, fluxo) -> None:
        for linha in iter(fluxo.readline, b""):
            texto = linha.decode("utf-8", errors="replace").strip()
            if not texto:
                continue
            self._tail_lines.append(texto)
            if RECORD_READY_MARKER in texto:
                self._ready.set()

    def start(self) -> None:
        """Sobe o scrcpy e espera o servidor conectar (até 5 s), e não um tempo fixo.

        Sem a linha do servidor no prazo, segue gravando com aviso: o começo
        da execução pode ter ficado fora do vídeo.
        """
        try:
            self._process = subprocess.Popen(
                self.command(), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
        except OSError as exc:
            raise EngineError(f"Não consegui iniciar o scrcpy: {exc}") from exc
        for fluxo in (self._process.stdout, self._process.stderr):
            if fluxo is not None:
                fio = threading.Thread(target=self._drain, args=(fluxo,), daemon=True, name="mobaile-run-scrcpy")
                fio.start()
                self._drains.append(fio)
        limite = time.monotonic() + RECORD_READY_TIMEOUT_S
        while not self._ready.wait(0.05):
            if self._process.poll() is not None:
                for fio in self._drains:
                    fio.join(1.0)
                if not self._ready.is_set():
                    raise EngineError(f"O scrcpy encerrou ao começar a gravar: {self._tail()}")
                break
            if time.monotonic() >= limite:
                self.warning = (f"O scrcpy não confirmou o início da gravação em {RECORD_READY_TIMEOUT_S:.0f} s; "
                                "o começo da execução pode ter ficado fora do vídeo.")
                logger.warning(self.warning)
                self.started_at = time.time()
                return
        # O servidor conectou; a folga cobre o primeiro quadro chegar ao arquivo.
        time.sleep(RECORD_READY_MARGIN_S)
        self.started_at = time.time()

    def _tail(self) -> str:
        return self._tail_lines[-1] if self._tail_lines else ""

    def stop(self) -> Path | None:
        processo = self._process
        if processo is None:
            return None
        if processo.poll() is None:
            try:
                processo.send_signal(signal.SIGINT)
                processo.wait(timeout=RECORD_CLOSE_S)
            except subprocess.TimeoutExpired:
                logger.warning("scrcpy não fechou o vídeo em %.0f s; encerrando à força.", RECORD_CLOSE_S)
                processo.kill()
                processo.wait(timeout=5)
        for fio in self._drains:
            fio.join(1.0)
        self._process = None
        if self.target.exists() and self.target.stat().st_size > 0:
            return self.target
        self.warning = f"O scrcpy não gravou o vídeo. {self._tail()}".strip()
        return None

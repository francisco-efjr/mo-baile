"""Gravação de vídeo da tela do aparelho.

Cada plataforma já traz a sua ferramenta, e nenhuma das duas precisa de
biblioteca extra:

- Android: `adb shell screenrecord`, que grava no proprio aparelho e depois e
  puxado para o Mac;
- iOS: `xcrun simctl io <udid> recordVideo`, que grava direto no Mac.

As duas param do mesmo jeito, por SIGINT: matar com SIGKILL deixaria o MP4 sem
o indice final e o arquivo nao abriria em lugar nenhum. Por isso o encerramento
e educado e espera o processo fechar o arquivo.
"""

from __future__ import annotations

import logging
import signal
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from mobaile.domain.errors import EngineError, InvalidInputError, ToolNotFoundError
from mobaile.domain.models import Platform
from mobaile.security import validate_device_id

logger = logging.getLogger(__name__)

# `screenrecord` do Android recusa valores acima disto e para sozinho ao
# atingir o limite. Deixar explicito e melhor que descobrir na hora que o video
# terminou antes do teste.
ANDROID_LIMITE_SEGUNDOS = 180

# Tempo dado ao processo para fechar o arquivo depois do SIGINT.
PRAZO_PARA_FECHAR = 15


@dataclass
class Gravacao:
    platform: Platform
    device_id: str
    local_path: Path
    device_path: str | None
    started_at: float


class ScreenRecorder:
    """Grava a tela do alvo ativo. Uma gravação por vez."""

    def __init__(self, adb, ios, output_dir: Path | None = None):
        self.adb = adb
        self.ios = ios
        self.output_dir = Path(output_dir) if output_dir else Path.home() / "Movies" / "Mo baile"
        self._process: subprocess.Popen | None = None
        self._atual: Gravacao | None = None

    # ------------------------------------------------------------------ estado

    @property
    def is_recording(self) -> bool:
        return self._process is not None and self._process.poll() is None

    def status(self) -> dict:
        if not self._atual:
            return {"recording": False, "path": None, "elapsed_s": 0.0, "platform": None}
        return {
            "recording": self.is_recording,
            "path": str(self._atual.local_path),
            "elapsed_s": round(time.time() - self._atual.started_at, 1),
            "platform": self._atual.platform.value,
        }

    # ------------------------------------------------------------------- inicio

    def start(self, platform: Platform, device_id: str) -> dict:
        if self.is_recording:
            raise InvalidInputError("Já existe uma gravação em andamento.")

        device_id = validate_device_id(device_id)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        carimbo = time.strftime("%Y%m%d-%H%M%S")
        local_path = self.output_dir / f"mobaile-{platform.value}-{carimbo}.mp4"

        if platform is Platform.IOS:
            device_path = None
            comando = [
                "xcrun", "simctl", "io", device_id, "recordVideo",
                "--codec", "h264", "--force", str(local_path),
            ]
        else:
            device_path = f"/sdcard/mobaile-{carimbo}.mp4"
            comando = [
                self.adb.adb_path, "-s", device_id, "shell", "screenrecord",
                "--time-limit", str(ANDROID_LIMITE_SEGUNDOS), device_path,
            ]

        try:
            self._process = subprocess.Popen(
                comando,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                # DEVNULL de proposito: sem isto o filho herda o stdin do
                # motor, que e o canal JSON-RPC, e passa a consumir as
                # linhas do protocolo. O sintoma e a chamada seguinte nunca
                # responder — no app, janela travada sem erro.
                stdin=subprocess.DEVNULL,
            )
        except FileNotFoundError as exc:
            ferramenta = "xcrun" if platform is Platform.IOS else "adb"
            raise ToolNotFoundError(f"{ferramenta} nao encontrado no sistema.", detail=str(exc)) from exc
        except OSError as exc:
            raise EngineError(f"Nao foi possivel iniciar a gravacao: {exc}") from exc

        # Falha de argumento aparece de imediato; sem esta espera curta, o
        # start responderia "gravando" para um processo que ja morreu.
        time.sleep(0.4)
        if self._process.poll() is not None:
            erro = (self._process.stderr.read() or b"").decode("utf-8", errors="ignore").strip()
            self._process = None
            raise EngineError(erro or "A gravacao encerrou imediatamente.")

        self._atual = Gravacao(
            platform=platform,
            device_id=device_id,
            local_path=local_path,
            device_path=device_path,
            started_at=time.time(),
        )
        logger.info("Gravacao iniciada em %s", local_path)
        return {
            "recording": True,
            "path": str(local_path),
            "platform": platform.value,
            "limit_s": ANDROID_LIMITE_SEGUNDOS if platform is Platform.ANDROID else None,
        }

    # -------------------------------------------------------------------- fim

    def stop(self) -> dict:
        """Encerra e devolve o arquivo. Idempotente."""
        if not self._atual:
            return {"recording": False, "path": None, "size_bytes": 0, "duration_s": 0.0}

        atual = self._atual
        duracao = round(time.time() - atual.started_at, 1)

        if self._process is not None:
            self._encerrar_processo()

        if atual.device_path:
            self._puxar_do_aparelho(atual)

        self._process = None
        self._atual = None

        tamanho = atual.local_path.stat().st_size if atual.local_path.exists() else 0
        if tamanho == 0:
            raise EngineError(
                "A gravacao terminou sem conteudo. Em aparelho fisico, verifique se a "
                "tela ficou visivel durante a captura."
            )

        logger.info("Gravacao encerrada: %s (%s bytes)", atual.local_path, tamanho)
        return {
            "recording": False,
            "path": str(atual.local_path),
            "size_bytes": tamanho,
            "duration_s": duracao,
        }

    def _encerrar_processo(self) -> None:
        """SIGINT e espera. SIGKILL deixaria o MP4 sem indice e ilegivel."""
        processo = self._process
        if processo is None or processo.poll() is not None:
            return
        try:
            processo.send_signal(signal.SIGINT)
            processo.wait(timeout=PRAZO_PARA_FECHAR)
        except subprocess.TimeoutExpired:
            logger.warning("Gravacao nao encerrou no prazo; encerrando a forca.")
            processo.kill()
            processo.wait(timeout=5)
        except OSError as exc:
            logger.warning("Falha ao sinalizar o processo de gravacao: %s", exc)

    def _puxar_do_aparelho(self, atual: Gravacao) -> None:
        """Traz o MP4 do Android para o Mac e limpa o aparelho."""
        try:
            # O `screenrecord` leva um instante para fechar o arquivo depois de
            # o processo do host sair.
            time.sleep(1.0)
            ret, _, stderr = self.adb._run_cmd(
                ["-s", atual.device_id, "pull", atual.device_path, str(atual.local_path)],
                timeout=120,
            )
            if ret != 0:
                detalhe = stderr.decode("utf-8", errors="ignore").strip()
                raise EngineError(f"Nao foi possivel trazer o video do aparelho: {detalhe}")
            self.adb._run_cmd(["-s", atual.device_id, "shell", "rm", "-f", atual.device_path], timeout=15)
        except (ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            raise EngineError(f"Falha ao recuperar o video do aparelho: {exc}") from exc

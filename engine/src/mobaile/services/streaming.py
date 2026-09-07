"""Motor de streaming do espelho.

Mudanca de comportamento importante em relacao a versao anterior: o quadro so
sobe para a camada de apresentacao quando algo mudou na tela. Antes o detector
de diferenca ja existia, mas o resultado era usado apenas para disparar o
evento de "tela estabilizada": o callback de quadro era chamado a cada ciclo,
entao uma tela parada continuava custando um redesenho completo por ciclo.
Numa ferramenta que fica horas aberta ao lado do simulador, isso e ventoinha
ligada sem motivo.
"""

from __future__ import annotations

import logging
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass

from PIL import Image, ImageChops, ImageStat

from mobaile.config import settings

logger = logging.getLogger(__name__)


@dataclass
class StreamStats:
    """Numeros para a barra de status: o que foi medido, nao o que foi pedido."""

    frames_captured: int = 0
    frames_emitted: int = 0
    frames_skipped: int = 0
    last_capture_ms: float = 0.0
    effective_fps: float = 0.0

    @property
    def skip_ratio(self) -> float:
        return self.frames_skipped / self.frames_captured if self.frames_captured else 0.0


class ScreenDiffDetector:
    def __init__(
        self,
        diff_threshold: float | None = None,
        settle_delay: float | None = None,
    ):
        self.diff_threshold = diff_threshold or settings.diff_threshold
        self.settle_delay = settle_delay or settings.settle_delay
        self.last_thumb: Image.Image | None = None
        self.is_in_transition = False
        self.last_change_time = 0.0

    def process_frame(self, image: Image.Image) -> tuple[bool, bool, float]:
        thumb = image.resize((32, 32), Image.Resampling.BILINEAR).convert("L")

        if self.last_thumb is None:
            self.last_thumb = thumb
            return False, True, 0.0

        diff_img = ImageChops.difference(self.last_thumb, thumb)
        diff_score = ImageStat.Stat(diff_img).mean[0]

        now = time.time()
        has_changed = diff_score > self.diff_threshold
        is_settled = False

        if has_changed:
            self.is_in_transition = True
            self.last_change_time = now
            self.last_thumb = thumb
        elif self.is_in_transition:
            if now - self.last_change_time >= self.settle_delay:
                self.is_in_transition = False
                is_settled = True
                self.last_thumb = thumb

        return has_changed, is_settled, diff_score

    def reset(self):
        self.last_thumb = None
        self.is_in_transition = False
        self.last_change_time = 0.0


class RealTimeStreamEngine:
    def __init__(
        self,
        get_frame_fn: Callable[[], Image.Image | None],
        on_frame_callback: Callable[[Image.Image], None],
        on_screen_settled_callback: Callable[[], None],
        fps: float | None = None,
    ):
        self.get_frame_fn = get_frame_fn
        self.on_frame_callback = on_frame_callback
        self.on_screen_settled_callback = on_screen_settled_callback
        self.frame_interval = 1.0 / (fps or settings.stream_fps)

        self.diff_detector = ScreenDiffDetector()
        self.stats = StreamStats()
        self._stop_event = threading.Event()
        self._pause_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self):
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._pause_event.clear()
        self._thread = threading.Thread(target=self._stream_loop, daemon=True, name="mobaile-stream")
        self._thread.start()

    def stop(self):
        self._stop_event.set()
        self._pause_event.set()
        if self._thread:
            self._thread.join(timeout=2.0)
            if self._thread.is_alive():
                logger.warning("Thread de streaming nao encerrou no tempo esperado.")
        self._thread = None

    def pause(self):
        self._pause_event.set()

    def resume(self):
        self._pause_event.clear()

    def reset_diff(self):
        self.diff_detector.reset()

    def _stream_loop(self):
        last_emit = time.time()
        while not self._stop_event.is_set():
            if self._pause_event.is_set():
                # Espera interrompivel: no stop() a thread sai na hora em vez de
                # dormir 300 ms antes de perceber.
                self._stop_event.wait(0.3)
                continue

            loop_start = time.time()
            try:
                img = self.get_frame_fn()
                if img is not None:
                    self.stats.frames_captured += 1
                    self.stats.last_capture_ms = (time.time() - loop_start) * 1000

                    has_changed, is_settled, _score = self.diff_detector.process_frame(img)
                    first_frame = self.stats.frames_emitted == 0

                    if has_changed or is_settled or first_frame:
                        self.stats.frames_emitted += 1
                        now = time.time()
                        delta = now - last_emit
                        if delta > 0:
                            # Media movel curta: o numero na barra de status para
                            # de piscar a cada quadro.
                            self.stats.effective_fps = (
                                0.7 * self.stats.effective_fps + 0.3 * (1.0 / delta)
                                if self.stats.effective_fps
                                else 1.0 / delta
                            )
                        last_emit = now
                        self.on_frame_callback(img)
                    else:
                        self.stats.frames_skipped += 1

                    if is_settled:
                        self.on_screen_settled_callback()
            except Exception:
                logger.exception("Falha ao processar quadro do espelho.")

            elapsed = time.time() - loop_start
            self._stop_event.wait(max(0.01, self.frame_interval - elapsed))

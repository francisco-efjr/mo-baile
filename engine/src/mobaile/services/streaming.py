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

# Cadencia adaptativa (PERF-2). Com a tela parada por `IDLE_AFTER_FRAMES`
# capturas seguidas e ha pelo menos `IDLE_GRACE_S` sem toque nem mudanca, a
# captura cai para `idle_fps`. Toque (`wake`) ou quadro diferente voltam ao
# normal na hora. O diff vem depois da captura, entao so espacar a captura
# poupa o `simctl`/`screencap`.
IDLE_AFTER_FRAMES = 5
IDLE_GRACE_S = 2.0
# Quando a captura e mais lenta que o intervalo pedido, o laco ainda descansa
# uma fracao do que ela levou, com um piso. Antes esperava 10 ms e capturava de
# novo: a thread e o processo de captura ficavam ocupados o tempo todo.
MIN_REST_S = 0.05
REST_RATIO = 0.25


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
        extrema = diff_img.getextrema()
        peak_diff = extrema[1] if isinstance(extrema, tuple) and len(extrema) == 2 else 0

        now = time.time()
        # Detecta por alteração global da tela ou por alteração local concentrada (ex.: toggle, foco de input, checkbox)
        has_changed = (diff_score > self.diff_threshold) or (peak_diff > 45 and diff_score > 0.4)
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
        idle_fps: float | None = None,
        idle_after: int = IDLE_AFTER_FRAMES,
        idle_grace_s: float = IDLE_GRACE_S,
    ):
        self.get_frame_fn = get_frame_fn
        self.on_frame_callback = on_frame_callback
        self.on_screen_settled_callback = on_screen_settled_callback
        self.frame_interval = 1.0 / (fps or settings.stream_fps)
        # Sem `idle_fps`, a cadencia nunca cai (comportamento de antes).
        self.idle_interval = 1.0 / idle_fps if idle_fps else None
        self.idle_after = idle_after
        self.idle_grace_s = idle_grace_s
        self._identicos = 0
        self._ultima_atividade = time.monotonic()

        self.diff_detector = ScreenDiffDetector()
        self.stats = StreamStats()
        self._stop_event = threading.Event()
        self._pause_event = threading.Event()
        # Acorda o laco antes da hora: retomada, parada e (PERF-2) toque do
        # usuario. Toda espera do laco e neste Event, nunca em sleep.
        self._wake = threading.Event()
        # Depois de uma pausa, o primeiro quadro sai mesmo igual ao ultimo: a
        # moldura volta com a tela de agora, e nao com a de antes da pausa.
        self._force_emit = False
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
        self._wake.set()
        if self._thread and self._thread is not threading.current_thread():
            self._thread.join(timeout=2.0)
            if self._thread.is_alive():
                logger.warning("Thread de streaming nao encerrou no tempo esperado.")
        if self._thread and not self._thread.is_alive():
            self._thread = None

    def pause(self):
        """Para de capturar (janela oculta, PERF-1). O laco fica parado no Event."""
        self._pause_event.set()

    def resume(self):
        if self._pause_event.is_set() and not self._stop_event.is_set():
            self._force_emit = True
        self._pause_event.clear()
        self._wake.set()

    @property
    def paused(self) -> bool:
        return self._pause_event.is_set() and not self._stop_event.is_set()

    def wake(self):
        """Toque ou digitacao: volta a cadencia normal e captura ja."""
        self._identicos = 0
        self._ultima_atividade = time.monotonic()
        self._wake.set()

    def set_cadence(self, fps: float, idle_fps: float | None) -> None:
        """Troca de perfil com o espelho ligado; vale a partir da proxima espera."""
        self.frame_interval = 1.0 / fps
        self.idle_interval = 1.0 / idle_fps if idle_fps else None
        self._wake.set()

    @property
    def idle(self) -> bool:
        return (
            self.idle_interval is not None
            and self._identicos >= self.idle_after
            and time.monotonic() - self._ultima_atividade >= self.idle_grace_s
        )

    def _espera(self, elapsed: float) -> float:
        intervalo = self.frame_interval
        if self.idle and self.idle_interval is not None:
            intervalo = max(intervalo, self.idle_interval)
        if elapsed >= intervalo:
            return max(MIN_REST_S, elapsed * REST_RATIO)
        return intervalo - elapsed

    def reset_diff(self):
        self.diff_detector.reset()

    def _stream_loop(self):
        last_emit = time.time()
        while not self._stop_event.is_set():
            if self._pause_event.is_set():
                # Espera interrompivel: no stop() e no resume() a thread acorda
                # na hora em vez de dormir 300 ms antes de perceber.
                self._wake.wait(0.3)
                self._wake.clear()
                continue

            loop_start = time.time()
            try:
                img = self.get_frame_fn()
                if self._stop_event.is_set():
                    break  # Captura iniciada antes da parada não vira evento tardio.
                if img is not None:
                    self.stats.frames_captured += 1
                    self.stats.last_capture_ms = (time.time() - loop_start) * 1000

                    has_changed, is_settled, _score = self.diff_detector.process_frame(img)
                    first_frame = self.stats.frames_emitted == 0
                    forced, self._force_emit = self._force_emit, False

                    if has_changed or is_settled or first_frame or forced:
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
                    if has_changed:
                        self._identicos = 0
                        self._ultima_atividade = time.monotonic()
                    else:
                        self._identicos += 1

                    if is_settled and not self._stop_event.is_set():
                        self.on_screen_settled_callback()
            except Exception:
                logger.exception("Falha ao processar quadro do espelho.")

            elapsed = time.time() - loop_start
            self._wake.wait(self._espera(elapsed))
            self._wake.clear()

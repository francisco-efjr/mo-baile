import logging
import re
import subprocess
import threading
import time
from collections.abc import Callable

try:
    import Quartz
    QUARTZ_AVAILABLE = True
except ImportError:
    QUARTZ_AVAILABLE = False


logger = logging.getLogger(__name__)


def get_video_viewport(win_w: int, win_h: int, device_w: int, device_h: int) -> tuple[int, int, int, int]:
    """
    Calcula o sub-retângulo (x, y, largura, altura) onde o vídeo do dispositivo
    é projetado dentro da janela respeitando a proporção nativa (sem esticar).
    """
    if win_w <= 0 or win_h <= 0 or device_w <= 0 or device_h <= 0:
        return (0, 0, max(1, win_w), max(1, win_h))
    device_ratio = device_w / device_h
    win_ratio = win_w / win_h
    if win_ratio > device_ratio:
        # Pillarbox: barras pretas laterais
        vp_h = win_h
        vp_w = int(win_h * device_ratio)
        vp_x = (win_w - vp_w) // 2
        vp_y = 0
    else:
        # Letterbox: barras pretas superior/inferior
        vp_w = win_w
        vp_h = int(win_w / device_ratio)
        vp_x = 0
        vp_y = (win_h - vp_h) // 2
    return (vp_x, vp_y, max(1, vp_w), max(1, vp_h))


class AndroidPassiveListener:
    def __init__(
        self,
        adb_path: str,
        device_id: str,
        on_tap_callback: Callable[[int, int], None],
        screen_size: tuple[int, int] = (1080, 2400),
        digitizer_bounds: tuple[str | None, int | None, int | None] | None = None,
        borderless: bool = True,
    ):
        self.adb_path = adb_path
        self.device_id = device_id
        self.on_tap_callback = on_tap_callback
        self.screen_size = screen_size
        self.borderless = borderless
        self._stop_event = threading.Event()
        self._adb_thread: threading.Thread | None = None
        self._mouse_thread: threading.Thread | None = None
        self._proc: subprocess.Popen | None = None

        self.touch_dev: str | None = None
        self.max_x: int | None = None
        self.max_y: int | None = None
        if digitizer_bounds:
            self.touch_dev, self.max_x, self.max_y = digitizer_bounds

    def _query_digitizer_bounds(self):
        try:
            cmd = [self.adb_path, "-s", self.device_id, "shell", "getevent", "-p"]
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if proc.returncode == 0 and proc.stdout:
                current_dev = None
                for line in proc.stdout.splitlines():
                    if "add device" in line:
                        current_dev = line.split(":")[-1].strip()
                    if ("0035" in line or "ABS_MT_POSITION_X" in line) and "max" in line:
                        m = re.search(r"max\s+(\d+)", line)
                        if m:
                            self.max_x = int(m.group(1))
                            self.touch_dev = current_dev
                    if ("0036" in line or "ABS_MT_POSITION_Y" in line) and "max" in line:
                        m = re.search(r"max\s+(\d+)", line)
                        if m:
                            self.max_y = int(m.group(1))
        except (OSError, subprocess.SubprocessError) as exc:
            logger.warning("Nao foi possivel ler os limites do digitizer: %s", exc)

        if not self.max_x or not self.max_y:
            # Falhar calado aqui e o pior caso: a escuta continua funcionando e
            # grava todo toque na coordenada errada. Medido neste Motorola, o
            # digitizer vai a 4320x9600 para uma tela de 1080x2400 — sem a
            # conversao, cada passo sai a quatro vezes a distancia.
            logger.warning(
                "Limites do digitizer nao encontrados para %s; a coordenada do toque "
                "passivo pode sair errada.", self.device_id,
            )

    def start(self):
        if (self._adb_thread and self._adb_thread.is_alive()) or (self._mouse_thread and self._mouse_thread.is_alive()):
            return
        self._stop_event.clear()
        self._adb_thread = threading.Thread(target=self._listen_adb_loop, daemon=True)
        self._adb_thread.start()

        if QUARTZ_AVAILABLE:
            self._mouse_thread = threading.Thread(target=self._listen_scrcpy_mouse_loop, daemon=True)
            self._mouse_thread.start()

    def stop(self):
        self._stop_event.set()
        if self._proc:
            try:
                self._proc.terminate()
            except Exception:
                pass
            self._proc = None
        self._adb_thread = None
        self._mouse_thread = None

    def _listen_adb_loop(self):
        try:
            if not self.max_x or not self.max_y:
                self._query_digitizer_bounds()

            cmd = [self.adb_path, "-s", self.device_id, "shell", "getevent", "-l"]
            if self.touch_dev:
                cmd.append(self.touch_dev)

            self._proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                # DEVNULL de proposito: sem isto o filho herda o stdin do
                # motor, que e o canal JSON-RPC, e passa a consumir as
                # linhas do protocolo. O sintoma e a chamada seguinte nunca
                # responder — no app, janela travada sem erro.
                stdin=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )

            current_raw_x: int | None = None
            current_raw_y: int | None = None
            touch_down = False
            tap_committed = False
            last_tap_time = 0.0

            for line in self._proc.stdout:
                if self._stop_event.is_set():
                    break

                line = line.strip()
                if not line:
                    continue

                if "ABS_MT_POSITION_X" in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        try:
                            current_raw_x = int(parts[-1], 16)
                        except ValueError:
                            pass
                elif "ABS_MT_POSITION_Y" in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        try:
                            current_raw_y = int(parts[-1], 16)
                        except ValueError:
                            pass
                elif "ABS_MT_TRACKING_ID" in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        val = parts[-1].lower()
                        if val in ("ffffffff", "-1"):
                            touch_down = False
                            tap_committed = False
                        else:
                            touch_down = True
                            tap_committed = False
                elif "BTN_TOUCH" in line:
                    if "DOWN" in line:
                        touch_down = True
                    elif "UP" in line:
                        touch_down = False
                        tap_committed = False
                elif "SYN_REPORT" in line:
                    if touch_down and not tap_committed and current_raw_x is not None and current_raw_y is not None:
                        now = time.time()
                        if now - last_tap_time >= 0.35:
                            screen_w, screen_h = self.screen_size
                            if self.max_x and self.max_x > 0:
                                target_x = min(screen_w, max(0, int((current_raw_x / self.max_x) * screen_w)))
                            else:
                                target_x = min(screen_w, max(0, current_raw_x))

                            if self.max_y and self.max_y > 0:
                                target_y = min(screen_h, max(0, int((current_raw_y / self.max_y) * screen_h)))
                            else:
                                target_y = min(screen_h, max(0, current_raw_y))

                            last_tap_time = now
                            tap_committed = True
                            self.on_tap_callback(target_x, target_y)

        except Exception:
            pass
        finally:
            if self._proc:
                try:
                    self._proc.terminate()
                except Exception:
                    pass
                self._proc = None

    def _get_scrcpy_window(self) -> tuple[int, int, int, int] | None:
        if not QUARTZ_AVAILABLE:
            return None
        try:
            windows = Quartz.CGWindowListCopyWindowInfo(
                Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
                Quartz.kCGNullWindowID,
            )
            for w in windows:
                owner = str(w.get("kCGWindowOwnerName", "")).lower()
                name = str(w.get("kCGWindowName", "")).lower()
                if "scrcpy" in owner or "scrcpy" in name:
                    bounds = w.get("kCGWindowBounds", {})
                    x = int(bounds.get("X", 0))
                    y = int(bounds.get("Y", 0))
                    width = int(bounds.get("Width", 0))
                    height = int(bounds.get("Height", 0))
                    if width > 50 and height > 50:
                        return (x, y, width, height)
        except Exception:
            pass
        return None

    def _listen_scrcpy_mouse_loop(self):
        if not QUARTZ_AVAILABLE:
            return
        was_down = False
        last_tap_time = 0.0

        while not self._stop_event.is_set():
            try:
                is_down = Quartz.CGEventSourceButtonState(
                    Quartz.kCGEventSourceStateCombinedSessionState,
                    Quartz.kCGMouseButtonLeft,
                )

                if is_down and not was_down:
                    now = time.time()
                    if now - last_tap_time >= 0.35:
                        win = self._get_scrcpy_window()
                        if win:
                            win_x, win_y, win_w, win_h = win
                            loc = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
                            if win_x <= loc.x <= (win_x + win_w) and win_y <= loc.y <= (win_y + win_h):
                                rel_x = loc.x - win_x
                                rel_y = loc.y - win_y

                                title_bar_h = 0 if self.borderless else (28 if win_h > 200 else 0)
                                content_h = max(1, win_h - title_bar_h)
                                rel_y_content = max(0, rel_y - title_bar_h)

                                screen_w, screen_h = self.screen_size
                                vp_x, vp_y, vp_w, vp_h = get_video_viewport(win_w, content_h, screen_w, screen_h)

                                if vp_x <= rel_x <= (vp_x + vp_w) and vp_y <= rel_y_content <= (vp_y + vp_h):
                                    target_x = min(screen_w, max(0, int(((rel_x - vp_x) / vp_w) * screen_w)))
                                    target_y = min(screen_h, max(0, int(((rel_y_content - vp_y) / vp_h) * screen_h)))
                                    last_tap_time = now
                                    self.on_tap_callback(target_x, target_y)

                was_down = is_down
            except Exception:
                pass

            time.sleep(0.025)



class IOSPassiveListener:
    def __init__(
        self,
        on_tap_callback: Callable[[int, int], None],
        ios_logical_size: tuple[int, int] = (390, 844),
    ):
        self.on_tap_callback = on_tap_callback
        self.ios_logical_size = ios_logical_size
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self):
        if not QUARTZ_AVAILABLE or (self._thread and self._thread.is_alive()):
            return

        self._stop_event.clear()
        self._thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=0.5)
        self._thread = None

    def _get_simulator_window(self) -> tuple[int, int, int, int] | None:
        try:
            windows = Quartz.CGWindowListCopyWindowInfo(
                Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
                Quartz.kCGNullWindowID,
            )
            for w in windows:
                if "Simulator" in w.get("kCGWindowOwnerName", ""):
                    bounds = w.get("kCGWindowBounds", {})
                    x = int(bounds.get("X", 0))
                    y = int(bounds.get("Y", 0))
                    width = int(bounds.get("Width", 0))
                    height = int(bounds.get("Height", 0))
                    if width > 100 and height > 200:
                        return (x, y, width, height)
        except Exception:
            pass
        return None

    def _listen_loop(self):
        was_down = False
        last_tap_time = 0.0

        while not self._stop_event.is_set():
            try:
                is_down = Quartz.CGEventSourceButtonState(
                    Quartz.kCGEventSourceStateCombinedSessionState,
                    Quartz.kCGMouseButtonLeft,
                )

                if is_down and not was_down:
                    now = time.time()
                    if now - last_tap_time >= 0.4:
                        loc = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
                        win = self._get_simulator_window()
                        if win:
                            win_x, win_y, win_w, win_h = win
                            if win_x <= loc.x <= (win_x + win_w) and win_y <= loc.y <= (win_y + win_h):
                                last_tap_time = now
                                rel_x = loc.x - win_x
                                rel_y = loc.y - win_y

                                title_bar_h = 28 if win_h > 300 else 0
                                content_h = max(1, win_h - title_bar_h)
                                click_y_content = max(0, rel_y - title_bar_h)

                                log_w, log_h = self.ios_logical_size
                                target_x = min(log_w, max(0, int((rel_x / win_w) * log_w)))
                                target_y = min(log_h, max(0, int((click_y_content / content_h) * log_h)))

                                self.on_tap_callback(target_x, target_y)

                was_down = is_down
            except Exception:
                pass

            time.sleep(0.025)

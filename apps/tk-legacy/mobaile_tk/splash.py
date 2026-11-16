import os
import tkinter as tk
from typing import Callable, Optional, Tuple

from PIL import Image, ImageTk

from mobaile_tk import resources

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False


def calculate_apple_geometry(root: Optional[tk.Tk] = None) -> Tuple[int, int, int, int]:
    should_destroy = False
    if root is None:
        root = tk.Tk()
        root.withdraw()
        should_destroy = True

    try:
        screen_w = root.winfo_screenwidth()
        screen_h = root.winfo_screenheight()
    except Exception:
        screen_w = 1440
        screen_h = 900

    if should_destroy:
        try:
            root.destroy()
        except Exception:
            pass

    target_w = 1440
    target_h = 900

    if screen_w < 1500:
        target_w = max(1080, int(screen_w * 0.88))
    if screen_h < 950:
        target_h = max(720, int(screen_h * 0.88))

    pos_x = max(0, (screen_w - target_w) // 2)
    pos_y = max(25, (screen_h - target_h) // 2 - 25)

    return target_w, target_h, pos_x, pos_y


def get_splash_video_path() -> Optional[str]:
    """Delegado ao resolvedor unico de assets (ver mobaile_tk/resources.py)."""
    return resources.splash_video_path()


def get_splash_mascot_path() -> Optional[str]:
    return resources.mascot_path()


def get_splash_bg_path() -> Optional[str]:
    return resources.splash_background_path()


class SplashScreen:
    """
    Splash Screen Oficial do Mo baile.
    Exibe o vídeo splash_app.mp4 na resolução real (1280x720) sem som,
    sem bordas, centralizado na tela, com transição suave para a janela principal.
    Permite pular com clique do mouse, espaço, esc ou enter.
    Inclui watchdog de segurança contra qualquer travamento.
    """

    def __init__(
        self,
        video_path: Optional[str] = None,
        on_complete: Optional[Callable[[], None]] = None,
        width: Optional[int] = None,
        height: Optional[int] = None,
        pos_x: Optional[int] = None,
        pos_y: Optional[int] = None,
        root: Optional[tk.Tk] = None,
        **kwargs,
    ):
        self.video_path = video_path or get_splash_video_path()
        self.on_complete = on_complete or (lambda: None)
        self.main_root = root

        self.cap: Optional[cv2.VideoCapture] = None
        self.current_tk_img: Optional[ImageTk.PhotoImage] = None
        self.delay_ms = 41  # 24 FPS padrão
        self.is_closed = False
        self._watchdog_id: Optional[str] = None

        # Determina resolução nativa real do vídeo (1280x720) e FPS
        vid_w, vid_h, fps = 1280, 720, 24.0
        if CV2_AVAILABLE and self.video_path and os.path.isfile(self.video_path):
            try:
                temp_cap = cv2.VideoCapture(self.video_path)
                if temp_cap.isOpened():
                    w = int(temp_cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                    h = int(temp_cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                    f = temp_cap.get(cv2.CAP_PROP_FPS)
                    if w > 0 and h > 0:
                        vid_w, vid_h = w, h
                    if f and f > 0:
                        fps = f
                temp_cap.release()
            except Exception:
                pass

        self.width = width or vid_w
        self.height = height or vid_h
        self.delay_ms = max(10, int(1000.0 / fps))

        # Janela do splash: borderless (overrideredirect) e centralizada na resolução real
        if self.main_root:
            self.main_root.withdraw()
            self.window = tk.Toplevel(self.main_root)
        else:
            self.window = tk.Tk()

        self.window.overrideredirect(True)
        self.window.configure(bg="#000000")

        try:
            screen_w = self.window.winfo_screenwidth()
            screen_h = self.window.winfo_screenheight()
        except Exception:
            screen_w, screen_h = 1920, 1080

        self.pos_x = pos_x if pos_x is not None else max(0, (screen_w - self.width) // 2)
        self.pos_y = pos_y if pos_y is not None else max(0, (screen_h - self.height) // 2)

        self.window.geometry(f"{self.width}x{self.height}+{self.pos_x}+{self.pos_y}")

        self.canvas = tk.Canvas(
            self.window,
            width=self.width,
            height=self.height,
            bg="#000000",
            highlightthickness=0,
            cursor="hand2",
        )
        self.canvas.pack(fill=tk.BOTH, expand=True)

        # Interações de fechamento rápido / pular splash
        self.canvas.bind("<Button-1>", lambda e: self._close())
        self.window.bind("<Button-1>", lambda e: self._close())
        self.window.bind("<Escape>", lambda e: self._close())
        self.window.bind("<space>", lambda e: self._close())
        self.window.bind("<Return>", lambda e: self._close())

        # Watchdog absoluto: garante que NUNCA fique travado (máximo 11s para vídeo de 10s)
        self._watchdog_id = self.window.after(11000, self._close)

    def start(self):
        if not CV2_AVAILABLE or not self.video_path or not os.path.isfile(self.video_path):
            self._close()
            return

        try:
            self.cap = cv2.VideoCapture(self.video_path)
            if not self.cap.isOpened():
                self._close()
                return
            self._play_next_frame()
            if not self.main_root:
                self.window.mainloop()
        except Exception:
            self._close()

    def _play_next_frame(self):
        if self.is_closed:
            return

        if not self.cap or not self.cap.isOpened():
            self._close()
            return

        try:
            ret, frame = self.cap.read()
            if not ret or frame is None:
                self._close()
                return

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            img = Image.fromarray(rgb)
            if img.size != (self.width, self.height):
                img = img.resize((self.width, self.height), Image.Resampling.BILINEAR)

            self.current_tk_img = ImageTk.PhotoImage(img)
            self.canvas.delete("frame")
            self.canvas.create_image(0, 0, anchor=tk.NW, image=self.current_tk_img, tags="frame")

            self.window.after(self.delay_ms, self._play_next_frame)
        except Exception:
            self._close()

    def _close(self):
        if self.is_closed:
            return
        self.is_closed = True

        if self._watchdog_id:
            try:
                self.window.after_cancel(self._watchdog_id)
            except Exception:
                pass
            self._watchdog_id = None

        if self.cap:
            try:
                self.cap.release()
            except Exception:
                pass
            self.cap = None

        try:
            self.window.destroy()
        except Exception:
            pass

        if self.main_root:
            try:
                self.main_root.deiconify()
                self.main_root.lift()
                self.main_root.focus_force()
            except Exception:
                pass

        try:
            self.on_complete()
        except Exception as e:
            print("Erro no callback on_complete do splash:", e)


def show_splash_if_available(
    on_complete: Callable[[], None],
    root: Optional[tk.Tk] = None,
) -> None:
    video_path = get_splash_video_path()

    if video_path and CV2_AVAILABLE:
        splash = SplashScreen(
            video_path=video_path,
            on_complete=on_complete,
            root=root,
        )
        splash.start()
    else:
        if root:
            try:
                root.deiconify()
                root.lift()
                root.focus_force()
            except Exception:
                pass
        on_complete()

import atexit
import os
import shutil
import subprocess


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

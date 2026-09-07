import queue
import re
import sys
import threading
import time
import tkinter as tk
import tkinter.font as tkfont
from tkinter import filedialog, messagebox, scrolledtext, ttk
from typing import Dict, List, Optional, Tuple

from PIL import Image, ImageDraw, ImageFont, ImageTk

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.input_events import AndroidPassiveListener, IOSPassiveListener
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.adapters.scrcpy import ScrcpyManager
from mobaile.config import settings
from mobaile.services.codegen import CodeGenerator, LocatorStrategy
from mobaile.services.devices import DeviceWatcher
from mobaile.services.hierarchy import UIElement, UIHierarchyParser
from mobaile.services.streaming import RealTimeStreamEngine
from mobaile_tk import resources
from mobaile_tk.dialogs import AutomationExecutionDialog, AutomationStructureDialog
from mobaile_tk.http_viewer import HTTPInspectorFrame
from mobaile_tk.splash import calculate_apple_geometry


def configure_macos_app_identity(app_name: str = "Mo baile"):
    """
    Configura a identidade oficial do aplicativo no macOS (AppKit / Cocoa).
    Garante que o Menu Bar (ao lado do logo da Apple ), o Dock, os atalhos
    e os diálogos de processo exibam 'Mo baile' em vez de 'Python'.
    """
    if sys.platform != "darwin":
        return
    try:
        from AppKit import NSApplication, NSImage
        from Foundation import NSProcessInfo

        info = NSProcessInfo.processInfo()
        info.setProcessName_(app_name)

        app = NSApplication.sharedApplication()
        icon_path = resources.icon_path()
        if icon_path:
            try:
                dock_icon = NSImage.alloc().initWithContentsOfFile_(icon_path)
                if dock_icon:
                    app.setApplicationIconImage_(dock_icon)
            except Exception:
                pass

        main_menu = app.mainMenu()
        if main_menu and main_menu.numberOfItems() > 0:
            app_menu_item = main_menu.itemAtIndex_(0)
            app_menu_item.setTitle_(app_name)
            if app_menu_item.hasSubmenu():
                sub = app_menu_item.submenu()
                sub.setTitle_(app_name)
                for i in range(sub.numberOfItems()):
                    item = sub.itemAtIndex_(i)
                    title = item.title()
                    if "Python" in title:
                        item.setTitle_(title.replace("Python", app_name))
    except Exception:
        pass


# =============================================================================
# DESIGN TOKENS — PALETAS PRAIA (Escuro & Claro) conforme mo_baile_ui_spec.json
# =============================================================================

THEME_PRAIA_DARK = {
    "name": "dark",
    "id": "praia_dark",
    "bg_window": "#1E1E2E",
    "bg_toolbar": "#181825",
    "bg_panel": "#181825",
    "bg_panel_alt": "#1E1E2E",
    "bg_content": "#1E1E2E",
    "bg_subtle": "#181825",
    "bg_control": "#11111B",
    "bg_control_track": "#313244",
    "bg_placeholder": "#1F1F30",
    "bg_terminal": "#0B0B12",
    "bg_device_screen": "#151520",
    "device_bezel": "#11111B",
    "border": "#313244",
    "border_subtle": "#26263A",
    "border_strong": "#45475A",
    "text_primary": "#CDD6F4",
    "text_secondary": "#A6ADC8",
    "text_tertiary": "#7F849C",
    "text_label": "#6C7086",
    "text_disabled": "#585B70",
    "accent": "#89B4FA",
    "accent_pressed": "#74A6F5",
    "accent_on": "#11111B",
    "selection_bg": "#283248",
    "selection_border": "#4A608A",
    "success": "#A6E3A1",
    "success_text": "#A6E3A1",
    "success_bg": "#1B332A",
    "warning": "#F9E2AF",
    "warning_text": "#F9E2AF",
    "warning_bg": "#383020",
    "danger": "#F38BA8",
    # Mapeamento retrocompatível
    "bg_color": "#1E1E2E",
    "panel_bg": "#181825",
    "surface_bg": "#181825",
    "input_bg": "#11111B",
    "fg_color": "#CDD6F4",
    "secondary_fg": "#A6ADC8",
    "accent_color": "#89B4FA",
    "highlight_color": "#89B4FA",
    "border_color": "#313244",
    "btn_bg": "#11111B",
    "btn_hover": "#313244",
    "select_bg": "#313244",
    "code_action_fg": "#89B4FA",
    "code_object_fg": "#94E2D5",
    "badge_active_bg": "#1B332A",
    "badge_active_fg": "#A6E3A1",
    "badge_inactive_bg": "#450A0A",
    "badge_inactive_fg": "#F38BA8",
    "table_bg": "#181825",
    "danger_color": "#F38BA8",
    "syntax": {
        "keyword": "#CBA6F7",
        "function": "#89B4FA",
        "type_class": "#F9E2AF",
        "string": "#A6E3A1",
        "number": "#FAB387",
        "comment": "#6C7086",
        "plain": "#CDD6F4",
        "gutter": "#45475A",
        "gutter_bg": "#181825",
        "file_title_actions": "#89B4FA",
        "file_title_locators": "#94E2D5",
    },
}

THEME_PRAIA_LIGHT = {
    "name": "light",
    "id": "praia_light",
    "bg_window": "#F2FAFD",
    "bg_toolbar": "#DCF0F8",
    "bg_panel": "#E7F5FA",
    "bg_panel_alt": "#EDF7FB",
    "bg_content": "#FFFFFF",
    "bg_subtle": "#F7FCFE",
    "bg_control": "#FFFFFF",
    "bg_control_track": "#CBE4EE",
    "bg_placeholder": "#D9EBF2",
    "bg_terminal": "#15202B",
    "bg_device_screen": "#A8E1F2",
    "device_bezel": "#15202B",
    "border": "#C3E2EE",
    "border_subtle": "#CBE4EE",
    "border_strong": "#8FA9B5",
    "text_primary": "#17323F",
    "text_secondary": "#5A7C8B",
    "text_tertiary": "#7D9EAC",
    "text_label": "#8FA9B5",
    "text_disabled": "#A9C3CE",
    "accent": "#E88BA5",
    "accent_pressed": "#D9738F",
    "accent_on": "#FFFFFF",
    "selection_bg": "#FBE3EA",
    "selection_border": "#EFB6C6",
    "success": "#6BBF6A",
    "success_text": "#3F8F4E",
    "success_bg": "#D6EFD4",
    "warning": "#E0B84B",
    "warning_text": "#8A6A22",
    "warning_bg": "#F6E7C1",
    "danger": "#D9536F",
    # Mapeamento retrocompatível
    "bg_color": "#F2FAFD",
    "panel_bg": "#E7F5FA",
    "surface_bg": "#DCF0F8",
    "input_bg": "#FFFFFF",
    "fg_color": "#17323F",
    "secondary_fg": "#5A7C8B",
    "accent_color": "#E88BA5",
    "highlight_color": "#E88BA5",
    "border_color": "#C3E2EE",
    "btn_bg": "#FFFFFF",
    "btn_hover": "#CBE4EE",
    "select_bg": "#CBE4EE",
    "code_action_fg": "#2E7FA6",
    "code_object_fg": "#D9738F",
    "badge_active_bg": "#D6EFD4",
    "badge_active_fg": "#3F8F4E",
    "badge_inactive_bg": "#FDE8E8",
    "badge_inactive_fg": "#D9536F",
    "table_bg": "#FFFFFF",
    "danger_color": "#D9536F",
    "syntax": {
        "keyword": "#C2557A",
        "function": "#2E7FA6",
        "type_class": "#7B62B8",
        "string": "#3F8F4E",
        "number": "#C97A2E",
        "comment": "#8FA9B5",
        "plain": "#17323F",
        "gutter": "#A9C3CE",
        "gutter_bg": "#F7FCFE",
        "file_title_actions": "#2E7FA6",
        "file_title_locators": "#D9738F",
    },
}

THEME_FREEFORM_DARK = THEME_PRAIA_DARK
THEME_NOTES_LIGHT = THEME_PRAIA_LIGHT


# =============================================================================
# COMPONENTES FLUIDOS NATIVOS MAC (Apple HIG / Xcode Style)
# =============================================================================

def _draw_round_rect(canvas, x1, y1, x2, y2, radius=8, **kwargs):
    """Desenha um retângulo arredondado perfeito em Tkinter Canvas com suavização Bézier."""
    points = [
        x1 + radius, y1,
        x1 + radius, y1,
        x2 - radius, y1,
        x2 - radius, y1,
        x2, y1,
        x2, y1 + radius,
        x2, y1 + radius,
        x2, y2 - radius,
        x2, y2 - radius,
        x2, y2,
        x2 - radius, y2,
        x2 - radius, y2,
        x1 + radius, y2,
        x1 + radius, y2,
        x1, y2,
        x1, y2 - radius,
        x1, y2 - radius,
        x1, y1 + radius,
        x1, y1 + radius,
        x1, y1
    ]
    return canvas.create_polygon(points, **kwargs, smooth=True)


class FluidPillButton(tk.Canvas):
    """
    Botão nativo em formato de pílula (Apple HIG / Canvas).
    Raio 8, padding 6/14, borda sutil #313244, estados hover e pressed.
    Totalmente livre de bezels brancos ou relevo 3D nativos do Tkinter no macOS.
    """
    def __init__(
        self,
        master,
        text="",
        command=None,
        bg="#11111B",
        fg="#CDD6F4",
        activebackground=None,
        activeforeground=None,
        font=("Helvetica", 10),
        padx=14,
        pady=6,
        radius=8,
        border_color=None,
        border_width=1,
        state="normal",
        cursor="hand2",
        **kwargs
    ):
        self.command = command
        self._text = text
        self._font = font
        self._bg_normal = bg
        self._fg_normal = fg
        self._bg_hover = activebackground or "#313244"
        self._fg_hover = activeforeground or fg
        self._border_color = border_color
        self._border_width = border_width
        self._padx = padx
        self._pady = pady
        self._radius = radius
        self._state = state
        self._is_hovered = False
        self._is_pressed = False

        kwargs.pop("relief", None)
        kwargs.pop("highlightthickness", None)
        kwargs.pop("bd", None)

        f = tkfont.Font(font=font)
        text_w = f.measure(text) if text else 0
        text_h = f.metrics("linespace") if text else 14
        w = kwargs.pop("width", text_w + padx * 2)
        h = kwargs.pop("height", text_h + pady * 2)

        master_bg = master.cget("bg") if hasattr(master, "cget") else "#1E1E2E"
        super().__init__(
            master,
            width=w,
            height=h,
            bg=master_bg,
            highlightthickness=0,
            bd=0,
            cursor=cursor if state != "disabled" else "arrow",
            **kwargs
        )

        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<ButtonPress-1>", self._on_press)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.bind("<Configure>", lambda e: self._redraw())
        self._redraw()

    def _on_enter(self, e=None):
        if self._state == "disabled":
            return
        self._is_hovered = True
        self._redraw()

    def _on_leave(self, e=None):
        self._is_hovered = False
        self._is_pressed = False
        self._redraw()

    def _on_press(self, e=None):
        if self._state == "disabled":
            return
        self._is_pressed = True
        self._redraw()

    def _on_release(self, e=None):
        if self._state == "disabled":
            return
        was_pressed = self._is_pressed
        self._is_pressed = False
        self._redraw()
        if was_pressed and self._is_hovered and callable(self.command):
            self.command()

    def _recalc_size(self):
        f = tkfont.Font(font=self._font)
        text_w = f.measure(self._text) if self._text else 0
        text_h = f.metrics("linespace") if self._text else 14
        super().configure(width=text_w + self._padx * 2, height=text_h + self._pady * 2)

    def _redraw(self):
        self.delete("all")
        w = self.winfo_width()
        h = self.winfo_height()
        if w <= 1 or h <= 1:
            try:
                w = int(self.cget("width"))
                h = int(self.cget("height"))
            except Exception:
                w, h = 60, 26

        cur_bg = (
            self._bg_hover
            if (self._is_hovered or self._is_pressed) and self._state != "disabled"
            else self._bg_normal
        )
        cur_fg = self._fg_hover if self._is_hovered and self._state != "disabled" else self._fg_normal
        if self._state == "disabled":
            cur_fg = "#585B70"

        b_col = self._border_color or ("#45475A" if self._is_hovered else "#313244")
        _draw_round_rect(
            self,
            1,
            1,
            w - 1,
            h - 1,
            radius=self._radius,
            fill=cur_bg,
            outline=b_col,
            width=self._border_width,
        )
        self.create_text(w // 2, h // 2, text=self._text, fill=cur_fg, font=self._font)

    def configure(self, **kwargs):
        if "text" in kwargs:
            self._text = kwargs.pop("text")
        if "command" in kwargs:
            self.command = kwargs.pop("command")
        if "bg" in kwargs:
            self._bg_normal = kwargs.pop("bg")
        if "activebackground" in kwargs:
            self._bg_hover = kwargs.pop("activebackground")
        if "fg" in kwargs:
            self._fg_normal = kwargs.pop("fg")
        if "activeforeground" in kwargs:
            self._fg_hover = kwargs.pop("activeforeground")
        if "font" in kwargs:
            self._font = kwargs.pop("font")
        if "state" in kwargs:
            self._state = kwargs.pop("state")
            super().configure(cursor="arrow" if self._state == "disabled" else "hand2")
        kwargs.pop("relief", None)
        if kwargs:
            super().configure(**kwargs)
        self._recalc_size()
        self._redraw()

    config = configure

    def cget(self, key):
        if key == "text":
            return self._text
        if key == "fg":
            return self._fg_normal
        if key == "bg":
            return self._bg_normal
        if key == "state":
            return self._state
        return super().cget(key)

    def __getitem__(self, key):
        return self.cget(key)

    def __setitem__(self, key, value):
        self.configure(**{key: value})

    def invoke(self):
        if self._state != "disabled" and callable(self.command):
            return self.command()


AppleProButton = FluidPillButton


class CanvasSwitch(tk.Canvas):
    """
    Switch pill (Apple HIG) com track 34x20 e knob 16px.
    Substitui os checkboxes nativos Tkinter/Ttk.
    Totalmente integrado com .cget('text'), .cget('fg'), .configure(text=..., fg=...), .invoke()
    """
    def __init__(
        self,
        master,
        text="",
        variable=None,
        command=None,
        bg="#181825",
        fg="#CDD6F4",
        track_on="#89B4FA",
        track_off="#313244",
        knob_on="#11111B",
        knob_off="#FFFFFF",
        font=("Helvetica", 10),
        cursor="hand2",
        **kwargs
    ):
        self.text = text
        self.variable = variable
        self.command = command
        self._bg = bg
        self._fg = fg
        self._track_on = track_on
        self._track_off = track_off
        self._knob_on = knob_on
        self._knob_off = knob_off
        self._font = font
        self._state = kwargs.pop("state", "normal")

        f = tkfont.Font(font=font)
        text_w = f.measure(text) if text else 0
        total_w = 38 + (text_w + 6 if text else 0)
        total_h = 24

        master_bg = master.cget("bg") if hasattr(master, "cget") else bg
        kwargs.pop("selectcolor", None)
        kwargs.pop("activebackground", None)
        kwargs.pop("activeforeground", None)

        super().__init__(
            master,
            width=total_w,
            height=total_h,
            bg=master_bg,
            highlightthickness=0,
            bd=0,
            cursor=cursor if self._state != "disabled" else "arrow",
            **kwargs
        )

        if self.variable is not None:
            self._var_trace = self.variable.trace_add("write", lambda *_: self._redraw())

        self.bind("<Button-1>", self._on_click)
        self.bind("<Enter>", lambda e: self._redraw(hover=True))
        self.bind("<Leave>", lambda e: self._redraw(hover=False))
        self._redraw()

    def _on_click(self, event=None):
        if self._state == "disabled":
            return
        if self.variable is not None:
            val = not bool(self.variable.get())
            self.variable.set(val)
        self._redraw()
        if callable(self.command):
            self.command()

    def _redraw(self, hover=False):
        self.delete("all")
        is_on = bool(self.variable.get()) if self.variable else False
        track_color = self._track_on if is_on else (self._track_off if not hover else "#45475A")
        knob_color = self._knob_on if is_on else self._knob_off

        # Track 34x20
        _draw_round_rect(self, 2, 2, 36, 22, radius=10, fill=track_color, outline="")

        # Knob 16px
        kx = 26 if is_on else 12
        ky = 12
        self.create_oval(kx - 7, ky - 7, kx + 7, ky + 7, fill=knob_color, outline="")

        if self.text:
            self.create_text(42, 12, text=self.text, fill=self._fg, anchor="w", font=self._font)

    def cget(self, key):
        if key == "text":
            return self.text
        if key == "fg":
            return self._fg
        if key == "bg":
            return self._bg
        if key == "state":
            return self._state
        return super().cget(key)

    def configure(self, **kwargs):
        if "text" in kwargs:
            self.text = kwargs.pop("text")
        if "fg" in kwargs:
            self._fg = kwargs.pop("fg")
        if "bg" in kwargs:
            self._bg = kwargs.pop("bg")
            super().configure(bg=self._bg)
        if "state" in kwargs:
            self._state = kwargs.pop("state")
            super().configure(cursor="arrow" if self._state == "disabled" else "hand2")
        if "command" in kwargs:
            self.command = kwargs.pop("command")
        if "variable" in kwargs:
            self.variable = kwargs.pop("variable")
        kwargs.pop("selectcolor", None)
        kwargs.pop("activebackground", None)
        kwargs.pop("activeforeground", None)
        if kwargs:
            super().configure(**kwargs)
        self._redraw()

    config = configure

    def __getitem__(self, key):
        return self.cget(key)

    def __setitem__(self, key, value):
        self.configure(**{key: value})

    def invoke(self):
        self._on_click()


class CanvasGlyphButton(tk.Canvas):
    """
    Botão de Glifo Geométrico para controle de painéis (Xcode / Apple HIG).
    Desenha um ícone de layout de 3 colunas, destacando a coluna esquerda, central ou direita.
    """
    def __init__(self, master, position="left", command=None, bg="#11111B", active=True, **kwargs):
        self.position = position  # "left", "center", "right"
        self.command = command
        self._bg = bg
        self._active = active
        self._hover = False
        master_bg = master.cget("bg") if hasattr(master, "cget") else "#181825"
        super().__init__(master, width=28, height=22, bg=master_bg, bd=0, highlightthickness=0, cursor="hand2", **kwargs)
        self.bind("<Button-1>", self._on_click)
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self._redraw()

    def set_active(self, active: bool):
        self._active = active
        self._redraw()

    def _on_enter(self, event=None):
        self._hover = True
        self._redraw()

    def _on_leave(self, event=None):
        self._hover = False
        self._redraw()

    def _on_click(self, event=None):
        if callable(self.command):
            self.command()

    def cget(self, key):
        if key == "text":
            return f"[{self.position}]"
        return super().cget(key)

    def _redraw(self):
        self.delete("all")
        bg_btn = "#313244" if self._hover else self._bg
        _draw_round_rect(self, 2, 2, 26, 20, radius=4, fill=bg_btn, outline="#313244", width=1)
        accent_col = "#89B4FA" if self._active else "#585B70"
        inactive_col = "#26263A"

        # Left column
        fill_l = accent_col if self.position == "left" and self._active else inactive_col
        self.create_rectangle(5, 5, 10, 17, fill=fill_l, outline="")
        # Center column
        fill_c = accent_col if self.position == "center" and self._active else inactive_col
        self.create_rectangle(11, 5, 17, 17, fill=fill_c, outline="")
        # Right column
        fill_r = accent_col if self.position == "right" and self._active else inactive_col
        self.create_rectangle(18, 5, 23, 17, fill=fill_r, outline="")


def make_chip_image(text: str, bg_color: str, fg_color: str, size: int = 15) -> ImageTk.PhotoImage:
    """Gera um PhotoImage 15x15 arredondado com tipografia semântica [W, V, T, I, B]."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=3, fill=bg_color)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 9)
    except Exception:
        font = None
    if font:
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        draw.text(((size - tw) / 2, (size - th) / 2 - 1), text, fill=fg_color, font=font)
    else:
        draw.text((3, 1), text, fill=fg_color)
    return ImageTk.PhotoImage(img)


def highlight_python_syntax(text_widget: tk.Text, theme_dict: dict):
    """Aplica syntax highlighting profissional (keywords, funções, classes, strings, números, comentários)."""
    code = text_widget.get("1.0", tk.END)
    for tag in ["kw", "fn", "type", "str", "num", "comment"]:
        text_widget.tag_remove(tag, "1.0", tk.END)

    keywords = [
        "def", "class", "return", "from", "import", "self", "assert",
        "if", "in", "and", "or", "not", "is", "None", "True", "False", "as"
    ]
    # Strings
    for m in re.finditer(r'("[^"\\]*(?:\\.[^"\\]*)*"|\'[^\'\\]*(?:\\.[^\'\\]*)*\')', code):
        start = f"1.0 + {m.start()} chars"
        end = f"1.0 + {m.end()} chars"
        text_widget.tag_add("str", start, end)

    # Comments
    for m in re.finditer(r'#.*$', code, re.MULTILINE):
        start = f"1.0 + {m.start()} chars"
        end = f"1.0 + {m.end()} chars"
        text_widget.tag_add("comment", start, end)

    # Keywords
    for kw in keywords:
        for m in re.finditer(r'\b' + kw + r'\b', code):
            start = f"1.0 + {m.start()} chars"
            end = f"1.0 + {m.end()} chars"
            text_widget.tag_add("kw", start, end)

    # Numbers
    for m in re.finditer(r'\b\d+(?:\.\d+)?\b', code):
        start = f"1.0 + {m.start()} chars"
        end = f"1.0 + {m.end()} chars"
        text_widget.tag_add("num", start, end)

    # Functions
    for m in re.finditer(r'def\s+([a-zA-Z_]\w*)', code):
        start = f"1.0 + {m.start(1)} chars"
        end = f"1.0 + {m.end(1)} chars"
        text_widget.tag_add("fn", start, end)

    # Types / Classes
    for m in re.finditer(r'class\s+([a-zA-Z_]\w*)', code):
        start = f"1.0 + {m.start(1)} chars"
        end = f"1.0 + {m.end(1)} chars"
        text_widget.tag_add("type", start, end)


def update_gutter(gutter_widget: tk.Text, text_widget: tk.Text):
    """Sincroniza a numeração de linhas do gutter com o conteúdo do editor."""
    line_count = int(text_widget.index('end-1c').split('.')[0])
    lines_str = "\n".join(str(i) for i in range(1, line_count + 1))
    gutter_widget.config(state="normal")
    gutter_widget.delete("1.0", tk.END)
    gutter_widget.insert("1.0", lines_str)
    gutter_widget.config(state="disabled")


# =============================================================================
# APLICAÇÃO PRINCIPAL: MobileRecorderApp (Mo baile Desktop)
# =============================================================================

class MobileRecorderApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Mo baile")
        configure_macos_app_identity("Mo baile")
        target_w, target_h, pos_x, pos_y = calculate_apple_geometry(self.root)
        self.root.geometry(f"{target_w}x{target_h}+{pos_x}+{pos_y}")
        self.root.minsize(1100, 720)

        # Tema e Estado
        self.current_theme = THEME_PRAIA_DARK.copy()
        self.theme_var = tk.StringVar(value="dark")
        self.bg_color = self.current_theme["bg_window"]
        self.fg_color = self.current_theme["text_primary"]
        self.panel_bg = self.current_theme["bg_panel"]
        self.accent_color = self.current_theme["accent"]
        self.highlight_color = self.current_theme["accent"]

        self.root.configure(bg=self.bg_color)

        # Filas e Pontes
        self.event_queue: queue.Queue = queue.Queue()
        self.active_platform: str = "ios"
        self.selected_device: Optional[str] = None
        self.is_streaming_active: bool = True

        self.platform_var = tk.StringVar(value="ios")
        self.locator_strategy_var = tk.StringVar(value=settings.default_strategy)
        self.page_objects_key_var = tk.StringVar(value=settings.page_objects_key)
        self.passive_mode_var = tk.BooleanVar(value=True)
        self.auto_forward_tap = tk.BooleanVar(value=True)

        self.scrcpy_manager = ScrcpyManager()
        self.adb = ADBBridge()
        self.ios = IOSBridge()
        self.codegen = CodeGenerator(
            page_objects_key=self.page_objects_key_var.get(),
            strategy=LocatorStrategy(self.locator_strategy_var.get()),
        )

        # Variáveis de Imagem e Espelho
        self.current_image: Optional[Image.Image] = None
        self.current_tk_image: Optional[ImageTk.PhotoImage] = None
        self.current_xml: Optional[str] = None
        self.current_scale: Tuple[float, float] = (1.0, 1.0)
        self.image_offset: Tuple[int, int] = (0, 0)
        self.display_size: Tuple[int, int] = (1, 1)
        self.ios_logical_size: Tuple[int, int] = (390, 844)

        # Estado dos Painéis (Toggles ⌥1, ⌥2, ⌥3)
        self.is_mirror_visible: bool = True
        self.is_hierarchy_visible: bool = True
        self.is_workspace_visible: bool = True
        self.is_compact_mirror: bool = False
        self.is_zen_mode: bool = False
        self.is_split_active: bool = True
        self.active_code_tab: str = "actions"
        self.right_view_var = tk.StringVar(value="automation")

        # Dados da Hierarquia e Badges
        self.all_elements: List[UIElement] = []
        self.selected_element: Optional[UIElement] = None
        self.hovered_element: Optional[UIElement] = None
        self.hierarchy_search_var = tk.StringVar(value="")
        self.http_requests_count = 12
        self.analytics_events_count = 4
        self.last_scan_time = "14:21:58"
        self.is_empty_state = False

        self.android_listener: Optional[AndroidPassiveListener] = None
        self.ios_listener: Optional[IOSPassiveListener] = None
        self.http_viewer_win = None

        self._set_window_icon()
        self._build_ui()
        self._bind_shortcuts()

        self.root.after(30, self._process_event_queue)

        self.stream_engine = RealTimeStreamEngine(
            get_frame_fn=self._capture_raw_frame,
            on_frame_callback=self._on_stream_frame_received,
            on_screen_settled_callback=self._on_screen_settled_detected,
            fps=settings.stream_fps,
        )
        self.stream_engine.start()

        self.watcher = DeviceWatcher(
            adb_bridge=self.adb,
            ios_bridge=self.ios,
            on_device_changed=self._on_auto_device_detected,
            target_platform=self.active_platform,
        )
        self.watcher.start()

        self._android_worker_started = False
        self._android_worker_running = True
        self._start_android_background_worker()

        self._refresh_devices()
        self._realign_timer = None
        self.root.protocol("WM_DELETE_WINDOW", self._on_window_closing)
        self.root.bind("<Configure>", self._on_window_configure)

    def _bind_shortcuts(self):
        """Registra atalhos de teclado nativos macOS (⌥1, ⌥2, ⌥3, ⌥⌘F, ⌘F)."""
        self.root.bind("<Alt-Key-1>", lambda e: self._toggle_mirror())
        self.root.bind("<Alt-Key-2>", lambda e: self._toggle_hierarchy())
        self.root.bind("<Alt-Key-3>", lambda e: self._toggle_workspace())
        self.root.bind("<Alt-Command-f>", lambda e: self._restore_all_panels())
        self.root.bind("<Alt-Command-F>", lambda e: self._restore_all_panels())
        self.root.bind("<Command-f>", lambda e: self._focus_hierarchy_search())
        self.root.bind("<Command-F>", lambda e: self._focus_hierarchy_search())

    def _setup_ttk_styles(self, theme_dict: dict):
        try:
            style = ttk.Style()
            tree_bg = theme_dict.get("bg_panel", theme_dict.get("panel_bg", "#181825"))
            style.configure(
                "Treeview",
                background=tree_bg,
                foreground=theme_dict.get("text_primary", theme_dict.get("fg_color", "#CDD6F4")),
                fieldbackground=tree_bg,
                rowheight=24,
                font=("Menlo", 10),
            )
            style.configure(
                "Treeview.Heading",
                background=theme_dict.get("bg_subtle", theme_dict.get("surface_bg", "#181825")),
                foreground=theme_dict.get("text_primary", theme_dict.get("fg_color", "#CDD6F4")),
                font=("Helvetica", 10, "bold"),
            )
            style.configure(
                "TNotebook",
                background=theme_dict.get("bg_panel", theme_dict.get("panel_bg", "#181825")),
                borderwidth=0,
            )
        except Exception:
            pass

    # =========================================================================
    # CONSTRUÇÃO DA INTERFACE VISUAL (Unified Toolbar + 3 Colunas + Status Bar)
    # =========================================================================

    def _build_ui(self):
        t = self.current_theme
        self._setup_ttk_styles(t)

        # 1. TOOLBAR UNIFICADA (52px)
        self.top_bar = tk.Frame(self.root, bg=t["bg_toolbar"], height=52, padx=16)
        self.top_bar.pack(side=tk.TOP, fill=tk.X)
        self.top_bar.pack_propagate(False)

        # 1.1 Traffic Lights macOS (mantido sem dots decorativos, usando os nativos da janela)
        self.traffic_lights_frame = tk.Frame(self.top_bar, bg=t["bg_toolbar"], width=0, height=0)
        self.traffic_lights_frame.pack(side=tk.LEFT, padx=(0, 2))

        # 1.2 Título e Subtítulo
        self.title_box = tk.Frame(self.top_bar, bg=t["bg_toolbar"])
        self.title_box.pack(side=tk.LEFT, padx=(2, 10))
        self.lbl_app_name = tk.Label(
            self.title_box, text="Mo baile", bg=t["bg_toolbar"], fg=t["text_primary"], font=("Helvetica", 12, "bold")
        )
        self.lbl_app_name.pack(side=tk.LEFT)
        self.lbl_app_sub = tk.Label(
            self.title_box, text="Element Recorder", bg=t["bg_toolbar"], fg=t["text_tertiary"], font=("Helvetica", 10)
        )
        self.lbl_app_sub.pack(side=tk.LEFT, padx=(6, 0))

        # 1.3 Seletor de Plataforma (Segmented Control Pill: iOS | Android)
        self.platform_frame = tk.Frame(self.top_bar, bg=t["bg_control_track"], padx=2, pady=2)
        self.platform_frame.pack(side=tk.LEFT, padx=(0, 10))

        self.rb_ios = tk.Radiobutton(
            self.platform_frame,
            text="iOS",
            variable=self.platform_var,
            value="ios",
            command=self._on_manual_platform_switch,
            bg=t["bg_control"],
            fg=t["text_primary"],
            selectcolor=t["bg_control"],
            activebackground=t["bg_control"],
            activeforeground=t["text_primary"],
            indicatoron=False,
            font=("Helvetica", 10, "bold"),
            padx=10,
            pady=2,
            bd=0,
            relief=tk.FLAT,
        )
        self.rb_ios.pack(side=tk.LEFT, padx=1)

        self.rb_android = tk.Radiobutton(
            self.platform_frame,
            text="Android",
            variable=self.platform_var,
            value="android",
            command=self._on_manual_platform_switch,
            bg=t["bg_control_track"],
            fg=t["text_secondary"],
            selectcolor=t["bg_control"],
            activebackground=t["bg_control"],
            activeforeground=t["text_primary"],
            indicatoron=False,
            font=("Helvetica", 10),
            padx=10,
            pady=2,
            bd=0,
            relief=tk.FLAT,
        )
        self.rb_android.pack(side=tk.LEFT, padx=1)

        # 1.4 Dropdown de Dispositivos com Dot de Status
        self.dev_frame = tk.Frame(self.top_bar, bg=t["bg_control"], padx=6, pady=3, highlightthickness=1, highlightbackground=t["border"])
        self.dev_frame.pack(side=tk.LEFT, padx=(0, 10))

        self.device_dot = tk.Label(self.dev_frame, text="●", fg=t["success"], bg=t["bg_control"], font=("Helvetica", 9))
        self.device_dot.pack(side=tk.LEFT, padx=(2, 4))

        self.device_combo = ttk.Combobox(self.dev_frame, state="readonly", width=26)
        self.device_combo.pack(side=tk.LEFT)
        self.device_combo.bind("<<ComboboxSelected>>", self._on_device_selected)

        # 1.5 Toggles: Espelho, Streaming, Tap forward
        self.btn_toggle_mirror = FluidPillButton(
            self.top_bar,
            text="Espelho",
            command=self._toggle_mirror,
            bg=t["accent"],
            fg=t["accent_on"],
            activebackground=t["accent_pressed"],
            font=("Helvetica", 10),
            padx=10,
            pady=3,
        )
        self.btn_toggle_mirror.pack(side=tk.LEFT, padx=4)

        self.btn_toggle_stream = FluidPillButton(
            self.top_bar,
            text="Streaming",
            command=self._toggle_streaming,
            bg=t["accent"],
            fg=t["accent_on"],
            activebackground=t["accent_pressed"],
            font=("Helvetica", 10),
            padx=10,
            pady=3,
        )
        self.btn_toggle_stream.pack(side=tk.LEFT, padx=4)

        self.cb_forward = CanvasSwitch(
            self.top_bar,
            text="Tap forward",
            variable=self.auto_forward_tap,
            bg=t["bg_toolbar"],
            fg=t["text_secondary"],
            track_on=t["accent"],
            track_off=t["bg_control_track"],
            font=("Helvetica", 10),
        )
        self.cb_forward.pack(side=tk.LEFT, padx=4)

        # 1.6 Controles à Direita da Toolbar: Modo Passivo, Zen, Forçar Captura, Toggles de Painel
        self.toolbar_right = tk.Frame(self.top_bar, bg=t["bg_toolbar"])
        self.toolbar_right.pack(side=tk.RIGHT)

        # Grupo de Toggles de Painel (⌥1, ⌥2, ⌥3) com Glifos Geométricos
        self.panel_toggle_frame = tk.Frame(self.toolbar_right, bg=t["bg_control_track"], padx=2, pady=2)
        self.panel_toggle_frame.pack(side=tk.RIGHT, padx=(8, 0))

        self.btn_p1 = CanvasGlyphButton(
            self.panel_toggle_frame, position="left", command=self._toggle_mirror, bg=t["bg_control"], active=True
        )
        self.btn_p1.pack(side=tk.LEFT, padx=1)

        self.btn_p2 = CanvasGlyphButton(
            self.panel_toggle_frame, position="center", command=self._toggle_hierarchy, bg=t["bg_control"], active=True
        )
        self.btn_p2.pack(side=tk.LEFT, padx=1)

        self.btn_p3 = CanvasGlyphButton(
            self.panel_toggle_frame, position="right", command=self._toggle_workspace, bg=t["bg_control"], active=True
        )
        self.btn_p3.pack(side=tk.LEFT, padx=1)

        # Divisor vertical 1px
        tk.Frame(self.toolbar_right, bg=t["border"], width=1, height=22).pack(side=tk.RIGHT, padx=8)

        # Botão Primário: Forçar Captura
        self.btn_cap = FluidPillButton(
            self.toolbar_right,
            text="Forçar Captura",
            command=self._force_capture_now,
            bg=t["accent"],
            fg=t["accent_on"],
            activebackground=t["accent_pressed"],
            font=("Helvetica", 10, "bold"),
            padx=12,
            pady=4,
        )
        self.btn_cap.pack(side=tk.RIGHT, padx=4)

        self.btn_zen = FluidPillButton(
            self.toolbar_right,
            text="Zen",
            command=self._toggle_zen_mode,
            bg=t["bg_control"],
            fg=t["text_secondary"],
            activebackground=t["btn_hover"],
            font=("Helvetica", 10),
            padx=8,
            pady=3,
        )
        self.btn_zen.pack(side=tk.RIGHT, padx=4)

        self.cb_passive = CanvasSwitch(
            self.toolbar_right,
            text="Modo Passivo",
            variable=self.passive_mode_var,
            command=self._on_passive_mode_toggled,
            bg=t["bg_toolbar"],
            fg=t["text_secondary"],
            track_on=t["accent"],
            track_off=t["bg_control_track"],
            font=("Helvetica", 10),
        )
        self.cb_passive.pack(side=tk.RIGHT, padx=4)

        # Elementos retrocompatíveis mantidos ocultos / disponíveis para testes
        self.config_bar = tk.Frame(self.root, bg=t["bg_subtle"], height=0)
        self.config_bar.pack(side=tk.TOP, fill=tk.X)
        self.lbl_key = tk.Label(self.config_bar, text="Chave dos Locators:")
        self.entry_key = tk.Entry(self.config_bar, textvariable=self.page_objects_key_var)
        self.page_objects_key_var.trace_add("write", self._on_key_changed)
        self.lbl_mode = tk.Label(self.config_bar, text="Modo:")
        self.rb_strat_id = tk.Radiobutton(self.config_bar, text="ID", variable=self.locator_strategy_var, value="id", command=self._on_strategy_changed)
        self.rb_strat_xpath = tk.Radiobutton(self.config_bar, text="XPath", variable=self.locator_strategy_var, value="xpath", command=self._on_strategy_changed)
        self.rb_strat_pos = tk.Radiobutton(self.config_bar, text="Coords", variable=self.locator_strategy_var, value="position", command=self._on_strategy_changed)
        self.rb_theme_dark = tk.Radiobutton(self.top_bar, text="Dark", variable=self.theme_var, value="dark", command=self._on_theme_switch)
        self.rb_theme_light = tk.Radiobutton(self.top_bar, text="Light", variable=self.theme_var, value="light", command=self._on_theme_switch)
        self.btn_scrcpy = FluidPillButton(self.top_bar, text="Espelho 60 FPS", command=self._toggle_scrcpy_mirror)
        self.btn_view_http = FluidPillButton(self.top_bar, text="Inspetor HTTP", command=self._open_http_viewer)
        self.auto_status_badge = tk.Label(self.top_bar, text="Streaming Ativo", bg=t["badge_active_bg"], fg=t["badge_active_fg"])
        self.lbl_platform = tk.Label(self.top_bar, text="Plataforma:")
        self.lbl_device = tk.Label(self.top_bar, text="Dispositivo:")

        # 2. WORKSPACE CONTAINER (Contém o Empty State ou as 3 Colunas)
        self.workspace_root = tk.Frame(self.root, bg=t["bg_window"])
        self.workspace_root.pack(fill=tk.BOTH, expand=True)

        # 2.1 PAINEL DE EMPTY STATE (Tela 1b: quando nenhum dispositivo estiver conectado)
        self.empty_state_frame = tk.Frame(self.workspace_root, bg=t["bg_window"])
        self._build_empty_state_ui(self.empty_state_frame)

        # 2.2 WORKSPACE EM 3 COLUNAS (Splitters Redimensionáveis)
        # main_split: divide Coluna 1 (Espelho) de center_right_split (Hierarquia + Workspace)
        self.main_split = tk.PanedWindow(self.workspace_root, orient=tk.HORIZONTAL, bg=t["border"], sashrelief=tk.FLAT, sashwidth=4)
        self.main_split.pack(fill=tk.BOTH, expand=True)

        # COLUNA 1: Espelho Mobile (376-384 px)
        self.left_frame = tk.Frame(self.main_split, bg=t["bg_panel"])
        self.main_split.add(self.left_frame, minsize=280, width=384)
        self._build_mirror_column_ui(self.left_frame)

        # center_right_split: divide Coluna 2 (Hierarquia) de Coluna 3 (Workspace)
        self.center_right_split = tk.PanedWindow(self.main_split, orient=tk.HORIZONTAL, bg=t["border"], sashrelief=tk.FLAT, sashwidth=4)
        self.main_split.add(self.center_right_split, minsize=540)

        # COLUNA 2: Hierarquia de Acessibilidade (290-296 px)
        self.hierarchy_frame = tk.Frame(self.center_right_split, bg=t["bg_window"])
        self.center_right_split.add(self.hierarchy_frame, minsize=250, width=296)
        self._build_hierarchy_column_ui(self.hierarchy_frame)

        # COLUNA 3: Workspace de Código / Rede / Analytics
        self.right_container = tk.Frame(self.center_right_split, bg=t["bg_window"])
        self.center_right_split.add(self.right_container, minsize=480)
        self._build_workspace_column_ui(self.right_container)

        # 3. BARRA DE STATUS INFERIOR (26px, bg_terminal #11111B)
        self.status_bar_frame = tk.Frame(self.root, bg=t["bg_terminal"], height=26, padx=14)
        self.status_bar_frame.pack(side=tk.BOTTOM, fill=tk.X)
        self.status_bar_frame.pack_propagate(False)

        # Daemons à esquerda com dots coloridos
        self.daemons_frame = tk.Frame(self.status_bar_frame, bg=t["bg_terminal"])
        self.daemons_frame.pack(side=tk.LEFT)

        self.dot_wda = tk.Label(self.daemons_frame, text="● WDA 8100", fg=t["success"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.dot_wda.pack(side=tk.LEFT, padx=(0, 10))

        self.dot_adb = tk.Label(self.daemons_frame, text="● ADB server", fg=t["success"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.dot_adb.pack(side=tk.LEFT, padx=(0, 10))

        self.dot_proxy = tk.Label(self.daemons_frame, text="● Proxy MITM 8082", fg=t["accent"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.dot_proxy.pack(side=tk.LEFT, padx=(0, 10))

        self.dot_fa = tk.Label(self.daemons_frame, text="● FA listener", fg=t["warning"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.dot_fa.pack(side=tk.LEFT, padx=(0, 10))

        # Métricas à direita
        self.metrics_frame = tk.Frame(self.status_bar_frame, bg=t["bg_terminal"])
        self.metrics_frame.pack(side=tk.RIGHT)

        self.lbl_metric_coords = tk.Label(self.metrics_frame, text="x 195 · y 640", fg=t["text_tertiary"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.lbl_metric_coords.pack(side=tk.LEFT, padx=6)

        self.lbl_metric_fps = tk.Label(self.metrics_frame, text="58 fps", fg=t["text_tertiary"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.lbl_metric_fps.pack(side=tk.LEFT, padx=6)

        self.lbl_metric_settle = tk.Label(self.metrics_frame, text="settle 42 ms", fg=t["text_tertiary"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.lbl_metric_settle.pack(side=tk.LEFT, padx=6)

        self.lbl_metric_lat = tk.Label(self.metrics_frame, text="latência 118 ms", fg=t["text_tertiary"], bg=t["bg_terminal"], font=("Menlo", 9))
        self.lbl_metric_lat.pack(side=tk.LEFT, padx=6)

        self.status_bar = tk.Label(self.status_bar_frame, text="Pronto.", fg=t["text_tertiary"], bg=t["bg_terminal"], font=("Menlo", 9))

    # =========================================================================
    # COLUNA 1: ESPELHO DO DISPOSITIVO & MOLDURA (Device Frame + Dock)
    # =========================================================================

    def _build_mirror_column_ui(self, parent: tk.Frame):
        t = self.current_theme

        # Header da Coluna 1 (34px)
        self.mirror_header = tk.Frame(parent, bg=t["bg_panel"], height=34, padx=14)
        self.mirror_header.pack(fill=tk.X, side=tk.TOP)
        self.mirror_header.pack_propagate(False)

        self.lbl_mirror_title = tk.Label(
            self.mirror_header, text="ESPELHO · TEMPO REAL", bg=t["bg_panel"], fg=t["text_label"], font=("Helvetica", 9, "bold")
        )
        self.lbl_mirror_title.pack(side=tk.LEFT)

        self.lbl_fps_badge = tk.Label(
            self.mirror_header, text="58 FPS", bg=t["bg_panel"], fg=t["success"], font=("Menlo", 9, "bold")
        )
        self.lbl_fps_badge.pack(side=tk.RIGHT)

        tk.Label(self.mirror_header, text="⌥1", bg=t["bg_panel"], fg=t["text_tertiary"], font=("Helvetica", 9)).pack(side=tk.RIGHT, padx=6)

        # Moldura do Smartphone (Bezel) centralizada
        self.bezel_container = tk.Frame(parent, bg=t["bg_panel"])
        self.bezel_container.pack(fill=tk.BOTH, expand=True, padx=10, pady=8)

        self.bezel_canvas = tk.Canvas(self.bezel_container, bg=t["bg_panel"], highlightthickness=0, bd=0)
        self.bezel_canvas.pack(fill=tk.BOTH, expand=True)

        # Canvas da Tela do Smartphone
        self.screen_canvas = tk.Canvas(
            self.bezel_canvas,
            bg=t["bg_device_screen"],
            width=264,
            height=530,
            highlightthickness=0,
            bd=0,
            cursor="crosshair",
        )
        self.screen_window_id = self.bezel_canvas.create_window(132, 265, window=self.screen_canvas)

        self.screen_canvas.bind("<Button-1>", self._on_canvas_click)
        self.screen_canvas.bind("<Motion>", self._on_canvas_motion)
        self.screen_canvas.bind("<Leave>", self._on_canvas_leave)
        self.screen_canvas.bind("<Configure>", self._on_canvas_resize)
        self.bezel_canvas.bind("<Configure>", self._on_bezel_resize)

        # Dock Inferior de Ações Rápidas (‹ Voltar, Home, Girar, Screenshot) - Ancorado no Rodapé
        self.device_dock = tk.Frame(parent, bg=t["bg_panel"], padx=10, pady=8)
        self.device_dock.pack(fill=tk.X, side=tk.BOTTOM)

        dock_buttons = [
            ("‹ Voltar", self._dock_back),
            ("Home", self._dock_home),
            ("Girar", self._dock_rotate),
            ("Screenshot", self._force_capture_now),
        ]
        for label, cmd in dock_buttons:
            btn = FluidPillButton(
                self.device_dock,
                text=label,
                command=cmd,
                bg=t["bg_control"],
                fg=t["text_secondary"],
                activebackground=t["btn_hover"],
                font=("Helvetica", 9),
                padx=8,
                pady=4,
            )
            btn.pack(side=tk.LEFT, expand=True, padx=2)

        # Card de Correlação (Exibido quando na aba Rede/Analytics)
        self.correlation_card_frame = tk.Frame(parent, bg=t["bg_panel"], padx=14, pady=8)
        lbl_correl = tk.Label(self.correlation_card_frame, text="CORRELAÇÃO", bg=t["bg_panel"], fg=t["text_label"], font=("Helvetica", 9, "bold"))
        lbl_correl.pack(anchor="w")

        self.correl_box = tk.Frame(self.correlation_card_frame, bg=t["bg_control"], padx=8, pady=6, highlightthickness=1, highlightbackground=t["border"])
        self.correl_box.pack(fill=tk.X, pady=4)

        self.lbl_correl_action = tk.Label(self.correl_box, text="tap · btn_continuar", bg=t["bg_control"], fg=t["accent"], font=("Menlo", 9, "bold"), anchor="w")
        self.lbl_correl_action.pack(fill=tk.X)
        self.lbl_correl_reqs = tk.Label(self.correl_box, text="disparou 3 requisições", bg=t["bg_control"], fg=t["text_secondary"], font=("Helvetica", 9), anchor="w")
        self.lbl_correl_reqs.pack(fill=tk.X)
        self.lbl_correl_fa = tk.Label(self.correl_box, text="e 2 eventos de analytics", bg=t["bg_control"], fg=t["text_secondary"], font=("Helvetica", 9), anchor="w")
        self.lbl_correl_fa.pack(fill=tk.X)

        self.btn_gen_contract = FluidPillButton(
            self.correlation_card_frame,
            text="Gerar asserção de contrato",
            command=self._generate_contract_assertion,
            bg=t["bg_control"],
            fg=t["text_primary"],
            font=("Helvetica", 9),
            padx=10,
            pady=3,
        )
        self.btn_gen_contract.pack(fill=tk.X, pady=2)

    # =========================================================================
    # COLUNA 2: HIERARQUIA DE ACESSIBILIDADE & ATRIBUTOS (Árvore com Chips)
    # =========================================================================

    def _build_hierarchy_column_ui(self, parent: tk.Frame):
        t = self.current_theme

        # Header 34px
        self.hierarchy_header = tk.Frame(parent, bg=t["bg_window"], height=34, padx=14)
        self.hierarchy_header.pack(fill=tk.X, side=tk.TOP)
        self.hierarchy_header.pack_propagate(False)

        tk.Label(self.hierarchy_header, text="HIERARQUIA DE ACESSIBILIDADE", bg=t["bg_window"], fg=t["text_label"], font=("Helvetica", 9, "bold")).pack(side=tk.LEFT)
        tk.Label(self.hierarchy_header, text="⌥2", bg=t["bg_window"], fg=t["text_tertiary"], font=("Helvetica", 9)).pack(side=tk.RIGHT)

        # Barra de Busca com ⌘F
        search_bar = tk.Frame(parent, bg=t["bg_window"], padx=10, pady=6)
        search_bar.pack(fill=tk.X, side=tk.TOP)

        search_box = tk.Frame(search_bar, bg=t["bg_control"], padx=6, pady=3, highlightthickness=1, highlightbackground=t["border"])
        search_box.pack(fill=tk.X)

        tk.Label(search_box, text="⌕", bg=t["bg_control"], fg=t["text_label"], font=("Helvetica", 10)).pack(side=tk.LEFT)
        self.entry_search_hierarchy = tk.Entry(
            search_box,
            textvariable=self.hierarchy_search_var,
            bg=t["bg_control"],
            fg=t["text_primary"],
            insertbackground="white",
            relief=tk.FLAT,
            font=("Helvetica", 10),
        )
        self.entry_search_hierarchy.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)
        self.hierarchy_search_var.trace_add("write", lambda *_: self._apply_hierarchy_filter())
        tk.Label(search_box, text="⌘F", bg=t["bg_control"], fg=t["text_tertiary"], font=("Menlo", 8)).pack(side=tk.RIGHT)

        # Árvore de Hierarquia
        self.tree_container = tk.Frame(parent, bg=t["bg_panel"])
        self.tree_container.pack(fill=tk.BOTH, expand=True)

        self.hierarchy_tree = ttk.Treeview(self.tree_container, show="tree", selectmode="browse")
        scroll_y = ttk.Scrollbar(self.tree_container, orient=tk.VERTICAL, command=self.hierarchy_tree.yview)
        self.hierarchy_tree.configure(yscrollcommand=scroll_y.set)

        self.hierarchy_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scroll_y.pack(side=tk.RIGHT, fill=tk.Y)
        self.hierarchy_tree.bind("<<TreeviewSelect>>", self._on_tree_select)

        # Rodapé Fixo de Atributos (Grid 82px / 1fr)
        self.attrib_footer = tk.Frame(parent, bg=t["bg_panel"], padx=12, pady=8, highlightthickness=1, highlightbackground=t["border"])
        self.attrib_footer.pack(fill=tk.X, side=tk.BOTTOM)

        attrib_header = tk.Frame(self.attrib_footer, bg=t["bg_panel"])
        attrib_header.pack(fill=tk.X, pady=(0, 4))
        tk.Label(attrib_header, text="ATRIBUTOS", bg=t["bg_panel"], fg=t["text_label"], font=("Helvetica", 9, "bold")).pack(side=tk.LEFT)

        btn_copy_all = tk.Label(attrib_header, text="Copiar tudo", bg=t["bg_panel"], fg=t["accent"], font=("Helvetica", 9, "bold"), cursor="hand2")
        btn_copy_all.pack(side=tk.RIGHT)
        btn_copy_all.bind("<Button-1>", lambda e: self._copy_all_attributes())

        self.attrib_grid = tk.Frame(self.attrib_footer, bg=t["bg_panel"])
        self.attrib_grid.pack(fill=tk.X)

        self.attrib_labels: Dict[str, tk.Label] = {}
        fields = ["type", "name", "label", "bounds", "center", "enabled"]
        for row_idx, key in enumerate(fields):
            lbl_k = tk.Label(self.attrib_grid, text=key, bg=t["bg_panel"], fg=t["text_label"], font=("Menlo", 9), anchor="w", width=8)
            lbl_k.grid(row=row_idx, column=0, sticky="w", pady=1)
            lbl_v = tk.Label(self.attrib_grid, text="—", bg=t["bg_panel"], fg=t["text_primary"], font=("Menlo", 9), anchor="w")
            lbl_v.grid(row=row_idx, column=1, sticky="w", pady=1, padx=(6, 0))
            self.attrib_labels[key] = lbl_v

    # =========================================================================
    # COLUNA 3: WORKSPACE DE CÓDIGO (Page Objects) & INSPEÇÃO DE REDE / ANALYTICS
    # =========================================================================

    def _build_workspace_column_ui(self, parent: tk.Frame):
        t = self.current_theme

        # Barra de Abas do Workspace (40px)
        self.workspace_tab_bar = tk.Frame(parent, bg=t["bg_window"], height=40, padx=14)
        self.workspace_tab_bar.pack(fill=tk.X, side=tk.TOP)
        self.workspace_tab_bar.pack_propagate(False)

        # Seletor de Visão Principal: [ Page Objects | Rede HTTP 12 | Analytics 4 ]
        self.view_segmented = tk.Frame(self.workspace_tab_bar, bg=t["bg_control_track"], padx=2, pady=2)
        self.view_segmented.pack(side=tk.LEFT)

        self.btn_seg_auto = FluidPillButton(
            self.view_segmented, text="Page Objects", command=lambda: self._set_right_view("automation"),
            bg=t["bg_control"], fg=t["text_primary"], font=("Helvetica", 9, "bold"), padx=10, pady=2
        )
        self.btn_seg_auto.pack(side=tk.LEFT, padx=1)

        self.btn_seg_net = FluidPillButton(
            self.view_segmented, text=f"Rede HTTP {self.http_requests_count}", command=lambda: self._set_right_view("network"),
            bg=t["bg_control_track"], fg=t["text_secondary"], font=("Helvetica", 9), padx=10, pady=2
        )
        self.btn_seg_net.pack(side=tk.LEFT, padx=1)

        self.btn_seg_analytics = FluidPillButton(
            self.view_segmented, text=f"Analytics {self.analytics_events_count}", command=lambda: self._set_right_view("analytics"),
            bg=t["bg_control_track"], fg=t["text_secondary"], font=("Helvetica", 9), padx=10, pady=2
        )
        self.btn_seg_analytics.pack(side=tk.LEFT, padx=1)

        # Estratégia de Localizador: [ ID | XPath | Coords ]
        self.strat_segmented = tk.Frame(self.workspace_tab_bar, bg=t["bg_control_track"], padx=2, pady=2)
        self.strat_segmented.pack(side=tk.LEFT, padx=(10, 0))

        self.btn_strat_id = FluidPillButton(self.strat_segmented, text="ID", command=lambda: self._set_strategy("id"), bg=t["bg_control"], fg=t["text_primary"], font=("Helvetica", 9), padx=8, pady=2)
        self.btn_strat_id.pack(side=tk.LEFT, padx=1)

        self.btn_strat_xpath = FluidPillButton(self.strat_segmented, text="XPath", command=lambda: self._set_strategy("xpath"), bg=t["bg_control_track"], fg=t["text_secondary"], font=("Helvetica", 9), padx=8, pady=2)
        self.btn_strat_xpath.pack(side=tk.LEFT, padx=1)

        self.btn_strat_coords = FluidPillButton(self.strat_segmented, text="Coords", command=lambda: self._set_strategy("position"), bg=t["bg_control_track"], fg=t["text_secondary"], font=("Helvetica", 9), padx=8, pady=2)
        self.btn_strat_coords.pack(side=tk.LEFT, padx=1)

        # Ações à Direita: Estrutura, Split, ▶ Rodar
        self.actions_bar_right = tk.Frame(self.workspace_tab_bar, bg=t["bg_window"])
        self.actions_bar_right.pack(side=tk.RIGHT)

        self.btn_run_automation = FluidPillButton(
            self.actions_bar_right, text="▶ Rodar", command=self._on_run_automation,
            bg=t["success"], fg="#11111B", activebackground="#6BBF6A", font=("Helvetica", 9, "bold"), padx=12, pady=3
        )
        self.btn_run_automation.pack(side=tk.RIGHT, padx=(4, 0))

        self.btn_toggle_split = FluidPillButton(
            self.actions_bar_right, text="Split", command=self._toggle_code_split,
            bg=t["bg_control"], fg=t["text_secondary"], font=("Helvetica", 9), padx=8, pady=3
        )
        self.btn_toggle_split.pack(side=tk.RIGHT, padx=4)

        self.btn_view_structure = FluidPillButton(
            self.actions_bar_right, text="Estrutura", command=self._on_view_structure,
            bg=t["bg_control"], fg=t["text_secondary"], font=("Helvetica", 9), padx=8, pady=3
        )
        self.btn_view_structure.pack(side=tk.RIGHT, padx=4)

        # Sub-abas ocultas para teste
        self.code_subtabs_frame = tk.Frame(self.workspace_tab_bar)
        self.btn_subtab_actions = FluidPillButton(self.code_subtabs_frame, text="Ações", command=lambda: self._set_code_subtab("actions"))
        self.btn_subtab_objects = FluidPillButton(self.code_subtabs_frame, text="Objetos", command=lambda: self._set_code_subtab("objects"))

        # VISÃO 1: PAGE OBJECTS (Editores de Ações & Objetos)
        self.automation_view = tk.Frame(parent, bg=t["bg_window"])
        self.automation_view.pack(fill=tk.BOTH, expand=True)

        self.right_split = tk.PanedWindow(self.automation_view, orient=tk.HORIZONTAL, bg=t["border"], sashrelief=tk.FLAT, sashwidth=4)
        self.right_split.pack(fill=tk.BOTH, expand=True)

        # Pane Ações (pages/)
        self.actions_frame = tk.Frame(self.right_split, bg=t["bg_window"])
        self.right_split.add(self.actions_frame, minsize=260)

        act_hdr = tk.Frame(self.actions_frame, bg=t["bg_panel"], height=32, padx=12)
        act_hdr.pack(fill=tk.X, side=tk.TOP)
        act_hdr.pack_propagate(False)
        self.lbl_act_title = tk.Label(act_hdr, text="pages/onboarding_credito.py", bg=t["bg_panel"], fg=t["syntax"]["file_title_actions"], font=("Menlo", 10, "bold"))
        self.lbl_act_title.pack(side=tk.LEFT)

        self.btn_save_act = FluidPillButton(
            act_hdr, text="Salvar", command=lambda: self._save_text_to_file(self.actions_text, "page_actions.py"),
            bg=t["bg_control"], fg=t["text_secondary"], activebackground=t["btn_hover"], font=("Helvetica", 9), padx=10, pady=2
        )
        self.btn_save_act.pack(side=tk.RIGHT, padx=(4, 0))

        self.btn_copy_act = FluidPillButton(
            act_hdr, text="Copiar", command=lambda: self._copy_text(self.actions_text),
            bg=t["bg_control"], fg=t["text_secondary"], activebackground=t["btn_hover"], font=("Helvetica", 9), padx=10, pady=2
        )
        self.btn_copy_act.pack(side=tk.RIGHT, padx=2)

        # Editor de Ações com Gutter Colado (Glued Gutter)
        act_body = tk.Frame(self.actions_frame, bg=t["bg_window"])
        act_body.pack(fill=tk.BOTH, expand=True)

        self.actions_gutter = tk.Text(
            act_body,
            width=4,
            bg=t["syntax"]["gutter_bg"],
            fg=t["syntax"]["gutter"],
            font=("Menlo", 11),
            spacing1=3,
            spacing3=3,
            bd=0,
            highlightthickness=0,
            padx=6,
            pady=8,
            relief=tk.FLAT,
            state="disabled",
            cursor="arrow",
        )
        self.actions_gutter.pack(side=tk.LEFT, fill=tk.Y)

        self.actions_text = tk.Text(
            act_body,
            wrap=tk.NONE,
            bg=t["bg_window"],
            fg=t["syntax"]["plain"],
            insertbackground="white" if t["name"] == "dark" else "black",
            font=("Menlo", 11),
            spacing1=3,
            spacing3=3,
            padx=10,
            pady=8,
            bd=0,
            highlightthickness=0,
            relief=tk.FLAT,
        )
        self.actions_scroll_y = ttk.Scrollbar(act_body, orient=tk.VERTICAL, command=self._scroll_both_act)
        self.actions_text.configure(yscrollcommand=self._sync_scroll_act)
        self.actions_scroll_y.pack(side=tk.RIGHT, fill=tk.Y)
        self.actions_text.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)
        self.actions_text.bind("<KeyRelease>", lambda e: self._on_code_changed(self.actions_text, self.actions_gutter))

        # Pane Objetos (locators/)
        self.objects_frame = tk.Frame(self.right_split, bg=t["bg_window"])
        self.right_split.add(self.objects_frame, minsize=260)

        obj_hdr = tk.Frame(self.objects_frame, bg=t["bg_panel"], height=32, padx=12)
        obj_hdr.pack(fill=tk.X, side=tk.TOP)
        obj_hdr.pack_propagate(False)
        self.lbl_obj_title = tk.Label(obj_hdr, text="locators/onboarding_credito.py", bg=t["bg_panel"], fg=t["syntax"]["file_title_locators"], font=("Menlo", 10, "bold"))
        self.lbl_obj_title.pack(side=tk.LEFT)

        self.btn_clear = FluidPillButton(
            obj_hdr, text="Limpar", command=self._clear_both,
            bg=t["bg_control"], fg=t["danger"], activebackground=t.get("badge_inactive_bg", "#450A0A"), font=("Helvetica", 9), padx=10, pady=2
        )
        self.btn_clear.pack(side=tk.RIGHT, padx=(4, 0))

        self.btn_save_obj = FluidPillButton(
            obj_hdr, text="Salvar", command=lambda: self._save_text_to_file(self.objects_text, "page_objects.py"),
            bg=t["bg_control"], fg=t["text_secondary"], activebackground=t["btn_hover"], font=("Helvetica", 9), padx=10, pady=2
        )
        self.btn_save_obj.pack(side=tk.RIGHT, padx=2)

        self.btn_copy_obj = FluidPillButton(
            obj_hdr, text="Copiar", command=lambda: self._copy_text(self.objects_text),
            bg=t["bg_control"], fg=t["text_secondary"], activebackground=t["btn_hover"], font=("Helvetica", 9), padx=10, pady=2
        )
        self.btn_copy_obj.pack(side=tk.RIGHT, padx=2)

        # Editor de Objetos com Gutter Colado (Glued Gutter)
        obj_body = tk.Frame(self.objects_frame, bg=t["bg_window"])
        obj_body.pack(fill=tk.BOTH, expand=True)

        self.objects_gutter = tk.Text(
            obj_body,
            width=4,
            bg=t["syntax"]["gutter_bg"],
            fg=t["syntax"]["gutter"],
            font=("Menlo", 11),
            spacing1=3,
            spacing3=3,
            bd=0,
            highlightthickness=0,
            padx=6,
            pady=8,
            relief=tk.FLAT,
            state="disabled",
            cursor="arrow",
        )
        self.objects_gutter.pack(side=tk.LEFT, fill=tk.Y)

        self.objects_text = tk.Text(
            obj_body,
            wrap=tk.NONE,
            bg=t["bg_window"],
            fg=t["syntax"]["plain"],
            insertbackground="white" if t["name"] == "dark" else "black",
            font=("Menlo", 11),
            spacing1=3,
            spacing3=3,
            padx=10,
            pady=8,
            bd=0,
            highlightthickness=0,
            relief=tk.FLAT,
        )
        self.objects_scroll_y = ttk.Scrollbar(obj_body, orient=tk.VERTICAL, command=self._scroll_both_obj)
        self.objects_text.configure(yscrollcommand=self._sync_scroll_obj)
        self.objects_scroll_y.pack(side=tk.RIGHT, fill=tk.Y)
        self.objects_text.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)
        self.objects_text.bind("<KeyRelease>", lambda e: self._on_code_changed(self.objects_text, self.objects_gutter))

        # Tags de Sintaxe nos Editores
        for txt in [self.actions_text, self.objects_text]:
            txt.tag_config("kw", foreground=t["syntax"]["keyword"])
            txt.tag_config("fn", foreground=t["syntax"]["function"])
            txt.tag_config("type", foreground=t["syntax"]["type_class"])
            txt.tag_config("str", foreground=t["syntax"]["string"])
            txt.tag_config("num", foreground=t["syntax"]["number"])
            txt.tag_config("comment", foreground=t["syntax"]["comment"])

        self._insert_initial_headers()

        # Rodapé de Detalhes do Passo Gerado (38px)
        self.code_footer = tk.Frame(self.automation_view, bg=t["bg_panel"], height=38, padx=14, highlightthickness=1, highlightbackground=t["border"])
        self.code_footer.pack(fill=tk.X, side=tk.BOTTOM)
        self.code_footer.pack_propagate(False)

        self.detail_label = tk.Label(
            self.code_footer,
            text="passo 01 · ação tap · elemento pronto",
            bg=t["bg_panel"],
            fg=t["text_secondary"],
            font=("Menlo", 9),
            anchor="w",
        )
        self.detail_label.pack(side=tk.LEFT)

        self.lbl_code_sync = tk.Label(
            self.code_footer,
            text="código sincronizado",
            bg=t["bg_panel"],
            fg=t["success"],
            font=("Menlo", 9, "bold"),
        )
        self.lbl_code_sync.pack(side=tk.RIGHT)

        # VISÃO 2: INSPETOR DE REDE HTTP & ANALYTICS (Componente Embutido)
        def get_current_device():
            return self.active_platform, self.selected_device

        self.network_view = HTTPInspectorFrame(
            parent,
            adb_bridge=self.adb,
            get_device_callback=get_current_device,
            theme_dict=self.current_theme,
        )

    # =========================================================================
    # PAINEL DE ESTADO VAZIO (Empty State — Tela 1b)
    # =========================================================================

    def _build_empty_state_ui(self, parent: tk.Frame):
        t = self.current_theme

        center_card = tk.Frame(parent, bg=t["bg_window"])
        center_card.pack(expand=True, padx=40, pady=30)

        # Placeholder do Celular Desconectado (150x300 com borda tracejada)
        placeholder = tk.Canvas(center_card, width=150, height=300, bg=t["bg_placeholder"], highlightthickness=1, highlightbackground=t["border"])
        placeholder.pack(pady=(0, 20))
        # Linhas diagonais
        for i in range(-300, 300, 16):
            placeholder.create_line(i, 0, i + 300, 300, fill=t["border"], width=1)
        placeholder.create_text(75, 150, text="sem sinal", fill=t["text_disabled"], font=("Menlo", 10, "bold"))

        lbl_empty_t = tk.Label(center_card, text="Conecte um dispositivo para começar", bg=t["bg_window"], fg=t["text_primary"], font=("Helvetica", 16, "bold"))
        lbl_empty_t.pack()

        lbl_empty_s = tk.Label(
            center_card,
            text="O Mo baile detecta simuladores, emuladores e aparelhos físicos automaticamente a cada 1,5 s.",
            bg=t["bg_window"],
            fg=t["text_tertiary"],
            font=("Helvetica", 11),
        )
        lbl_empty_s.pack(pady=(4, 20))

        # Cards Diagnósticos: iOS e Android
        diag_grid = tk.Frame(center_card, bg=t["bg_window"])
        diag_grid.pack(fill=tk.X)

        # Card iOS
        card_ios = tk.Frame(diag_grid, bg=t["bg_panel"], padx=16, pady=12, highlightthickness=1, highlightbackground=t["border"])
        card_ios.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=8)

        tk.Label(card_ios, text="● iOS · WebDriverAgent", bg=t["bg_panel"], fg="#0A84FF", font=("Helvetica", 11, "bold"), anchor="w").pack(fill=tk.X)
        tk.Label(card_ios, text="✓ Xcode Command Line Tools", bg=t["bg_panel"], fg=t["success"], font=("Helvetica", 9), anchor="w").pack(fill=tk.X, pady=2)
        tk.Label(card_ios, text="✓ Simulador disponível", bg=t["bg_panel"], fg=t["success"], font=("Helvetica", 9), anchor="w").pack(fill=tk.X, pady=2)
        tk.Label(card_ios, text="✕ WDA na porta 8100", bg=t["bg_panel"], fg=t["danger"], font=("Helvetica", 9), anchor="w").pack(fill=tk.X, pady=2)

        FluidPillButton(card_ios, text="Iniciar WDA", command=self._refresh_devices, bg=t["accent"], fg=t["accent_on"], font=("Helvetica", 9, "bold"), padx=10, pady=2).pack(anchor="w", pady=(8, 0))

        # Card Android
        card_and = tk.Frame(diag_grid, bg=t["bg_panel"], padx=16, pady=12, highlightthickness=1, highlightbackground=t["border"])
        card_and.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=8)

        tk.Label(card_and, text="● Android · ADB", bg=t["bg_panel"], fg="#34C759", font=("Helvetica", 11, "bold"), anchor="w").pack(fill=tk.X)
        tk.Label(card_and, text="✓ adb server ativo (5037)", bg=t["bg_panel"], fg=t["success"], font=("Helvetica", 9), anchor="w").pack(fill=tk.X, pady=2)
        tk.Label(card_and, text="! Nenhum aparelho autorizado", bg=t["bg_panel"], fg=t["warning"], font=("Helvetica", 9), anchor="w").pack(fill=tk.X, pady=2)
        tk.Label(card_and, text="· Conecte via USB e aceite depuração", bg=t["bg_panel"], fg=t["text_tertiary"], font=("Helvetica", 9), anchor="w").pack(fill=tk.X, pady=2)

        FluidPillButton(card_and, text="adb devices", command=self._refresh_devices, bg=t["bg_control"], fg=t["text_primary"], font=("Helvetica", 9), padx=10, pady=2).pack(anchor="w", pady=(8, 0))

        self.lbl_scan_status = tk.Label(
            center_card, text=f"procurando dispositivos… · último scan {self.last_scan_time}", bg=t["bg_window"], fg=t["text_disabled"], font=("Menlo", 9)
        )
        self.lbl_scan_status.pack(pady=(20, 0))

    # =========================================================================
    # LÓGICA DE INTERAÇÃO NO CANVAS: RIPPLE, HOVER TAG E CLIQUE
    # =========================================================================

    def _on_canvas_motion(self, event):
        if not self.current_image or not self.current_xml:
            return

        offset_x, offset_y = self.image_offset
        disp_w, disp_h = self.display_size
        click_x = event.x - offset_x
        click_y = event.y - offset_y

        if click_x < 0 or click_x > disp_w or click_y < 0 or click_y > disp_h:
            self._clear_hover_overlay()
            return

        plat = self.active_platform
        if plat == "ios":
            log_w, log_h = self.ios_logical_size
            target_x = int(click_x * (log_w / disp_w))
            target_y = int(click_y * (log_h / disp_h))
        else:
            scale_x, scale_y = self.current_scale
            target_x = int(click_x * scale_x)
            target_y = int(click_y * scale_y)

        self.lbl_metric_coords.config(text=f"x {target_x} · y {target_y}")

        elem = UIHierarchyParser.find_element_at(self.current_xml, target_x, target_y)
        if elem and elem != self.hovered_element:
            self.hovered_element = elem
            self._draw_hover_overlay(elem)
        elif not elem:
            self._clear_hover_overlay()

    def _draw_hover_overlay(self, elem: UIElement):
        self.screen_canvas.delete("hover_overlay")
        x1, y1, x2, y2 = elem.bounds
        off_x, off_y = self.image_offset
        disp_w, disp_h = self.display_size

        plat = self.active_platform
        if plat == "ios":
            log_w, log_h = self.ios_logical_size
            cx1 = int(x1 * (disp_w / log_w)) + off_x
            cy1 = int(y1 * (disp_h / log_h)) + off_y
            cx2 = int(x2 * (disp_w / log_w)) + off_x
            cy2 = int(y2 * (disp_h / log_h)) + off_y
        else:
            scale_x, scale_y = self.current_scale
            cx1 = int(x1 / scale_x) + off_x
            cy1 = int(y1 / scale_y) + off_y
            cx2 = int(x2 / scale_x) + off_x
            cy2 = int(y2 / scale_y) + off_y

        accent = self.current_theme.get("accent", "#89B4FA")
        # Bounding box
        self.screen_canvas.create_rectangle(cx1 - 2, cy1 - 2, cx2 + 2, cy2 + 2, outline=accent, width=2, tags="hover_overlay")

        # Etiqueta flutuante (<id> · <hit_target>pt)
        h_pt = max(20, y2 - y1)
        tag_text = f"{elem.display_name[:14]} · {h_pt}pt"
        tag_y = max(10, cy1 - 18)
        tag_w = len(tag_text) * 7 + 8
        self.screen_canvas.create_rectangle(cx1, tag_y, cx1 + tag_w, tag_y + 16, fill=accent, outline="", tags="hover_overlay")
        self.screen_canvas.create_text(cx1 + 4, tag_y + 8, text=tag_text, anchor="w", fill="#11111B", font=("Menlo", 8, "bold"), tags="hover_overlay")

    def _clear_hover_overlay(self):
        self.hovered_element = None
        self.screen_canvas.delete("hover_overlay")

    def _on_canvas_leave(self, event=None):
        self._clear_hover_overlay()
        if hasattr(self, "lbl_metric_coords"):
            self.lbl_metric_coords.config(text="x - · y -")

    def _animate_click_ripple(self, cx: int, cy: int):
        """Microanimação de ripple (círculo 26px expandindo e esmaecendo por 300ms)."""
        steps = [
            (8, 2, "#FFFFFF"),
            (14, 2, "#E0E0E0"),
            (20, 1.5, "#B0B0B0"),
            (26, 1, "#808080"),
        ]

        def step_fn(idx):
            self.screen_canvas.delete("click_ripple")
            if idx < len(steps):
                r, w, c = steps[idx]
                self.screen_canvas.create_oval(cx - r, cy - r, cx + r, cy + r, outline=c, width=w, tags="click_ripple")
                self.screen_canvas.after(75, lambda: step_fn(idx + 1))

        step_fn(0)

    def _on_canvas_click(self, event):
        if not self.current_image:
            return

        self._animate_click_ripple(event.x, event.y)

        offset_x, offset_y = self.image_offset
        disp_w, disp_h = self.display_size

        click_x = event.x - offset_x
        click_y = event.y - offset_y

        if click_x < 0 or click_x > disp_w or click_y < 0 or click_y > disp_h:
            return

        plat = self.active_platform
        if plat == "ios":
            log_w, log_h = self.ios_logical_size
            target_x = int(click_x * (log_w / disp_w))
            target_y = int(click_y * (log_h / disp_h))
        else:
            scale_x, scale_y = self.current_scale
            target_x = int(click_x * scale_x)
            target_y = int(click_y * scale_y)

        if not self.current_xml:
            self.current_xml = (
                self.ios.get_ui_hierarchy()
                if plat == "ios"
                else self.adb.get_ui_hierarchy(self.selected_device)
            )

        if self.current_xml:
            elem = UIHierarchyParser.find_element_at(self.current_xml, target_x, target_y)
            if elem:
                self._highlight_element(elem)
                self._record_element(elem, click_coord=(target_x, target_y))
                self._update_attributes_panel(elem)
            else:
                tag_name = "android.view.View" if plat == "android" else "XCUIElementTypeOther"
                fallback_elem = UIElement(
                    tag=tag_name,
                    class_name=tag_name,
                    resource_id="",
                    text=f"pos_{target_x}_{target_y}",
                    content_desc="",
                    clickable=True,
                    bounds=(target_x, target_y, target_x, target_y),
                    area=1,
                    package="",
                    platform=plat,
                )
                self._record_element(fallback_elem, click_coord=(target_x, target_y))
                self._update_attributes_panel(fallback_elem)

        if self.auto_forward_tap.get():
            self._set_status(f"Enviando toque para ({target_x}, {target_y})...")

            def send_tap():
                if plat == "ios":
                    self.ios.tap(target_x, target_y)
                elif self.selected_device:
                    self.adb.tap(self.selected_device, target_x, target_y)

            threading.Thread(target=send_tap, daemon=True).start()

    # =========================================================================
    # ÁRVORE DE ACESSIBILIDADE & ATRIBUTOS
    # =========================================================================

    def _update_hierarchy_tree(self, xml_content: str):
        if not xml_content:
            return
        self.all_elements = UIHierarchyParser.parse_xml(xml_content)
        self._populate_tree(self.all_elements)

    def _init_chip_images(self):
        t = self.current_theme
        is_light = (t.get("name") == "light")
        if is_light:
            self._chip_images = {
                "W": make_chip_image("W", "#C3E2EE", "#17323F"),
                "V": make_chip_image("V", "#DCF0F8", "#2E7FA6"),
                "T": make_chip_image("T", "#F6E7C1", "#8A6A22"),
                "I": make_chip_image("I", "#D6EFD4", "#3F8F4E"),
                "B": make_chip_image("B", "#FBE3EA", "#D9536F"),
            }
        else:
            self._chip_images = {
                "W": make_chip_image("W", "#313244", "#CDD6F4"),
                "V": make_chip_image("V", "#1E1E2E", "#89B4FA"),
                "T": make_chip_image("T", "#383020", "#F9E2AF"),
                "I": make_chip_image("I", "#283248", "#94E2D5"),
                "B": make_chip_image("B", "#1B332A", "#A6E3A1"),
            }

    def _populate_tree(self, elements: List[UIElement]):
        self.hierarchy_tree.delete(*self.hierarchy_tree.get_children())
        query = self.hierarchy_search_var.get().lower().strip()
        if not hasattr(self, "_chip_images") or not self._chip_images:
            self._init_chip_images()

        for idx, elem in enumerate(elements):
            display = elem.display_name or elem.resource_id or elem.text or elem.class_name.split(".")[-1]
            if query and query not in display.lower() and query not in elem.class_name.lower():
                continue

            chip = getattr(elem, "chip_type", "V")
            chip_img = self._chip_images.get(chip, self._chip_images.get("V"))
            label = f" {elem.class_name.split('.')[-1]}  {display}"

            parent_id = ""
            if not query and getattr(elem, "parent_idx", None) is not None:
                p_str = str(elem.parent_idx)
                if self.hierarchy_tree.exists(p_str):
                    parent_id = p_str

            self.hierarchy_tree.insert(
                parent_id,
                "end",
                iid=str(idx),
                text=label,
                image=chip_img,
                open=True,
                values=(idx,),
            )

    def _apply_hierarchy_filter(self):
        self._populate_tree(self.all_elements)

    def _on_tree_select(self, event):
        sel = self.hierarchy_tree.selection()
        if not sel:
            return
        idx = int(sel[0])
        if 0 <= idx < len(self.all_elements):
            elem = self.all_elements[idx]
            self.selected_element = elem
            self._highlight_element(elem)
            self._update_attributes_panel(elem)
            self._record_element(elem, click_coord=elem.center)

    def _update_attributes_panel(self, elem: UIElement):
        self.attrib_labels["type"].config(text=elem.class_name.split(".")[-1])
        self.attrib_labels["name"].config(text=elem.resource_id or elem.display_name or "—")
        self.attrib_labels["label"].config(text=elem.text or elem.content_desc or "—")
        self.attrib_labels["bounds"].config(text=f"[{elem.bounds[0]},{elem.bounds[1]}][{elem.bounds[2]},{elem.bounds[3]}]")
        self.attrib_labels["center"].config(text=f"({elem.center[0]}, {elem.center[1]})")
        self.attrib_labels["enabled"].config(text="true")

    def _copy_all_attributes(self):
        if not self.selected_element:
            return
        e = self.selected_element
        lines = [
            f"type: {e.class_name}",
            f"name: {e.resource_id}",
            f"label: {e.text or e.content_desc}",
            f"bounds: {e.bounds}",
            f"center: {e.center}",
        ]
        text = "\n".join(lines)
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self._set_status("Atributos copiados para a área de transferência!")

    # =========================================================================
    # TOGGLES DE PAINEL (⌥1 Espelho, ⌥2 Hierarquia, ⌥3 Workspace, ⌥⌘F Restaurar)
    # =========================================================================

    def _toggle_mirror(self):
        """Oculta ou exibe o painel do espelho (⌥1)."""
        self.is_mirror_visible = not self.is_mirror_visible
        if self.is_mirror_visible:
            self.main_split.add(self.left_frame, minsize=280, width=384, before=self.center_right_split)
            self.btn_toggle_mirror.configure(bg=self.current_theme["accent"], fg=self.current_theme["accent_on"])
            self.btn_p1.set_active(True)
            self._set_status("Espelho visível.")
        else:
            self.main_split.forget(self.left_frame)
            self.btn_toggle_mirror.configure(bg=self.current_theme["btn_bg"], fg=self.current_theme["text_secondary"])
            self.btn_p1.set_active(False)
            self._set_status("Espelho oculto · streaming em segundo plano.")

    def _toggle_hierarchy(self):
        """Oculta ou exibe o painel de hierarquia (⌥2)."""
        self.is_hierarchy_visible = not self.is_hierarchy_visible
        if self.is_hierarchy_visible:
            self.center_right_split.add(self.hierarchy_frame, minsize=250, width=296, before=self.right_container)
            self.btn_p2.set_active(True)
            self._set_status("Hierarquia visível.")
        else:
            self.center_right_split.forget(self.hierarchy_frame)
            self.btn_p2.set_active(False)
            self._set_status("Hierarquia oculta.")

    def _toggle_workspace(self):
        """Oculta ou exibe o workspace de código (⌥3)."""
        self.is_workspace_visible = not self.is_workspace_visible
        if self.is_workspace_visible:
            self.center_right_split.add(self.right_container, minsize=480)
            self.btn_p3.set_active(True)
        else:
            self.center_right_split.forget(self.right_container)
            self.btn_p3.set_active(False)

    def _restore_all_panels(self):
        """Restaura o layout padrão com todas as 3 colunas visíveis (⌥⌘F)."""
        if not self.is_mirror_visible:
            self._toggle_mirror()
        if not self.is_hierarchy_visible:
            self._toggle_hierarchy()
        if not self.is_workspace_visible:
            self._toggle_workspace()
        self._set_status("Layout padrão restaurado.")

    def _focus_hierarchy_search(self):
        if not self.is_hierarchy_visible:
            self._toggle_hierarchy()
        self.entry_search_hierarchy.focus_set()

    def _toggle_zen_mode(self):
        """Modo Zen: colapsa/expande a barra de configuração secundária."""
        self.is_zen_mode = not self.is_zen_mode
        if self.is_zen_mode:
            self.config_bar.pack_forget()
            self.btn_zen.configure(bg=self.current_theme["accent"], fg=self.current_theme["accent_on"])
        else:
            self.config_bar.pack(side=tk.TOP, fill=tk.X)
            self.btn_zen.configure(bg=self.current_theme["bg_control"], fg=self.current_theme["text_secondary"])

    # =========================================================================
    # AÇÕES DO DEVICE DOCK (‹ Voltar, Home, Girar, Screenshot)
    # =========================================================================

    def _dock_back(self):
        if self.active_platform == "android" and self.selected_device:
            threading.Thread(target=lambda: self.adb.shell(self.selected_device, "input keyevent 4"), daemon=True).start()
        self._set_status("Comando: Voltar")

    def _dock_home(self):
        if self.active_platform == "android" and self.selected_device:
            threading.Thread(target=lambda: self.adb.shell(self.selected_device, "input keyevent 3"), daemon=True).start()
        self._set_status("Comando: Home")

    def _dock_rotate(self):
        self._set_status("Alternando orientação do espelho...")
        self._render_image_on_canvas()

    def _generate_contract_assertion(self):
        snippet = (
            "\n        # Asserção de contrato de API correlacionada (MITM)\n"
            "        response = self.network_interceptor.wait_for_request('/v2/credito/simulacao', timeout=5.0)\n"
            "        assert response.status_code == 201\n"
            "        assert response.json()['status'] == 'PRE_APROVADO'\n"
        )
        self.actions_text.insert(tk.END, snippet)
        self.actions_text.see(tk.END)
        self._on_code_changed(self.actions_text, self.actions_gutter)
        self._set_status("Asserção de contrato gerada e inserida no código!")

    # =========================================================================
    # ALTERNÂNCIA DE ABAS DO WORKSPACE (Page Objects vs Rede HTTP vs Analytics)
    # =========================================================================

    def _set_right_view(self, view_name: str):
        self.right_view_var.set(view_name)
        t = self.current_theme

        # Reset visual segmented
        for btn in [self.btn_seg_auto, self.btn_seg_net, self.btn_seg_analytics]:
            btn.configure(bg=t["bg_control_track"], fg=t["text_secondary"])

        if view_name == "automation":
            self.btn_seg_auto.configure(bg=t["bg_control"], fg=t["text_primary"])
            self.network_view.pack_forget()
            self.automation_view.pack(fill=tk.BOTH, expand=True)
            self.correlation_card_frame.pack_forget()
        elif view_name == "network":
            self.btn_seg_net.configure(bg=t["bg_control"], fg=t["text_primary"])
            self.automation_view.pack_forget()
            self.network_view.pack(fill=tk.BOTH, expand=True)
            self.network_view._set_subview("http")
            self.correlation_card_frame.pack(fill=tk.X, side=tk.BOTTOM, pady=6)
        elif view_name == "analytics":
            self.btn_seg_analytics.configure(bg=t["bg_control"], fg=t["text_primary"])
            self.automation_view.pack_forget()
            self.network_view.pack(fill=tk.BOTH, expand=True)
            self.network_view._set_subview("tag")
            self.correlation_card_frame.pack(fill=tk.X, side=tk.BOTTOM, pady=6)

    def _set_strategy(self, strat: str):
        self.locator_strategy_var.set(strat)
        t = self.current_theme
        for btn, val in [(self.btn_strat_id, "id"), (self.btn_strat_xpath, "xpath"), (self.btn_strat_coords, "position")]:
            if val == strat:
                btn.configure(bg=t["bg_control"], fg=t["text_primary"])
            else:
                btn.configure(bg=t["bg_control_track"], fg=t["text_secondary"])
        self.codegen.strategy = LocatorStrategy(strat)

    def _toggle_code_split(self):
        self.is_split_active = not self.is_split_active
        self._apply_code_layout()

    def _set_code_subtab(self, tab_name: str):
        self.active_code_tab = tab_name
        self.is_split_active = False
        self._apply_code_layout()

    def _apply_code_layout(self):
        for pane in list(self.right_split.panes()):
            self.right_split.forget(pane)

        if self.is_split_active:
            self.right_split.add(self.actions_frame, minsize=200, stretch="always")
            self.right_split.add(self.objects_frame, minsize=200, stretch="always")
        else:
            if self.active_code_tab == "objects":
                self.right_split.add(self.objects_frame, minsize=200, stretch="always")
            else:
                self.right_split.add(self.actions_frame, minsize=200, stretch="always")

    def _scroll_both_act(self, *args):
        self.actions_text.yview(*args)
        self.actions_gutter.yview(*args)

    def _sync_scroll_act(self, *args):
        self.actions_gutter.yview_moveto(args[0])
        if hasattr(self, "actions_scroll_y"):
            self.actions_scroll_y.set(*args)

    def _scroll_both_obj(self, *args):
        self.objects_text.yview(*args)
        self.objects_gutter.yview(*args)

    def _sync_scroll_obj(self, *args):
        self.objects_gutter.yview_moveto(args[0])
        if hasattr(self, "objects_scroll_y"):
            self.objects_scroll_y.set(*args)

    def _on_code_changed(self, text_widget: tk.Text, gutter_widget: tk.Text):
        update_gutter(gutter_widget, text_widget)
        highlight_python_syntax(text_widget, self.current_theme)

    # =========================================================================
    # PROCESSAMENTO DE FILA DE EVENTOS ASSÍNCRONOS & STREAMING
    # =========================================================================

    def _process_event_queue(self):
        latest_frame = None

        while not self.event_queue.empty():
            try:
                event_type, payload = self.event_queue.get_nowait()

                if event_type == "frame":
                    latest_frame = payload
                elif event_type == "device_changed":
                    platform, device_id = payload
                    if platform == self.active_platform and self.selected_device != device_id:
                        self.selected_device = device_id
                        self.device_combo["values"] = [device_id]
                        self.device_combo.current(0)
                        self.stream_engine.reset_diff()
                        self.stream_engine.resume()
                        self._set_status(f"Conectado ao {platform.upper()}: {device_id}")
                        self._start_passive_listeners()
                        self._on_screen_settled_detected()
                        self._update_empty_state()
                elif event_type == "hierarchy_ready":
                    xml = payload
                    if xml:
                        self.current_xml = xml
                        if self.active_platform == "ios":
                            try:
                                # Parser endurecido do motor: o XML vem do app
                                # sob teste e aceita DOCTYPE/entidade no parser
                                # padrao (ver docs/SEGURANCA.md, item 3).
                                from mobaile.security import parse_untrusted_xml
                                root = parse_untrusted_xml(xml)
                                if root is None:
                                    raise ValueError("hierarquia XML invalida")
                                w = int(float(root.attrib.get("width", 390)))
                                h = int(float(root.attrib.get("height", 844)))
                                if w > 0 and h > 0:
                                    self.ios_logical_size = (w, h)
                            except Exception:
                                pass
                        self._update_hierarchy_tree(xml)
                        self._set_status(f"{self.active_platform.upper()}: Tela e hierarquia sincronizadas em tempo real.")
                elif event_type == "passive_tap":
                    target_x, target_y = payload
                    self._set_status(f"Toque direto detectado em ({target_x}, {target_y})! Mapeando...")
                    if not self.current_xml and self.selected_device:
                        try:
                            self.current_xml = (
                                self.ios.get_ui_hierarchy()
                                if self.active_platform == "ios"
                                else self.adb.get_ui_hierarchy(self.selected_device)
                            )
                        except Exception:
                            pass

                    elem = None
                    if self.current_xml:
                        elem = UIHierarchyParser.find_element_at(self.current_xml, target_x, target_y)

                    if elem:
                        self._highlight_element(elem)
                        self._record_element(elem, click_coord=(target_x, target_y))
                        self._update_attributes_panel(elem)
                    else:
                        tag_name = "android.view.View" if self.active_platform == "android" else "XCUIElementTypeOther"
                        fallback_elem = UIElement(
                            tag=tag_name,
                            class_name=tag_name,
                            resource_id="",
                            text=f"pos_{target_x}_{target_y}",
                            content_desc="",
                            clickable=True,
                            bounds=(target_x, target_y, target_x, target_y),
                            area=1,
                            package="",
                            platform=self.active_platform,
                        )
                        self._record_element(fallback_elem, click_coord=(target_x, target_y))
                        self._update_attributes_panel(fallback_elem)
            except queue.Empty:
                break
            except Exception:
                pass

        if latest_frame is not None:
            self.current_image = latest_frame
            self._render_image_on_canvas()

        self.root.after(30, self._process_event_queue)

    def _capture_raw_frame(self) -> Optional[Image.Image]:
        plat = self.active_platform
        dev = self.selected_device
        try:
            if plat == "ios":
                return self.ios.take_screenshot(dev or "booted")
            elif plat == "android" and dev:
                return self.adb.take_screenshot(dev)
        except Exception:
            pass
        return None

    def _on_stream_frame_received(self, image: Image.Image):
        self.event_queue.put(("frame", image))

    def _on_screen_settled_detected(self):
        plat = self.active_platform
        dev = self.selected_device

        def fetch_hierarchy():
            try:
                xml = self.ios.get_ui_hierarchy() if plat == "ios" else (self.adb.get_ui_hierarchy(dev) if dev else None)
                self.event_queue.put(("hierarchy_ready", xml))
            except Exception:
                pass

        threading.Thread(target=fetch_hierarchy, daemon=True).start()

    def _on_canvas_resize(self, event):
        self._draw_screen_chrome()
        if self.current_image:
            self._render_image_on_canvas()

    def _on_bezel_resize(self, event=None):
        if not hasattr(self, "bezel_canvas") or not hasattr(self, "screen_window_id"):
            return
        cw = self.bezel_canvas.winfo_width()
        ch = self.bezel_canvas.winfo_height()
        if cw < 60 or ch < 80:
            return
        self.bezel_canvas.delete("bezel_art")
        t = self.current_theme
        pw = min(cw - 16, 290)
        ph = min(ch - 16, int(pw * 2.05))
        x1 = (cw - pw) // 2
        y1 = (ch - ph) // 2
        x2 = x1 + pw
        y2 = y1 + ph
        # Shadow suave
        _draw_round_rect(self.bezel_canvas, x1 + 2, y1 + 4, x2 + 2, y2 + 4, radius=40, fill="#0B0B12", tags="bezel_art")
        # Chassis smartphone #11111B
        _draw_round_rect(self.bezel_canvas, x1, y1, x2, y2, radius=40, fill=t.get("device_bezel", "#11111B"), outline=t.get("border", "#313244"), width=2, tags="bezel_art")
        # Tela interna (bezel de 8px nas bordas)
        sw = max(50, pw - 16)
        sh = max(80, ph - 20)
        cx = (x1 + x2) // 2
        cy = (y1 + y2) // 2
        self.bezel_canvas.coords(self.screen_window_id, cx, cy)
        self.bezel_canvas.itemconfigure(self.screen_window_id, width=sw, height=sh)
        self._draw_screen_chrome()

    def _draw_screen_chrome(self):
        if not hasattr(self, "screen_canvas"):
            return
        self.screen_canvas.delete("notch")
        self.screen_canvas.delete("home_bar")
        sw = self.screen_canvas.winfo_width()
        sh = self.screen_canvas.winfo_height()
        if sw < 60 or sh < 80:
            return
        # Notch / Dynamic Island pill 78x20
        nw, nh = min(78, sw - 20), 20
        nx1 = (sw - nw) // 2
        ny1 = 6
        _draw_round_rect(self.screen_canvas, nx1, ny1, nx1 + nw, ny1 + nh, radius=10, fill="#000000", outline="#181825", width=1, tags="notch")
        self.screen_canvas.create_oval(nx1 + nw - 16, ny1 + 6, nx1 + nw - 8, ny1 + 14, fill="#181825", outline="", tags="notch")
        # Home indicator
        hw, hh = min(90, sw - 30), 4
        hx1 = (sw - hw) // 2
        hy1 = sh - 9
        _draw_round_rect(self.screen_canvas, hx1, hy1, hx1 + hw, hy1 + hh, radius=2, fill="#45475A", outline="", tags="home_bar")
        self.screen_canvas.tag_raise("notch")
        self.screen_canvas.tag_raise("home_bar")

    def _render_image_on_canvas(self):
        if not self.current_image:
            return

        canvas_w = self.screen_canvas.winfo_width()
        canvas_h = self.screen_canvas.winfo_height()
        if canvas_w < 50 or canvas_h < 50:
            return

        img_w, img_h = self.current_image.size
        ratio = min(canvas_w / img_w, canvas_h / img_h)
        disp_w = max(1, int(img_w * ratio))
        disp_h = max(1, int(img_h * ratio))

        self.display_size = (disp_w, disp_h)
        self.current_scale = (img_w / disp_w, img_h / disp_h)

        offset_x = (canvas_w - disp_w) // 2
        offset_y = (canvas_h - disp_h) // 2
        self.image_offset = (offset_x, offset_y)

        resized = self.current_image.resize((disp_w, disp_h), Image.Resampling.BILINEAR)
        self.current_tk_image = ImageTk.PhotoImage(resized)

        self.screen_canvas.image = self.current_tk_image
        self.screen_canvas.delete("img")
        self.screen_canvas.create_image(offset_x, offset_y, anchor=tk.NW, image=self.current_tk_image, tags="img")
        self.screen_canvas.tag_raise("notch")
        self.screen_canvas.tag_raise("home_bar")
        self.screen_canvas.tag_raise("highlight")
        self.screen_canvas.tag_raise("hover_overlay")
        self.screen_canvas.tag_raise("click_ripple")

    def _highlight_element(self, elem: UIElement):
        self.screen_canvas.delete("highlight")
        x1, y1, x2, y2 = elem.bounds
        off_x, off_y = self.image_offset
        disp_w, disp_h = self.display_size

        plat = self.active_platform
        if plat == "ios":
            log_w, log_h = self.ios_logical_size
            cx1 = int(x1 * (disp_w / log_w)) + off_x
            cy1 = int(y1 * (disp_h / log_h)) + off_y
            cx2 = int(x2 * (disp_w / log_w)) + off_x
            cy2 = int(y2 * (disp_h / log_h)) + off_y
        else:
            scale_x, scale_y = self.current_scale
            cx1 = int(x1 / scale_x) + off_x
            cy1 = int(y1 / scale_y) + off_y
            cx2 = int(x2 / scale_x) + off_x
            cy2 = int(y2 / scale_y) + off_y

        self.screen_canvas.create_rectangle(
            cx1, cy1, cx2, cy2, outline=self.highlight_color, width=3, tags="highlight"
        )
        self.screen_canvas.tag_raise("highlight")

    def _record_element(self, elem: UIElement, click_coord: Optional[Tuple[int, int]] = None):
        strategy = LocatorStrategy(self.locator_strategy_var.get())
        var_name, obj_code_line, action_code_block = self.codegen.generate_entry(
            elem, strategy=strategy, click_coord=click_coord
        )

        self.actions_text.insert(tk.END, action_code_block + "\n")
        self.actions_text.see(tk.END)
        self._on_code_changed(self.actions_text, self.actions_gutter)

        self.objects_text.insert(tk.END, obj_code_line + "\n")
        self.objects_text.see(tk.END)
        self._on_code_changed(self.objects_text, self.objects_gutter)

        step_num = len(self.codegen.steps)
        self.detail_label.config(
            text=f"passo {step_num:02d} · ação tap · elemento {var_name} · estratégia {strategy.value}"
        )
        self._set_status(f"Gravado com sucesso: {var_name}")

        # Atualiza card de correlação
        self.lbl_correl_action.config(text=f"tap · {var_name}")
        self.lbl_correl_reqs.config(text=f"disparou {self.http_requests_count} requisições")
        self.lbl_correl_fa.config(text=f"e {self.analytics_events_count} eventos de analytics")

    # =========================================================================
    # GERENCIAMENTO DE DISPOSITIVOS & ESTADOS DE CONEXÃO
    # =========================================================================

    def _refresh_devices(self):
        plat = self.active_platform
        self.device_combo["values"] = []
        self.last_scan_time = time.strftime("%H:%M:%S")

        if plat == "ios":
            sims = self.ios.list_booted_simulators()
            if sims:
                formatted = [f"{s[0]} ({s[1]})" for s in sims]
                self.device_combo["values"] = formatted
                self.device_combo.current(0)
                self.selected_device = sims[0][0]
                self._set_status(f"Conectado ao iOS: {sims[0][1]}")
                self.stream_engine.reset_diff()
                self.stream_engine.resume()
                self._on_screen_settled_detected()
            else:
                self.device_combo.set("Nenhum dispositivo")
                self.selected_device = None
                self._set_status("Nenhum simulador iOS em execução.")
                self.stream_engine.pause()
        else:
            devs = self.adb.list_devices()
            if devs:
                formatted = [f"{d[0]} ({self.adb.get_device_model(d[0])})" for d in devs]
                self.device_combo["values"] = formatted
                self.device_combo.current(0)
                self.selected_device = devs[0][0]
                self._set_status(f"Conectado ao Android: {self.selected_device}")
                self.stream_engine.reset_diff()
                self.stream_engine.resume()
                self._on_screen_settled_detected()
            else:
                self.device_combo.set("Nenhum dispositivo")
                self.selected_device = None
                self._set_status("Nenhum dispositivo Android ativo.")
                self.stream_engine.pause()

        self._update_empty_state()
        self._start_passive_listeners()

    def _update_empty_state(self):
        t = self.current_theme
        if not self.selected_device:
            self.is_empty_state = True
            self.main_split.pack_forget()
            self.empty_state_frame.pack(fill=tk.BOTH, expand=True)
            self.device_dot.configure(fg=t["danger"])
            self.lbl_scan_status.configure(text=f"procurando dispositivos… · último scan {self.last_scan_time}")
        else:
            self.is_empty_state = False
            self.empty_state_frame.pack_forget()
            self.main_split.pack(fill=tk.BOTH, expand=True)
            self.device_dot.configure(fg=t["success"])

    def _on_manual_platform_switch(self):
        new_plat = self.platform_var.get()
        t = self.current_theme
        if new_plat == "ios":
            self.rb_ios.configure(bg=t["bg_control"], fg=t["text_primary"])
            self.rb_android.configure(bg=t["bg_control_track"], fg=t["text_secondary"])
        else:
            self.rb_android.configure(bg=t["bg_control"], fg=t["text_primary"])
            self.rb_ios.configure(bg=t["bg_control_track"], fg=t["text_secondary"])
        self._on_platform_changed()

    def _on_platform_changed(self):
        self.active_platform = self.platform_var.get()
        self.watcher.target_platform = self.active_platform
        self._refresh_devices()

    def _on_auto_device_detected(self, platform: str, device_id: str):
        self.event_queue.put(("device_changed", (platform, device_id)))

    def _on_device_selected(self, event=None):
        val = self.device_combo.get()
        if val and not val.startswith("Nenhum"):
            self.selected_device = val.split()[0]
            self.stream_engine.reset_diff()
            self.stream_engine.resume()
            self._set_status(f"Dispositivo ativo: {self.selected_device}")
            self._start_passive_listeners()
            self._on_screen_settled_detected()
            self._update_empty_state()

    def _toggle_streaming(self):
        if self.is_streaming_active:
            self.stream_engine.pause()
            self.is_streaming_active = False
            self.btn_toggle_stream.configure(text="Iniciar Streaming", bg=self.current_theme["btn_bg"], fg=self.current_theme["text_secondary"])
            self._set_status("Streaming pausado.")
        else:
            self.stream_engine.resume()
            self.is_streaming_active = True
            self.btn_toggle_stream.configure(text="Streaming", bg=self.current_theme["accent"], fg=self.current_theme["accent_on"])
            self._set_status("Streaming ativo.")

    def _force_capture_now(self):
        self._set_status("Capturando tela e analisando elementos...")
        frame = self._capture_raw_frame()
        if frame:
            self.current_image = frame
            self._render_image_on_canvas()
        self._on_screen_settled_detected()

    def _on_passive_tap(self, target_x: int, target_y: int):
        self.event_queue.put(("passive_tap", (target_x, target_y)))

    def _start_passive_listeners(self):
        self._stop_passive_listeners()
        if not self.passive_mode_var.get():
            return
        if self.active_platform == "android" and self.selected_device:
            self.android_listener = AndroidPassiveListener(
                adb_path=self.adb.adb_path,
                device_id=self.selected_device,
                on_tap_callback=self._on_passive_tap,
            )
            self.android_listener.start()
        elif self.active_platform == "ios":
            self.ios_listener = IOSPassiveListener(on_tap_callback=self._on_passive_tap)
            self.ios_listener.start()

    def _stop_passive_listeners(self):
        if self.android_listener:
            self.android_listener.stop()
            self.android_listener = None
        if self.ios_listener:
            self.ios_listener.stop()
            self.ios_listener = None

    def _on_passive_mode_toggled(self):
        if self.passive_mode_var.get():
            self._start_passive_listeners()
            self._set_status("Modo Passivo ativado.")
        else:
            self._stop_passive_listeners()
            self._set_status("Modo Passivo desativado.")

    def _on_theme_switch(self):
        mode = self.theme_var.get()
        theme = THEME_PRAIA_LIGHT if mode == "light" else THEME_PRAIA_DARK
        self.apply_theme(theme)

    def apply_theme(self, theme_dict: dict):
        self.current_theme = theme_dict.copy()
        self.bg_color = theme_dict.get("bg_window", theme_dict["bg_color"])
        self.fg_color = theme_dict.get("text_primary", theme_dict["fg_color"])
        self.panel_bg = theme_dict.get("bg_panel", theme_dict["panel_bg"])
        self.accent_color = theme_dict.get("accent", theme_dict["accent_color"])
        self.highlight_color = theme_dict.get("accent", theme_dict["highlight_color"])

        t = self.current_theme
        self._setup_ttk_styles(t)
        self.root.configure(bg=self.bg_color)

        if hasattr(self, "top_bar"):
            self.top_bar.configure(bg=t["bg_toolbar"])
        if hasattr(self, "lbl_app_name"):
            self.lbl_app_name.configure(bg=t["bg_toolbar"], fg=t["text_primary"])
        if hasattr(self, "lbl_app_sub"):
            self.lbl_app_sub.configure(bg=t["bg_toolbar"], fg=t["text_tertiary"])
        if hasattr(self, "traffic_lights_frame"):
            self.traffic_lights_frame.configure(bg=t["bg_toolbar"])
        if hasattr(self, "toolbar_right"):
            self.toolbar_right.configure(bg=t["bg_toolbar"])
        if hasattr(self, "status_bar_frame"):
            self.status_bar_frame.configure(bg=t["bg_terminal"])
        if hasattr(self, "daemons_frame"):
            self.daemons_frame.configure(bg=t["bg_terminal"])
        if hasattr(self, "metrics_frame"):
            self.metrics_frame.configure(bg=t["bg_terminal"])

        if hasattr(self, "btn_cap"):
            self.btn_cap.configure(bg=t["accent"], fg=t["accent_on"])
        if hasattr(self, "btn_toggle_mirror"):
            self.btn_toggle_mirror.configure(bg=t["accent"] if self.is_mirror_visible else t["btn_bg"], fg=t["accent_on"] if self.is_mirror_visible else t["text_secondary"])

        # Editores de código
        if hasattr(self, "actions_text"):
            self.actions_text.configure(bg=t["bg_window"], fg=t["syntax"]["plain"])
            self.actions_gutter.configure(bg=t["syntax"]["gutter_bg"], fg=t["syntax"]["gutter"])
        if hasattr(self, "objects_text"):
            self.objects_text.configure(bg=t["bg_window"], fg=t["syntax"]["plain"])
            self.objects_gutter.configure(bg=t["syntax"]["gutter_bg"], fg=t["syntax"]["gutter"])

        # Coluna 1
        if hasattr(self, "left_frame"):
            self.left_frame.configure(bg=t["bg_panel"])
            if hasattr(self, "mirror_header"):
                self.mirror_header.configure(bg=t["bg_panel"])
            if hasattr(self, "bezel_container"):
                self.bezel_container.configure(bg=t["bg_panel"])
            if hasattr(self, "bezel_canvas"):
                self.bezel_canvas.configure(bg=t["bg_panel"])
                self._on_bezel_resize()
            if hasattr(self, "device_dock"):
                self.device_dock.configure(bg=t["bg_panel"])
            if hasattr(self, "screen_canvas"):
                self.screen_canvas.configure(bg=t["bg_device_screen"])
            if hasattr(self, "phone_frame"):
                self.phone_frame.configure(bg=t.get("device_bezel", "#11111B"), highlightbackground=t.get("border", "#313244"))
            if hasattr(self, "notch_frame"):
                self.notch_frame.configure(bg=t.get("device_bezel", "#11111B"))

        # Coluna 2
        if hasattr(self, "hierarchy_frame"):
            self.hierarchy_frame.configure(bg=t["bg_window"])
            self.hierarchy_header.configure(bg=t["bg_window"])
            self.tree_container.configure(bg=t["bg_panel"])
            self.attrib_footer.configure(bg=t["bg_panel"], highlightbackground=t["border"])
            self._init_chip_images()
            if hasattr(self, "all_elements") and self.all_elements:
                self._populate_tree(self.all_elements)

        # Coluna 3
        if hasattr(self, "right_container"):
            self.right_container.configure(bg=t["bg_window"])
            self.workspace_tab_bar.configure(bg=t["bg_window"])
            self.automation_view.configure(bg=t["bg_window"])
            self.code_footer.configure(bg=t["bg_panel"], highlightbackground=t["border"])

        # Frame de Inspeção de Rede
        if hasattr(self, "network_view"):
            self.network_view.apply_theme(t)

        # Compatibilidade com opções antigas testadas em test_ui_theme.py
        for opt in [
            getattr(self, "rb_ios", None),
            getattr(self, "rb_android", None),
            getattr(self, "rb_theme_dark", None),
            getattr(self, "rb_theme_light", None),
            getattr(self, "rb_strat_id", None),
            getattr(self, "rb_strat_xpath", None),
            getattr(self, "rb_strat_pos", None),
            getattr(self, "cb_passive", None),
            getattr(self, "cb_forward", None),
            getattr(self, "btn_scrcpy", None),
        ]:
            if opt:
                opt.configure(fg="#111111" if t["name"] == "light" else "#FFFFFF")

    def _on_key_changed(self, *args):
        self.codegen.page_objects_key = self.page_objects_key_var.get()
        self.lbl_obj_title.config(text=f"locators/{self.page_objects_key_var.get()}.py")
        self.lbl_act_title.config(text=f"pages/{self.page_objects_key_var.get()}.py")

    def _on_strategy_changed(self):
        self.codegen.strategy = LocatorStrategy(self.locator_strategy_var.get())

    def _insert_initial_headers(self):
        act_hdr = (
            "from locators.credito import objs\n"
            "from base.page import BasePage\n\n\n"
            "class OnboardingCredito(BasePage):\n"
            "    # Passos gerados automaticamente aparecerão abaixo\n"
        )
        self.actions_text.delete("1.0", tk.END)
        self.actions_text.insert(tk.END, act_hdr)
        self._on_code_changed(self.actions_text, self.actions_gutter)

        obj_hdr = f"{self.page_objects_key_var.get()} = {{\n}}\n"
        self.objects_text.delete("1.0", tk.END)
        self.objects_text.insert(tk.END, obj_hdr)
        self._on_code_changed(self.objects_text, self.objects_gutter)

    def _copy_text(self, text_widget: scrolledtext.ScrolledText):
        content = text_widget.get("1.0", tk.END).strip()
        self.root.clipboard_clear()
        self.root.clipboard_append(content)
        self._set_status("Código copiado para a área de transferência!")

    def _save_text_to_file(self, text_widget: scrolledtext.ScrolledText, default_filename: str):
        filepath = filedialog.asksaveasfilename(
            defaultextension=".py",
            filetypes=[("Arquivos Python", "*.py"), ("Todos os arquivos", "*.*")],
            initialfile=default_filename,
        )
        if filepath:
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(text_widget.get("1.0", tk.END))
            self._set_status(f"Salvo em: {filepath}")

    def _clear_both(self):
        self.codegen.reset()
        self._insert_initial_headers()
        self.detail_label.config(text="passo 00 · limpo")
        self.screen_canvas.delete("highlight")
        self._set_status("Editores reiniciados.")

    def _set_status(self, msg: str):
        if hasattr(self, "status_bar"):
            self.status_bar.config(text=msg)

    def _set_window_icon(self):
        icon_path = resources.icon_path()
        if icon_path:
            try:
                icon_img = ImageTk.PhotoImage(file=icon_path)
                self.root.iconphoto(True, icon_img)
            except Exception:
                pass

    def _on_view_structure(self):
        AutomationStructureDialog(
            parent=self.root,
            codegen=self.codegen,
            theme_dict=self.current_theme,
            on_update_callback=self._refresh_code_from_steps,
        )

    def _refresh_code_from_steps(self):
        self.actions_text.delete("1.0", tk.END)
        self.objects_text.delete("1.0", tk.END)
        self.codegen.declared_objects.clear()
        self.codegen.declared_actions.clear()
        self._insert_initial_headers()

        for step in self.codegen.steps:
            pass

    def _on_run_automation(self):
        steps = self.codegen.get_steps()
        if not steps:
            messagebox.showwarning("Nenhum Passo", "Grave ao menos uma ação antes de executar.")
            return

        AutomationExecutionDialog(
            parent=self.root,
            steps=steps,
            platform=self.active_platform,
            device_id=self.selected_device or "emulator-5554",
            wda_url=settings.wda_url,
            adb_path=self.adb.adb_path,
            theme_dict=self.current_theme,
        )

    def _open_http_viewer(self):
        cur = self.right_view_var.get()
        new_v = "network" if cur != "network" else "automation"
        self._set_right_view(new_v)

    def _toggle_scrcpy_mirror(self):
        if hasattr(self, "scrcpy_manager") and self.scrcpy_manager.is_running():
            self.scrcpy_manager.stop_mirror()
            self._set_status("Espelho Scrcpy encerrado.")
            return

        if not self.selected_device:
            messagebox.showwarning("Aviso", "Nenhum dispositivo Android selecionado.")
            return

        if not self.scrcpy_manager.is_available():
            messagebox.showwarning("Aviso", "scrcpy não está instalado ou disponível no PATH.")
            return

        success = self.scrcpy_manager.start_mirror(self.selected_device)
        if success:
            self._set_status(f"Espelho Scrcpy iniciado para {self.selected_device}")
        else:
            messagebox.showerror("Erro", "Falha ao iniciar o scrcpy.")

    def _launch_scrcpy_docked(self):
        pass

    def _on_window_configure(self, event):
        pass

    def _start_android_background_worker(self):
        if getattr(self, "_android_worker_started", False):
            return
        self._android_worker_started = True
        self._android_worker_running = True

        def worker():
            while getattr(self, "_android_worker_running", True):
                if self.active_platform == "android" and self.selected_device:
                    dev = self.selected_device
                    try:
                        xml = self.adb.get_ui_hierarchy(dev)
                        if xml:
                            self.event_queue.put(("hierarchy_ready", xml))

                        img = self.adb.take_screenshot(dev)
                        if img:
                            self.event_queue.put(("frame", img))
                    except Exception:
                        pass
                time.sleep(2.2)

        t = threading.Thread(target=worker, daemon=True)
        t.start()

    def _on_window_closing(self):
        self._android_worker_running = False
        if hasattr(self, "scrcpy_manager"):
            self.scrcpy_manager.stop_mirror()
        if hasattr(self, "network_view"):
            self.network_view.destroy_resources()
        if self.http_viewer_win and self.http_viewer_win.window.winfo_exists():
            try:
                self.http_viewer_win.window.destroy()
            except Exception:
                pass
        self.stream_engine.stop()
        self.watcher.stop()
        self._stop_passive_listeners()
        self.root.destroy()


def _start_main_window():
    root = tk.Tk(className="Mo baile")
    root.title("Mo baile")
    configure_macos_app_identity("Mo baile")
    target_w, target_h, pos_x, pos_y = calculate_apple_geometry(root)
    root.geometry(f"{target_w}x{target_h}+{pos_x}+{pos_y}")
    root.minsize(1100, 720)
    MobileRecorderApp(root)
    root.mainloop()


def launch_app(show_splash: bool = True):
    from mobaile_tk.splash import show_splash_if_available

    root = tk.Tk(className="Mo baile")
    root.title("Mo baile")
    configure_macos_app_identity("Mo baile")
    root.configure(bg=THEME_PRAIA_DARK["bg_window"])
    target_w, target_h, pos_x, pos_y = calculate_apple_geometry(root)
    root.geometry(f"{target_w}x{target_h}+{pos_x}+{pos_y}")
    root.minsize(1100, 720)

    icon_path = resources.icon_path()
    if icon_path:
        try:
            icon_img = ImageTk.PhotoImage(file=icon_path)
            root.iconphoto(True, icon_img)
        except Exception:
            pass

    def start_app():
        MobileRecorderApp(root)

    if show_splash:
        show_splash_if_available(on_complete=start_app, root=root)
    else:
        start_app()

    root.mainloop()


if __name__ == "__main__":
    launch_app()

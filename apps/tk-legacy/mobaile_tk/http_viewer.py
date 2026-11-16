"""
Módulo de Interface do Inspetor de Tráfego de Rede e Tagueamento (HTTP & Analytics Inspector)
---------------------------------------------------------------------------------------------
Fornece um componente embutível (HTTPInspectorFrame) e uma janela auxiliar para:
1. Inspeção de tráfego de rede HTTP/HTTPS (MobileNetworkProxy).
2. Captura em tempo real de eventos de Firebase Analytics (FA/FA-SVC no Android e
   Apple Unified Logging no iOS) com suporte completo à skill /tagueamento
   (cópia em formato TSV para Google Planilhas e exportação de log_obtido.json).

A plataforma selecionada no topo do app (🍎 iOS ou 🤖 Android) guia automaticamente:
- O tipo de conexão de rede e certificados;
- O comando nativo de streaming de logs de analytics (logcat vs simctl log stream);
- O formato e o nome dos botões e badges.
"""

import json
import tkinter as tk
import tkinter.font as tkfont
from tkinter import filedialog, messagebox, ttk
from typing import Callable, Dict, List, Optional, Tuple

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.analytics_logcat import AnalyticsEvent, analytics_listener
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.adapters.proxy import NetworkEvent, network_interceptor

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
    "table_bg": "#181825",
    "danger_color": "#F38BA8",
    "badge_active_bg": "#1B332A",
    "badge_active_fg": "#A6E3A1",
    "badge_inactive_bg": "#450A0A",
    "badge_inactive_fg": "#F38BA8",
}


def _draw_round_rect(canvas, x1, y1, x2, y2, radius=8, **kwargs):
    """Desenha um retângulo arredondado em Canvas com suavização Bézier."""
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
    Totalmente livre de bezels brancos nativos do macOS Tkinter.
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

        master_bg = master.cget("bg") if hasattr(master, "cget") else "#181825"
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


class UnderlineTabBar(tk.Frame):
    """
    Barra de abas alinhadas à esquerda com sublinhado ativo de 1.5px (#89B4FA).
    Substitui a aparência nativa centralizada do ttk.Notebook.
    """
    def __init__(
        self,
        master,
        tabs: List[str],
        command: Optional[Callable[[int], None]] = None,
        on_change: Optional[Callable[[int], None]] = None,
        bg="#181825",
        fg="#A6ADC8",
        active_fg="#CDD6F4",
        accent="#89B4FA",
        font=("Menlo", 10),
        height: int = 28,
        **kwargs
    ):
        super().__init__(master, bg=bg, **kwargs)
        self.tabs = tabs
        self.on_change = command or on_change
        self._bg = bg
        self._fg = fg
        self._active_fg = active_fg
        self._accent = accent
        self._font = font
        self._tab_height = height
        self.active_idx = 0
        self.tab_buttons: List[tk.Canvas] = []
        self._build()

    def _build(self):
        f = tkfont.Font(font=self._font)
        for idx, title in enumerate(self.tabs):
            tw = f.measure(title) + 18
            th = self._tab_height
            can = tk.Canvas(self, width=tw, height=th, bg=self._bg, bd=0, highlightthickness=0, cursor="hand2")
            can.pack(side=tk.LEFT, padx=(0, 4))
            can.bind("<Button-1>", lambda e, i=idx: self.select(i))
            self.tab_buttons.append(can)
        self._redraw()

    def select(self, idx: int):
        self.active_idx = idx
        self._redraw()
        if callable(self.on_change):
            self.on_change(idx)

    def _redraw(self):
        for idx, can in enumerate(self.tab_buttons):
            can.delete("all")
            w = can.winfo_width()
            h = can.winfo_height()
            if w <= 1 or h <= 1:
                try:
                    w = int(can.cget("width"))
                    h = int(can.cget("height"))
                except Exception:
                    w, h = 80, 28
            is_active = (idx == self.active_idx)
            color = self._active_fg if is_active else self._fg
            can.create_text(w // 2, (h - 4) // 2, text=self.tabs[idx], fill=color, font=self._font)
            line_color = self._accent if is_active else "#26263A"
            line_width = 2 if is_active else 1
            can.create_line(0, h - 2, w, h - 2, fill=line_color, width=line_width)

    def configure(self, **kwargs):
        if "bg" in kwargs:
            self._bg = kwargs.pop("bg")
            super().configure(bg=self._bg)
            for can in self.tab_buttons:
                can.configure(bg=self._bg)
        if "fg" in kwargs:
            self._fg = kwargs.pop("fg")
        if "active_fg" in kwargs:
            self._active_fg = kwargs.pop("active_fg")
        if "accent" in kwargs:
            self._accent = kwargs.pop("accent")
        if kwargs:
            super().configure(**kwargs)
        self._redraw()

    config = configure


class EmptyStateCard(tk.Frame):
    """Card minimalista para estado vazio (0 requisições / 0 eventos)."""
    def __init__(
        self,
        parent: tk.Widget,
        icon: str = "⇄",
        title: str = "Nenhuma requisição",
        subtitle: str = "Inicie o proxy e navegue no app para inspecionar tráfego.",
        theme: Optional[Dict[str, str]] = None,
        **kwargs,
    ):
        t = theme or THEME_PRAIA_DARK
        super().__init__(parent, bg=t.get("bg_subtle", t.get("panel_bg", "#181825")), **kwargs)
        self.configure(
            highlightbackground=t.get("border_subtle", "#26263A"),
            highlightthickness=1,
            padx=24,
            pady=24,
        )

        self.lbl_icon = tk.Label(
            self,
            text=icon,
            bg=t.get("bg_subtle", t.get("panel_bg", "#181825")),
            fg=t.get("accent", "#89B4FA"),
            font=("Helvetica", 28),
        )
        self.lbl_icon.pack(pady=(0, 8))

        self.lbl_title = tk.Label(
            self,
            text=title,
            bg=t.get("bg_subtle", t.get("panel_bg", "#181825")),
            fg=t.get("text_primary", "#CDD6F4"),
            font=("Menlo", 11, "bold"),
        )
        self.lbl_title.pack(pady=(0, 4))

        self.lbl_sub = tk.Label(
            self,
            text=subtitle,
            bg=t.get("bg_subtle", t.get("panel_bg", "#181825")),
            fg=t.get("text_secondary", "#A6ADC8"),
            font=("Menlo", 9),
            wraplength=340,
            justify=tk.CENTER,
        )
        self.lbl_sub.pack()

    def update_theme(self, t: Dict[str, str]):
        bg = t.get("bg_subtle", t.get("panel_bg", "#181825"))
        self.configure(bg=bg, highlightbackground=t.get("border_subtle", "#26263A"))
        self.lbl_icon.configure(bg=bg, fg=t.get("accent", "#89B4FA"))
        self.lbl_title.configure(bg=bg, fg=t.get("text_primary", "#CDD6F4"))
        self.lbl_sub.configure(bg=bg, fg=t.get("text_secondary", "#A6ADC8"))


class HTTPInspectorFrame(tk.Frame):
    """
    Componente integrado para inspeção de tráfego HTTP/HTTPS e Tagueamento de Analytics.
    Totalmente responsivo à plataforma ativa (iOS ou Android) com estética Praia Dark.
    """

    def __init__(
        self,
        parent: tk.Widget,
        adb_bridge: Optional[ADBBridge] = None,
        get_device_callback: Optional[Callable[[], Tuple[str, Optional[str]]]] = None,
        theme_dict: Optional[Dict[str, str]] = None,
        **kwargs,
    ):
        super().__init__(parent, **kwargs)
        self.adb = adb_bridge or ADBBridge()
        self.ios = IOSBridge()
        self.get_device_callback = get_device_callback
        self.proxy = network_interceptor
        self.analytics = analytics_listener

        # Tema Praia Dark
        self.current_theme = theme_dict or THEME_PRAIA_DARK.copy()
        self.configure(bg=self.current_theme.get("bg_window", "#1E1E2E"))

        self._setup_ttk_styles(self.current_theme)

        # Estado da Sub-Visão ('http' ou 'tag')
        self.active_subview = "http"
        self._last_known_platform = "android"
        self._selected_http_event: Optional[NetworkEvent] = None
        self._req_subtab_idx = 0
        self._resp_subtab_idx = 0

        # Variáveis - Aba HTTP
        self.http_search_var = tk.StringVar(value="")
        self.http_status_var = tk.StringVar(
            value="● Proxy Ativo (8082)" if self.proxy.is_running() else "○ Proxy Inativo (8082)"
        )
        self.http_count_var = tk.StringVar(value="Total: 0 requisições")
        self.displayed_http_events: Dict[str, NetworkEvent] = {}

        # Variáveis - Aba Tagueamento (Analytics)
        self.tag_search_var = tk.StringVar(value="")
        self.tag_status_var = tk.StringVar(value="Coleta Inativa")
        self.tag_count_var = tk.StringVar(value="Total: 0 eventos")
        self.displayed_tag_events: Dict[str, AnalyticsEvent] = {}

        self._is_active = True

        self._build_ui()
        self._load_existing_data()
        self._update_platform_ui()
        self._update_empty_states()

        # Iniciar polling contínuo (HTTP e Analytics)
        self.after(120, self._poll_events)

    def _setup_ttk_styles(self, t: Dict[str, str]):
        try:
            style = ttk.Style()
            style.theme_use("clam")
            # Ocultar abas nativas do ttk Notebook para usar UnderlineTabBar mantendo notebook.tabs() funcional
            style.layout("Hidden.TNotebook", [("Notebook.client", {"sticky": "nswe"})])
            style.layout("Hidden.TNotebook.Tab", [])

            # Estilo Praia Dark para tabelas Treeview (sem 3D, cabeçalhos alinhados à esquerda)
            style.configure(
                "Praia.Treeview",
                background=t.get("table_bg", t.get("bg_panel", "#181825")),
                foreground=t.get("text_primary", t.get("fg_color", "#CDD6F4")),
                fieldbackground=t.get("table_bg", t.get("bg_panel", "#181825")),
                borderwidth=0,
                highlightthickness=0,
                rowheight=24,
                font=("Menlo", 9),
            )
            style.configure(
                "Praia.Treeview.Heading",
                background=t.get("bg_toolbar", t.get("panel_bg", "#181825")),
                foreground=t.get("text_secondary", t.get("secondary_fg", "#A6ADC8")),
                relief="flat",
                borderwidth=0,
                font=("Menlo", 9, "bold"),
            )
            style.map(
                "Praia.Treeview",
                background=[("selected", t.get("selection_bg", "#283248"))],
                foreground=[("selected", t.get("text_primary", "#CDD6F4"))],
            )
            style.map(
                "Praia.Treeview.Heading",
                background=[("active", t.get("bg_toolbar", "#181825"))],
                foreground=[("active", t.get("text_primary", "#CDD6F4"))],
            )
        except Exception:
            pass

    def _get_platform_and_device(self) -> Tuple[str, Optional[str]]:
        if self.get_device_callback:
            plat, dev = self.get_device_callback()
            return (plat or "android").lower(), dev
        return "android", None

    def _build_ui(self):
        t = self.current_theme

        # 1. Barra Superior Principal: LINHA ÚNICA (Subtabs | Busca ⌕ | Ações | Limpar | Overflow ··· | Status & Total)
        self.top_bar = tk.Frame(self, bg=t.get("bg_toolbar", t["panel_bg"]), height=40, padx=8, pady=4)
        self.top_bar.pack(side=tk.TOP, fill=tk.X)

        # Seletor Segmentado (Pill Style): [ Tráfego HTTP ] [ Analytics ]
        self.subtabs_frame = tk.Frame(
            self.top_bar,
            bg=t.get("bg_control", "#11111B"),
            padx=2,
            pady=2,
            highlightthickness=1,
            highlightbackground=t.get("border_subtle", "#26263A"),
        )
        self.subtabs_frame.pack(side=tk.LEFT, padx=(0, 8))

        self.btn_subtab_http = FluidPillButton(
            self.subtabs_frame,
            text="Tráfego HTTP",
            command=lambda: self._set_subview("http"),
            bg=t.get("accent", "#89B4FA"),
            fg=t.get("accent_on", "#11111B"),
            font=("Helvetica", 9, "bold"),
            padx=10,
            pady=3,
        )
        self.btn_subtab_http.pack(side=tk.LEFT, padx=1)

        self.btn_subtab_tag = FluidPillButton(
            self.subtabs_frame,
            text="Analytics",
            command=lambda: self._set_subview("tag"),
            bg=t.get("bg_control", "#11111B"),
            fg=t.get("text_secondary", "#A6ADC8"),
            font=("Helvetica", 9, "bold"),
            padx=10,
            pady=3,
        )
        self.btn_subtab_tag.pack(side=tk.LEFT, padx=1)

        # Campo de Busca Único (Filtro) com glifo ⌕
        self.search_container = tk.Frame(
            self.top_bar,
            bg=t.get("input_bg", "#11111B"),
            highlightthickness=1,
            highlightbackground=t.get("border_subtle", "#26263A"),
            padx=6,
            pady=2,
        )
        self.search_container.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))

        self.lbl_search_glyph = tk.Label(
            self.search_container,
            text="⌕",
            bg=t.get("input_bg", "#11111B"),
            fg=t.get("text_label", "#6C7086"),
            font=("Menlo", 11),
        )
        self.lbl_search_glyph.pack(side=tk.LEFT, padx=(0, 4))

        insert_bg = "black" if t.get("name") == "light" else "white"
        self.entry_filter_http = tk.Entry(
            self.search_container,
            textvariable=self.http_search_var,
            bg=t.get("input_bg", "#11111B"),
            fg=t.get("fg_color", "#CDD6F4"),
            insertbackground=insert_bg,
            relief=tk.FLAT,
            font=("Menlo", 10),
        )
        self.http_search_var.trace_add("write", lambda *_: self._apply_http_filter())

        self.entry_filter_tag = tk.Entry(
            self.search_container,
            textvariable=self.tag_search_var,
            bg=t.get("input_bg", "#11111B"),
            fg=t.get("fg_color", "#CDD6F4"),
            insertbackground=insert_bg,
            relief=tk.FLAT,
            font=("Menlo", 10),
        )
        self.tag_search_var.trace_add("write", lambda *_: self._apply_tag_filter())

        # Exibe o entry correspondente à subview ativa
        self.entry_filter_http.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # Ações contextuais de visualização
        self.btn_export_har = FluidPillButton(
            self.top_bar,
            text="Exportar HAR",
            command=self._export_har,
            bg=t.get("btn_bg", "#11111B"),
            fg=t.get("fg_color", "#CDD6F4"),
            font=("Menlo", 9, "bold"),
            padx=10,
            pady=3,
        )
        self.btn_export_har.pack(side=tk.LEFT, padx=3)

        self.btn_copy_tsv = FluidPillButton(
            self.top_bar,
            text="Copiar TSV",
            command=self._copy_tsv_to_clipboard,
            bg=t.get("accent", "#89B4FA"),
            fg=t.get("accent_on", "#11111B"),
            font=("Menlo", 9, "bold"),
            padx=10,
            pady=3,
        )

        # Botão Limpar
        self.btn_clear = FluidPillButton(
            self.top_bar,
            text="Limpar",
            command=self._clear_active_view,
            bg=t.get("btn_bg", "#11111B"),
            fg=t.get("danger", "#F38BA8"),
            activeforeground=t.get("danger", "#F38BA8"),
            font=("Menlo", 9, "bold"),
            padx=10,
            pady=3,
        )
        self.btn_clear.pack(side=tk.LEFT, padx=3)

        # Botão Overflow "···" para Iniciar Proxy / Conectar / Ações Secundárias
        self.btn_overflow = FluidPillButton(
            self.top_bar,
            text="···",
            command=self._show_overflow_menu,
            bg=t.get("btn_bg", "#11111B"),
            fg=t.get("text_secondary", "#A6ADC8"),
            font=("Menlo", 10, "bold"),
            padx=8,
            pady=3,
        )
        self.btn_overflow.pack(side=tk.LEFT, padx=3)

        # Widgets virtuais de compatibilidade para métodos internos e testes existentes
        self.btn_toggle_proxy = FluidPillButton(self, text="Parar Proxy" if self.proxy.is_running() else "Iniciar Proxy", command=self._toggle_proxy)
        self.btn_device_proxy = FluidPillButton(self, text="Conectar Android (ADB)", command=self._setup_device_proxy)
        self.btn_device_reset = FluidPillButton(self, text="Desconectar ADB", command=self._teardown_device_proxy)
        self.btn_toggle_tag = FluidPillButton(self, text="Iniciar Coleta (Android)", command=self._toggle_analytics)
        self.btn_clear_logcat = FluidPillButton(self, text="Limpar Logcat (-c)", command=self._clear_device_logcat)
        self.btn_save_json = FluidPillButton(self, text="Salvar log_obtido.json", command=self._save_json_file)

        # Canto Direito: Contador + Badge de Status do Proxy
        self.lbl_count = tk.Label(
            self.top_bar,
            textvariable=self.http_count_var,
            bg=t.get("bg_toolbar", t["panel_bg"]),
            fg=t.get("text_tertiary", "#7F849C"),
            font=("Menlo", 9),
        )
        self.lbl_count.pack(side=tk.RIGHT, padx=(6, 0))

        b_bg = t.get("badge_active_bg", "#1B332A") if self.proxy.is_running() else t.get("badge_inactive_bg", "#450A0A")
        b_fg = t.get("badge_active_fg", "#A6E3A1") if self.proxy.is_running() else t.get("badge_inactive_fg", "#F38BA8")
        self.badge_status = tk.Label(
            self.top_bar,
            textvariable=self.http_status_var,
            bg=b_bg,
            fg=b_fg,
            font=("Menlo", 9, "bold"),
            padx=8,
            pady=2,
            highlightthickness=1,
            highlightbackground=t.get("border_subtle", "#26263A"),
        )
        self.badge_status.pack(side=tk.RIGHT, padx=4)

        # 2. Containers das Sub-Visões (SEM barras de ferramentas duplas intermediárias)
        self.http_container = tk.Frame(self, bg=t.get("bg_panel", t["panel_bg"]))
        self.tag_container = tk.Frame(self, bg=t.get("bg_panel", t["panel_bg"]))

        self._build_http_container(self.http_container)
        self._build_tag_container(self.tag_container)

        self.http_container.pack(fill=tk.BOTH, expand=True)

    # -------------------------------------------------------------------------
    # CONTAINER 1: TRÁFEGO HTTP / HTTPS
    # -------------------------------------------------------------------------

    def _build_http_container(self, parent: tk.Frame):
        t = self.current_theme
        insert_bg = "black" if t.get("name") == "light" else "white"

        # Painel Dividido Vertical: Tabela no Topo, Detalhes na Base
        self.paned_http = tk.PanedWindow(
            parent,
            orient=tk.VERTICAL,
            bg=t.get("border_subtle", "#26263A"),
            sashrelief=tk.FLAT,
            sashwidth=2,
        )
        self.paned_http.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)

        # Tabela de Requisições
        self.http_table_frame = tk.Frame(self.paned_http, bg=t.get("bg_panel", "#181825"))
        self.paned_http.add(self.http_table_frame, minsize=140, height=220)

        cols = ("id", "time", "method", "status", "host", "path", "duration")
        self.http_tree = ttk.Treeview(
            self.http_table_frame,
            columns=cols,
            show="headings",
            selectmode="browse",
            style="Praia.Treeview",
        )

        self.http_tree.heading("id", text="#", anchor=tk.W)
        self.http_tree.heading("time", text="Hora", anchor=tk.W)
        self.http_tree.heading("method", text="Método", anchor=tk.W)
        self.http_tree.heading("status", text="Status", anchor=tk.W)
        self.http_tree.heading("host", text="Host", anchor=tk.W)
        self.http_tree.heading("path", text="Path / Endpoint", anchor=tk.W)
        self.http_tree.heading("duration", text="Duração", anchor=tk.W)

        self.http_tree.column("id", width=40, minwidth=30, anchor=tk.W)
        self.http_tree.column("time", width=85, minwidth=75, anchor=tk.W)
        self.http_tree.column("method", width=75, minwidth=65, anchor=tk.W)
        self.http_tree.column("status", width=65, minwidth=55, anchor=tk.W)
        self.http_tree.column("host", width=180, minwidth=120, anchor=tk.W)
        self.http_tree.column("path", width=320, minwidth=150, anchor=tk.W)
        self.http_tree.column("duration", width=75, minwidth=60, anchor=tk.W)

        scroll_y = ttk.Scrollbar(self.http_table_frame, orient=tk.VERTICAL, command=self.http_tree.yview)
        scroll_x = ttk.Scrollbar(self.http_table_frame, orient=tk.HORIZONTAL, command=self.http_tree.xview)
        self.http_tree.configure(yscrollcommand=scroll_y.set, xscrollcommand=scroll_x.set)

        self.http_tree.grid(row=0, column=0, sticky="nsew")
        scroll_y.grid(row=0, column=1, sticky="ns")
        scroll_x.grid(row=1, column=0, sticky="ew")
        self.http_table_frame.grid_rowconfigure(0, weight=1)
        self.http_table_frame.grid_columnconfigure(0, weight=1)

        # Tags de coloração de métodos HTTP
        self.http_tree.tag_configure("GET", foreground="#A6E3A1")
        self.http_tree.tag_configure("POST", foreground="#89B4FA")
        self.http_tree.tag_configure("PUT", foreground="#F9E2AF")
        self.http_tree.tag_configure("DELETE", foreground="#F38BA8")
        self.http_tree.tag_configure("CONNECT", foreground="#CBA6F7")
        self.http_tree.tag_configure("OTHER", foreground=t.get("text_primary", "#CDD6F4"))

        self.http_tree.bind("<<TreeviewSelect>>", self._on_http_selected)

        # Empty State Card para HTTP
        self.empty_card_http = EmptyStateCard(
            self.http_table_frame,
            icon="⇄",
            title="Nenhuma requisição interceptada",
            subtitle="Inicie o proxy e navegue no app do dispositivo para inspecionar tráfego HTTP/HTTPS.",
            theme=t,
        )
        self.empty_card_http.place(relx=0.5, rely=0.5, anchor=tk.CENTER)

        # Detalhes: UnderlineTabBar + Hidden.TNotebook
        self.http_detail_frame = tk.Frame(self.paned_http, bg=t.get("bg_panel", "#181825"))
        self.paned_http.add(self.http_detail_frame, minsize=150, height=220)

        # Barra de abas principais com sublinhado ativo de 1.5px
        self.req_resp_tabbar = UnderlineTabBar(
            self.http_detail_frame,
            tabs=["Requisição (Request)", "Resposta (Response)"],
            command=self._on_req_resp_tab_change,
            bg=t.get("bg_toolbar", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
            font=("Menlo", 9, "bold"),
            height=30,
        )
        self.req_resp_tabbar.pack(side=tk.TOP, fill=tk.X)

        self.http_notebook = ttk.Notebook(self.http_detail_frame, style="Hidden.TNotebook")
        self.http_notebook.pack(fill=tk.BOTH, expand=True)
        self.notebook = self.http_notebook  # Retrocompatibilidade com testes!

        # Aba 1: Requisição (Request) com sub-abas Headers / Body / Raw
        self.req_tab = tk.Frame(self.http_notebook, bg=t.get("bg_panel", "#181825"))
        self.http_notebook.add(self.req_tab, text="Requisição (Request)")

        self.req_subtabbar = UnderlineTabBar(
            self.req_tab,
            tabs=["Headers", "Body", "Raw"],
            command=self._on_req_subtab_change,
            bg=t.get("bg_subtle", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
            font=("Menlo", 9),
            height=26,
        )
        self.req_subtabbar.pack(side=tk.TOP, fill=tk.X)

        self.txt_req = tk.Text(
            self.req_tab,
            bg=t.get("input_bg", "#11111B"),
            fg=t.get("fg_color", "#CDD6F4"),
            insertbackground=insert_bg,
            font=("Menlo", 10),
            relief=tk.FLAT,
            wrap=tk.NONE,
            padx=8,
            pady=8,
            spacing1=3,
            spacing3=3,
        )
        self.txt_req.pack(fill=tk.BOTH, expand=True)

        # Aba 2: Resposta (Response) com sub-abas Headers / Body / Raw
        self.resp_tab = tk.Frame(self.http_notebook, bg=t.get("bg_panel", "#181825"))
        self.http_notebook.add(self.resp_tab, text="Resposta (Response)")

        self.resp_subtabbar = UnderlineTabBar(
            self.resp_tab,
            tabs=["Headers", "Body", "Raw"],
            command=self._on_resp_subtab_change,
            bg=t.get("bg_subtle", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
            font=("Menlo", 9),
            height=26,
        )
        self.resp_subtabbar.pack(side=tk.TOP, fill=tk.X)

        self.txt_resp = tk.Text(
            self.resp_tab,
            bg=t.get("input_bg", "#11111B"),
            fg=t.get("fg_color", "#CDD6F4"),
            insertbackground=insert_bg,
            font=("Menlo", 10),
            relief=tk.FLAT,
            wrap=tk.NONE,
            padx=8,
            pady=8,
            spacing1=3,
            spacing3=3,
        )
        self.txt_resp.pack(fill=tk.BOTH, expand=True)

    # -------------------------------------------------------------------------
    # CONTAINER 2: TAGUEAMENTO ANALYTICS (ANDROID & IOS)
    # -------------------------------------------------------------------------

    def _build_tag_container(self, parent: tk.Frame):
        t = self.current_theme
        insert_bg = "black" if t.get("name") == "light" else "white"

        # Painel Dividido Vertical: Tabela no Topo, Detalhes na Base
        self.paned_tag = tk.PanedWindow(
            parent,
            orient=tk.VERTICAL,
            bg=t.get("border_subtle", "#26263A"),
            sashrelief=tk.FLAT,
            sashwidth=2,
        )
        self.paned_tag.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)

        # Tabela de Tags
        self.tag_table_frame = tk.Frame(self.paned_tag, bg=t.get("bg_panel", "#181825"))
        self.paned_tag.add(self.tag_table_frame, minsize=140, height=220)

        cols = ("id", "time", "plat", "tag", "event", "params_preview")
        self.tag_tree = ttk.Treeview(
            self.tag_table_frame,
            columns=cols,
            show="headings",
            selectmode="browse",
            style="Praia.Treeview",
        )

        self.tag_tree.heading("id", text="#", anchor=tk.W)
        self.tag_tree.heading("time", text="Hora", anchor=tk.W)
        self.tag_tree.heading("plat", text="Plat", anchor=tk.W)
        self.tag_tree.heading("tag", text="Origem", anchor=tk.W)
        self.tag_tree.heading("event", text="Nome do Evento (Analytics)", anchor=tk.W)
        self.tag_tree.heading("params_preview", text="Parâmetros Detectados", anchor=tk.W)

        self.tag_tree.column("id", width=35, minwidth=25, anchor=tk.W)
        self.tag_tree.column("time", width=85, minwidth=75, anchor=tk.W)
        self.tag_tree.column("plat", width=50, minwidth=40, anchor=tk.W)
        self.tag_tree.column("tag", width=85, minwidth=65, anchor=tk.W)
        self.tag_tree.column("event", width=220, minwidth=140, anchor=tk.W)
        self.tag_tree.column("params_preview", width=450, minwidth=200, anchor=tk.W)

        scroll_y = ttk.Scrollbar(self.tag_table_frame, orient=tk.VERTICAL, command=self.tag_tree.yview)
        scroll_x = ttk.Scrollbar(self.tag_table_frame, orient=tk.HORIZONTAL, command=self.tag_tree.xview)
        self.tag_tree.configure(yscrollcommand=scroll_y.set, xscrollcommand=scroll_x.set)

        self.tag_tree.grid(row=0, column=0, sticky="nsew")
        scroll_y.grid(row=0, column=1, sticky="ns")
        scroll_x.grid(row=1, column=0, sticky="ew")
        self.tag_table_frame.grid_rowconfigure(0, weight=1)
        self.tag_table_frame.grid_columnconfigure(0, weight=1)

        self.tag_tree.tag_configure("screen_view", foreground="#A6E3A1")
        self.tag_tree.tag_configure("interaction", foreground="#89B4FA")
        self.tag_tree.tag_configure("user_engagement", foreground="#CBA6F7")
        self.tag_tree.tag_configure("custom", foreground="#F9E2AF")

        self.tag_tree.bind("<<TreeviewSelect>>", self._on_tag_selected)

        # Empty State Card para Tags
        self.empty_card_tag = EmptyStateCard(
            self.tag_table_frame,
            icon="🏷",
            title="Nenhum evento de analytics capturado",
            subtitle="Inicie a coleta para interceptar logs de eventos Firebase, AppsFlyer e Adjust.",
            theme=t,
        )
        self.empty_card_tag.place(relx=0.5, rely=0.5, anchor=tk.CENTER)

        # Detalhes de Tagueamento
        self.tag_detail_frame = tk.Frame(self.paned_tag, bg=t.get("bg_panel", "#181825"))
        self.paned_tag.add(self.tag_detail_frame, minsize=150, height=220)

        self.tag_tabbar = UnderlineTabBar(
            self.tag_detail_frame,
            tabs=["JSON Estruturado (Skill /tagueamento)", "Log Bruto Original"],
            command=lambda idx: self.tag_notebook.select(idx),
            bg=t.get("bg_toolbar", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
            font=("Menlo", 9, "bold"),
            height=30,
        )
        self.tag_tabbar.pack(side=tk.TOP, fill=tk.X)

        self.tag_notebook = ttk.Notebook(self.tag_detail_frame, style="Hidden.TNotebook")
        self.tag_notebook.pack(fill=tk.BOTH, expand=True)

        # Sub-aba 1: JSON dos Parâmetros
        self.tab_tag_json = tk.Frame(self.tag_notebook, bg=t.get("bg_panel", "#181825"))
        self.tag_notebook.add(self.tab_tag_json, text="JSON Estruturado")
        self.txt_tag_json = tk.Text(
            self.tab_tag_json,
            bg=t.get("input_bg", "#11111B"),
            fg=t.get("badge_active_fg", "#A6E3A1"),
            insertbackground=insert_bg,
            font=("Menlo", 10),
            relief=tk.FLAT,
            wrap=tk.NONE,
            padx=8,
            pady=8,
            spacing1=3,
            spacing3=3,
        )
        self.txt_tag_json.pack(fill=tk.BOTH, expand=True)

        # Sub-aba 2: Log Bruto
        self.tab_tag_raw = tk.Frame(self.tag_notebook, bg=t.get("bg_panel", "#181825"))
        self.tag_notebook.add(self.tab_tag_raw, text="Log Bruto")
        self.txt_tag_raw = tk.Text(
            self.tab_tag_raw,
            bg=t.get("input_bg", "#11111B"),
            fg=t.get("secondary_fg", "#A6ADC8"),
            insertbackground=insert_bg,
            font=("Menlo", 10),
            relief=tk.FLAT,
            wrap=tk.WORD,
            padx=8,
            pady=8,
            spacing1=3,
            spacing3=3,
        )
        self.txt_tag_raw.pack(fill=tk.BOTH, expand=True)

    # -------------------------------------------------------------------------
    # TRATAMENTO DE ABAS E SUB-ABAS
    # -------------------------------------------------------------------------

    def _on_req_resp_tab_change(self, idx: int):
        self.http_notebook.select(idx)

    def _on_req_subtab_change(self, idx: int):
        self._req_subtab_idx = idx
        self._render_req_details()

    def _on_resp_subtab_change(self, idx: int):
        self._resp_subtab_idx = idx
        self._render_resp_details()

    def _render_req_details(self):
        ev = self._selected_http_event
        if not ev:
            return
        self.txt_req.delete("1.0", tk.END)
        idx = self._req_subtab_idx
        if idx == 0:  # Headers
            lines = [f"{k}: {v}" for k, v in ev.request_headers.items()]
            self.txt_req.insert(tk.END, "\n".join(lines) if lines else "(Nenhum cabeçalho)")
        elif idx == 1:  # Body
            if ev.request_body:
                try:
                    self.txt_req.insert(tk.END, json.dumps(json.loads(ev.request_body), indent=2, ensure_ascii=False))
                except Exception:
                    self.txt_req.insert(tk.END, ev.request_body)
            else:
                self.txt_req.insert(tk.END, "(Corpo vazio)")
        else:  # Raw
            self.txt_req.insert(tk.END, self._format_request_text(ev))

    def _render_resp_details(self):
        ev = self._selected_http_event
        if not ev:
            return
        self.txt_resp.delete("1.0", tk.END)
        idx = self._resp_subtab_idx
        if idx == 0:  # Headers
            lines = [f"{k}: {v}" for k, v in ev.response_headers.items()]
            self.txt_resp.insert(tk.END, "\n".join(lines) if lines else "(Nenhum cabeçalho)")
        elif idx == 1:  # Body
            if ev.response_body:
                try:
                    self.txt_resp.insert(tk.END, json.dumps(json.loads(ev.response_body), indent=2, ensure_ascii=False))
                except Exception:
                    self.txt_resp.insert(tk.END, ev.response_body)
            else:
                self.txt_resp.insert(tk.END, "(Corpo vazio)")
        else:  # Raw
            self.txt_resp.insert(tk.END, self._format_response_text(ev))

    def _update_empty_states(self):
        # HTTP
        if len(self.displayed_http_events) == 0:
            self.empty_card_http.place(relx=0.5, rely=0.5, anchor=tk.CENTER)
        else:
            self.empty_card_http.place_forget()

        # TAG
        if len(self.displayed_tag_events) == 0:
            self.empty_card_tag.place(relx=0.5, rely=0.5, anchor=tk.CENTER)
        else:
            self.empty_card_tag.place_forget()

    def _show_overflow_menu(self):
        plat, _ = self._get_platform_and_device()
        t = self.current_theme

        menu = tk.Menu(
            self,
            tearoff=0,
            bg=t.get("bg_panel", "#181825"),
            fg=t.get("text_primary", "#CDD6F4"),
            activebackground=t.get("selection_bg", "#283248"),
            activeforeground=t.get("text_primary", "#CDD6F4"),
            relief=tk.FLAT,
            font=("Menlo", 10),
        )

        proxy_running = self.proxy.is_running()
        menu.add_command(
            label="⏹ Parar Proxy" if proxy_running else "▶ Iniciar Proxy",
            command=self._toggle_proxy,
        )

        dev_label = "📱 Conectar iOS (Simulador)" if plat == "ios" else "📱 Conectar Android (ADB)"
        menu.add_command(label=dev_label, command=self._setup_device_proxy)
        reset_label = "🔌 Desconectar iOS" if plat == "ios" else "🔌 Desconectar ADB"
        menu.add_command(label=reset_label, command=self._teardown_device_proxy)

        menu.add_separator()

        tag_running = self.analytics.is_running()
        tag_toggle_label = f"⏹ Parar Coleta ({plat.upper()})" if tag_running else f"🏷 Iniciar Coleta ({plat.upper()})"
        menu.add_command(label=tag_toggle_label, command=self._toggle_analytics)

        if plat == "android":
            menu.add_command(label="🧹 Limpar Logcat (-c)", command=self._clear_device_logcat)

        menu.add_command(label="💾 Salvar log_obtido.json", command=self._save_json_file)

        menu.add_separator()
        menu.add_command(label="📄 Exportar Tráfego HAR", command=self._export_har)

        try:
            x = self.btn_overflow.winfo_rootx()
            y = self.btn_overflow.winfo_rooty() + self.btn_overflow.winfo_height()
            menu.tk_popup(x, y)
        finally:
            menu.grab_release()

    def _export_har(self):
        """Exporta requisições capturadas no formato HAR (HTTP Archive)."""
        if not self.displayed_http_events:
            messagebox.showinfo("Exportar HAR", "Nenhuma requisição para exportar.", parent=self)
            return

        file_path = filedialog.asksaveasfilename(
            parent=self,
            title="Exportar Arquivo HAR",
            defaultextension=".har",
            filetypes=[("HTTP Archive", "*.har"), ("JSON files", "*.json"), ("All Files", "*.*")],
            initialfile="network_traffic.har",
        )
        if not file_path:
            return

        har_data = {
            "log": {
                "version": "1.2",
                "creator": {"name": "Mo baile Inspector", "version": "2.0"},
                "entries": [],
            }
        }
        for ev in self.displayed_http_events.values():
            entry = {
                "startedDateTime": ev.time_str,
                "time": ev.duration_ms,
                "request": {
                    "method": ev.method,
                    "url": ev.url,
                    "httpVersion": ev.protocol,
                    "headers": [{"name": k, "value": v} for k, v in ev.request_headers.items()],
                    "postData": {"mimeType": "application/json", "text": ev.request_body} if ev.request_body else {},
                },
                "response": {
                    "status": ev.status_code,
                    "statusText": ev.status_text,
                    "httpVersion": ev.protocol,
                    "headers": [{"name": k, "value": v} for k, v in ev.response_headers.items()],
                    "content": {"mimeType": "application/json", "text": ev.response_body} if ev.response_body else {},
                },
            }
            har_data["log"]["entries"].append(entry)

        try:
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(har_data, f, indent=2, ensure_ascii=False)
            messagebox.showinfo("Sucesso", f"Arquivo HAR salvo com sucesso:\n{file_path}", parent=self)
        except Exception as e:
            messagebox.showerror("Erro ao Salvar", str(e), parent=self)

    # -------------------------------------------------------------------------
    # ADAPTAÇÃO DINÂMICA DA PLATAFORMA (iOS vs Android)
    # -------------------------------------------------------------------------

    def _on_platform_changed(self):
        """Chamado quando o usuário altera a plataforma no topo do app."""
        self._update_platform_ui()

    def _update_platform_ui(self):
        plat, _ = self._get_platform_and_device()
        self._last_known_platform = plat

        if plat == "ios":
            if not self.proxy.is_running():
                self.btn_device_proxy.config(text="Conectar iOS (Simulador)")
            self.btn_device_reset.config(text="Desconectar iOS")
            if not self.analytics.is_running():
                self.btn_toggle_tag.config(text="Iniciar Coleta (iOS)")
        else:
            if not self.proxy.is_running():
                self.btn_device_proxy.config(text="Conectar Android (ADB)")
            self.btn_device_reset.config(text="Desconectar ADB")
            if not self.analytics.is_running():
                self.btn_toggle_tag.config(text="Iniciar Coleta (Android)")

    def _set_subview(self, view_name: str):
        self.active_subview = view_name
        t = self.current_theme

        if view_name == "http":
            self.tag_container.pack_forget()
            self.http_container.pack(fill=tk.BOTH, expand=True)

            self.btn_subtab_http.config(
                bg=t.get("accent", "#89B4FA"),
                fg=t.get("accent_on", "#11111B"),
            )
            self.btn_subtab_tag.config(
                bg=t.get("bg_control", "#11111B"),
                fg=t.get("text_secondary", "#A6ADC8"),
            )
            self.entry_filter_tag.pack_forget()
            self.entry_filter_http.pack(side=tk.LEFT, fill=tk.X, expand=True)
            self.btn_copy_tsv.pack_forget()
            self.btn_export_har.pack(side=tk.LEFT, padx=3, before=self.btn_clear)
            self.lbl_count.config(textvariable=self.http_count_var)
        else:
            self.http_container.pack_forget()
            self.tag_container.pack(fill=tk.BOTH, expand=True)

            self.btn_subtab_tag.config(
                bg=t.get("accent", "#89B4FA"),
                fg=t.get("accent_on", "#11111B"),
            )
            self.btn_subtab_http.config(
                bg=t.get("bg_control", "#11111B"),
                fg=t.get("text_secondary", "#A6ADC8"),
            )
            self.entry_filter_http.pack_forget()
            self.entry_filter_tag.pack(side=tk.LEFT, fill=tk.X, expand=True)
            self.btn_export_har.pack_forget()
            self.btn_copy_tsv.pack(side=tk.LEFT, padx=3, before=self.btn_clear)
            self.lbl_count.config(textvariable=self.tag_count_var)

    # -------------------------------------------------------------------------
    # CONEXÃO DE DISPOSITIVO (Android ADB vs iOS Simulator)
    # -------------------------------------------------------------------------

    def _setup_device_proxy(self):
        plat, dev_id = self._get_platform_and_device()
        t = self.current_theme

        # 1. Loading visual suave em tempo real (sem popup)
        self.btn_device_proxy.config(
            text="Conectando...",
            fg=t.get("secondary_fg", "#8E8E93"),
            state=tk.DISABLED,
        )
        self.update_idletasks()

        def run_connect():
            try:
                if not self.proxy.is_running():
                    started = self.proxy.start()
                    if started:
                        self.http_status_var.set("Proxy Ativo (Porta 8082)")
                        b_bg = t.get("badge_active_bg", t["surface_bg"])
                        b_fg = t.get("badge_active_fg", "#30D158")
                        self.badge_status.config(bg=b_bg, fg=b_fg)
                        self.btn_toggle_proxy.config(text="Parar Proxy")

                if plat == "ios":
                    # Conexão iOS Simulator
                    booted = self.ios.list_booted_simulators()
                    if not booted:
                        self.btn_device_proxy.config(text="Conectar iOS (Simulador)", fg=t["fg_color"], state=tk.NORMAL)
                        messagebox.showerror(
                            "Simulador Não Encontrado",
                            "Nenhum simulador iOS ativo foi detectado.\nAbra o Simulator antes de conectar.",
                            parent=self,
                        )
                        return

                    # Sucesso silencioso e fluido
                    self.btn_device_proxy.config(
                        text="✓ iOS Conectado",
                        fg="#30D158" if t.get("name") == "dark" else "#248A3D",
                        state=tk.NORMAL,
                    )
                else:
                    # Conexão Android ADB
                    active_dev = dev_id
                    if not active_dev:
                        devices = self.adb.list_devices()
                        if devices:
                            active_dev = devices[0][0]

                    if not active_dev:
                        self.btn_device_proxy.config(text="Conectar Android (ADB)", fg=t["fg_color"], state=tk.NORMAL)
                        messagebox.showerror(
                            "Dispositivo Não Encontrado",
                            "Nenhum dispositivo Android foi detectado via ADB.\nVerifique a conexão USB do aparelho.",
                            parent=self,
                        )
                        return

                    ok = self.adb.setup_reverse_proxy(active_dev, proxy_port=8082)
                    if ok:
                        self.btn_device_proxy.config(
                            text="✓ Android Conectado",
                            fg="#30D158" if t.get("name") == "dark" else "#248A3D",
                            state=tk.NORMAL,
                        )
                    else:
                        self.btn_device_proxy.config(text="Conectar Android (ADB)", fg=t["fg_color"], state=tk.NORMAL)
                        messagebox.showerror(
                            "Falha ao Configurar",
                            f"Não foi possível configurar o proxy no dispositivo '{active_dev}'.",
                            parent=self,
                        )

            except Exception as e:
                orig_label = "Conectar iOS (Simulador)" if plat == "ios" else "Conectar Android (ADB)"
                self.btn_device_proxy.config(text=orig_label, fg=t["fg_color"], state=tk.NORMAL)
                messagebox.showerror("Erro ao Conectar", str(e), parent=self)

        self.after(50, run_connect)

    def _teardown_device_proxy(self):
        plat, dev_id = self._get_platform_and_device()
        t = self.current_theme

        self.btn_device_reset.config(text="Desconectando...", state=tk.DISABLED)
        self.update_idletasks()

        def run_disconnect():
            try:
                if plat == "android":
                    active_dev = dev_id or (self.adb.list_devices()[0][0] if self.adb.list_devices() else None)
                    if active_dev:
                        self.adb.teardown_reverse_proxy(active_dev, proxy_port=8082)

                self.btn_device_reset.config(text="Desconectar " + ("iOS" if plat == "ios" else "ADB"), state=tk.NORMAL)
                self.btn_device_proxy.config(
                    text="Conectar iOS (Simulador)" if plat == "ios" else "Conectar Android (ADB)",
                    fg=t["fg_color"],
                    state=tk.NORMAL,
                )
            except Exception as e:
                self.btn_device_reset.config(text="Desconectar " + ("iOS" if plat == "ios" else "ADB"), state=tk.NORMAL)
                messagebox.showerror("Erro ao Desconectar", str(e), parent=self)

        self.after(50, run_disconnect)

    # -------------------------------------------------------------------------
    # OPERAÇÕES DE TAGUEAMENTO / ANALYTICS
    # -------------------------------------------------------------------------

    def _toggle_analytics(self):
        plat, dev_id = self._get_platform_and_device()
        t = self.current_theme

        if self.analytics.is_running():
            self.analytics.stop()
            self.tag_status_var.set("Coleta de Tags Inativa")
            orig_text = f"Iniciar Coleta ({'iOS' if plat == 'ios' else 'Android'})"
            self.btn_toggle_tag.config(text=orig_text, fg=t["accent_color"])
        else:
            self.btn_toggle_tag.config(text="Iniciando...", state=tk.DISABLED)
            self.update_idletasks()

            def run_start_tag():
                try:
                    started = self.analytics.start(platform=plat, device_id=dev_id)
                    if started:
                        self.tag_status_var.set(f"Coleta Ativa ({plat.upper()})")
                        self.btn_toggle_tag.config(text="Parar Coleta", fg=t.get("danger_color", "#FF453A"), state=tk.NORMAL)
                    else:
                        orig = f"Iniciar Coleta ({'iOS' if plat == 'ios' else 'Android'})"
                        self.btn_toggle_tag.config(text=orig, fg=t["accent_color"], state=tk.NORMAL)
                        messagebox.showerror("Erro", f"Não foi possível iniciar a coleta de logs no {plat.upper()}.", parent=self)
                except Exception as e:
                    orig = f"Iniciar Coleta ({'iOS' if plat == 'ios' else 'Android'})"
                    self.btn_toggle_tag.config(text=orig, fg=t["accent_color"], state=tk.NORMAL)
                    messagebox.showerror("Erro de Coleta", str(e), parent=self)

            self.after(50, run_start_tag)

    def _clear_device_logcat(self):
        plat, dev_id = self._get_platform_and_device()
        if plat == "android":
            self.analytics.clear_device_logcat(dev_id)
            # Feedback visual leve no botão sem popup
            orig = self.btn_clear_logcat.cget("text")
            self.btn_clear_logcat.config(text="✓ Logcat Limpo!")
            self.after(1200, lambda: self.btn_clear_logcat.config(text=orig))

    def _copy_tsv_to_clipboard(self):
        tsv = self.analytics.export_as_tsv()
        self.clipboard_clear()
        self.clipboard_append(tsv)
        # Feedback visual sutil no botão sem popup
        orig = self.btn_copy_tsv.cget("text")
        self.btn_copy_tsv.config(text="✓ Copiado para Planilhas!")
        self.after(1400, lambda: self.btn_copy_tsv.config(text=orig))

    def _save_json_file(self):
        json_content = self.analytics.export_as_json()
        path = filedialog.asksaveasfilename(
            parent=self,
            title="Salvar log_obtido.json",
            defaultextension=".json",
            initialfile="log_obtido.json",
            filetypes=[("JSON Files", "*.json"), ("All Files", "*.*")],
        )
        if path:
            try:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(json_content)
                orig = self.btn_save_json.cget("text")
                self.btn_save_json.config(text="✓ Arquivo Salvo!")
                self.after(1400, lambda: self.btn_save_json.config(text=orig))
            except Exception as e:
                messagebox.showerror("Erro ao Salvar", str(e), parent=self)

    def _clear_active_view(self):
        if self.active_subview == "http":
            self._clear_http()
        else:
            self._clear_tags()

    def _clear_tags(self):
        self.analytics.clear_history()
        self.displayed_tag_events.clear()
        self.tag_tree.delete(*self.tag_tree.get_children())
        self.txt_tag_json.delete("1.0", tk.END)
        self.txt_tag_raw.delete("1.0", tk.END)
        self.tag_count_var.set("Total: 0 eventos")
        self._update_empty_states()

    def _clear_http(self):
        self.proxy.clear_history()
        self.displayed_http_events.clear()
        self.http_tree.delete(*self.http_tree.get_children())
        self.txt_req.delete("1.0", tk.END)
        self.txt_resp.delete("1.0", tk.END)
        self._selected_http_event = None
        self.http_count_var.set("Total: 0 requisições")
        self._update_empty_states()

    # -------------------------------------------------------------------------
    # POLLING E SELEÇÃO DE ITENS
    # -------------------------------------------------------------------------

    def _poll_events(self):
        if not self._is_active:
            return

        # Verifica se a plataforma mudou externamente
        cur_plat, _ = self._get_platform_and_device()
        if cur_plat != self._last_known_platform:
            self._update_platform_ui()

        # Drena fila HTTP
        http_cnt = 0
        while not self.proxy.event_queue.empty() and http_cnt < 30:
            try:
                ev = self.proxy.event_queue.get_nowait()
                self._insert_http_event(ev)
                http_cnt += 1
            except Exception:
                break
        if http_cnt > 0:
            self.http_count_var.set(f"Total: {len(self.proxy.events_history)} requisições")

        # Drena fila de Analytics
        tag_cnt = 0
        while not self.analytics.event_queue.empty() and tag_cnt < 30:
            try:
                tag_ev = self.analytics.event_queue.get_nowait()
                self._insert_tag_event(tag_ev)
                tag_cnt += 1
            except Exception:
                break
        if tag_cnt > 0:
            self.tag_count_var.set(f"Total: {len(self.analytics.events_history)} eventos")

        if self.winfo_exists():
            self.after(120, self._poll_events)

    def _load_existing_data(self):
        for ev in self.proxy.events_history:
            self._insert_http_event(ev)
        self.http_count_var.set(f"Total: {len(self.proxy.events_history)} requisições")

        for tag_ev in self.analytics.events_history:
            self._insert_tag_event(tag_ev)
        self.tag_count_var.set(f"Total: {len(self.analytics.events_history)} eventos")

    def _insert_http_event(self, event: NetworkEvent):
        self.displayed_http_events[str(event.id)] = event
        search = self.http_search_var.get().lower().strip()
        if search:
            match = (
                search in event.url.lower()
                or search in event.method.lower()
                or search in event.host.lower()
                or search in str(event.status_code)
            )
            if not match:
                self._update_empty_states()
                return

        tag = event.method if event.method in ("GET", "POST", "PUT", "DELETE", "CONNECT") else "OTHER"
        status_display = str(event.status_code) if event.status_code else "-"
        duration_display = f"{event.duration_ms:.0f} ms"

        self.http_tree.insert(
            "",
            0,
            iid=str(event.id),
            values=(
                event.id,
                event.time_str,
                event.method,
                status_display,
                event.host,
                event.path,
                duration_display,
            ),
            tags=(tag,),
        )
        self._update_empty_states()

    def _apply_http_filter(self):
        self.http_tree.delete(*self.http_tree.get_children())
        search = self.http_search_var.get().lower().strip()
        for ev in reversed(self.proxy.events_history):
            if not search or (
                search in ev.url.lower()
                or search in ev.method.lower()
                or search in ev.host.lower()
                or search in str(ev.status_code)
            ):
                tag = ev.method if ev.method in ("GET", "POST", "PUT", "DELETE", "CONNECT") else "OTHER"
                status_display = str(ev.status_code) if ev.status_code else "-"
                duration_display = f"{ev.duration_ms:.0f} ms"
                self.http_tree.insert(
                    "",
                    tk.END,
                    iid=str(ev.id),
                    values=(
                        ev.id,
                        ev.time_str,
                        ev.method,
                        status_display,
                        ev.host,
                        ev.path,
                        duration_display,
                    ),
                    tags=(tag,),
                )
        self._update_empty_states()

    def _insert_tag_event(self, event: AnalyticsEvent):
        self.displayed_tag_events[str(event.id)] = event
        search = self.tag_search_var.get().lower().strip()
        if search:
            match = (
                search in event.event_name.lower()
                or search in event.tag.lower()
                or any(search in f"{k} {v}".lower() for k, v in event.params.items())
            )
            if not match:
                self._update_empty_states()
                return

        tag_style = "custom"
        ev_lower = event.event_name.lower()
        if "screen" in ev_lower:
            tag_style = "screen_view"
        elif any(w in ev_lower for w in ("interaction", "click", "botao", "touch")):
            tag_style = "interaction"
        elif "engagement" in ev_lower or "session" in ev_lower:
            tag_style = "user_engagement"

        preview_items = [f"{k}: {v}" for k, v in list(event.params.items())[:4]]
        preview_str = " | ".join(preview_items) if preview_items else "(Sem parâmetros)"

        self.tag_tree.insert(
            "",
            0,
            iid=str(event.id),
            values=(
                event.id,
                event.time_str,
                event.platform.upper(),
                event.tag,
                event.event_name,
                preview_str,
            ),
            tags=(tag_style,),
        )
        self._update_empty_states()

    def _apply_tag_filter(self):
        self.tag_tree.delete(*self.tag_tree.get_children())
        search = self.tag_search_var.get().lower().strip()
        for ev in reversed(self.analytics.events_history):
            if not search or (
                search in ev.event_name.lower()
                or search in ev.tag.lower()
                or any(search in f"{k} {v}".lower() for k, v in ev.params.items())
            ):
                tag_style = "custom"
                ev_lower = ev.event_name.lower()
                if "screen" in ev_lower:
                    tag_style = "screen_view"
                elif any(w in ev_lower for w in ("interaction", "click", "botao", "touch")):
                    tag_style = "interaction"
                elif "engagement" in ev_lower or "session" in ev_lower:
                    tag_style = "user_engagement"

                preview_items = [f"{k}: {v}" for k, v in list(ev.params.items())[:4]]
                preview_str = " | ".join(preview_items) if preview_items else "(Sem parâmetros)"

                self.tag_tree.insert(
                    "",
                    tk.END,
                    iid=str(ev.id),
                    values=(
                        ev.id,
                        ev.time_str,
                        ev.platform.upper(),
                        ev.tag,
                        ev.event_name,
                        preview_str,
                    ),
                    tags=(tag_style,),
                )
        self._update_empty_states()

    def _on_http_selected(self, _=None):
        sel = self.http_tree.selection()
        if not sel:
            return
        ev = self.displayed_http_events.get(sel[0])
        if not ev:
            return

        self._selected_http_event = ev
        self._render_req_details()
        self._render_resp_details()

    def _on_tag_selected(self, _=None):
        sel = self.tag_tree.selection()
        if not sel:
            return
        ev = self.displayed_tag_events.get(sel[0])
        if not ev:
            return

        # 1. JSON estruturado dos parâmetros (padrão /tagueamento)
        self.txt_tag_json.delete("1.0", tk.END)
        json_obj = {
            "event_name": ev.event_name,
            "platform": ev.platform,
            "origin": ev.tag,
            "timestamp": ev.time_str,
            "params": ev.params,
        }
        self.txt_tag_json.insert(tk.END, json.dumps(json_obj, indent=2, ensure_ascii=False))

        # 2. Log bruto
        self.txt_tag_raw.delete("1.0", tk.END)
        self.txt_tag_raw.insert(tk.END, ev.raw_log)

    def _format_request_text(self, ev: NetworkEvent) -> str:
        req_text = f"URL: {ev.url}\nMÉTODO: {ev.method}\nPROTOCOLO: {ev.protocol}\n\n--- CABEÇALHOS ---\n"
        for k, v in ev.request_headers.items():
            req_text += f"{k}: {v}\n"
        req_text += "\n--- CORPO (BODY) ---\n"
        if ev.request_body:
            try:
                req_text += json.dumps(json.loads(ev.request_body), indent=2, ensure_ascii=False)
            except Exception:
                req_text += ev.request_body
        else:
            req_text += "(Vazio)"
        return req_text

    def _format_response_text(self, ev: NetworkEvent) -> str:
        resp_text = (
            f"STATUS: {ev.status_code} {ev.status_text}\n"
            f"DURAÇÃO: {ev.duration_ms:.1f} ms\n\n"
            f"--- CABEÇALHOS ---\n"
        )
        for k, v in ev.response_headers.items():
            resp_text += f"{k}: {v}\n"
        resp_text += "\n--- CORPO (BODY) ---\n"
        if ev.response_body:
            try:
                resp_text += json.dumps(json.loads(ev.response_body), indent=2, ensure_ascii=False)
            except Exception:
                resp_text += ev.response_body
        else:
            resp_text += "(Vazio)"
        return resp_text

    def _toggle_proxy(self):
        t = self.current_theme
        if self.proxy.is_running():
            self.proxy.stop()
            self.http_status_var.set("○ Proxy Inativo (8082)")
            b_bg = t.get("badge_inactive_bg", "#450A0A")
            b_fg = t.get("badge_inactive_fg", "#F38BA8")
            self.badge_status.config(bg=b_bg, fg=b_fg)
            self.btn_toggle_proxy.config(text="Iniciar Proxy")
        else:
            started = self.proxy.start()
            if started:
                self.http_status_var.set("● Proxy Ativo (8082)")
                b_bg = t.get("badge_active_bg", "#1B332A")
                b_fg = t.get("badge_active_fg", "#A6E3A1")
                self.badge_status.config(bg=b_bg, fg=b_fg)
                self.btn_toggle_proxy.config(text="Parar Proxy")
            else:
                messagebox.showerror(
                    "Erro ao Iniciar",
                    "Não foi possível iniciar o proxy na porta 8082.",
                    parent=self,
                )

    def apply_theme(self, theme_dict: Dict[str, str]):
        self.current_theme = theme_dict
        t = theme_dict

        self.configure(bg=t.get("bg_window", "#1E1E2E"))
        self.top_bar.configure(bg=t.get("bg_toolbar", t.get("panel_bg", "#181825")))
        self.http_container.configure(bg=t.get("bg_panel", "#181825"))
        self.tag_container.configure(bg=t.get("bg_panel", "#181825"))

        self.subtabs_frame.configure(bg=t.get("bg_control", "#11111B"))
        self.search_container.configure(bg=t.get("input_bg", "#11111B"))
        self.lbl_search_glyph.configure(bg=t.get("input_bg", "#11111B"), fg=t.get("text_label", "#6C7086"))

        b_bg = t.get("badge_active_bg", "#1B332A") if self.proxy.is_running() else t.get("badge_inactive_bg", "#450A0A")
        b_fg = t.get("badge_active_fg", "#A6E3A1") if self.proxy.is_running() else t.get("badge_inactive_fg", "#F38BA8")
        self.badge_status.configure(bg=b_bg, fg=b_fg)

        insert_bg = "black" if t.get("name") == "light" else "white"
        self.entry_filter_http.configure(bg=t.get("input_bg", "#11111B"), fg=t.get("fg_color", "#CDD6F4"), insertbackground=insert_bg)
        self.entry_filter_tag.configure(bg=t.get("input_bg", "#11111B"), fg=t.get("fg_color", "#CDD6F4"), insertbackground=insert_bg)

        self.req_tab.configure(bg=t.get("bg_panel", "#181825"))
        self.resp_tab.configure(bg=t.get("bg_panel", "#181825"))
        self.tab_tag_json.configure(bg=t.get("bg_panel", "#181825"))
        self.tab_tag_raw.configure(bg=t.get("bg_panel", "#181825"))

        self.txt_req.configure(bg=t.get("input_bg", "#11111B"), fg=t.get("fg_color", "#CDD6F4"), insertbackground=insert_bg)
        self.txt_resp.configure(bg=t.get("input_bg", "#11111B"), fg=t.get("fg_color", "#CDD6F4"), insertbackground=insert_bg)
        self.txt_tag_json.configure(bg=t.get("input_bg", "#11111B"), insertbackground=insert_bg)
        self.txt_tag_raw.configure(bg=t.get("input_bg", "#11111B"), fg=t.get("secondary_fg", "#A6ADC8"), insertbackground=insert_bg)

        self.req_resp_tabbar.configure(
            bg=t.get("bg_toolbar", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
        )
        self.req_subtabbar.configure(
            bg=t.get("bg_subtle", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
        )
        self.resp_subtabbar.configure(
            bg=t.get("bg_subtle", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
        )
        self.tag_tabbar.configure(
            bg=t.get("bg_toolbar", "#181825"),
            fg=t.get("text_secondary", "#A6ADC8"),
            active_fg=t.get("text_primary", "#CDD6F4"),
            accent=t.get("accent", "#89B4FA"),
        )

        self.empty_card_http.update_theme(t)
        self.empty_card_tag.update_theme(t)
        self._setup_ttk_styles(t)

    def destroy_resources(self):
        self._is_active = False
        if self.analytics.is_running():
            self.analytics.stop()


class HTTPViewerWindow:
    """Janela auxiliar retrocompatível."""

    def __init__(
        self,
        parent: tk.Tk,
        adb_bridge: Optional[ADBBridge] = None,
        get_device_callback: Optional[Callable[[], Tuple[str, Optional[str]]]] = None,
        theme_dict: Optional[Dict[str, str]] = None,
    ):
        self.parent = parent
        self.window = tk.Toplevel(parent)
        self.window.title("Inspetor de Tráfego e Tagueamento - Mobile Recorder")
        self.window.geometry("1160x740")
        self.window.minsize(920, 560)

        self.frame = HTTPInspectorFrame(
            self.window,
            adb_bridge=adb_bridge,
            get_device_callback=get_device_callback,
            theme_dict=theme_dict,
        )
        self.frame.pack(fill=tk.BOTH, expand=True)
        self.window.protocol("WM_DELETE_WINDOW", self._on_close)

    def _on_close(self):
        self.frame.destroy_resources()
        self.window.destroy()

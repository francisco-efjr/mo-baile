"""
Diálogos de Estrutura e Execução da Automação
--------------------------------------------
Fornece janelas para:
1. AutomationStructureDialog: Visualização tabular da estrutura ordenada dos passos gravados.
2. AutomationExecutionDialog: Execução em tempo real do script oculto (.flow_runner.py)
   com validação de pré-condições e streaming de logs.
"""

import os
import time
import tkinter as tk
from tkinter import messagebox, scrolledtext, ttk
from typing import Callable, List, Optional

from mobaile.services.codegen import AutomationStep
from mobaile.services.flows import (
    generate_hidden_runner_script,
    run_flow_in_background,
    verify_preconditions,
)


class FluidPillButton(tk.Label):
    """Botão em formato de pílula (Apple HIG Style)."""
    def __init__(
        self,
        master,
        text="",
        command=None,
        bg="#28282C",
        fg="#FFFFFF",
        activebackground="#343438",
        activeforeground=None,
        font=("Helvetica", 10),
        padx=10,
        pady=3,
        cursor="hand2",
        relief=tk.FLAT,
        state="normal",
        **kwargs
    ):
        self.command = command
        self._bg_normal = bg
        self._fg_normal = fg
        self._bg_hover = activebackground or bg
        self._fg_hover = activeforeground or fg
        self._state = state
        self._is_hovered = False
        self._is_pressed = False

        kwargs.pop("relief", None)
        super().__init__(
            master,
            text=text,
            bg=bg,
            fg=fg,
            font=font,
            padx=padx,
            pady=pady,
            cursor=cursor if state != "disabled" else "arrow",
            relief=tk.FLAT,
            **kwargs
        )

        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<ButtonPress-1>", self._on_press)
        self.bind("<ButtonRelease-1>", self._on_release)

    def _on_enter(self, event=None):
        if self._state == "disabled":
            return
        self._is_hovered = True
        if not self._is_pressed:
            super().configure(bg=self._bg_hover, fg=self._fg_hover)

    def _on_leave(self, event=None):
        self._is_hovered = False
        self._is_pressed = False
        super().configure(bg=self._bg_normal, fg=self._fg_normal)

    def _on_press(self, event=None):
        if self._state == "disabled":
            return
        self._is_pressed = True
        super().configure(bg=self._bg_hover)

    def _on_release(self, event=None):
        if self._state == "disabled":
            return
        was_pressed = self._is_pressed
        self._is_pressed = False
        if self._is_hovered:
            super().configure(bg=self._bg_hover, fg=self._fg_hover)
            if was_pressed and callable(self.command):
                self.command()

    def configure(self, **kwargs):
        if "bg" in kwargs:
            self._bg_normal = kwargs["bg"]
        if "fg" in kwargs:
            self._fg_normal = kwargs["fg"]
        if "activebackground" in kwargs:
            self._bg_hover = kwargs["activebackground"]
        if "activeforeground" in kwargs:
            self._fg_hover = kwargs["activeforeground"]
        if "state" in kwargs:
            self._state = kwargs["state"]
            kwargs["cursor"] = "arrow" if self._state == "disabled" else "hand2"
        super().configure(**kwargs)


class AutomationStructureDialog:
    """Janela modal para visualização da estrutura ordenada do fluxo."""
    def __init__(
        self,
        parent: tk.Tk,
        steps: List[AutomationStep],
        platform: str,
        device_id: Optional[str],
        theme_dict: dict,
        on_run_callback: Optional[Callable[[], None]] = None,
    ):
        self.parent = parent
        self.steps = steps
        self.platform = platform
        self.device_id = device_id or "Nenhum"
        self.theme = theme_dict
        self.on_run_callback = on_run_callback

        self.window = tk.Toplevel(parent)
        self.window.title("Estrutura da Automação (Passos Gravados)")
        self.window.geometry("780x520")
        self.window.minsize(650, 400)
        self.window.configure(bg=self.theme["bg_color"])
        self.window.transient(parent)
        self.window.grab_set()

        self._build_ui()
        self._center_window()

    def _center_window(self):
        self.window.update_idletasks()
        w = self.window.winfo_width()
        h = self.window.winfo_height()
        px = self.parent.winfo_x() + (self.parent.winfo_width() // 2) - (w // 2)
        py = self.parent.winfo_y() + (self.parent.winfo_height() // 2) - (h // 2)
        self.window.geometry(f"+{max(0, px)}+{max(0, py)}")

    def _build_ui(self):
        t = self.theme
        plat_icon = "🤖 Android" if self.platform == "android" else "🍎 iOS"

        # Header
        header = tk.Frame(self.window, bg=t["panel_bg"], padx=14, pady=10)
        header.pack(fill=tk.X, side=tk.TOP)

        lbl_title = tk.Label(
            header,
            text="ESTRUTURA DO FLUXO GRAVADO",
            bg=t["panel_bg"],
            fg=t["fg_color"],
            font=("Helvetica", 12, "bold"),
        )
        lbl_title.pack(side=tk.LEFT)

        info_text = f"{plat_icon}  |  Device: {self.device_id}  |  Total: {len(self.steps)} passos"
        lbl_info = tk.Label(
            header,
            text=info_text,
            bg=t["panel_bg"],
            fg=t["secondary_fg"],
            font=("Helvetica", 10),
        )
        lbl_info.pack(side=tk.RIGHT)

        # Content Frame
        content_frame = tk.Frame(self.window, bg=t["bg_color"], padx=12, pady=10)
        content_frame.pack(fill=tk.BOTH, expand=True)

        columns = ("step", "action", "var_name", "strategy", "coords")
        self.tree = ttk.Treeview(content_frame, columns=columns, show="headings", height=12)

        self.tree.heading("step", text="#")
        self.tree.heading("action", text="Ação")
        self.tree.heading("var_name", text="Elemento")
        self.tree.heading("strategy", text="Estratégia")
        self.tree.heading("coords", text="Coordenadas / Seletor")

        self.tree.column("step", width=45, anchor="center")
        self.tree.column("action", width=85, anchor="center")
        self.tree.column("var_name", width=220, anchor="w")
        self.tree.column("strategy", width=95, anchor="center")
        self.tree.column("coords", width=300, anchor="w")

        scrollbar = ttk.Scrollbar(content_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)

        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.tree.bind("<<TreeviewSelect>>", self._on_select_item)

        # Preenche os passos
        for s in self.steps:
            action_label = "Preencher" if s.action_type == "input" else "Clique"
            strat_val = s.strategy.value.upper() if hasattr(s.strategy, "value") else str(s.strategy).upper()
            coords_info = f"({s.coords[0]}, {s.coords[1]})" if s.coords else "N/A"
            self.tree.insert(
                "",
                tk.END,
                values=(s.step_num, action_label, s.var_name, strat_val, coords_info),
            )

        # Detail Box
        detail_frame = tk.Frame(self.window, bg=t["panel_bg"], padx=14, pady=8)
        detail_frame.pack(fill=tk.X, side=tk.TOP, padx=12, pady=(0, 10))

        self.lbl_detail = tk.Label(
            detail_frame,
            text="Selecione um passo acima para inspecionar os detalhes do seletor.",
            bg=t["panel_bg"],
            fg=t["secondary_fg"],
            font=("Menlo", 10),
            anchor="w",
            justify=tk.LEFT,
        )
        self.lbl_detail.pack(fill=tk.X)

        # Bottom Bar
        bottom_bar = tk.Frame(self.window, bg=t["panel_bg"], padx=14, pady=10)
        bottom_bar.pack(fill=tk.X, side=tk.BOTTOM)

        btn_close = FluidPillButton(
            bottom_bar,
            text="Fechar",
            command=self.window.destroy,
            bg=t["btn_bg"],
            fg=t["fg_color"],
            activebackground=t["btn_hover"],
            font=("Helvetica", 10),
            padx=12,
            pady=3,
        )
        btn_close.pack(side=tk.LEFT)

        btn_copy = FluidPillButton(
            bottom_bar,
            text="Copiar Resumo",
            command=self._copy_summary,
            bg=t["btn_bg"],
            fg=t["fg_color"],
            activebackground=t["btn_hover"],
            font=("Helvetica", 10),
            padx=12,
            pady=3,
        )
        btn_copy.pack(side=tk.LEFT, padx=6)

        if self.on_run_callback and self.steps:
            btn_run = FluidPillButton(
                bottom_bar,
                text="▶ Rodar Agora",
                command=self._on_run_click,
                bg="#059669",
                fg="#FFFFFF",
                activebackground="#10B981",
                font=("Helvetica", 10, "bold"),
                padx=14,
                pady=3,
            )
            btn_run.pack(side=tk.RIGHT)

    def _on_select_item(self, event=None):
        selected = self.tree.selection()
        if not selected:
            return
        idx = self.tree.index(selected[0])
        if 0 <= idx < len(self.steps):
            step = self.steps[idx]
            info = (
                f"Passo {step.step_num}: {step.var_name}\n"
                f"Ação: {step.action_type.upper()} | Tag: {step.class_name} | Coordenadas: {step.coords}\n"
                f"Locator: {step.locator_value}"
            )
            self.lbl_detail.config(text=info)

    def _copy_summary(self):
        lines = [f"# Resumo do Fluxo de Automação ({self.platform.upper()})", f"# Dispositivo: {self.device_id}", ""]
        for s in self.steps:
            action_desc = "Preenchimento de texto" if s.action_type == "input" else "Clique"
            lines.append(f"Passo {s.step_num}: {action_desc} -> {s.var_name} em {s.coords}")
            lines.append(f"   Locator: {s.locator_value}")
        text = "\n".join(lines)
        self.parent.clipboard_clear()
        self.parent.clipboard_append(text)
        messagebox.showinfo("Copiado", "Resumo da estrutura copiado para a área de transferência.")

    def _on_run_click(self):
        self.window.destroy()
        if self.on_run_callback:
            self.on_run_callback()


class AutomationExecutionDialog:
    """Janela modal para execução e visualização em tempo real do .flow_runner.py (Design 1d)."""
    def __init__(
        self,
        parent: tk.Tk,
        steps: List[AutomationStep],
        platform: str,
        device_id: str,
        wda_url: str,
        adb_path: str,
        theme_dict: dict,
        on_complete_callback: Optional[Callable[[bool], None]] = None,
    ):
        self.parent = parent
        self.steps = steps
        self.platform = platform
        self.device_id = device_id
        self.wda_url = wda_url
        self.adb_path = adb_path
        self.theme = theme_dict
        self.on_complete_callback = on_complete_callback
        self.is_running = True
        self.current_step_idx = 0
        self.step_labels = []
        self.start_time = time.time()
        self.runner_process = None

        self.window = tk.Toplevel(parent)
        self.window.title("Executar fluxo · " + (steps[0].package if steps and steps[0].package else "onboarding_credito"))
        self.window.geometry("860x540")
        self.window.minsize(780, 480)
        self.window.configure(bg=self.theme.get("bg_window", self.theme.get("bg_color", "#1E1E2E")))
        self.window.transient(parent)
        self.window.grab_set()

        self._build_ui()
        self._center_window()
        self.window.after(300, self._start_execution)

    def _center_window(self):
        self.window.update_idletasks()
        w = self.window.winfo_width()
        h = self.window.winfo_height()
        px = self.parent.winfo_x() + (self.parent.winfo_width() // 2) - (w // 2)
        py = self.parent.winfo_y() + (self.parent.winfo_height() // 2) - (h // 2)
        self.window.geometry(f"+{max(0, px)}+{max(0, py)}")

    def _build_ui(self):
        t = self.theme
        bg_card = t.get("bg_window", t.get("bg_color", "#1E1E2E"))
        bg_bar = t.get("bg_panel", t.get("panel_bg", "#181825"))
        border_col = t.get("border", t.get("border_color", "#313244"))
        fg_pri = t.get("text_primary", t.get("fg_color", "#CDD6F4"))
        fg_sec = t.get("text_secondary", t.get("secondary_fg", "#A6ADC8"))
        fg_ter = t.get("text_tertiary", "#7F849C")
        accent = t.get("accent", t.get("accent_color", "#89B4FA"))
        success_col = t.get("success", "#A6E3A1")
        danger_col = t.get("danger", t.get("danger_color", "#F38BA8"))

        # 1. Header 44px
        header = tk.Frame(self.window, bg=bg_bar, height=44, padx=16, pady=10)
        header.pack(fill=tk.X, side=tk.TOP)

        title_text = "Executar fluxo · " + (self.steps[0].package if self.steps and self.steps[0].package else "onboarding_credito")
        self.lbl_header_title = tk.Label(
            header,
            text=title_text,
            bg=bg_bar,
            fg=fg_pri,
            font=("Helvetica", 11, "bold"),
        )
        self.lbl_header_title.pack(side=tk.LEFT)

        self.badge_status = tk.Label(
            header,
            text="INICIANDO",
            bg="#313244",
            fg=accent,
            font=("Menlo", 9, "bold"),
            padx=8,
            pady=2,
        )
        self.badge_status.pack(side=tk.LEFT, padx=10)

        precond_text = f"{self.device_id[:16] if self.device_id else 'Dispositivo'} · "
        if self.platform == "ios":
            precond_text += "WDA 8100 ✓"
        else:
            precond_text += "ADB server ✓"
        precond_text += " · Proxy 8082 ✓"

        self.lbl_precond = tk.Label(
            header,
            text=precond_text,
            bg=bg_bar,
            fg=fg_ter,
            font=("Helvetica", 10),
        )
        self.lbl_precond.pack(side=tk.RIGHT)

        # 2. Progress bar (5px)
        prog_frame = tk.Frame(self.window, bg=bg_card, padx=16, pady=6)
        prog_frame.pack(fill=tk.X, side=tk.TOP)

        self.prog_canvas = tk.Canvas(prog_frame, height=5, bg="#313244", highlightthickness=0)
        self.prog_canvas.pack(side=tk.LEFT, fill=tk.X, expand=True)

        self.lbl_step_prog = tk.Label(
            prog_frame,
            text=f"passo 0 / {len(self.steps)}",
            bg=bg_card,
            fg=fg_sec,
            font=("Menlo", 10),
            padx=10,
        )
        self.lbl_step_prog.pack(side=tk.RIGHT)

        # 3. Main Split: Steps List (left 334px) + Terminal (right 1fr)
        body = tk.Frame(self.window, bg=bg_card, padx=16, pady=4)
        body.pack(fill=tk.BOTH, expand=True, side=tk.TOP)

        # Left Column: Steps list
        left_col = tk.Frame(body, bg=bg_card, width=334)
        left_col.pack(side=tk.LEFT, fill=tk.BOTH, padx=(0, 12))
        left_col.pack_propagate(False)

        lbl_steps_header = tk.Label(
            left_col,
            text="PASSOS GRAVADOS",
            bg=bg_card,
            fg=fg_ter,
            font=("Helvetica", 9, "bold"),
            anchor="w",
        )
        lbl_steps_header.pack(fill=tk.X, pady=(0, 6))

        self.steps_container = tk.Frame(left_col, bg=bg_card)
        self.steps_container.pack(fill=tk.BOTH, expand=True)

        for i, step in enumerate(self.steps):
            row = tk.Frame(self.steps_container, bg=bg_bar, padx=8, pady=6, highlightthickness=1, highlightbackground=border_col)
            row.pack(fill=tk.X, pady=2)

            icon_lbl = tk.Label(row, text="·", bg=bg_bar, fg=fg_ter, font=("Menlo", 10, "bold"), width=2)
            icon_lbl.pack(side=tk.LEFT)

            num_lbl = tk.Label(row, text=f"{i+1:02d}", bg=bg_bar, fg=fg_ter, font=("Menlo", 9))
            num_lbl.pack(side=tk.LEFT, padx=(2, 6))

            name_lbl = tk.Label(row, text=step.element_name or step.var_name, bg=bg_bar, fg=fg_pri, font=("Helvetica", 10))
            name_lbl.pack(side=tk.LEFT)

            if step.input_text:
                val_lbl = tk.Label(row, text=f'"{step.input_text[:12]}"', bg=bg_bar, fg=fg_ter, font=("Menlo", 9))
                val_lbl.pack(side=tk.RIGHT)

            self.step_labels.append({"row": row, "icon": icon_lbl, "num": num_lbl, "name": name_lbl})

        # Right Column: Terminal
        right_col = tk.Frame(body, bg="#0B0B12", highlightthickness=1, highlightbackground=border_col)
        right_col.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        term_header = tk.Frame(right_col, bg="#11111B", height=28, padx=12, pady=4)
        term_header.pack(fill=tk.X, side=tk.TOP)

        tk.Label(term_header, text=".flow_runner.py", bg="#11111B", fg=fg_ter, font=("Menlo", 9, "bold")).pack(side=tk.LEFT)
        tk.Label(term_header, text="stdout · streaming", bg="#11111B", fg=fg_ter, font=("Menlo", 9)).pack(side=tk.RIGHT)

        self.log_text = scrolledtext.ScrolledText(
            right_col,
            wrap=tk.WORD,
            bg="#0B0B12",
            fg=fg_sec,
            insertbackground="white",
            font=("Menlo", 10),
            padx=10,
            pady=8,
            relief=tk.FLAT,
        )
        self.log_text.pack(fill=tk.BOTH, expand=True)

        # Tags de cores nos logs estilo Handoff
        self.log_text.tag_config("info", foreground=accent)
        self.log_text.tag_config("pass", foreground=success_col)
        self.log_text.tag_config("run", foreground=accent)
        self.log_text.tag_config("http", foreground="#F9E2AF")
        self.log_text.tag_config("fa", foreground="#F9E2AF")
        self.log_text.tag_config("error", foreground=danger_col)
        self.log_text.tag_config("ts", foreground="#585B70")
        self.log_text.tag_config("dim", foreground="#6C7086")

        # 4. Bottom Footer (52px)
        footer = tk.Frame(self.window, bg=bg_bar, height=52, padx=16, pady=10, highlightthickness=1, highlightbackground=border_col)
        footer.pack(fill=tk.X, side=tk.BOTTOM)

        self.lbl_summary = tk.Label(
            footer,
            text=f"0 aprovados · 0 falhas · {len(self.steps)} passos",
            bg=bg_bar,
            fg=fg_ter,
            font=("Helvetica", 10),
        )
        self.lbl_summary.pack(side=tk.LEFT)

        self.btn_close = FluidPillButton(
            footer,
            text="Concluir",
            command=self.window.destroy,
            bg="#26263a",
            fg="#585B70",
            activebackground=t.get("btn_hover", "#343438"),
            font=("Helvetica", 10, "bold"),
            state="disabled",
            padx=14,
            pady=4,
        )
        self.btn_close.pack(side=tk.RIGHT, padx=(6, 0))

        self.btn_stop = FluidPillButton(
            footer,
            text="Interromper",
            command=self._interrupt_execution,
            bg=t.get("btn_bg", "#28282C"),
            fg=danger_col,
            activebackground=t.get("btn_hover", "#343438"),
            font=("Helvetica", 10),
            padx=12,
            pady=4,
        )
        self.btn_stop.pack(side=tk.RIGHT, padx=4)

    def _interrupt_execution(self):
        self.is_running = False
        self._append_log("FALHA: Execução interrompida pelo usuário.")
        self._on_finish(False, "Interrompido")

    def _update_progress_bar(self, cur: int, total: int):
        if total <= 0:
            return
        self.lbl_step_prog.config(text=f"passo {cur} / {total}")
        self.prog_canvas.delete("bar")
        w = self.prog_canvas.winfo_width() or 400
        ratio = min(1.0, max(0.0, cur / total))
        self.prog_canvas.create_rectangle(0, 0, int(w * ratio), 5, fill="#A6E3A1", width=0, tags="bar")

    def _set_step_state(self, step_idx: int, state: str):
        if 0 <= step_idx < len(self.step_labels):
            item = self.step_labels[step_idx]
            if state == "running":
                item["row"].configure(bg="#232a3b", highlightbackground="#89B4FA")
                item["icon"].configure(text="◐", fg="#89B4FA", bg="#232a3b")
                item["num"].configure(bg="#232a3b")
                item["name"].configure(bg="#232a3b")
            elif state == "done":
                item["row"].configure(bg=self.theme.get("panel_bg", "#181825"), highlightbackground="#313244")
                item["icon"].configure(text="✓", fg="#A6E3A1", bg=self.theme.get("panel_bg", "#181825"))
                item["num"].configure(bg=self.theme.get("panel_bg", "#181825"))
                item["name"].configure(bg=self.theme.get("panel_bg", "#181825"))
            elif state == "fail":
                item["row"].configure(bg="#3b232a", highlightbackground="#F38BA8")
                item["icon"].configure(text="✕", fg="#F38BA8", bg="#3b232a")

    def _append_log(self, text: str):
        import time as _tm
        ts = _tm.strftime("%H:%M:%S")
        self.log_text.insert(tk.END, f"{ts} ", "ts")

        # Classificação de linha
        u_text = text.upper()
        if "PASS" in u_text or "SUCESSO" in u_text or "APROVAD" in u_text or "✔" in text:
            self.log_text.insert(tk.END, "PASS  ", "pass")
            self.log_text.insert(tk.END, text.replace("PASS", "").strip() + "\n")
        elif "FAIL" in u_text or "ERRO" in u_text or "FALHA" in u_text or "❌" in text:
            self.log_text.insert(tk.END, "FAIL  ", "error")
            self.log_text.insert(tk.END, text + "\n")
        elif "HTTP" in u_text or "POST" in u_text or "GET" in u_text or "200" in u_text or "201" in u_text:
            self.log_text.insert(tk.END, "HTTP  ", "http")
            self.log_text.insert(tk.END, text + "\n")
        elif "FA" in u_text or "ANALYTICS" in u_text or "FIREBASE" in u_text:
            self.log_text.insert(tk.END, "FA    ", "fa")
            self.log_text.insert(tk.END, text + "\n")
        elif "RUN" in u_text or "EXECUTANDO" in u_text or "PASSO" in u_text:
            self.log_text.insert(tk.END, "RUN   ", "run")
            self.log_text.insert(tk.END, text + "\n")
        elif "INFO" in u_text or "INICIANDO" in u_text:
            self.log_text.insert(tk.END, "INFO  ", "info")
            self.log_text.insert(tk.END, text + "\n")
        else:
            self.log_text.insert(tk.END, "·     ", "dim")
            self.log_text.insert(tk.END, text + "\n")

        self.log_text.see(tk.END)

        # Detecta passo em execução pela mensagem
        for i, s in enumerate(self.steps):
            if s.element_name in text or s.var_name in text:
                if i > 0:
                    self._set_step_state(i - 1, "done")
                self._set_step_state(i, "running")
                self._update_progress_bar(i + 1, len(self.steps))
                break

    def _start_execution(self):
        # 1. Validação de pré-condições prévia pela interface
        self.badge_status.config(text="EM EXECUÇÃO", bg="rgba(166,227,161,.14)", fg="#A6E3A1")
        self._append_log("INFO: Verificando pré-condições no ambiente...")

        ok, msg = verify_preconditions(
            platform=self.platform,
            device_id=self.device_id,
            wda_url=self.wda_url,
            adb_path=self.adb_path,
        )

        if not ok:
            self._append_log(f"FAIL: {msg}")
            self.badge_status.config(text="FALHA", bg="#450A0A", fg="#F38BA8")
            self.btn_close.configure(text="Fechar", state="normal", bg="#89B4FA", fg="#11111B")
            self.btn_stop.configure(state="disabled")
            self.is_running = False
            if self.on_complete_callback:
                self.on_complete_callback(False)
            return

        self._append_log(f"PASS: Pré-condições OK ({msg})")
        self._append_log("INFO: Gerando script Python (.flow_runner.py)...")

        # 2. Gera o arquivo oculto
        try:
            script_path = generate_hidden_runner_script(
                steps=self.steps,
                platform=self.platform,
                device_id=self.device_id,
                wda_url=self.wda_url,
                adb_path=self.adb_path,
            )
            self._append_log(f"PASS: Script compilado com sucesso ({os.path.basename(script_path)})")
        except Exception as e:
            self._append_log(f"FAIL: Erro ao criar .flow_runner.py: {e}")
            self.badge_status.config(text="ERRO", bg="#450A0A", fg="#F38BA8")
            self.btn_close.configure(text="Fechar", state="normal", bg="#89B4FA", fg="#11111B")
            self.btn_stop.configure(state="disabled")
            self.is_running = False
            if self.on_complete_callback:
                self.on_complete_callback(False)
            return

        # 3. Dispara a execução em background
        self._append_log("INFO: Iniciando execução do fluxo...")
        self._update_progress_bar(1, len(self.steps))
        if self.steps:
            self._set_step_state(0, "running")

        def on_output_line(line: str):
            self.window.after(0, lambda l=line: self._append_log(l))

        def on_finished(success: bool, final_msg: str):
            self.window.after(0, lambda: self._on_finish(success, final_msg))

        run_flow_in_background(script_path, on_output_line, on_finished)

    def _on_finish(self, success: bool, final_msg: str):
        self.is_running = False
        duration = round(time.time() - self.start_time, 1)

        # Marca todos os passos
        total = len(self.steps)
        if success:
            for i in range(total):
                self._set_step_state(i, "done")
            self._update_progress_bar(total, total)
            self.badge_status.config(text="CONCLUÍDO", bg="#064E3B", fg="#A6E3A1")
            self.lbl_summary.config(text=f"{total} aprovados · 0 falhas · tempo {duration} s")
            self._append_log(f"PASS: Fluxo concluído com sucesso em {duration} s.")
        else:
            self.badge_status.config(text="FALHA", bg="#450A0A", fg="#F38BA8")
            self.lbl_summary.config(text=f"Falha na execução · tempo {duration} s")
            self._append_log(f"FAIL: Execução finalizada com erro: {final_msg}")

        self.btn_close.configure(text="Concluir", state="normal", bg="#A6E3A1", fg="#11111B")
        self.btn_stop.configure(state="disabled")
        if self.on_complete_callback:
            self.on_complete_callback(success)

import tkinter as tk
import unittest

from mobaile_tk.main_window import THEME_FREEFORM_DARK, THEME_NOTES_LIGHT, MobileRecorderApp


class TestUITheme(unittest.TestCase):
    def setUp(self):
        try:
            self.root = tk.Tk()
            self.root.withdraw()
            self.app = MobileRecorderApp(self.root)
        except tk.TclError:
            self.root = None
            self.app = None

    def tearDown(self):
        if self.app:
            try:
                self.app.stream_engine.stop()
                self.app.watcher.stop()
                self.app._stop_passive_listeners()
            except Exception:
                pass
        if self.root:
            try:
                self.root.destroy()
            except Exception:
                pass

    def test_theme_dictionaries_structure(self):
        for theme in (THEME_FREEFORM_DARK, THEME_NOTES_LIGHT):
            self.assertIn("name", theme)
            self.assertIn("bg_color", theme)
            self.assertIn("panel_bg", theme)
            self.assertIn("accent_color", theme)
            self.assertIn("highlight_color", theme)
            self.assertIn("code_action_fg", theme)
            self.assertIn("code_object_fg", theme)

        # Ensure Praia Dark (Apple HIG / Catppuccin Macchiato) colors
        self.assertEqual(THEME_FREEFORM_DARK["name"], "dark")
        self.assertEqual(THEME_FREEFORM_DARK["accent_color"], "#89B4FA")
        self.assertEqual(THEME_FREEFORM_DARK["highlight_color"], "#89B4FA")

        # Ensure Praia Light colors
        self.assertEqual(THEME_NOTES_LIGHT["name"], "light")
        self.assertEqual(THEME_NOTES_LIGHT["accent_color"], "#E88BA5")
        self.assertEqual(THEME_NOTES_LIGHT["highlight_color"], "#E88BA5")

    def test_theme_switch_and_apply(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        # Default is Praia Dark
        self.assertEqual(self.app.current_theme["name"], "dark")
        self.assertEqual(self.app.highlight_color, "#89B4FA")

        # Switch to Praia Light
        self.app.theme_var.set("light")
        self.app._on_theme_switch()
        self.assertEqual(self.app.current_theme["name"], "light")
        self.assertEqual(self.app.highlight_color, "#E88BA5")
        self.assertEqual(self.app.bg_color, "#F2FAFD")

        # Switch back to Praia Dark
        self.app.theme_var.set("dark")
        self.app._on_theme_switch()
        self.assertEqual(self.app.current_theme["name"], "dark")
        self.assertEqual(self.app.highlight_color, "#89B4FA")
        self.assertEqual(self.app.bg_color, "#1E1E2E")

    def test_btn_scrcpy_exists_and_styled(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        self.assertTrue(hasattr(self.app, "btn_scrcpy"))
        self.assertEqual(self.app.btn_scrcpy.cget("text"), "Espelho 60 FPS")

        # Test switching theme applies standardized high-contrast foreground to scrcpy button
        self.app.theme_var.set("light")
        self.app._on_theme_switch()
        self.assertEqual(self.app.btn_scrcpy.cget("fg"), "#111111")

        self.app.theme_var.set("dark")
        self.app._on_theme_switch()
        self.assertEqual(self.app.btn_scrcpy.cget("fg"), "#FFFFFF")

    def test_standardized_high_contrast_options(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        # Switch to Light Mode and verify all options have crisp, readable dark text
        self.app.theme_var.set("light")
        self.app._on_theme_switch()
        options = [
            self.app.rb_ios,
            self.app.rb_android,
            self.app.rb_theme_dark,
            self.app.rb_theme_light,
            self.app.rb_strat_id,
            self.app.rb_strat_xpath,
            self.app.rb_strat_pos,
            self.app.cb_passive,
            self.app.cb_forward,
        ]
        for opt in options:
            self.assertEqual(
                opt.cget("fg"), "#111111",
                f"Option '{opt.cget('text')}' should have high-contrast text '#111111' in light mode, got '{opt.cget('fg')}'"
            )

        # Switch to Dark Mode and verify all options have crisp, readable white text
        self.app.theme_var.set("dark")
        self.app._on_theme_switch()
        for opt in options:
            self.assertEqual(
                opt.cget("fg"), "#FFFFFF",
                f"Option '{opt.cget('text')}' should have high-contrast text '#FFFFFF' in dark mode, got '{opt.cget('fg')}'"
            )

    def test_no_emojis_in_main_ui_elements(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        buttons_and_labels = [
            self.app.rb_ios.cget("text"),
            self.app.rb_android.cget("text"),
            self.app.btn_toggle_stream.cget("text"),
            self.app.auto_status_badge.cget("text"),
            self.app.btn_scrcpy.cget("text"),
            self.app.btn_view_http.cget("text"),
            self.app.btn_cap.cget("text"),
            self.app.cb_passive.cget("text"),
            self.app.btn_copy_act.cget("text"),
            self.app.btn_save_act.cget("text"),
            self.app.btn_copy_obj.cget("text"),
            self.app.btn_save_obj.cget("text"),
            self.app.btn_clear.cget("text"),
        ]

        import re
        emoji_pattern = re.compile(r"[\U00010000-\U0010ffff]|[\u2600-\u27bf]|[\u2300-\u23ff]")
        for text in buttons_and_labels:
            self.assertIsNone(
                emoji_pattern.search(text),
                f"Element text '{text}' contains an emoji, violating Apple Pro minimalism.",
            )

    def test_integrated_single_screen_http_view(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        # Verifica presença dos componentes em tela única
        self.assertTrue(hasattr(self.app, "network_view"))
        self.assertTrue(hasattr(self.app, "btn_seg_auto"))
        self.assertTrue(hasattr(self.app, "btn_seg_net"))

        # Default é Automação
        self.assertEqual(self.app.right_view_var.get(), "automation")
        self.assertEqual(self.app.automation_view.winfo_manager(), "pack")
        self.assertEqual(self.app.network_view.winfo_manager(), "")

        # Alterna para Rede (HTTP)
        self.app._set_right_view("network")
        self.assertEqual(self.app.right_view_var.get(), "network")
        self.assertEqual(self.app.network_view.winfo_manager(), "pack")
        self.assertEqual(self.app.automation_view.winfo_manager(), "")

        # Alterna de volta para Automação
        self.app._set_right_view("automation")
        self.assertEqual(self.app.right_view_var.get(), "automation")
        self.assertEqual(self.app.automation_view.winfo_manager(), "pack")
        self.assertEqual(self.app.network_view.winfo_manager(), "")

    def test_http_inspector_tabs_strictly_two(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        tabs = self.app.network_view.notebook.tabs()
        self.assertEqual(len(tabs), 2)
        tab_names = [self.app.network_view.notebook.tab(tab_id, "text") for tab_id in tabs]
        self.assertEqual(tab_names, ["Requisição (Request)", "Resposta (Response)"])
        self.assertNotIn("Snippet de Teste (Python)", tab_names)

    def test_code_subtabs_and_split_mode(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        # Verifica existência dos novos controles de abas fluidas
        self.assertTrue(hasattr(self.app, "code_subtabs_frame"))
        self.assertTrue(hasattr(self.app, "btn_subtab_actions"))
        self.assertTrue(hasattr(self.app, "btn_subtab_objects"))
        self.assertTrue(hasattr(self.app, "btn_toggle_split"))

        # Default é Split View ativo
        self.assertTrue(self.app.is_split_active)
        self.assertEqual(len(self.app.right_split.panes()), 2)

        # Alterna para modo de aba única (Split Desativado)
        self.app._toggle_code_split()
        self.assertFalse(self.app.is_split_active)
        self.assertEqual(len(self.app.right_split.panes()), 1)

        # Foca na aba de Objetos
        self.app._set_code_subtab("objects")
        self.assertEqual(self.app.active_code_tab, "objects")
        self.assertEqual(len(self.app.right_split.panes()), 1)
        self.assertIn(str(self.app.objects_frame), [str(p) for p in self.app.right_split.panes()])

        # Foca na aba de Ações
        self.app._set_code_subtab("actions")
        self.assertEqual(self.app.active_code_tab, "actions")
        self.assertEqual(len(self.app.right_split.panes()), 1)
        self.assertIn(str(self.app.actions_frame), [str(p) for p in self.app.right_split.panes()])

        # Restaura Split View
        self.app._toggle_code_split()
        self.assertTrue(self.app.is_split_active)
        self.assertEqual(len(self.app.right_split.panes()), 2)

    def test_zen_mode_toggle(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        self.assertTrue(hasattr(self.app, "btn_zen"))
        self.assertFalse(self.app.is_zen_mode)
        self.assertEqual(self.app.config_bar.winfo_manager(), "pack")

        # Ativa Modo Zen
        self.app._toggle_zen_mode()
        self.assertTrue(self.app.is_zen_mode)
        self.assertEqual(self.app.config_bar.winfo_manager(), "")

        # Desativa Modo Zen
        self.app._toggle_zen_mode()
        self.assertFalse(self.app.is_zen_mode)
        self.assertEqual(self.app.config_bar.winfo_manager(), "pack")

    def test_toggle_mirror(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        self.assertTrue(hasattr(self.app, "btn_toggle_mirror"))
        self.assertTrue(self.app.is_mirror_visible)
        self.assertEqual(len(self.app.main_split.panes()), 2)
        self.assertIn(str(self.app.left_frame), [str(p) for p in self.app.main_split.panes()])

        # Oculta o espelho do dispositivo
        self.app._toggle_mirror()
        self.assertFalse(self.app.is_mirror_visible)
        self.assertEqual(len(self.app.main_split.panes()), 1)
        self.assertNotIn(str(self.app.left_frame), [str(p) for p in self.app.main_split.panes()])

        # Exibe o espelho do dispositivo novamente
        self.app._toggle_mirror()
        self.assertTrue(self.app.is_mirror_visible)
        self.assertEqual(len(self.app.main_split.panes()), 2)
        self.assertIn(str(self.app.left_frame), [str(p) for p in self.app.main_split.panes()])

    def test_apple_pro_button_functionality(self):
        if not self.app:
            self.skipTest("Tkinter display not available in current environment")

        from mobaile_tk.main_window import AppleProButton
        clicked = []
        btn = AppleProButton(
            self.root,
            text="Test Action",
            command=lambda: clicked.append(True),
            bg="#28282C",
            fg="#FFFFFF",
        )
        self.assertEqual(btn.cget("text"), "Test Action")
        self.assertEqual(btn.cget("bg"), "#28282C")
        self.assertEqual(btn.cget("fg"), "#FFFFFF")

        # Testa invoke()
        btn.invoke()
        self.assertEqual(clicked, [True])

        # Testa desativação (disabled)
        btn.configure(state="disabled")
        self.assertEqual(btn.cget("state"), "disabled")
        btn.invoke()
        self.assertEqual(clicked, [True])  # Não deve acionar quando disabled

        btn.destroy()


if __name__ == "__main__":
    unittest.main()

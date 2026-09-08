#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import threading
from collections.abc import Callable

from mobaile.config import settings
from mobaile.domain.errors import InvalidInputError
from mobaile.security import validate_device_id, write_executable_script
from mobaile.services.codegen import AutomationStep


def verify_preconditions(
    platform: str,
    device_id: str | None = None,
    wda_url: str | None = None,
    adb_path: str | None = None,
) -> tuple[bool, str]:
    """
    Valida as pré-condições para execução da automação em Android ou iOS.
    Retorna (True, 'OK') ou (False, 'Mensagem de Erro').
    """
    plat = platform.lower()
    active_adb = adb_path or settings.adb_path or "adb"
    active_wda = wda_url or settings.wda_url

    if plat == "android":
        if not device_id:
            return False, "Nenhum dispositivo Android selecionado ou conectado."

        try:
            cmd = [active_adb, "devices"]
            res = subprocess.run(cmd, capture_output=True, timeout=5)
            if res.returncode != 0:
                return False, f"Falha ao executar ADB: {res.stderr.decode('utf-8', errors='ignore')}"

            lines = res.stdout.decode("utf-8", errors="ignore").strip().splitlines()
            found_state = None
            for line in lines[1:]:
                parts = line.strip().split()
                if len(parts) >= 2 and parts[0] == device_id:
                    found_state = parts[1]
                    break

            if not found_state:
                return False, f"Dispositivo '{device_id}' não encontrado na lista do ADB."
            if found_state != "device":
                return False, f"Dispositivo '{device_id}' não está pronto (estado atual: '{found_state}')."

            # Tenta despertar a tela e desbloquear o aparelho
            subprocess.run(
                [active_adb, "-s", device_id, "shell", "input", "keyevent", "224"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=4,
            )
            subprocess.run(
                [active_adb, "-s", device_id, "shell", "wm", "dismiss-keyguard"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=4,
            )
            return True, f"Android '{device_id}' pronto (Conectado, Tela desperta e Desbloqueada)."
        except Exception as e:
            return False, f"Erro ao validar pré-condições do Android: {e}"

    elif plat == "ios":
        # Checa status do simulador iOS via xcrun simctl
        try:
            cmd = ["xcrun", "simctl", "list", "devices"]
            res = subprocess.run(cmd, capture_output=True, timeout=5)
            if res.returncode == 0:
                output = res.stdout.decode("utf-8", errors="ignore")
                if "Booted" not in output:
                    return False, "Nenhum simulador iOS ativo (Booted) encontrado."
        except Exception as e:
            return False, f"Falha ao checar simuladores iOS: {e}"

        # Checa status do WebDriverAgent (WDA)
        try:
            import requests
            resp = requests.get(f"{active_wda}/status", timeout=3)
            if resp.status_code != 200:
                return False, f"WebDriverAgent não respondeu com sucesso em {active_wda}/status (HTTP {resp.status_code})."
            data = resp.json()
            if not data.get("sessionId") and not (data.get("value") or {}).get("sessionId"):
                # Tenta abrir sessão
                s_resp = requests.post(f"{active_wda}/session", json={"capabilities": {}}, timeout=4)
                if s_resp.status_code != 200:
                    return False, f"Não foi possível iniciar sessão no WebDriverAgent ({active_wda})."
            return True, f"iOS e WebDriverAgent prontos ({active_wda})."
        except Exception as e:
            return False, f"WebDriverAgent indisponível em {active_wda}. Certifique-se de que o WDA está rodando. Erro: {e}"

    return False, f"Plataforma desconhecida: {platform}"


def generate_hidden_runner_script(
    steps: list[AutomationStep],
    platform: str,
    device_id: str,
    wda_url: str = "http://localhost:8100",
    adb_path: str = "adb",
    output_path: str | None = None,
) -> str:
    """
    Gera o script Python executável e autônomo em arquivo oculto (.flow_runner.py).
    Retorna o caminho absoluto do arquivo criado.
    """
    # O serial vem de `adb devices` / `adb connect`, ou seja, de fora. Ele era
    # interpolado direto dentro de uma string literal do script gerado, o que
    # permitia fechar a aspa e emendar código Python arbitrário. Valida antes,
    # e mesmo assim só entra no script via repr().
    device_id = validate_device_id(device_id)
    if platform.lower() not in ("android", "ios"):
        raise InvalidInputError(f"Plataforma não suportada: {platform!r}")

    steps_data = []
    for s in steps:
        steps_data.append({
            "step_num": s.step_num,
            "action_type": s.action_type,
            "var_name": s.var_name,
            "element_name": s.element_name,
            "class_name": s.class_name,
            "strategy": s.strategy.value if hasattr(s.strategy, "value") else str(s.strategy),
            "locator_value": s.locator_value,
            "coords": list(s.coords) if s.coords else [0, 0],
            "input_text": s.input_text or "Texto de Exemplo",
            "package": s.package,
            "platform": s.platform,
        })

    steps_json = json.dumps(steps_data, indent=4, ensure_ascii=False)

    script_content = f"""#!/usr/bin/env python3
# -*- coding: utf-8 -*-
\"\"\"
ARQUIVO DE EXECUÇÃO DE AUTOMAÇÃO (OCULTO)
Gerado automaticamente pelo Mobile Element Recorder.
Plataforma: {platform.upper()}
Dispositivo/Target: {device_id}
Total de Passos: {len(steps)}
\"\"\"

import json
import os
import subprocess
import sys
import time

PLATFORM = {platform.lower()!r}
DEVICE_ID = {device_id!r}
ADB_PATH = {adb_path!r}
WDA_URL = {wda_url!r}
# Os passos entram como JSON e são desserializados em tempo de execução: assim
# nenhum conteúdo gravado pelo usuário é interpretado como código Python.
STEPS = json.loads({steps_json!r})

# Aspas simples: o unico quoting em que o sh do aparelho nao interpreta nada dentro.
def _quote_for_device_shell(raw):
    return "'" + raw.replace("'", "'\\''") + "'"

def log(msg):
    timestamp = time.strftime("%H:%M:%S")
    print(f"[{{timestamp}}] {{msg}}", flush=True)

def verify_preconditions():
    log("=== [PRÉ-CONDIÇÕES] Verificando ambiente antes da execução ===")
    if PLATFORM == "android":
        if not DEVICE_ID:
            log("❌ ERRO: Dispositivo Android não informado.")
            return False
        try:
            res = subprocess.run([ADB_PATH, "-s", DEVICE_ID, "get-state"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            state = res.stdout.decode("utf-8", errors="ignore").strip()
            if state != "device":
                log(f"❌ ERRO: Dispositivo '{{DEVICE_ID}}' em estado inválido: '{{state}}'.")
                return False
            log(f"✔ Dispositivo Android conectado e autorizado: {{DEVICE_ID}}")
            # Despertar tela e desbloquear
            subprocess.run([ADB_PATH, "-s", DEVICE_ID, "shell", "input", "keyevent", "224"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
            subprocess.run([ADB_PATH, "-s", DEVICE_ID, "shell", "wm", "dismiss-keyguard"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
            log("✔ Tela desperta e bloqueio descartado com sucesso.")
            return True
        except Exception as e:
            log(f"❌ ERRO ao checar ADB: {{e}}")
            return False
    elif PLATFORM == "ios":
        try:
            import requests
            log(f"Verificando WebDriverAgent em {{WDA_URL}}...")
            r = requests.get(f"{{WDA_URL}}/status", timeout=4)
            if r.status_code == 200:
                log("✔ WebDriverAgent respondendo normalmente.")
                return True
            log(f"❌ ERRO: WDA retornou código {{r.status_code}}.")
            return False
        except Exception as e:
            log(f"❌ ERRO: Falha ao conectar ao WebDriverAgent em {{WDA_URL}}: {{e}}")
            return False
    return False

def execute_android_step(step):
    coords = step.get("coords") or [0, 0]
    x, y = coords[0], coords[1]
    action = step.get("action_type", "click")
    var_name = step.get("var_name", "ELEMENTO")

    if action == "input":
        text = step.get("input_text", "Texto de Teste")
        log(f"-> Clicando no campo {{var_name}} em ({{x}}, {{y}})...")
        subprocess.run([ADB_PATH, "-s", DEVICE_ID, "shell", "input", "tap", str(x), str(y)], timeout=5)
        time.sleep(0.5)
        encoded = text.replace(" ", "%s")
        log(f"-> Preenchendo texto '{{text}}'...")
        subprocess.run(
            [ADB_PATH, "-s", DEVICE_ID, "shell", "input text " + _quote_for_device_shell(encoded)],
            timeout=5,
        )
    else:
        log(f"-> Clicando em {{var_name}} em ({{x}}, {{y}})...")
        subprocess.run([ADB_PATH, "-s", DEVICE_ID, "shell", "input", "tap", str(x), str(y)], timeout=5)
    return True

def execute_ios_step(step):
    import requests
    coords = step.get("coords") or [0, 0]
    x, y = coords[0], coords[1]
    var_name = step.get("var_name", "ELEMENTO")

    # Obtém sessão WDA
    sid = None
    try:
        r = requests.get(f"{{WDA_URL}}/status", timeout=3)
        if r.status_code == 200:
            sid = r.json().get("sessionId")
    except Exception:
        pass
    if not sid:
        r = requests.post(f"{{WDA_URL}}/session", json={{"capabilities": {{}}}}, timeout=4)
        if r.status_code == 200:
            data = r.json()
            sid = data.get("sessionId") or (data.get("value") or {{}}).get("sessionId")

    if not sid:
        log("❌ Falha ao obter Session ID do WebDriverAgent.")
        return False

    log(f"-> Clicando em {{var_name}} via WDA em ({{x}}, {{y}})...")
    res = requests.post(f"{{WDA_URL}}/session/{{sid}}/wda/tap", json={{"x": x, "y": y}}, timeout=5)
    if res.status_code == 200:
        return True

    # Fallback para /actions
    action_payload = {{
        "actions": [
            {{
                "type": "pointer",
                "id": "finger1",
                "parameters": {{"pointerType": "touch"}},
                "actions": [
                    {{"type": "pointerMove", "duration": 0, "x": x, "y": y}},
                    {{"type": "pointerDown", "button": 0}},
                    {{"type": "pause", "duration": 80}},
                    {{"type": "pointerUp", "button": 0}},
                ],
            }}
        ]
    }}
    res2 = requests.post(f"{{WDA_URL}}/session/{{sid}}/actions", json=action_payload, timeout=5)
    return res2.status_code == 200

def main():
    log("================================================================")
    log(f"🚀 INICIANDO EXECUÇÃO DO FLUXO ({{len(STEPS)}} PASSOS)")
    log(f"Plataforma: {{PLATFORM.upper()}} | Dispositivo: {{DEVICE_ID}}")
    log("================================================================")

    if not STEPS:
        log("⚠ AVISO: Nenhum passo gravado para executar.")
        sys.exit(1)

    # 1. Checagem e execução de pré-condições
    if not verify_preconditions():
        log("❌ ABORTADO: Pré-condições falharam. Corrija o dispositivo e tente novamente.")
        sys.exit(1)

    log("✔ Pré-condições validadas! Iniciando passos sequenciais...")
    time.sleep(0.8)

    # 2. Execução dos passos
    total = len(STEPS)
    for i, step in enumerate(STEPS, start=1):
        var_name = step.get("var_name", f"PASSO_{{i}}")
        coords = step.get("coords", [0, 0])
        action = step.get("action_type", "click")
        log(f"----------------------------------------------------------------")
        log(f"▶ [{{i}}/{{total}}] Executando: {{var_name}} (Ação: {{action}}, Coords: {{coords}})")

        success = False
        try:
            if PLATFORM == "android":
                success = execute_android_step(step)
            elif PLATFORM == "ios":
                success = execute_ios_step(step)
        except Exception as e:
            log(f"❌ Erro inesperado ao executar o passo {{i}}: {{e}}")
            success = False

        if not success:
            log(f"❌ FALHA no passo {{i}} ({{var_name}}). Interrompendo automação.")
            sys.exit(1)

        log(f"✔ [{{i}}/{{total}}] Passo {{var_name}} concluído com sucesso!")
        time.sleep(1.0)  # Delay para observabilidade visual no espelho

    log("================================================================")
    log("🎉 AUTOMAÇÃO EXECUTADA COM SUCESSO TOTAL!")
    log(f"Todos os {{total}} passos foram validados e rodaram corretamente.")
    log("================================================================")
    sys.exit(0)

if __name__ == "__main__":
    main()
"""

    # Antes o script ia para a raiz do projeto com permissão 0755: código
    # executável em caminho previsível, gravável entre a escrita e a execução.
    # Agora vai para um diretório da sessão (0700) com arquivo 0600, e roda via
    # `sys.executable <script>`, que dispensa bit de execução.
    if output_path:
        target = os.path.abspath(output_path)
        with open(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
            f.write(script_content)
        os.chmod(target, 0o600)
        return target

    return str(write_executable_script(script_content))


def run_flow_in_background(
    script_path: str,
    on_output: Callable[[str], None],
    on_finished: Callable[[bool, str], None],
) -> threading.Thread:
    """
    Executa o script oculto em um subprocesso de forma assíncrona,
    repassando cada linha de log para `on_output` e notificando em `on_finished`.
    """
    def worker():
        try:
            proc = subprocess.Popen(
                [sys.executable, script_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                # DEVNULL de proposito: sem isto o filho herda o stdin do
                # motor, que e o canal JSON-RPC, e passa a consumir as
                # linhas do protocolo. O sintoma e a chamada seguinte nunca
                # responder — no app, janela travada sem erro.
                stdin=subprocess.DEVNULL,
                text=True,
                bufsize=1,
                universal_newlines=True,
            )

            for line in iter(proc.stdout.readline, ""):
                stripped = line.rstrip()
                if stripped:
                    on_output(stripped)

            proc.stdout.close()
            return_code = proc.wait()

            if return_code == 0:
                on_finished(True, "Automação executada com sucesso!")
            else:
                on_finished(False, f"Automação falhou (código de saída: {return_code}).")
        except Exception as ex:
            on_output(f"Erro de execução: {ex}")
            on_finished(False, f"Exceção durante execução: {ex}")

    t = threading.Thread(target=worker, daemon=True)
    t.start()
    return t

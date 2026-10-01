import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
import streamlit as st

st.set_page_config(
    page_title="Executor de Automação Mobile",
    page_icon="📲",
    layout="centered"
)

# --- FUNÇÕES AUXILIARES ---

def encontrar_adb() -> str:
    """Retorna o caminho do executável do adb no sistema."""
    candidatos = [
        "adb",
        os.path.expanduser("~/Library/Android/sdk/platform-tools/adb"),
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
    ]
    for cmd in candidatos:
        if cmd == "adb" and shutil.which("adb"):
            return "adb"
        if os.path.exists(cmd) and os.access(cmd, os.X_OK):
            return cmd
    return "adb"


def verificar_dispositivos() -> list[str]:
    """Verifica se há algum aparelho Android conectado e autorizado via ADB."""
    adb_bin = encontrar_adb()
    try:
        resultado = subprocess.run(
            [adb_bin, "devices"],
            capture_output=True,
            text=True,
            timeout=5
        )
        linhas = [l.strip() for l in resultado.stdout.splitlines() if l.strip()]
        # Ignora o cabeçalho ("List of devices attached") e filtra os autorizados
        dispositivos = [
            l.split()[0]
            for l in linhas[1:]
            if "\tdevice" in l
        ]
        return dispositivos
    except Exception:
        return []


# --- INTERFACE ---

st.title("📲 Executor de Automação Mobile")
st.write("Importe o pacote de testes contendo o `main.py` para disparar o fluxo no aparelho conectado.")

st.divider()

# 1. Verificação do Dispositivo
st.subheader("1. Dispositivo Conectado")
dispositivos_online = verificar_dispositivos()

col_status, col_btn = st.columns([4, 1])
with col_status:
    if dispositivos_online:
        st.success(f"Dispositivo pronto: **`{dispositivos_online[0]}`** ({len(dispositivos_online)} conectado(s))")
    else:
        st.warning("⚠️ Nenhum aparelho pronto encontrado. Conecte o cabo USB e ative a depuração.")

with col_btn:
    if st.button("🔄 Atualizar"):
        st.rerun()

st.divider()

# 2. Upload do Arquivo
st.subheader("2. Pacote de Automação")
arquivo = st.file_uploader(
    "Selecione um arquivo .zip (contendo main.py) ou o arquivo main.py diretamente:",
    type=["zip", "py"],
    help="Envie um arquivo .zip compactado ou o arquivo .py principal."
)

# 3. Disparo da Execução
st.divider()
st.subheader("3. Execução")

executar = st.button(
    "🚀 Iniciar Automação",
    disabled=(arquivo is None or not dispositivos_online),
    use_container_width=True,
    type="primary"
)

if executar and arquivo:
    pasta_trabalho = tempfile.mkdtemp(prefix="mobaile_run_")
    
    try:
        caminho_main = None
        
        with st.spinner("Extraindo e preparando arquivos..."):
            if arquivo.name.endswith(".zip"):
                caminho_zip = os.path.join(pasta_trabalho, "pacote.zip")
                with open(caminho_zip, "wb") as f:
                    f.write(arquivo.getvalue())
                
                with zipfile.ZipFile(caminho_zip, "r") as zip_ref:
                    zip_ref.extractall(pasta_trabalho)
                
                # Procura o main.py na pasta extraída (inclusive subdiretórios)
                for raiz, _, arquivos in os.walk(pasta_trabalho):
                    if "main.py" in arquivos:
                        caminho_main = os.path.join(raiz, "main.py")
                        break
            else:
                # Arquivo .py avulso
                caminho_main = os.path.join(pasta_trabalho, "main.py")
                with open(caminho_main, "wb") as f:
                    f.write(arquivo.getvalue())

        if not caminho_main or not os.path.exists(caminho_main):
            st.error("❌ O arquivo `main.py` não foi encontrado dentro do pacote enviado.")
        else:
            diretorio_execucao = os.path.dirname(caminho_main)
            st.info(f"Executando `{os.path.basename(caminho_main)}` no dispositivo...")
            
            # Caixa para streaming dos logs
            st.caption("Logs de execução em tempo real:")
            log_container = st.empty()
            logs = []
            
            inicio = time.time()
            
            # Inicia o processo com o Python do ambiente atual
            processo = subprocess.Popen(
                [sys.executable, "-u", caminho_main],
                cwd=diretorio_execucao,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            # Leitura linha a linha em streaming
            if processo.stdout:
                for linha in iter(processo.stdout.readline, ""):
                    logs.append(linha)
                    # Mantém as últimas 25 linhas visíveis dinamicamente
                    log_container.code("".join(logs[-25:]), language="bash")
                processo.stdout.close()

            retorno = processo.wait()
            duracao = round(time.time() - inicio, 1)

            # Resultado
            if retorno == 0:
                st.success(f"🎉 Automação concluída com sucesso em {duracao}s!")
            else:
                st.error(f"❌ Falha na execução da automação (Código de saída: {retorno}) após {duracao}s.")

            # Logs completos para auditoria/diagnóstico
            with st.expander("📄 Ver log completo da execução"):
                st.code("".join(logs) if logs else "Nenhum log gerado.", language="bash")

    except Exception as erro:
        st.error(f"Erro inesperado durante a execução: {erro}")
    finally:
        # Limpeza da pasta temporária após execução
        shutil.rmtree(pasta_trabalho, ignore_errors=True)

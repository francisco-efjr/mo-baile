#!/usr/bin/env bash
#
# Instala o que o Mo baile precisa num Mac, por partes.
#
#   bash tools/setup/instalar-mac.sh <alvo> [<alvo>...]
#
# Alvos:
#   python          Python só do Mo baile, com Pillow e requests (o motor não sobe sem ele)
#   android         Android Platform Tools (adb)
#   scrcpy          espelho Android a 60 quadros, em janela própria (opcional)
#   appium          Node.js, Appium e o driver XCUITest (toque e hierarquia no iOS)
#   appium-android  driver UiAutomator2 do Appium (reserva da hierarquia no Android)
#   ios-device      pymobiledevice3 (Analytics e Rede de iPhone físico por cabo)
#   escuta          pyobjc-framework-Quartz (escuta passiva de toques no simulador)
#   tudo            python, android, scrcpy e appium
#   verificar       só mostra o que está pronto e o que falta
#
# O app roda este script no Terminal pelo botão "Instalar no Terminal…" da tela
# Início, e você vê cada comando antes de ele rodar. Precisa de internet só
# agora: depois de instalado, tudo roda nesta máquina, offline.
#
# O Xcode não entra aqui: ele vem da App Store (a tela Início abre a página).
#
# Onde fica o Python do Mo baile: ~/Library/Application Support/Mo baile/python.
# O app procura esse caminho depois do MOBAILE_PYTHON e antes dos Pythons do
# sistema (EngineLocator.swift e tools/verify_native_app.sh: se mudar aqui,
# muda lá). Com MOBAILE_PYTHON definido, os pacotes vão para aquele Python.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_VENV="$HOME/Library/Application Support/Mo baile/python"
PACOTES_MOTOR=(Pillow requests)

# O motor fica ao lado: no repositório em engine/src, no app em Resources/engine/src.
MOTOR_SRC=""
for candidato in "$AQUI/../engine/src" "$AQUI/../../engine/src"; do
    if [ -d "$candidato/mobaile" ]; then MOTOR_SRC="$(cd "$candidato" && pwd)"; break; fi
done

negrito() { printf '\n\033[1m%s\033[0m\n' "$*"; }
rodar() { printf '  $ %s\n' "$*"; "$@"; }
falha() { printf '\nNão deu: %s\n' "$*" >&2; exit 1; }

confirmar() {
    local resposta
    read -r -p "$1 [s/N] " resposta || true
    [[ "$resposta" =~ ^[sS] ]]
}

# ------------------------------------------------------------------ Homebrew

garantir_brew() {
    if command -v brew >/dev/null 2>&1; then return 0; fi
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
    done
    negrito "O Homebrew não está instalado"
    echo "  Ele instala adb, scrcpy, Node e Python com um comando cada. O instalador oficial"
    echo "  (https://brew.sh) pede a senha de administrador deste Mac."
    confirmar "Instalar o Homebrew agora?" || falha "sem o Homebrew, instale cada item à mão (docs/INSTALACAO.md)."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
    done
    falha "o Homebrew não ficou disponível. Abra um Terminal novo e rode o script de novo."
}

# -------------------------------------------------------------------- Python

# Python 3.10+ do sistema, para criar o ambiente do Mo baile.
python_base() {
    local p
    for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12; do
        if [ -x "$p" ] && "$p" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
            echo "$p"; return 0
        fi
    done
    return 1
}

criar_venv() {
    if [ -x "$APP_VENV/bin/python3" ]; then return 0; fi
    local base
    if ! base="$(python_base)"; then
        negrito "Instalando o Python 3.12 pelo Homebrew"
        garantir_brew
        rodar brew install python@3.12
        base="$(python_base)" || falha "o Python 3.12 não apareceu em /opt/homebrew/bin."
    fi
    negrito "Criando o Python do Mo baile em $APP_VENV"
    mkdir -p "$(dirname "$APP_VENV")"
    rodar "$base" -m venv "$APP_VENV"
    rodar "$APP_VENV/bin/python3" -m pip install --quiet --upgrade pip
}

# O Python que vai receber os pacotes: o que o app usa (MOBAILE_PYTHON), se ele
# aceitar pip, ou o do Mo baile. Python do Homebrew recusa `pip install` fora
# de um ambiente virtual (PEP 668); aí o pacote vai para o do Mo baile.
python_alvo() {
    local p="${MOBAILE_PYTHON:-}"
    if [ -n "$p" ] && [ -x "$p" ]; then
        if "$p" -c 'import sys, sysconfig, os
gerenciado = os.path.exists(os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED"))
sys.exit(1 if gerenciado and sys.prefix == sys.base_prefix else 0)' 2>/dev/null; then
            echo "$p"; return 0
        fi
        echo "  $p não aceita pip install (Python gerenciado pelo Homebrew); usando o Python do Mo baile." >&2
    fi
    criar_venv >&2
    echo "$APP_VENV/bin/python3"
}

instalar_pacotes() {
    local py
    py="$(python_alvo)"
    # Pacote novo num Python diferente do que o app usa hoje: o motor precisa
    # das dependências dele lá também.
    rodar "$py" -m pip install --quiet "${PACOTES_MOTOR[@]}" "$@"
}

alvo_python() {
    negrito "Python do motor"
    criar_venv
    rodar "$APP_VENV/bin/python3" -m pip install --quiet "${PACOTES_MOTOR[@]}" "pyobjc-framework-Quartz>=10.0"
    echo "  Pronto: $("$APP_VENV/bin/python3" -V)."
}

# ------------------------------------------------------------------- Android

alvo_android() {
    negrito "Android Platform Tools (adb)"
    if command -v adb >/dev/null 2>&1; then echo "  Já instalado: $(command -v adb)"; return 0; fi
    garantir_brew
    rodar brew install --cask android-platform-tools
    echo "  No aparelho: Ajustes > Sobre o telefone > toque 7 vezes em Número da versão,"
    echo "  depois Opções do desenvolvedor > Depuração USB. Aceite o aviso ao plugar o cabo."
}

alvo_scrcpy() {
    negrito "scrcpy"
    if command -v scrcpy >/dev/null 2>&1; then echo "  Já instalado: $(command -v scrcpy)"; return 0; fi
    garantir_brew
    rodar brew install scrcpy
}

# ----------------------------------------------------------------------- iOS

garantir_node() {
    if command -v node >/dev/null 2>&1; then return 0; fi
    garantir_brew
    rodar brew install node
}

garantir_appium() {
    garantir_node
    if ! command -v appium >/dev/null 2>&1; then
        rodar npm install --global appium
    fi
}

instalar_driver() {
    local driver="$1"
    if appium driver list --installed 2>&1 | grep -qi "$driver"; then
        echo "  Driver $driver já instalado."
    else
        rodar appium driver install "$driver"
    fi
}

alvo_appium() {
    negrito "Appium e driver XCUITest"
    if [ ! -x /Applications/Xcode.app/Contents/Developer/usr/bin/simctl ] && [ -z "${DEVELOPER_DIR:-}" ]; then
        echo "  Aviso: o Xcode completo não foi encontrado. O WebDriverAgent precisa dele."
        echo "  Instale pela App Store e abra o Xcode uma vez para aceitar a licença."
    fi
    garantir_appium
    instalar_driver xcuitest
    echo "  Na primeira vez que o Mo baile pedir o WebDriverAgent, o Appium compila o WDA. Leva minutos."
}

alvo_appium_android() {
    negrito "Appium e driver UiAutomator2"
    garantir_appium
    instalar_driver uiautomator2
    echo "  O UiAutomator2 também precisa de Java (brew install --cask temurin) e de ANDROID_HOME."
}

# -------------------------------------------------------------------- extras

alvo_ios_device() {
    negrito "pymobiledevice3 (iPhone físico por cabo)"
    instalar_pacotes "pymobiledevice3>=11.0"
}

alvo_escuta() {
    negrito "pyobjc-framework-Quartz (escuta passiva)"
    instalar_pacotes "pyobjc-framework-Quartz>=10.0"
}

# ------------------------------------------------------------------ verificar

alvo_verificar() {
    negrito "O que está pronto"
    [ -n "$MOTOR_SRC" ] || { echo "  Motor não encontrado ao lado do script."; return 0; }
    local py="${MOBAILE_PYTHON:-}"
    if [ -z "$py" ] || [ ! -x "$py" ]; then
        if [ -x "$APP_VENV/bin/python3" ]; then py="$APP_VENV/bin/python3"; else py="$(python_base || true)"; fi
    fi
    [ -n "$py" ] || { echo "  Nenhum Python 3.10+ ainda."; return 0; }
    PYTHONPATH="$MOTOR_SRC" "$py" -m mobaile.services.setup || true
}

# ---------------------------------------------------------------------- main

[ $# -gt 0 ] || { sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

for alvo in "$@"; do
    case "$alvo" in
        python) alvo_python ;;
        android) alvo_android ;;
        scrcpy) alvo_scrcpy ;;
        appium) alvo_appium ;;
        appium-android) alvo_appium_android ;;
        ios-device) alvo_ios_device ;;
        escuta) alvo_escuta ;;
        tudo) alvo_python; alvo_android; alvo_scrcpy; alvo_appium ;;
        verificar) ;;
        *) falha "alvo desconhecido: $alvo (rode sem argumentos para ver a lista)." ;;
    esac
done

alvo_verificar
negrito "Pronto. Volte ao Mo baile: a tela Início confere de novo sozinha."
echo "  Se instalou um Python novo, clique em Reiniciar Motor na tela Início."

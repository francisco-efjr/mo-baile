#!/bin/bash
#
# Instala o Mo baile num Mac com um comando, sem o bloqueio do Gatekeeper
# ("A Apple não pôde verificar se o item está livre de malware"):
#
#   curl -fsSL https://raw.githubusercontent.com/francisco-efjr/mo-baile/main/tools/instalar.sh | bash
#
# O que faz, na ordem:
#   1. confere o Mac: Apple Silicon e macOS 14 ou mais novo;
#   2. baixa o zip do último release e confere o SHA-256 publicado junto;
#   3. instala o app em /Applications, ou em ~/Applications quando a conta não
#      é de administrador, trocando a versão anterior se houver;
#   4. prepara o Python do Mo baile em ~/Library/Application Support/Mo baile/python:
#      um Python 3.12 próprio, com Pillow e requests, sem Homebrew e sem senha;
#   5. sobe o motor embutido com esse Python (engine.hello) e abre o app.
#
# Por que não aparece o aviso: o Gatekeeper só confere arquivos marcados com o
# atributo de quarentena, que o navegador, o Slack e o AirDrop gravam no
# download. O curl não grava. O zip é o mesmo da página de Releases, e o SHA-256
# prova que ele chegou inteiro. A confiança é a mesma do "Abrir Mesmo Assim":
# na origem do arquivo (README, "Aviso: o app não é notarizado").
#
# Variáveis opcionais:
#   MOBAILE_VERSAO=3.26.0  instala essa versão em vez da última
#   MOBAILE_DESTINO=pasta  instala o app nessa pasta
#   MOBAILE_ABRIR=0        não abre o app no fim
#   MOBAILE_SUPORTE=pasta  troca a pasta do Python (só para testes: o app procura
#                          o Python apenas na pasta padrão)
#
# Escrito para o /bin/bash 3.2 do macOS. Não chama /usr/bin/python3, git nem
# lipo: num Mac sem as Command Line Tools, eles abrem o pedido de instalação.
# Tudo fica dentro de main(), que só roda depois que o script chegou inteiro.

if [ -z "${BASH_VERSION:-}" ]; then
    echo "Rode com bash: curl -fsSL <endereço do instalar.sh> | bash" >&2
    exit 1
fi

set -euo pipefail

REPO="francisco-efjr/mo-baile"
APP_NAME="Mo baile (nativo)"
# pgrep usa expressão regular: parênteses e ponto escapados.
APP_RODANDO='Mo baile \(nativo\)\.app/Contents/MacOS/'
MACOS_MINIMO="14.0"

# Python do Mo baile: build "install_only" do python-build-standalone (o mesmo
# projeto de onde o uv tira os Pythons), fixo por versão e SHA-256. Para trocar,
# veja docs/INSTALACAO.md, seção "Instalador de um comando".
PY_RELEASE="20261026"
PY_ARQUIVO="cpython-3.12.16+${PY_RELEASE}-aarch64-apple-darwin-install_only.tar.gz"
PY_SHA256="fbf4afef53c2a6b72bb741bc06d5671a9dfaf87bd84e5aa73ac9b3d0d589f14e"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_RELEASE}/${PY_ARQUIVO//+/%2B}"

# Dependências do motor (engine/pyproject.toml) e o extra da escuta passiva,
# o mesmo conjunto do `tools/setup/instalar-mac.sh python`.
PACOTES_MOTOR="Pillow requests"
PACOTE_ESCUTA="pyobjc-framework-Quartz>=10.0"

# A mesma sonda do PythonProbe (EngineLocator.swift), rodada com -I -S como o
# app faz: imprime "OK 3.12.16", "OLD 3.9.6" ou "MISSING 3.12.16 Pillow".
SONDA='import sys, os, site, importlib.util
for d in site.getsitepackages():
    if d not in sys.path and os.path.isdir(d):
        sys.path.append(d)
v = "%d.%d.%d" % sys.version_info[:3]
if sys.version_info[:2] < (3, 10):
    print("OLD", v)
else:
    faltam = [nome for mod, nome in [("PIL", "Pillow"), ("requests", "requests")] if importlib.util.find_spec(mod) is None]
    print("MISSING" if faltam else "OK", v, *faltam)'

if [ -t 1 ]; then NEG=$'\033[1m'; FIM=$'\033[0m'; else NEG=""; FIM=""; fi

passo() { printf '\n%s==> %s%s\n' "$NEG" "$*" "$FIM"; }
info() { printf '    %s\n' "$*"; }

# falha "o que houve" ["o que fazer" ...]
falha() {
    printf '\n%sNão deu para instalar:%s %s\n' "$NEG" "$FIM" "$1" >&2
    shift
    local linha
    for linha in "$@"; do printf '  %s\n' "$linha" >&2; done
    printf '  Nada foi apagado. Corrigido isso, rode o mesmo comando de novo.\n' >&2
    exit 1
}

# baixar URL ARQUIVO: só HTTPS, com novas tentativas e barra de progresso no
# terminal.
baixar() {
    local progresso="--silent"
    if [ -t 2 ]; then progresso="--progress-bar"; fi
    curl --fail --show-error "$progresso" --location --proto '=https' --tlsv1.2 \
        --retry 3 --retry-delay 2 --connect-timeout 20 -o "$2" "$1"
}

sha256_de() {
    if [ -x /usr/bin/shasum ]; then
        /usr/bin/shasum -a 256 "$1" | awk '{print tolower($1)}'
    else
        /usr/bin/openssl dgst -sha256 -r "$1" | awk '{print tolower($1)}'
    fi
}

# versao_ge A B: A >= B, comparando até três partes numéricas.
versao_ge() {
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<< "$1"
    IFS=. read -r b1 b2 b3 <<< "$2"
    a1="${a1:-0}"; a2="${a2:-0}"; a3="${a3:-0}"
    b1="${b1:-0}"; b2="${b2:-0}"; b3="${b3:-0}"
    [ "$a1" -gt "$b1" ] && return 0; [ "$a1" -lt "$b1" ] && return 1
    [ "$a2" -gt "$b2" ] && return 0; [ "$a2" -lt "$b2" ] && return 1
    [ "$a3" -ge "$b3" ]
}

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true; }

conferir_mac() {
    passo "Conferindo o Mac"
    [ "$(uname -s)" = "Darwin" ] || falha "este instalador é só para macOS." \
        "No Windows e no Linux, use o Relatório e o Analytics no navegador (README, Windows e Linux)."
    # hw.optional.arm64 diz o chip de verdade, mesmo num Terminal aberto pelo Rosetta.
    if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" != "1" ]; then
        falha "este Mac tem processador Intel, e o Mo baile só roda em Apple Silicon (M1 ou mais novo)." \
            "Confira em Menu Apple › Sobre Este Mac: a linha Chip precisa dizer Apple M…"
    fi
    MACOS="$(sw_vers -productVersion)"
    versao_ge "$MACOS" "$MACOS_MINIMO" || falha "este Mac está no macOS $MACOS, e o Mo baile precisa do macOS 14 ou mais novo." \
        "Atualize em Ajustes do Sistema › Geral › Atualização de Software."
    if pgrep -f "$APP_RODANDO" >/dev/null 2>&1; then
        falha "o Mo baile está aberto." "Feche o app (⌘Q) e rode o mesmo comando de novo."
    fi
    info "macOS $MACOS, Apple Silicon."
}

descobrir_versao() {
    if [ -n "${MOBAILE_VERSAO:-}" ]; then
        VERSAO="${MOBAILE_VERSAO#v}"
    else
        local url
        url="$(curl --fail --silent --show-error --location --proto '=https' --head \
            --retry 3 --connect-timeout 20 -o /dev/null -w '%{url_effective}' \
            "https://github.com/$REPO/releases/latest")" \
            || falha "não consegui falar com o github.com." \
                "Confira a internet. Em rede de empresa, o acesso ao github.com pode estar bloqueado."
        VERSAO="${url##*/}"
        VERSAO="${VERSAO#v}"
    fi
    printf '%s' "$VERSAO" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
        || falha "versão inválida: '$VERSAO'." "Use MOBAILE_VERSAO=X.Y.Z ou deixe em branco para a última."
}

baixar_app() {
    passo "Baixando o Mo baile $VERSAO"
    local zip="MoBaile-$VERSAO-macOS.zip"
    local base="https://github.com/$REPO/releases/download/v$VERSAO"
    baixar "$base/$zip.sha256" "$TMP/$zip.sha256" \
        || falha "não achei o release v$VERSAO em github.com/$REPO/releases."
    baixar "$base/$zip" "$TMP/$zip" || falha "o download do zip não terminou." "Confira a internet."
    local esperado obtido
    esperado="$(awk '{print tolower($1); exit}' "$TMP/$zip.sha256")"
    obtido="$(sha256_de "$TMP/$zip")"
    [ -n "$esperado" ] && [ "$esperado" = "$obtido" ] \
        || falha "o zip baixado não confere com o SHA-256 publicado no release." \
            "Esperado: $esperado" "Obtido:   $obtido"
    info "SHA-256 confere: $obtido"

    mkdir "$TMP/app"
    ditto -x -k "$TMP/$zip" "$TMP/app" || falha "não consegui descompactar o zip."
    NOVO="$TMP/app/$APP_NAME.app"
    [ -d "$NOVO" ] || falha "o zip não tem o $APP_NAME.app."
    codesign --verify --deep --strict "$NOVO" 2>/dev/null \
        || falha "a assinatura do app baixado não confere (codesign --verify)."
    local no_app minimo
    no_app="$(plist "$NOVO" CFBundleShortVersionString)"
    [ "$no_app" = "$VERSAO" ] || falha "o app do zip diz versão '$no_app', o release é $VERSAO."
    minimo="$(plist "$NOVO" LSMinimumSystemVersion)"
    if [ -n "$minimo" ] && ! versao_ge "$MACOS" "$minimo"; then
        falha "esta versão do Mo baile precisa do macOS $minimo, e este Mac está no $MACOS." \
            "Atualize em Ajustes do Sistema › Geral › Atualização de Software."
    fi
}

instalar_app() {
    passo "Instalando o app"
    local destino
    if [ -n "${MOBAILE_DESTINO:-}" ]; then
        destino="$MOBAILE_DESTINO"
    elif [ -w /Applications ]; then
        destino="/Applications"
    else
        destino="$HOME/Applications"
        info "Esta conta não grava em /Applications: o app vai para $destino (não pede senha)."
    fi
    mkdir -p "$destino" || falha "não consegui criar a pasta $destino."
    DEST="$destino/$APP_NAME.app"

    # A versão anterior sai inteira para a pasta temporária e só é apagada
    # depois que a nova estiver no lugar.
    local anterior=""
    if [ -e "$DEST" ]; then
        anterior="$TMP/anterior.app"
        mv "$DEST" "$anterior" 2>/dev/null \
            || falha "não consegui trocar o app que já está em $DEST." \
                "Arraste esse app para o Lixo. Se o macOS disser que o Terminal não pode alterar apps," \
                "libere em Ajustes do Sistema › Privacidade e Segurança › Gerenciamento de Apps › Terminal."
        info "Versão anterior: $(plist "$anterior" CFBundleShortVersionString) (substituída)."
    fi
    if ! mv "$NOVO" "$DEST"; then
        [ -n "$anterior" ] && mv "$anterior" "$DEST" 2>/dev/null
        falha "não consegui gravar o app em $destino."
    fi
    # O curl não grava quarentena; isto cobre um zip que tenha passado por outro caminho.
    xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
    if xattr -lr "$DEST" 2>/dev/null | grep -q 'com.apple.quarantine'; then
        falha "o app ficou com o atributo de quarentena e o macOS ia bloquear a abertura."
    fi
    codesign --verify --deep --strict "$DEST" 2>/dev/null || falha "a assinatura do app instalado não confere."
    info "App em $DEST, sem quarentena e com a assinatura conferida."

    if [ "$destino" != "/Applications" ] && [ -d "/Applications/$APP_NAME.app" ]; then
        info "Atenção: há outra cópia em /Applications. Arraste-a para o Lixo para não abrir a antiga."
    fi
}

sonda() {
    "$1" -I -S -c "$SONDA" 2>/dev/null | head -n 1 || true
}

pip_instalar() {
    # PIP_USER e PIP_REQUIRE_VIRTUALENV de quem roda não podem mandar os pacotes
    # para outro lugar nem recusar o Python do Mo baile.
    PIP_USER=0 PIP_REQUIRE_VIRTUALENV=0 PIP_DISABLE_PIP_VERSION_CHECK=1 \
        "$PY" -m pip install --quiet --no-input --no-warn-script-location "$@"
}

instalar_python_novo() {
    info "Baixando o Python 3.12 do Mo baile (cerca de 25 MB)."
    baixar "$PY_URL" "$TMP/python.tar.gz" \
        || falha "o download do Python não terminou." "Confira o acesso a github.com."
    local obtido
    obtido="$(sha256_de "$TMP/python.tar.gz")"
    [ "$obtido" = "$PY_SHA256" ] || falha "o Python baixado não confere com o SHA-256 esperado." \
        "Esperado: $PY_SHA256" "Obtido:   $obtido"
    mkdir "$TMP/py"
    tar -xzf "$TMP/python.tar.gz" -C "$TMP/py" || falha "não consegui descompactar o Python."
    [ -x "$TMP/py/python/bin/python3" ] || falha "o pacote do Python veio sem python/bin/python3."
    if [ -e "$PYDIR" ]; then
        local guarda
        guarda="$PYDIR.anterior-$(date +%Y%m%d%H%M%S)"
        mv "$PYDIR" "$guarda" || falha "não consegui tirar do caminho o Python antigo em $PYDIR."
        info "O Python antigo, que não servia, ficou em $guarda (pode apagar)."
    fi
    mkdir -p "$SUPORTE"
    mv "$TMP/py/python" "$PYDIR" || falha "não consegui gravar o Python em $PYDIR."
    xattr -dr com.apple.quarantine "$PYDIR" 2>/dev/null || true
}

preparar_python() {
    passo "Preparando o Python do motor"
    SUPORTE="${MOBAILE_SUPORTE:-$HOME/Library/Application Support/Mo baile}"
    PYDIR="$SUPORTE/python"
    PY="$PYDIR/bin/python3"

    local resultado=""
    [ -x "$PY" ] && resultado="$(sonda "$PY")"
    case "$resultado" in
        OK\ *)
            info "Já estava pronto: Python ${resultado#OK } em $PYDIR."
            pip_instalar "$PACOTE_ESCUTA" >/dev/null 2>&1 || true
            return 0 ;;
        MISSING\ *)
            # Python da versão certa sem os pacotes: tenta completar antes de trocar.
            info "Completando os pacotes do Python que já existe em $PYDIR."
            pip_instalar $PACOTES_MOTOR >/dev/null 2>&1 || true
            resultado="$(sonda "$PY")" ;;
    esac
    case "$resultado" in
        OK\ *) ;;
        *)
            instalar_python_novo
            info "Instalando Pillow e requests."
            pip_instalar $PACOTES_MOTOR \
                || falha "não consegui instalar Pillow e requests." \
                    "O pip precisa de acesso a pypi.org e files.pythonhosted.org." \
                    "Em rede de empresa, confira com a TI ou use outra rede."
            resultado="$(sonda "$PY")" ;;
    esac
    case "$resultado" in
        OK\ *) ;;
        *) falha "o Python do Mo baile não passou na conferência do app (${resultado:-sem resposta})." ;;
    esac
    # A escuta passiva de toques no simulador usa o Quartz; sem ele o resto funciona.
    pip_instalar "$PACOTE_ESCUTA" >/dev/null 2>&1 \
        || info "Aviso: o pacote opcional da escuta passiva (Quartz) não instalou; o resto funciona."
    info "Python ${resultado#OK } com Pillow e requests em $PYDIR."
    if [ -n "${MOBAILE_SUPORTE:-}" ]; then
        info "Atenção: MOBAILE_SUPORTE aponta para uma pasta de teste; o app não procura o Python ali."
    fi
}

conferir_motor() {
    passo "Conferindo o motor"
    local motor protocolo resposta
    motor="$DEST/Contents/Resources/engine/src"
    protocolo="$(sed -n 's/^PROTOCOL_VERSION = \([0-9][0-9]*\).*/\1/p' "$motor/mobaile/rpc/contract.py" 2>/dev/null || true)"
    [ -n "$protocolo" ] || falha "o app instalado veio sem o motor embutido."
    # Mesmo comando do verify_native_app.sh. Sem bytecode: o selo cobre o motor.
    resposta="$(printf '{"jsonrpc":"2.0","id":1,"method":"engine.hello","params":{"protocol_version":%s}}\n' "$protocolo" \
        | PYTHONPATH="$motor" PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 "$PY" -S -m mobaile.rpc 2>"$TMP/motor.log" \
        | head -n 1 || true)"
    if ! printf '%s' "$resposta" | grep -q "\"engine_version\":\"$VERSAO\""; then
        tail -n 5 "$TMP/motor.log" >&2 || true
        falha "o motor não respondeu com o Python do Mo baile (resposta: ${resposta:-vazia})."
    fi
    codesign --verify --deep --strict "$DEST" 2>/dev/null \
        || falha "a assinatura do app quebrou depois de subir o motor."
    info "O motor $VERSAO subiu e respondeu."
}

main() {
    printf '%sInstalador do Mo baile%s\n' "$NEG" "$FIM"
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/mobaile-instalar.XXXXXX")"
    trap 'rm -rf "$TMP"' EXIT

    conferir_mac
    descobrir_versao
    baixar_app
    instalar_app
    preparar_python
    conferir_motor

    passo "Pronto"
    info "Mo baile $VERSAO instalado em $DEST."
    info "Na primeira abertura o macOS pode pedir acesso à rede local: é o proxy de Rede. Pode permitir."
    info "As próximas versões chegam pelo próprio app (Atualizar › Reiniciar e Atualizar)."
    if [ "${MOBAILE_ABRIR:-1}" != "0" ]; then
        open "$DEST" || info "Abra o Mo baile pela pasta Aplicativos ou pelo Spotlight."
    fi
}

main "$@"

#!/usr/bin/env bash
#
# Empacota o FRONT NATIVO (SwiftUI) como bundle .app.
#
# LEIA ANTES DE RODAR
# -------------------
# A versao anterior deste script fazia `rm -rf "/Applications/Mo baile.app"` e
# instalava a build Swift por cima, com o mesmo nome do app que estava em uso.
# Como o front nativo ainda nao esta terminado, o resultado foi um app que abre
# no estado vazio, nao reconhece dispositivo e nao espelha simulador. Foi
# exatamente isso que aconteceu em 05/09/2026 as 20:17.
#
# Travas que impedem que se repita:
#   1. `swift test` roda antes, e a instalacao aborta se algum teste falhar;
#   2. o destino padrao e "Mo baile (nativo).app", um app separado. Substituir
#      o app em uso passou a ser um ato explicito:
#        APP_NAME="Mo baile" bash tools/package_macos_app.sh
#   3. com o app aberto, o script recusa rodar (nao encerra o processo);
#   4. o bundle e montado num diretorio temporario (staging) no mesmo volume,
#      assinado e conferido com `codesign --verify`. So depois o app instalado
#      e trocado, com `mv` atomico: o antigo vira backup e volta se algo falhar.
#
# Variaveis:
#   DEST_DIR       destino do .app (padrao /Applications). O workflow de release
#                  usa um diretorio do runner.
#   APP_NAME       nome do bundle (padrao "Mo baile (nativo)").
#   SIGN_IDENTITY  identidade do codesign (padrao "-", ad-hoc). Outra identidade
#                  liga hardened runtime e timestamp (docs/RELEASE.md).
#
# Para instalar a interface Python, use tools/install_tk_app.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Mo baile (nativo)}"
DEST_DIR="${DEST_DIR:-/Applications}"
DEST_DIR="${DEST_DIR%/}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_DIR="$DEST_DIR/$APP_NAME.app"
# Fonte unica da versao (docs/VERSIONAMENTO.md). Sem ela, nao empacota: um app
# com versao inventada nao diz qual codigo esta rodando.
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
[ -n "$VERSION" ] || { echo "erro: VERSION vazio ou ausente na raiz do repositorio."; exit 1; }
python3 "$REPO_ROOT/tools/version.py" check || { echo "ABORTADO: versao inconsistente."; exit 1; }

command -v swift >/dev/null || { echo "erro: swift nao encontrado. Instale as Command Line Tools do Xcode."; exit 1; }

# Rastreabilidade: o commit vai para o Info.plist (MoBaileGitCommit) e o
# verify_native_app.sh confere contra o HEAD. "-dirty" marca build feito com
# mudancas rastreadas ainda nao commitadas.
GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo desconhecido)"
if [ "$GIT_COMMIT" != "desconhecido" ] && ! git -C "$REPO_ROOT" diff --quiet HEAD -- 2>/dev/null; then
    GIT_COMMIT="$GIT_COMMIT-dirty"
    echo "aviso: arvore com mudancas nao commitadas; o app sai marcado como $GIT_COMMIT."
fi

# pgrep -f usa regex: "Mo baile (nativo)" sem escape casaria "Mo baile nativo"
# e nunca acharia o app. Escapa o caminho do executavel e procura por ele.
regex_literal() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }
APP_PROC_REGEX="$(regex_literal "$APP_DIR/Contents/MacOS/")"

recusar_se_aberto() {
    if pgrep -f "$APP_PROC_REGEX" >/dev/null 2>&1; then
        echo
        echo "ABORTADO: $APP_DIR esta aberto."
        echo "Feche o app (Cmd+Q) e rode de novo. O script nao encerra o processo:"
        echo "trocar o bundle por baixo de um app aberto derruba o motor em uso."
        exit 1
    fi
}

recusar_se_aberto

if [ "$APP_NAME" = "Mo baile" ]; then
    echo
    echo "ATENCAO: isto vai SUBSTITUIR o app em uso em $DEST_DIR/Mo baile.app."
    read -r -p "Digite 'substituir' para confirmar: " confirmacao
    [ "$confirmacao" = "substituir" ] || { echo "Cancelado."; exit 1; }
fi

cd "$REPO_ROOT/apps/MoBaile"

echo "==> Rodando a suite do front antes de empacotar"
if ! swift test; then
    echo
    echo "ABORTADO: a suite do front nao passou."
    echo "Empacotar assim entregaria um app que abre sem funcionar."
    exit 1
fi

echo "==> Compilando o front (release)"
swift build -c release

# --- Staging -----------------------------------------------------------------
# No mesmo volume do destino, para o `mv` final ser um rename atomico.
mkdir -p "$DEST_DIR"
STAGE="$(mktemp -d "$DEST_DIR/.mobaile-staging.XXXXXX")"
NOVO="$STAGE/$APP_NAME.app"
BACKUP="$STAGE/anterior.app"
CONTENTS="$NOVO/Contents"

finalizar() {
    local rc=$?
    # Falhou entre tirar o antigo e pôr o novo: devolve o antigo.
    if [ -d "$BACKUP" ] && [ ! -e "$APP_DIR" ]; then
        if mv "$BACKUP" "$APP_DIR"; then
            echo "Restaurado o app anterior em $APP_DIR."
        else
            echo "ERRO: nao consegui restaurar o app anterior. Ele esta em $BACKUP." >&2
            exit "$rc"
        fi
    fi
    case "$STAGE" in
        "$DEST_DIR"/.mobaile-staging.*) rm -rf "$STAGE" ;;
    esac
    exit "$rc"
}
trap finalizar EXIT
trap 'exit 130' INT TERM

echo "==> Montando o bundle em staging ($STAGE)"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp ".build/release/MoBaile" "$CONTENTS/MacOS/$APP_NAME"

echo "==> Copiando recursos"
ASSETS="$REPO_ROOT/assets"
for file in icon.icns icon.png mascot.png splash_bg.png splash_app.mp4; do
    if [ -f "$ASSETS/$file" ]; then cp "$ASSETS/$file" "$CONTENTS/Resources/"; fi
done
if [ -f "$ASSETS/icon.icns" ]; then cp "$ASSETS/icon.icns" "$CONTENTS/Resources/AppIcon.icns"; fi

echo "==> Compilando a cor de destaque (Assets.car)"
# O flamingo do design system (#C2456E) vira a cor de destaque do app: seleção
# da barra lateral, das tabelas e da árvore, botão padrão. Sem o catálogo, o
# macOS usa o destaque do sistema. O actool vem com o Xcode, não com as
# Command Line Tools.
ACCENT_PLIST=""
if xcrun --find actool >/dev/null 2>&1; then
    parcial="$STAGE/actool-parcial.plist"
    xcrun actool "$REPO_ROOT/apps/MoBaile/AppResources/Assets.xcassets" \
        --compile "$CONTENTS/Resources" --platform macosx --minimum-deployment-target 14.0 \
        --output-partial-info-plist "$parcial" --errors >/dev/null
    rm -f "$parcial"
    ACCENT_PLIST="<key>NSAccentColorName</key>
    <string>AccentColor</string>"
else
    echo "aviso: actool nao encontrado (precisa do Xcode); a selecao usa o destaque do sistema."
fi

echo "==> Embutindo o motor Python"
# O front resolve este caminho em EngineLocator (Contents/Resources/engine/src).
mkdir -p "$CONTENTS/Resources/engine"
cp -R "$REPO_ROOT/engine/src" "$CONTENTS/Resources/engine/src"
find "$CONTENTS/Resources/engine" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

echo "==> Gerando Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.qa.mobaile</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>MoBaileGitCommit</key>
    <string>$GIT_COMMIT</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt-BR</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    $ACCENT_PLIST
    <key>NSLocalNetworkUsageDescription</key>
    <string>O Mo baile abre um proxy local para inspecionar o trafego do aparelho conectado.</string>
</dict>
PLIST
echo "</plist>" >> "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" >/dev/null

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> Assinando (ad-hoc)"
    # Ad-hoc serve para rodar na propria maquina. Para distribuir sem o aviso do
    # Gatekeeper: Developer ID + notarizacao (docs/RELEASE.md).
    codesign --force --deep --sign - "$NOVO"
else
    echo "==> Assinando com $SIGN_IDENTITY (hardened runtime)"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$NOVO"
fi

echo "==> Conferindo a assinatura"
codesign --verify --deep --strict --verbose=2 "$NOVO"

# --- Troca atomica -----------------------------------------------------------
# O app pode ter sido aberto durante o build.
recusar_se_aberto

echo "==> Instalando em $APP_DIR"
if [ -e "$APP_DIR" ]; then
    mv "$APP_DIR" "$BACKUP"
fi
mv "$NOVO" "$APP_DIR"
rm -rf "$BACKUP"

if [ "$DEST_DIR" = "/Applications" ]; then
    echo "==> Registrando no LaunchServices"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" || true
fi

echo "OK: $APP_DIR (versao $VERSION, commit $GIT_COMMIT)"

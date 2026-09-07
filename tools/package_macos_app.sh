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
# Duas travas agora impedem que se repita:
#   1. `swift test` roda antes, e a instalacao aborta se algum teste falhar;
#   2. o destino padrao e "Mo baile (nativo).app", um app separado. Substituir
#      o app em uso passou a ser um ato explicito:
#        APP_NAME="Mo baile" bash tools/package_macos_app.sh
#
# Para instalar a interface Python, que e a que funciona hoje, use
# tools/install_tk_app.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Mo baile (nativo)}"
DEST_DIR="${DEST_DIR:-/Applications}"
APP_DIR="$DEST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$REPO_ROOT/engine/src/mobaile/__init__.py" | head -1)"
VERSION="${VERSION:-2.0.0}"

command -v swift >/dev/null || { echo "erro: swift nao encontrado. Instale as Command Line Tools do Xcode."; exit 1; }

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

if [ "$APP_NAME" = "Mo baile" ]; then
    echo
    echo "ATENCAO: isto vai SUBSTITUIR o app em uso em $DEST_DIR/Mo baile.app."
    read -r -p "Digite 'substituir' para confirmar: " confirmacao
    [ "$confirmacao" = "substituir" ] || { echo "Cancelado."; exit 1; }
fi

echo "==> Montando o bundle em $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp ".build/release/MoBaile" "$CONTENTS/MacOS/$APP_NAME"

echo "==> Copiando recursos"
ASSETS="$REPO_ROOT/assets"
for file in icon.icns icon.png mascot.png splash_bg.png splash_app.mp4; do
    [ -f "$ASSETS/$file" ] && cp "$ASSETS/$file" "$CONTENTS/Resources/"
done
[ -f "$ASSETS/icon.icns" ] && cp "$ASSETS/icon.icns" "$CONTENTS/Resources/AppIcon.icns"

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
    <key>CFBundleDevelopmentRegion</key>
    <string>pt-BR</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>O Mo baile abre um proxy local para inspecionar o trafego do aparelho conectado.</string>
</dict>
PLIST
echo "</plist>" >> "$CONTENTS/Info.plist"

echo "==> Assinando (ad-hoc)"
# Ad-hoc serve para rodar na propria maquina. Para distribuir para o time sem o
# aviso do Gatekeeper e preciso Developer ID + notarizacao:
#   codesign --force --options runtime --sign "Developer ID Application: <nome>" "$APP_DIR"
#   xcrun notarytool submit ... && xcrun stapler staple "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Registrando no LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" || true

echo "OK: $APP_DIR (versao $VERSION)"

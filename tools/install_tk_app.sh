#!/usr/bin/env bash
#
# Instala o Mo baile (interface Python/Tk, a que esta em uso) como bundle .app.
#
# Este script NAO compila Swift. O front nativo tem script proprio
# (tools/package_macos_app.sh) e so deve ser instalado depois de `swift test`
# passar, porque ate la ele abre no estado vazio e nao reconhece dispositivo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Mo baile}"
DEST_DIR="${DEST_DIR:-/Applications}"
APP_DIR="$DEST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Instalando $APP_DIR (interface Python/Tk)"
echo "    codigo em: $REPO_ROOT"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

ASSETS="$REPO_ROOT/assets"
for file in icon.icns icon.png mascot.png splash_bg.png splash_app.mp4; do
    [ -f "$ASSETS/$file" ] && cp "$ASSETS/$file" "$CONTENTS/Resources/"
done
[ -f "$ASSETS/icon.icns" ] && cp "$ASSETS/icon.icns" "$CONTENTS/Resources/AppIcon.icns"

# O executavel do bundle e um script. Nao e Mach-O, entao nao exige assinatura,
# e o caminho do codigo fica legivel em vez de embutido num binario.
cat > "$CONTENTS/MacOS/$APP_NAME" <<LAUNCHER
#!/bin/bash
# Lancador do Mo baile. Gerado por tools/install_tk_app.sh.
REPO="$REPO_ROOT"
LOG="\$HOME/Library/Logs/Mo baile.log"
mkdir -p "\$(dirname "\$LOG")"

falhar() {
    # Sem isto, um erro aqui faria o app "abrir e sumir" sem explicacao.
    echo "\$(date '+%Y-%m-%d %H:%M:%S') ERRO: \$1" >> "\$LOG"
    osascript -e "display dialog \"\$1\n\nDetalhes em ~/Library/Logs/Mo baile.log\" with title \"Mo baile\" buttons {\"OK\"} default button 1 with icon stop" >/dev/null 2>&1
    exit 1
}

[ -d "\$REPO" ] || falhar "Pasta do projeto nao encontrada em \$REPO"
[ -f "\$REPO/apps/tk-legacy/main.py" ] || falhar "main.py nao encontrado em \$REPO/apps/tk-legacy"

PY="python3"
[ -x "\$REPO/.venv/bin/python3" ] && PY="\$REPO/.venv/bin/python3"

"\$PY" -c "import tkinter" 2>/dev/null || falhar "O Python usado (\$PY) nao tem tkinter."

cd "\$REPO"
echo "\$(date '+%Y-%m-%d %H:%M:%S') iniciando com \$PY" >> "\$LOG"
exec "\$PY" "\$REPO/apps/tk-legacy/main.py" >> "\$LOG" 2>&1
LAUNCHER
chmod +x "$CONTENTS/MacOS/$APP_NAME"

VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$REPO_ROOT/engine/src/mobaile/__init__.py" | head -1)"
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
    <string>${VERSION:-2.0.0}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION:-2.0.0}</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt-BR</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

echo "OK: $APP_DIR"
echo "    log de execucao: ~/Library/Logs/Mo baile.log"

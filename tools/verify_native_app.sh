#!/usr/bin/env bash
#
# Confere se o "Mo baile (nativo).app" instalado nesta maquina esta com o codigo
# do repositorio. Obrigatorio ao fim de qualquer tarefa que mexa no app (ver
# AGENTS.md): `make build-native` instala, este script prova que deu certo.
#
# Verifica tres coisas, na ordem em que costumam falhar:
#   1. a versao do Info.plist e a do motor embutido batem com VERSION;
#   2. o motor embutido e o mesmo codigo de engine/src (nada ficou para tras);
#   3. o Python que o app vai usar sobe o motor embutido e responde ao
#      engine.hello com a versao certa.
#
# O Python e escolhido na mesma ordem do EngineLocator.swift quando o app roda
# fora do repositorio. Se o EngineLocator mudar, mude aqui junto.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Mo baile (nativo)}"
DEST_DIR="${DEST_DIR:-/Applications}"
APP_DIR="$DEST_DIR/$APP_NAME.app"
ENGINE_SRC="$APP_DIR/Contents/Resources/engine/src"
ESPERADA="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"

falha() { echo "FALHOU: $*"; echo "Rode 'make build-native' (com o app fechado) e verifique de novo."; exit 1; }

[ -d "$APP_DIR" ] || falha "$APP_DIR nao existe."

plist="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
[ "$plist" = "$ESPERADA" ] || falha "Info.plist esta em '$plist', o repositorio em '$ESPERADA'."

motor="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$ENGINE_SRC/mobaile/__init__.py" 2>/dev/null || true)"
[ "$motor" = "$ESPERADA" ] || falha "motor embutido esta em '$motor', o repositorio em '$ESPERADA'."

# Mesma versao nao prova mesmo codigo: um agente pode mudar o motor sem subir a
# versao e esquecer de reempacotar.
if ! diff -rq -x "__pycache__" "$REPO_ROOT/engine/src" "$ENGINE_SRC" >/dev/null; then
    diff -rq -x "__pycache__" "$REPO_ROOT/engine/src" "$ENGINE_SRC" | head -5 || true
    falha "o motor embutido difere de engine/src."
fi

python=""
for candidato in "${MOBAILE_PYTHON:-}" /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [ -n "$candidato" ] && [ -x "$candidato" ]; then python="$candidato"; break; fi
done
[ -n "$python" ] || falha "nenhum Python encontrado nos caminhos do EngineLocator."

resposta="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"engine.hello","params":{"protocol_version":2}}' \
    | PYTHONPATH="$ENGINE_SRC" PYTHONNOUSERSITE=1 "$python" -m mobaile.rpc 2>/dev/null | head -n 1 || true)"
echo "$resposta" | grep -q "\"engine_version\":\"$ESPERADA\"" \
    || falha "o motor embutido nao respondeu ao engine.hello com $python (resposta: ${resposta:-vazia})."

echo "OK: $APP_DIR na versao $ESPERADA, motor igual a engine/src, handshake com $python."

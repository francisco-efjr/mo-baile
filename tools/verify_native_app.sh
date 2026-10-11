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
# O Python e escolhido com a mesma regra do EngineLocator.swift quando o app
# roda fora do repositorio: na ordem MOBAILE_PYTHON, /opt/homebrew/bin/python3,
# /usr/local/bin/python3, /usr/bin/python3, vale o primeiro com Python >= 3.10
# e as dependencias do motor importaveis. Se o EngineLocator mudar, mude aqui
# junto.
#
# `--so-python` so escolhe e imprime o Python, sem olhar o app (usado pelos
# testes, com VERIFY_PYTHON_CANDIDATES no lugar dos caminhos fixos).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Mo baile (nativo)}"
DEST_DIR="${DEST_DIR:-/Applications}"
APP_DIR="$DEST_DIR/$APP_NAME.app"
ENGINE_SRC="$APP_DIR/Contents/Resources/engine/src"
ESPERADA="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"

falha() { echo "FALHOU: $*"; echo "Rode 'make build-native' (com o app fechado) e verifique de novo."; exit 1; }

# Dependencias do motor (engine/pyproject.toml, [project].dependencies): nome de
# import e nome de pacote no pip.
MODULOS_DO_MOTOR="PIL requests"
PACOTES_DO_MOTOR="Pillow requests"
CANDIDATOS_PYTHON="${VERIFY_PYTHON_CANDIDATES:-/opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3}"
# Escrita para rodar ate em Python antigo: sai com 3 se a versao nao serve e
# com 4 se falta dependencia.
SONDA='import sys
if sys.version_info < (3, 10):
    sys.exit(3)
try:
    for nome in sys.argv[1:]:
        __import__(nome)
except Exception:
    sys.exit(4)'

# Imprime o primeiro Python que serve. Sem nenhum, explica cada recusa e o que
# instalar, e devolve 1.
escolher_python() {
    local motivos="" candidato rc versao sem_deps=""
    # shellcheck disable=SC2086 # a lista e separada por espaco de proposito
    for candidato in "${MOBAILE_PYTHON:-}" $CANDIDATOS_PYTHON; do
        [ -n "$candidato" ] || continue
        if [ ! -x "$candidato" ]; then
            motivos+="  - $candidato: nao existe"$'\n'
            continue
        fi
        rc=0
        # shellcheck disable=SC2086
        PYTHONNOUSERSITE=1 "$candidato" -c "$SONDA" $MODULOS_DO_MOTOR >/dev/null 2>&1 || rc=$?
        case "$rc" in
            0) echo "$candidato"; return 0 ;;
            3)
                versao="$("$candidato" -V 2>&1 | head -n 1 || true)"
                motivos+="  - $candidato: ${versao:-versao desconhecida}, o motor precisa de 3.10 ou mais novo"$'\n' ;;
            4)
                sem_deps="${sem_deps:-$candidato}"
                motivos+="  - $candidato: faltam dependencias do motor ($PACOTES_DO_MOTOR)"$'\n' ;;
            *) motivos+="  - $candidato: nao rodou (codigo $rc)"$'\n' ;;
        esac
    done
    {
        echo "FALHOU: nenhum Python serve para o motor do app."
        printf '%s' "$motivos"
        echo "O app usa o primeiro Python 3.10 ou mais novo com as dependencias do motor."
        if [ -n "$sem_deps" ]; then
            echo "Instale as dependencias no Python que ja tem a versao certa:"
            echo "  $sem_deps -m pip install $PACOTES_DO_MOTOR"
        else
            echo "Instale um Python 3.10 ou mais novo (ex.: 'brew install python') e, nele:"
            echo "  python3 -m pip install $PACOTES_DO_MOTOR"
        fi
        echo "Ou aponte MOBAILE_PYTHON para um Python que ja tenha tudo."
    } >&2
    return 1
}

if [ "${1:-}" = "--so-python" ]; then
    escolher_python
    exit $?
fi

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

# --- Rastreabilidade do build e assinatura (REL-3) ----------------------------
# Bloco separado da escolha do Python, de proposito. O diff acima prova o motor;
# isto prova o resto do bundle: o binario Swift saiu do commit atual
# (MoBaileGitCommit, gravado pelo package_macos_app.sh) e a assinatura e valida.
conferir_build_e_assinatura() {
    local gravado head saida
    gravado="$(/usr/libexec/PlistBuddy -c "Print :MoBaileGitCommit" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
    [ -n "$gravado" ] || falha "o Info.plist nao tem MoBaileGitCommit (app empacotado por uma versao antiga do script)."
    head="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$head" ] || falha "nao consegui ler o HEAD de $REPO_ROOT."
    [ "${gravado%-dirty}" = "$head" ] \
        || falha "o app foi empacotado do commit $gravado, o repositorio esta em $head."
    if [ "$gravado" != "$head" ]; then
        echo "aviso: o app foi empacotado com mudancas nao commitadas ($gravado)."
    fi
    if ! git -C "$REPO_ROOT" diff --quiet HEAD -- 2>/dev/null; then
        echo "aviso: ha mudancas rastreadas nao commitadas; o app pode nao refleti-las."
    fi
    if ! saida="$(codesign --verify --deep --strict "$APP_DIR" 2>&1)"; then
        echo "$saida"
        falha "assinatura invalida (codesign --verify --deep --strict)."
    fi
    echo "build: commit $gravado, assinatura valida."
}
conferir_build_e_assinatura

python="$(escolher_python)" || exit 1

resposta="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"engine.hello","params":{"protocol_version":2}}' \
    | PYTHONPATH="$ENGINE_SRC" PYTHONNOUSERSITE=1 "$python" -m mobaile.rpc 2>/dev/null | head -n 1 || true)"
echo "$resposta" | grep -q "\"engine_version\":\"$ESPERADA\"" \
    || falha "o motor embutido nao respondeu ao engine.hello com $python (resposta: ${resposta:-vazia})."

echo "OK: $APP_DIR na versao $ESPERADA, motor igual a engine/src, handshake com $python."

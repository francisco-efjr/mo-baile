#!/usr/bin/env bash
# Roda o CLI do Maestro (mobile.dev) sem que nada saia da maquina.
#
# Uso:  tools/maestro_offline/maestro-offline.sh <argumentos do maestro>
#       tools/maestro_offline/maestro-offline.sh mcp        # servidor MCP por stdio
#       tools/maestro_offline/maestro-offline.sh test flow.yaml
#
# Tres camadas, porque nenhuma basta sozinha (ver
# docs/research/maestro-modelo-de-automacao.md, secao "Rede"):
#
# 1. Variaveis de ambiente que o proprio Maestro respeita: desligam a analytics
#    (PostHog), o aviso do `--analyze` e o aviso de atualizacao.
# 2. MAESTRO_API_URL e MAESTRO_CLOUD_API_URL apontando para 127.0.0.1:9 (porta
#    "discard", onde nada escuta). Isso cobre o que as variaveis nao desligam:
#    a consulta de versao nova (feita sempre, a variavel so esconde o aviso), o
#    relatorio de erro e o relatorio de profundidade de tela, que nao tem
#    opcao de desligar no codigo do CLI.
# 3. sandbox-exec com rede de saida negada, exceto localhost e sockets unix.
#    Pega o que tem endereco fixo no codigo (a ferramenta MCP `cheat_sheet`
#    chama api.copilot.mobile.dev direto). adb (5037), o driver Android
#    (porta 7001 via adb forward) e o runner XCTest do iOS ficam em localhost.
#
# Comandos que dependem da nuvem ou de conta sao recusados antes de rodar.
# Sem sandbox-exec o script recusa: falha fechado, nunca roda "meio offline".
set -euo pipefail

die() { echo "maestro-offline: $*" >&2; exit 2; }

for arg in "$@"; do
    case "$arg" in
        cloud|login|logout|record|--analyze|--api-key|--api-url)
            die "'$arg' depende do Maestro Cloud ou de conta; recusado no modo offline." ;;
    esac
done

command -v sandbox-exec >/dev/null 2>&1 || die "sandbox-exec nao encontrado; sem ele nao ha garantia de rede fechada."

# Estado isolado: analytics.json, sessoes e logs do Maestro ficam aqui, longe
# do ~/.maestro do Maestro Studio e sem ler o token de login de ninguem.
STATE_DIR="${MAESTRO_OFFLINE_STATE:-$HOME/Library/Application Support/MoBaile/maestro-offline}"
mkdir -p "$STATE_DIR"

# Auditoria: MAESTRO_OFFLINE_TRAP=<porta> manda as chamadas a api da mobile.dev
# para uma armadilha local (tools/maestro_offline/auditar.py), que registra o
# que teria saido. Continua em localhost.
SINK="http://127.0.0.1:${MAESTRO_OFFLINE_TRAP:-9}"

unset MAESTRO_CLOUD_API_KEY MAESTRO_CLI_AI_KEY
export MAESTRO_CLI_NO_ANALYTICS=1
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
export MAESTRO_DISABLE_UPDATE_CHECK=true
export MAESTRO_API_URL="$SINK"
export MAESTRO_CLOUD_API_URL="$SINK"
export XDG_STATE_HOME="$STATE_DIR"

# A JVM abre socket IPv6 e conecta em ::ffff:127.0.0.1, que o filtro
# "localhost" do sandbox nao reconhece: sem IPv4 puro o Maestro nem acha o
# servidor do adb. JAVA_OPTS/MAESTRO_OPTS valem para o `maestro` instalado.
export JAVA_OPTS="${JAVA_OPTS:-} -Djava.net.preferIPv4Stack=true"
export MAESTRO_OPTS="${MAESTRO_OPTS:-} -Djava.net.preferIPv4Stack=true"

PROFILE='(version 1)
(allow default)
(deny network-outbound)
(allow network-outbound (remote ip "localhost:*"))
(allow network-outbound (remote unix-socket))'

# Onde esta o Maestro: MAESTRO_BIN explicito, o `maestro` instalado no PATH,
# ou o CLI que vem dentro do Maestro Studio (jar + JVM 17 embutidos).
if [[ -n "${MAESTRO_BIN:-}" ]]; then
    exec sandbox-exec -p "$PROFILE" "$MAESTRO_BIN" "$@"
fi
if command -v maestro >/dev/null 2>&1; then
    exec sandbox-exec -p "$PROFILE" "$(command -v maestro)" "$@"
fi

STUDIO="${MAESTRO_STUDIO_APP:-/Applications/Maestro Studio.app}/Contents/Resources/app.asar.unpacked"
case "$(uname -m)" in
    arm64) JVM_ARCH=mac-arm64 ;;
    *) JVM_ARCH=mac-x64 ;;
esac
JAVA="$STUDIO/bundled-jvm/$JVM_ARCH/Contents/Home/bin/java"
JAR="$STUDIO/dist-server/studio-server.jar"
[[ -x "$JAVA" && -f "$JAR" ]] || die "Maestro nao encontrado: instale o CLI ou o Maestro Studio, ou defina MAESTRO_BIN."

exec sandbox-exec -p "$PROFILE" "$JAVA" -Djava.net.preferIPv4Stack=true -Dapple.awt.UIElement=true -cp "$JAR" maestro.cli.AppKt "$@"

#!/usr/bin/env bash
# D1 (decisão do dono): prepara o Mo baile com histórico limpo para publicar.
#
# Este script só faz a parte LOCAL e segura:
#   1. guarda o histórico completo num espelho privado (backup);
#   2. monta um repositório novo, com UM commit, a partir da branch integrada;
#   3. procura dado pessoal ou de empresa na árvore nova e para se achar.
# Ele não fala com o GitHub. Os passos remotos (renomear o repo antigo, deixá-lo
# privado, criar o novo e enviar) estão em d1-historico-limpo.md e são do dono.
#
# Uso: bash d1-historico-limpo.sh <branch-integrada> <pasta-nova> <backup.git> [termos.txt]
#   termos.txt (opcional, fora do repositório): um termo por linha, ou o
#   replacements.txt do filter-repo (usa o lado esquerdo de "==>").
set -euo pipefail

BRANCH="${1:?branch integrada (ex.: main)}"
DEST="${2:?pasta do repositório novo (não pode existir)}"
BACKUP="${3:?caminho do espelho de backup (ex.: ~/mo-baile-historico.git)}"
TERMOS="${4:-}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
NOME="Francisco Edson Ferreira Junior"
EMAIL="279321095+francisco-efjr@users.noreply.github.com"

[ -e "$DEST" ] && { echo "erro: $DEST já existe" >&2; exit 1; }
git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null \
    || { echo "erro: branch $BRANCH não existe" >&2; exit 1; }
VERSAO="$(git -C "$REPO_ROOT" show "$BRANCH:VERSION" | tr -d '[:space:]')"

echo "==> 1. Backup do histórico completo em $BACKUP"
if [ -e "$BACKUP" ]; then
    echo "    já existe; mantido como está"
else
    git clone --quiet --mirror "$REPO_ROOT" "$BACKUP"
fi

echo "==> 2. Repositório novo em $DEST, um commit, a partir de $BRANCH ($VERSAO)"
mkdir -p "$DEST"
git -C "$REPO_ROOT" archive "$BRANCH" | tar -x -C "$DEST"
git -C "$DEST" init --quiet -b main
# --force: o archive só traz arquivos rastreados, inclusive os que o .gitignore
# esconderia (fixtures com .idea/, por exemplo). Sem ele, eles ficariam de fora.
git -C "$DEST" add -A --force
GIT_AUTHOR_NAME="$NOME" GIT_AUTHOR_EMAIL="$EMAIL" GIT_COMMITTER_NAME="$NOME" GIT_COMMITTER_EMAIL="$EMAIL" \
    git -C "$DEST" -c commit.gpgsign=false commit --quiet \
    -m "Mo baile $VERSAO: histórico reiniciado para a liberação pública" \
    -m "O histórico anterior foi arquivado fora do repositório público."
GIT_COMMITTER_NAME="$NOME" GIT_COMMITTER_EMAIL="$EMAIL" \
    git -C "$DEST" tag -a "v$VERSAO" -m "Mo baile $VERSAO"

echo "==> 3. Varredura da árvore nova"
falhou=0
# Padrões genéricos: só avisam (testes usam caminhos fictícios de propósito).
genericos='/Users/[A-Za-z0-9._-]+/|@gmail\.com|-MacBook[A-Za-z0-9-]*\.local'
echo "    padrões genéricos (conferir a olho):"
git -C "$DEST" grep -n -I -E "$genericos" -- . ':!docs/melhorias/2026-11-16-liberacao/pendentes/' | sed 's/^/      /' || echo "      nenhum"
# Termos reais (arquivo fora do repositório): param a publicação.
if [ -n "$TERMOS" ]; then
    lista="$(mktemp)"
    sed -e 's/==>.*$//' -e 's/^regex://' -e 's/^literal://' "$TERMOS" | grep -v '^\s*#' | grep -v '^\s*$' > "$lista"
    # -P: a lista do filter-repo usa sintaxe PCRE (lookahead). Código 1 é "nada
    # achado"; qualquer outro diferente de 0 é erro e para a publicação.
    set +e
    git -C "$DEST" grep -n -I -i -P -f "$lista" -- . ':!docs/melhorias/2026-11-16-liberacao/pendentes/'
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        echo "    ACHADO: termos do arquivo $TERMOS acima" >&2; falhou=1
    elif [ "$rc" -ne 1 ]; then
        echo "    ERRO: a busca de termos falhou (código $rc)" >&2; falhou=1
    fi
    rm -f "$lista"
fi
echo "    autores: $(git -C "$DEST" log --format='%an <%ae>' | sort -u | tr '\n' ' ')"
echo "    imagens para conferir a olho: $(git -C "$DEST" ls-files '*.png' '*.jpg' '*.pdf' | wc -l | tr -d ' ')"

if [ "$falhou" -ne 0 ]; then
    echo "==> Pare aqui: corrija a branch $BRANCH e rode de novo (apague $DEST antes)." >&2
    exit 1
fi
echo "==> Pronto. Próximos passos (no GitHub, pelo dono): d1-historico-limpo.md"

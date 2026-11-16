# Onde estamos antes da liberação pública (16/11/2026)

Levantamento feito a partir do git local, do remoto `francisco-efjr/mo-baile`
(depois de `git fetch`) e dos relatórios de rodada em `docs/melhorias/`.

## 1. Git: o que existe só nesta máquina

| Item | Estado |
|---|---|
| Repositório no GitHub | **Público**, licença MIT, 0 forks, 0 estrelas, issues ligadas, 0 issues abertas |
| `origin/main` | 3.17.3 (`cdf9b03`, PR #13, 05/11) |
| Trabalho fora da `main` | 15 commits, da 3.18.0 à 3.23.0 (`45376ee..4913365`), que estão na branch `melhoria/2026-11-12-execucao-projeto` (sem upstream). Esta rodada parte dela |
| Release "Latest" do GitHub | **3.21.0**, publicada a partir da branch `melhoria/2026-11-03-pycharm-desempenho`, e não da `main`. Quem baixa hoje recebe uma versão que não está na `main` |
| Tags só locais | `v3.3.1`, `v3.4.0`, `v3.17.0`, `v3.18.0`, `v3.19.0`, `v3.20.0`, `v3.22.0`, `v3.23.0`. Mais de 3 tags num push não disparam a workflow de release |
| Branch com commit sem push | `melhoria/2026-11-03-pycharm-desempenho` (+1: `91589eb`, 3.21.1/3.22.0). O commit já está na branch atual |
| PR aberto | mo-baile#5 (dependabot, actions). CI vermelho: versão e motor falham, porque o bump de dependência não subiu a `VERSION` |
| Worktrees `wip` de 06/10 | 6 branches `worktree-agent-*` com trabalho interrompido, nunca testado nem integrado (detalhe em `docs/RODADA_2026-10-05_PENDENCIAS.md`). Ocupam `.claude/worktrees/` |
| Worktrees já integrados | `agent-a7324fdb…` (pycharm-dev), `agent-ad17da0f…` (desempenho-dev), `automacao-fase2`, `design-ds`, `main-3-17-3`: podem ser removidos |
| Arquivos não rastreados | `.claude/launch.json`, `docs/SESSAO_2026-10-08_REDESENHO_3.0.md`, `docs/design/telas/arquivo-2.x/` (39 MB de prints antigos), `docs/status/`, `docs/video/` (vídeos e roteiros de módulo). Nenhum está no git; entram no `.gitignore` nesta rodada para não subirem por engano |

## 2. Pendências de produto, por tema

Só o que continua aberto. Origem entre parênteses.

**Execução do projeto externo** (`2026-11-12-execucao-projeto`)
- Testar a B1 com o projeto real; depois B2 (shim de eventos do behave), B3
  (árvore ao vivo) e B4 (capítulos, print da falha, HTML, `junit.xml`).
- FR-05 completo (o motor recebe o que o diálogo de confiança mostrou).

**Automação mobile** (`2026-10-27-automacao`, `2026-10-28-automacao-sync`, `2026-11-04-automacao-fase2`)
- Aceite no moto g55: o flow que falhava, 10 de 10.
- SYNC-7 (depende do rastro de uma falha), SYNC-11 (`/source` do WDA e iOS no
  runner de localizador), âncora fora de lista rolável.
- Seletor fixo ambíguo (R-05) e seletor igual ao texto digitado no YAML.

**Page Objects e desempenho** (`2026-11-03-pycharm-desempenho`)
- Mac Intel: o binário é só arm64. Binário universal é decisão do dono.
- Medir o modo leve num M1 de 8 GB; conferir as cores claras do PyCharm.
- P1 restantes: Buscar em Tudo (⇧⇧), histórico, ⌘L, breadcrumbs, ⌘F no editor.

**Qualidade e arquitetura** (`2026-10-26`, `2026-10-14`)
- QA-1 (CI contando testes pulados), UX-3/UX-4, SEG-4/SEG-5, ARQ-2/3/4, PLAT-3/4/5.
- `cancelled` em `flow.finished` e `flow.step` no contrato.

**Rodada de 05/10** (`docs/RODADA_2026-10-05_PENDENCIAS.md`)
- PB3 (sessão após reinício), PB5 (teto das filas de eventos), A2/C1 (codegen
  com `ast`), B1 (card de correlação), C2/C3, P0 4 do pesquisador (log do motor
  ao abrir pelo Finder). Parte disso tem branch `wip` preservada.

## 3. O que esta rodada trata

Os pedidos de 16/11 para a liberação: privacidade (árvore e histórico),
download e atualização, ajuda por módulo, aviso de produto em desenvolvimento,
relato de bugs e execução fora do macOS. O resultado está em `MELHORIAS.md`.

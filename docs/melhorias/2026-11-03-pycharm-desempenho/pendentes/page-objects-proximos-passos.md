# Page Objects no modelo do PyCharm: próximos passos

Status: proposta pronta, sem código · Origem: rodada 2026-11-03 (PO-1 a PO-5 entregues na branch `melhoria/2026-11-03-pycharm-dev`).

## Conferências que faltam (antes de dar o P0 por fiel)

| Item | O que fazer | Aceite |
|---|---|---|
| Oráculo T1 | No PyCharm, colar T1 num `.py` vazio, salvar e rodar `xxd`. Guardar como fixture | O `test_codegen_save_bytes.py` passa contra a fixture do oráculo, e não contra a previsão |
| Esquema claro | Ler `expUI_lightScheme.xml` (intellij-community) e corrigir `EditorScheme.pycharm(escuro: false)` | `EditorEsquemaTests` ganha a tabela clara com os valores verificados |
| Coluna no status | Comparar `linha:coluna` com o PyCharm nas linhas L3 (tab) e L6 (emoji) | Mesma coluna nos dois |
| VoiceOver | Ler T1 no editor com o VoiceOver | Lê os caracteres, não as etiquetas |

## P1 que ficou de fora desta rodada

| Item | Proposta | Esforço |
|---|---|---|
| P1-4 Buscar em Tudo | Paleta com abas (Tudo, Arquivos, Símbolos, Passos, Ações), ⇧⇧ e ⇧⌘O; símbolos de um `codegen.outline` com `ast` | M |
| P1-5 Histórico | ⌘[ e ⌘] entre posições; ⌘L (livre) para Ir para Linha:Coluna, aberto também pelo clique em `linha:coluna` no rodapé | M |
| P1-6 Breadcrumbs | `pages › feature.py › click_x` embaixo do editor, pelo outline | P |
| P1-7 Painéis | ⇧⌘F12 como sinônimo do Zen; ⎋ na árvore devolve o foco ao editor; ⌘F contextual no editor (`usesFindBar`) | P |
| ⌘S contextual | Com uma aba de arquivo à frente, ⌘S grava a aba (precisa de decisão do dono, D-2) | P |
| `workspace.changed` | Notificação do motor depois de `codegen.save` e `flow.maestro_export`; hoje o front relê a árvore depois de salvar | P |
| Specs e Relatórios na árvore | Decisão D-4 desta rodada; acrescentar se o dono quiser | P |

## P2 (da pesquisa, seção 6)

Dobra de código, guias de recuo (`#323438`), sticky lines, pares de aspas e parênteses com sobrescrita do fechamento, autocompletar de locators, ⌘/ ⌘D ⌥↑, mostrar espaços (desligado por padrão) e remover espaço no fim só nas linhas modificadas (G19). Critérios de aceite na tabela P2 da pesquisa.

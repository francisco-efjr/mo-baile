# Relatório: o que foi aplicado da análise de design (3.28.0)

Rodada de 19/11/2026. A análise do designer está em
[ANALISE-DESIGN.md](ANALISE-DESIGN.md). Os prints estão em
`docs/design/telas/textos-grandes/`:
- `antes/`: 56 PNGs gerados por um agente à parte;
- `depois/`: as mesmas 14 cenas e mais 3 novas, de erro e do editor de JSON.

Cada cena sai em claro e escuro, na janela de 1280×800 e na pequena.

Para gerar de novo, com a tela do Mac desbloqueada:

```bash
cd apps/MoBaile && MOBAILE_SNAPSHOT_DIR="$PWD/../../docs/design/telas/textos-grandes/depois" swift test --filter 'WindowSnapshotTests/testTextosGrandes'
```

## Aplicado

| ID | O quê | Onde |
|---|---|---|
| RE-01 | Validação agrupada (evento + um grupo por item, aberto se diverge), recorte Todos/Divergentes, Parâmetro com 136 pt, obtido e esperado empilhados no painel estreito, "via item_name" na chave com `\|`, cabeçalho em 2 linhas, Disparo com um grupo por item | `ReportDetailPane.swift`, `ReportCheckGroups.swift` |
| RE-02 | `FieldIssue`, `.dsFieldIssue` e `FieldMessage` no design system; problemas por campo (`ReportCardDraft.issues()`, de onde `problems` deriva); erro depois de sair do campo ou de tentar gravar; "N para corrigir" no cabeçalho; coluna de situação, barra e Próximo Problema (⌘') na Tabela; erro do motor ao gravar perto do formulário do inspector | `Views/DesignSystem/FieldValidation.swift`, `Models/ReportValueRules.swift`, `ReportSpecEditorView.swift`, `ReportCardEditor.swift` |
| RE-03 | Resumo do JSON na célula e folha com `CodeEditorView`, JSON formatado, validação ao vivo com linha e coluna (em português), Cancelar e Aplicar (⌘↩) | `ReportJSONValueSheet.swift`, `ReportFieldRows.swift` |
| RE-04 | Status, Evento, Divergências, Variação, Seção, Fluxo; Horário e Disparos ocultos; personalização guardada (`@SceneStorage`); resumo e ordenação por falhas; corte no meio em Evento, Variação e na tabela Fora da Spec | `ReportView.swift` |
| RE-05 | Largura da chave pelo conteúdo; valor em até 4 linhas; empilhado quando o valor não ganha ~25 caracteres; sem correção automática em campos mono; remover com `BarIconButton`; adicionar com `PlainTextButtonStyle`; Seção, Título, Evento e Observação do inspector crescem com o texto | `ReportFieldRows.swift`, `ReportCardEditor.swift`, `ReportSpecEditorView.swift` |
| RE-06 | `@FocusState`: Adicionar foca a linha nova, Return avança, Esc termina o campo; rótulos "Nome do parâmetro 3 de 5", "Valor de item_id ou item_name, card 2 · purchase" | `ReportFieldRows.swift`, `ReportCardEditor.swift` |
| RE-07 | `AppState.reportCardEditing`; Editar do inspector desligado com o editor da spec aberto, e Editar Spec desligado com um card aberto no inspector | `AppState.swift`, `ReportCardInspector.swift`, `ReportToolbar.swift`, `ReportView.swift` |
| RE-08 | Menu Inserir Regra, popover Regras dos Valores, aviso amarelo de regra desconhecida (com sugestão por distância de edição), de `[soma_itens]` dentro de items e de chave `a\|` sem o outro lado; nota do inspector e ajuda atualizadas | `ReportValueRulesViews.swift`, `Models/ReportValueRules.swift`, `docs/ajuda/report.md` |
| RE-14 | Disparos anteriores: as 3 primeiras divergências e "e mais N", o resto no tooltip | `ReportDetailPane.swift` |

## Decisões tomadas (as recomendações do designer)

- **D1:** o formulário do inspector continua, com RE-02, RE-05 e RE-07.
- **D2:** a nova ordem de colunas foi aplicada, com personalização guardada.
- **D3:** a linha com chave e valor vazios sai ao gravar e não conta como erro.
- **D4:** o editor de JSON usa `CodeEditorView`, com entrada literal e sem aspas inteligentes.
- **D5:** o recorte padrão segue uma regra fixa: Divergentes com mais de 12 linhas e status divergente.

Um desvio do RE-02: no inspector, o Salvar fica ligado. Com erro, ele mostra
todos os campos marcados e "N campos para corrigir" em vez de gravar. Um botão
desligado não deixaria o ⌘S revelar os erros.

## Achado durante a rodada

Uma view com `@Environment(ThemeManager.self)` dentro de célula de `Table`
derrubava o app ao encolher a janela, na Tabela do editor de spec. O `.dsFieldIssue(_:theme:)`
recebe o tema explícito para uso em célula de tabela.

## Fica para a próxima (P2 e o que os prints mostraram fora do escopo)

- **RE-09:** o Bloco sem quebra de linha, com rolagem horizontal.
- **RE-10:** a barra acessória com nomes longos.
- **RE-11:** o inspector "Card do Figma" corta identificadores no meio.
- **RE-12:** a Tabela do editor com `DisclosureTableRow`.
- **RE-13:** desfazer a remoção de linha.
- **RE-15:** a conta da soma no tooltip.
- **RE-16:** trocar paddings literais por tokens nos outros arquivos.
- Problemas A, B e G do agente de prints:
  - a toolbar da janela com subtítulo longo;
  - spec e log cortados na barra do Relatório;
  - a área do Relatório sem margem esquerda na janela pequena.

## Não verificado

- Se o Esc com um campo em foco no editor de spec termina só o campo. O Fechar
  tem `.cancelAction`, e com alteração o Fechar pede confirmação antes de
  descartar.
- O efeito de `.autocorrectionDisabled()` no macOS.
- O VoiceOver de verdade. Os rótulos foram escritos, mas não foram ouvidos.
- Cenas do editor na janela pequena com a tela bloqueada: o servidor de janelas
  devolve PNG em branco. As cenas 33–44 e 57–64 precisam ser geradas com a tela
  desbloqueada.

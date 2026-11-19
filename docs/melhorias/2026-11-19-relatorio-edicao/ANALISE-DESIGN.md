# Relatório: edição, entrada de dados e textos grandes — análise de design

Status: rascunho para implementação · Plataforma: macOS 14+ (vidro do macOS 26) · Superfície: Operate
Sistema: design system do Mo baile (`brain-of-agent/design-systems/mo-baile/`) e a implementação dele no app (`Theme/`, `Views/DesignSystem/`)
Branch lida: `melhoria/2026-11-19-ga4-regras-e-editor` (somente leitura, sem commit)
Rótulos: **Verificado (código)** li no arquivo · **Verificado (print)** vi na captura · **Inferido** deduzido do código ou da captura, sem executar · **Suposição** · **Não verificado**
Independência: avaliação de um modelo da mesma família de quem gerou o código. É opinião de modelo, não teste com pessoas.

**Veredito: RETRABALHAR.** Nota ponderada 3,0 de 5. São 3 P0, 5 P1 e 8 P2.

Brief em uma linha: quem audita o tagueamento (QA de analytics) precisa achar o que diverge num evento com dezenas de itens e corrigir a spec sem abrir o JSON.

---

## 0. Material usado

- **Código** dos arquivos de `apps/MoBaile/Sources/MoBaile/Views/Report/`, `Theme/` e `Views/DesignSystem/`. Também li `Models/ReportModels.swift`, `Engine/JSONValue.swift`, `Engine/EngineSession.swift` e a mudança do motor ainda não commitada em `engine/src/mobaile/services/report/{rules,audit}.py`.
- **Prints de textos grandes** em `docs/design/telas/textos-grandes/antes/`, 12 arquivos em claro e escuro, janela de 1280×800 e pequena de 1070×680:
  - `01`–`04`: resultado com itens;
  - `05`–`08`: painel Validação rolado até os itens;
  - `09`–`12`: aba Disparo.
  Todos são da **tela de resultado**.
- **Não há print do editor de spec** (Quadro e Tabela), do formulário do inspector nem de uma folha de edição. A análise dessas telas vem do código e está marcada como Inferido. Na seção 6 estão as cenas que faltam capturar para conferir os critérios de aceite.
- Catálogo existente: `docs/design/telas/06c-relatorio-divergencia-claro.png` e `06e-relatorio-revisao-importacao-claro.png`. O `12-relatorio-claro.png` e o `14-relatorio-spec-claro.png` citados no pedido não estão no repositório. Eles saem do `WindowSnapshotTests` com `MOBAILE_SNAPSHOT_DIR` (`docs/design/relatorio.md`, seção "Pontos para a próxima revisão").

---

## 1. Resumo

### 1.1 O que está bom

- **Status nunca só por cor.** O `StatusIndicator` usa ícone, cor e texto (`Views/DesignSystem/Indicators.swift:21-37`). Cada linha da grade de validação também tem ícone, e o leitor de tela recebe uma frase inteira: "component: diverge, obtido toggle, esperado button" (`ReportDetailPane.swift:121-145`). Verificado (código).
- **Os componentes do DS são usados de forma coerente.** Aparecem `InlineError`, `EmptyState`, `DetailHeader`, `KeyValueGrid`, `CodeBlock`, `dsCard`, `crossfade` e `AdaptivePair`, além dos tokens de cor do tema e da escala `DSFont`. O contraste dos pares usados passa AA (seção 2.4). Verificado (código).
- **A janela estreita foi pensada.** O resumo usa `ViewThatFits` e `FlowRow` (`ReportView.swift:254-277`), e o filtro vira menu (print `03`). O detalhe vira abas abaixo de 640 pt (`ReportDetailPane.swift:25`, print `03`). A barra acessória tem modo compacto (`ReportToolbar.swift:13-16`). Verificado (print).
- **O nome do log corta no meio no resumo** (`ReportView.swift:317-319`, print `01`: `log_obtido_moto_g55_android15_2026…essao_completa_com_seguro.json`). É o padrão certo para nome de arquivo.
- **Texto útil é selecionável** no detalhe e no cartão da spec (`textSelection(.enabled)`, `ReportDetailPane.swift:67, 138`), como pede a HIG de text views.
- **O editor de spec tem bons fundamentos**:
  - há um modelo de rascunho separado do que está no disco (`ReportSpecDraft.saved`, `ReportModels.swift:425-460`);
  - mostra "Alterado" por card;
  - pede confirmação antes de descartar (`ReportSpecEditorView.swift:43-51`);
  - o Salvar é o botão de destaque, com ⌘S;
  - a observação já quebra linha (`ReportSpecEditorView.swift:305-306`).

### 1.2 O que falha com textos grandes (tela de resultado)

| # | Falha | Evidência | Rótulo |
|---|---|---|---|
| T1 | O painel Validação vira uma lista plana de ~6 linhas por item: com 12 itens são ~70 linhas, e as 3 divergências só aparecem rolando | prints `05`, `06`, `07`; `ReportDetailPane.swift:119` (um `ForEach` só, sem grupo) | Verificado (print) |
| T2 | O nome do parâmetro quebra no meio: `items[0].item_` / `id`, `items[3].item_` / `id\|item_name` | prints `05` e `07`; `ReportDetailPane.swift:124` (`Text(check.field)` sem `lineLimit` nem largura) | Verificado (print) |
| T3 | Os valores mono quebram por caractere (`T-2026-11-19-0` / `00482`, `app:pedido:emp` / `resa:checkout:`), e o "Esperado" do `value` (`soma dos itens: 72.05`) é cortado em 3 linhas | print `01`; `ReportDetailPane.swift:126-135` (três colunas disputando ~300 pt; `lineLimit(3)`) | Verificado (print) |
| T4 | Na aba Disparo, `items` vira um JSON compacto cortado em 2 ou 3 linhas: dá para ver 1,5 item de 12, e as chaves vêm fora de ordem (`quantity` antes de `item_id`) | prints `09` e `11`; `ReportDetailPane.swift:196-197`, `Content.swift:146-152` (`lineLimit(3)`), `JSONValue.swift:78-80` | Verificado (print) |
| T5 | A coluna Divergências da tabela (e também Horário e Disparos) fica fora da área visível em todos os prints. As larguras ideais somam 1.226 pt para uma coluna central de ~750 pt | prints `01`, `03`, `05` e `09` (barra de rolagem horizontal); `ReportView.swift:393-440` | Verificado (print) |
| T6 | Evento e Variação cortam no fim e escondem justamente a parte que distingue uma linha da outra (`interaction_pedido_empresa_simu…`) | print `01`; `ReportView.swift:405-417` (só `lineLimit(1)`) | Verificado (print) |
| T7 | O Bloco quebra as linhas longas sem recuo (`"screen_name":` fica sozinha numa linha), e os ✓ e ✗ se deslocam | prints `01` e `05`; `Content.swift:113-129` | Verificado (print) |
| T8 | Com nomes longos de spec e log, a barra acessória entra no modo compacto. Auditar e Checklist viram dois ícones quase iguais, e o nome do log corta no fim (`log_obtido_moto_g…`) | print `01`; `ReportToolbar.swift:33, 43, 135, 141-143` | Verificado (print) |
| T9 | O inspector "Card do Figma" quebra identificadores no meio da palavra (`checkou` / `t:confirmacao`) e corta o título do card na 3ª linha | print `01`; `Content.swift:146-152` | Verificado (print) |

### 1.3 O que falha na edição (editor de spec e inspector)

| # | Falha | Evidência | Rótulo |
|---|---|---|---|
| E1 | **A Tabela do editor não mostra problema nenhum.** O Salvar fica desabilitado e o tooltip diz "Corrija os cards marcados", mas nada está marcado | `ReportSpecEditorView.swift:388-434` (não lê `problems`), `:101-102`, `:116-119` | Verificado (código) |
| E2 | **O formulário do inspector não valida antes de gravar.** O Salvar só desabilita enquanto grava. O erro do `rpcCard()` vai para `reportError`, no topo da coluna central, longe do formulário | `ReportCardEditor.swift:90-95`; `EngineSession.swift:1761-1765`; `ReportView.swift:22-28` | Verificado (código) |
| E3 | No Quadro, o erro aparece numa lista no rodapé do card com borda vermelha no card inteiro, mas o campo errado não é marcado. "Adicionar Parâmetro" cria uma linha vazia que já conta como erro, antes de a pessoa digitar | `ReportSpecEditorView.swift:314-332`; `ReportCardEditor.swift:169-171`; `ReportModels.swift:382-401` | Verificado (código) |
| E4 | O `items` (JSON) é editado numa linha só de ~150 pt (Quadro) ou ~120 pt (inspector). Um items de 4 campos tem ~110 caracteres (~730 pt em SF Mono 11), e o tooltip mostra "Valor em JSON (lista ou objeto)" em vez do valor | `ReportCardEditor.swift:143, 152-155`; `ReportSpecEditorView.swift:163, 262, 423-430`; `JSONValue.swift:62-68` | Verificado (código); larguras Inferido |
| E5 | A chave tem largura fixa (92 ou 104 pt) e o valor ocupa uma linha só: `app:pedido:empresa:checkout:confirmacao` (39 caracteres) não cabe, e chaves com mais de ~15 caracteres (`firebase_screen_class`) cortam | `ReportCardEditor.swift:143, 149-155`; `ReportSpecEditorView.swift:262, 287` | Inferido |
| E6 | Não existe gestão de foco: adicionar uma linha não leva o foco para ela, e Return não avança da chave para o valor. Esc com um campo focado pode acionar o Fechar (`.cancelAction`) | `ReportCardEditor.swift:169-171`; `ReportSpecEditorView.swift:93`; nenhum `@FocusState` em `Views/Report/` | Verificado (código); Esc Inferido |
| E7 | **Dois lugares editam o mesmo card ao mesmo tempo.** Com o editor de spec aberto, o "Editar" do inspector continua ativo. O inspector grava por `report.card_update` e não atualiza o rascunho do editor, e um Salvar depois no editor pode gravar a versão antiga. Também ficam dois ⌘S na tela | `ReportCardInspector.swift:25-33`; `EngineSession.swift:1758-1792`; `ReportSpecEditorView.swift:99`; `ReportCardEditor.swift:91` | Verificado (código); a sobrescrita é Inferido |
| E8 | A gramática dos valores só existe na memória de quem edita: | | |
| | • a nota do inspector não cita `[data]` nem as regras novas (`[soma_itens]` e chave `a\|b`); | `ReportCardEditor.swift:79` | Verificado (código) |
| | • o editor de spec não mostra regra nenhuma; | | Verificado (código) |
| | • um erro como `[soma_item]` vira comparação literal, sem aviso. | `rules.py:47` (`_TOKEN`) | Verificado (código) |
| E9 | Rótulos para o leitor de tela: | | Verificado (código) |
| | • "Remover " e "Valor de " ficam sem nome quando a chave está vazia; | `ReportCardEditor.swift:155, 159` | |
| | • "Nome do parâmetro" se repete sem dizer a posição; | `:151` | |
| | • o botão de remover (`minus.circle` borderless small, ~16 pt) fica abaixo do `--hit-min` de 20 pt do DS. | `:156-163` | Inferido |

### 1.4 Onde a mudança do motor (3.27.0 e 3.28.0) bate na tela

- **Todos os itens conferidos.** Os campos agora são `items[0].item_id` … `items[N].campo` (`audit.py:143-160`). Isso multiplica as linhas de T1 a T3 e o tamanho do texto de Divergências (T5). `ReportCheck.id` é o próprio `field` (`ReportModels.swift:69`). Hoje é único, mas a grade não deveria depender disso.
- **Chave `item_id|item_name`.** O obtido vem como `item_name=Tee` (`audit.py`, `check_value`), e a barra vertical é lida como símbolo pelo leitor de tela (Inferido).
- **`[soma_itens]`.** O esperado vem como `soma dos itens: 72.05` ou como um motivo longo (`soma dos itens (items[2].price ausente ou não numérico)`). Ele precisa de largura no detalhe e de uma entrada fácil no editor. Fora do nível do evento, a regra falha só na auditoria (`audit.py`, ramo `event_level`).

---

## 2. Critérios usados

### 2.1 Design system do Mo baile

O DS fica em `design-systems/mo-baile/`.

- **Conteúdo** (`readme.md`, CONTENT FUNDAMENTALS):
  - erro diz o que houve e o que fazer;
  - tooltip é uma frase curta com o efeito;
  - termos técnicos ficam em mono e sem tradução;
  - botões no infinitivo, com reticências quando abrem painel.
- **Espaço** (`tokens/spacing.css`, `guidelines/spacing-form.html`, `guidelines/spacing-scale.html`):
  - grade de 4 pt;
  - `--gap-label-control` 6, `--gap-stacked-controls` 6;
  - `--control-height-small` 20;
  - `--hit-min` 20;
  - `--table-row` 24.
- **Tipografia** (`tokens/typography.css`, `guidelines/type-mono.html`):
  - SF Mono para dados técnicos;
  - números tabulares;
  - hierarquia por peso e cor.
- **Componentes:**
  - `components/controls/TextField.prompt.md`: mono sem correção ortográfica; `invalid` com borda de erro, que é `.mb-field.is-invalid` em `components/mb.css:87`;
  - `components/content/DataTable.prompt.md`: ordenar, redimensionar colunas, setas navegam;
  - `EmptyState` e `InlineError` (`mb.css:247`).
- **Estado = ícone + cor + texto** (`readme.md` e `components/indicators/StatusIndicator`).
- **Materiais:** sem vidro no conteúdo (`readme.md`, VISUAL FOUNDATIONS). As folhas e menus propostos usam os do sistema.
- **No app**, os nomes equivalentes são:
  - `DesignMetrics.Spacing` (`s1` 2 … `s10` 32);
  - `DesignMetrics.Radius.field` (7) e `.card` (12);
  - `DesignMetrics.Heights.controlSmall` (20) e `.codeFooter` (26);
  - `DSFont.*`;
  - os tokens do tema (`labelPrimary`/`Secondary`/`Tertiary`, `destructive`, `warning`, `accentText`, `bgField`, `bgContentAlt`, `dangerTint`);
  - componentes `StatusIndicator`, `InlineError`, `EmptyState`, `DetailHeader`, `KeyValueGrid`, `CodeBlock`, `BarIconButton`, `PlainTextButtonStyle` e `AdaptivePair`.

### 2.2 Papéis do brain-of-agent aplicados

Os papéis estão em `plugins/ux-ui-design/agents/`.

**`ui-designer`.** Apliquei:
- o checklist de estados de campo: vazio, preenchido, inválido, texto longo;
- teclado (ordem de tabulação, Enter, Escape);
- conteúdo do erro (o que houve e o que fazer);
- regra de reutilizar antes de criar: só proponho um componente novo no DS, justificado na seção 5;
- toda medida cita um token. Onde não existe token, aparece como "medida de componente";
- nota por tela, adições intencionais e substituições a validar (seção 5).

**`design-evaluator`.** Apliquei o teste de tronco, as notas de 1 a 5 com evidência, a ponderação (2 design + 2 originalidade/consistência + acabamento + funcionalidade) / 6 e a regra de escolher a nota menor quando há dúvida.

| Critério | Nota | Evidência | Rótulo |
|---|---|---|---|
| Qualidade de design (peso 2) | 3 | A hierarquia resumo → tabela → detalhe é clara (print `01`). Com itens, o detalhe perde a tarefa principal: 70 linhas com o mesmo peso e as divergências escondidas (prints `05` e `07`) | Verificado (print) |
| Consistência com a marca (peso 2) | 4 | Usa os tokens e componentes do DS em todo o fluxo, e o status tem três canais. Há drift de espaçamento (seção 2.3) | Verificado (código) |
| Acabamento (peso 1) | 2 | Quebra no meio da palavra (prints `01` e `05`), "soma dos itens" cortado (`01`), coluna Divergências fora da tela (`01` e `03`), JSON cortado (`09` e `11`) | Verificado (print) |
| Funcionalidade (peso 1) | 2 | Validação invisível na Tabela e no inspector, JSON numa linha só, dois editores do mesmo card (E1, E2, E4, E7) | Verificado (código) |

Nota ponderada: (2×3 + 2×4 + 2 + 2) / 6 = **3,0**.

O teste de tronco no print `01` deu **PARTIAL (5 de 6)**:
- **Página, seções, onde estou e como busco:** claros.
- **Opções neste nível:** parcial. Os dois ícones de lista na barra, Auditar e Checklist, não se distinguem.
- **Nome do produto:** não aparece, por decisão do DS (o título é a seção).

**`design-system-auditor`.** Fiz o inventário com `grep` nas 6 views do pedido (Verificado):
- 38 `.padding(n)` com literal;
- 44 `spacing: n` com literal;
- 2 usos de `DesignMetrics.Spacing`;
- 14 `DSFont.mono(11…)` sem token próprio. O DS tem `--text-code` 12, e o 11 virou um token implícito.

O impacto de release das propostas é **minor**: um componente novo compatível (`FieldValidation`) e nada removido nem renomeado.

**`a11y-reviewer` (WCAG 2.2 AA, roteado para app nativo).** Critérios aplicados:

| Critério | Onde |
|---|---|
| 1.3.1 Informações e relações | grupos de itens |
| 1.4.1 Uso de cor | erro com ícone e texto |
| 1.4.3 Contraste mínimo e 1.4.11 Contraste não textual | seção 2.4 |
| 2.1.1 Teclado | |
| 2.4.3 Ordem do foco | |
| 2.5.3 Rótulo no nome | |
| 2.5.8 Tamanho mínimo do alvo | botão remover |
| 3.3.1 Identificação do erro | E1 e E2 |
| 3.3.3 Sugestão de erro | textos de erro e `[soma_item]` |
| 4.1.2 Nome, função, valor | E9 |

Teclado e leitor de tela reais ficam como Não verificado (seção 6).

**`ux-researcher`.** Não se aplica a esta rodada, porque não há notas de usuário. O pedido de testar o recorte "Divergentes" com quem audita fica em Decisões pendentes (D5).

### 2.3 Referências externas (resumo; links na seção 7)

| Referência | Regra aplicada aqui |
|---|---|
| HIG Text fields / Entering data | Tamanho do campo proporcional ao texto esperado. Escolher o momento de validar. Tooltip de expansão no macOS para texto cortado. Oferecer escolhas em vez de digitação. Validar enquanto a pessoa preenche |
| HIG Text views | Texto longo, editável ou com formato especial vai num text view, não num text field |
| HIG Lists and tables / Outline views | Texto curto na linha e o resto no detalhe. Reticência no meio preserva começo e fim. Colunas redimensionáveis. Dado hierárquico vai em outline com disclosure, e a escolha de expandir é lembrada |
| HIG Disclosure controls | Esconder detalhe até ele importar, com rótulo que diz o que está escondido |
| HIG Panels (inspector) | O inspector acompanha a seleção e deve preferir ajuste simples a digitação longa |
| HIG Offering help | Tooltip de até 60–75 caracteres |
| NN/g Data tables | Editar na linha só funciona com tabela estreita. Para edição profunda, painel lateral não-modal em vez de modal. Acordeões abertos poluem. Filtro ativo precisa estar visível |
| NN/g Errors in forms | Erro ao lado do campo, cor mais ícone, não validar antes de a pessoa terminar o campo, resumo no topo não basta sozinho, não reportar erro por tooltip |
| Baymard (inline validation) e Konjević ("reward early, punish late") | Erro aparece ao sair do campo e some na tecla em que o valor fica válido |
| AG Grid (large text editor; start/stop editing) | Editor em janela própria para texto longo. Enter confirma, Esc cancela só a célula, Tab avança |
| Airtable (long text / expand record) | Texto longo é visto e editado num registro expandido, não na célula |
| Postman (Params / Bulk Edit) e VS Code (Edit in settings.json) | Tabela chave-valor para o simples. Para valor complexo (lista ou objeto), um editor de texto próprio a partir do formulário |
| PatternFly Truncate | Corte no começo, no meio ou no fim conforme a parte que distingue, sempre com tooltip do texto inteiro |
| Notion (side peek) | Editar o registro ao lado com a lista à vista: um lugar de edição |

### 2.4 Contrastes calculados (fórmula WCAG, valores reais do tema)

Os valores com alfa foram compostos sobre o fundo.

| Par | Claro | Escuro | Exigido | Resultado |
|---|---|---|---|---|
| `labelTertiary` sobre `bgContent` (cabeçalhos "PARÂMETROS", "Card N") | 4,94:1 | 5,07:1 | 4,5:1 | passa |
| `labelTertiary` sobre `bgContentAlt` (nome do card no Quadro) | 4,83:1 | 4,95:1 | 4,5:1 | passa, com folga pequena |
| `destructive` sobre `bgContent` (texto do erro e borda do campo) | 5,38:1 | 6,27:1 | 4,5:1 (texto) / 3:1 (borda) | passa |
| `destructive` sobre `dangerTint` (`InlineError`) | 4,51:1 | — | 4,5:1 | passa no limite |
| `accentText` sobre `bgContent` (chaves) | 5,71:1 | 7,54:1 | 4,5:1 | passa |
| `warning` sobre `bgContent` (aviso não-bloqueante) | 5,54:1 | — | 4,5:1 | passa |
| `controlBorder` sobre `bgContent` (borda do campo do DS) | 1,34:1 | 1,43:1 | 3:1 (1.4.11) | não passa; os campos atuais usam `.roundedBorder` do sistema, por isso fica só como nota |

No tema claro, `labelSecondary` e `labelTertiary` têm o mesmo valor (`navy(0.62)`, `PraiaLightTheme.swift:17,19`). A hierarquia entre os dois só existe pelo tamanho. Fica como nota para o DS, fora do escopo.

---

## 3. Recomendações priorizadas

| ID | Sev. | Título | Arquivos | Esforço | Risco |
|---|---|---|---|---|---|
| RE-01 | P0 | Validação e Disparo legíveis com dezenas de itens | `ReportDetailPane.swift` | M | baixo |
| RE-02 | P0 | Validação no campo, igual no Quadro, na Tabela e no inspector | `ReportSpecEditorView.swift`, `ReportCardEditor.swift`, novo `DesignSystem/FieldValidation.swift` | M | médio |
| RE-03 | P0 | Valor JSON (`items`) com editor próprio | `ReportCardEditor.swift`, `ReportSpecEditorView.swift`, novo `ReportJSONValueSheet.swift` | M | baixo |
| RE-04 | P1 | Tabela de auditoria: Divergências à vista e resumida | `ReportView.swift` | P | baixo (muda o hábito: D2) |
| RE-05 | P1 | Linhas chave-valor que acompanham o texto | `ReportCardEditor.swift` (`ReportFieldRows`), `ReportSpecEditorView.swift` | M | baixo |
| RE-06 | P1 | Foco, teclado e leitor de tela na edição | `ReportCardEditor.swift`, `ReportSpecEditorView.swift` | P | baixo |
| RE-07 | P1 | Um lugar de edição por vez (inspector × editor de spec) | `ReportCardInspector.swift` (+1 propriedade no `AppState`) | P | baixo |
| RE-08 | P1 | Gramática à mão: Inserir Regra, ajuda e avisos | `ReportCardEditor.swift`, `ReportSpecEditorView.swift`, `docs/ajuda/report.md` | M | baixo |

Ordem sugerida de implementação:
1. RE-02, que cria o `FieldValidation` usado pelo RE-03 e pelo RE-08;
2. RE-05 e RE-06, no mesmo `ReportFieldRows`;
3. RE-03;
4. RE-08;
5. RE-07;
6. RE-01;
7. RE-04.

Ao terminar, rodar `make check`, `make test-swift` e `make update-native` (AGENTS.md). O RE-08 mexe em `docs/ajuda/`, que entra no bundle.

---

### RE-01 (P0) Validação e Disparo legíveis com dezenas de itens

**Problema.** Com a auditoria de todos os itens, o painel Validação é uma grade plana com três colunas de texto disputando ~300 pt. Os nomes `items[i].campo` quebram no meio, os valores quebram por caractere, o esperado da soma é cortado e as divergências (3 de ~70) só aparecem rolando. Na aba Disparo, `items` vira um JSON cortado. É a leitura principal da 3.27.0 e da 3.28.0.

**Evidência:**
- prints `01` (value: "soma dos / itens…" cortado; `T-2026-11-19-0` / `00482`), `05`/`06` (`items[0].item_` / `id`; "Camiseta Básica Masculina Azu…"), `07` (`items[3].item_id|` / `item_name`), `09`/`11` (items "…quan…");
- `ReportDetailPane.swift:106-150`: o Grid não define largura de coluna, `:124` não tem `lineLimit`, e `:129` e `:134` usam `lineLimit(3)`;
- `:63-70`: o cabeçalho ocupa 4 linhas no print `01`;
- `:196-197` com `Content.swift:146-152` (Disparo);
- `JSONValue.swift:78-80`.

**Mudança proposta (SwiftUI, só em `ReportDetailPane.swift`).**

1. **Agrupar os checks por item** com um tipo privado:

   ```swift
   /// "items[3].item_id|item_name" → (item: 3, chave: "item_id|item_name").
   private enum CampoDeItem {
       static func separar(_ campo: String) -> (item: Int, chave: String)? {
           guard let m = campo.wholeMatch(of: /items\[(\d+)\]\.(.+)/), let i = Int(m.1) else { return nil }
           return (i, String(m.2))
       }
   }

   private struct GrupoDeChecks: Identifiable {
       let id: String                 // "evento" ou "items[3]"
       let item: Int?                 // nil: parâmetros do evento
       let checks: [ReportCheck]
       var divergentes: Int { checks.filter { $0.exported && !$0.ok }.count }
       /// O que identifica o item no rótulo: o obtido de item_id ou item_name.
       var identificacao: String? { ... }
   }
   ```

2. **Pôr um recorte acima da grade**, logo abaixo do cabeçalho:
   - um `Picker` segmentado `.controlSize(.small)`, igual ao filtro do resumo (`ReportView.swift:322-337`), com "Todos 70 | Divergentes 3";
   - o padrão é `.divergentes` quando `result.status == .error && result.checks.count > 12`, e `.todos` nos outros casos;
   - quando o recorte fica vazio, mostrar `EmptyState(icon: "checkmark.seal", text: "Nenhuma divergência nesta variação.", actionLabel: "Mostrar Todos", compact: true)`.

3. **Montar os grupos assim:**
   - **Grupo do evento:** sempre aberto e no topo.
   - **Cada item:** um `DisclosureGroup(isExpanded:)`, aberto quando `divergentes > 0` e fechado quando tudo confere. O estado aberto ou fechado fica num `@State var abertos: Set<String>`, iniciado na troca de `result.id` (a HIG de outline pede para lembrar a escolha).
   - **Rótulo do grupo:**
     - `Image(systemName: divergentes > 0 ? "xmark.circle.fill" : "checkmark.circle.fill")` em `theme.destructive` ou `theme.success`;
     - `Text("Item \(i + 1)")` em `DSFont.subheadlineSemibold`;
     - a identificação em `DSFont.mono(11)` `labelSecondary` `.lineLimit(1)` `.truncationMode(.middle)`;
     - `Spacer`;
     - à direita, `Text(divergentes > 0 ? "\(divergentes) de \(n) divergem" : "\(n) OK")` em `DSFont.subheadline.monospacedDigit()` `labelSecondary`.
   - **Botão para abrir tudo:** "Expandir Itens" / "Recolher Itens" (`PlainTextButtonStyle`, `.controlSize(.small)`) na linha do recorte. O DisclosureGroup do SwiftUI não tem ⌥-clique.
   - **Muitos itens:** usar `LazyVStack` dentro do `ScrollView`.

4. **Montar a grade com colunas fixas**, alinhadas entre os grupos:
   - **ícone:** 14 pt;
   - **Parâmetro:**
     - `.frame(width: 136, alignment: .leading)` (medida de componente: cabe `item_id|item_name`, ~112 pt em SF Mono 11);
     - `.lineLimit(1)` e `.truncationMode(.middle)`;
     - `.help(check.field)` com o nome completo;
     - dentro do grupo de item mostra só a chave curta.
   - **Obtido e Esperado:**
     - largura flexível: `.frame(maxWidth: .infinity, alignment: .leading)`;
     - `.lineLimit(4)` e `.help(texto)`;
     - `.textSelection(.enabled)` continua.
   - **Layout por largura**, com o mesmo truque do `AdaptivePair.swift:42-43`:
     - **três colunas** com `.frame(minWidth: 480, idealWidth: 480, maxWidth: .infinity)` dentro de um `ViewThatFits`;
     - **duas linhas** quando o painel é estreito: ícone, Parâmetro e um `VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1)` com o obtido em `labelPrimary` e "esperado {valor}" em `labelSecondary`. O valor ganha ~170 pt em vez de ~85.
   - **`ForEach`:** usar `ForEach(Array(grupo.checks.enumerated()), id: \.offset)`, que não depende de `field` ser único.

5. **Tratar a chave com alternativa** (`item_id|item_name`):
   - `.help("Basta um dos dois: item_id ou item_name")`;
   - quando o obtido tem o formato `alt=valor` e `alt` é uma das alternativas, mostrar `Text(valor)` e, abaixo, `Text("via \(alt)")` em `DSFont.footnote` `labelTertiary`;
   - no rótulo de acessibilidade, trocar `|` por " ou " e incluir o item: "item 4, item_id ou item_name: diverge, obtido ausente, esperado preenchido".

6. **Reduzir o cabeçalho do painel** (`:64-69`) para `.lineLimit(2)`, `.truncationMode(.tail)` e `.help(cabecalho)`. O título do card já está no inspector.

7. **Aba Disparo.** Quando `matched.params["items"]` decodifica como `[[String: JSONValue]]`, mostrar um `DisclosureGroup` por item:
   - o rótulo é "Item N · {item_id ou item_name}";
   - o conteúdo é um `KeyValueGrid`, com as chaves na ordem `item_id`, `item_name`, `price`, `quantity` e depois as outras em ordem alfabética;
   - os demais parâmetros continuam no `KeyValueGrid` atual;
   - se a decodificação falhar, cair no texto atual.

**Critério de aceite** (prints "depois" das mesmas cenas, em `docs/design/telas/textos-grandes/depois/`):
- `01` e `05`:
  - nenhuma chave de parâmetro em duas linhas;
  - grupos "Item 1"…"Item 12" visíveis;
  - recorte "Divergentes 3" ativo, com só os itens com ✕ abertos;
  - a linha `value` mostra "soma dos itens: 72.05" inteiro.
- `07` (janela pequena): o mesmo, e o valor no layout de duas linhas sem quebra no meio da palavra para valores de até 25 caracteres.
- `09` e `11`: Disparo com "Item 1" aberto mostrando `item_id`, `item_name`, `price` e `quantity` em linhas separadas, sem JSON cortado.
- VoiceOver anuncia "Item 4, 1 de 6 divergem, expandido".

---

### RE-02 (P0) Validação no campo, igual no Quadro, na Tabela e no inspector

**Problema:**
- a validação existe (`ReportCardDraft.problems`), mas só aparece no Quadro, e longe do campo;
- a Tabela não mostra nada;
- o inspector deixa gravar e mostra o erro no topo de outra coluna;
- o Quadro acusa linha vazia antes de a pessoa digitar;
- os textos ("Parâmetros: parâmetro sem nome") não dizem o que fazer.

**Evidência:** E1, E2 e E3 da seção 1.3; `ReportModels.swift:382-401`; CONTENT FUNDAMENTALS do DS.

**Mudança proposta.**

1. **Componente pequeno novo** em `Views/DesignSystem/FieldValidation.swift`. É o equivalente SwiftUI de `.mb-field.is-invalid` (`mb.css:87`) e do `InlineError`, aplicado ao campo:

   ```swift
   /// Problema de um campo: bloqueia a gravação (erro) ou só alerta (aviso).
   struct FieldIssue: Equatable {
       let message: String
       var blocking: Bool = true
   }

   private struct DSFieldIssueModifier: ViewModifier {
       @Environment(ThemeManager.self) private var themeManager
       let issue: FieldIssue?

       func body(content: Content) -> some View {
           let theme = themeManager.current
           content
               .overlay {
                   if let issue {
                       RoundedRectangle(cornerRadius: DesignMetrics.Radius.field)
                           .strokeBorder(issue.blocking ? theme.destructive : theme.warning, lineWidth: 1)
                           .allowsHitTesting(false)
                   }
               }
               // Não usar accessibilityValue: num TextField ele substituiria o texto digitado.
               .accessibilityHint(issue?.message ?? "")
               .onChange(of: issue?.message) { _, nova in
                   if let nova { AccessibilityNotification.Announcement(nova).post() }   // macOS 14
               }
       }
   }

   extension View {
       func dsFieldIssue(_ issue: FieldIssue?) -> some View { modifier(DSFieldIssueModifier(issue: issue)) }
   }

   /// Frase sob o campo: ícone e texto, nunca só cor.
   struct FieldMessage: View {
       @Environment(ThemeManager.self) private var themeManager
       let issue: FieldIssue
       var body: some View {
           let theme = themeManager.current
           Label {
               Text(issue.message).fixedSize(horizontal: false, vertical: true)
           } icon: {
               Image(systemName: issue.blocking ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
           }
           .font(DSFont.subheadline)
           .foregroundStyle(issue.blocking ? theme.destructive : theme.warning)
           .accessibilityElement(children: .combine)
       }
   }
   ```

2. **Problema por campo, e não só por card.** Criar uma extensão em `ReportCardEditor.swift`, `ReportCardDraft.issues() -> [UUID: FieldIssue]`, com as mesmas regras de `problems` mais o evento vazio. O `problems` passa a derivar dela, ou ganha um teste unitário que garanta que as duas listas batem. Textos novos:

   | Hoje | Proposta |
   |---|---|
   | Evento vazio | Informe o evento (ex.: purchase). |
   | Parâmetros: parâmetro sem nome | Dê um nome ao parâmetro ou remova a linha. |
   | Variação 2: detail repetido | detail já aparece nesta variação. Renomeie ou remova uma das linhas. |
   | Parâmetros: items não é JSON válido | items não é um JSON válido. Abra Editar JSON… para ver onde. |

3. **Momento de mostrar o erro** ("reward early, punish late"):
   - `@State private var tocados: Set<UUID>`. Um campo entra no conjunto quando perde o foco (alimentado pelo `FocusState` do RE-06) ou quando a pessoa tenta gravar;
   - só campos tocados mostram borda e frase;
   - depois que o erro aparece, o campo revalida a cada tecla e o erro some assim que o valor fica válido;
   - uma linha com chave e valor vazios não conta como problema e é descartada ao gravar (D3).

4. **Onde aparece em cada tela:**
   - **Quadro e inspector:** `.dsFieldIssue(issue)` nos dois campos da linha e `FieldMessage(issue)` logo abaixo da linha, recuado `DesignMetrics.Spacing.s2`. A lista do rodapé do card (`ReportSpecEditorView.swift:314-325`) sai, porque todo problema tem campo. A borda vermelha do card (`:329-332`) continua como sinal de varredura.
   - **Tabela (`ReportSpecTable`):**
     - uma primeira coluna `.width(22)` com `exclamationmark.circle.fill` em `theme.destructive` para problema, ou `pencil` em `labelSecondary` para linha de card alterado;
     - essa coluna tem `.help(mensagem)` e `accessibilityLabel("Problema: \(mensagem)")` ou "Alterado";
     - `.dsFieldIssue` nos TextFields Parâmetro e Valor;
     - seleção de linha;
     - sob a tabela, uma barra de 26 pt (`DesignMetrics.Heights.codeFooter`, separador no topo) com o `FieldMessage` da linha selecionada e o botão "Próximo Problema" (⌘'), porque erro não pode ficar só em tooltip (NN/g).
   - **Cabeçalho do editor** (`ReportSpecEditorView.swift:59-107`): quando um card alterado tem problema, mostrar, antes do Salvar, `Button { irParaPrimeiroProblema() } label: { StatusIndicator(status: .error, label: "2 para corrigir", mono: false) }.buttonStyle(.plain)`.
     - No Quadro, ele rola com `ScrollViewReader` e `.id(item.cardIndex)` em cada `ReportSpecCardBox`.
     - Na Tabela, ele seleciona a linha.
     - O Salvar continua desabilitado (a HIG de entering data pede ação disponível só com o dado exigido), e o `ajudaSalvar` passa a dizer "Corrija os 2 campos marcados antes de gravar".
   - **Inspector (`ReportCardEditor`):**
     - Salvar `.disabled(gravando || !draft.problems.isEmpty)`;
     - ⌘S com problema marca todos os campos como tocados;
     - erro do motor ao gravar com o formulário aberto (`appState.reportError != nil`) aparece como `InlineError` acima do rodapé do inspector, e não só no topo da coluna central.

**Critério de aceite.** Cenas novas, capturadas pelo `WindowSnapshotTests`:
- `14-editor-tabela-problemas-claro.png`: Tabela com um parâmetro sem nome e um JSON inválido. As duas linhas têm ícone vermelho e campos com borda vermelha, a barra inferior mostra a frase da linha selecionada e o cabeçalho mostra "2 para corrigir" ao lado do Salvar desabilitado.
- `13-editor-quadro-claro.png`, logo após "Adicionar Parâmetro": card sem borda vermelha, foco no campo novo e nenhuma frase de erro.
- `15-inspector-editar-card-claro.png` com o evento apagado: o campo Evento tem borda vermelha e "Informe o evento (ex.: purchase)." abaixo, o Salvar fica desabilitado e não aparece nada no topo da coluna central.

---

### RE-03 (P0) Valor JSON (`items`) com editor próprio

**Problema:**
- o `items` é a regra central do e-commerce na 3.28.0 e é editado como JSON compacto numa linha estreita;
- a pessoa vê ~20 de ~110 caracteres;
- o tooltip não mostra o valor;
- as chaves são reordenadas (`.sortedKeys`);
- digitar JSON num TextField pode sofrer substituição de aspas do macOS (Suposição: conferir; o app já desliga isso no editor de código).

**Evidência:**
- E4;
- `ReportCardEditor.swift:152-155` e `ReportSpecEditorView.swift:423-430`, com tooltip fixo;
- `JSONValue.swift:62-68`;
- `CodeTextView.swift:462-480`, `configurarEntradaLiteral()`, que desliga aspas inteligentes, correção e substituição.

**Mudança proposta.**

1. **Trocar o TextField de valor JSON por um botão-resumo** nas três telas: `ReportFieldRows` e a coluna Valor da Tabela.

   ```swift
   if field.isJSON {
       Button { editandoJSON = field.id } label: {
           HStack(spacing: DesignMetrics.Spacing.s2) {
               Image(systemName: "curlybraces").foregroundStyle(theme.labelSecondary).accessibilityHidden(true)
               Text(ResumoJSON(field.value).texto)   // "lista · 2 itens · item_id|item_name, price, quantity"
                   .font(DSFont.mono(11)).lineLimit(2).truncationMode(.tail)
               Spacer(minLength: 0)
           }
           .padding(.horizontal, DesignMetrics.Spacing.s3)
           .frame(minHeight: DesignMetrics.Heights.controlSmall)
           .background(theme.bgField, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
           .contentShape(Rectangle())
       }
       .buttonStyle(.plain)
       .dsFieldIssue(issues[field.id])
       .help("Editar o JSON de \(nome)")
       .accessibilityLabel("Valor JSON de \(nome)")
       .accessibilityValue(ResumoJSON(field.value).texto)
       .sheet(isPresented: ...) { ReportJSONValueSheet(chave: field.key, valor: $field.value) }
   }
   ```

   `ResumoJSON` decodifica `JSONValue`:
   - lista: "lista · N itens · " mais as chaves do primeiro objeto;
   - objeto: "objeto · N campos";
   - inválido: "JSON inválido", em `theme.destructive`.

2. **Folha `ReportJSONValueSheet`**, arquivo novo em `Views/Report/`:
   - **Topo:** "Editar JSON de items" (`DSFont.headline`) e "card 3 · purchase" (`DSFont.subheadline` `labelSecondary`).
   - **Corpo:** `CodeEditorView(text: $rascunho, accessibilityLabel: "JSON de items", python: false)`, que já tem entrada literal e desfazer (`Views/Workspace/CodeEditorView.swift:6-28`). Ao abrir, o JSON vem formatado (`JSONEncoder` com `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`).
   - **Rodapé à esquerda:** status ao vivo. Válido mostra `StatusIndicator(status: .ok, label: "JSON válido · 2 itens", mono: false)`. Inválido mostra `InlineError(title: "JSON inválido.", text: <mensagem do decoder, que traz linha e coluna>)`.
   - **Rodapé à direita:** `Cancelar` (`.keyboardShortcut(.cancelAction)`) e `Aplicar` (`.keyboardShortcut(.return, modifiers: .command)`, `.buttonStyle(.borderedProminent)`, `.disabled(!valido)`). Aplicar grava de volta em forma compacta (`jsonText`), e o modelo e o RPC ficam iguais.
   - **Nota curta abaixo do editor**, em `DSFont.footnote` `labelTertiary`: "O último item da lista vale para os itens a mais do evento. item_id|item_name: basta um dos dois. [soma_itens] não vale dentro de items."
   - **Tamanho:** `.frame(minWidth: 480, idealWidth: 560, minHeight: 300, idealHeight: 380)`.
   - **Por que folha e não popover:** o popover fecha com um clique fora. Na AG Grid isso grava; aqui gravaria JSON inválido ou perderia o rascunho sem aviso.

**Critério de aceite:**
- Cena `16-editor-json-items-claro.png`: a folha abre com um items de 2 objetos formatado em ~12 linhas, rodapé "JSON válido · 2 itens" e Aplicar habilitado.
- Com uma vírgula apagada (mesma cena, variante "-erro"): o rodapé mostra o erro com linha e coluna, e Aplicar fica desabilitado.
- Na cena `13`, a linha `items` do Quadro mostra "lista · 2 itens · item_id|item_name, price, quantity" em no máximo 2 linhas.
- Teste manual: com Ajustes do Sistema › Teclado › Texto › aspas inteligentes ligado, digitar `"` na folha continua dando `"`.

---

### RE-04 (P1) Tabela de auditoria: Divergências à vista e resumida

**Problema:**
- a coluna que diz o que fazer, Divergências, nunca aparece sem rolagem horizontal;
- com itens, o texto dela vira uma frase enorme numa linha só, e o tooltip repete a frase inteira;
- Evento e Variação cortam na parte que distingue as linhas.

**Evidência:**
- T5 e T6 (prints `01`, `03`, `05` e `09`);
- `ReportView.swift:393-440`, onde a soma das ideais é 1.226 pt;
- `:419-426`;
- texto montado em `engine/.../documents.py:37-45`.

**Mudança proposta** (`ReportView.swift`, tabela `resultados`):

1. **Resumo na célula**, com uma extensão no mesmo arquivo:

   ```swift
   extension ReportResult {
       /// "value · items: 3 itens · +2 anteriores": o que diverge, curto.
       var divergenceSummary: String {
           if status == .missing { return "Não disparado no log" }
           if status == .ok { return "" }
           let falhas = checks.filter { $0.exported && !$0.ok }
           var nomes: [String] = []
           var itens = Set<Int>()
           for f in falhas {
               if let (i, _) = CampoDeItem.separar(f.field) { itens.insert(i) } else { nomes.append(f.field) }
           }
           if !itens.isEmpty { nomes.append(itens.count == 1 ? "items: 1 item" : "items: \(itens.count) itens") }
           if olderDivergent > 0 { nomes.append("+\(olderDivergent) anteriores") }
           return nomes.joined(separator: " · ")
       }
   }
   ```

   O `CampoDeItem` do RE-01 passa a ser `fileprivate` num arquivo comum de `Views/Report/`.
   - Ordenar a coluna por `failedChecks` (`ReportModels.swift:114`), e não pelo texto.
   - O tooltip mostra as 4 primeiras divergências, uma por linha, e "e mais N no painel Validação".
2. **Ordem e larguras** para caber em ~750 pt (1280 menos a barra lateral e o inspector):

   | Coluna | min / ideal | Detalhes |
   |---|---|---|
   | Status | 88 / 96 | |
   | Evento | 110 / 150 | `.truncationMode(.middle)` |
   | Divergências | 140 / 200 | sem máximo; é a coluna que cresce |
   | Variação | 100 / 140 | `.truncationMode(.middle)` |
   | Seção | 70 / 84 | |
   | Fluxo | 60 / 90 | |
   | Horário | — | `.defaultVisibility(.hidden)` |
   | Disparos | — | `.defaultVisibility(.hidden)` |

   - Com Evento e Divergências colados (a NN/g pede pontos de interesse perto), a janela pequena (`03`) também mostra Divergências.
   - Horário e Disparos continuam no cabeçalho do painel Validação ("log 14:41:22.907 · 2 disparo(s)").
   - Dar um `.customizationID` a cada coluna e passar `columnCustomization: $colunas` ao `Table` (macOS 14), para a pessoa reexibir, reordenar e redimensionar.
   - Persistir com `@SceneStorage`, como no exemplo da Apple. Se o tipo não for aceito direto, codificar em JSON num `@AppStorage` de texto (Inferido: conferir).
   - Aplicar o mesmo `.truncationMode(.middle)` na tabela "Fora da Spec" (Evento, Tela, Detail; `:475-496`).

**Critério de aceite:**
- Print "depois" da cena `01`: a coluna Divergências fica visível sem rolagem horizontal, a linha `purchase` mostra "value · items: 3 itens" e não há barra de rolagem horizontal na tabela.
- Cena `03` (1070×680): Divergências visível, inteira ou cortada pelo fim do texto, mas na área visível.
- Evento longo aparece como `interaction_pedido…empresa_simulacao`.

---

### RE-05 (P1) Linhas chave-valor que acompanham o texto

**Problema:**
- a chave tem largura fixa e o valor ocupa uma linha só, em card de 300 pt e no inspector de 260 a 380 pt;
- valores reais de 30 a 40 caracteres somem;
- chaves longas cortam;
- o botão de remover é pequeno;
- campos mono ficam com a correção automática do sistema.

**Evidência:** E5 e E9; `ReportCardEditor.swift:139-178`; `ReportSpecEditorView.swift:244-252, 262, 287, 427`; `components/controls/TextField.jsx` do DS, que desliga `spellCheck` quando o campo é `mono`.

**Mudança proposta** (`ReportFieldRows` em `ReportCardEditor.swift`, usado também no Quadro):

1. **Largura da chave pelo conteúdo** (medida de componente):

   ```swift
   /// SF Mono 11 avança ~6,6 pt por caractere; +16 do recuo do campo arredondado.
   private var larguraChave: CGFloat {
       let maior = fields.map { $0.key.count }.max() ?? 0
       return min(max(CGFloat(maior) * 6.6 + 16, 72), 168)
   }
   ```

   O parâmetro `keyWidth` sai.
2. **Layout adaptativo**, com o mesmo truque de `idealWidth` do `AdaptivePair.swift:42-43`:

   ```swift
   ViewThatFits(in: .horizontal) {
       linhas(empilhado: false)   // lado a lado só se o valor ganhar >= 180 pt (~25 caracteres)
           .frame(minWidth: larguraChave + 180 + 48, idealWidth: larguraChave + 180 + 48, maxWidth: .infinity)
       linhas(empilhado: true)
   }
   ```

   - **Lado a lado:** chave com `.frame(width: larguraChave)`; valor com `TextField("Valor", text: $field.value, axis: .vertical).lineLimit(1...4)`, que quebra em vez de cortar.
   - **Empilhado** (inspector e card estreito):
     - chave na largura toda, com o remover à direita;
     - valor embaixo com `.padding(.leading, DesignMetrics.Spacing.s5)` e `.lineLimit(1...6)`;
     - separador de 1 pt (`DesignMetrics.hairline`, `theme.separator`) entre pares;
     - espaçamento vertical `DesignMetrics.Spacing.s3` (`--gap-stacked-controls`).
3. **`.autocorrectionDisabled()`** na chave, no valor e no Evento (`ReportSpecEditorView.swift:247`, `ReportCardEditor.swift:21`). O efeito no macOS é Inferido, e é preciso conferir.
4. **Valor sem quebra de linha:** remover `\n` no `.onChange(of: field.value)`. O motor compara o texto exato, e ⌥↩ num campo vertical insere quebra (Inferido).
5. **Remover:** `BarIconButton(icon: "minus.circle", label: "Remover \(nome)")` (`Bars.swift:104-121`, alvo de 24×22, `.help` e rótulo incluídos). Aplicar também em "Remover Variação" (`ReportCardEditor.swift:38-45`, `ReportSpecEditorView.swift:278-285`).
6. **Adicionar:** `.buttonStyle(PlainTextButtonStyle(theme: theme))` com `.controlSize(.small)` (`Bars.swift:155-185`), igual a "Copiar Tudo".
7. **Título do Quadro** (`ReportSpecEditorView.swift:244`): `axis: .vertical` com `.lineLimit(1...2)`.
8. **Tabela do editor** (as linhas não crescem): valor com `.truncationMode(.middle)` e tooltip de expansão `.help(valor.count > 25 ? valor : "")` no lugar do `""` atual (`:427`).
9. **Rótulo do inspector:** espaço até o campo de 6 pt (`DesignMetrics.Spacing.s3`, `--gap-label-control`), em vez de 4 (`ReportCardEditor.swift:108`).

**Critério de aceite:**
- Cena `13` com um card que tem `screen_name = app:pedido:empresa:checkout:confirmacao` e a chave `firebase_screen_class`: valor inteiro (quebrado em até 4 linhas) e chave inteira.
- Cena `15` (inspector com 280 pt): pares empilhados e valor na largura toda.
- O botão de remover mede pelo menos 24×22 pt no Accessibility Inspector.

---

### RE-06 (P1) Foco, teclado e leitor de tela na edição

**Problema:**
- adicionar uma linha não leva o foco para ela;
- Return não avança da chave para o valor;
- Esc pode fechar o editor inteiro;
- os rótulos para o leitor de tela ficam vazios ou repetidos;
- a `|` é lida como símbolo.

**Evidência:** E6 e E9; nenhum `@FocusState` nas views do Relatório.

**Mudança proposta** (`ReportFieldRows`):

```swift
private enum Foco: Hashable { case chave(UUID), valor(UUID) }
@FocusState private var foco: Foco?

TextField("Parâmetro", text: $field.key)
    .focused($foco, equals: .chave(field.id))
    .onSubmit { foco = .valor(field.id) }
TextField("Valor", text: $field.value, axis: .vertical)
    .focused($foco, equals: .valor(field.id))
    .onSubmit { foco = proximo(depois: field.id).map(Foco.chave) }

Button {
    let novo = ReportCardDraft.Field(key: "", value: "")
    fields.append(novo)
    foco = .chave(novo.id)
} label: { Label(addLabel, systemImage: "plus") }
```

1. **Marcar tocado:** `.onChange(of: foco) { antigo, _ in marcarTocado(antigo) }` alimenta o "tocados" do RE-02.
2. **Esc com campo em foco:** `.onExitCommand { foco = nil }` no contêiner das linhas termina a edição sem fechar o editor. Se não tiver precedência sobre o `.keyboardShortcut(.cancelAction)` do Fechar (`ReportSpecEditorView.swift:93`), tirar o atalho do Fechar enquanto `foco != nil`. Esse estado precisa subir para o editor por um `@FocusState` próprio ou por uma `PreferenceKey`. Não verificado.
3. **Ordem do Tab:** chave → valor → Inserir Regra (RE-08) → remover → próxima chave. É a ordem natural da `HStack`; conferir.
4. **Rótulos:**
   - "Nome do parâmetro \(i + 1) de \(n)";
   - "Valor de \(nome)";
   - "Remover \(nome)";
   - com `nome = key.isEmpty ? "parâmetro \(i + 1) sem nome" : key.replacingOccurrences(of: "|", with: " ou ")`.
   - Na Tabela, acrescentar o card: "Valor de screen_name, card 3" (`ReportSpecEditorView.swift:419, 428`).
5. **Um só ⌘S na tela** por vez (RE-07).

**Critério de aceite:**
- Clicar em "Adicionar Parâmetro" deixa o anel de foco (`focusRing`) no campo novo. Capturar um print logo depois do clique.
- Return na chave leva o foco ao valor.
- Esc com um campo focado no editor de spec deixa o editor aberto.
- No rotor do VoiceOver, os campos aparecem como "Nome do parâmetro 3 de 5".

---

### RE-07 (P1) Um lugar de edição por vez

**Problema:**
- o inspector e o editor de spec editam o mesmo card ao mesmo tempo, sem sincronizar, com dois ⌘S;
- a HIG pede inspector com ajuste simples, e a NN/g recomenda um painel de edição ao lado da lista. O editor de spec já é esse lugar.

**Evidência:** E7; `ReportCardInspector.swift:25-33`; `EngineSession.swift:1758-1792`, onde `saveReportCard` não toca em `reportSpecEditor`.

**Mudança proposta:**

1. **Inspector com editor de spec aberto.** Em `ReportCardInspector.swift:26-33`:

   ```swift
   .disabled(appState.reportOperation != nil || appState.reportSpecEditor != nil)
   .help(appState.reportSpecEditor != nil
         ? "O editor da spec está aberto: edite o card \(result.cardIndex + 1) por lá"
         : "Corrige os textos do card na spec, sem abrir o JSON")
   ```

2. **Editor de spec com o formulário do inspector aberto.** Criar `var reportCardEditing: Int?` no `AppState`, com 1 linha fora de `Views/Report/`. O inspector põe o valor ao abrir o rascunho e tira ao fechar.
   - "Editar Spec" fica desabilitado enquanto ele está preenchido (`ReportToolbar.swift:79`, `ReportView.swift:168`), com o tooltip "Grave ou cancele a edição do card no inspector".
3. **Erro de gravação perto do formulário:** é o último ponto do RE-02.
4. **D1 (pendente):** trocar o formulário do inspector por "Editar no Editor da Spec", que abre o editor rolado até o card e com ele destacado.

**Critério de aceite:**
- Print com o editor de spec aberto e o inspector visível: o "Editar" do inspector aparece desabilitado e o tooltip explica o motivo.
- Não existe estado de tela com dois botões Salvar.

---

### RE-08 (P1) Gramática à mão: Inserir Regra, ajuda e avisos

**Problema.** As regras dos valores não aparecem onde se edita:
- a nota do inspector está incompleta;
- o editor de spec não mostra regra nenhuma;
- um erro de digitação numa regra não é regra e vira comparação literal, sem aviso;
- `[soma_itens]` dentro de items só falha na auditoria.

A HIG de entering data pede para oferecer escolhas em vez de exigir digitação.

**Evidência:** E8; `ReportCardEditor.swift:79`; `rules.py:6-25, 47`; `audit.py` (`check_value`, ramo `event_level`).

**Mudança proposta.**

1. **Menu "Inserir Regra"** por linha de valor, entre o valor e o remover:

   ```swift
   Menu {
       Button("Qualquer Valor  [preenchido]") { field.value = "[preenchido]" }
       Button("Número  [numero]") { field.value = "[numero]" }
       Button("Data dd/mm/aaaa  [data]") { field.value = "[data]" }
       Button("Um dos Valores  [a|b]") { field.value = "[opção1|opção2]" }
       Button("Expressão Regular  re:") { field.value = "re:" + field.value }
       Button("Chave do Fluxo  {fluxo}") { field.value += "{fluxo}" }
       Divider()
       Button("Soma de price × quantity  [soma_itens]") { field.value = "[soma_itens]" }
           .disabled(dentroDeItems)
   } label: {
       Image(systemName: "curlybraces.square")
   }
   .menuStyle(.borderlessButton)
   .menuIndicator(.hidden)
   .fixedSize()
   .help("Inserir regra no valor")
   .accessibilityLabel("Inserir regra no valor de \(nome)")
   ```

   No macOS 14 o SwiftUI não dá a posição do cursor no TextField (a seleção de texto só chegou no macOS 15). Por isso as regras de valor inteiro substituem o valor, `re:` vai no começo e `{fluxo}` vai no fim. Depois de inserir, o foco vai para o valor (RE-06).

2. **Avisos que não bloqueiam a gravação** (`FieldIssue(blocking: false)`, `theme.warning`):
   - **regra desconhecida:** `[palavra]` sem `|` que não é regra conhecida. Mensagem: "[soma_item] não é uma regra e vai ser comparado como texto. Quis dizer [soma_itens]?". A sugestão vem por distância de edição de no máximo 2 contra `[preenchido]`, `[numero]`, `[data]` e `[soma_itens]`;
   - **`[soma_itens]` dentro do JSON de items:** "[soma_itens] só vale nos parâmetros do evento, não dentro de items.";
   - **alternativa com um lado vazio:** chave como `item_id|`. Mensagem: "Falta a outra chave depois da barra (ex.: item_id|item_name).".
3. **Ajuda à vista:**
   - um `BarIconButton(icon: "questionmark.circle", label: "Regras dos Valores")` no cabeçalho do editor de spec e no do inspector;
   - ele abre um popover de ~360 pt com a tabela regra → exemplo → o que confere, escrita a partir do docstring de `rules.py:6-25` com a linguagem do usuário (inclui `[data]`, chave `a|b` e `[soma_itens]`);
   - a nota de `ReportCardEditor.swift:79` passa a ser "Regras: [preenchido], [numero], [data], [a|b], re:…, {fluxo}, [soma_itens]; chave a|b aceita uma das duas.";
   - a mesma tabela entra em `docs/ajuda/report.md`, numa seção "Regras dos valores". Esse arquivo vai no bundle, então pede `make update-native`.

**Critério de aceite:**
- Cena `13` com o menu aberto: as 7 regras aparecem, com "[soma_itens]" desabilitado dentro do editor de items.
- Um valor `[soma_item]` mostra borda e frase amarelas com a sugestão, e o Salvar continua habilitado.
- O popover "Regras dos Valores" lista `[data]` e `[soma_itens]`.

---

### Recomendações P2 (polimento, próxima rodada)

| ID | Problema e evidência | Mudança |
|---|---|---|
| RE-09 | O Bloco quebra linhas sem recuo e desloca os ✓ e ✗ (prints `01` e `05`; `Content.swift:113-129`) | Acrescentar `wraps: Bool = true` ao `CodeBlock`. No Bloco do Relatório, usar `wraps: false` com `ScrollView([.horizontal, .vertical])` e o texto em `.fixedSize(horizontal: true, vertical: false)` |
| RE-10 | Barra acessória: com nomes longos, Auditar e Checklist viram dois ícones quase iguais, e o nome do log corta no fim (print `01`; `ReportToolbar.swift:33, 43, 141-143`) | O botão Auditar, que é a ação principal, mantém o texto. Os menus de spec e log encolhem primeiro (`.layoutPriority`). `encurtar` corta no meio, mantendo o começo e os ~12 últimos caracteres |
| RE-11 | O inspector "Card do Figma" quebra identificadores no meio da palavra e corta o título do card (print `01`; `Content.swift:146-152`) | Linha `card`: `lineLimit(nil)`. Identificadores (`variação`, `evento`): `.lineLimit(2)` com `.truncationMode(.middle)` e `.help` |
| RE-12 | A Tabela do editor repete Card e Evento em toda linha (`ReportSpecEditorView.swift:391-406`) | `Table(of:)` com `DisclosureTableRow` (macOS 14): a linha do card mostra título, evento e situação, e os parâmetros ficam dentro dela (HIG de outline views) |
| RE-13 | Remover linha ou variação não tem volta (`ReportCardEditor.swift:39, 157`; `ReportSpecEditorView.swift:279`) | Registrar o desfazer no `@Environment(\.undoManager)`, para ⌘Z devolver a linha na mesma posição |
| RE-14 | A observação de disparos anteriores junta todas as divergências antigas num parágrafo, que com itens pode ter dezenas (`ReportDetailPane.swift:157-160`) | Mostrar no máximo 3 e "e mais N", com o resto no `.help` |
| RE-15 | A soma dos itens mostra só o total esperado (print `01`) | Tooltip no Esperado com a conta feita a partir do Disparo: `3 × 10.01 + 2 × 21.01 = 72.05` |
| RE-16 | Drift do DS: 38 `.padding(n)` e 44 `spacing: n` literais contra 2 usos de `DesignMetrics.Spacing`; `DSFont.mono(11)` repetido sem token | Ao tocar nos arquivos acima, trocar por `DesignMetrics.Spacing.s2` (4), `.s3` (6), `.s4` (8), `.s5` (12) e `.s6` (14). Propor `DSFont.monoSmall` (= `mono(11)`) com nota no DS (minor) |

---

## 4. Decisões pendentes do humano

| ID | Pergunta | Opções e impacto | Recomendação |
|---|---|---|---|
| D1 | O inspector continua editando o card? | (a) Mantém o formulário com RE-02, RE-05 e RE-07: duas telas de edição com o mesmo componente. (b) Troca por "Editar no Editor da Spec": um só lugar de edição e menos código | (a) nesta rodada; (b) na próxima, se ninguém sentir falta |
| D2 | Ordem e colunas visíveis da tabela de auditoria | Evento e Divergências colados, com Horário e Disparos ocultos por padrão: muda o hábito de quem já usa. A personalização deixa cada pessoa voltar ao que era | Aplicar, com a personalização persistida |
| D3 | Linha com chave e valor vazios é descartada ao gravar? | Sim: mesmo comportamento de Postman e Excel, e "Adicionar" não gera erro. Não: a linha vazia vira erro depois de perder o foco | Sim. Hoje ela já impede a gravação, então nenhuma spec válida muda |
| D4 | Editor de JSON | `CodeEditorView`: entrada literal garantida, mas usa JetBrains Mono 13 e o esquema do editor, fora da escala do DS. `TextEditor`: DS mono 11, sem garantia contra aspas inteligentes | `CodeEditorView`, registrado como substituição a validar |
| D5 | Recorte padrão do painel Validação | "Divergentes" quando há mais de 12 linhas e status divergente, ou lembrar a última escolha (`@AppStorage`) | Regra fixa agora; ouvir 2 ou 3 pessoas do QA antes de lembrar a escolha |

---

## 5. Nota por tela, adições intencionais e substituições a validar

| Tela | O que muda | Por quê |
|---|---|---|
| Resultado · Validação | Grupos por item, recorte Divergentes, colunas fixas, alternativa legível | Dezenas de itens por variação na 3.27.0 e na 3.28.0 |
| Resultado · Disparo | `items` em grupos por item | JSON cortado em 3 linhas |
| Resultado · Tabela | Resumo da divergência, ordem e larguras, corte no meio | A coluna da ação ficava fora da tela |
| Editor · Quadro | Erro no campo, linhas que crescem, foco, Inserir Regra, botão-resumo de JSON | Validação longe do campo, texto cortado |
| Editor · Tabela | Coluna de situação, borda no campo, barra do problema, "N para corrigir" | Nenhuma validação visível |
| Inspector · Editar Card | Layout empilhado, validação antes de gravar, erro no rodapé, bloqueado com editor aberto | 260–380 pt de largura, erro longe, dois editores |
| Folha · Editar JSON | Nova | Valor complexo pede editor próprio (VS Code, Postman, AG Grid) |

**Adições intencionais:**
- `FieldValidation.swift` (`FieldIssue`, `.dsFieldIssue`, `FieldMessage`). O DS da web tem `.mb-field.is-invalid` e `InlineError`, mas o app não tinha o estado inválido de um campo;
- a folha `ReportJSONValueSheet`;
- o menu "Inserir Regra";
- o popover "Regras dos Valores".

**Substituições a validar:**
- a fonte do editor de JSON (JetBrains Mono 13 do `CodeEditorView`);
- o rótulo acima do campo no inspector, em vez do rótulo à direita com dois-pontos do `spacing-form.html`. É um desvio consciente: com 260 pt não cabe rótulo ao lado.

---

## 6. Não verificado e como verificar

- **Editor de spec, inspector em edição e folha de JSON não têm print.** Capturar com o `WindowSnapshotTests`:
  - `13-editor-quadro-claro`: card `purchase` com items, valor longo e chave longa;
  - `14-editor-tabela-problemas-claro`;
  - `15-inspector-editar-card-claro`: inspector com 280 pt;
  - `16-editor-json-items-claro` e a variante `-erro`;
  - as mesmas cenas em escuro.

  Os critérios de aceite das seções RE-02, RE-03, RE-05, RE-07 e RE-08 dependem delas.
- **Esc** com um campo focado: o `onExitCommand` ganha ou não do `.cancelAction`. Testar à mão no editor de spec.
- **`.autocorrectionDisabled()`** no `TextField` do macOS: confirmar que a correção some, com a correção automática ligada em Ajustes do Sistema.
- **Aspas inteligentes** no field editor do `TextField` (hoje) e na folha (`CodeEditorView`).
- **`TableColumnCustomization`** persistido em `@SceneStorage`: confirmar o tipo aceito.
- **Leitor de tela:**
  - roteiro: VoiceOver ligado;
  - percorrer o painel Validação com itens (grupo e linha);
  - no editor, adicionar um parâmetro, sair com a chave vazia e ouvir o anúncio do erro;
  - ouvir o rótulo do botão remover.
- **Alvo do botão remover:** medir no Accessibility Inspector do Xcode.
- **Contraste do tema Alto contraste:** não calculado. Os pares acima são das aparências Claro e Escuro padrão.

---

## 7. Referências

| Fonte | O que tirei |
|---|---|
| Apple HIG, Text fields: https://developer.apple.com/design/human-interface-guidelines/text-fields | Tamanho do campo proporcional ao texto esperado. Validar no momento certo. Quebra de linha ou corte conforme o campo. Tooltip de expansão para texto cortado (RE-03, RE-05) |
| Apple HIG, Entering data: https://developer.apple.com/design/human-interface-guidelines/entering-data | Oferecer escolhas em vez de digitação (RE-08). Validar enquanto a pessoa preenche (RE-02). Botão só disponível com o dado exigido (Salvar). Tooltip de expansão no macOS |
| Apple HIG, Text views: https://developer.apple.com/design/human-interface-guidelines/text-views | Texto longo ou com formato especial vai num text view (folha de JSON). Texto útil selecionável |
| Apple HIG, Lists and tables: https://developer.apple.com/design/human-interface-guidelines/lists-and-tables | Texto curto na linha e detalhe à parte. Reticência no meio. Colunas redimensionáveis e ordenáveis (RE-04) |
| Apple HIG, Outline views: https://developer.apple.com/design/human-interface-guidelines/outline-views | Hierarquia com disclosure, escolha de expandir lembrada, reticência no meio (RE-01, RE-12) |
| Apple HIG, Disclosure controls: https://developer.apple.com/design/human-interface-guidelines/disclosure-controls | Esconder detalhe até importar, com rótulo descritivo (grupos de itens) |
| Apple HIG, Panels: https://developer.apple.com/design/human-interface-guidelines/panels | O inspector acompanha a seleção e deve evitar digitação longa (RE-07, D1) |
| Apple HIG, Offering help: https://developer.apple.com/design/human-interface-guidelines/offering-help | Tooltip curto, de 60 a 75 caracteres (tooltip da coluna Divergências limitado) |
| SwiftUI: `DisclosureTableRow` (macOS 14) https://developer.apple.com/documentation/swiftui/disclosuretablerow · `TableColumnCustomization` (14) https://developer.apple.com/documentation/swiftui/tablecolumncustomization · `defaultVisibility(_:)` (14) https://developer.apple.com/documentation/swiftui/tablecolumncontent/defaultvisibility(_:) · `TextField(_:text:prompt:axis:)` (13) https://developer.apple.com/documentation/swiftui/textfield/init(_:text:prompt:axis:) · `focused(_:equals:)` https://developer.apple.com/documentation/swiftui/view/focused(_:equals:) · `onExitCommand(perform:)` https://developer.apple.com/documentation/swiftui/view/onexitcommand(perform:) · `AccessibilityNotification.Announcement` (14) https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement | Disponibilidade no macOS 14 conferida na documentação de cada API citada nas mudanças |
| NN/g, Data Tables: https://www.nngroup.com/articles/data-tables/ | Editar na linha só em tabela estreita. Painel lateral não-modal para edição profunda. Acordeões abertos poluem. Filtro ativo visível. Pontos de interesse perto (RE-01, RE-04, RE-07) |
| NN/g, Errors in Forms: https://www.nngroup.com/articles/errors-forms-design-guidelines/ | Erro ao lado do campo, cor mais ícone, não validar antes do fim do campo, resumo no topo não basta, erro não vai em tooltip (RE-02) |
| Baymard, Inline Form Validation: https://baymard.com/blog/inline-form-validation | Evitar validação prematura e tirar o erro na tecla em que o valor fica válido (RE-02) |
| Konjević, "Inline validation in forms — designing the experience": https://medium.com/wdstack/inline-validation-in-forms-designing-the-experience-123fb34088ce · Smashing, "A Complete Guide To Live Validation UX": https://www.smashingmagazine.com/2022/09/inline-validation-web-forms-ux/ | Padrão "reward early, punish late" (RE-02) |
| AG Grid, Large Text Editor: https://www.ag-grid.com/javascript-data-grid/provided-cell-editors-large-text/ | Valor longo editado numa janela própria de várias linhas (RE-03) |
| AG Grid, Start/Stop Editing: https://www.ag-grid.com/javascript-data-grid/cell-editing-start-stop/ | Enter confirma, Esc cancela só a edição, Tab avança (RE-06) |
| Airtable, Long text fields: https://support.airtable.com/docs/long-text-fields-in-airtable | Texto longo visto e editado no registro expandido, não na célula (RE-03, RE-05) |
| Postman, Parameters (Bulk Edit): https://learning.postman.com/docs/sending-requests/create-requests/parameters/ | Tabela chave-valor com alternativa em texto para o que é complexo (RE-03) |
| VS Code, Settings: https://code.visualstudio.com/docs/configure/settings | Valor complexo editado em JSON a partir do formulário ("Edit in settings.json") (RE-03) |
| PatternFly, Truncate: https://www.patternfly.org/components/truncate/design-guidelines | Corte no começo, no meio ou no fim conforme o que distingue, sempre com tooltip do texto inteiro (RE-04, RE-10, RE-11) |
| Notion, side peek (release de 20/07/2022): https://www.notion.com/releases/2022-07-20 | Editar o registro ao lado com a lista à vista: um só lugar de edição (RE-07) |
| Design system do Mo baile: `brain-of-agent/design-systems/mo-baile/` (`readme.md`, `tokens/*.css`, `guidelines/spacing-form.html`, `components/mb.css`, `components/controls/TextField.*`, `components/content/{DataTable,EmptyState}.*`) | Tokens, estados de campo, conteúdo de erro e tooltip, alvo mínimo, mono sem correção |
| Papéis: `brain-of-agent/plugins/ux-ui-design/agents/{ui-designer,design-evaluator,design-system-auditor,a11y-reviewer}.md`; `ORCHESTRATOR.md` §3.1 e §6 | Método, pesos das notas, rótulos de evidência, formato dos achados (ID, severidade, `arquivo:linha`, critério de aceite) |

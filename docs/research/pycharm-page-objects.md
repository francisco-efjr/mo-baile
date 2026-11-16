# Page Objects "como o PyCharm": pesquisa, mapa do código e especificação

Status: rascunho para decisão do dono · Data: 2026-11-04 · Branch: `melhoria/2026-11-03-pycharm-desempenho`

Rótulos usados:
- **Verificado**: fonte primária aberta nesta pesquisa, ou código e captura do repositório lidos.
- **Inferido**: dedução a partir de código, da semântica da linguagem ou de captura sem medição.
- **Suposição**: preferência ou dado que ninguém confirmou.
- **Não verificado**: não foi possível abrir a fonte.

Código da JetBrains citado: `JetBrains/intellij-community`, branch `master`, commit `a525578a46af83cc8792190619552bdc2ad47842` (2026-11-04), lido pela API do GitHub. Quando o texto diz "padrão do PyCharm", o valor vem desse código ou da ajuda oficial, e a fonte está indicada ao lado. A documentação da JetBrains está resumida com minhas palavras.

## Resumo executivo

1. **O editor atual não lê código Python como um editor de código.** A quebra de linha automática (soft wrap) está sempre ligada e não há rolagem horizontal (`CodeTextView.swift:130,136-138`). Na captura do catálogo, a linha `    self.wait_to_be_visible(...)` deixa os 4 espaços sozinhos numa linha visual, com número no gutter, e o código continua na linha de baixo, sem recuo. O efeito é recuo sumido e linhas "em branco" falsas (`docs/design/telas/03b-…-escuro.png` e `03c-…-escuro.png`). No PyCharm o soft wrap vem desligado para `.py`: a máscara padrão é `*.md; *.txt; *.rst; *.adoc`. **Verificado.**
2. **Hoje o tratamento de caracteres não é igual ao do PyCharm.**
   - O PyCharm normaliza toda quebra de linha para `\n` dentro do documento e grava com o separador do arquivo (LF no macOS). O Mo baile guarda o `\r\n` colado e o grava como `0D 0A`.
   - O PyCharm desenha NBSP, ZWSP, BOM e controles bidi como etiquetas visíveis (`NBSP`, `ZWSP`). No Mo baile esses caracteres ficam invisíveis.
   - O Mo baile desliga aspas e travessões automáticos, mas deixa ligadas a substituição de texto do macOS, a verificação ortográfica contínua, a inserção inteligente e a predição inline.
   - A contagem de linhas trata `\r\n` como um único `Character` do Swift, e o cabeçalho mostra "1 linha" para um texto colado do Windows.

   Os fatos sobre o PyCharm estão **Verificados**. O comportamento do Mo baile é **Inferido** do código.
3. **O realce de sintaxe para de acompanhar quando a pessoa digita.** O `PythonHighlighter` só roda quando o texto vindo do estado é diferente do texto do editor (`CodeEditorView.swift:43`). Quando é a pessoa que digita, os dois já são iguais, e o realce não roda. **Inferido** do código.
4. **Tipografia e cores diferentes.**

   | | Mo baile hoje | PyCharm |
   | --- | --- | --- |
   | Fonte | SF Mono 11,5 pt | JetBrains Mono 13 |
   | Espaçamento | 1,35 | 1,2 |
   | Ligaduras | — | desligadas |
   | Esquema escuro | Catppuccin | Islands Dark / Dark (valores na seção 2.5) |

   Trocar para a fonte e as cores do PyCharm contraria o design system (SF Mono para código, ADR 0002). Essa decisão é do dono.
5. **Proposta**:
   - **P0**: editor fiel ao PyCharm (caracteres, fonte, sem soft wrap, gutter, linha atual, status do editor com `linha:coluna  LF  UTF-8  4 espaços`).
   - **P1**: uma árvore "Projeto" com a pasta `~/Documents/Mo baile` (pages, locators, flows, Specs, Relatórios) servida pelo motor, abas de editor e navegação pelo keymap macOS do PyCharm (⇧⇧, ⇧⌘O, ⌥⌘O, ⌘E, ⌘[ ⌘], ⌘L, ⇧⌘F12).
   - **P2**: dobra de código, guias de recuo, pares de aspas e parênteses, autocompletar de locators, sticky lines.
   - **Fora**: indexação, seletor de interpretador, VCS, faixas de tool windows flutuantes e AI.

## 1. Pergunta e decisão

- **Pedido** (palavras do dono): a aba Page Objects "similar ao PyCharm", com a mesma fluidez, e "o que ele recebe de caractere eu quero receber no nosso".
- **Decisão que esta pesquisa apoia**: o escopo e a ordem da reformulação (P0, P1, P2), o que não copiar e qual teste prova que o editor trata texto como o PyCharm.
- **Fronteira**: o Mo baile não é IDE. Do PyCharm interessam o layout de tool windows, o editor de texto, a árvore de arquivos, a navegação por teclado e a sensação de que nada trava.
- **Método**: leitura de fonte primária (ajuda oficial, código do IntelliJ Platform, keymap) e leitura do código do Mo baile. Não houve teste com usuário nem execução do PyCharm nesta rodada. O teste de caracteres da seção 5 tem o PyCharm real como oráculo.

## 2. PyCharm: como funciona (fatos)

### 2.1 Layout da janela (New UI / Islands)

| Elemento | O que faz | Fonte | Rótulo |
| --- | --- | --- | --- |
| Cabeçalho da janela | Widgets de projeto, de VCS e de Run, além de Search Everywhere e Settings | [Guided tour](https://www.jetbrains.com/help/pycharm/guided-tour-around-the-user-interface.html) | Verificado |
| Faixas de tool windows | Barras de ícones nas laterais e embaixo. Clicar mostra ou esconde o painel. Dá para arrastar ícones e ligar ou desligar as barras em View › Appearance. Um botão no canto inferior esquerdo mostra ou esconde as barras | [Tool windows](https://www.jetbrains.com/help/pycharm/tool-windows.html), Guided tour | Verificado |
| Atalhos de tool window (keymap macOS) | ⌘1 Project, ⌘4 Run, ⌘6 Problems, ⌘7 Structure, ⌘8 Services, ⌘0 Commit, ⌥F12 Terminal | `Mac OS X 10.5+.xml` e `$default.xml`; o keymap do Mac troca Ctrl por ⌘ (`MacOSDefaultKeymap.kt`, `mapModifiers`) | Verificado |
| Esconder tudo, voltar ao editor | ⇧⌘F12 esconde ou restaura todas as tool windows. ⎋ devolve o foco ao editor. ⇧⎋ esconde a tool window ativa. F12 volta para a última tool window | `$default.xml` (`HideAllWindows`, `HideActiveWindow`, `JumpToLastWindow`) + conversão do Mac; [Tool windows](https://www.jetbrains.com/help/pycharm/tool-windows.html) | Verificado |
| Redimensionar | Atalhos de "stretch" com Ctrl+Alt+Shift+setas (página da ajuda; equivalente Mac não listado). Que a largura fica lembrada é **Inferido** (comportamento conhecido, não documentado na página) | Tool windows | Verificado em parte |
| Abas do editor | Uma aba por arquivo. ⇧⌘[ e ⇧⌘] trocam de aba, ⌘W fecha, ⌃Tab abre o Switcher (arquivos e tool windows). Dividir à direita ("Open in Right Split", ⇧↩ na árvore) | `Mac OS X 10.5+.xml` (`NextTab`, `PreviousTab`, `CloseContent`, `Switcher`); [Project tool window](https://www.jetbrains.com/help/pycharm/project-tool-window.html) | Verificado |
| Breadcrumbs e navigation bar | Breadcrumbs ligados por padrão e embaixo do editor (`SHOW_BREADCRUMBS = true`, `SHOW_BREADCRUMBS_ABOVE = false`). Na New UI a navigation bar fica à esquerda da status bar (View › Appearance › Navigation Bar: Top ou Don't show). ⌘↑ abre a navigation bar | `EditorSettingsExternalizable.java:1135-1136`; Guided tour; `Mac OS X 10.5+.xml` (`ShowNavBar`) | Verificado |
| Status bar | Mensagens recentes, progresso e widgets: `linha:coluna` (clicar abre Go to Line), separador de linha (`LF`), codificação (`UTF-8`), recuo ("4 spaces"), cadeado de somente leitura, interpretador Python, branch do VCS e memória. Clicar com o botão direito liga ou desliga cada widget | [Guided tour](https://www.jetbrains.com/help/pycharm/guided-tour-around-the-user-interface.html) | Verificado |
| Editor vazio | Dicas de atalho: Search Everywhere (Double ⇧), Go to File ⇧⌘O, Recent Files ⌘E, Navigation Bar ⌘↑, Drop files here to open them | Captura enviada pelo dono; a ajuda não descreve essa tela | Verificado só pela captura |

### 2.2 Árvore Project

| Recurso | Comportamento | Fonte | Rótulo |
| --- | --- | --- | --- |
| Cabeçalho | Select Opened File (alvo), Expand All, Collapse All, menu de opções e Hide (⇧⎋) | [Project tool window](https://www.jetbrains.com/help/pycharm/project-tool-window.html) | Verificado |
| Opções | Always Select Opened File (o equivalente ao antigo "autoscroll from source"), Open Files with Single Click, Enable Preview Tab, ordenação (nome, tipo, data de modificação) e "pastas sempre no topo" | idem | Verificado |
| Nós | Pastas e pacotes, External Libraries (só na visão Project) e Scratches and Consoles | idem | Verificado |
| Teclado | Espaço abre uma prévia em popup. F4 abre no editor. ⇧↩ abre na divisão à direita | idem | Verificado |
| Localizar o arquivo aberto | Select In (⌥F1) e o botão Select Opened File | `$default.xml` (`SelectIn` = `alt F1`); Project tool window | Verificado |
| Speed search | Digitar com o foco na árvore abre um campo sobre o painel. A seleção pula para o primeiro item que casa, com a parte casada realçada. ↑↓ passam entre os itens que casam, ↩ abre, ⎋ fecha o campo. Só procura em nós expandidos. A página não diz se a árvore é filtrada | [Speed search](https://www.jetbrains.com/help/pycharm/speed-search-in-the-tool-windows.html) | Verificado |
| Arrastar e soltar | Arrastar no editor vem ligado (`IS_DND_ENABLED = true`). A ajuda não trata do arrastar na árvore | `EditorSettingsExternalizable.java:1166` | Verificado em parte |

### 2.3 Navegação e fluidez (keymap macOS padrão)

Fonte: `platform/platform-resources/src/keymaps/Mac OS X 10.5+.xml`, `$default.xml` e a conversão de Ctrl para ⌘ em `MacOSDefaultKeymap.kt`. Todos **Verificados** no código.

| Ação | Atalho | Observação (ajuda) |
| --- | --- | --- |
| Search Everywhere | ⇧ duas vezes | Abre com os arquivos recentes. Tab troca entre abas (All, Classes, Files, Symbols, Actions, Text). [Ajuda](https://www.jetbrains.com/help/pycharm/searching-everywhere.html) |
| Find Action | ⇧⌘A | |
| Go to File / Class / Symbol | ⇧⌘O / ⌘O / ⌥⌘O | |
| Recent Files / Recent Locations | ⌘E / ⇧⌘E | |
| Back / Forward | ⌘[ / ⌘] (também ⌥⌘← / ⌥⌘→ e os botões 4 e 5 do mouse) | |
| Go to Line:Column | ⌘L | Aceita `linha:coluna`. [Ajuda](https://www.jetbrains.com/help/pycharm/navigating-through-the-source-code.html) |
| File Structure | ⌘F12 | |
| Find / Replace / Find in Files | ⌘F / ⌘R / ⇧⌘F | |
| Comentar linha / Reformatar / Duplicar | ⌘/ / ⌥⌘L / ⌘D | |
| Expandir e recolher dobra (uma / todas) | ⌘+ ⌘- / ⇧⌘+ ⇧⌘- | |
| Colar do histórico / Colar como texto simples | ⇧⌘V / ⌥⇧⌘V | |
| Ampliar e reduzir seleção | ⌥↑ / ⌥↓ | |
| Desfazer / Refazer | ⌘Z / ⇧⌘Z | |
| Run / Debug | ⌃R / ⌃D | |
| Ações de contexto | ⌥↩ | |

### 2.4 O editor ("leitor de texto"): padrões

| Item | Padrão do PyCharm | Fonte | Rótulo |
| --- | --- | --- | --- |
| Fonte | JetBrains Mono | [IntelliJ Platform UI Guidelines, Typography](https://plugins.jetbrains.com/docs/intellij/typography.html) | Verificado |
| Tamanho | 13 com JetBrains Mono (12 com outra fonte, fora do Windows) | `FontPreferences.java`, `DEFAULT_FONT_SIZE` | Verificado |
| Altura de linha | 1,2 | `FontPreferences.java`, `DEFAULT_LINE_SPACING = 1.2f`; [Font](https://www.jetbrains.com/help/pycharm/settings-editor-font.html) | Verificado |
| Ligaduras | desligadas (`useLigatures()` devolve `false`) | `FontPreferences.java` | Verificado |
| Licença da fonte | OFL-1.1, v2.304 | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono) | Verificado |
| Números de linha | ligados, absolutos | `EditorSettingsExternalizable.java:1128-1130` | Verificado |
| Contorno de dobra | ligado, só no hover | `:1132-1133` | Verificado |
| Linha do cursor realçada | ligada (`myCaretRowShown = true`) | `EditorSettingsState.kt:78` | Verificado |
| Guias de recuo | ligadas | `:1160` | Verificado |
| Mostrar espaços em branco | desligado (com Leading, Inner, Trailing e Selection marcados para quando ligar) | `:1153-1157` | Verificado |
| Caracteres especiais | ligado: "Render special characters … using their Unicode name abbreviations" | `intellij.platform.ide.impl.xml:1546`, `ApplicationBundle.properties:899` | Verificado |
| Soft wrap | só `*.md; *.txt; *.rst; *.adoc`. Com soft wrap ligado, o trecho quebrado herda o recuo da linha original (`USE_CUSTOM_SOFT_WRAP_INDENT = true`, deslocamento 0) | `:64,1108-1110` | Verificado (o significado de "herda o recuo" é Inferido) |
| Sticky lines | ligadas, até 5 | `:1137-1138` | Verificado |
| Cursor | piscando, 500 ms, sem bloco | `:1124-1125,1145`, `BLINKING_RANGE` | Verificado |
| Realce das ocorrências da seleção | ligado | `:1152` | Verificado |
| Smart Home | ligado | `:1143` | Verificado |
| Ao salvar: remover espaços no fim da linha | só nas linhas modificadas (`Changed`), preservando a linha do cursor | `:1117,1183` | Verificado |
| Ao salvar: garantir quebra de linha no fim | **desligado** | `:1118` | Verificado |
| Ao salvar: remover linhas em branco no fim | desligado | `:1119` | Verificado |
| Quebra de linha no documento | "sempre normalizadas para `\n`" | [Documents](https://plugins.jetbrains.com/docs/intellij/documents.html) | Verificado |
| Separador de linha | Code Style › Line separator, com a opção System-Dependent (LF no macOS). O widget da status bar troca por arquivo. A inspeção "Inconsistent line separators" aponta os arquivos que divergem | [Line separators](https://www.jetbrains.com/help/pycharm/configuring-line-endings-and-line-separators.html) | Verificado. Que o padrão de fábrica seja System-Dependent é Inferido: a página lista a opção sem dizer qual é o padrão |
| Codificação | Com BOM, vale a codificação do BOM. Sem BOM, vale a do arquivo, depois a da pasta, a do projeto e por fim a global. A página não diz o padrão de fábrica nem se arquivo UTF-8 novo leva BOM | [Encoding](https://www.jetbrains.com/help/pycharm/encoding.html) | Verificado o que a página diz. UTF-8 sem BOM para arquivo novo é Inferido |
| Pares de colchete e de aspas | ligados. Digitar aspas sobre uma seleção envolve a seleção. Tab sai do par | `CodeInsightSettings.java:137-140,178` | Verificado |
| Smart indent no Enter, smart backspace | ligado; backspace em modo `AUTOINDENT` | `:116,129` | Verificado |
| Reformatar ao colar | `INDENT_EACH_LINE` (recua cada linha colada) | `:144-147` | Verificado. O Python tem processador próprio de colagem, Não verificado |
| Autocompletar | popup automático ligado | `:68` | Verificado |
| Tab do teclado no Python | insere 4 espaços (`USE_TAB_CHARACTER` falso no estilo do Python) | — | Inferido (PEP 8 e padrão conhecido; não aberto) |
| Aspas e travessões "inteligentes" do macOS | não acontecem: o editor do IntelliJ é Swing, desenhado pela JetBrains Runtime, fora do sistema de texto Cocoa (`NSTextView`) onde moram essas substituições | — | Inferido |

**Quais caracteres viram etiqueta** (`SpecialCharacterFragment.java:19-49`, **Verificado**):
- os controles C0, menos tab, LF e CR (`NUL`, `BEL`, `ESC`…);
- `DEL` e os controles C1;
- `NBSP`, `SHY` e `CGJ`;
- os espaços tipográficos U+2000–U+200A;
- `ZWSP`, `ZWNJ`, `ZWJ`, `LRM` e `RLM`;
- `LSEP` e `PSEP`;
- os controles bidi `LRE`, `RLE`, `PDF`, `LRO`, `RLO`, `LRI`, `RLI`, `FSI` e `PDI`;
- `NNBSP`, `MMSP` e `WJ`;
- o BOM no meio do texto, `ZWNBSP`.

Há duas exceções:
- NBSP e os espaços especiais seguidos de marca combinante não viram etiqueta;
- ZWJ e ZWNJ vizinhos de caractere não ASCII também não viram, para não quebrar emoji nem escritas complexas (`:69-84`).

O emoji `👩‍💻` aparece inteiro, e um `ZWSP` entre letras ASCII aparece como `ZWSP`.

### 2.5 Cores do esquema escuro (Python)

| Papel | Islands Dark (2025.2+) | New UI Dark | Fonte |
| --- | --- | --- | --- |
| Fundo do editor | `#191A1C` | `#1E1F22` | `themes/islands/IslandSchemeDark.xml`, `themes/expUI/expUI_darkScheme.xml` |
| Texto e identificador | `#BCBEC4` | `#BCBEC4` | idem |
| Palavra-chave (`def`, `class`, `return`) | `#CF8E6D` | `#CF8E6D` | idem |
| String | `#6AAB73` | `#6AAB73` | idem |
| Comentário de linha | `#7A7E85` | `#7A7E85` | idem |
| Docstring | `#5F826B` | `#5F826B` | idem |
| Número | `#2AACB8` | `#2AACB8` | idem |
| Declaração de função | `#56A8F5` | `#56A8F5` | idem |
| Decorador (metadata) | `#B3AE60` | `#B3AE60` | idem |
| Escape em string | `#CF8E6D` | `#CF8E6D` | idem |
| Constante e campo de instância | `#C77DBB` | `#C77DBB` | idem |
| `self` | `#94558D` | herdado | `python/python-code-insight/resources/colorSchemes/PythonDarcula.xml` |
| Builtin / argumento nomeado | `#8888C6` / `#AA4926` | herdado | idem |
| Linha do cursor | `#1F2024` | `#26282E` | esquemas acima |
| Número de linha / número na linha do cursor | `#4B5059` / `#A1A3AB` | igual | idem |
| Guia de recuo / espaços visíveis | `#323438` / `#6F737A` | `#313438` / `#6F737A` | idem |

Todos **Verificados**. O tema "Islands Dark" declara `parent_scheme="Darcula"` e `ideVersion 2025.2.0.0`. Nome de classe e constante em CAIXA ALTA não têm cor própria no Python. Isso é **Inferido**: o `DEFAULT_CLASS_NAME` não está sobrescrito nesses arquivos.

### 2.6 Desempenho percebido

- **Indexação** (chamada de "project analysis" desde a 2025.3) roda em segundo plano. Enquanto ela corre, recursos "inteligentes" ficam indisponíveis ou parciais, mas digitar, usar VCS e mudar ajustes continuam funcionando. O progresso aparece na status bar e abre o diálogo Processes. A varredura não pausa; a análise de conteúdo pausa ([Indexing](https://www.jetbrains.com/help/pycharm/indexing.html)). **Verificado.**
- **Power Save Mode** (File › Power Save Mode) desliga a análise contínua, o popup automático de completar e de parâmetros e a completação preemptiva. Completar manual, documentação, navegação, busca, refatoração e VCS continuam. A fonte é a ajuda do Rider ([Power Save Mode](https://www.jetbrains.com/help/rider/Power_save_mode.html)); a página do PyCharm não foi achada. **Verificado para o Rider, Inferido para o PyCharm.**
- **Lição para outra trilha**: o editor nunca espera trabalho de fundo. Análise cara é adiada, pausável e desligável, e o progresso fica visível num lugar só.

## 3. Mo baile hoje: a aba Page Objects (lida no código)

### 3.1 Layout

| Peça | Onde | O que faz | Rótulo |
| --- | --- | --- | --- |
| Janela | `Views/MainWindow/ContentView.swift:22-56` | `NavigationSplitView`: barra lateral, depois `DetailColumn`, depois o inspector próprio num `HStack`. A largura do inspector é guardada em `@SceneStorage("larguraInspector")` (`:99`) | Verificado |
| Barra lateral | `Views/MainWindow/AppSidebar.swift:22-80` | Início, a seção Workspace (Page Objects ⌘1, Rede ⌘2, Analytics ⌘3, Relatório ⌘4) e a seção "Fluxo · <chave>" com os passos gravados | Verificado |
| Coluna central | `ContentView.swift:194-265` | Espelho com largura guardada (`larguraEspelho`), divisória própria e `WorkspacePane`. Mais embaixo, a `StatusBar` global | Verificado |
| Área Page Objects | `Views/Workspace/DualEditorPane.swift:15-146` | Na barra acessória: seletor de estratégia, `pages`/`locators` em controle segmentado (quando os editores não estão lado a lado), Estrutura… e Lado a lado. Estado vazio com "Nenhum passo gravado". Rodapé de 26 pt com "passo N · ação · estratégia" e um "Código sincronizado" fixo | Verificado |
| Cabeçalho do editor | `DualEditorPane.swift:149-235` | Ícone de pasta, `pages / <chave>.py`, contagem de linhas e os botões Copiar, Salvar e Limpar | Verificado |
| Inspector | `ContentView.swift:39-56`, `Views/Hierarchy/HierarchyTreeView.swift` | Hierarquia com campo de busca que **filtra** a árvore (`:145-203`), ← e → para recolher e expandir (`:61-67`) e atributos embaixo | Verificado |
| `splitEditors` | `App/AppState.swift:33` | Não persiste entre aberturas | Verificado |

### 3.2 O editor

| Item | Valor atual | Onde | Rótulo |
| --- | --- | --- | --- |
| Componente | `NSTextView` (`CodeTextView`, subclasse vazia) dentro de `NSScrollView`, com gutter próprio (`IDEGutterView`) | `CodeTextView.swift:11-178` | Verificado |
| Fonte | `NSFont.monospacedSystemFont(ofSize: 11.5)` (SF Mono) no texto. Gutter em `monospacedDigitSystemFont` 11 | `CodeEditorView.swift:15`, `CodeTextView.swift:18` | Verificado |
| Altura de linha | `lineHeightMultiple = 1.35` | `PythonHighlighter.swift:55-57` | Verificado |
| Soft wrap | sempre ligado: `widthTracksTextView = true`, `isHorizontallyResizable = false`, sem rolagem horizontal | `CodeTextView.swift:130,136-138` | Verificado |
| Efeito do soft wrap | O recuo aparece numa linha visual sozinho e o código desce para a linha seguinte, sem recuo. Daí as linhas "vazias" numeradas no gutter | capturas `03b`/`03c` (escuro) | Verificado na captura. O mecanismo (o word wrap leva a "palavra" longa inteira para a linha seguinte) é Inferido |
| Substituições desligadas | aspas (`isAutomaticQuoteSubstitutionEnabled`), travessão (`isAutomaticDashSubstitutionEnabled`), correção ortográfica (`isAutomaticSpellingCorrectionEnabled`) | `CodeEditorView.swift:24-26` | Verificado |
| Não tocadas (ficam no padrão do sistema ou nas preferências do usuário) | `isAutomaticTextReplacementEnabled` (atalhos de texto do usuário), `isContinuousSpellCheckingEnabled`, `isGrammarCheckingEnabled`, `isAutomaticLinkDetectionEnabled`, `isAutomaticDataDetectionEnabled`, `isAutomaticTextCompletionEnabled`, `smartInsertDeleteEnabled` ("insere ou apaga espaço em volta das palavras selecionadas"), `inlinePredictionType` (macOS 14+) e Writing Tools (macOS 15.1+) | busca sem ocorrência em `apps/MoBaile/Sources`. Semântica das propriedades em [NSTextView](https://developer.apple.com/documentation/appkit/nstextview) | Verificado que não são definidas. O valor padrão de cada uma é Não verificado (a página da Apple não informa) |
| Rich text | `isRichText = false` | `:22` | Verificado |
| Desfazer | `allowsUndo = true`, mas cada passo gravado troca o conteúdo inteiro com `textStorage.setAttributedString` | `:23,51` | Inferido: a troca não passa pelo `UndoManager`, e ⌘Z depois de gravar um passo fica incoerente |
| Realce de sintaxe | regex sobre o texto todo, em 7 passadas, na thread principal. `self` é colorido como palavra-chave. CAIXA_ALTA ganha a cor de classe | `PythonHighlighter.swift:14-58` | Verificado |
| Realce ao digitar | não atualiza. Só recolore se `textView.string != text` ou se o destaque ou o tema mudarem; depois de digitar, os dois textos já são iguais | `CodeEditorView.swift:42-59,101-103` | Inferido do código |
| Linha atual, guias de recuo, espaços, caracteres especiais, dobra | não existem | — | Verificado (ausência no código) |
| Gutter | numera depois de `0x0A`. A largura vem de `text.split(separator: "\n")` | `CodeTextView.swift:83-96`, `CodeEditorView.swift:71` | Verificado |
| Contagem com CRLF | `split(separator: "\n")` sobre `String` compara `Character`, e `"\r\n"` é um só grafema (regra GB3 do [UAX #29](https://www.unicode.org/reports/tr29/)). Texto todo em CRLF conta como "1 linha" no cabeçalho | `DualEditorPane.swift:229-234` | Inferido |
| Busca dentro do editor | sem `usesFindBar`. O ⌘F do app vai para a busca da hierarquia em Page Objects | `CommandRegistry.swift:318-324` | Verificado |

### 3.3 Como o código chega e como é gravado

- **Chegada.** O `codegen.record` do motor devolve `object_code` e `action_code`. O front **acrescenta** cada um, mais `"\n"`, a `locatorsCode` e `actionsCode` (`Engine/EngineSession.swift:1081-1082`). O `passive.step` faz o mesmo (`:1690-1691`), e a asserção de rede também acrescenta trecho (`Views/Mirror/MirrorRefreshButton.swift:118`). **Verificado.**
- **Formato gerado.** Recuo de 4 espaços, com `def` dentro de classe implícita e aspas duplas por `_py_str` (`engine/src/mobaile/services/codegen.py:29-40,343-372`). O arquivo salvo é uma sequência de trechos recuados, sem `class …:` nem imports, então não é um módulo Python válido sozinho. Isso fica fora do escopo, mas afeta a árvore Projeto. **Verificado.**
- **Gravação.** O `codegen.save` recebe o texto dos editores (`EngineSession.swift:1191-1206`) e grava `pages/<chave>.py` e `locators/<chave>.py` em `~/Documents/Mo baile`, com `write_text(conteudo, encoding="utf-8")` (`engine/src/mobaile/rpc/server.py:1656-1693`):
  - UTF-8 sem BOM. **Verificado.**
  - O modo texto do Python troca `\n` por `os.linesep` (`\n` no macOS) e deixa `\r` como está, então CRLF vai para o disco como `0D 0A` ([open()](https://docs.python.org/3/library/functions.html#open)). **Inferido.**
  - Nenhuma normalização Unicode, nenhuma remoção de espaço no fim da linha, nenhum ajuste de quebra de linha no fim do arquivo. **Verificado** pela ausência no código.
  - O nome da chave é validado e a pasta fica presa à raiz (SEC-5).
- **Outras pastas que o motor grava:**
  - `flows/*.yaml`, sem sobrescrever (`server.py:2059-2093`);
  - `Relatórios/` e `Specs/` (`services/report/service.py:96,295,367`);
  - gravações de tela em `~/Movies/Mo baile`.

  Os recentes ficam em `home.recents` via `_remember` (`server.py:715-718`). **Verificado.**

### 3.4 Atalhos e paleta

Registro único em `App/CommandRegistry.swift` (o menu e a paleta leem dele). Os atalhos que importam aqui (**Verificado**, `:270-523`):

| Atalho | Ação | Linha |
| --- | --- | --- |
| ⌘0 a ⌘5 | áreas (⌘1 = Page Objects) | `:272` |
| ⌥⌘I | inspector | `:283` |
| ⌥1 / ⌥2 | espelho / workspace | `:291,298` |
| ⌥⌘F | todos os painéis | `:302` |
| ⌃⌘Z | Modo Zen | `:307` |
| ⌘F | busca | `:319,324` |
| ⇧⌘R | atualizar aparelhos | `:347` |
| ⌘K | atualizar tela | `:352` |
| ⌘E | iniciar ou parar o espelho | `:358` |
| ⌘R | Rodar Automação | `:424` |
| ⌘S | Salvar Page Object | `:442` |
| ⇧⌘E | Exportar HAR | `:463` |
| ⌘O | Abrir Spec | `:488` |
| ⌘, | Ajustes | `:514` |
| ⇧⌘P | Paleta de Comandos | `:523` |

A paleta (`Views/CommandPalette/`, `App/CommandSearch.swift`) tem busca por palavras com subsequência e distância de edição, mais as recentes no topo. Ela só busca **ações**: não busca arquivos, símbolos nem passos.

## 4. Gap analysis: PyCharm × Mo baile

| # | Característica do PyCharm | Mo baile hoje | Veredito |
| --- | --- | --- | --- |
| G1 | Soft wrap desligado em `.py`. Rolagem horizontal. Quando ligado, o trecho quebrado herda o recuo | Sempre ligado, recuo some | **Copiar** (P0) |
| G2 | JetBrains Mono 13 / 1,2 / sem ligaduras | SF Mono 11,5 / 1,35 | **Copiar**, com decisão de design (ver R1) (P0) |
| G3 | Quebra de linha normalizada para `\n` ao entrar (colar, abrir). Grava com o separador do arquivo, LF por padrão | Guarda CR e CRLF e grava como estão | **Copiar** (P0) |
| G4 | Nenhuma substituição do sistema. Colar é literal (fora o recuo) | Aspas, travessão e correção desligados. Substituição de texto, ortografia contínua, smart insert/delete, predição inline e Writing Tools ligados ou indefinidos | **Copiar**: desligar tudo (P0) |
| G5 | Caracteres especiais desenhados como etiqueta (`NBSP`, `ZWSP`…) | Invisíveis | **Copiar** (P0) |
| G6 | Gutter com números, linha do cursor realçada (`#1F2024`), número da linha atual mais claro | Gutter sem linha atual. Números desalinhados com o texto (o espaçamento de 1,35 empurra o glifo para baixo; Inferido da captura) | **Copiar** (P0) |
| G7 | Realce de sintaxe sempre atual e incremental | Fica velho depois de digitar e recolore tudo a cada passo | **Copiar** (P0) |
| G8 | Cores Islands Dark e New UI Dark para Python | Catppuccin (escuro) e cores próprias (claro); `self` como palavra-chave; CAIXA_ALTA colorida | **Copiar** como esquema do editor "PyCharm", opcional (P0 no escuro, P1 no claro) |
| G9 | Status do editor: `linha:coluna`, `LF`, `UTF-8`, `4 spaces`, interpretador, cadeado | Rodapé com passo e um "Código sincronizado" sempre verde (`DualEditorPane.swift:131`) | **Adaptar** (P0): rodapé vira status do editor; o interpretador mostra o Python do motor (`setup.py:124,488` já expõe versão e caminho) |
| G10 | Estado salvo ou alterado do arquivo | Inexistente; "sincronizado" fixo engana | **Adaptar** (P0): "não salvo" / "salvo às hh:mm" |
| G11 | Editor vazio com dicas de atalho e "solte arquivos aqui" | "Nenhum passo gravado" + Gravar Passo | **Adaptar** (P1): manter a frase e a ação; acrescentar as dicas de atalho que existirem |
| G12 | Árvore Project com speed search, Select Opened File, Expand/Collapse All, prévia com Espaço | Inexistente. Os passos estão na barra lateral | **Adaptar** (P1): árvore "Projeto" = `~/Documents/Mo baile` servida pelo motor |
| G13 | Abas do editor, Split Right, ⌘W, ⇧⌘[ ⇧⌘] | Segmentado pages/locators + Lado a lado | **Adaptar** (P1): abas reais; Lado a lado = Split Right |
| G14 | Search Everywhere ⇧⇧, Find Action ⇧⌘A, Go to File ⇧⌘O, Go to Symbol ⌥⌘O, Recent Files ⌘E, Back/Forward ⌘[ ⌘], Go to Line ⌘L, File Structure ⌘F12 | Paleta de ações ⇧⌘P | **Adaptar** (P1): a paleta ganha abas e passa a responder também a ⇧⇧ e ⇧⌘A |
| G15 | ⌘1 foca ou alterna Project. ⇧⌘F12 esconde todas as tool windows. ⎋ volta ao editor. ⇧⎋ esconde o painel | ⌘1 vai para a área. Zen em ⌃⌘Z. ⌥1/⌥2/⌥⌘I alternam painéis | **Adaptar** (P1): ⌘1 de novo em Page Objects alterna a árvore; ⇧⌘F12 vira sinônimo do Zen |
| G16 | Breadcrumbs embaixo (arquivo › def) | "passo N · ação · estratégia" | **Adaptar** (P1) |
| G17 | Find e Replace no editor (⌘F / ⌘R) | ⌘F vai para a hierarquia; ⌘R roda a automação | **Adaptar** (P1): ⌘F contextual ao foco; Replace em ⌥⌘F (macOS) para não tirar o ⌘R do Rodar |
| G18 | Dobra, guias de recuo, sticky lines, pares de aspas e parênteses, smart backspace, autocompletar | Inexistentes | **Copiar depois** (P2) |
| G19 | Ao salvar: remover espaços no fim só das linhas modificadas; não forçar quebra de linha no fim | Não mexe em nada | **Decidir** (P1). Recomendo copiar só o "não forçar quebra de linha no fim" e não remover espaços, porque o Mo baile não sabe quais linhas foram alteradas antes do primeiro salvamento (Suposição) |
| G20 | Indexação, dumb mode, Power Save, interpretador selecionável, VCS, widget de Run, faixa de AI, tool windows flutuantes ou destacáveis, External Libraries, Scratches | — | **Não copiar**. O Mo baile não analisa projeto, e o Rodar já existe. Faixas de ícones laterais brigam com a barra lateral do HIG (ADR 0002). Vidro só na navegação (ADR 0006): editor e árvore são conteúdo, sem vidro |

**Atalhos com conflito** (**Verificado** no registro; a decisão é do dono):
- ⌘E: espelho no Mo baile, Recent Files no PyCharm;
- ⌘R: Rodar no Mo baile, Replace no PyCharm, onde Run é ⌃R;
- ⌘K: atualizar tela no Mo baile, Commit no PyCharm;
- ⌘O: Abrir Spec no Mo baile, Go to Class no PyCharm;
- ⇧⌘E: Exportar HAR no Mo baile, Recent Locations no PyCharm;
- ⌘F: busca da hierarquia no Mo baile, busca no editor no PyCharm.

Recomendação: valer o atalho do PyCharm **quando o foco estiver no editor ou na árvore de Page Objects**, e o do Mo baile no resto. A exceção é ⌘R: o Rodar fica, porque é a ação primária do produto. O ⌘E precisa de decisão explícita: trocar o espelho de atalho tira memória muscular de quem já usa.

## 5. Teste de caracteres idênticos (oráculo: PyCharm)

### 5.1 Procedimento

1. **PyCharm** (versão anotada no relatório, ajustes de fábrica, projeto novo):
   - criar `prova.py` vazio;
   - colar o texto T1 com ⌘V;
   - salvar com ⌘S;
   - rodar `xxd prova.py > pycharm.hex`.
2. **Mo baile**:
   - com o editor `pages` vazio, colar T1 com ⌘V;
   - salvar com ⌘S;
   - rodar `xxd ~/Documents/Mo\ baile/pages/<chave>.py > mobaile.hex`.
3. `diff pycharm.hex mobaile.hex` tem de sair vazio.
4. Comparar também a tela: as capturas dos dois editores devem mostrar as mesmas etiquetas `NBSP` e `ZWSP`, o emoji inteiro e o `é` igual nas duas formas.
5. **Teste automatizado no Mo baile** (sem PyCharm), em duas camadas:
   - unitário Swift: colagem em `CodeTextView` produzindo a string esperada;
   - contrato Python: `codegen.save` com essa string produzindo os bytes esperados.

   Os bytes esperados vêm do `pycharm.hex` capturado uma vez e guardado como fixture.

### 5.2 Texto de prova T1

Montado no pasteboard como texto simples, **com `\r\n` (CRLF) entre as linhas e sem quebra no fim**:

| Linha | Conteúdo (pontos de código) | Prova o quê |
| --- | --- | --- |
| L1 | `s = "reta" + 'simples'` | aspas retas U+0022 e U+0027 |
| L2 | `# -- ... --- fim` | `--`, `...` e `---` sem virar travessão nem reticências |
| L3 | `a` U+0009 `b` | tab no meio da linha preservado |
| L4 | `x` U+00A0 `y` | NBSP preservado e visível |
| L5 | `z` U+200B `w` | ZWSP preservado e visível |
| L6 | U+1F600 espaço U+1F469 U+200D U+1F4BB | emoji fora do BMP e sequência com ZWJ |
| L7 | `c` U+00E9 espaço `c` U+0065 U+0301 | é em NFC e em NFD, sem normalizar |
| L8 | `def f():` | — |
| L9 | 4 × U+0020 `return 1` | recuo relativo preservado na colagem |

### 5.3 Bytes esperados

Previsão **Inferida** a partir dos fatos Verificados da seção 2.4: normalização para `\n`, LF, UTF-8, nenhuma quebra de linha forçada no fim, nenhum espaço no fim de linha. Confirmar com o oráculo antes de virar fixture.

```text
L1  73 20 3D 20 22 72 65 74 61 22 20 2B 20 27 73 69 6D 70 6C 65 73 27 0A
L2  23 20 2D 2D 20 2E 2E 2E 20 2D 2D 2D 20 66 69 6D 0A
L3  61 09 62 0A
L4  78 C2 A0 79 0A
L5  7A E2 80 8B 77 0A
L6  F0 9F 98 80 20 F0 9F 91 A9 E2 80 8D F0 9F 92 BB 0A
L7  63 C3 A9 20 63 65 CC 81 0A
L8  64 65 66 20 66 28 29 3A 0A
L9  20 20 20 20 72 65 74 75 72 6E 20 31
```

- **Total**: 8 bytes `0A`, nenhum `0D`, sem `EF BB BF` no início, sem `0A` final.
- **Hoje o Mo baile daria** (Inferido): `0D 0A` no lugar de cada `0A`. O cabeçalho mostraria "1 linha". `NBSP` e `ZWSP` ficariam invisíveis.
- **Ponto a confirmar no oráculo**: o recuo de L9. O `REFORMAT_ON_PASTE = INDENT_EACH_LINE` e o processador de colagem do Python podem mexer no recuo. Colando na coluna 0 de um arquivo vazio, a previsão é manter os 4 espaços (Inferido). Se o PyCharm mudar, o Mo baile segue o PyCharm.

### 5.4 Testes de digitação

O ponto de partida é um arquivo vazio, digitando tecla a tecla.

- **T2** (Inferido): digitar `x = "a" -- ...` deve dar exatamente esses caracteres nos dois editores.
  - O PyCharm insere o par `""` e sobrescreve a aspa de fechamento ao digitá-la, então o resultado final é o mesmo.
  - Um atalho de "Substituição de texto" do macOS configurado pelo usuário, como o `omw`, **não** pode disparar.
  - O sublinhado vermelho de ortografia não pode aparecer.
- **T3** (Inferido): Tab no começo da linha insere 4 espaços (U+0020 ×4), não U+0009. Com predição inline do macOS visível, Tab não pode aceitar a sugestão.
- **T4** (Inferido): abrir pelo motor um arquivo que já usa CRLF (P1).
  - O status mostra `CRLF`.
  - Editar e salvar mantém `0D 0A`, como o PyCharm, que grava com o separador do arquivo.
  - Trocar para `LF` no widget converte o arquivo inteiro.

## 6. Especificação proposta

A divisão segue a ADR 0001. Ficam no **front**, por serem comportamento de interface:
- entrada de texto, normalização de colagem, desenho, atalhos e layout.

Ficam no **motor**:
- listar, ler e gravar arquivos;
- detectar codificação e separador;
- montar o outline Python (com `ast`).

Toda RPC nova é aditiva (`PROTOCOL_VERSION` 2) e pede `make fixtures` e atualização de `docs/PROTOCOLO_RPC.md`. Mudanças em `apps/MoBaile/` ou `engine/src/` só terminam com `make update-native` e o OK do `verify-native` (AGENTS.md).

### P0: layout e editor com caracteres idênticos

**P0-1. Entrada de texto literal.** Esforço P.
- **O quê**: desligar em `CodeEditorView.makeNSView` (`CodeEditorView.swift:17-31`):
  - `isAutomaticTextReplacementEnabled`;
  - `isContinuousSpellCheckingEnabled`;
  - `isGrammarCheckingEnabled`;
  - `isAutomaticLinkDetectionEnabled`;
  - `isAutomaticDataDetectionEnabled`;
  - `isAutomaticTextCompletionEnabled`;
  - `smartInsertDeleteEnabled`;
  - `inlinePredictionType = .no` (macOS 14+);
  - `writingToolsBehavior = .none` (macOS 15.1+, com `#available`).

  As três que já estão desligadas continuam como estão.
- **Aceite**:
  - um teste unitário instancia o editor e confere cada propriedade;
  - os testes T2 e T3 passam.

**P0-2. Normalização de quebra de linha ao colar e ao receber.** Esforço P.
- **O quê**: o `CodeTextView` sobrescreve a colagem de texto simples (e só ela). Na entrada, `\r\n` e `\r` viram `\n`. Os demais caracteres ficam intactos: tab, NBSP, ZWSP, emoji, NFD e U+2028.
- **Também**:
  - a contagem de linhas passa a usar `NSString`/`utf16` (ou `unicodeScalars`) e não `split` em `Character`;
  - o gutter conta os mesmos separadores que o layout.
- **Aceite**:
  - T1 colado produz em `textView.string` exatamente L1–L9 unidas por `\n`, com os escalares conferidos;
  - o cabeçalho diz "9 linhas".

**P0-3. Gravação com bytes do PyCharm.** Esforço P.
- **O quê**: o `codegen.save` grava com `newline="\n"` (ou com o separador do arquivo, quando houver P1-2). Nada de BOM, normalização Unicode ou quebra de linha forçada no fim.
- **Aceite**:
  - teste de contrato: `codegen.save` com a string de T1 normalizada grava os bytes da seção 5.3;
  - a fixture vem do oráculo PyCharm.

**P0-4. Caracteres especiais visíveis.** Esforço M.
- **O quê**: desenhar a etiqueta (abreviação Unicode num retângulo de 1 pt) para o mesmo conjunto de `SpecialCharacterFragment.java`, com as mesmas exceções (NBSP antes de marca combinante; ZWJ e ZWNJ vizinhos de não ASCII).
- **Caminho provável**: substituição de glifo no `NSLayoutManager` (`shouldGenerateGlyphs` + desenho próprio) ou TextKit 2. O texto não muda, só o desenho.
- **Aceite**:
  - a captura do editor com T1 mostra `NBSP` em L4 e `ZWSP` em L5;
  - o emoji de L6 fica inteiro;
  - copiar a linha devolve U+00A0 e U+200B, e não a etiqueta;
  - o VoiceOver lê o caractere, não a moldura (Inferido; validar).

**P0-5. Sem soft wrap, com rolagem horizontal.** Esforço P.
- **O quê**: `widthTracksTextView = false`, `isHorizontallyResizable = true`, `hasHorizontalScroller = true` e o `containerSize` largo.
- **Opcional**: "Quebrar linhas" fica em Visualizar, desligado por padrão. Ligado, quebra com o recuo da linha original (`headIndent` por parágrafo).
- **Aceite**:
  - com a fixture do catálogo, cada linha lógica ocupa uma linha visual e o recuo de 4 espaços aparece;
  - o gutter numera 1 a 1, sem linhas vazias falsas;
  - recapturar `03b` e `03c`.

**P0-6. Tipografia do PyCharm.** Esforço M. Depende de R1.
- **O quê**:
  - JetBrains Mono 13, altura 1,2 e ligaduras desligadas (`.ligature: 0`). A fonte vai embutida no bundle (OFL-1.1, com a licença copiada para `Resources`), com recuo para SF Mono se o arquivo faltar;
  - gutter na mesma fonte, com tamanho 1 pt menor (Guidelines: "Default −1" para números de linha), alinhado à linha de base do texto;
  - o tamanho vira ajuste do editor, com ⌘+ ⌘- só no editor.
- **Aceite**:
  - `NSFont.fontName` do editor é `JetBrainsMono-Regular` no tamanho 13;
  - `lineHeightMultiple` ou `lineSpacing` equivalente a 1,2;
  - a captura mostra os números do gutter na mesma linha de base do texto (diferença até 1 pt, medida no `NSLayoutManager`);
  - `make verify-native` OK.

**P0-7. Realce de sintaxe incremental e sempre atual.** Esforço M.
- **O quê**:
  - recolorir o parágrafo editado via `NSTextStorageDelegate` (ou `textDidChange` sobre o intervalo editado);
  - acrescentar passo gravado com `textStorage.append`/`replaceCharacters` no fim, preservando seleção e desfazer;
  - `self` com cor própria;
  - CAIXA_ALTA sem cor especial, como no PyCharm.
- **Aceite**:
  - digitar `def x():` muda a cor de `def` na hora;
  - gravar 50 passos com o cursor no meio do texto não move o cursor, e ⌘Z desfaz só a última edição manual;
  - uma recoloração de 1.000 linhas fica abaixo de um quadro (16 ms) num perfil Instruments. O número é a meta, ainda não medido.

**P0-8. Linha atual e esquema "PyCharm Escuro".** Esforço P.
- **O quê**:
  - realce da linha do cursor e número da linha atual mais claro;
  - tokens de sintaxe do Islands Dark (seção 2.5) como esquema do editor "PyCharm", escolhido em Ajustes. A Praia continua padrão do app até o dono decidir (R1);
  - o fundo do editor segue `bgContent` do tema, sem vidro (ADR 0006).
- **Aceite**:
  - `PaletteCheck` (ou um teste equivalente) confere os hexadecimais contra a tabela 2.5;
  - o contraste é calculado (não estimado) para texto, comentário e número de linha sobre o fundo;
  - os valores abaixo de 4,5:1 vão para a lista de riscos, porque o próprio PyCharm usa `#4B5059` no gutter;
  - em Aumentar contraste, o número de linha usa `#A1A3AB`.

**P0-9. Status do editor.** Esforço P.
- **O quê**: o rodapé de 26 pt (`DualEditorPane.swift:122-145`) mostra, quando o editor tem foco, `linha:coluna  LF  UTF-8  4 espaços  Python 3.x.y`. O interpretador vem do `setup`, só leitura.
  - Clicar em `linha:coluna` abre Ir para Linha (⌘L).
  - O "Código sincronizado" fixo sai. Entra "não salvo" ou "salvo às hh:mm", com o caminho no tooltip.
  - O resumo "passo N · ação" vai para os breadcrumbs (P1-6).
- **Aceite**:
  - mover o cursor atualiza `linha:coluna`, contando colunas em grafemas (verificar contra o PyCharm com a linha L6);
  - editar mostra "não salvo";
  - ⌘S mostra "salvo".

### P1: navegação e projeto

**P1-1. Árvore "Projeto".** Esforço G.
- **Motor**:
  - `workspace.tree` lista `~/Documents/Mo baile`: `pages/`, `locators/`, `flows/`, `Specs/`, `Relatórios/`;
  - a sessão atual entra no topo, como nó "Não salvo · <chave>", com `pages` e `locators` em memória;
  - os passos podem aparecer como filhos, mas a lista principal continua na barra lateral;
  - não segue links simbólicos para fora da raiz (SEC-5).
- **Front**:
  - lista em árvore à esquerda do editor, dentro da área Page Objects, com largura em `@SceneStorage`;
  - ⌘1, com Page Objects já aberto, mostra, esconde ou foca a árvore;
  - cabeçalho com Localizar Arquivo Aberto (⌥F1), Expandir Tudo, Recolher Tudo e Revelar no Finder.
- **Speed search** como no PyCharm:
  - digitar abre o campo, seleciona e realça;
  - ↑↓ passam entre os resultados;
  - ⎋ fecha;
  - Espaço abre a prévia (Quick Look).
- **Aceite**:
  - a árvore lista o que existe na pasta e atualiza depois de `codegen.save` e de `flow.maestro_export` (notificação `workspace.changed`);
  - digitar "feat" com foco na árvore seleciona `feature.py`;
  - fixture de contrato gerada.

**P1-2. Abrir, editar e gravar arquivo da árvore.** Esforço M.
- **Motor**:
  - `workspace.read` devolve `{text, encoding, line_separator, bom}`. O texto chega com `\n`, e o separador original vai à parte;
  - `workspace.write` grava com o separador, a codificação e o BOM do arquivo;
  - um arquivo que não é UTF-8 abre como somente leitura, com aviso (cadeado no status).
- **Aceite**:
  - T4 passa;
  - arquivo Latin-1 abre com o cadeado e não é regravado.

**P1-3. Abas.** Esforço M.
- **O quê**: uma aba por arquivo aberto, `pages/<chave>.py` e `locators/<chave>.py` fixas. O Lado a lado vira "Dividir à Direita", e a escolha persiste.
- **Atalhos**: ⌘W fecha, ⇧⌘[ e ⇧⌘] trocam, ⌃Tab abre o Switcher.
- **Aceite**: os atalhos funcionam com o foco no editor, e o estado da divisão sobrevive a reabrir o app.

**P1-4. Buscar em Tudo.** Esforço M.
- **O quê**: a paleta ganha as abas Tudo, Arquivos, Símbolos, Passos e Ações e responde a ⇧⇧ (detector de duplo Shift via `flagsChanged`, janela de 300 ms; Suposição), ⇧⌘A (Ações), ⇧⌘O (Arquivos) e ⌥⌘O (Símbolos).
  - Símbolos vêm de `codegen.outline` no motor, com `ast`: `def`, locators e linha.
  - Aberta sem termo, mostra os recentes (`home.recents`).
- **Aceite**:
  - ⇧⇧ abre a paleta em até 1 quadro depois da segunda tecla;
  - digitar `CAMPO_CPF` e ↩ leva à linha do locator;
  - ⇧⇧ não dispara quando Shift é usado com outra tecla no meio.

**P1-5. Histórico de navegação.** Esforço M.
- **O quê**: ⌘[ e ⌘] (voltar e avançar entre posições de cursor e arquivos), ⌘E (Arquivos Recentes, se o dono aceitar mover o espelho; senão ⇧⌘E) e ⌘L (Ir para Linha:Coluna).
- **Aceite**: abrir A, ir para B na linha 30 e apertar ⌘[ volta para A na posição anterior.

**P1-6. Breadcrumbs.** Esforço P.
- **O quê**: embaixo do editor, `pages › feature.py › click_botao_continuar`, calculado pelo outline do motor e pela posição do cursor (projeção no front). Clicar num segmento leva até ele.
- **Aceite**: mover o cursor para dentro de outro `def` atualiza o breadcrumb.

**P1-7. Painéis.** Esforço P.
- **O quê**:
  - ⇧⌘F12 vira sinônimo do Modo Zen (esconde e restaura tudo);
  - ⎋ na árvore ou no inspector devolve o foco ao editor;
  - ⇧⎋ esconde o painel com foco;
  - ⌘F com foco no editor abre a barra de busca do editor (`usesFindBar = true`, `isIncrementalSearchingEnabled = true`). Fora do editor, continua na hierarquia.
- **Aceite**: os quatro atalhos funcionam em `ToolbarLayoutTests`/UI tests, e a paleta mostra o atalho certo conforme o foco.

**P1-8. Editor vazio.** Esforço P.
- **O quê**: mantém "Nenhum passo gravado" e a ação. Embaixo, as dicas no estilo do PyCharm, só com atalhos que existem: "Buscar em Tudo ⇧⇧", "Ir para Arquivo ⇧⌘O", "Arquivos Recentes ⌘E", "Arraste um .py ou .yaml para abrir".
- **Aceite**: cada dica executa o que diz, e o texto está em pt-BR.

**P1-9. Esquema "PyCharm Claro".** Esforço P.
- **O quê**: extrair de `expUI_lightScheme.xml` com o mesmo método da tabela 2.5.
- **Aceite**: os valores conferem com a fonte, e o contraste é calculado.

### P2: o resto

| Item | Esforço | Aceite |
| --- | --- | --- |
| Dobra de código por `def` e `class` (⌘+ ⌘- ⇧⌘+ ⇧⌘-), contorno no hover | G | Recolher `def` esconde o corpo; salvar grava tudo |
| Guias de recuo (`#323438`) | P | Visíveis a cada 4 colunas de espaço inicial |
| Sticky lines (até 5) com o `def` atual no topo ao rolar | M | Rolando dentro de um `def` longo, a assinatura fica fixa |
| Pares de aspas e parênteses, sobrescrever o fechamento, Tab sai do par, smart backspace | M | Teclas iguais às do PyCharm geram os mesmos caracteres (T2 estendido) |
| Autocompletar nomes de locators e métodos (outline do motor) | M | Digitar `self.locators[...]` e `.CAM` sugere `CAMPO_CPF` |
| Comentar linha ⌘/, duplicar ⌘D, ampliar seleção ⌥↑ | P | Atalhos iguais aos do keymap |
| Mostrar espaços (Visualizar), desligado por padrão | P | Ligado, desenha `·` e `→` em `#6F737A` |
| Ao salvar: remover espaços no fim das linhas modificadas (decisão G19) | M | Se adotado, segue `Changed` + preservar a linha do cursor |
| Arrastar arquivo do Finder para o editor ou a árvore | P | Abre, ou copia para a raiz, conforme decisão |

## 7. O que não copiar, e por quê

- **Indexação, dumb mode e Power Save.** Não existe análise de projeto. Fica a lição de desempenho: nada pesado na thread principal do editor (P0-7).
- **Faixas verticais de tool windows e modos Float, Undock e Window.** A janela segue o HIG com barra lateral nativa (ADR 0002). A árvore Projeto entra como painel da área, não como faixa nova. Vidro não entra em editor nem em árvore (ADR 0006).
- **Seletor de interpretador, VCS, widget de Run e faixa de AI e notificações.** O Python é o do motor (só leitura). O Rodar já é a ação primária. As mensagens já vão para a status bar.
- **Refatoração, inspeções e Find Usages.** Exigiriam um analisador Python no motor. Pode voltar como pedido separado.

## 8. Riscos

| ID | Risco | Mitigação |
| --- | --- | --- |
| R1 | JetBrains Mono e as cores do PyCharm contrariam o design system (SF Mono para código; a Praia e as paletas são a identidade do app) | Decisão do dono. Se aprovar, registrar adendo à ADR 0002 e atualizar `docs/design/design-system/tokens`. Alternativa: "esquema do editor" separado do tema do app, com PyCharm como opção e não como padrão |
| R2 | Contraste do esquema PyCharm (número de linha `#4B5059` sobre `#191A1C`) provavelmente abaixo de 4,5:1 | Calcular no `PaletteCheck`. Em Aumentar contraste, usar `#A1A3AB` |
| R3 | Desenhar caracteres especiais no TextKit pode quebrar seleção, cópia, cursor e VoiceOver | Mudar só o desenho, nunca o texto. Teste de cópia (P0-4) e verificação manual com VoiceOver |
| R4 | Atalhos do PyCharm em conflito com os do Mo baile (⌘E, ⌘R, ⌘K, ⌘O, ⇧⌘E, ⌘F) | Atalhos por foco. O dono decide ⌘E e ⇧⌘E. Testes no `CommandRegistry` |
| R5 | Detector de ⇧⇧ disparando sem querer | Janela curta, cancela se outra tecla vier no meio, ajuste para desligar |
| R6 | Prever bytes sem rodar o PyCharm (seção 5.3) | A fixture só nasce do oráculo real. Até lá, o teste fica marcado como pendente |
| R7 | O arquivo gravado não é módulo Python válido (trechos sem `class`) e, aberto na árvore, parece "quebrado" | Fora do escopo. Registrar como pendência para o codegen |
| R8 | Árvore e escrita em arquivo ampliam a superfície do motor | Mesmas travas do `codegen.save`: raiz fixa, `_dentro_de`, sem seguir link simbólico e validação de nome. Teste de segurança |

## 9. Validação com usuário (plano curto)

- **Decisão apoiada**: P0 está pronto para virar padrão?
- **Método**: teste moderado com 5 pessoas que usam o PyCharm no dia a dia e escrevem Page Object. O dono é uma delas, mas não a única. Recrutar 7 para garantir 5; o número é heurística de autor, não norma.
- **Tarefas**:
  1. Colar um locator copiado do Slack ou do Jira (com NBSP) e salvar.
  2. Achar o método `click_botao_continuar` sem mouse.
  3. Voltar ao ponto anterior.
  4. Esconder todos os painéis e voltar.
  5. Abrir o flow exportado ontem.
- **Registro**: hesitações, atalho tentado primeiro e diferença de bytes depois de salvar.
- **O que o estudo não responde**: preferência estética de fonte e cor; isso é decisão do dono (R1).

## Decisões pendentes do dono

1. Fonte e cores do PyCharm como padrão do editor ou como opção (R1, adendo à ADR 0002).
2. ⌘E: Arquivos Recentes (como o PyCharm) ou Espelho (como hoje).
3. Remover espaços no fim das linhas ao salvar (G19).
4. A árvore Projeto mostra também `Specs/` e `Relatórios/`, ou só código (pages, locators, flows)?
5. Versão: P0 muda o editor de forma visível. Sobe minor ou major? A regra da casa diz que redesenho drástico sobe major; isto é Suposição de que P0 sozinho não é drástico.

## Fontes

JetBrains (consultadas em 2026-11-04):
- Ajuda do PyCharm:
  - [Font](https://www.jetbrains.com/help/pycharm/settings-editor-font.html)
  - [Encoding](https://www.jetbrains.com/help/pycharm/encoding.html)
  - [Line separators](https://www.jetbrains.com/help/pycharm/configuring-line-endings-and-line-separators.html)
  - [Editor › General](https://www.jetbrains.com/help/pycharm/settings-editor-general.html)
  - [Appearance](https://www.jetbrains.com/help/pycharm/settings-editor-appearance.html)
  - [Tool windows](https://www.jetbrains.com/help/pycharm/tool-windows.html)
  - [Project tool window](https://www.jetbrains.com/help/pycharm/project-tool-window.html)
  - [Speed search](https://www.jetbrains.com/help/pycharm/speed-search-in-the-tool-windows.html)
  - [Search Everywhere](https://www.jetbrains.com/help/pycharm/searching-everywhere.html)
  - [Source code navigation](https://www.jetbrains.com/help/pycharm/navigating-through-the-source-code.html)
  - [Guided tour (UI)](https://www.jetbrains.com/help/pycharm/guided-tour-around-the-user-interface.html)
  - [Indexing](https://www.jetbrains.com/help/pycharm/indexing.html)
- Ajuda do Rider: [Power Save Mode](https://www.jetbrains.com/help/rider/Power_save_mode.html)
- IntelliJ Platform:
  - [UI Guidelines, Typography](https://plugins.jetbrains.com/docs/intellij/typography.html)
  - [SDK, Documents](https://plugins.jetbrains.com/docs/intellij/documents.html)
- [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) (OFL-1.1, v2.304)

Código, em `github.com/JetBrains/intellij-community`, commit `a525578a`:
- `platform/editor-ui-api/src/com/intellij/openapi/editor/colors/FontPreferences.java`
- `platform/ide-core-impl/src/com/intellij/openapi/editor/ex/EditorSettingsExternalizable.java`
- `platform/platform-impl/src/com/intellij/openapi/editor/impl/EditorSettingsState.kt`
- `platform/analysis-impl/src/com/intellij/codeInsight/CodeInsightSettings.java`
- `platform/platform-impl/src/com/intellij/openapi/editor/impl/view/SpecialCharacterFragment.java`
- `platform/platform-impl/resources/intellij.platform.ide.impl.xml`
- `platform/platform-resources/src/keymaps/Mac OS X 10.5+.xml` e `$default.xml`
- `platform/platform-impl/src/com/intellij/openapi/keymap/impl/MacOSDefaultKeymap.kt`
- `platform/platform-resources/src/themes/islands/IslandSchemeDark.xml`
- `platform/platform-resources/src/themes/expUI/expUI_darkScheme.xml`
- `python/python-code-insight/resources/colorSchemes/PythonDarcula.xml`

Apple, Unicode e Python:
- [NSTextView](https://developer.apple.com/documentation/appkit/nstextview): `smartInsertDeleteEnabled`, `isAutomaticTextReplacementEnabled`, `inlinePredictionType` e `isAutomaticTextCompletionEnabled`, lidos pela API JSON da documentação
- [UAX #29](https://www.unicode.org/reports/tr29/), regra GB3
- [Python `open()`](https://docs.python.org/3/library/functions.html#open)

Captura enviada pelo dono: tela vazia do PyCharm (New UI, escuro), descrita no pedido.

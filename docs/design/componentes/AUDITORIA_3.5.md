# Auditoria de componentes contra o contrato (3.5)

Base: `b751498` (3.5.0) + CMP-1. Data: 2026-10-11. Item CMP-3.
Escopo: componentes reutilizáveis de `apps/MoBaile/Sources/MoBaile/Views`, fora os três que já seguem o contrato (paleta de comandos, faixa do motor e `DiagnosticCard`). Telas inteiras (`ContentView`, `ReportView`, `HTTPInspectorView`, sheets, ajustes) ficam de fora, salvo quando um achado de movimento mora nelas.
Contrato: [README.md](README.md), adaptado de cult-ui para SwiftUI.

Só relatório. Nenhum código foi mudado neste item.

## Método

- Inventário por regex num script de leitura, com cada achado conferido no código. Os números de linha são do arquivo em `b751498` mais CMP-1.
- **Cor crua**: `Color(hex:)`, `Color(r:…)`, `Color.black`, `Color.white` e `Color.primary` na view. Também conta opacidade literal aplicada a um token.
- **Tamanho cru**: número literal em `.system(size:)`, `frame`, `padding`, `spacing` maior que 0, `cornerRadius`, `lineWidth`, `radius` e `DSFont.mono(n)`. Literal que já é igual a um token (`12` = `Spacing.s5`) também conta, porque o token existe e não foi usado.
- **Movimento reduzido**: toda `withAnimation`, `.animation` e `.transition`. Só opacidade e `Motion.crossfade` contam como OK sem ler a preferência.
- **a11y**: papel, rótulo, alvo mínimo (no macOS: 20 pt para controle pequeno, 24 pt para regular, conforme `DesignMetrics.Heights.control*`) e foco. A leitura é estática: nada foi testado com VoiceOver nem com Controle Total por Teclado.
- Rótulos: **Verificado** (lido no código nesta sessão) e **Inferido** (depende de rodar).

## Resumo

| Medida | Contagem |
| --- | --- |
| Componentes auditados | 43 |
| Sem `#Preview` | 43 de 43. Nenhum arquivo de `Views` tinha preview antes do CMP-1 |
| Com cor crua | 8: `DeviceBezel`, `ScreenCanvas`, `PaletteCard`, `PalettePreview`, `SplashView` e três botões da toolbar com `Color.primary`. Mais 3 com opacidade literal sobre token: `TypeChip`, `BarIconButtonStyle`, `PlainTextButtonStyle` |
| Com tamanho cru | 30 componentes, 193 linhas. `PalettePreview` sozinho tem 53 |
| Animação que ignora Reduzir movimento | 2 componentes, 3 pontos: `HierarchyRow`, `ScreenCanvas` ×2. Fora da tabela, a tela `PageObjectsView` tem mais 1 |
| Respeitam Reduzir movimento | `ProgressBar`, `SplashView`. `PaletteCard` e `WorkspacePane` só fazem crossfade |
| Com achado de a11y | 12 |
| Prioridade | P1: 7 · P2: 18 · P3: 18 |

Prioridade:

- **P1**: quebra C-12 (movimento) ou C-15 (alvo ou foco) num componente muito usado, ou é a base do design system sem preview. Corrigir primeiro.
- **P2**: tokens e preview em componente compartilhado.
- **P3**: componente de uso único, arte de marca ou mock, onde o literal é a própria peça.

## Tabela

`Views/` omitido nos caminhos. "—" quer dizer sem achado.

### Design system (`DesignSystem/`)

| Componente | Arquivo:linha | Falta #Preview | Cor/tamanho cru | Reduce motion | a11y | Prior. |
| --- | --- | --- | --- | --- | --- | --- |
| StatusIndicator | DesignSystem/Indicators.swift:8 | sim | tamanho: :22 `spacing: 4`, :24 `.system(size: 10)`, :28 `mono(11)` | sem animação | — (forma, cor e palavra; rótulo por extenso) | P1 (24 usos) |
| TypeChip | DesignSystem/Indicators.swift:78 | sim | :85 `.system(size: 9.5)`; opacidade :88 `0.16` | sem animação | — | P2 |
| CountBadge | DesignSystem/Indicators.swift:107 | sim | — | sem animação | só o número ("12"), sem dizer o quê | P2 |
| ProgressBar | DesignSystem/Indicators.swift:121 | sim | :139 `height: 5` | OK (:136 `Motion.smooth(reduceMotion:)`) | — | P2 |
| AccessoryBar | DesignSystem/Bars.swift:8 | sim | :14 `spacing: 8`, :18 `padding 12`, :22 `height: 1` | sem animação | — | P2 |
| PaneHeader | DesignSystem/Bars.swift:27 | sim | :34 `spacing: 6`, :42 `padding 12` | sem animação | — | P2 |
| DetailHeader | DesignSystem/Bars.swift:56 | sim | :69, :71 `.system(size: 12)`, :95, :96, :98 | sem animação | "Copiado" troca o rótulo mas não é anunciado | P2 |
| BarIconButton | DesignSystem/Bars.swift:104 | sim | :114 `.system(size: 12.5)`, :115 `minWidth: 24, minHeight: 22` | sem animação | — (rótulo e tooltip) | P2 |
| BarIconButtonStyle | DesignSystem/Bars.swift:124 | sim | :142 `padding 4`; opacidade :146 `0.38` | sem animação | Inferido: estilo próprio sem anel de foco desenhado; com Controle Total por Teclado o foco pode não aparecer | P1 |
| PlainTextButtonStyle | DesignSystem/Bars.swift:155 | sim | :175 `padding 6`, :176 `16/20/24` em vez de `Heights.control*`; opacidade :181 `0.42` | sem animação | Inferido: mesmo caso de anel de foco | P1 |
| DSSearchField | DesignSystem/Bars.swift:188 | sim | :198, :200, :213 `.system(size: 12)`, :225, :226, :232 | sem animação | botão Limpar (:209–217) com glifo de 12 pt e sem `frame` mínimo: alvo abaixo de 20 pt | P1 |
| EmptyState | DesignSystem/Content.swift:5 | sim | :29 `.system(size: 20/28)`, :33 `.system(size: 13)`, :42 `maxWidth: 340`, :47 `padding 8` | sem animação | título sem `.isHeader` | P1 (21 usos) |
| InlineError | DesignSystem/Content.swift:57 | sim | :67 `spacing: 6`, :80, :81 | sem animação | — | P2 |
| DSCard | DesignSystem/Content.swift:89 | sim | — (linha de 0,5/1 pt em :101) | sem animação | — | P3 |
| CodeBlock | DesignSystem/Content.swift:113 | sim | :120 `mono(11)`, :125, :126 `cornerRadius: 8`, :127 | sem animação | — (texto selecionável) | P2 |
| KeyValueGrid | DesignSystem/Content.swift:132 | sim | :143, :144, :145 `minWidth: 90`, :149, :150, :154 | sem animação | — | P2 |

### Espelho, hierarquia e editor

| Componente | Arquivo:linha | Falta #Preview | Cor/tamanho cru | Reduce motion | a11y | Prior. |
| --- | --- | --- | --- | --- | --- | --- |
| DeviceBezel | Mirror/DeviceBezel.swift:14 | sim | cor: :60 `Color.black.opacity(0.2)`, :62 sombra `Color(r: 10, g: 12, b: 40, 0.22)`, `radius: 20` | sem animação | — (decorativo) | P2 |
| ScreenCanvas | Mirror/ScreenCanvas.swift:16 | sim | cor: :89 `Color.white`, :90 `Color.black.opacity(0.2)`; tamanho: :52, :64, :65, :67, :68, :77 `mono(9.5)`, :79–81, :91 `26×26` | **quebra**: :73 `.easeOut(0.12)` no realce; :139 `withAnimation(.easeOut(0.3))` com `scaleEffect` 0,6→1,6 no clique | clique (:117) sem `accessibilityAction`; a árvore da hierarquia é a alternativa | P1 |
| MirrorRefreshButton | Mirror/MirrorRefreshButton.swift:13 | sim | — | sem animação | — | P3 |
| CorrelationPopover | Mirror/MirrorRefreshButton.swift:54 | sim | :61, :72 `mono(10.5)`, :76, :78 `cornerRadius: 8`, :91, :92 `width: 300` | sem animação | título sem `.isHeader` | P3 |
| HierarchyRow | Hierarchy/HierarchyTreeView.swift:207 | sim | :216 `spacing: 5`, :222 `.system(size: 9)`, :225 `12×16`, :231 | **quebra**: :224 `Motion.snappy()` sem `reduceMotion` (gira o chevron com quique) | chevron (:220–229) com alvo de 12×16 pt | P1 |
| AttributesPanel | Hierarchy/AttributesPanel.swift:67 | sim | :73, :94 `width: 64`, :102 `mono(11)`, :114–116 | sem animação | — | P2 |
| CodeEditorPane | Workspace/DualEditorPane.swift:150 | sim | :163, :164, :166, :173, :210, :211, :213 | sem animação | — | P2 |
| CodeEditorView | Workspace/CodeEditorView.swift:5 | sim (NSViewRepresentable) | — (cores vêm do `PythonHighlighter`) | sem animação | Inferido: a11y do `NSTextView` nativo | P3 |

### Janela e toolbar

| Componente | Arquivo:linha | Falta #Preview | Cor/tamanho cru | Reduce motion | a11y | Prior. |
| --- | --- | --- | --- | --- | --- | --- |
| StatusBar | MainWindow/StatusBar.swift:9 | sim | :24 `spacing: 12`, :47, :51, :54 | sem animação | — (explicação por serviço, D11) | P2 |
| SectionTitleView | MainWindow/UnifiedToolbar.swift:50 | sim | :66 `padding 6` | sem animação | — | P3 |
| DeviceMenu | MainWindow/UnifiedToolbar.swift:78 | sim | — | sem animação | — | P3 |
| InteractionModePicker | MainWindow/UnifiedToolbar.swift:143 | sim | — | sem animação | — | P3 |
| PassiveCaptureButton | MainWindow/UnifiedToolbar.swift:166 | sim | cor: :179 `Color.primary` | sem animação | estado só pelo rótulo; sem `accessibilityValue`, ao contrário de `ScrcpyButton` | P3 |
| ScreenRecordingButton | MainWindow/UnifiedToolbar.swift:207 | sim | cor: :220 `Color.primary` | sem animação | mesmo caso do anterior | P3 |
| ScrcpyButton | MainWindow/UnifiedToolbar.swift:228 | sim | cor: :240 `Color.primary` | sem animação | — | P3 |
| RunAutomationButton | MainWindow/UnifiedToolbar.swift:254 | sim | — | sem animação | — (motivo no `.help`) | P2 |
| HierarchySearchButton | MainWindow/UnifiedToolbar.swift:294 | sim | — | sem animação | — | P3 |
| InspectorToggleButton | MainWindow/UnifiedToolbar.swift:313 | sim | — | sem animação | — | P3 |
| PaneDivider (privado) | MainWindow/ContentView.swift:241 | sim | :254 `width: 1`, :255 `padding 3` | sem animação | escondido do VoiceOver, sem redimensionar por teclado; ⌥1, ⌥2 e ⌥⌘F são a alternativa | P3 |

### Outros compartilhados

| Componente | Arquivo:linha | Falta #Preview | Cor/tamanho cru | Reduce motion | a11y | Prior. |
| --- | --- | --- | --- | --- | --- | --- |
| DetailTabPicker | Network/RequestDetailView.swift:62 | sim | — | sem animação | — (Picker nativo com rótulo) | P3 |
| NoDeviceView | EmptyState/DiagnosticCard.swift:249 | sim (só o cartão tem preview) | 16 linhas: :259 `cornerRadius: 22`, :260 `dash: [5, 4]`, :261 `92×184`, :264 `.system(size: 26)`, :267, :279 `maxWidth: 440`, :281, :282, :284, :289, :304, :306–308, :321, :354 | sem animação | — | P2 |
| ReportSummaryBar | Report/ReportView.swift:223 | sim | :231–233, :270–272 | sem animação | — | P2 |
| ReportResultsTable | Report/ReportView.swift:316 | sim | :353, :361, :376, :416, :423, :433 | sem animação | — | P2 |
| ReportPrintImage | Report/ReportDetailPane.swift:209 | sim | :220 | sem animação | — | P3 |
| PaletteCard | Settings/PaletteGallery.swift:45 | sim | cor: :83 `Color(hex: amostra.hex)` (é a amostra, aceitável), :84 `Color.black.opacity(0.14)`; tamanho: 16 linhas (:56–59, :79, :81, :82, :84, :85, :87 `.system(size: 9)`, :91, :101, :103, :105, :110, :119) | OK (:70 só crossfade) | — | P3 |
| PalettePreview | Settings/PaletteGallery.swift:135 | sim | cor: :150, :165, :244, :264; tamanho: 53 linhas (:148–:282) | sem animação | — (miniatura decorativa) | P3 |
| SplashView | Splash/SplashWindow.swift:132 | sim | cor: :138 `#141543`, :162, :164 `#C2456E`, :199 degradê; tamanho: :143, :148, :153 `.system(size: 48)`, :157, :169, :170, :172, :175, :179 `640×380` | OK (:166 lê `reduceMotion`; :185 só opacidade) | — | P3 |

### Fora da tabela

- `PageObjectsView` (tela), `Workspace/DualEditorPane.swift:111`: `withAnimation(Motion.smooth())` ao alternar Lado a lado, sem ler `reduceMotion`. A correção é de uma linha: ler `@Environment(\.accessibilityReduceMotion)` e passar o valor ao `Motion.smooth(reduceMotion:)`. P1.
- `WorkspacePane` (`Workspace/WorkspaceColumn.swift:19–28`) e `ContentView.swift:52` só fazem crossfade. OK.

## Recomendações, em ordem

1. **C-12, 3 pontos e 1 linha cada**: `HierarchyRow:224`, `ScreenCanvas:73` e `:139`, `DualEditorPane:111`. Com Reduzir movimento, o anel de clique do espelho deve só esmaecer, sem `scaleEffect`.
2. **C-15**:
   - alvo do chevron da árvore e do Limpar da busca com `frame(minWidth:minHeight:)` em `Heights.controlSmall`;
   - conferir com Controle Total por Teclado se `BarIconButtonStyle` e `PlainTextButtonStyle` mostram foco. Se não mostrarem, desenhar o anel com `theme.focusRing`, como o `DSSearchField` já faz.
3. **#Preview na base do design system**: `StatusIndicator`, `EmptyState`, `InlineError` e `ProgressBar` primeiro, com os cinco `DaemonState` e o modo compacto. São os mais usados.
4. **Tokens**:
   - literais iguais a `Spacing.s*` viram o token, sem mudança visual;
   - fonte de símbolo vai para `DSFont.Symbol`;
   - as opacidades de desabilitado (0,38 e 0,42) viram um token só. O D6 da 3.5 já usa 0,42 na paleta.
5. **P3**: `PalettePreview` e `SplashView` são arte e miniatura, e o literal é a peça. Registrar como desvio aceito na doc deles em vez de tokenizar.

## Fora do escopo e não verificado

- Nenhum teste com VoiceOver, Controle Total por Teclado, Aumentar contraste ou Reduzir transparência. Os achados de foco estão como Inferido.
- Contraste não foi recalculado aqui. O teste da 3.5 já cobre `labelTertiary` (D10).
- Telas inteiras e sheets (`FlowRunnerSheet` com 28 literais, `StructureSheet` com 12, `ReportCardInspector` com 10, `ReportImportSheet` com 9) não são componentes reutilizáveis, então ficaram fora da tabela. Os números vêm do mesmo script.
- Revisão feita pelo mesmo modelo que escreveu o CMP-1: é uma leitura independente em contexto, não validação externa.

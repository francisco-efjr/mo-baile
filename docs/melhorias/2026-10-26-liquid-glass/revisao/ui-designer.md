# Spec: adoção do Liquid Glass real (macOS 26) no Mo baile nativo

Status: **rascunho** · Plataforma: macOS 14+ (app `apps/MoBaile`, SwiftUI) · Sistema: "Mo baile · macOS 27 / Liquid Glass" (`docs/design/design-system/`, ADR `docs/adr/0002-redesenho-liquid-glass.md`) · Direção: sistema existente · Rótulos: **Verificado** · **Inferido** · **Suposição**

Brief: trocar a imitação de vidro por Liquid Glass do macOS 26 só onde o design system já manda ter vidro (navegação e controles flutuantes), com fallback igual ao de hoje no macOS 14 e 15, para quem usa o Mo baile todo dia num Mac com macOS 26 · Superfície: **Operate**

Autor: especialista `ux-ui-design:ui-designer` (brain-of-agent), 2026-10-26. Escopo: diagnóstico e especificação. Nenhum código foi alterado. Nada foi compilado, renderizado nem testado.

---

## 0. Resumo em cinco linhas

1. Quase não há imitação de vidro no app. **Verificado:** o único material translúcido desenhado à mão é o da paleta de comandos (`CommandPaletteView.swift:101-106`). O resto são preenchimentos `fill*`/`bg*` de conteúdo, que pela regra do design system não podem virar vidro.
2. A maior parte do vidro do macOS 26 **o sistema já desenha**: a toolbar, a sidebar com `.listStyle(.sidebar)`, a busca `.searchable`, os popovers, as sheets, os alertas e os menus. O trabalho é **não pintar por cima** do vidro. Um ponto pinta: a sidebar com paleta alternativa (`AppSidebar.swift:76-77`).
3. Há três riscos reais de vidro sobre vidro ou de cápsula indevida, todos na toolbar e na sidebar: o título em `ToolbarItem` (`UnifiedToolbar.swift:22-26`), o botão Rodar `.glassProminent` dentro do vidro compartilhado da toolbar (`UnifiedToolbar.swift:38-40, 247`) e qualquer vidro posto no item Ambiente do rodapé da sidebar (`AppSidebar.swift:197-251`).
4. **Não há como fazer morphing de verdade entre a cápsula do Ambiente na Início e o item Ambiente da sidebar.** Os dois estão em colunas diferentes da `NavigationSplitView`, e o item da sidebar já está dentro do vidro do sistema. Os pontos legítimos de transição de vidro são a entrada e a saída da paleta de comandos e, se o dono aprovar, os controles do espelho.
5. Proposta: um arquivo `Views/DesignSystem/Glass.swift` com `mbGlass(_:in:)`, `mbGlassButton(_:ativo:)`, `MBGlassGroup`, `mbGlassID`, `mbGlassTransition` e os ajustes de toolbar e rolagem. **Só esse arquivo** pode ter `#available(macOS 26, *)`, e um teste que lê as fontes, como o de `NoDeviceTests.swift:49-54`, barra a regra.

---

## 1. Reutiliza

- Tokens: `ThemeTokens` (`Theme/DesignTokens.swift:13-104`): `accent`, `onAccent`, `accentText`, `bgContent`, `bgControl`, `bgWindow`, `bgSidebar`, `separator`, `separatorStrong`, `fill*`, `highContrast`. Métricas: `DesignMetrics.Radius.card/popover/menu` (`DesignTokens.swift:177-191`) e `DesignMetrics.Shadow` (`:269-272`). Derivados: `floatingScrim` e `floatingShadow` (`:316-323`). Movimento: `Motion.smooth/snappy(reduceMotion:)` e `Motion.crossfade` (`:331-342`).
- Componente existente que já é vidro real: `prominentGlassButton(_:)` (`UnifiedToolbar.swift:312-325`). Ele vira `mbGlassButton(.destaque, ativo:)`.
- Regras do design system: `tokens/materials.css` (cabeçalho: "só para a camada de navegação e controles flutuantes. Nunca vidro sobre vidro; sobre vidro, separar com --fill-*"), `readme.md:56` (Materiais) e `:62` (Transparência e desfoque), e ADR 0002 linha 28 ("O único uso explícito é o botão Rodar").
- APIs do SDK 26.2 cuja **existência e assinatura foram Verificadas** no `.swiftinterface` (`MacOSX26.2.sdk`, SwiftUI e SwiftUICore):
  - `glassEffect(_:in:)`, com `Glass.regular`, `.clear`, `.identity`, `.tint(_:)` e `.interactive(_:)`;
  - `GlassEffectContainer(spacing:content:)`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)` e `glassEffectTransition(_:)` (`.matchedGeometry`, `.materialize`);
  - `buttonStyle(.glass)` e `buttonStyle(.glassProminent)`;
  - `sharedBackgroundVisibility(_:)` em `ToolbarContent`, `safeAreaBar(edge:)`, `backgroundExtensionEffect()`, `scrollEdgeEffectStyle(_:for:)` (`.automatic`, `.hard`, `.soft`) e `containerBackground(_:for:)`.

  O **comportamento visual** de todas essas APIs é Inferido: nada foi renderizado.

---

## 2. Inventário e decisão por superfície

Legenda da camada: **N** é navegação ou controle flutuante, **C** é conteúdo. Decisões possíveis: **vidro real** (com a API), **sistema já faz** (no macOS 26, tirar ou não pôr fundo à mão) e **não entra** (com o motivo).

### 2.1 Janela, toolbar e sidebar (camada de navegação)

| arquivo:linha | Componente | O que faz hoje | Camada | Decisão | Rótulo |
| --- | --- | --- | --- | --- | --- |
| `App/MoBaileApp.swift:22,37` | Janela `Window` + `.windowToolbarStyle(.unified)` | Toolbar unificada do sistema | N | **Sistema já faz.** Nada a mudar. | Verificado (código) / Inferido (visual) |
| `Views/MainWindow/ContentView.swift:22` | `NavigationSplitView` | Colunas sidebar e detalhe | N | **Sistema já faz** a sidebar flutuante de vidro no 26. | Inferido |
| `Views/MainWindow/ContentView.swift:60` + `UnifiedToolbar.swift:17-49` | `MainToolbar` | Itens nativos, `ToolbarSpacer(.flexible)` só no 26 (`:30-32`) | N | **Sistema já faz.** Os itens recebem vidro e agrupamento automáticos. | Inferido |
| `UnifiedToolbar.swift:22-26` | `SectionTitleView` como `ToolbarItem(.navigation)` | Título e subtítulo desenhados (`:55-75`) | N | **Ajuste no 26:** `sharedBackgroundVisibility(.hidden)` no item, para o título não ganhar cápsula de vidro. Risco descrito em 3.1. | Inferido |
| `UnifiedToolbar.swift:27-29, 83-113` | `DeviceMenu` (pop-up) | `Menu` nativo com ícone colorido | N | **Sistema já faz** (cápsula de vidro do item). | Inferido |
| `UnifiedToolbar.swift:33-37` | Grupo Gravar do Aparelho, Gravar a Tela e 60 FPS | `ToolbarItemGroup`; o 60 FPS só aparece no Android (`:216`) | N | **Sistema já faz** o vidro compartilhado e a animação quando o item entra ou sai. | Inferido |
| `UnifiedToolbar.swift:38-40, 236-250, 312-325` | `RunAutomationButton` + `prominentGlassButton` | **Já é vidro real:** `.glassProminent` no 26 e `.borderedProminent` antes; sem tom quando inativo (D2) | N | **Vidro real, mantém.** Migrar para `mbGlassButton(.destaque, ativo:)`, com `foregroundStyle(theme.onAccent)` (ver 4.2) e, se a captura mostrar cápsula dupla, `sharedBackgroundVisibility(.hidden)` no `ToolbarItem`. | Verificado (código) / Inferido (cápsula dupla) |
| `UnifiedToolbar.swift:41-48, 276-310` | Buscar na Hierarquia e Inspector | Botões nativos | N | **Sistema já faz.** | Inferido |
| `ContentView.swift:364-391` | `.searchable(placement: .toolbar)` em Rede, Analytics e Relatório | Campo de busca nativo | N | **Sistema já faz.** A troca entre o botão de busca e o campo é animada pela toolbar. | Inferido |
| `ContentView.swift:418-429` | `ToolbarTitle` (`.toolbar(removing: .title)` no 15+) | Tira o título nativo | N | Mantém. | Verificado (código) |
| `Views/MainWindow/AppSidebar.swift:73` | `List.listStyle(.sidebar)` | Sidebar nativa | N | **Sistema já faz** o vidro da sidebar no 26. | Inferido |
| `AppSidebar.swift:74-77` | Fundo da sidebar | Na Praia: `Color.clear` + `.automatic` (vidro do sistema). **Com paleta:** `.scrollContentBackground(.hidden)` + `.background(theme.bgSidebar)` **opaco** | N | Praia: **sistema já faz**. Paletas: **decisão pendente D-1**. A recomendação é manter o sólido, encapsulado em `mbSidebarBackground()`. | Verificado (código) |
| `AppSidebar.swift:78-83` | `safeAreaInset(.bottom)` com Ambiente + barra inferior | Rodapé fixo dentro da coluna | N | **Não entra em vidro**: já está dentro do vidro da sidebar. No 26, avaliar `safeAreaBar(edge: .bottom)` para o efeito de borda da rolagem passar por baixo do rodapé (D-5). | Inferido |
| `AppSidebar.swift:197-251` (`:236-239`) | `SidebarEnvironmentItem` | Botão próprio com fundo `selection`/`fillSecondary` em `RoundedRectangle(sidebarItem)` | N (dentro de vidro) | **Não entra em vidro**, porque seria vidro sobre vidro. Continua com preenchimento, como manda o `materials.css`. Conferir na captura se o raio e a cor da seleção batem com os da seleção nativa da `List` no 26 (a nativa usa o `AccentColor` fixo, segundo o ADR 0002 no adendo 3.1.0). | Verificado (código) / Inferido (paridade) |
| `AppSidebar.swift:227` | Contagem amarela em `Capsule` | `warningFill` + texto `Color.black.opacity(0.78)` (`:224`) | N (dentro de vidro) | **Não entra.** É um badge de estado. | Verificado |
| `AppSidebar.swift:254-285` | `SidebarBottomBar` | Separador no topo (`:284`), `BarIconButtonStyle`, `StatusIndicator` | N (dentro de vidro) | **Não entra.** Os preenchimentos de hover sobre o vidro estão corretos. | Verificado |

### 2.2 Superfícies flutuantes próprias

| arquivo:linha | Componente | O que faz hoje | Camada | Decisão | Rótulo |
| --- | --- | --- | --- | --- | --- |
| `Views/CommandPalette/CommandPaletteView.swift:101` | Fundo do painel | `.regularMaterial` em `RoundedRectangle(card)` | N (flutuante) | **Vidro real:** `mbGlass(.flutuante, in: RoundedRectangle(cornerRadius: Radius.card))`, que no 26 vira `glassEffect(.regular, in:)`. | Verificado (código) |
| `CommandPaletteView.swift:102-105` | Borda | `strokeBorder(separatorStrong, hairline/2)` | N | No 26 **sai**, porque o vidro desenha a própria borda. Fica no fallback 14/15 e no Aumentar contraste. | Inferido |
| `CommandPaletteView.swift:106` | Sombra | `shadow(floatingShadow, 24, y 10)` | N | No 26 **sai** (o vidro tem sombra própria). Fica no fallback. | Inferido |
| `CommandPaletteView.swift:13-31` (`:21`, `:29`) | Overlay, véu e transição | `floatingScrim` + `.transition(.opacity)` | N | Véu **mantém**: ele garante o contraste do texto sobre o vidro (ver 4.3). Transição no 26: `mbGlassTransition(.materialize)`; com Reduzir movimento, `.opacity`. | Inferido |
| `CommandPaletteView.swift:96, 199, 370-373` | Aviso (`warningTint`), rodapé (`fillQuaternary`), linha escolhida (`accent`/`fillPrimary`) | Preenchimentos dentro do painel | N (dentro de vidro) | **Não entra.** É o preenchimento sobre vidro que o `materials.css` pede. | Verificado |
| `Views/Mirror/MirrorColumn.swift:46`, `Views/Network/HTTPInspectorView.swift:135`, `Views/Home/HomeDaily.swift:543` | Popovers (Correlação, Diagnóstico de tráfego, Ver Tudo) | `.popover` nativo | N | **Sistema já faz.** Não pôr fundo opaco no conteúdo do popover. Hoje nenhum põe: `MirrorRefreshButton.swift:61-92` só tem um `fillTertiary` interno em `:78`. | Verificado (código) |
| `ContentView.swift:66-75`, `Views/Report/ReportView.swift:58` | Sheets (Estrutura, Execução, Importar) | `.sheet` nativo | N | **Sistema já faz.** O conteúdo interno das sheets é conteúdo: terminal em `FlowRunnerSheet.swift:160-161`, tabela em `StructureSheet.swift:52-53`. | Inferido |
| `ContentView.swift:76-88` | Alertas de Limpar | `.alert` nativo | N | **Sistema já faz.** | Inferido |
| `Views/Splash/SplashWindow.swift:130-139, 208-212, 226` | Splash: `NSWindow` sem borda e transparente; trilho da barra `Color.white.opacity(0.55)` | Ilustração da marca | C (marca) | **Não entra.** É o único momento ilustrado do app (`readme.md`, Fundos). Vidro não traz função ali, e o trilho translúcido sobre a ilustração é desenho de marca. | Verificado (código) |

### 2.3 Conteúdo (não entra em vidro)

Motivo comum de todas as linhas: o conteúdo nunca usa vidro (`materials.css`, `readme.md:56`, HIG citado em `apple-e-plataformas.md`). Nesses casos o vidro deixaria o texto denso menos legível e acabaria com a hierarquia entre as camadas.

| arquivo:linha | Componente | O que faz hoje | Motivo específico |
| --- | --- | --- | --- |
| `Views/Home/HomeDaily.swift:89-124` (`:115`) | `HomeEnvironmentPill` (cápsula do Ambiente na Início) | `fillSecondary`/`fillPrimary` em `Capsule`, `buttonStyle(.plain)` | É controle, mas fica dentro do conteúdo que rola, sobre `bgContent` liso (`HomeView.swift:20`). Vidro sobre fundo liso só vira uma cápsula cinza com borda. É a **decisão pendente D-3**. |
| `Views/Home/HomeDaily.swift:197, 228, 446, 510-511, 629`; `HomeView.swift:156, 166-171`; `HomeFirstRun.swift:83-85, 196, 218-221` | Linhas de alvo, chips de plataforma, cartões de área, recentes, próximo passo | Preenchimentos e aros | Cartões e linhas de conteúdo. |
| `HomeDaily.swift:48, 133, 464` (layouts em `:699`, `:742`) | `HomePairLayout`, `HomeColumnsLayout` | Layouts | Sem superfície própria. |
| `Views/Environment/EnvironmentView.swift:21, 216-222, 279, 301-306` | Tela Ambiente | `bgContent`, aro `warningFill`, comando, aro do destaque | Conteúdo. |
| `Views/DesignSystem/Content.swift:82, 97-102, 126` | `InlineError`, `DSCard` (`dsCard`), `CodeBlock` | `dangerTint`, `bgGroup` + borda, `bgContentAlt` | Conteúdo, por contrato ("Cartões: fundo `--bg-group`… sem sombra"). |
| `Views/DesignSystem/Bars.swift:8-24` (`:21-22`) | `AccessoryBar` | `bgContent` + separador, logo abaixo da toolbar | **Não entra:** vidro aqui empilharia duas faixas de vidro, a da toolbar e a da barra (vidro sobre vidro na vertical). Avaliar `safeAreaBar` no 26 (D-5). |
| `Bars.swift:98`, `Bars.swift:143-145, 177-180`, `Bars.swift:228-234` | `DetailHeader`, `BarIconButtonStyle`, `PlainTextButtonStyle`, `DSSearchField` | Separador; cápsula de hover; cápsula `fillSecondary`/`bgField` + anel de foco | Controles da camada de conteúdo, com hover por preenchimento como o design system descreve. |
| `Views/DesignSystem/CorrelationChip.swift:25` | `CorrelationChip` | `accentText.opacity(0.10)` em `Capsule` | Chip de filtro dentro do conteúdo (escopo da tabela, `HTTPInspectorView.swift:188`; `AnalyticsInspectorView.swift:19`). |
| `Views/DesignSystem/Indicators.swift:88, 132-136` | `TypeChip`, `ProgressBar` | Preenchimentos | Indicadores. |
| `Views/DesignSystem/AdaptivePair.swift:37, 54` | `AdaptivePair` | Separadores | Layout. |
| `Views/DesignSystem/VerticalSplit.swift:36-45` | `VerticalSplit` | Divisória própria | Layout. |
| `Views/MainWindow/StatusBar.swift:52-54` | `StatusBar` | `bgContentAlt` + separador | Barra de status informativa, que nos apps do sistema não é vidro. |
| `Views/MainWindow/EngineStatusBanner.swift:146-151` | Faixa do motor | `warningTint`/`dangerTint` | Estado de erro precisa de fundo sólido e tingido para ser lido. |
| `ContentView.swift:53, 233`; `WorkspaceColumn.swift:34`; `AttributesPanel.swift:53`; `HTTPInspectorView.swift:46`; `AnalyticsInspectorView.swift:41`; `ReportView.swift:52, 266`; `DualEditorPane.swift:62, 135-136, 212` | Fundos de coluna, inspector, editores e tabelas | `bgContent` | Conteúdo. Mantêm o fundo opaco, que é o que a toolbar de vidro amostra por trás. |
| `ReportView.swift:53, 428, 484`; `HTTPInspectorView.swift:258`; `AnalyticsInspectorView.swift:81` | `EmptyState` em `.overlay` | Estado vazio | Conteúdo. |
| `Views/Mirror/MirrorColumn.swift:35-57` | Coluna do espelho e linha Atualizar + Correlação | `bgContentAlt`; botões `.controlSize(.small)` | Hoje é conteúdo. Pode virar grupo flutuante (**D-4**). |
| `Views/Mirror/DeviceBezel.swift:56-75`; `ScreenCanvas.swift:64-70, 81, 88-90` | Moldura do aparelho, realce do elemento, rótulo, toque | Sombra e aros próprios | Objeto desenhado e mídia. |
| `Views/EmptyState/DiagnosticCard.swift:112-115, 259-262, 311` | Cartão de diagnóstico | Aro, tracejado | Conteúdo. |
| `Views/Report/ReportCardEditor.swift:50, 70-73`; `ReportDetailPane.swift:225`; `ReportBug.swift:258` | Editor de card, prints, imagem do bug | Campos e `Color.white` (imagem exportada) | Conteúdo. `ReportBug` gera imagem para a área de transferência. |
| `Views/Settings/PaletteGallery.swift:31, 82-84, 121-125, 150, 184-282` (`:244`, `:264`) | Galeria de paletas: miniatura de janela desenhada à mão | Sombras e cápsulas que imitam a janela | **Não entra.** É uma prévia de cores. No 26 ela vai divergir do app real (a miniatura não tem vidro); fica registrado como risco aceito. |

### 2.4 Rolagem e borda (macOS 26)

| arquivo:linha | Superfície | Decisão | Rótulo |
| --- | --- | --- | --- |
| `HomeView.swift:17-20`, `EnvironmentView.swift:18-21` | `ScrollView` logo abaixo da toolbar | **Sistema já faz** o efeito de borda suave. Fica `.automatic`. | Inferido |
| Tabelas de Rede, Analytics e Relatório (`HTTPInspectorView.swift:195`) | `Table` abaixo de `AccessoryBar` | A barra acessória opaca fica entre a toolbar e a tabela, então o efeito de borda da toolbar cai sobre a barra, não sobre a tabela. Nada a fazer, a não ser que D-5 mude a barra. | Inferido |
| Sidebar e detalhe | `backgroundExtensionEffect()` | **Não entra.** Não há imagem ou mídia de borda a borda sob a sidebar. | Inferido |

---

## 3. Riscos de vidro sobre vidro e de cápsula indevida

1. **Título na toolbar** (`UnifiedToolbar.swift:22-26`). No macOS 26, um `ToolbarItem` com view própria ganha o fundo de vidro compartilhado da toolbar, e o título e o subtítulo apareceriam dentro de uma cápsula. Correção: `.sharedBackgroundVisibility(.hidden)` só nesse item, no 26. **Inferido**, a confirmar com `WindowSnapshotTests` (inspeção).
2. **Rodar dentro do vidro da toolbar** (`UnifiedToolbar.swift:38-40, 247`). `.glassProminent` dentro de um item que já recebe vidro compartilhado pode desenhar cápsula sobre cápsula. Se a captura mostrar isso, aplicar `.sharedBackgroundVisibility(.hidden)` no `ToolbarItem` do Rodar. **Inferido.**
3. **Item Ambiente do rodapé** (`AppSidebar.swift:197-251`). Ele está dentro da sidebar, que no 26 é vidro. Dar `glassEffect` ou `.buttonStyle(.glass)` a ele seria vidro sobre vidro. **Proibido** pela regra. Mantém o preenchimento.
4. **Barra acessória sob a toolbar** (`Bars.swift:8-24`). Vidro aqui empilha duas faixas de vidro. **Proibido.** Fica opaca, ou passa a ser `safeAreaBar` (D-5), mas sem vidro próprio.
5. **Conteúdo de popover e sheet**. Pôr `mbGlass` dentro de `.popover`/`.sheet` é vidro sobre vidro. **Proibido.** Hoje ninguém faz isso (Verificado).
6. **Paleta de comandos sobre a toolbar**. O overlay está no conteúdo (`ContentView.swift:64`); a toolbar é do AppKit e fica fora (`CommandPaletteModal.swift:9-10`). O painel desce 56 pt (`DesignTokens.swift:285`) e não se sobrepõe às cápsulas da toolbar. **Sem risco**, desde que `topOffset` continue maior que a altura da toolbar (52, `DesignTokens.swift:194`). Inferido.
7. **Sidebar com paleta** (`AppSidebar.swift:77`). Não é vidro sobre vidro, mas é o caso oposto: um sólido pintado dentro do vidro do sistema. O resultado visual no 26 é **Suposição** (painel opaco dentro da moldura flutuante). Decisão D-1.

Guarda proposta: o `GlassAdherenceTests` (seção 7) falha se `mbGlass(`, `.glassEffect(` ou `.buttonStyle(.glass` aparecerem em `AppSidebar.swift`, em `UnifiedToolbar.swift` (fora do `mbGlassButton` do Rodar) ou em views apresentadas por `.popover`/`.sheet`.

---

## 4. Transições que pedem `GlassEffectContainer` + `glassEffectID`

| Transição | Onde | Decisão | Por quê |
| --- | --- | --- | --- |
| Cápsula do Ambiente na Início ↔ item Ambiente no rodapé da sidebar | `HomeDaily.swift:89-124` ↔ `AppSidebar.swift:197-251` | **Não viável como morph de vidro.** | (a) O `glassEffectID` só faz morph entre elementos do mesmo `GlassEffectContainer`, e os dois estão em colunas diferentes da `NavigationSplitView` (`ContentView.swift:22-30`). (b) O item da sidebar não pode ter vidro (risco 3). (c) Clicar na cápsula troca de área, e isso já é o crossfade de 180 ms (`WorkspaceColumn.swift:32`). Alternativa honesta: nenhuma animação compartilhada; a seleção da sidebar muda junto, o que já é a ligação visual. Inferido. |
| Paleta de comandos aparece e some | `CommandPaletteView.swift:13-31` | **Vidro real:** `mbGlassTransition(.materialize)` no 26; `.opacity` no 14/15 e com Reduzir movimento. | Superfície única; não precisa de container. Inferido. |
| Botões da toolbar que entram e saem (60 FPS só no Android, busca ↔ campo, Rodar com e sem tom) | `UnifiedToolbar.swift:216, 280, 318-324` | **Sistema já faz.** | A toolbar anima os próprios itens. O Rodar alterna entre `.glassProminent` e o estilo padrão quando a janela fica inativa (D2). Conferir na captura se a troca não "pisca". Inferido. |
| Controles do espelho: Atualizar + Correlação (a Correlação só aparece em Rede e Analytics) | `MirrorColumn.swift:35-54` | **Só se D-4 for aprovado:** `MBGlassGroup(spacing: Glass.groupSpacing) { refresh.mbGlassID("refresh", in: ns); correlacao.mbGlassID("correlacao", in: ns) }` com `mbGlassButton(.padrao)`. A Correlação entra e sai com morph a partir do Atualizar. | É o único conjunto de controles que aparece e some sobre algo parecido com mídia. Hoje está abaixo da moldura, sobre `bgContentAlt` liso, e aí o ganho é pequeno. |
| Chip de Correlação, faixa do motor, inspector | `CorrelationChip.swift`, `EngineStatusBanner.swift:97`, `ContentView.swift:39-56` | **Não entra.** | São conteúdo. As transições atuais (`.move+.opacity`, que vira `.opacity` com Reduzir movimento) ficam. |

---

## 5. As nove paletas

Fonte: `Theme/Palettes.swift` (`PaletteSpec.all`, `:46-92`; `PaletteTheme`, `:130-246`; `checks`, `:262-286`). Testes: `PaletteTests.swift` e `ContrastTests.swift`.

1. **O tom do vidro vem do token de destaque.** A janela já injeta `.tint(theme.accent)` (`ContentView.swift:62`, Verificado), e o `.glassProminent` lê o `tint` (Inferido). Regra da API: `mbGlassButton(.destaque)` e `mbGlass(.destaque)` usam `theme.accent` explicitamente (`Glass.regular.tint(theme.accent)`) e não o `AccentColor` do asset, que é fixo em flamingo (ADR 0002, adendo). Assim, as 9 paletas e as 2 Praias pintam o Rodar com o próprio destaque, e no alto contraste usam o `accentDarkened` (`Palettes.swift:181`).
2. **O texto sobre o vidro tingido usa `onAccent`, não o branco do sistema.** **Achado:** a paleta Costes (`garcia`, `Palettes.swift:72-76`) tem destaque `#D2AE5C` e `onAccent` `#24170E`. Cálculo WCAG feito à mão neste relatório: branco sobre `#D2AE5C` dá **cerca de 2,1:1 (reprova)**; `#24170E` sobre `#D2AE5C` dá **cerca de 8,3:1**. Se o `.glassProminent` e o `.borderedProminent` desenham o rótulo em branco (Inferido: o macOS usa a cor alternativa de controle selecionado), então **hoje o Rodar e todos os `.borderedProminent` do conteúdo** (por exemplo `HomeView.swift:234, 240`, `HomeDaily.swift:240, 385` e `EnvironmentView.swift:285`) **já falham na Costes**. Correção: `mbGlassButton` aplica `.foregroundStyle(theme.onAccent)` ao rótulo. Abrir também um item à parte para os `.borderedProminent` de conteúdo (D-8). As outras paletas e as Praias passam com branco: a Praia `#C2456E` dá cerca de 4,8:1 e a Terracota `#B4532F` cerca de 5,0:1, os dois calculados.
3. **A checagem existente não cobre o vidro.** "Texto sobre destaque" (`Palettes.swift:270`) mede `onAccent` contra o destaque **sólido**. O vidro tingido é translúcido, e o fundo efetivo mistura o destaque com o que está atrás, então o contraste real é menor e **não dá para calcular** sem render. Regra: o papel `.destaque` só existe em botão (o `.glassProminent` é quase opaco, Inferido); `mbGlass(.destaque)` em superfície com texto fica fora até haver captura medida.
4. **Texto sobre o vidro neutro (paleta de comandos).** Os rótulos do tema são cores fixas, como `ink` com opacidade (`Palettes.swift:150-155`) e `navy(…)` na Praia. O vidro `.regular` se adapta ao fundo (Inferido), e uma cor fixa pode perder contraste sobre um conteúdo escuro numa paleta clara. Mitigações já presentes: o véu `floatingScrim` (`DesignTokens.swift:319`) e o fato de as paletas imporem o esquema de cor (`ThemeManager.swift:126-128`), que deixa o vidro no mesmo esquema que os rótulos. Regra da API: dentro de `.flutuante`, manter os tokens do tema (a paridade de paleta é requisito) e manter o véu. A medição fica para a revisão visual (Não verificado).
5. **Sidebar com paleta**: ver D-1. O `ContrastTests.swift:42-56` mede o terciário contra `bgSidebar` em 22 temas. Isso só continua valendo se a sidebar com paleta seguir sólida (opção A).
6. **Galeria de paletas** (`PaletteGallery.swift:184-282`): a prévia não mostra vidro. Isso é aceito, porque ela prova as cores, não o material.

---

## 6. Acessibilidade

### O que já existe (Verificado no código)

| Preferência | Onde é tratada | Como |
| --- | --- | --- |
| Aumentar contraste | `Theme/ThemeManager.swift:19, 40, 48-56` | Lê `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` e troca para as variantes `highContrast` (Praia em `PraiaLightTheme.swift:45, 49` e `PraiaDarkTheme.swift:45, 49`; paletas em `Palettes.swift:150-200`). `DSCard` engrossa a borda (`Content.swift:100-101`). |
| Reduzir movimento | `DesignTokens.swift:332-338`; `EngineStatusBanner.swift:77, 97, 100`; `Indicators.swift:123, 136`; `SplashWindow.swift:179, 212` | As molas viram `linear` curto, a faixa só esmaece e o splash não anima a barra. |
| Reduzir transparência | **Nenhum lugar.** O `grep` por `accessibilityReduceTransparency` e `ReduceTransparency` em `Sources` não acha nada. | Hoje isso só funciona porque o único material é o `.regularMaterial` da paleta, que o sistema já torna sólido (Inferido). |

### O que precisa passar a tratar

1. **Reduzir transparência**, dentro de `mbGlass` (um lugar só): `@Environment(\.accessibilityReduceTransparency)`. Quando ligado, cada papel troca para o sólido do token (tabela 7.2), **nos dois sistemas** (recomendação de D-2). Isso implementa `materials.css` (`[data-reduce-transparency="true"]`: "todo vidro vira superfície sólida e opaca") sem `if` nas views.
2. **Aumentar contraste**: usar `@Environment(\.colorSchemeContrast) == .increased` **ou** `theme.highContrast` (é a mesma fonte, `ThemeManager`). Recomendação: `theme.highContrast`, para não haver duas verdades. No fallback 14/15 e no sólido, `strokeBorder(theme.separatorStrong, lineWidth: 1)` (`materials.css`, `[data-contrast="high"]`: `--glass-edge: 0 0 0 1px var(--control-border)`). No 26, o vidro do sistema já se adapta (Inferido); a borda própria não entra, para evitar borda dupla.
3. **Reduzir movimento**: `mbGlassTransition` e `mbGlassID` leem `accessibilityReduceMotion`. Com ele ligado, a transição vira `.opacity` (`Motion.crossfade`) e o morph vira troca simples. O `interactive()` do vidro (brilho ao toque) fica desligado com Reduzir movimento (Suposição: o sistema talvez já faça isso; desligar explicitamente custa pouco).
4. **Foco**: o vidro não pode esconder o anel de foco. A paleta mantém o foco no campo (`CommandPaletteView.swift:116`). Conferir com o VoiceOver se o `isModal` (`:111`) e o `HiddenBehindCommandPalette` continuam funcionando com `glassEffect` (Não verificado).
5. **Estado nunca só por cor**: o vidro tingido do Rodar não pode ser o único sinal de que ele está disponível. Isso já vale, com `.disabled` e a dica em `UnifiedToolbar.swift:248-249`.

---

## 7. API única proposta

### 7.1 Arquivo e regra

`apps/MoBaile/Sources/MoBaile/Views/DesignSystem/Glass.swift`. **Somente** este arquivo e o `ToolbarSpacer` já existente (`UnifiedToolbar.swift:30-32`) podem conter `#available(macOS 26`. As views usam só os nomes abaixo.

```swift
/// Papel do vidro. Fechado: a view escolhe o papel, nunca o material.
enum MBGlassRole: Sendable {
    /// Painel que flutua sobre o conteúdo (paleta de comandos).
    case flutuante
    /// Grupo de controles flutuante sobre conteúdo ou mídia (controles do espelho, se D-4).
    case capsula
    /// Barra flutuante própria. Reservado: hoje nenhuma barra do app flutua (toolbar e sidebar são do sistema).
    case barra
    /// Superfície tingida pelo destaque. Só botão nesta rodada (ver 5.3).
    case destaque
}

enum MBGlassButtonKind: Sendable { case padrao, destaque }

extension View {
    /// Vidro do papel, na forma dada. Lê tema, Reduzir transparência e alto contraste do ambiente.
    func mbGlass<S: InsettableShape>(_ papel: MBGlassRole, in forma: S, interativo: Bool = false) -> some View
    /// Botão de vidro. `ativo == false` (desabilitado ou janela inativa) volta ao estilo padrão (D2, como hoje).
    func mbGlassButton(_ tipo: MBGlassButtonKind = .padrao, ativo: Bool = true) -> some View
    /// `glassEffectID` no 26; nada no 14/15 nem com Reduzir movimento.
    func mbGlassID<ID: Hashable & Sendable>(_ id: ID, in ns: Namespace.ID) -> some View
    /// `glassEffectTransition` no 26; `.transition(.opacity)` no 14/15 e com Reduzir movimento.
    func mbGlassTransition(_ tipo: MBGlassTransitionKind = .materialize) -> some View
    /// Fundo da sidebar segundo a paleta (encapsula AppSidebar.swift:76-77 e a decisão D-1).
    func mbSidebarBackground() -> some View
    /// `safeAreaBar` no 26; `safeAreaInset` no 14/15 (D-5).
    func mbSafeAreaBar<C: View>(edge: VerticalEdge, @ViewBuilder _ c: () -> C) -> some View
}

/// `GlassEffectContainer(spacing:)` no 26; `Group` no 14/15.
struct MBGlassGroup<Content: View>: View { init(spacing: CGFloat = DesignMetrics.Glass.groupSpacing, @ViewBuilder content: () -> Content) }

extension ToolbarContent {
    /// `sharedBackgroundVisibility(.hidden)` no 26; sem efeito antes. Para o título e, se preciso, o Rodar.
    func mbSemVidroCompartilhado() -> some ToolbarContent
}
```

As assinaturas das APIs de base foram **Verificadas** no SDK 26.2. A forma exata do `ToolbarContentBuilder` com `if #available` é **Inferida** do uso que já existe em `UnifiedToolbar.swift:22, 30`.

### 7.2 Comportamento de cada papel

| Papel | macOS 26 | macOS 14/15 (fallback) | Reduzir transparência (os dois) | Aumentar contraste |
| --- | --- | --- | --- | --- |
| `.flutuante` | `glassEffect(.regular, in: forma)`, sem borda e sem sombra próprias | `.background(.regularMaterial, in: forma)` + `strokeBorder(separatorStrong, hairline/2)` + `shadow(floatingShadow, Shadow.floatingRadius, y: Shadow.floatingY)` (o que existe hoje em `CommandPaletteView.swift:101-106`) | `.background(theme.bgContent, in: forma)` + `strokeBorder(separatorStrong, 1)` + sombra | Fallback e sólido: borda `separatorStrong` de 1 pt; no 26, o sistema |
| `.capsula` | `glassEffect(.regular[.interactive()], in: forma)` | `.background(.thinMaterial, in: forma)` + `strokeBorder(separator, 0.5)` | `theme.bgControl` + `strokeBorder(controlBorder, 1)` | Igual: `controlBorder` de 1 pt |
| `.barra` | `glassEffect(.regular, in: forma)` | `.background(.bar, in: forma)` + separador | `theme.bgWindow` | Separador `separatorStrong` |
| `.destaque` | `glassEffect(.regular.tint(theme.accent)[.interactive()], in: forma)` | `.background(theme.accent, in: forma)` | `theme.accent` sólido | `theme.accent` já escurecido (`Palettes.swift:181`) |
| `mbGlassButton(.padrao)` | `.buttonStyle(.glass)` | `.buttonStyle(.bordered)` | O sistema (estilo nativo) | O sistema |
| `mbGlassButton(.destaque)` | `.buttonStyle(.glassProminent)` + `.tint(theme.accent)` + rótulo em `theme.onAccent` | `.buttonStyle(.borderedProminent)` + o mesmo tom e rótulo | O sistema | O sistema |
| `ativo == false` | Estilo padrão, sem tom (D2) | Igual | Igual | Igual |

O texto dentro de qualquer papel mantém os tokens do tema (`labelPrimary`, `labelSecondary`) para garantir a paridade das paletas. Dentro do vidro, a separação vem de `fill*` (`materials.css`).

### 7.3 Tokens propostos

| Token | Camada | Valor | Nota |
| --- | --- | --- | --- |
| `DesignMetrics.Glass.groupSpacing` | componente | `DesignMetrics.Spacing.s4` (8) | Distância de fusão do `GlassEffectContainer`. Valor da grade de 4 pt, a validar na captura. |
| `ThemeTokens.glassTint` | semântico (derivado) | `accent` | Alias explícito, para a auditoria achar o tom do vidro. |
| `ThemeTokens.onGlassTint` | semântico (derivado) | `onAccent` | Rótulo sobre o vidro tingido. |
| `ThemeTokens.glassSolid(_ papel)` | semântico (derivado) | `.flutuante → bgContent`, `.capsula → bgControl`, `.barra → bgWindow`, `.destaque → accent` | Sólido do Reduzir transparência. Espelha `materials.css` sem valor cru novo. |

Nenhum hex novo. Os derivados ficam numa `extension ThemeTokens`, como `floatingScrim` (`DesignTokens.swift:316-323`), então não mexem no protocolo nem nas 11 conformidades.

### 7.4 Como cada view passa a ficar (exemplos)

- `CommandPaletteView.swift:100-106` vira `.frame(width: Self.width).mbGlass(.flutuante, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))`, e o overlay em `:29` passa a usar `.mbGlassTransition()`.
- `UnifiedToolbar.swift:247` vira `.mbGlassButton(.destaque, ativo: Self.podeRodar(appState) && estadoDaJanela != .inactive)`; `prominentGlassButton` sai, ou fica como alias com `@available(*, deprecated)`.
- `UnifiedToolbar.swift:23-25` vira `ToolbarItem(placement: .navigation) { SectionTitleView(…) }.mbSemVidroCompartilhado()`.
- `AppSidebar.swift:76-77` vira `.mbSidebarBackground()`.

---

## 8. Testes de UI: o que muda e o que guarda

| Teste | Papel nesta mudança | Ajuste necessário |
| --- | --- | --- |
| `ToolbarLayoutTests.swift:52-60` (≥ 6 itens na toolbar instalada) | **Guarda.** O `sharedBackgroundVisibility` não pode tirar itens. | Nenhum (Inferido). |
| `ToolbarLayoutTests.swift:148-162` (`podeRodar`) | **Guarda** da regra de habilitar o Rodar. | Nenhum. |
| `ToolbarLayoutTests.swift:247-268, 275-292` (mínimos 1100×600 e colunas) | **Guarda.** O `safeAreaBar` (D-5) e o `GlassEffectContainer` não podem aumentar o mínimo. | Nenhum; rodar depois de D-4 e D-5. |
| `WindowSnapshotTests.swift:14-24` (só com `MOBAILE_SNAPSHOT_DIR`), `:165-210`, `:333-340` (paleta), `:287` (Terracota), `:367` (Sálvia), `:699` (catálogo) | **Ferramenta de inspeção**, não asserção. É ela que mostra a cápsula do título, a cápsula dupla do Rodar e a sidebar com paleta. | Regerar o catálogo `docs/design/telas` no 26. Acrescentar capturas da Costes (Rodar com `onAccent`) e com Reduzir transparência e Aumentar contraste. Atenção: o vidro amostra o que está atrás da janela, então as capturas variam com o papel de parede (Suposição). |
| `LayoutSnapshotTests.swift:31` (`ImageRenderer`), `HomeContent`/`EnvironmentContent` (`HomeView.swift:24-25`) | Inspeção. | O `ImageRenderer` provavelmente não desenha `glassEffect` (Suposição). Não usar essas capturas para julgar o vidro. |
| `PaletteTests.swift:14-38, 71-130` | **Guarda** de que os tokens batem com `palettes.css`. | Nenhum, enquanto os derivados novos não entrarem no `mapa`. Se `glassSolid` virar variável CSS, acrescentar ao `mapa`. |
| `PaletteTests.swift:96-110` (`checks`) e `Palettes.swift:270` | **Guarda** de `onAccent` sobre o destaque sólido. | Novo teste: `mbGlassButton(.destaque)` usa `onAccent` (por leitura de fonte ou por estilo testável). A checagem atual não pega a Costes, porque o defeito é o rótulo branco do estilo nativo e não o token. |
| `ContrastTests.swift:42-56` (terciário contra `bgSidebar` em 22 temas) | **Guarda** só se D-1 = A (sidebar com paleta sólida). | Se D-1 = B, o teste perde o sentido para a sidebar: documentar e trocar por uma revisão visual. |
| `ThemeTests.swift:35-44` (Aumentar contraste) | **Guarda** dos tokens de alto contraste usados pelo fallback. | Nenhum. |
| `AccessibilityTests.swift` (nomes e estados) | **Guarda** de que o vidro não muda a árvore de acessibilidade. | Nenhum (Inferido). |
| **Novo:** `GlassAdherenceTests` | **Guarda de aderência.** Segue o padrão de leitura de fonte de `NoDeviceTests.swift:49-54`. | (1) `#available(macOS 26`, `.glassEffect(`, `GlassEffectContainer`, `.buttonStyle(.glass` e `Material` (`.regularMaterial`, `.thinMaterial`, `.ultraThinMaterial`, `.thickMaterial`, `.bar`) só em `Glass.swift` (e o `ToolbarSpacer` de `UnifiedToolbar.swift`). (2) `mbGlass(` proibido em `AppSidebar.swift` e em views de `.popover`/`.sheet`. (3) `prominentGlassButton` ausente. |
| **Novo:** `GlassFallbackTests` | Guarda do sólido do Reduzir transparência. | Para os 22 temas, `labelPrimary` e `labelSecondary` sobre `glassSolid(.flutuante)` e `glassSolid(.capsula)` com pelo menos 4,5:1, usando a mesma função de contraste do `ContrastTests`. |

---

## 9. Estados

| Estado | Paleta de comandos (`.flutuante`) | Rodar (`mbGlassButton(.destaque)`) | Sidebar |
| --- | --- | --- | --- |
| Padrão | Vidro regular (26); material com borda e sombra (14/15) | Vidro tingido no `accent`, rótulo `onAccent` | Vidro do sistema (Praia); D-1 (paletas) |
| Hover / pressionado | Linhas: `fillPrimary`/`accent` (`CommandPaletteView.swift:372`) | Do sistema | Itens do sistema; `SidebarEnvironmentItem` com `fillSecondary` |
| Foco | Anel do campo (do sistema) | Anel do sistema | Do sistema |
| Desabilitado / janela inativa | — | Estilo padrão sem tom (D2) | Seleção vira `selectionInactive` |
| Vazio / indisponível | Aviso `warningTint` dentro do vidro | `.disabled` + dica | "Nenhum passo gravado." |
| Reduzir transparência | `bgContent` sólido + borda | Do sistema | Do sistema / sólido |
| Aumentar contraste | Borda de 1 pt (fallback e sólido) | `accent` escurecido | Tokens `highContrast` |
| Reduzir movimento | Entrada e saída em crossfade | — | — |

---

## 10. Critérios de aceite (observáveis)

1. `grep -rn '#available(macOS 26' apps/MoBaile/Sources` lista só `Views/DesignSystem/Glass.swift` e `Views/MainWindow/UnifiedToolbar.swift` (o `ToolbarSpacer`). O `GlassAdherenceTests` passa.
2. `grep -rn 'Material' apps/MoBaile/Sources` não acha `.regularMaterial` fora de `Glass.swift`.
3. No macOS 26, `CommandPaletteView` não tem `strokeBorder` nem `shadow` próprios; no 14/15, o código desenha o mesmo que a versão 3.12.0 (mesmo material, borda e sombra).
4. Com Reduzir transparência ligado, o caminho de código da paleta usa `theme.bgContent` sólido nos dois sistemas. O `GlassFallbackTests` dá pelo menos 4,5:1 para o primário e o secundário nos 22 temas.
5. O rótulo do Rodar usa `theme.onAccent`. Na Costes isso dá `#24170E` sobre `#D2AE5C` (cerca de 8,3:1, calculado).
6. Com a janela inativa ou o Rodar desabilitado, o botão não tem tom (D2, como hoje em `UnifiedToolbar.swift:314-319`).
7. Na captura de `WindowSnapshotTests` no 26, o título da seção não aparece dentro de cápsula e o Rodar não tem cápsula dupla.
8. `AppSidebar.swift`, `UnifiedToolbar.swift` (fora do `mbGlassButton`) e as views de popover e sheet não chamam `mbGlass`.
9. `ToolbarLayoutTests`, `PaletteTests`, `ContrastTests`, `ThemeTests` e `AccessibilityTests` passam sem alteração de asserção (com D-1 = A).
10. Com Reduzir movimento ligado, `mbGlassTransition` cai em `.opacity` e `mbGlassID` não aplica `glassEffectID` (o teste verifica o caminho de código).
11. O app instalado é atualizado e verificado com `make update-native` e um OK do `verify-native` (AGENTS.md). Isso cabe a quem implementar.

---

## 11. Nota por tela (design system da casa)

| Tela | O que muda | Por quê |
| --- | --- | --- |
| Janela (toolbar) | O título perde a cápsula de vidro; o Rodar usa o tom e o rótulo da paleta | Evitar vidro em texto; contraste na Costes |
| Sidebar | A Praia fica igual; paletas conforme D-1 | Não pintar sobre o vidro sem decisão |
| Paleta de comandos | Material imitado → vidro real; entrada com `materialize` | É a única superfície flutuante própria |
| Início, Ambiente, Rede, Analytics, Relatório, Page Objects | Nada (conteúdo) | Regra do design system |
| Splash, Ajustes › Paletas | Nada | Marca e prévia de cores |

**Adições intencionais** (o design system não tinha): o papel `.capsula` para grupo de controles flutuante (só usado se D-4); a API de toolbar `mbSemVidroCompartilhado`; os tokens derivados `glassTint`, `onGlassTint` e `glassSolid`.

**Substituições a validar**: o `materials.css` descreve o vidro como `blur(18px) saturate(1.6)` a 62%, e o vidro do sistema não segue esses números. O token passa a ser documentação do fallback 14/15 e do protótipo HTML. É preciso registrar isso num adendo ao ADR 0002 e no cabeçalho de `materials.css`.

---

## 12. Decisões pendentes do humano

| # | Decisão | Opções e impacto | Recomendação |
| --- | --- | --- | --- |
| D-1 | Sidebar com paleta alternativa no macOS 26 (`AppSidebar.swift:76-77`) | **A** manter `bgSidebar` sólido: a cor da paleta fica e o contraste segue testado (`ContrastTests`), mas a sidebar não tem vidro nas 9 paletas. **B** vidro do sistema sem a cor: o visual fica nativo, mas a identidade da paleta some da sidebar e o contraste não é mensurável. **C** vidro + `containerBackground(bgSidebar.opacity(…), for: .navigation)`: o resultado é desconhecido e pede captura. | **A** nesta rodada; C como experimento com captura. |
| D-2 | Reduzir transparência no 26 | **A** forçar sólido por token: previsível e testável. **B** confiar no fosco do sistema: mais nativo, sem teste. | **A** para o vidro próprio. O vidro do sistema (toolbar, sidebar) segue o sistema de qualquer jeito. |
| D-3 | Cápsula do Ambiente na Início (`HomeDaily.swift:89-124`) | **A** manter o preenchimento (conteúdo). **B** `mbGlassButton(.padrao)`, abrindo exceção à regra "conteúdo nunca usa vidro". O morph com a sidebar não é viável em nenhuma das duas. | **A**. |
| D-4 | Controles do espelho como grupo flutuante de vidro (`MirrorColumn.swift:35-54`) | **A** não mexer. **B** `MBGlassGroup` + `mbGlassID` sobre a base da moldura, com morph da Correlação; mexe no layout e pode afetar `testConteudoDasColunasCabeNoMinimoDeclarado`. | **A** nesta rodada. |
| D-5 | Barra acessória e rodapé da sidebar como `safeAreaBar` no 26 | **A** manter. **B** migrar, para o efeito de borda passar por baixo; muda medidas. | Decidir depois da captura. |
| D-6 | `scrollEdgeEffectStyle` | `.automatic` em tudo, ou `.hard` nas tabelas com cabeçalho | `.automatic`. Usar `.hard` só se a captura mostrar o cabeçalho de `Table` borrado. |
| D-7 | Versão | Minor (3.13.0): adoção de material do sistema sem redesenho. Major: se o dono considerar a mudança visual drástica (memória "UI drástica sobe major"). | Minor. |
| D-8 | `.borderedProminent` de conteúdo com rótulo branco na Costes (`HomeView.swift:234, 240`, `HomeDaily.swift:240, 385`, `EnvironmentView.swift:285` e outros) | Corrigir junto (rótulo `onAccent` via `mbGlassButton(.destaque)` ou um `dsProminentButton`) ou em item separado | Item separado, no mesmo PR, porque é um bug de contraste já existente (a confirmar na captura). |

---

## 13. Verificado / Inferido / Suposição / Não verificado

- **Verificado (leitura de código nesta sessão):**
  - todas as citações `arquivo:linha` acima;
  - que o único material translúcido é `CommandPaletteView.swift:101`;
  - que não há tratamento de Reduzir transparência;
  - que a sidebar pinta `bgSidebar` sólido com paleta;
  - que `.tint(theme.accent)` está na raiz;
  - que `onAccent` da Costes é `#24170E`;
  - os cálculos de contraste (2,1:1, 8,3:1, 4,8:1 e 5,0:1, feitos à mão com a fórmula WCAG de luminância relativa);
  - a existência e as assinaturas das APIs no SDK `MacOSX26.2.sdk`;
  - que o macOS da máquina é 26.3.1 e o `Package.swift` é `swift-tools-version: 5.10`, `.macOS(.v14)`.
- **Inferido:** todo comportamento visual do vidro no macOS 26:
  - a cápsula automática em item de toolbar com view própria;
  - a cápsula dupla no Rodar;
  - o `.glassProminent` lendo o `tint`;
  - o rótulo branco nos estilos proeminentes;
  - o sistema se adaptando a Aumentar contraste e Reduzir transparência;
  - o efeito de borda automático nas `ScrollView`.
- **Suposição:**
  - o `ImageRenderer` não desenha `glassEffect`;
  - as capturas variam com o papel de parede;
  - o visual da sidebar com sólido dentro da moldura flutuante;
  - o `interactive()` se comportando com Reduzir movimento.
- **Não verificado:** nada foi compilado, renderizado, capturado nem testado com VoiceOver. Não houve medição de contraste sobre vidro, que não é calculável sem render.

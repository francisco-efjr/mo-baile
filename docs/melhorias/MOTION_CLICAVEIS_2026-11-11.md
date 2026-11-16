# Motion dos clicáveis: checklist (11/11/2026)

Objetivo: todo clique que abre, fecha, expande ou troca uma tela no app nativo
tem a mesma fluidez do botão **Projeto** da faixa de tool windows em Page
Objects.

## 1. A referência: o botão Projeto

[ProjectTreeView.swift:341](../../apps/MoBaile/Sources/MoBaile/Views/Workspace/ProjectTreeView.swift)

```swift
BarIconButton(icon: "folder", label: "Projeto", isOn: appState.projectTreeVisible) {
    withAnimation(Motion.smooth()) { appState.projectTreeVisible.toggle() }
}
```

O que faz a animação ser boa:

1. **A mudança de estado vai dentro de `withAnimation`.** A árvore entra e sai
   de um `HStack` com `if`; o SwiftUI anima a entrada (transição padrão,
   opacidade) e, junto, a largura do editor ao lado. Por isso nada "pula".
2. **A curva é `Motion.smooth()`** ([DesignTokens.swift:352](../../apps/MoBaile/Sources/MoBaile/Theme/DesignTokens.swift)):
   mola de 0,5 s sem quique (`.spring(duration: 0.5, bounce: 0)`). Começa
   rápida e assenta devagar: nem lenta, nem seca.
3. **Respeita o perfil leve.** Com `MotionPolicy.reduced` (PERF-4) a mola vira
   um crossfade linear de 0,18 s.

O sistema já tem os quatro tempos definidos em `Motion`:

| Token | Curva | Uso previsto |
|---|---|---|
| `smooth()` | mola 0,5 s, sem quique | painéis que abrem e fecham (a referência) |
| `snappy()` | mola 0,35 s, quique 0,15 | cliques curtos: expandir pasta/nó, interruptores |
| `crossfade` | linear 0,18 s | trocar de seção ou de conteúdo no mesmo lugar |
| `hover` | linear 0,06 s | realce de passar o mouse |

**Regra a replicar:** toda mudança de estado que insere ou remove uma view por
causa de um clique vai dentro de `withAnimation(<token>)`, de preferência num
método único do `AppState` (como `toggleMirror()`), para que botão, atalho e
paleta de comandos animem igual.

## 2. Checklist

Legenda: ✅ já igual à referência · ❌ sem animação (pula) · ⚠️ anima, mas
diferente ou só em parte · 🔒 animação do sistema (sheet, popover, alerta),
não mexer.

### A. Painéis que abrem e fecham (`Motion.smooth()`)

| # | Clicável | Onde | Hoje | Ação |
|---|---|---|---|---|
| A1 | Projeto, na faixa de tool windows | `ProjectTreeView.swift:341` | ✅ referência | — |
| A2 | Mostrar/Ocultar Projeto pela paleta e menu | `CommandPerformer.swift:52` | ✅ | — |
| A3 | **−** (Ocultar Projeto) no cabeçalho da árvore | `DualEditorPane.swift:55` | ✅ 3.22.0 (era: ❌ `projectTreeVisible = false` sem animação) | criar `AppState.setProjectTree(_:)` animado e usar nos três lugares |
| A4 | Hierarquia, na faixa de tool windows | `ProjectTreeView.swift:347` | ✅ 3.22.0 (era: ❌ `toggleInspector()` sem animação) | animar dentro de `toggleInspector()` |
| A5 | Inspector na toolbar | `UnifiedToolbar.swift:340` | ✅ 3.22.0 (era: ❌ mesma causa do A4) | resolvido pelo A4 |
| A6 | Inspector por ⌥⌘I / paleta | `CommandPerformer.swift:45` | ✅ 3.22.0 (era: ❌ mesma causa do A4) | resolvido pelo A4 |
| A7 | Inspector some/volta sozinho (Início, Ambiente, aparelho desconectado) | `AppState.inspectorSuppressed` | ✅ 3.22.0 (era: ❌ pula ao trocar de área) | `.animation(Motion.smooth(), value: appState.inspectorShown)` no `HStack` do detalhe (`ContentView.swift:36`) |
| A8 | Espelho na toolbar e ⌥1 | `AppState.toggleMirror()` | ✅ | — |
| A9 | Workspace (paleta) | `CommandPerformer.swift:49` | ✅ | — |
| A10 | Lado a lado (pages + locators) | `DualEditorPane.swift:288` | ✅ | — |
| A11 | Mostrar Todos os Painéis | `CommandPerformer.swift:54` | ✅ | — |
| A12 | Modo Zen | `CommandPerformer.swift:56` | ✅ | — |
| A13 | Barra lateral (botão do canto e ⌃⌘S) | `NavigationSplitView` | 🔒 nativa | — |
| A14 | Árvore some por falta de largura (coluna estreita) | `DualEditorPane.swift:52` | ⚠️ some sem animação ao redimensionar | deixar: é consequência do arrasto, animar ali dá atraso |

### B. Expandir e recolher (`Motion.snappy()`)

| # | Clicável | Onde | Hoje | Ação |
|---|---|---|---|---|
| B1 | Pasta da árvore do Projeto (chevron, clique, ← →) | `ProjetoModelo.alternar` / `ProjectTreeView.swift:216` | ✅ 3.22.0 (era: ❌ linhas aparecem de uma vez; chevron troca de ícone sem girar) | `withAnimation(Motion.snappy())` nos pontos de clique; chevron único com `rotationEffect`, como na hierarquia |
| B2 | Expandir tudo / Recolher tudo do Projeto | `ProjetoModelo.expandirTudo/recolherTudo` | ✅ 3.22.0 (era: ❌) | idem B1 |
| B3 | Nó da Hierarquia | `HierarchyTreeView.swift:64,69,84` | ✅ 3.22.0 (era: ⚠️ só o chevron gira; as linhas pulam) | `withAnimation(Motion.snappy())` em volta de `recolhidos` |

### C. Troca de área e de conteúdo (`Motion.crossfade`)

| # | Clicável | Onde | Hoje | Ação |
|---|---|---|---|---|
| C1 | Itens da barra lateral (Início, Page Objects, Rede, Analytics, Relatório, Ambiente) e todos os atalhos que mudam `workspaceTab` (Início, paleta, ⌘1–⌘5) | `WorkspaceColumn.swift:32` | ✅ crossfade central, vale para qualquer origem | decisão: manter crossfade (padrão do design system para troca de seção) ou passar para `smooth()` |
| C2 | Selecionar requisição na Rede (detalhe abre) | `HTTPInspectorView.swift:51` | ✅ 3.22.0 (era: ❌) | `.animation(Motion.crossfade, value: appState.selectedRequest?.id)` |
| C3 | Selecionar evento no Analytics | `AnalyticsInspectorView.swift:109` | ✅ 3.22.0 (era: ❌) | idem, com o id do evento |
| C4 | Selecionar resultado/extra no Relatório | `ReportDetailPane.swift:19`, `ReportCardInspector.swift:53` | ✅ 3.22.0 (era: ❌) | idem |
| C5 | Selecionar elemento (Atributos) | `AttributesPanel.swift:87` | ✅ 3.22.0 (era: ❌) | idem |
| C6 | Abrir arquivo / trocar aba de arquivo no editor | `DualEditorPane.swift` (`abas`, `arquivoAtivo`) | ✅ 3.22.0 (era: ❌) | crossfade no editor com `value: arquivoAtivo` |
| C7 | Segmentados que trocam conteúdo: Request/Response, filtros da Rede, Quadro/Tabela do Relatório, filtro do Relatório, detalhe do Relatório, `AdaptivePair` | `RequestDetailView:71`, `HTTPInspectorView:181`, `ReportSpecEditorView:84`, `ReportView:273`, `ReportDetailPane:183`, `AdaptivePair:48` | ⚠️ 3.22.0: ✅ nos que trocam conteúdo; filtros de tabela ficam sem animação (ver seção 3) | crossfade com `value:` da seleção |
| C8 | Estado do Início (carregando → pronto) | `HomeView.swift:44` | ✅ | — |
| C9 | Paleta de comandos (⇧⌘P, ⎋, clique fora) | `ContentView.swift:67` | ✅ crossfade | — |
| C10 | Banner de status do motor | `EngineStatusBanner.swift:100` | ✅ | — |
| C11 | Configurações: abas e paletas | `SettingsView.swift:42`, `PaletteGallery.swift:70` | ✅ 3.22.0 (era: ⚠️ paleta anima, segmentado não) | crossfade no segmentado |

### D. Janelas e balões do sistema (não mexer)

| # | Clicável | Onde | Hoje |
|---|---|---|---|
| D1 | Estrutura do fluxo (sheet) | `ContentView.swift:68` | 🔒 |
| D2 | Rodar flow (sheet) | `ContentView.swift:73` | 🔒 |
| D3 | Importar/Exportar no Relatório (sheets) | `ReportView.swift:60,68` | 🔒 |
| D4 | Ver Tudo no Início (popover) | `HomeDaily.swift:543` | 🔒 |
| D5 | Diagnóstico do tráfego (popover) | `HTTPInspectorView.swift:135` | 🔒 |
| D6 | Correlação no espelho (popover) | `MirrorColumn.swift:46` | 🔒 |
| D7 | Print no editor de spec (popover) | `ReportSpecEditorView.swift:235` | 🔒 |
| D8 | Alertas e confirmações (limpar, apagar, descartar) | `ContentView.swift:78`, `DualEditorPane.swift:77,88`, `ReportSpecEditorView.swift:42` | 🔒 |
| D9 | Splash | `SplashWindow.swift` | ✅ própria |

## 3. Aplicado na 3.22.0

- `AppState.toggleInspector()` e `setProjectTree(_:)` / `toggleProjectTree()`
  animam com `Motion.smooth()`; botões, atalhos e paleta passam por eles.
- `ContentView`: `.animation(Motion.smooth(), value: inspectorShown)`.
- Árvores: `withAnimation(Motion.snappy())` em `ProjetoModelo` e em
  `HierarchyTreeView`; chevron do Projeto gira.
- Novo modificador `crossfade(on:)` (`DesignTokens.swift`) nos detalhes, no
  editor (`arquivoAtivo`), em Request/Response, Bloco/Evento, `AdaptivePair` e
  Quadro/Tabela; a aparência troca com crossfade.
- `MotionPolicy.shared` segue o "Reduzir movimento" do macOS.
- **C7 parcial, de propósito:** os filtros que só filtram linhas de tabela
  (escopo da Rede, filtro do Relatório) não animam, para não pesar em tabelas
  grandes.

## 4. Resumo

- **Já fluidos (9):** A1, A2, A8–A12, C1, C8–C10.
- **A corrigir (≈17):** A3–A7, B1–B3, C2–C7, C11.
- **Do sistema (9):** A13, D1–D8.

## 5. Como foi planejado

1. `AppState`: `toggleInspector()` e um `setProjectTree(_:)` passam a animar
   com `Motion.smooth()`, como `toggleMirror()` já faz. Assim A3–A6 ficam
   resolvidos sem mexer em cada botão.
2. `ContentView`: animação implícita no `HStack` do detalhe para quando o
   inspector some/volta sozinho (A7).
3. Árvores (B1–B3): `withAnimation(Motion.snappy())` e chevron girando.
4. Detalhes e segmentados (C2–C7, C11): `.animation(Motion.crossfade, value:)`
   com o id da seleção.
5. Teste: um teste por método do `AppState` não cobre a animação em si, então a
   conferência é visual, no app instalado (`make update-native`), clicando item
   por item desta lista.
6. Observação: `Motion.smooth()` é chamado sem `reduceMotion:` nos toggles de
   painel, então o "Reduzir movimento" do macOS só vale onde a view lê
   `@Environment(\.accessibilityReduceMotion)`. Vale ligar o `MotionPolicy` a
   essa preferência do sistema na mesma rodada.

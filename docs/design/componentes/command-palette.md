---
title: CommandPalette
description: Paleta de comandos em SwiftUI para o Mo baile, com busca sem acento, sinônimos, recentes e motivo de indisponibilidade, para achar qualquer ação pelo nome.
---

# CommandPalette

A paleta de comandos é um painel de vidro que flutua sobre a janela e lista todas as ações do registro (`CommandRegistry`) num campo de busca. O QA abre com ⇧⌘P, digita o verbo que lembra ("ligar proxy", "inspecao") e executa com Enter, sem procurar em menu, toolbar ou barra da área.

Código: `apps/MoBaile/Sources/MoBaile/Views/CommandPalette/CommandPaletteView.swift`.
Especificação: `docs/design/FLUIDEZ_3.5.md` (D1 a D6, FLU-1).

Partes:

- `CommandPaletteOverlay`: véu e posição sobre a janela; mostra o painel quando `AppState.commandPalettePresented` é verdadeiro.
- `CommandPaletteView`: campo, lista por seção, aviso de indisponível e rodapé de teclas.
- `CommandPaletteRow`: uma linha (símbolo, título, motivo e atalho).
- `CommandPaletteKeyboard`: função pura que decide se uma tecla é da paleta e o que fazer com ela (`CommandPaletteKeyboardTests`).
- `HiddenBehindCommandPalette` e `CommandPaletteFocus` (`CommandPaletteModal.swift`): fundo fora do VoiceOver com a paleta aberta e foco devolvido ao fechar (`CommandPaletteModalTests`).

Previews no arquivo:

- "Paleta: sem termo (recentes e categorias)": primeira abertura, motor parado, muitas ações indisponíveis com motivo.
- "Paleta: com resultados (proxy)": termo controlado por `@Previewable @State`.
- "Paleta: sem resultado": termo "teletransportar".
- "Linhas: selecionada, comum e indisponível" e "Linhas: escuro": `CommandPaletteRow` isolada, com ação disponível selecionada, comum, indisponível ("Grave ao menos um passo") e indisponível selecionada.

## Uso

Onde é montado: `ContentView.swift`, como overlay da janela inteira:

```swift
.overlay { CommandPaletteOverlay().tint(theme.accent) }
.animation(Motion.crossfade, value: appState.commandPalettePresented)
```

Quem abre e fecha é o `CommandPerformer` (`CommandID.palette`, ⇧⌘P no menu Visualizar), o clique no véu, o Esc e a execução de uma ação.

Montagem isolada (preview, teste visual):

```swift
CommandPaletteView()
    .environment(appState)
    .environment(engineSession)
    .environment(ThemeManager(preview: PraiaLightTheme()))
```

### Controlado

O termo buscado pode vir de fora. Sem `query`, a paleta guarda o termo num `@State` interno e abre vazia, que é o caso do app.

```swift
@State private var termo = "proxy"
CommandPaletteView(query: $termo)
```

## API Reference

### CommandPaletteOverlay

Sem parâmetros. Lê `AppState.commandPalettePresented`.

### CommandPaletteView

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `query` | `Binding<String>?` | `nil` | Termo buscado, controlado por quem monta. `nil` usa estado interno e abre com o campo vazio. |
| `width` (estático) | `CGFloat` | `DesignMetrics.CommandPalette.width` (560) | Largura do painel. Alias do token. |

### CommandPaletteRow

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `command` | `AppCommand` | - | A ação, já com a disponibilidade do contexto. `disabledReason` não nulo esmaece a linha e mostra o motivo. |
| `selected` | `Bool` | - | Linha sob o cursor do teclado ou do mouse. Disponível e selecionada: fundo no destaque. Indisponível e selecionada: fundo neutro. |
| `disabledOpacity` (estático) | `Double` | `0.42` | Transparência do símbolo, título e atalho de ação indisponível (D6). |
| `spokenLabel(_:)` (estático) | `(AppCommand) -> String` | - | Rótulo do VoiceOver: título, atalho por extenso e motivo. Coberto por `CommandPaletteTests`. |

### CommandPaletteKeyboard

| Membro | Type | Description |
| --- | --- | --- |
| `action(keyCode:modifiers:situation:)` | `(UInt16, NSEvent.ModifierFlags, Situation) -> Action` | O que o monitor faz com a tecla. Fora da paleta, devolve `.passThrough` e a tecla segue normalmente. |
| `Situation` | `struct` | `paletteOpen`, `eventInPaletteWindow`, `modalOpen`, `sheetAttached`, lidos do AppKit no momento da tecla. |
| `Action` | `enum` | `.move(Int)`, `.execute`, `.close`, `.keepFocus` (Tab, ⇧Tab, ⌃Tab), `.passThrough`. |

### HiddenBehindCommandPalette

`ViewModifier` sem parâmetros. Lê `AppState.commandPalettePresented` e aplica `.accessibilityHidden` ao conteúdo. Em `ContentView`, vai na barra lateral, na coluna central e no inspector.

### CommandPaletteFocus

| Membro | Type | Description |
| --- | --- | --- |
| `restorable(_:in:)` | `(NSResponder?, NSWindow?) -> NSResponder?` | O responder a devolver ao fechar. Editor de campo vira o próprio campo; view fora da janela dá `nil`. |
| `blockingModifiers` | `NSEvent.ModifierFlags` | ⌘, ⌥ e ⌃: com qualquer um, a tecla não é da paleta. |

### Ambiente

| Chave | Obrigatória | Para quê |
| --- | --- | --- |
| `AppState` | sim (`CommandPaletteView`, `CommandPaletteOverlay`) | Contexto das ações e o sinal de aberta ou fechada |
| `EngineSession` | sim (`CommandPaletteView`) | Contexto (motor no ar, simuladores) e execução |
| `ThemeManager` | sim (as três) | Tokens de cor |
| `\.openSettings` | padrão do sistema | Executar "Ajustes…" |

Faltar um ambiente obrigatório derruba a view na hora (comportamento do `@Environment(Tipo.self)`), o que serve de aviso cedo no preview.

### Tokens usados

`DesignMetrics.CommandPalette.*` (largura, topo, altura do campo e do rodapé, altura máxima da lista, coluna do símbolo, espaços), `DesignMetrics.Radius.card` e `.menuItem`, `DesignMetrics.Shadow.floating*`, `DSFont.Symbol.field` e `.body`, `theme.floatingScrim`, `theme.floatingShadow`, `theme.separatorStrong`, `theme.accent`, `theme.onAccent`, `theme.warningTint`.

## Accessibility

- Papel: o painel é um grupo modal (`.isModal`) com rótulo "Paleta de comandos". Como o traço sozinho não prende o VoiceOver no SwiftUI hospedado pelo AppKit, a barra lateral, a coluna central e o inspector saem da árvore de acessibilidade enquanto a paleta está aberta (`HiddenBehindCommandPalette`). A toolbar é do AppKit e continua visível ao VoiceOver. Cada linha é apresentada como botão, com `.isSelected` na escolhida. Os títulos de seção são cabeçalhos.
- Teclado: ⇧⌘P abre. ↑ e ↓ movem a seleção (com volta ao início), Enter (Return ou Enter do teclado numérico) executa, Esc fecha. Um monitor local de teclado pega essas teclas antes do campo, e só quando são da paleta (`CommandPaletteKeyboard`): paleta aberta, tecla na janela onde ela abriu, sem sheet nem janela modal por cima e sem ⌘, ⌥ ou ⌃. Assim ⌘↑ e ⌥Return continuam com o campo, e as teclas de Ajustes ou de um painel de arquivo não mexem na paleta.
- Janela: se a janela da paleta perde o foco (Ajustes, painel de arquivo, outro app), a paleta fecha. O monitor sai no próprio fechar, antes da transição, para um Return rápido não executar de novo.
- Foco: ao abrir, o foco vai para o campo de busca. A seleção começa na primeira ação disponível. O foco de teclado nunca sai do campo: Tab, ⇧Tab e ⌃Tab são consumidos e devolvem o foco ao campo; as linhas não são paradas de Tab. Ao fechar sem executar (Esc, clique fora, janela sem foco), o foco volta para onde estava; um campo em edição volta como o próprio campo. Ao executar uma ação, o foco fica com o que a ação abrir.
- VoiceOver: ao mover com as setas, um anúncio lê a linha escolhida ("Rodar Automação, atalho Command R. Indisponível: Grave ao menos um passo"). Enter numa ação indisponível não executa: mostra o motivo numa faixa e o anuncia.
- Indisponível sem sumir: a linha fica a 42% com o motivo em `labelSecondary`, que é legível. Na seleção, ação indisponível não ganha o fundo de destaque, para não parecer que Enter vai executar.
- Movimento reduzido: a entrada e a saída são só opacidade (`Motion.crossfade`, 180 ms), que já serve a quem pede menos movimento. A rolagem até a linha escolhida não é animada. Não há outra animação.
- Contraste: texto principal em `labelPrimary`, motivo em `labelSecondary`. Selecionada e disponível: `onAccent` sobre `accent`, o par de botão do design system.
- Alvo: cada linha tem pelo menos 28 pt de altura (6 pt de respiro acima e abaixo do texto de 13 pt) e ocupa a largura do painel.
- Não testado: VoiceOver real com a paleta aberta, Controle Total por Teclado (Tab pela janela inteira), Aumentar contraste e Reduzir transparência sobre o `.regularMaterial`, uso por QA de verdade. O retorno do foco é testado na regra (`CommandPaletteFocus`), não com a paleta montada numa janela real.

## Features

- Busca aproximada sem acento e sem caixa, com sinônimos (ligar = iniciar = abrir; parar = desligar; buscar = filtrar; ajustes = preferências; gravar = capturar) e pontuação por palavra exata, prefixo, trecho e subsequência (`CommandSearch`).
- Até 5 recentes no topo quando o campo está vazio, guardadas em `UserDefaults` (`mobaile.paleta.recentes`).
- Ação indisponível aparece com o motivo, nunca some.
- A ação roda depois de a paleta fechar, para alerta ou sheet aberto por ela não disputar a tela.

## Troubleshooting

### ⌘K não abre a paleta

⌘K é Atualizar Tela desde antes da 3.5. A paleta usa ⇧⌘P (D2). Para trocar, mude `CommandID.palette` e `CommandID.captureNow` no `CommandRegistry`; o teste de atalhos únicos acusa conflito.

### As setas não movem o cursor no campo

É de propósito: enquanto a paleta está aberta, o monitor local consome ↑, ↓, Enter e Esc (sem ⌘, ⌥ ou ⌃) para a lista. ⌘↑ e ⌘↓ continuam levando o cursor ao início e ao fim do campo. O monitor sai ao fechar a paleta e, por garantia, no `onDisappear`.

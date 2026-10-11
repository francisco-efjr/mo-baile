---
title: EngineStatusBanner
description: Faixa de estado do motor em SwiftUI para o Mo baile, com mensagem real e botão Reiniciar Motor, para sair de motor caído ou Python inadequado sem fechar o app.
---

# EngineStatusBanner

A faixa do motor aparece no topo da coluna central quando o motor Python caiu e está sendo reiniciado, ou quando parou de vez (inclusive quando nem subiu por causa de um Python inadequado). Ela diz o que houve com o texto que veio do motor ou do `EngineLocator` e, quando ninguém vai tentar de novo sozinho, oferece **Reiniciar Motor** ali mesmo.

Código: `apps/MoBaile/Sources/MoBaile/Views/MainWindow/EngineStatusBanner.swift`.
Especificação: `docs/design/FLUIDEZ_3.5.md` (D7 e D8, FLU-2).

Partes:

- `EngineStatusBanner`: versão montada; lê `EngineSession.engineStatus` e liga o botão a `restartEngine()`.
- `EngineStatusBannerView`: o desenho, com estado e ação por parâmetro. É o que os previews usam.
- `EngineStatusBanner.Conteudo`: título, mensagem e tom de cada estado que merece faixa (testado em `EngineStatusTests`).

Previews no arquivo:

- "Parado: motor caiu de vez": a supervisão esgotou as 3 tentativas.
- "Reiniciando": progresso, sem botão, com a tentativa em curso.
- "Reinício pedido": progresso depois de Reiniciar Motor (faixa ou paleta), sem botão.
- "Python inadequado (escuro)": a mensagem real de `EngineLocator.unsuitableMessage`, com dois Pythons recusados.

## Uso

Onde é montado: `ContentView.swift`, acima do conteúdo da área central:

```swift
EngineStatusBanner()
```

Montagem isolada, sem `EngineSession`:

```swift
EngineStatusBannerView(status: .stopped("O motor está parado.")) {
    Task { await session.restartEngine() }
}
.environment(ThemeManager(preview: PraiaLightTheme()))
```

Em `.running` e `.starting` a view não desenha nada (o splash cobre a primeira subida), então pode ficar montada o tempo todo.

## API Reference

### EngineStatusBanner

Sem parâmetros. Lê `EngineSession` do ambiente.

### EngineStatusBannerView

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `status` | `EngineStatus` | - | Estado do motor. Só `.restarting(String)`, `.restartRequested` e `.stopped(String)` mostram faixa; a `String` é a mensagem exibida. |
| `onRestart` | `() -> Void` | - | Ação do botão Reiniciar Motor, que só existe no tom parado. |

### EngineStatusBanner.Conteudo

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `init?(_:)` | `EngineStatus` | - | `nil` quando o estado não merece faixa. |
| `titulo` | `String` | - | "O motor caiu. Reiniciando…", "Reiniciando o motor…" ou "O motor está parado". |
| `mensagem` | `String` | - | O motivo, como veio da sessão. |
| `tom` | `Tom` | - | Variante visual. |
| `reiniciando` | `Bool` | - | Atalho para `tom == .reiniciando`. |
| `anuncio` | `String` | - | Título e mensagem juntos, para o VoiceOver. |

### EngineStatusBanner.Conteudo.Tom

| Caso | Quando | Visual |
| --- | --- | --- |
| `.reiniciando` | A supervisão está subindo outro motor, ou o reinício pedido está em andamento | `warningTint`, spinner pequeno, sem botão |
| `.parado` | Supervisão desistiu, ou o motor nem subiu | `dangerTint`, octógono em `destructive`, botão Reiniciar Motor em destaque |

### Ambiente

| Chave | Obrigatória | Para quê |
| --- | --- | --- |
| `EngineSession` | sim (`EngineStatusBanner`) | Estado e reinício |
| `ThemeManager` | sim (`EngineStatusBannerView`) | Tokens de cor |
| `\.accessibilityReduceMotion` | padrão do sistema | Troca deslizar + esmaecer por só esmaecer |

### Tokens usados

`DesignMetrics.EngineBanner.*`, `DesignMetrics.Spacing.s1` e `.s6`, `DesignMetrics.hairline`, `DSFont.headline`, `.callout` e `.Symbol.banner`, `theme.warningTint`, `theme.dangerTint`, `theme.destructive`, `theme.labelPrimary`, `theme.labelSecondary`, `theme.separator`.

## Accessibility

- Papel: grupo com rótulo "Estado do motor". Título e mensagem formam um só elemento de leitura; o símbolo e o spinner ficam escondidos do VoiceOver. O botão é um `Button` nativo.
- Teclado: Reiniciar Motor é alcançável por Tab com Controle Total por Teclado ligado, e Espaço aciona. A mensagem aceita seleção de texto, para copiar o comando de instalação.
- Foco: a faixa não rouba o foco ao aparecer; quem está digitando continua onde estava. Ao apertar Reiniciar Motor o botão some (o tom vira reiniciando) e volta se o motor não subir.
- VoiceOver: ao mudar para reiniciando ou parado, um anúncio lê título e mensagem, porque o VoiceOver não percebe sozinho uma view que aparece fora do foco.
- Estado não só por cor: o tom muda o fundo, o símbolo (spinner ou octógono) e o título.
- Movimento reduzido: sem a preferência, a faixa desliza do topo e esmaece com `Motion.smooth`. Com `accessibilityReduceMotion`, ela só esmaece, e a animação vira o crossfade linear curto do `Motion.smooth(reduceMotion: true)`.
- Não testado: VoiceOver real lendo o anúncio, ordem de Tab na janela inteira, Aumentar contraste sobre `dangerTint` e `warningTint`.

## Features

- A mensagem é a da sessão, sem reescrita: no Python inadequado ela já diz o que foi achado, o que instalar e que depois é só usar Reiniciar Motor.
- Reiniciar Motor é o ciclo de vida que já existia (`disconnect()` + `connect()`), sem regra nova.
- `restartEngine()` é idempotente: um segundo pedido (duplo clique, faixa e paleta juntas) espera o primeiro, e uma supervisão em andamento é cancelada e aguardada antes. Sobra sempre um motor só. Enquanto isso o estado é `.restartRequested`: a faixa mostra progresso sem botão e a paleta desabilita Reiniciar Motor com o motivo "O motor está reiniciando" (`EngineSession.isRestarting`).
- O reinício limpa o cache da sonda do Python, então "instale o Pillow e use Reiniciar Motor" funciona sem reabrir o app.

## Troubleshooting

### A faixa não aparece com o motor fora do ar

Na primeira subida o estado é `.starting` e quem cobre é o splash. A faixa só aparece em `.restarting`, `.restartRequested` ou `.stopped`. Um erro de chamada qualquer com o motor conectado não é motor parado: `engineStatus` dá `.running` enquanto `isConnected` for verdadeiro.

---
title: DiagnosticCard
description: Cartão de diagnóstico por plataforma em SwiftUI para o Mo baile, com checagens medidas pelo motor e ênfase Próximo passo, para sair do estado sem aparelho.
---

# DiagnosticCard

O cartão de diagnóstico mostra, para iOS ou Android, as checagens que o motor mediu (simulador, WebDriverAgent, ADB, emulador) e um botão que faz o próximo passo. Na tela sem aparelho há dois cartões lado a lado, e só um por vez leva a ênfase **Próximo passo**, com o único botão em destaque da tela.

Código: `apps/MoBaile/Sources/MoBaile/Views/EmptyState/DiagnosticCard.swift`.
Especificação: `docs/design/FLUIDEZ_3.5.md` (D9, FLU-3).

Partes no mesmo arquivo:

- `DiagnosticCard`: o cartão.
- `NoDeviceRecommendation.pick`: escolhe qual cartão é o próximo passo (testado em `NoDeviceTests`).
- `DiagnosticCopy.natural`: traduz "2 AVD(s)" e "1 conectado(s)" do motor para linguagem natural.
- `NoDeviceView`: a tela que monta os dois cartões (fora deste contrato; ver a auditoria).

Previews no arquivo:

- "Próximo passo: iOS": simulador desligado (ação `boot_simulator`) com ênfase; Android com emulador parado, comum.
- "Próximo passo: Android (iOS pronto)": iOS pronto mostra "Pronto"; Android leva a ênfase.
- "Sem próximo passo: verificando e sem emulador (escuro)": iOS ainda verificando (spinner), Android sem emulador e botão desabilitado.
- "Próximo passo em andamento": ênfase com `isBusy`, o botão vira "Iniciando…".

## Uso

Onde é montado: `NoDeviceView`, no mesmo arquivo, um por plataforma:

```swift
DiagnosticCard(
    platform: .android,
    diagnostics: session.diagnostics?.android,
    isBusy: session.isBooting,
    action: { Task { await session.bootEmulator() } },
    actionTitle: "Abrir Emulador",
    actionEnabled: !session.avds.isEmpty,
    emphasis: recomendado == .android ? .nextStep : .standard
)
```

A ênfase vem de `NoDeviceRecommendation.pick(activePlatform:ios:android:)`: a plataforma em uso com ação pendente vence; na falta dela, vence a outra; sem ação executável, nenhum cartão é próximo passo.

## API Reference

### DiagnosticCard

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `platform` | `Platform` | - | Plataforma do cartão: ponto de cor (`PlatformIdentity`) e título de reserva. |
| `diagnostics` | `EngineDTO.PlatformDiagnostics?` | - | Checagens medidas pelo motor. `nil` mostra "Verificando ambiente…". |
| `isBusy` | `Bool` | - | Ação em andamento: o botão vira "Iniciando…" e fica desabilitado. |
| `action` | `() -> Void` | - | O que o botão faz. |
| `actionTitle` | `String` | - | Rótulo do botão, no verbo da ação ("Abrir Simulador", "Iniciar WebDriverAgent"). |
| `actionEnabled` | `Bool` | - | `false` desabilita o botão (por exemplo, sem emulador criado). |
| `emphasis` | `DiagnosticCard.Emphasis` | `.standard` | Ênfase na tela sem aparelho. |
| `symbol(_:)` (estático) | `(DaemonState) -> String` | - | Símbolo SF de cada estado de checagem. |

### DiagnosticCard.Emphasis

| Caso | Visual |
| --- | --- |
| `.standard` | Botão `.bordered`. Mostra "Pronto" no cabeçalho quando `diagnostics.ready`. |
| `.nextStep` | Etiqueta "Próximo passo" em `accentText`, aro de 1,5 pt em `accent` e o botão em destaque. Dica do VoiceOver: "Próximo passo recomendado". |

### Ambiente

| Chave | Obrigatória | Para quê |
| --- | --- | --- |
| `ThemeManager` | sim | Tokens de cor |

### Tokens usados

`DesignMetrics.DiagnosticCard.*` (altura mínima, ponto da plataforma, coluna do símbolo, aro, espaço do detalhe), `DesignMetrics.Widths.diagnosticCard`, `DesignMetrics.Spacing.s3` a `.s5` e `.groupBoxPadding`, `DesignMetrics.Radius.card`, `DSFont.body`, `.subheadline`, `.subheadlineSemibold`, `.callout` e `.Symbol.small`, `theme.success`, `.warning`, `.destructive`, `.info`, `.labelTertiary`, `.accent`, `.accentText`, e o modificador `.dsCard()`.

## Accessibility

- Papel: o título do cartão é cabeçalho. Cada checagem é um elemento só, lido como "Simulador ligado. atenção. Nenhum em execucao." (rótulo, palavra do estado, detalhe). O botão é um `Button` nativo.
- Teclado: o botão é alcançável por Tab com Controle Total por Teclado ligado, e Espaço aciona. Não há outra parte interativa no cartão.
- Foco: o cartão não move o foco ao carregar nem ao mudar de ênfase.
- VoiceOver: o cartão em destaque acrescenta a dica "Próximo passo recomendado" ao botão. O aro decorativo fica escondido.
- Estado não só por cor: cada checagem tem símbolo próprio (✓ círculo, triângulo, ✕ círculo, setas, traço), cor e palavra. A ênfase tem etiqueta em texto, aro e estilo de botão.
- Movimento reduzido: o cartão não anima. O único movimento é o spinner do sistema em "Verificando ambiente…".
- Não testado: VoiceOver real, Aumentar contraste sobre o aro de 1,5 pt, leitura da etiqueta "Próximo passo" na ordem certa em relação ao título.

## Features

- Um só botão em destaque na tela inteira, garantido pelo teste `testTextosAntigosSairamDaTela` (só um `.borderedProminent` no arquivo).
- O texto das checagens é o do motor; a interface só ajusta a forma (`DiagnosticCopy`), nunca o fato.

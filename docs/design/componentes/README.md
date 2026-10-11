# Componentes do Mo baile

Documentação, uma página por componente SwiftUI de `apps/MoBaile/Sources/MoBaile/Views`. O design system (tokens, cores, tipografia, movimento) fica em `apps/MoBaile/Sources/MoBaile/Theme/` e em `docs/design/design-system/`. Esta pasta trata da **forma** de cada componente, não da estética.

## Regra

**Todo componente novo segue o contrato.** São quatro partes:

1. **View + `#Preview` + doc.** A View e os `#Preview` com estados reais (vazio, com dados, desabilitado com motivo, erro) ficam no mesmo arquivo. O conteúdo é plausível, tirado do motor ou da especificação, sem lorem ipsum. A doc é uma página nesta pasta, feita a partir do [template](_template.md).
2. **Variantes em `enum` fechada.** Nada de `Bool` para estilo, e o padrão vem declarado no init.
3. **Ambiente e estado.** `@Environment` com padrão. Quando o componente tem estado que alguém de fora pode querer controlar, ele aceita um `Binding` opcional e usa um `@State` interno quando o `Binding` falta.
4. **Tokens, movimento e acessibilidade.**
   - Nenhuma cor nem medida crua: só `DesignMetrics`, `DSFont`, `Motion` e `ThemeTokens`. Medida própria do componente vira token de componente em `DesignTokens.swift`.
   - Animação lê `@Environment(\.accessibilityReduceMotion)` e passa o valor para `Motion`.
   - Comentário `///` em cada propriedade e init expostos.
   - A seção Accessibility da doc diz papel, teclado, foco, VoiceOver, movimento reduzido e o que **não** foi testado.

Componente que não cumpre uma regra registra o desvio e o motivo na própria doc.

O estado de cada componente que já existia antes do contrato está em [AUDITORIA_3.5.md](AUDITORIA_3.5.md).

## Índice

| Componente | Doc | Código | Origem |
| --- | --- | --- | --- |
| CommandPalette (overlay, painel e linha) | [command-palette.md](command-palette.md) | `Views/CommandPalette/CommandPaletteView.swift` | 3.5, FLU-1 |
| EngineStatusBanner | [engine-status-banner.md](engine-status-banner.md) | `Views/MainWindow/EngineStatusBanner.swift` | 3.5, FLU-2 |
| DiagnosticCard (Próximo passo) | [diagnostic-card.md](diagnostic-card.md) | `Views/EmptyState/DiagnosticCard.swift` | 3.5, FLU-3 |

## Previews

Os `#Preview` compilam no SwiftPM (`swift build` em `apps/MoBaile`, com o toolchain do Xcode) e aparecem no canvas do Xcode ao abrir o `Package.swift`. O termo controlado da paleta usa `@Previewable @State`. Os previews montam o tema com `ThemeManager(preview:)` e, quando precisam de sessão, uma `EngineSession` cujo motor nunca sobe.

## Atribuição

O contrato de forma e o template de página vêm do padrão de componente do playbook `ux-ui-design` do brain-of-agent (MIT). Esse padrão, por sua vez, segue a documentação de componentes do [cult-ui](https://github.com/nolly-studio/cult-ui) (MIT, © Jordan Gilliam / Nolly Studio) e foi adaptado aqui de React para SwiftUI. Os componentes e o texto desta pasta são do Mo baile. Nenhum código do cult-ui foi copiado.

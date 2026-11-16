---
title: [NomeDoComponente]
description: [O que é] em SwiftUI para o Mo baile, [com recursos-chave], [para qual tarefa do QA].
---

<!--
Template de documentação de componente SwiftUI do Mo baile.

Adaptado do T-14 do playbook ux-ui-design (brain-of-agent), que segue o
padrão de documentação do cult-ui (MIT, © Jordan Gilliam / Nolly Studio).
Mudanças para SwiftUI (§8 do padrão):
- sem Installation: o componente vive no próprio pacote `apps/MoBaile`;
- o demo é o `#Preview` no mesmo arquivo da View;
- a tabela de API lista os parâmetros dos inits, não props de React;
- variantes são `enum` fechada, estado controlável é `Binding` opcional.

Substitua cada [___]. Seção opcional sem conteúdo real sai da página.
Salve como docs/design/componentes/<nome-em-kebab>.md.
-->

# [NomeDoComponente]

[Primeira frase: o que é e onde aparece.] [Segunda frase: para que o QA usa.]

Código: `apps/MoBaile/Sources/MoBaile/Views/[Pasta]/[Arquivo].swift`.
Previews: [lista dos `#Preview` do arquivo, com o estado que cada um mostra].

## Uso

Onde é montado: [view que monta, arquivo e linha aproximada].

```swift
[NomeDoComponente]([parâmetros com valores reais])
    .environment(ThemeManager(preview: PraiaLightTheme()))
```

### Controlado

Quando há estado controlável (`Binding` opcional):

```swift
@State private var [valor] = [inicial]
[NomeDoComponente]([rotulo]: $[valor])
```

## API Reference

### [NomeDoComponente]

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `[param]` | `[Tipo]` | `[padrão]` ou - | [___] |

### [NomeDoComponente].[Variante]

| Caso | Quando |
| --- | --- |
| `.[caso]` | [___] |

### Ambiente

| Chave | Obrigatória | Para quê |
| --- | --- | --- |
| `ThemeManager` | sim | Tokens de cor da aparência e da paleta |
| `\.accessibilityReduceMotion` | padrão do sistema | [o que muda] |

## Accessibility

- Papel: [botão nativo, grupo com rótulo, cabeçalho, modal].
- Teclado: [Tab, Espaço, Enter, setas, Esc; o que cada uma faz].
- Foco: [para onde vai ao abrir e ao fechar; anel de foco do sistema].
- VoiceOver: [rótulo, dica, anúncio quando o estado muda].
- Movimento reduzido: [o que muda com `accessibilityReduceMotion`].
- Contraste: [tokens usados e a razão medida, se houver teste].
- Não testado: [VoiceOver real, Controle Total por Teclado, Aumentar contraste, etc.].

## Features

- [Recurso curto e verificável]

## Troubleshooting

### [Sintoma]

[Causa e correção.]

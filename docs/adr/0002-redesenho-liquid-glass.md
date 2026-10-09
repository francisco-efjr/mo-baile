# ADR 0002 — Redesenho 3.0: design system "Liquid Glass" com controles nativos

Data: 2026-10-08
Status: aceito

## Contexto

O design system "Mo baile · macOS 27 / Liquid Glass" (feito no Claude Design e
guardado em [`docs/design/design-system/`](../design/design-system/)) redesenha
o app no padrão de um app nativo do macOS, sem tirar nem inventar funções. A
estrutura muda: Sidebar | Espelho + Workspace | Inspector, uma toolbar
unificada no lugar das duas barras empilhadas, sheets no lugar dos modais
desenhados à mão, popover de correlação e janela de Ajustes.

O protótipo é HTML e CSS. Ele imita com `backdrop-filter`, sombras e cápsulas o
que o macOS 26 já desenha sozinho (toolbar de vidro, menus, popovers, alertas,
sheets, barra lateral com vibrancy, tabela que ordena e redimensiona colunas).

## Decisão

Implementar o design system com os componentes do sistema sempre que existe
um, e desenhar só o que o AppKit não tem.

- Janela: `NavigationSplitView` (sidebar), `.inspector` (hierarquia e
  atributos), `.toolbar` com `ToolbarItem`/`ToolbarSpacer` e `.searchable`
  (filtro de Rede e Analytics), `Table` para requisições, eventos e estrutura,
  `.sheet`, `.alert`, `.popover`, `.contextMenu` e a cena `Settings`.
- Vidro: o Liquid Glass vem do próprio macOS 26 na camada de navegação. O único
  uso explícito é o botão Rodar (`.glassProminent`, com recuo para
  `.borderedProminent` no macOS 14 e 15). O conteúdo não usa vidro.
- Tokens: `Theme/DesignTokens.swift` segue os nomes de `tokens/*.css`
  (rótulos, preenchimentos, fundos, destaque, semânticas, categorias, chips,
  sintaxe, HTTP), com Claro, Escuro e as duas variantes de Aumentar contraste.
  O destaque é o flamingo escurecido `#C2456E`, também compilado como
  `AccentColor` (`apps/MoBaile/AppResources/Assets.xcassets`) para a seleção
  nativa.
- Componentes próprios (`Views/DesignSystem/`): `StatusIndicator` (ícone, cor e
  texto, nunca só cor), `TypeChip`, `CountBadge`, `EmptyState`, `InlineError`,
  `AccessoryBar`, `DetailHeader`, `KeyValueGrid`, `CodeBlock`, `DSSearchField`
  e o cartão (`dsCard`). `DiagnosticCard` e a moldura do aparelho seguem as
  medidas do design system.
- Ícones: SF Symbols. O protótipo usa Lucide só porque SF Symbols não podem
  ser distribuídos na web.

## O que ficou de fora, e por quê

O protótipo mostra três coisas que o motor não oferece hoje. Elas não foram
simuladas na interface:

- **Excluir e reordenar um passo** (arrastar na barra lateral, ⌫, "Mover para
  Cima"): o motor só tem `codegen.reset`, que apaga todos. Precisa de
  `codegen.delete_step` e `codegen.move_step`.
- **Desfazer limpezas com ⌘Z**: o motor apaga tráfego, eventos e passos de
  verdade. Os alertas dizem que a ação não pode ser desfeita.
- **Editar WDA e proxy em Ajustes › Conexões**: o protocolo não tem como mudar
  esses endereços com o motor no ar. A aba mostra os valores do motor só para
  leitura.

## Consequências

- A largura mínima deixou de ser 1320 pt (a soma das duas barras antigas). A
  toolbar nativa manda o excedente para o menu », e cada coluna tem o seu
  mínimo.
- Testes de layout que liam pixels da barra antiga viraram testes da janela de
  verdade: `ToolbarLayoutTests` abre a janela e confere a toolbar instalada e o
  título da seção; `WindowSnapshotTests` fotografa a janela inteira (só com
  `MOBAILE_SNAPSHOT_DIR`).
- O `AccessibilityInspector` dos testes passou a ler também o protocolo antigo
  de acessibilidade do AppKit, que é como as linhas de `Table` e `List`
  aparecem para o VoiceOver.
- Mudança drástica de interface sobe a versão MAIOR: 2.1.2 → 3.0.0.

## Adendo (3.1.0): paletas alternativas

As nove paletas de `docs/design/paletas/` viraram `PaletteSpec` +
`PaletteTheme` (`Theme/Palettes.swift`). Só as cores de base são declaradas;
o resto é derivado com as fórmulas de `paletas-data.js` (opacidades da tinta,
mistura em sRGB para hover e pressionado, alto contraste). `PaletteTests`
compara cada variável de `palettes.css` com o token Swift. Uma paleta é clara
ou escura e impõe a aparência; a Praia segue a Aparência. A seleção nativa de
lista e tabela continua na cor de destaque do app/sistema (`AccentColor` é
fixo no `Assets.car`).

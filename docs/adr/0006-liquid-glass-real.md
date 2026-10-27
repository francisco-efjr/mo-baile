# ADR 0006 — Liquid Glass de verdade no macOS 26, por papéis

Data: 2026-10-26
Status: aceito

## Contexto

O ADR 0002 adotou o design system "Liquid Glass" com controles nativos e
deixou o vidro por conta do macOS 26. O único vidro explícito era o botão Rodar
(`.glassProminent`). O dono pediu o Liquid Glass real da Apple no app.

A pesquisa ([`docs/research/liquid-glass-macos26.md`](../research/liquid-glass-macos26.md))
e o diagnóstico do designer
([`docs/melhorias/2026-10-26-liquid-glass/revisao/ui-designer.md`](../melhorias/2026-10-26-liquid-glass/revisao/ui-designer.md))
chegaram a três conclusões:

- Compilado com o SDK 26, o app já recebe o vidro do sistema na toolbar, na
  barra lateral flutuante, no `.searchable`, nos popovers, sheets, menus e
  alertas. Não havia quase nada de vidro imitado. O único material desenhado à
  mão era o da paleta de comandos.
- O HIG põe o vidro só na camada de navegação e nos controles que flutuam sobre
  o conteúdo. Proíbe vidro sobre vidro e fundo próprio em toolbar, barra
  lateral, sheet ou popover. Usa o tom só na ação primária.
- O vidro do sistema já reage a Aumentar contraste (fica opaco, com borda) e a
  Reduzir movimento. Com Reduzir transparência, o `glassEffect` próprio fica
  mais fosco, mas não opaco.

## Decisão

1. **Uma API, por papel.**
   - `Views/DesignSystem/Glass.swift` expõe `mbGlass(_:in:interactive:)` com
     três papéis fechados (`GlassRole`):
     - `flutuante`: painel solto;
     - `capsula`: controle sobre conteúdo liso;
     - `midia`: vidro transparente sobre imagem.
   - O mesmo arquivo traz `mbProminentGlassButton(_:)` (o Rodar),
     `mbGlassTransition()` (`materialize`, ou nada com Reduzir movimento) e
     `mbBottomBar` (`safeAreaBar` no macOS 26).
   - A decisão entre vidro, material, preenchimento ou sólido é uma função pura
     (`GlassSurface.resolve`), testada em `GlassTests`.
   - Só `Glass.swift` e a toolbar falam com a API do macOS 26 (`#available`):
     `ToolbarContent` não aceita modificador de View. Um teste lê as fontes e
     barra o resto.
2. **Onde entra o vidro próprio:**

   | Superfície | Papel | macOS 26 | macOS 14 e 15 |
   | --- | --- | --- | --- |
   | Paleta de comandos | `flutuante` | `glassEffect(.regular)`, sem borda nem sombra próprias; transição `materialize` | `.regularMaterial` com borda e sombra (como antes) |
   | Cápsula do Ambiente na Início | `capsula` | `glassEffect(.regular.tint(fillPrimary).interactive())` | preenchimento `fillSecondary`, hover mais escuro |
   | Trilho do splash | `midia` | `glassEffect(.clear.tint(branco 30%))` | branco a 55% (como antes) |
   | Rodar | botão primário | estilo próprio: `glassEffect(.regular.tint(accent).interactive())`, rótulo `onAccent`, fora da cápsula compartilhada da toolbar | cápsula preenchida com o destaque, rótulo `onAccent` |

   O tom da cápsula existe porque vidro sobre fundo liso não tem o que refratar
   e some, sobretudo no escuro (visto nas capturas).

   O Rodar deixou o `.glassProminent` (e o `.borderedProminent` no recuo)
   porque os dois desenham o rótulo branco e ignoram o `foregroundStyle`. Na
   Costes o branco sobre o dourado dá 2,1:1 (visto na captura do recuo). O
   estilo próprio (`ProminentGlassButtonStyle`) pinta o rótulo com `onAccent`.
   Desabilitado ou com a janela inativa, perde o tom e o rótulo volta ao
   primário. No macOS 26 o item fica com `sharedBackgroundVisibility(.hidden)`,
   para não ser vidro dentro da cápsula da toolbar.
3. **Onde o sistema já faz, e o app só deixa de atrapalhar:**
   - Título da seção na toolbar: `sharedBackgroundVisibility(.hidden)`. É texto
     da janela e não deve ter cápsula de vidro.
   - Rodapé da barra lateral (Ambiente e estado do aparelho): `safeAreaBar` no
     macOS 26. A lista rola por baixo com o efeito de borda do sistema, sem
     vidro próprio.
   - Toolbar, barra lateral, popovers, sheets, menus e alertas ficam como estão.
4. **Onde não entra:**
   - Item Ambiente no rodapé da barra lateral: está dentro do vidro da barra
     lateral, e vidro ali seria vidro sobre vidro.
   - Morphing entre a cápsula da Início e o item da barra lateral: os dois
     ficam em colunas diferentes da `NavigationSplitView`, e o
     `glassEffectID` só funciona dentro de um mesmo `GlassEffectContainer`.
   - Barra acessória: logo abaixo da toolbar, seriam duas faixas de vidro
     empilhadas.
   - Cartões, tabelas, listas, editores, espelho, faixa do motor e barra de
     status: são conteúdo.
5. **Acessibilidade:**
   - Reduzir transparência: todo vidro próprio vira superfície opaca do tema,
     com borda, nos dois sistemas. É o que `tokens/materials.css` já pedia.
   - Aumentar contraste: o sistema põe a borda no vidro dele; no material e no
     sólido, a borda é `controlBorder`, mais forte.
   - Reduzir movimento: sem `materialize`.
   - O vidro lê o tema do ambiente quando há. O splash abre antes da janela e
     usa a Praia clara.
6. **Paletas.**
   - O tom do Rodar vem de `theme.accent` e o rótulo de `theme.onAccent`. Na
     Costes (destaque dourado), o rótulo branco dava 2,1:1.
   - Na Praia escura com Aumentar contraste, o branco sobre `#D9567F` dava
     3,8:1. O `onAccent` passou a ser o marinho `#141543`, que dá 4,6:1
     (`tokens/colors.css` e `PraiaDarkTheme`).
   - A barra lateral das paletas alternativas continua com a cor da paleta,
     dentro do recorte flutuante do sistema (D-1: manter). O vidro do sistema
     não aceita tom, e sem a cor a paleta perderia a identidade.

## Consequências

- Capturas:
  - `WindowSnapshotTests` deixou de cair no `cacheDisplay`, que desenha a
    janela sem o vidro e sem avisar. Sem captura do servidor de janelas, o
    teste falha.
  - O catálogo ganhou as cenas `11c` (Costes), `11d` (vidro nas 12
    aparências), `11e` (recuo do macOS 14 e 15, `MOBAILE_SEM_VIDRO=1`), `12`
    (paleta de comandos) e `13` (Reduzir transparência).
  - `MOBAILE_CENA=<prefixo>` refaz só algumas cenas.
- Tom nas capturas:
  - O macOS tira o tom de tudo quando o app está inativo: o Rodar tingido, o
    `.borderedProminent` e o `glassEffect` tingido.
  - O processo de teste só fica ativo se o app da frente ceder o foco.
  - O `catalogo.json` lista em `capturadasComAppInativo` as imagens tiradas
    assim.
- `MOBAILE_SEM_VIDRO=1` força o caminho do macOS 14 e 15 no que é do app.
  Aproxima o recuo, mas não substitui um Mac ou uma VM com 14 ou 15: o vidro
  do sistema na toolbar e na barra lateral continua, e os controles nativos
  saem com a aparência do 26. A captura num 14 ou 15 de verdade fica pendente.
- O design system web ganhou os papéis (`.mb-glass--flutuante`, `--capsula` e
  `--midia`), os tokens `--glass-clear-*` e `--glass-capsule-tint`, e o cartão
  `guidelines/materials-roles.html`.

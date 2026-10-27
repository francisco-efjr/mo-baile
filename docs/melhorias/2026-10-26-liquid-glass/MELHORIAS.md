# Liquid Glass de verdade (3.13.0)

## Resumo

O app passou a usar o Liquid Glass real do macOS 26 onde o HIG pede vidro.
Antes, no máximo imitava o vidro, ou não usava. O modo de trabalho foi o
orquestrador brain-of-agent (ORCHESTRATOR.md, opção B), com estes papéis:

- pesquisador (`consultor-pesquisador`): APIs no SDK local, HIG e os quatro
  repositórios indicados, em [`docs/research/liquid-glass-macos26.md`](../../research/liquid-glass-macos26.md);
- designer (`ux-ui-design:ui-designer`): inventário e decisões, em [`revisao/ui-designer.md`](revisao/ui-designer.md);
- implementação: o orquestrador;
- revisor independente (`mobile-apps:mobile-pr-reviewer`): [`revisao/mobile-pr-reviewer.md`](revisao/mobile-pr-reviewer.md).

As decisões estão no [ADR 0006](../../adr/0006-liquid-glass-real.md).

Lacuna do brain-of-agent: não há tag de conhecimento para macOS/SwiftUI
desktop. Usei a combinação "Telas novas ou redesign" (`ux-ui-design` +
`mobile-apps`).

O trabalho ficou na `main`, sem commit e sem branch nova. A sessão divide a
pasta com outras e não troca de branch. O dono commita quando quiser.

## Linha de base × depois

| Verificação | Antes (3.12.0) | Depois (3.13.0) |
| --- | --- | --- |
| `make check`: motor | 725 passed, 839 subtests | 725 passed, 839 subtests |
| `make check`: Tk e harness | 20 e 11 | 20 e 11 |
| `make check`: QA | 19, 31, 35, 34 e 26, todos OK | igual |
| `make check`: fixtures | em dia | em dia (regeradas: versão e CSS do relatório) |
| `make test-swift` | 393 testes, 27 pulados, 0 falhas | 404 testes, 27 pulados, 0 falhas |
| Catálogo de telas | 36 cenas, 72 PNGs, 37,9 MB, várias desatualizadas (2.x e 3.3) | 39 cenas, 73 PNGs em 1x, 18,6 MB |

## Mudanças

| ID | Especialista | Problema (arquivo:linha de antes) | Mudança | Como foi provado |
| --- | --- | --- | --- | --- |
| LG-1 | designer + orquestrador | Sem API de vidro: `#available` e estilos espalhados (`UnifiedToolbar.swift:312-325`) | `Views/DesignSystem/Glass.swift`: papéis `flutuante`, `capsula` e `midia`; `GlassSurface.resolve`; `mbProminentGlassButton`; `mbGlassTransition`; `mbBottomBar` | `GlassTests`: 11 testes, incluindo as guardas de fonte |
| LG-2 | designer | Paleta de comandos com material desenhado à mão (`CommandPaletteView.swift:101-106`) | Vidro do sistema com transição `materialize`; material com borda e sombra só no recuo | Cenas 12 (vidro) e 13 (sólido) |
| LG-3 | revisor (D1) | Rodar com `.glassProminent`/`.borderedProminent`: rótulo branco a 2,1:1 na Costes | `ProminentGlassButtonStyle` com rótulo `onAccent`, fora da cápsula compartilhada da toolbar | Cena 11e e `testRotuloDoRodarLegivelSobreODestaqueDeTodaPaleta` (22 temas) |
| LG-4 | designer | Título da seção dentro de uma cápsula de vidro na toolbar | `sharedBackgroundVisibility(.hidden)` | Capturas da janela |
| LG-5 | dono + designer | Cápsula do Ambiente na Início com preenchimento chapado (`HomeDaily.swift:113-116`) | Vidro interativo com o tom do tema e hover pelo modificador | Cenas 02c, 02e e 11d |
| LG-6 | dono | Splash com trilho branco a 55% (`SplashWindow.swift:205-215`) | Vidro transparente com véu branco | Cena 01 |
| LG-7 | pesquisa (HIG) | Rodapé da barra lateral com `safeAreaInset` (`AppSidebar.swift:78`) | `safeAreaBar` no macOS 26 (efeito de borda do sistema) | Cena 03b e `ToolbarLayoutTests` |
| LG-8 | `GlassTests` | Praia escura com Aumentar contraste: branco sobre o destaque a 3,8:1 (`PraiaDarkTheme.swift:48`) | `onAccent` marinho `#141543`, que dá 4,6:1, também em `tokens/colors.css` e no CSS do relatório | `GlassTests`, `ContrastTests` e `test_report_html` |
| LG-9 | pesquisa | `WindowSnapshotTests` caía no `cacheDisplay`, que apaga o vidro | Falha sem a captura do servidor; `MOBAILE_CENA`; lista de capturas com app inativo | Catálogo regenerado |

Diff de produção: `Glass.swift` com 231 linhas, mais 39 inclusões e 38
remoções nas telas. Testes: `GlassTests` com 180 linhas, mais 119 e 18 no
`WindowSnapshotTests`.

## Descartado ou não aplicado

- **Morphing entre a cápsula da Início e o item da barra lateral:** ficam em
  colunas diferentes da `NavigationSplitView`, e o `glassEffectID` exige o
  mesmo `GlassEffectContainer`.
- **Vidro no item Ambiente da barra lateral:** seria vidro sobre vidro. O
  rodapé ganhou o `safeAreaBar`.
- **Vidro na barra acessória:** seriam duas faixas de vidro empilhadas sob a
  toolbar.
- **Vidro em cartões, tabelas, editores, espelho e faixa do motor:** são
  conteúdo.
- **Fundo da barra lateral nas paletas alternativas (D-1):** fica a cor da
  paleta dentro do recorte flutuante. O vidro do sistema não aceita tom.
- **Reimplementar refração com shader (referência Kyant0/AndroidLiquidGlass):**
  não se aplica quando o sistema já desenha o vidro.

## Decisões tomadas pelo orquestrador (para o dono revisar)

1. **Versão 3.13.0 (MENOR), e não 4.0.0.** O critério do
   `docs/VERSIONAMENTO.md` para MAIOR é reaprender onde as coisas estão.
   Nada mudou de lugar. Para subir a MAIOR:
   `python3 tools/version.py bump major` (3.13.0 → 4.0.0), trocar o título da
   seção do CHANGELOG, rodar
   `make fixtures` e `make update-native`.
2. **A cápsula do Ambiente virou vidro.** O dono pediu, e o designer
   recomendava não (D-3). Ficou como controle de vidro, com tom do tema para
   não sumir sobre o fundo liso.
3. **Reduzir transparência força sólido no vidro do app (D-2),** como o
   `materials.css` já pedia.

## Próximos passos

- **Botões em destaque do conteúdo** (Início, Ambiente, faixa do motor,
  diagnóstico, editor de card): seguem `.borderedProminent`, com rótulo branco
  na Costes (2,1:1). Aplicar o recuo do `ProminentGlassButtonStyle`, sem vidro,
  porque é conteúdo.
- Capturar num macOS 14 ou 15 de verdade, ou numa VM, para fechar o recuo.
- Gravar a tela abrindo ⇧⌘P no app instalado, para conferir o `materialize`
  com e sem Reduzir movimento.
- Regerar o catálogo com o app de testes ativo (com o Terminal na frente, por
  exemplo), para as imagens mostrarem o tom do vidro.

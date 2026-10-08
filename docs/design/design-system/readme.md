# Mo baile — Design System (macOS 27 · Liquid Glass)

O Mo baile é um app de Mac para quem escreve testes automatizados de apps mobile (iOS e Android). Ele faz quatro coisas:
- **Espelho ao vivo**: mostra a tela do aparelho ou do simulador, e um clique no espelho vira toque no aparelho.
- **Hierarquia**: mostra a árvore de acessibilidade, a mesma que o Appium enxerga, igual para iOS e Android.
- **Page Objects**: gera um locator e um método para cada toque gravado, em Python/Appium.
- **Rede HTTP e Analytics**: registra o tráfego do aparelho por um proxy MITM local e os eventos de Firebase Analytics.

Este design system redesenha o app no padrão de um app nativo do macOS, sem tirar nem inventar funções. A estrutura segue o HIG. As cores vêm do ícone (flamingo + alien numa piscina).

## Fontes
- Catálogo de telas do app atual: `uploads/pdf-1791483110835-0ymn.pdf` (49 páginas, 16 telas e variações, claro e escuro).
- Repositório: **github.com/francisco-efjr/mo-baile** (branch `main`). Arquivos lidos: `README.md`, `docs/design/handoff-desktop/README.md` e, em `apps/MoBaile/Sources/MoBaile/`, `Theme/DesignTokens.swift`, `Theme/PraiaLightTheme.swift`, `Theme/PraiaDarkTheme.swift`, `Models/Enums.swift`, `Views/MainWindow/UnifiedToolbar.swift`, `Views/MainWindow/StatusBar.swift`, `App/MoBaileApp.swift`, `Views/Network/NetworkToolbar.swift`, `Views/Analytics/AnalyticsToolbar.swift` e `Views/EmptyState/DiagnosticCard.swift`.
- Ícone do app enviado pelo usuário: `assets/app-icon.png`. Mascote e fundo do splash vieram do repositório.

## Índice
- `styles.css`: só `@import`s (tokens + `components/mb.css`).
- `tokens/`: `colors.css` (Claro, Escuro e Alto contraste), `typography.css`, `spacing.css`, `shape.css` (raios e sombras), `materials.css` (Liquid Glass e Reduzir transparência), `motion.css` (molas e Reduzir movimento).
- `components/`: primitivos em React, com `.d.ts`, `.prompt.md` e um card por pasta.
- `guidelines/`: 20 cards de fundamentos (cores, tipo, espaço, materiais, movimento, marca).
- `ui_kits/macos-app/`: protótipo interativo completo, com uma nota por tela sobre o que mudou (README).
- `assets/`: `app-icon.png`, `icon.png`, `mascot.png`, `splash_bg.png`.
- `thumbnail.html`, `SKILL.md`, `github.md`.

## Components
Namespace: `window.MoBaileDesignSystem_ce6669`.
- **controls/**: Button, SegmentedControl, PopUpButton, SearchField, TextField, Switch, Checkbox
- **indicators/**: Icon, CountBadge, StatusIndicator, TypeChip, ProgressIndicator
- **navigation/**: Toolbar (+ ToolbarTitle, ToolbarSpacer), ToolbarButton, ToolbarGroup, ToolbarSearch, AccessoryBar, Sidebar, SidebarSection, SidebarItem, SidebarBottomBar
- **overlays/**: Menu (+ ContextMenu, portal), Popover, Tooltip, Sheet, Alert
- **window/**: Window, TrafficLights, MenuBar, DeviceFrame, Splitter
- **content/**: DataTable, DiagnosticCard, EmptyState (+ InlineError)

Mapeamento a partir do código Swift: FluidPillButton → Button / ToolbarButton · SegmentedControl → SegmentedControl · ActivityBadge → CountBadge · CanvasSwitch → Switch · PanelToggles → ToolbarButton (sidebar/inspector) · UnderlineTabBar → SegmentedControl pequeno (Headers | Body) · TypeChip → TypeChip · DaemonIndicator → StatusIndicator · SearchField → SearchField · MirrorRefreshButton → Button · CollapsedRail → animação de recolher o painel · DiagnosticCard → DiagnosticCard · DeviceBezel → DeviceFrame · StatusBar → StatusIndicator + barra de 22 pt.

### Intentional additions
Esses componentes não existem no app atual, mas o brief de macOS pede cada um deles: Checkbox e TextField (formulários de Ajustes), PopUpButton (escolha entre muitas opções), Toolbar/ToolbarGroup/ToolbarSearch/AccessoryBar (toolbar unificada com Liquid Glass), Sidebar*, Menu/ContextMenu, Popover, Tooltip, Sheet, Alert, Window, TrafficLights, MenuBar, Splitter, DataTable, EmptyState/InlineError e ProgressIndicator. O Icon embrulha o conjunto de glifos.

## CONTENT FUNDAMENTALS
- **Língua**: português do Brasil. O tom é direto, curto e cordial, e trata o usuário por "você" ("Grava o que você fizer direto no aparelho, sem clicar no espelho").
- **Botões**: verbo no infinitivo, com maiúscula em cada palavra principal, no estilo do macOS: "Rodar Automação", "Limpar Tráfego", "Iniciar WebDriverAgent", "Verificar de Novo". Quando o comando abre um painel ou pede mais informação, termina em reticências: "Exportar HAR…", "Estrutura…", "Ajustes…". Não use "OK" quando houver um verbo melhor.
- **Títulos de janela**: o nome da seção, nunca o do app ("Rede HTTP · 8 requisições").
- **Termos técnicos do domínio**: ficam como estão, em fonte mono (locator, XPath, `send_keys`, `CONNECT`, WDA 8100). Não traduza nomes de arquivo nem de método.
- **Erros**: dizem o que houve e o que fazer, sem código de erro. Exemplo: "Não foi possível iniciar o proxy. A porta 8082 já está em uso por outro app. Feche-o ou troque a porta em Ajustes › Conexões."
- **Tooltips**: frases curtas que explicam o efeito ("Exporta o tráfego capturado no formato HAR 1.2").
- **Estados vazios**: uma frase e uma ação ("Nenhum passo gravado" + "Gravar Passo").
- **Status**: em minúsculas e mono, só na barra de status e no rodapé do código ("procurando dispositivos…", "passo 6 · click · coords").
- **Sem emoji.** Os símbolos ✓ ! ✕ do original viraram ícones.

## VISUAL FOUNDATIONS
- **Cor**: a interface é neutra, levemente tingida de azul-marinho (os rótulos são `rgba(20,21,67,…)`). O destaque é o **flamingo escurecido `#C2456E`**, porque o `#F389A9` do ícone tem só 2,2:1 com branco. Ele aparece com parcimônia: seleção, botão padrão, links, controles ativos e a única cápsula tingida (Rodar). O azul-piscina fica só no papel de parede, na tela do aparelho e no splash, nunca em grandes áreas da interface. Os ícones da sidebar usam cores por categoria (flamingo, verde, azul). iOS `#0A84FF` e Android `#34C759` vêm do código.
- **Aparências**: Claro, Escuro e Alto contraste, todas como tokens. Na janela inativa, a seleção colorida vira cinza e a sombra da janela diminui.
- **Tipografia**: SF Pro (fonte do sistema), na escala do macOS: Body 13, Headline 13 Bold, Title 3 15, Title 2 17, Title 1 22, Large Title 26, auxiliares 10–12. A hierarquia vem de peso e de cor. SF Mono fica para código, logs, hosts e atributos, e os números usam `tabular-nums`.
- **Espaço**: grade de 4 pt. Margem de 20 em janelas e formulários. 14 entre a toolbar e o primeiro controle. 16 dentro de caixas. Toolbar com 52, barra acessória com 36, barra de status com 22 e barra inferior da sidebar com 32.
- **Raios concêntricos**: janela 16 → item de sidebar 8. Menu 10 → item 6. Aparelho 40 → tela 33 (padding 7). Os controles são cápsulas. Os cartões usam 12, os campos 7 e os chips 4.
- **Materiais**: o Liquid Glass Regular fica só na camada de navegação: cápsulas da toolbar, menus, popovers e alertas. Ele é feito com `backdrop-filter: blur(18px) saturate(1.6)`, fundo a 62%, um realce de 0,5 px na borda superior e uma sombra difusa. O conteúdo nunca usa vidro, e nunca há vidro sobre vidro: dentro de uma cápsula, a separação vem dos preenchimentos `--fill-*`. A tinta (flamingo a 88%) só vai no elemento primário. Com Reduzir transparência, tudo fica sólido.
- **Profundidade**: camadas e sombras suaves (`--shadow-*`). Nada de bordas grossas ou gradientes fortes. Os separadores têm 1 px na cor do sistema.
- **Fundos**: os do app são lisos. A única ilustração é o mascote no splash. O papel de parede do protótipo é um degradê azul-piscina, do topo para a base, como o ícone.
- **Movimento**: molas no estilo WWDC23. A *smooth* (0,5 s, bounce 0) é o padrão, para painéis e sheets. A *snappy* (0,35 s, bounce 0,15) é para cliques, segmentados e switches. A *bouncy* fica só para manipulação direta, e quase não aparece. Na CSS, as molas são `linear()` amostradas. Sidebar e inspector usam uma mola em JS que preserva a velocidade quando a animação é interrompida. Trocar de seção é um crossfade de 180 ms, menus aparecem na hora e somem em 150 ms, e o popover vai de 95 a 100% de escala com fade. Com Reduzir movimento, tudo vira crossfade.
- **Hover**: o fundo do item da toolbar ou do botão de barra aparece na hora (`--fill-secondary`). **Pressionado**: o controle escurece (`brightness(.9)` ou `--fill-primary`), sem ripple. **Desabilitado**: 42% de opacidade, sem sumir. **Foco**: um anel de 3 px em `--focus-ring` que segue a forma do controle.
- **Cartões**: fundo `--bg-group`, borda interna de 0,5 px, raio 12, sem sombra.
- **Transparência e desfoque**: só na sidebar (vibrancy), na toolbar, nos menus e nos popovers.
- **Imagens**: ilustração em estilo cartoon (contorno marinho, cores chapadas e quentes). Ela só aparece no ícone e no splash.

## ICONOGRAPHY
- O app nativo usa SF Symbols (`hand.tap`, `record.circle`, `stop.circle`, `network`, `square.and.arrow.up`, `antenna.radiowaves.left.and.right`…). Como os SF Symbols não podem ser distribuídos na web, **o projeto usa Lucide** (`lucide-static@0.460.0`, ISC) **no lugar deles**. São 67 glifos copiados para `components/indicators/Icon.jsx`, com traço de 1,6, para chegar perto do peso Regular dos SF Symbols ao lado de texto de 13 pt. Equivalências: `hand.tap` → `pointer`/`hand`, `record.circle` → `circle-dot`, `square.and.arrow.up` → `share`, `antenna…` → `radio-tower`, `sidebar.left` → `panel-left`.
- Os ícones da sidebar têm cor. Itens de menu só levam ícone nos principais. Todo botão só com ícone tem tooltip e `aria-label`.
- Não há emoji. Unicode só aparece nos atalhos (⌘ ⇧ ⌥ ⌃ ⌫).
- **Logo**: não há logotipo tipográfico. A marca é o ícone do app (`assets/app-icon.png`). Onde precisar do nome, use “Mo baile” em SF Pro.

## Substituições a validar
- **Fonte**: SF Pro e SF Mono vêm do sistema (pilha `-apple-system`), sem arquivos de fonte. No Mac, renderizam certo. Em outros sistemas, cai para Helvetica Neue ou similar.
- **Ícones**: Lucide no lugar de SF Symbols (ver acima).
- **Destaque**: o formulário não definiu um. Escolhi o flamingo escurecido (`#C2456E`) para ter contraste. As cores por categoria e a destrutiva também foram derivadas da paleta do ícone e do vermelho do sistema.

# Mo baile para macOS — protótipo interativo

`index.html` abre a janela completa (1280 × 800 pt) sobre um papel de parede azul-piscina, com a barra de menus simulada no topo. Um painel **Protótipo** no canto inferior direito controla aparência, acessibilidade, janela ativa/inativa e os estados de tela (conectado, carregando, erro, sem aparelho).

## Estrutura da janela
Sidebar | Espelho + Workspace | Inspector

- **Sidebar** (232–360, padrão 240): seção *Workspace* (Page Objects, Rede HTTP, Analytics) e seção *Fluxo* (passos gravados: arrastar para reordenar, menu de contexto, ⌫ exclui). A barra inferior tem Gravar Passo (+), Excluir Passo (−) e o status do aparelho.
- **Toolbar**: título da seção + subtítulo · aparelho (pop-up agrupado por iOS/Android) · Repassar toque | Gravar passo · [Gravar do aparelho, Gravar a tela, 60 FPS no Android] · ▶ Rodar (única cápsula tingida) · Buscar · Inspector. Abaixo de 700 pt os itens de gravação vão para o menu »; abaixo de 560 pt o segmentado vira pop-up.
- **Inspector** (260–380): Hierarquia (busca ⌘F, árvore com setas, menu de contexto) + Atributos (Copiar Tudo).
- **Sheets**: Estrutura do fluxo · Executar fluxo (sucesso/falha pelo painel Protótipo).
- **Popover**: Correlação (botão sob o espelho em Rede/Analytics).
- **Alertas**: Limpar Tráfego / Eventos / Passos (todos com ⌘Z para desfazer).
- **Ajustes** (⌘,): janela separada com abas Geral e Conexões.

## Atalhos
⌃⌘S barra lateral · ⌥⌘I inspector · ⌥1 espelho · ⌥2 workspace · ⌥⌘F todos os painéis · ⌘1/2/3 áreas · ⌘F buscar · ⌘R rodar · ⌘K atualizar tela · ⌘S salvar · ⌘Z/⇧⌘Z desfazer/refazer · ⌘, ajustes · Esc fecha sheets, menus e popovers.

## O que mudou em cada tela, e por quê
- **01 Splash**: igual ao original (mascote, piscina e barra de progresso). Aparece por 1,5 s e pode ser reaberto em Janela › Mostrar Splash.
- **02 Sem dispositivo (a, b, c)**: cartões e textos mantidos. O checklist agora usa ícone, cor e texto juntos, para não depender só de cor. Os botões viraram verbos no infinitivo: "Iniciar WebDriverAgent", "Abrir Emulador", "Verificar de Novo".
- **03/04 Janela e barra superior**: as duas barras viraram uma toolbar unificada. A seleção iOS | Android foi absorvida pelo pop-up de aparelhos, que agrupa por plataforma. O nome do app saiu do título, que agora mostra a seção. Os botões de painel viraram botões de sidebar e de inspector, que não mudam de lugar.
- **05 Coluna espelho**: a moldura e o "Atualizar" (⌘K) continuam. O cartão de Correlação virou um popover. Nas áreas de Rede e Analytics, o espelho fica compacto, como no original.
- **06 Hierarquia**: passou para o Inspector recolhível. Os chips de tipo continuam (W V T I B). Busca vazia, carregando e sem resultado têm estados próprios.
- **07/08 Workspace e estratégia**: Seletor, Estrutura… e Lado a lado ficam na barra acessória, só sobre o conteúdo. Sem lado a lado, um segmentado alterna entre pages e locators.
- **09/10 Passos e estrutura**: a lista de passos vai para a sidebar (seção Fluxo), com arraste. A Estrutura do fluxo abre como sheet.
- **11 Execução**: o modal virou uma sheet. Interromper é destrutivo e nunca é o botão padrão. Concluir fica desabilitado até o fim.
- **12 Rede**: o filtro passou para a busca da toolbar. A tabela ordena e redimensiona colunas. O detalhe usa os segmentados Headers | Body, e o túnel HTTPS e o erro 422 continuam com estados próprios.
- **13 Analytics**: segue a mesma estrutura de Rede, de propósito, para manter a consistência.
- **14 Barra de status**: mantida, em 22 pt, com o estado de cada serviço mostrado por ícone e texto.
- **15 Painéis recolhidos**: em vez de trilhos laterais de 30 pt, os painéis abrem e fecham com mola smooth. Os comandos ficam no menu Visualizar.
- **16 Componentes**: passaram a ser componentes do design system (ver `components/`).

## Arquivos
`App.jsx` (estado, toolbar, menus, atalhos) · `AppSidebar.jsx` · `Mirror.jsx` · `Inspector.jsx` · `PageObjects.jsx` · `Traffic.jsx` (Rede + Analytics) · `Sheets.jsx` · `NoDevice.jsx` · `Settings.jsx` (Ajustes + Splash) · `Demo.jsx` (painel do protótipo) · `data.js` · `spring.js` (mola com velocidade preservada para sidebar/inspector).

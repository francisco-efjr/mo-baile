# Changelog

Todas as mudanças relevantes do Mo baile ficam aqui, da mais nova para a mais
antiga. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e a numeração segue o [Versionamento Semântico](https://semver.org/lang/pt-BR/).
A regra de quando e como subir a versão está em [docs/VERSIONAMENTO.md](docs/VERSIONAMENTO.md).

## [3.0.0] - 2026-10-08

Redesenho do front nativo com o design system "Mo baile · macOS 27 / Liquid
Glass" ([`docs/design/design-system/`](docs/design/design-system/)). A
versão MAIOR sobe porque a interface muda de estrutura: quem usa precisa
reaprender onde as coisas estão. O motor e o protocolo RPC não mudaram.
Decisões em [ADR 0002](docs/adr/0002-redesenho-liquid-glass.md).

### Mudado

- Janela em três colunas no padrão do macOS: barra lateral (Page Objects, Rede
  HTTP, Analytics e os passos do fluxo), espelho com workspace, e inspector
  recolhível (⌥⌘I) com hierarquia e atributos.
- As duas barras empilhadas viraram uma toolbar unificada (Liquid Glass no
  macOS 26): título e subtítulo da seção, pop-up de aparelho agrupado por iOS e
  Android (absorveu o seletor de plataforma), Repassar toque | Gravar passo,
  gravação, Rodar (a única cápsula tingida), busca e inspector. Com pouco
  espaço, o macOS manda os itens para o menu ».
- Estrutura do fluxo e Executar fluxo viraram sheets. Interromper é destrutivo
  e nunca é o botão padrão; Concluir fica desabilitado até o fim.
- O cartão de Correlação virou um popover, aberto pelo botão sob o espelho em
  Rede e Analytics.
- Rede e Analytics usam a tabela do sistema, que ordena pelo cabeçalho e
  redimensiona as colunas. O filtro foi para a busca da toolbar (⌘F).
- Cores do design system nas aparências Clara e Escura, com variantes de
  Aumentar contraste. O destaque é o flamingo escurecido `#C2456E`, também na
  seleção nativa (`AccentColor` compilado no empacotamento).
- Indicadores de status com ícone, cor e texto (antes, só um ponto colorido).
- Painéis abrem e fecham com mola; trocar de área é um crossfade de 180 ms.
- Botões com verbo e maiúscula em cada palavra principal ("Abrir Simulador",
  "Verificar de Novo", "Exportar HAR…").
- Largura mínima da janela: de 1320 pt para o mínimo das colunas abertas.

### Adicionado

- Janela de Ajustes (⌘,): aparência (Sistema, Claro, Escuro, guardada entre
  aberturas), seletor padrão e "Iniciar o espelho automaticamente"; a aba
  Conexões mostra os endereços do motor.
- Passos do fluxo na barra lateral. Escolher um passo destaca o código dele
  nos editores; menu de contexto com Copiar Locator e Copiar Seletor.
- Inspector: árvore expandida, com ← e → para recolher e expandir, menu de
  contexto (Copiar Locator, Copiar XPath, Copiar Atributos, Gravar como Passo)
  e o elemento escolhido destacado também no espelho.
- Menus Arquivo, Editar, Visualizar, Dispositivo, Automação e Janela com todas
  as ações da toolbar e atalhos (⌘1/⌘2/⌘3, ⌥1/⌥2, ⌃⌘Z Modo Zen, ⌘R, ⌘K,
  ⇧⌘E, ⌘S).
- Splash de abertura (1,5 s) com o mascote; reabre em Janela › Mostrar Splash.
- Rede: Copiar como cURL no menu de contexto e erro em linha quando o proxy
  não sobe, com "Tentar de Novo".

### Corrigido

- "Copiar tudo" dos atributos não fazia nada; agora copia.
- O atributo "enabled" mostrava `clickable`; passou a se chamar `clickable`.
- A execução de fluxo contava como aprovados todos os passos gravados e
  mostrava "tempo 0.0 s" fixo; agora conta os aprovados de fato e mede o tempo
  pelo log do runner.
- Sem tráfego capturado, "Gerar Asserção de Contrato" inseria um endpoint fixo
  com status 200; agora o botão fica desabilitado, e sem status a asserção não
  inventa um.
- O texto digitado nos passos de digitação aparece mascarado na barra lateral e
  na execução.
- O campo de busca da hierarquia não ganha mais foco sozinho ao abrir a janela.
- O editor recolore o código ao trocar de aparência.

### Removido

- Componentes próprios substituídos por controles do sistema: `FluidPillButton`,
  `SegmentedControl`, `ActivityBadge`, `CanvasSwitch`, `UnderlineTabBar`,
  `CollapsedRail` e `PanelToggles`.

## [2.1.2] - 2026-10-06

### Adicionado

- `AGENTS.md` (importado pelo `CLAUDE.md`): todo agente que mexe em
  `engine/src/`, `apps/MoBaile/` ou `assets/` só conclui a tarefa com o
  "Mo baile (nativo).app" desta máquina reempacotado e verificado.
- `make verify-native` (`tools/verify_native_app.sh`): confere se a versão
  instalada é igual a `VERSION`, se o motor embutido é idêntico a
  `engine/src` e se o `engine.hello` responde pelo Python que o app usa.
  `make update-native` empacota e verifica.

## [2.1.1] - 2026-10-06

### Corrigido

- Execução de fluxo: o texto digitado não aparece mais no `flow.log`, nas
  notificações nem no stdout do motor; o log registra só o tamanho e o campo.
  Passo de digitação sem texto falha com motivo, em vez de digitar os textos
  inventados "Texto de Exemplo" ou "Texto de Teste".
- Proxy: redação de credenciais em corpo, URL, Location/Referer e erros;
  encaminhamento em blocos com teto de captura; recusas tipadas (400/413/501/502)
  sem chamar a origem; `Proxy-Authorization` não chega à origem.
- `flow.stop` cooperativo entre passos; falha de ADB reprova o passo.
- Front Swift preserva passos, edições e evidências quando o RPC falha e
  descarta respostas antigas de hierarquia pela geração.
- Gate de QA exige resumo válido, usa ferramentas falsas e portas efêmeras;
  testes Tkinter distinguem skip de erro.

### Acessibilidade

- Rótulos, estados e papéis para VoiceOver na toolbar, controles segmentados,
  abas, tabelas HTTP e de analytics, editores, espelho e estado vazio, com
  testes que leem a árvore de acessibilidade real do macOS.

### Documentação

- Revisão de QA de 05/10 (`docs/QA_2026-10-05.md`), relatório de pontos de
  melhoria (`docs/research/pontos-de-melhoria-2026-10-05.md`) e pendências da
  rodada de melhorias, com análise item a item e o trabalho parcial preservado
  (`docs/RODADA_2026-10-05_PENDENCIAS.md`).

## [2.1.0] - 2026-10-01

### Adicionado

- Tagueamento iOS no simulador: a aba Analytics lê o log do Firebase
  (`-FIRDebugEnabled`) pelo `log stream` do simulador, remontando a mensagem de
  várias linhas e mostrando um evento só por disparo, mesmo com o SDK logando
  cada evento em mais de um estágio.
- Tagueamento iOS em iPhone físico por cabo, via `pymobiledevice3` (dependência
  opcional `engine[ios-device]`). Seletor de origem na aba Analytics
  (Automático, Simulador ou o iPhone) e método `analytics.ios_devices`.
- Protocolo JSON-RPC v2 (etapa 1, "motor que não trava"): `engine.hello` com
  aperto de mão versionado, seis filas de despacho declaradas em
  `rpc/contract.py`, `$/cancelRequest` e `$/progress`.
- Cliente Swift com prazo por método vindo do motor, quadros sem acúmulo e
  reinício automático do motor quando ele cai.
- Estudo de mercado e plano de evolução em `docs/research/estudo-mercado/`.
- Versionamento: arquivo `VERSION`, este CHANGELOG, `tools/version.py`, hook de
  `pre-push` e verificação no CI.

### Corrigido

- Parar e reiniciar a escuta de analytics duplicava cada evento na interface.
- Estado da sessão protegido por lock e época; o desmonte do motor sobrevive a
  SIGTERM.

### Desempenho

- Import do motor de ~250 ms para ~60 ms, com dependências pesadas carregadas
  só quando usadas.

## [2.0.0] - 2026-09-08

Linha de base: primeira versão declarada, antes do versionamento formal. Motor
headless em Python com fronteira JSON-RPC, interface Tkinter e front nativo
SwiftUI em construção.

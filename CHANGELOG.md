# Changelog

Todas as mudanças relevantes do Mo baile ficam aqui, da mais nova para a mais
antiga. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e a numeração segue o [Versionamento Semântico](https://semver.org/lang/pt-BR/).
A regra de quando e como subir a versão está em [docs/VERSIONAMENTO.md](docs/VERSIONAMENTO.md).

## [3.3.0] - 2026-10-09

Rodada de melhorias de 09/10: três pedidas, os defeitos que o catálogo de telas
novo mostrou e a revisão de produto em
[docs/MELHORIAS_2026-10-09.md](docs/MELHORIAS_2026-10-09.md).

### Adicionado

- **App em Debug no Android:** tráfego HTTPS do app em debug sem proxy nem
  certificado, lido do logcat (log do `HttpLoggingInterceptor` do OkHttp).
  Funciona com o debugger do Android Studio conectado. É a mesma ação do
  "iPhone em Debug" ([ADR 0004](docs/adr/0004-https-sem-proxy-android.md)).
- Catálogo de telas da 3.x em `docs/design/telas/`: 29 telas e estados em
  claro e escuro, PDF e folha de contato, gerados por
  `WindowSnapshotTests.testCatalogoDeTelas` e `tools/catalogo_telas.py`. O
  catálogo da 2.x foi para `docs/design/telas/arquivo-2.x/`.

### Mudado

- **Busca em tudo:** a busca da toolbar procura em qualquer dado capturado. Na
  Rede: URL, query, headers (nome e valor), corpos e erro. No Analytics: nome,
  parâmetros (chave e valor), origem e log bruto. No Relatório: evento,
  variação, divergência e parâmetros do disparo. Cada palavra precisa
  aparecer em algum campo, sem diferenciar maiúsculas nem acentos.
- **Splash que espera o app:** fica até o motor responder e a primeira
  varredura de aparelhos e do ambiente terminar, com a fase escrita na tela
  ("Iniciando o motor…", "Procurando aparelhos e simuladores…"), mínimo de
  2,5 s e teto de 12 s. Se o motor falhar, sai para o erro aparecer na janela.
- A barra de status cede espaço em largura estreita (só ícones dos serviços,
  métricas curtas) em vez de impor 690 pt à janela.
- `netlog.start` escolhe a fonte pela plataforma da sessão e devolve `source`.

### Corrigido

- O corpo JSON da Rede mostrava `28.399999999999999` no lugar de `28.4` e
  reordenava as chaves. Agora a indentação é feita sobre o texto original.
- O popover de Correlação mostrava `AutomationStep(stepNum: …)`. Agora mostra a
  frase do passo e o locator.
- "1 aprovados" no rodapé da execução.
- O passo por coordenada aparecia como "click position" (valor interno). Agora
  é "toque em x, y".

## [3.2.0] - 2026-10-08

Aba **Relatório**: a auditoria de tagueamento do `tag_audit` (projeto
bold-kepler) agora roda dentro do Mo baile, no motor. Decisões em
[ADR 0003](docs/adr/0003-relatorio-tagueamento.md); anatomia da tela em
[docs/design/relatorio.md](docs/design/relatorio.md).

### Adicionado

- Relatório na barra lateral (⌘4), sem precisar de aparelho: abre a
  spec-modelo dos cards do Figma, audita os eventos que a escuta de Analytics
  capturou nesta sessão ou um log exportado (`log_obtido.json`, Logcat em
  texto) e mostra a conformidade, uma linha por variação (card × fluxo ×
  variação) e, para cada uma, o parâmetro obtido e o esperado, o bloco com ✓/✗
  e o disparo avaliado. O inspector mostra o card do Figma da linha.
- Recortes: Pedem Ação, Divergentes, Não Disparadas, OK e Fora da Spec
  (eventos dos fluxos que nenhum card cobre, e alertas de `app_exception` e
  `error_view`). A busca da toolbar (⌘F) filtra a tabela.
- Exportar grava o board Excalidraw, o HTML, o Markdown e o TSV em
  Documentos › Mo baile › Relatórios, ou na pasta escolhida. Copiar põe o TSV
  (Google Planilhas) ou o Markdown (PR, Jira) na área de transferência.
- Importar Prints do Figma: o OCR do macOS (Vision, local) lê os cards e grava
  o rascunho da spec, sem sobrescrever spec existente, com a lista do que
  conferir em cada card.
- Arquivo › Abrir Spec de Tagueamento… (⌘O), Importar Prints do Figma… e
  Exportar Relatório….
- Contrato: `report.spec`, `report.audit`, `report.export` e `report.import`,
  numa fila própria (`report`), com progresso. O relatório não espera nem
  segura o aparelho.
- Fluxo 5 do harness de QA (relatório de ponta a ponta, 26 verificações).

### Mudado

- Em relação ao `tag_audit`: regex inválida na spec é recusada ao abrir (antes
  quebrava a auditoria no meio); o board sai determinístico (ids por contador,
  não `uuid4`); spec, log e pastas passam por validação de caminho e de
  tamanho antes de abrir. As regras de casamento são as mesmas: Markdown, TSV e
  HTML saem idênticos aos do `tag_audit` para os mesmos arquivos.

### Fora desta versão

- O pipeline antigo `run` do `tag_audit`, a sincronização com o WebKit do
  *Francis' DrawCred* e a saída com código 2 para CI (ver ADR 0003).

## [3.1.0] - 2026-10-08

### Adicionado

- Ajustes › Paletas: galeria com nove paletas alternativas inspiradas em
  designers de interiores (`docs/design/paletas/`). São quatro claras (Sálvia
  & Palha, Azulejo/Sig Bergamin, Hampshire/Dorothy Draper, Veludo
  Rosé/India Mahdavi), quatro escuras (Terracota/Kelly Wearstler,
  Costes/Jacques Garcia, Geométrico/David Hicks, Mármore/Joseph Dirand) e uma
  extra (Jardim Digital/Antoni Tudisco). Cada cartão mostra uma mini-janela de
  prévia nas cores da paleta, as 11 amostras e as oito checagens de contraste
  (WCAG e distância OKLab entre o destaque e as cores de estado). "Usar
  Paleta" aplica o tema na hora, e a escolha é guardada.
- Cada paleta tem variação de Aumentar contraste. O que ela não declara
  (sintaxe, chips, GET/POST, terminal) vem da Praia da mesma aparência.

### Mudado

- Uma paleta clara ou escura define a aparência do app. Em Ajustes › Geral, a
  Aparência fica desabilitada e oferece "Voltar para a Praia". A Praia
  continua sendo o padrão e segue Sistema, Claro ou Escuro.
- Com uma paleta alternativa, a barra lateral usa a cor de barra lateral da
  paleta no lugar do material do sistema.

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
- Rede no iOS: "iPhone em Debug" lê pelo cabo as requisições do app em debug,
  sem proxy nem certificado (`netlog.start` / `netlog.stop`, a partir do log
  `CFNETWORK_DIAGNOSTICS=3`). Rede e Analytics mostram o mais novo no topo.

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

- `ScreenCatalogTests`, que fotografava as telas da 2.x; a janela 3.0 é
  fotografada por `WindowSnapshotTests` (com `MOBAILE_SNAPSHOT_DIR`).
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

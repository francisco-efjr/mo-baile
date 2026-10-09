# Melhorias — revisão de produto de 09/10/2026

Revisão do Mo baile inteiro com o olhar de quem cuida de um app da Apple:
design (HIG e o design system Liquid Glass), fluidez, integração com o macOS,
arquitetura e qualidade. A base é o [catálogo de telas 3.2](design/telas/CHECKLIST.md)
(29 telas, claro e escuro), medições na janela de verdade e leitura do código.
Cada item diz o problema com a evidência, o que fazer, o esforço (P, M, G) e a
prioridade.

**P0** quebra uso ou confiança e vem primeiro. **P1** é o que separa uma
ferramenta de um app de Mac. **P2** amplia o alcance.

## Já entregue nesta rodada (3.3.0)

| Item | O que mudou |
|---|---|
| Busca em tudo | Rede procura em URL, query, headers (nome e valor), corpos e erro; Analytics em nome, parâmetros (chave e valor), origem e log bruto; Relatório em evento, variação, divergência e parâmetros do disparo. Cada palavra precisa aparecer, sem diferenciar maiúsculas nem acentos. |
| App em Debug no Android | HTTPS sem proxy nem certificado, lendo do logcat o log do `HttpLoggingInterceptor` do OkHttp. Funciona com o debugger do Android Studio conectado. Mesma ação do "iPhone em Debug". |
| Splash que espera o app | Fica até o motor responder e a primeira varredura de aparelhos e ambiente terminar, com mínimo de 2,5 s, teto de 12 s e a fase escrita na tela. |
| Defeitos do catálogo | JSON da Rede com os números e a ordem originais; Correlação com a frase do passo em vez de `AutomationStep(...)`; "1 aprovado"; passo por coordenada como "toque em x, y"; barra de status que cede espaço em vez de impor 690 pt. |

## Design e HIG

| # | Melhoria | Evidência | Como fazer | Esforço | Prioridade |
|---|---|---|---|---|---|
| D1 | **A janela precisa caber num MacBook** | `contentMinSize` medido: 1.885 pt (Page Objects), 1.865 (Rede), 1.746 (Relatório). Sem barra lateral nem inspector cai para 581. O mínimo declarado é 980 e a tela de um MacBook Air tem 1.470. | Investigar a soma da `NavigationSplitView` com `.inspector` e o `HSplitView` interno (barra lateral soma 744 pt, inspector 560, bem acima dos mínimos declarados). Caminho provável: trocar o `HSplitView` por `NavigationSplitView` de três colunas ou por `HStack` com `.layoutPriority`, e testar o mínimo em `ToolbarLayoutTests` com `contentMinSize <= 1100`. | M | **P0** |
| D2 | **Rodar desabilitado some no tema claro** | Catálogo 03 e 03b: play branco sobre cápsula clara. | Desabilitado com `.glassProminent` precisa de contraste próprio: use o estilo padrão quando `!podeRodar` e a cápsula tingida só quando dá para rodar. | P | **P0** |
| D3 | **Inspector contextual** | Sem aparelho, o inspector repete "Conecte um aparelho" ao lado do estado vazio (02, 02b), ocupando 260 pt. | Esconder o inspector automaticamente quando não há aparelho e devolvê-lo ao conectar, respeitando a escolha manual (como o Xcode faz com o inspector sem seleção). No Relatório ele já mostra o card do Figma. | P | P1 |
| D4 | **Barra de status por plataforma** | "ADB server" aparece numa sessão iOS e "WDA" numa Android (03b). | Mostrar só os serviços da plataforma ativa; o resto vai para o tooltip. | P | P1 |
| D5 | **Menu » aparece com janela larga** | Catálogo 03, 04: o chevron está lá a 1.885 pt. | Conferir quais itens o macOS manda para o menu (o `ScrcpyButton` some no iOS e deixa o grupo inconsistente) e dar `id` e prioridade estáveis aos itens. | P | P1 |
| D6 | **Tokens de busca (Console.app)** | A busca agora olha tudo; falta recortar por campo. | `.searchable(text:tokens:)` com sugestões: `status:4xx`, `método:POST`, `host:api…`, `evento:screen_view`, `param:ga_screen`. É como o Console e o Mail fazem. | M | P1 |
| D7 | **Escopo da tabela de Rede** | Sem filtro por tipo, o JSON da API divide a tabela com imagens e telemetria. | Barra de escopo acima da tabela: Todos · API (JSON) · Mídia · Erros (4xx/5xx) · Lentas (> 1 s). | P | P1 |
| D8 | **Colunas lembradas** | Larguras, ordem e colunas visíveis se perdem a cada abertura. | `TableColumnCustomization` com `@SceneStorage` em Rede, Analytics e Relatório. | P | P1 |
| D9 | **Cor de categoria própria do Relatório** | Hoje reusa o verde do Analytics. | `cat4` nas quatro aparências e nas nove paletas (o `PaletteTests` cobre). | M | P2 |

## Fluidez

| # | Melhoria | Evidência | Como fazer | Esforço | Prioridade |
|---|---|---|---|---|---|
| F1 | **Espelho em JPEG e fora do JSON** | Cada quadro vira PNG + base64 dentro do JSON-RPC (ADR 0001, plano da etapa 2.1). | JPEG já reduz a carga; o passo seguinte é um socket ou memória compartilhada (`IOSurface`) só para quadros, deixando o RPC para comandos. | M | P1 |
| F2 | **Busca sem travar com tráfego grande** | A busca nova lê corpos de até 256 KB a cada tecla. | Índice de texto por evento, montado uma vez na chegada (minúsculas e sem acento), e filtro com debounce de 150 ms. | P | P1 |
| F3 | **Estado restaurado ao abrir** | Nenhum `@SceneStorage`: área, inspector, divisórias e tamanho voltam ao padrão. | `@SceneStorage` para área, inspector, espelho e workspace; `NSWindow` com `setFrameAutosaveName`. | P | P1 |
| F4 | **Animação de chegada de linha** | Requisição nova aparece de uma vez no topo da tabela. | Realce de 1 s na linha nova (fundo `accent` a 12% que some), como o Mail faz com mensagem nova; com Reduzir movimento, sem realce. | P | P2 |

## Plataforma Apple

| # | Melhoria | Evidência | Como fazer | Esforço | Prioridade |
|---|---|---|---|---|---|
| A1 | **Assinatura Developer ID, notarização e Python embutido** | O app é assinado ad-hoc e depende do Python do sistema (AGENTS.md item 4: dependência nova quebra o app). | Runtime Python próprio dentro do bundle (python-build-standalone), Hardened Runtime, notarização e atualização automática (Sparkle). Acaba com "funciona na minha máquina". | G | **P0** |
| A2 | **Desfazer de verdade (⌘Z)** | Limpar tráfego, eventos e passos apaga no motor (ADR 0002, "o que ficou de fora"). | Lixeira no motor (`*.clear` guarda o último lote, `*.restore` devolve) e `UndoManager` no front. | M | P1 |
| A3 | **Notificações de operação longa** | Compilar o WDA leva minutos; a auditoria e o OCR também levam tempo. Nenhum `UserNotifications`. | Notificação quando terminar com o app em segundo plano, e selo no Dock com o número de divergências do Relatório. | P | P1 |
| A4 | **Dicas contextuais (TipKit)** | Recursos como "App em Debug", busca em tudo, ⌘4 e Importar Prints não são descobertos. Nenhum TipKit. | `TipKit` (macOS 14): uma dica por recurso, mostrada uma vez, no lugar certo. | P | P1 |
| A5 | **Atalhos e automação (App Intents)** | A auditoria de tagueamento só roda clicando. | `AppIntent` "Auditar Tagueamento" (spec + log → conformidade) para Atalhos e Spotlight, e o mesmo caso de uso pela linha de comando do motor com saída 2 em divergência, para CI. | M | P1 |
| A6 | **Sessão como documento** | Tráfego, eventos, passos e relatório somem ao fechar. | Arquivo `.mobaile` (Arquivo › Salvar Sessão) com HAR, eventos, passos e relatório, aberto de novo no app, como um trace do Instruments. | G | P2 |
| A7 | **Log unificado** | O front não usa `os.Logger`; o motor escreve no stderr. | `Logger(subsystem: "br.com.mobaile", category:)` no front e o stderr do motor encaminhado para a mesma categoria: tudo aparece no Console.app. | P | P1 |
| A8 | **Quick Look** | Board, HTML e spec exportados só abrem fora do app. | `QLPreviewPanel` no Relatório (barra de espaço sobre o arquivo exportado) e prévia do print do card. | P | P2 |
| A9 | **Várias janelas, um aparelho por janela** | Uma janela só; trocar de aparelho troca a sessão inteira. | `WindowGroup(for: DeviceID.self)`: cada janela com o seu aparelho e o seu motor. | G | P2 |
| A10 | **Localização** | Todo texto está escrito no código, em português. | String Catalog (`.xcstrings`) com pt-BR como base; inglês depois. | M | P2 |

## Arquitetura

| # | Melhoria | Evidência | Como fazer | Esforço | Prioridade |
|---|---|---|---|---|---|
| R1 | **Servidor RPC por domínio** | `rpc/server.py` tem 1.743 linhas e concentra todos os handlers. | Um módulo de handlers por domínio (`rpc/handlers/network.py`, `analytics.py`, `report.py`…) registrando na tabela do `contract.py`. O despacho e as filas não mudam. | M | P1 |
| R2 | **Sessão do front por funcionalidade** | `EngineSession.swift` tem 1.457 linhas. | Coordenadores `@Observable` por área (Rede, Analytics, Relatório, Automação) sobre o mesmo cliente; a sessão fica com ciclo de vida, handshake e notificações. | M | P1 |
| R3 | **Porta de "tráfego sem proxy"** | iPhone (CFNetwork) e Android (OkHttp) agora são dois adapters com o mesmo papel. | Porta `DebugTrafficSource` em `ports/`, escolhida pela plataforma, para um terceiro formato (Ktor, `HttpURLConnection` via agente) entrar sem tocar no servidor. | P | P2 |
| R4 | **Concorrência estrita do Swift 6** | O build mostra avisos de `Sendable` (`KeyPathComparator`, `ThemeManager`). | Resolver os avisos e ligar o modo Swift 6; hoje são avisos, no Swift 6 viram erro. | M | P1 |
| R5 | **Network Inspector completo no Android** | O "App em Debug" depende do app ter o interceptor do OkHttp. O App Inspection do Android Studio vê tudo porque injeta um agente JVMTI (`am attach-agent`). | Estudo com o `consultor-pesquisador` sobre o protocolo do App Inspection, antes de decidir. | G | P2 |

## Qualidade

| # | Melhoria | Evidência | Como fazer | Esforço | Prioridade |
|---|---|---|---|---|---|
| Q1 | **Regressão visual automática** | O catálogo é gerado à mão e revisado a olho. | Comparar as capturas com uma linha de base (diferença por pixel com tolerância) num runner macOS do CI, com a tela ativa. Quebra quando uma tela muda sem querer. | M | P1 |
| Q2 | **Auditoria de acessibilidade das janelas** | Os testes de acessibilidade conferem rótulos escolhidos à mão. | `XCUIApplication().performAccessibilityAudit()` (macOS 14) sobre as telas do catálogo, com as exceções documentadas. | M | P1 |
| Q3 | **Fuzz dos parsers de log** | OkHttp, CFNetwork, Bundle do Firebase e OCR são texto de fora. | Testes por propriedade (Hypothesis) que garantem que nenhum texto derruba o parser nem vaza credencial. | P | P1 |
| Q4 | **Teste da largura mínima** | O achado D1 passou por todas as suítes. | `ToolbarLayoutTests` passa a conferir `contentMinSize` com barra lateral e inspector. | P | **P0** (junto com D1) |
| Q5 | **Desempenho medido** | Não há orçamento escrito para quadro, busca ou abertura. | `XCTMetric` para decodificar quadro, filtrar 1.000 requisições e abrir até "pronto", com limites no CI. | M | P2 |

## Ordem sugerida

1. **P0:** D1 + Q4 (janela no MacBook), D2 (Rodar visível) e A1 (bundle notarizado com Python próprio).
2. **P1 de interface:** D3, D4, D5, F3, D8, A4.
3. **P1 de produto:** D6, D7, A2, A3, A5.
4. **P1 de base:** R1, R2, R4, A7, Q1, Q2, Q3.
5. **P2**, conforme a demanda.

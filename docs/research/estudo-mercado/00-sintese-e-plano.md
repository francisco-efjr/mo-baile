# Estudo de mercado e plano de evolução do Mo baile

Síntese de 29/09/2026. Consolida quatro relatórios do agente
`consultor-pesquisador` (`.claude/agents/consultor-pesquisador.md`), que juntos
somam cerca de 4.200 linhas, mais de 100 ferramentas estudadas e fontes
datadas:

| Relatório | Frente | Linhas |
|---|---|---|
| [01-inspecao-automacao-mobile.md](01-inspecao-automacao-mobile.md) | Appium, Maestro, Android Studio, Xcode, scrcpy, idb, nuvens, agentes de IA mobile | 983 |
| [02-rede-analytics-depuracao.md](02-rede-analytics-depuracao.md) | Proxyman, Charles, mitmproxy, Chucker/Pulse, Firebase DebugView, Adobe Assurance, Avo, Snowplow Micro | 997 |
| [03-arquitetura-desempenho-devtools.md](03-arquitetura-desempenho-devtools.md) | VS Code/LSP, Zed, Playwright/CDP, stacks desktop, IPC e vídeo, empacotamento, MCP | 1060 |
| [04-qualidade-codegen-mercado.md](04-qualidade-codegen-mercado.md) | locators, auto-cura, relatórios, acessibilidade, qualidade de código, tendências, preço | 1183 |

Este documento não repete as fichas. Ele diz o que o estudo conclui, o que foi
conferido no código e o que fazer, em que ordem.

---

## 1. O que o estudo conclui

### 1.1 O mercado já resolveu inspeção e automação isoladamente

Espelhar tela, ler hierarquia, gravar passo e gerar código são problemas
resolvidos, e bem, por ferramentas gratuitas: Appium Inspector, Maestro Studio,
Layout Inspector, Accessibility Inspector, scrcpy. Competir de frente com
qualquer uma delas, no terreno dela, é perder.

Do mesmo jeito, interceptar HTTPS é terreno do Proxyman e do Charles, e QA de
tagueamento é terreno do Firebase DebugView, da Adobe Assurance e do Avo.

### 1.2 O espaço vazio é a junção

As quatro frentes chegaram, de forma independente, ao mesmo ponto: **nenhuma
ferramenta estudada junta, numa sessão local e sem SDK no app, o passo de UI, a
requisição HTTP e o evento de analytics que esse passo disparou, e ainda valida
o resultado contra um plano de medição.**

- O Trace Viewer do Playwright faz essa junção para web, e é a referência de
  formato.
- Datadog e Sentry fazem correlação em produção, mas exigem SDK e nuvem.
- As ferramentas de tagueamento validam o evento, mas não sabem que toque o
  disparou.

O Mo baile já tem três das quatro peças rodando no mesmo processo: espelho com
toque, proxy e escuta de analytics. Falta o relógio único e o plano de medição.

### 1.3 O produto que existe hoje não entrega a promessa básica

Antes de qualquer diferencial, o estudo encontrou defeitos que quebram o que o
README promete. Os principais foram conferidos por mim no código nesta data:

| Defeito | Onde | Conferido |
|---|---|---|
| XPath e posição marcados como únicos sem contar nada (`"matches": 1`) | `services/codegen.py:172` e `:178` | sim |
| Page Object gerado chama `click_at_position`, que não existe no repositório | `services/codegen.py:246` | sim |
| Executor repete coordenada com `sleep(1.0)` fixo e ignora o localizador | `services/flows.py:318` | sim |
| Cada quadro do espelho é PNG em base64 dentro do JSON-RPC | `rpc/server.py:175` | sim |
| O motor atende uma requisição por vez; `wda.start` longo trava `input.tap` e `engine.shutdown` | `rpc/server.py:1039` | sim |
| Cliente Swift sem timeout por chamada | `Engine/EngineClient.swift` | sim, nenhum timeout encontrado |
| Modo debug do Firebase fica ligado no aparelho depois de parar (entra no BigQuery do cliente) | `adapters/analytics_logcat.py` | sim, `stop` não faz `setprop .none.` |
| Resposta `chunked` corrompida, `gzip` ilegível, `items` de e-commerce quebrado, parâmetros sem tipo | `adapters/proxy.py`, `analytics_logcat.py` | reproduzido pelo agente da frente 2 |
| Ligar a escuta de novo duplica callbacks e linhas na tela | `rpc/server.py` | leitura do agente da frente 2 |
| `CorrelationCard` e interface Tk inserem `/v2/credito/simulacao` fixo e `wait_for_request` inexistente | Swift e `tk-legacy` | sim, `main_window.py:1971` |
| Proxy não decifra HTTPS; para app moderno a aba Rede é lista de hosts | `adapters/proxy.py` | leitura dos agentes |
| Bundle do app depende do Python do sistema e é assinado ad-hoc; não roda em Mac limpo | `tools/`, `Makefile` | leitura do agente da frente 3 |

### 1.4 A arquitetura se sustenta, com dois reparos

O agente da frente 3 mediu e concluiu: motor Python com front SwiftUI sobre
JSON-RPC por stdio é o mesmo desenho de LSP, DAP, Playwright e MCP. O
enquadramento é idêntico ao do MCP stdio, e uma ida e volta custa de 10 a 20 µs.
A decisão do ADR 0001 está certa para controle.

Onde dói:

1. **Vídeo.** O custo não é o base64, é o motor recodificar cada quadro em PNG
   (cerca de 25 ms de CPU) e o front decodificar PNG no ator principal (cerca de
   7 ms). Hoje a captura Android (1,3 s por quadro no moto g55) esconde isso.
   Quando a captura ficar rápida, o teto é cerca de 40 fps. A saída é tirar o
   pixel do Python: JPEG já, e vídeo H.264 por canal próprio depois.
2. **Concorrência.** Despacho sequencial e fila sem descarte são o defeito com
   mais chance de virar reclamação ("o app travou"), e ficam piores quando o
   espelho acelerar.

### 1.5 O que não fazer

Os quatro relatórios convergem também no que evitar:

- **Agente de IA próprio para testar app.** O mercado está lotado (GPTDriver,
  Drizz, Midscene, Maestro AI, Arbigent). Melhor expor o Mo baile **para** os
  agentes via MCP.
- **Nuvem de aparelhos própria.** BrowserStack, Sauce Labs e AWS resolvem
  escala. O Mo baile exporta para eles.
- **Auto-cura por IA e teste visual como diferencial.** A evidência mostra que
  45% da instabilidade vem de espera assíncrona, e o que mais reduziu
  flakiness no mobile (Maestro) foi espera automática, não IA.
- **Embarcar Frida** para quebrar pinning, e **capturar por IOSurface com
  framework privado da Apple**. As duas coisas quebram a cada versão e criam
  risco jurídico ou de manutenção.

---

## 2. Posicionamento proposto

**O que é.** O inspetor local de apps mobile que liga passo de UI, tráfego HTTP
e evento de analytics numa linha do tempo, e transforma a sessão em teste
Appium com seletor validado, asserção de tagueamento e relatório portátil.
Sem SDK no app e sem nuvem.

**Para quem.** QA e dev mobile em Mac, em times que precisam provar fluxo,
tagueamento e acessibilidade: banco, fintech, varejo, mídia. É o público que
hoje abre Appium Inspector, Charles e Firebase DebugView ao mesmo tempo e cola
os três à mão.

**Diferencial defensável.** A correlação e o plano de medição, não o espelho.
O espelho precisa ser bom o bastante para não atrapalhar.

**Distribuição.** Proposta da frente 4: núcleo gratuito e versão Pro por
assento, no estilo do Proxyman (licença perpétua de US$ 89 a 99; time a cerca de
US$ 12 por assento ao mês). Isso depende de uma decisão que hoje não existe: o
`pyproject.toml` declara licença `Proprietary`. A decisão vai para um ADR na
etapa 0.

---

## 3. Plano em etapas

Esforço: **P** até 3 dias, **M** de 1 a 2 semanas, **G** mais de 2 semanas.
Cada item aponta o relatório e a lição de origem. A ordem respeita dependências.
Um item só conta como pronto quando o critério é verificado por teste ou em
aparelho real, na linha do `ESTADO_ATUAL.md`.

### Etapa 0 · Chão firme (cerca de 2 semanas)

Objetivo: o que o README promete passa a ser verdade, e nada na tela mente.

| # | Entrega | Esforço | Origem | Critério de pronto |
|---|---|---|---|---|
| 0.1 | Commitar o trabalho pendente (hierarquia desacoplada, proxy, analytics, toolbar) e decidir o destino do `web_app.py`, que acessa o adb por fora do motor | P | estado atual | `git status` limpo; `make check` verde |
| 0.2 | Higiene do analytics: callback único, fila com teto, parser com aninhamento e tipo, `.none.` ao parar, restaurar `log.tag.*` | P | 02 · Ideia 1 | teste com linha real de `purchase` com dois itens; religar a escuta não duplica linha; `getprop` vazio depois de parar |
| 0.3 | Higiene do proxy: `chunked` de ida e volta, `gzip` e `br` decodificados na inspeção, streaming com teto, evento emitido no início, restaurar `captive_portal_mode` | P | 02 · Ideia 2 | testes de integração com servidor local para cada caso |
| 0.4 | Tirar as fachadas: `CorrelationCard` desligado até a correlação existir, asserção fixa da interface Tk, "tempo 0.0 s" e `flow.stop` que não encerra, splash com roteiro fixo | P | 02 · Ideia 3; 04 · L11 | busca por literal fixo não encontra nada; `flow.stop` mata o processo filho |
| 0.5 | Exportações (HAR e TSV) geradas no motor, uma vez só | P | 02 · Ideia 3 | HAR válido no validador; Swift só grava o que o motor devolve |
| 0.6 | Guardas no CI: `import-linter` com o contrato de camadas e Opengrep com as invariantes de segurança do `SEGURANCA.md` | P | 04 · L10 | CI reprova PR que importe adapter dentro de domain |
| 0.7 | ADR 0002 sobre licença e distribuição (núcleo aberto e Pro, ou interno) | P | 04 · posicionamento | ADR aprovado |
| 0.8 | Reescrever `docs/ESTADO_ATUAL.md` a partir do código de hoje | P | estado atual | cada linha com prova ou marcada como fachada |

### Etapa 1 · Motor que não trava (cerca de 2 a 3 semanas)

> **Concluída em 29/09/2026** na branch `etapa-1/motor-que-nao-trava`. Protocolo
> v2 com `engine.hello`, seis filas (`inline`, `fast`, `capture`, `services`,
> `query`, `environment`), `$/cancelRequest`, `$/progress`, estado de sessão com
> lock e época, desmonte que sobrevive a SIGTERM, cliente Swift com prazo por
> método vindo do motor, quadros sem acúmulo e com `device_id`, decodificação
> fora do MainActor e reinício automático do motor. Medido: chamada rápida com
> p95 abaixo de 1 ms durante leitura lenta de 6 s; `engine.shutdown` em menos
> de 1 ms; import do motor de cerca de 250 ms para cerca de 60 ms. O item 1.3
> entregou a tabela declarativa (`rpc/contract.py`) como fonte única de filas e
> prazos, verificada contra código e doc; gerar os DTOs Swift a partir dela
> ficou para depois.

Objetivo: nenhuma chamada lenta bloqueia as outras, e o front aguenta enxurrada
de quadros. Vem antes do espelho rápido porque espelho rápido aumenta a pressão
exatamente onde hoje não há controle.

| # | Entrega | Esforço | Origem | Critério de pronto |
|---|---|---|---|---|
| 1.1 | Despacho concorrente no motor: filas por domínio, lock no estado da sessão, `$/cancelRequest` e notificação de progresso, no modelo do LSP | M | 03 · Lição 1 | `input.tap` responde em menos de 200 ms com `wda.start` em andamento; teste de contrato de cancelamento |
| 1.2 | Cliente Swift com timeout por chamada, stream só de quadros que guarda o mais novo e decodificação fora do ator principal | P | 03 · Lição 2 | teste com 200 quadros em rajada: memória estável e a interface não congela |
| 1.3 | Handshake versionado (`engine.hello`) e contrato gerado a partir de esquema | M | 03 · Lição 7 | motor e front de versões diferentes recusam conexão com mensagem clara |
| 1.4 | Subida mais rápida: imports preguiçosos (Quartz toma 120 dos 265 ms) e reinício automático do motor | P | 03 · Lições 10 e 11 | motor responde `engine.info` em menos de 150 ms; matar o motor não derruba o app |

### Etapa 2 · Espelho e hierarquia rápidos (cerca de 3 semanas)

Objetivo: o espelho parece ao vivo e a árvore chega sem esperar a tela ficar
ociosa.

| # | Entrega | Esforço | Origem | Critério de pronto |
|---|---|---|---|---|
| 2.1 | JPEG no lugar de PNG no espelho (medido: 38% menos CPU e 66% menos bytes) | P | 01 · L3; 03 · Lição 3 | benchmark no repositório com antes e depois |
| 2.2 | Espelho iOS pelo MJPEG do WebDriverAgent (porta 9100), já exigido pelo Mo baile | P | 01 · L1; 03 · Lição 6 | 10 fps sustentados no Simulator e no aparelho físico |
| 2.3 | Hierarquia Android por sessão UiAutomator2 persistente com `waitForIdleTimeout` baixo, e o `stream.settled` do motor fazendo o papel da espera | P | 01 · L4 | dump em menos de 500 ms no moto g55, contra 1 a 10 s hoje |
| 2.4 | `/source` do WDA com `excluded_attributes` | P | 01 · L5 | tempo de dump medido numa tela SwiftUI grande |
| 2.5 | Quadro e árvore com o mesmo `snapshot_id`; toque resolvido contra a árvore da tela certa | M | 01 · L8 | teste em que tela muda entre captura e toque: o motor avisa em vez de clicar no elemento errado |
| 2.6 | Botões de sistema (voltar, home, girar) e gestos | P | 01 · L11 | controles do `DeviceDock` ligados |

### Etapa 3 · Código gerado que roda (cerca de 3 a 4 semanas)

Objetivo: o que o Mo baile gera é teste de verdade, que passa de primeira na
máquina de quem não conhece a ferramenta. É o núcleo do produto.

| # | Entrega | Esforço | Origem | Critério de pronto |
|---|---|---|---|---|
| 3.1 | Localizador honesto: unicidade contada avaliando a própria expressão, refinada até ser única, com escape de aspas e `name` no iOS, e alternativas nativas (predicado iOS, UiSelector) | P–M | 04 · L1; 01 · L7 | três botões de mesmo `resource-id` geram seletor que casa com um só; todo arquivo gerado passa em `ast.parse` |
| 3.2 | Padrão sensato de fábrica: id de acessibilidade primeiro, posição só como último recurso e com aviso | P | 04 · L2 | estratégia padrão deixa de ser `position` |
| 3.3 | Replay por localizador com espera automática, nova tentativa e verificação de efeito; vários localizadores por passo, com o uso de um alternativo reportado como "curado" | M | 04 · L3; 01 · L6 | fluxo gravado roda dez vezes seguidas sem falha num app de demonstração |
| 3.4 | Exportar projeto mínimo que roda de primeira: `BasePage` com esperas, `pytest`, `conftest`, e YAML do Maestro como opção | M | 04 · L4; 01 · L10 | numa máquina limpa, `pip install` e `pytest` passam sem editar nada |
| 3.5 | Medir instabilidade antes de entregar: rodar o teste N vezes e marcar o passo instável | P | 04 · L9 | relatório de instabilidade por passo |

### Etapa 4 · O diferencial: linha do tempo correlacionada (cerca de 5 a 6 semanas)

Objetivo: a coisa que ninguém mais faz.

| # | Entrega | Esforço | Origem | Critério de pronto |
|---|---|---|---|---|
| 4.1 | Relógio único: passo gravado ganha hora, o motor corrige a diferença entre relógio do aparelho e do Mac (`logcat -v epoch,usec`), evento atribuído ao passo por janela de tempo e marcado como "provável" | M | 02 · Ideia 4; 04 · L5 | teste com relógio do aparelho adiantado 3 s: eventos caem no passo certo |
| 4.2 | Trace de sessão portátil (passo, captura antes e depois, HTTP redigido, eventos) num arquivo que abre de novo no app, com exportação para Allure | G | 04 · L5; 03 · Lição 12; 02 · Ideia 5 | arquivo aberto em outra máquina mostra a mesma sessão; HAR e Allure gerados dele |
| 4.3 | Plano de medição em JSON, importável de planilha, com as regras de limite do GA4 embutidas; veredito verde, amarelo ou vermelho por passo; opção de inferir o plano de uma sessão | M | 02 · Ideia 5 e seguintes | plano de exemplo validado contra sessão gravada, com um evento faltando detectado |
| 4.4 | Asserções a partir do que foi observado: de UI, de evento de analytics com parâmetros tipados, e de contrato de resposta, usando `expect_event` e `expect_request` no código gerado | M | 04 · L6; 02 · Ideia 8 | teste gerado falha quando o app deixa de disparar o evento |
| 4.5 | Auditoria de acessibilidade pela árvore e pela captura: rótulo ausente, área de toque (48 dp e 44 pt) e contraste, mapeados para WCAG 2.2 e NBR 17060 | M | 04 · L7; 01 · L13 | tela de demonstração com três problemas conhecidos: os três aparecem |
| 4.6 | Diagnóstico honesto de "por que não vejo tráfego" (Flutter, pinning, proxy ignorado) | P | 02 · Ideia 11 | cada causa comum tem mensagem e passo de correção |

### Etapa 5 · Alcance e distribuição (contínua, a partir do fim da etapa 3)

Objetivo: o Mo baile roda em qualquer Mac, conversa com agentes de IA e com o
CI, e a aba Rede enxerga HTTPS.

| # | Entrega | Esforço | Origem | Critério de pronto |
|---|---|---|---|---|
| 5.1 | App autossuficiente: python-build-standalone embarcado (cerca de 25 MB), runtime reforçado, assinatura de dentro para fora, notarização; depois Sparkle e Sentry com telemetria opt-in | M | 03 · Lições 9 e 11; 04 · L13 | app baixado roda num Mac limpo sem Python instalado; `spctl` aceita |
| 5.2 | Servidor MCP e CLI headless sobre o mesmo motor, com o SDK oficial (a especificação mudou de forma incompatível na revisão de 28/07/2026) | M | 03 · Lição 8; 01 · L9; 04 · L8 | um agente lê árvore, toca, e recebe a requisição e o evento disparados pelo toque; CLI roda fluxo no CI |
| 5.3 | HTTPS em camadas: CA própria com assistente de `network_security_config` para build de debug; injeção de CA no emulador com root; `mitmdump` como processo filho (contorna a exigência de Python 3.12 do mitmproxy 12) | G | 02 · Ideia 6 | tráfego HTTPS de app debug visível com corpo; guia de uso no app |
| 5.4 | Decodificar no tráfego os hits de GA4, Segment, Amplitude, Mixpanel e Adobe | M | 02 · Ideia 7 | evento visto no tráfego e no logcat aparece como um só |
| 5.5 | Espelho Android em H.264 pelo protocolo do scrcpy, decodificado com VideoToolbox, e toque e texto pelo canal de controle (hoje `adb shell input` custa de 115 a 150 ms) | G | 01 · L2; 03 · Lições 4 e 5 | latência de ponta a ponta abaixo de 100 ms medida com cronômetro na tela |
| 5.6 | iOS de primeira classe na frente de analytics (`-FIRDebugEnabled`) | P/M | 02 · Ideia 9 | eventos do iOS com a mesma riqueza do Android |
| 5.7 | Mock mínimo para estados de erro (depende de 5.3) | M | 02 · Ideia 10 | resposta 500 simulada num endpoint escolhido |

---

## 4. Como medir se está funcionando

| Indicador | Hoje | Meta ao fim da etapa |
|---|---|---|
| Latência do espelho Android | cerca de 1,3 s por quadro (moto g55) | etapa 2: menos de 300 ms; etapa 5: menos de 100 ms |
| Tempo de dump de hierarquia Android | 1 a 10 s | etapa 2: menos de 500 ms |
| Page Object gerado que compila e roda sem edição | não roda (métodos inexistentes) | etapa 3: 100% no app de demonstração |
| Fluxo gravado que passa dez vezes seguidas | não medido | etapa 3: sim |
| Tempo até o primeiro valor para alguém de fora | infinito (depende do Python do sistema) | etapa 5: menos de 10 min do download ao primeiro teste gerado |
| Evento de analytics atribuído ao passo certo | inexistente | etapa 4: correto no teste de relógio defasado |

---

## 5. Conflitos entre os relatórios e como foram resolvidos

- **Primeiro o espelho ou primeiro o motor?** A frente 1 põe o MJPEG do WDA em
  primeiro lugar. A frente 3 põe a concorrência. Adotei a frente 3: acelerar o
  espelho sem controle de fluxo piora o travamento. As duas etapas são curtas e
  ficam em sequência.
- **mitmproxy dentro ou fora do motor?** O estudo anterior
  (`docs/research/interceptador-rede.md`) esboçava embarcar. A frente 2 mostrou
  que o mitmproxy 12 exige Python 3.12 e o motor declara 3.10. Adotei processo
  filho, o que não obriga a subir a versão mínima.
- **Licença.** Só a frente 4 tratou disso a fundo, e com razão. Sem a decisão
  da etapa 0, a etapa 5 não tem como ser planejada.

## 6. O que continua não verificado

Listado em detalhe em cada relatório. Os pontos que afetam decisão:

- latência real do scrcpy no moto g55 (a tela provavelmente estava desligada
  nos testes da frente 3);
- se o Running Devices do Android Studio usa H.264 ou HEVC (no binário só
  aparecem VP8 e AV1);
- preços de concorrentes mudam com frequência; conferir antes de fechar o ADR
  de licença.

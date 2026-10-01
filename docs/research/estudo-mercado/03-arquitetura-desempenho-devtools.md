# Estudo de mercado 3/4: arquitetura, tecnologia e desempenho de ferramentas de desenvolvimento desktop

Data: 29/09/2026. Autor: consultor-pesquisador do Mo baile.
Escopo: como ferramentas de referência são construídas (processos, protocolos,
transporte de quadros, empacotamento, extensão) e o que isso diz sobre a
arquitetura do Mo baile: motor Python, front SwiftUI e JSON-RPC sobre stdio.

Método. Fonte primária primeiro: documentação oficial, código-fonte, arquivos
de especificação e binários instalados nesta máquina. Blog de terceiros aparece
só como indício, e vem marcado. Os números sem fonte pública foram medidos
nesta pesquisa, com o método descrito na seção 2. Onde não houve como
verificar, está escrito "não verificado".

---

## 1. Resumo executivo

**A decisão se sustenta para o plano de controle e não se sustenta para o
plano de vídeo.** As duas coisas precisam ser separadas.

- JSON-RPC 2.0 sobre stdio, uma mensagem por linha, é o mesmo desenho do LSP,
  do DAP, do driver do Playwright e do transporte local do MCP. O enquadramento
  do Mo baile é idêntico ao do MCP stdio, byte a byte. A ida e volta de uma
  chamada trivial ficou na casa de 10 a 20 µs (medido, seção 2). Para
  controle, stdio não é gargalo e não vai ser.
- JSON com base64 também não é o vilão. Playwright trafega `binary` como base64
  dentro do JSON, e o Chrome DevTools Protocol entrega o screencast como JPEG em
  base64. No Swift, decodificar o envelope e o base64 de um quadro de 416 KB
  custou cerca de 0,7 ms (medido).
- **O que vai doer é a forma do espelho**: capturar uma imagem cheia, reduzir,
  recodificar em PNG no Python, embrulhar em JSON, decodificar PNG no Swift e
  redesenhar. Hoje isso fica escondido porque a captura Android leva cerca de
  1,3 s por quadro (`adb exec-out screencap`, medido no moto g55). Com captura
  instantânea, o motor ainda gastaria cerca de 25 ms de CPU por quadro só para
  reduzir, codificar e serializar. O teto fica perto de 40 quadros/s num M4 Pro,
  com o GIL disputado pelo proxy, pelo analytics e pelo laço RPC.
- Quem resolveu esse problema separou os planos. O scrcpy manda H.264 cru por
  socket próprio e declara de 35 a 70 ms de latência. O Android Studio empurra
  um agente nativo com MediaCodec, abre sockets separados para vídeo e controle
  e decodifica com FFmpeg na IDE (verificado no bundle instalado). O emulador
  Android expõe gRPC para controle e entrega pixels por memória compartilhada
  (`MMAP`, verificado no `.proto` do SDK). **O motor orquestra e o pixel não
  passa por ele.**
- Existe um defeito estrutural mais urgente que o vídeo. O motor despacha as
  requisições **em série, na thread principal** (`serve_forever`). `wda.start`
  pode levar minutos, e `hierarchy.dump` leva segundos. Enquanto isso,
  `input.tap`, `stream.stop` e até `engine.shutdown` ficam na fila. Do lado
  Swift, `call` não tem timeout e as notificações usam `AsyncStream` sem
  limite. LSP e CDP resolvem isso com cancelamento, progresso e controle de
  fluxo por confirmação. O Mo baile não tem nenhum dos três.
- O maior ganho de posicionamento está no MCP. O enquadramento já é o mesmo, e
  a Apple (Xcode 26.3), a Microsoft (Playwright MCP e Playwright CLI), o
  projeto Appium (appium-mcp) e a mobile-next (mobile-mcp) já expõem as suas
  ferramentas a agentes. Nenhum desses concorrentes junta hierarquia
  normalizada, ranking de localizador, rede e tagueamento na mesma sessão.

As oito ideias de maior valor estão na seção 7, em ordem de prioridade.

---

## 2. Medições feitas nesta pesquisa

Ambiente: Apple M4 Pro, macOS 26.3.1, Python 3.14.0 (`.venv` do repositório),
Pillow 12.3.0, Swift com `-O`. Aparelho: moto g55 5G, Android 14, 1080×2400,
por USB. Scripts no scratchpad da sessão, fora do repositório. Nenhum arquivo do
repositório foi alterado para medir.

| # | O que | Resultado | Como |
|---|---|---|---|
| M1 | Subida do motor até a primeira resposta de `engine.info` | 200 a 245 ms com cache quente; 544 ms na primeira execução | `Popen(python -m mobaile.rpc)`, 7 rodadas |
| M2 | Ida e volta de chamada trivial (`codegen.steps`) por stdio | p50 de 10 a 18 µs, p95 abaixo de 30 µs | 200 chamadas por rodada, cliente Python |
| M3 | Tempo de import do motor | 265 ms cumulativos, dos quais **120 ms são `Quartz` (pyobjc)**, importado por `adapters.input_events`, e 77 ms são `requests` | `python -X importtime -m mobaile.rpc` |
| M4 | Memória do motor ocioso | cerca de 74 MB de RSS | `ps -o rss` após `engine.info` |
| M5 | Python: converter de RGBA e reduzir de 1080×2400 para 900 px | 13,3 ms | Pillow, média de 20 |
| M6 | Python: miniatura 32×32 do detector de diferença | 2,2 ms | idem |
| M7 | Python: caminho atual (reduzir, PNG `compress_level=1`, base64, JSON) | **25,2 ms, linha de 416 KB** com tela de UI sintética; 28,7 ms e 905 KB com faixa de "foto" | idem |
| M8 | Python: mesmo quadro em JPEG q80, binário | **15,5 ms, 142 KB** | idem |
| M9 | Swift: decodificar o envelope e o JSON completo da linha de 416 KB | 0,37 ms + 0,22 ms | `JSONDecoder`, média de 30 |
| M10 | Swift: base64 para `Data` | 0,12 ms | idem |
| M11 | Swift: `NSImage(data:)` com decodificação forçada, PNG de 900×2000 | 6,8 ms (JPEG: 5,1 ms) | idem |
| M12 | Android: `adb exec-out screencap` cru | **1311 a 1372 ms** | 4 rodadas. A tela possivelmente estava apagada, porque `screenrecord` respondeu `INVALID_LAYER_STACK`. Bate com os 1227 ms de `docs/ESTADO_ATUAL.md` |
| M13 | Android: `adb shell input keyevent 0` (no-op), custo de um toque via `input` | 115 a 151 ms | 3 rodadas |

Leitura rápida:

1. A captura (M12) é de 50 a 100 vezes mais cara que todo o resto somado. Hoje o
   transporte não é o gargalo, e otimizar JSON ou base64 antes de trocar a
   captura é otimizar o lugar errado.
2. Quando a captura deixar de ser o gargalo, o custo por quadro no Python (M7)
   vira o teto: 1000 / 25 ≈ 40 quadros/s num único núcleo, disputando o GIL.
   Com H.264 repassado, esse custo cai a zero, porque o motor não toca em pixel.
3. Metade da subida do motor é import evitável (M3).
4. Cada toque via `adb shell input` paga de 115 a 150 ms de subida de processo
   no aparelho (M13). O canal de controle do scrcpy injeta evento num socket
   que já está aberto.

---

## 3. Fichas por ferramenta

### 3.1 Visual Studio Code, com LSP e DAP

**O que é.** Editor de código da Microsoft sobre Electron. O núcleo "Code - OSS"
é MIT. A distribuição da Microsoft tem licença própria.

**Estrutura e arquitetura.**
- Processos: *main* (janelas e ciclo de vida), *renderer* por janela (workbench,
  com sandbox), *shared process* (instalação de extensão; hospeda o *pty host*
  e o observador de arquivos como filhos), *extension host* por janela e
  processos utilitários. A migração para sandbox tirou o extension host do
  renderer e o levou para um *utility process* criado pelo main, API que o time
  do VS Code adicionou ao próprio Electron. A comunicação entre processos passou
  a usar *MessagePorts*, canais diretos que não sobrecarregam o main.
  ([VS Code blog, 28/11/2022](https://code.visualstudio.com/blogs/2022/11/28/vscode-sandbox);
  [Extension Host](https://code.visualstudio.com/api/advanced-topics/extension-host))
- O extension host isola código de terceiros. Se uma extensão trava o host, a
  janela sobrevive e o usuário vê "Extension host terminated unexpectedly".
  Existe *Extension Bisect* para achar a culpada. Todas as extensões do host
  caem juntas, e isso é queixa recorrente
  ([issue #79782](https://github.com/microsoft/vscode/issues/79782)).
- **LSP**: JSON-RPC 2.0 com cabeçalho `Content-Length` e corpo, "comparável a
  HTTP". Tem negociação de capacidades no `initialize`, cancelamento
  (`$/cancelRequest`) e progresso (`$/progress`)
  ([LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)).
- **DAP**: mesmo enquadramento por cabeçalho. Tem dois modos: sessão única, com
  o adaptador como processo filho por stdin/stdout, e multissessão, com o
  adaptador escutando numa porta
  ([DAP overview](https://microsoft.github.io/debug-adapter-protocol/overview)).

**Desempenho.** A versão 1.94 (setembro de 2024) migrou o código para ESM,
reduziu o bundle do workbench em mais de 10% e "melhora massivamente" a
subida ([release notes 1.94](https://code.visualstudio.com/updates/v1_94);
[devclass, 14/10/2024](https://devclass.com/2024/10/14/vs-code-migration-to-ecmascript-modules-massively-improves-startup-performance-but-extensions-left-behind-for-now/)).
O blog do sandbox aponta o *code caching* na subida como "a melhor solução"
para tempo de início. Nenhum número absoluto oficial em milissegundos: **não
verificado**.

**Telemetria.** Um único ajuste, `telemetry.telemetryLevel`, com quatro níveis:
`all`, `error`, `crash` e `off`
([docs](https://code.visualstudio.com/docs/configure/telemetry)).

**Pontos fortes.** Protocolos abertos (LSP e DAP) que viraram padrão da
indústria. Isolamento de extensão por processo. Migração incremental, entregue
mês a mês.

**Pontos fracos.** O custo de memória do Chromium. Um host compartilhado por
todas as extensões. O Content-Length exige parser de cabeçalho, que é mais
complexo que quebra de linha, mas aceita qualquer conteúdo.

### 3.2 Zed

**O que é.** Editor em Rust, dos criadores do Atom. O editor é GPL, os
componentes de servidor são AGPL e o **GPUI é Apache 2.0**
([Zed is now open source](https://zed.dev/blog/zed-is-now-open-source)).

**Estrutura e arquitetura.**
- GPUI: framework de UI próprio que renderiza tudo na GPU, com shaders Metal
  para poucas primitivas: retângulos por SDF, sombras, glifos em atlas e
  imagens. Mantém cache de pares texto e fonte já moldados, e desenha os glifos
  numa única chamada instanciada
  ([Zed blog, 07/03/2023](https://zed.dev/blog/videogame)).
- Colaboração por CRDT: as edições são expressas em posições lógicas, não em
  deslocamentos absolutos, e por isso comutam
  ([Zed blog: CRDTs](https://zed.dev/blog/crdts)).
- Extensões em Rust compiladas para `wasm32-wasip1`, rodando em sandbox Wasm e
  capazes de fornecer language servers
  ([Life of a Zed Extension, 21/10/2024](https://zed.dev/blog/zed-decoded-extensions)).

**Desempenho.** A meta declarada é 120 quadros/s, ou seja, 8,33 ms por quadro
para estado, layout e escrita no framebuffer (mesma fonte). Não há
benchmark independente citado aqui.

**Pontos fortes.** Latência de interface de primeira linha. Extensões isoladas
por Wasm, sem processo extra por extensão.

**Pontos fracos.** Um framework de UI próprio é um custo enorme, que só se
paga porque o editor inteiro é o produto. Acessibilidade e integração nativa
ficam por conta do time.

### 3.3 JetBrains: IntelliJ Platform (split mode) e Fleet

**IntelliJ Platform.** A arquitetura de desenvolvimento remoto, chamada *split
mode*, divide a IDE em frontend, que renderiza a UI, e backend, que hospeda
modelo de projeto, indexação, análise e execução. Os dois conversam por RPC,
com dados serializados por `kotlinx.serialization`, e o backend pode rodar na
mesma máquina, em contêiner ou na nuvem
([Split Mode, SDK](https://plugins.jetbrains.com/docs/intellij/split-mode-and-remote-development.html)).
Em 2026.1 o depurador foi redesenhado: janela e breakpoints passaram para o
frontend, e o breakpoint "é aplicado imediatamente", com a conversa com o
backend acontecendo depois
([JetBrains Platform blog, 01/2026](https://blog.jetbrains.com/platform/2026/01/platform-debugger-architecture-redesign-for-remote-development-in-2026-1/)).

**Fleet.** Arquitetura distribuída desde o início: frontend em Kotlin/JVM com
UI própria (*Noria*) sobre Skia (skiko), workspace e backends separados, com
protocolo próprio
([Fleet Below Deck I, 01/2022](https://blog.jetbrains.com/fleet/2022/01/fleet-below-deck-part-i---architecture-overview/);
[Parte VI, Noria](https://blog.jetbrains.com/fleet/2023/02/fleet-below-deck-part-vi-ui-with-noria/)).
**Descontinuado**: download encerrado em 22/12/2025. A JetBrains afirmou que
não conseguiu nem substituir o IntelliJ nem ocupar um nicho claro
([The Future of Fleet, 12/2025](https://blog.jetbrains.com/fleet/2025/12/the-future-of-fleet/)).

**Compose Multiplatform (Toolbox App).** A JetBrains migrou o Toolbox App de
Electron e React para Compose for Desktop. Relata memória ociosa
"significativamente" menor, instalador com cerca de metade do tamanho e
renderização mais rápida, para mais de 1 milhão de usuários ativos por mês
([Kotlin blog, 12/2021](https://blog.jetbrains.com/kotlin/2021/12/compose-multiplatform-toolbox-case-study/)).
Números absolutos: não publicados.

**Lição.** Separar frontend e backend por RPC é o padrão maduro. O Fleet mostra
que uma arquitetura elegante não salva produto sem diferencial. E o
redesenho do depurador ensina que **estado sensível a latência vai para o
front, com confirmação assíncrona**.

### 3.4 Xcode

**O que é.** IDE proprietária da Apple. Os serviços de linguagem vivem em
processos XPC (SourceKit). O `sourcekit-lsp` é Apache 2.0 e expõe o mesmo motor
via LSP.

**Novidade relevante.** O Xcode 26.3 (anúncio em 03/02/2026, lançamento em
26/02/2026) integra o Claude Agent SDK e o Codex e **expõe as capacidades do
Xcode por MCP**
([Apple Newsroom, 02/2026](https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/)).
Segundo fontes secundárias, o binário `xcrun mcpbridge` traduz MCP para o XPC
interno e expõe cerca de 20 ferramentas: build, testes, logs, previews,
snippets e busca de documentação
([Rudrank Riyam](https://rudrank.com/exploring-xcode-using-mcp-tools-cursor-external-clients),
secundária). A contagem exata não foi verificada em fonte da Apple.

**Lição.** Até o fornecedor mais fechado do ecossistema decidiu que a
ferramenta precisa ser dirigível por agente, via MCP, por cima da mesma
fronteira interna que a IDE já usa.

### 3.5 Android Studio: Running Devices e emulador embutido

**Espelho de aparelho físico.** Verificado no bundle instalado nesta máquina
(Android Studio 2025.3):

- Agente nativo `libscreen-sharing-agent.so` (C++, namespace `screensharing`)
  para arm64, armv7, x86 e x86_64, mais um `screen-sharing-agent.jar`. A IDE os
  empurra para `/data/local/tmp/.studio/`.
- Codificação no aparelho pela API NDK `AMediaCodec`, com superfície de
  entrada. As strings incluem `video/x-vnd.on2.vp8` e `video/av01`. H.264 e
  HEVC não aparecem literais: não verificado.
- A mensagem de log "Created video and control sockets" confirma **sockets
  separados para vídeo e controle**.
- Cada pacote de vídeo carrega `frame_number`, `origination_timestamp_us`,
  `presentation_timestamp_us` e `bit_rate`, o que indica medição de latência
  ponta a ponta e taxa ajustável (`AMediaCodec_setParameters`). A taxa
  adaptativa é inferência a partir de strings; não foi verificada no código.
- Decodificação na IDE com FFmpeg 7.1.1 via JavaCPP
  (`ffmpeg-7.1.1-1.5.12-macosx-arm64.jar`).
- Documentação de uso: [Run apps on a hardware device](https://developer.android.com/studio/run/device).
  Aparelhos que não sustentam a taxa de bits exigida falham com erro de
  codificador (mesma página, indício).

**Emulador embutido.** O emulador expõe gRPC (`EmulatorController`) e
`streamScreenshot`, um *server streaming* que entrega "um novo quadro sempre
que o aparelho produz um". O próprio `.proto` avisa que PNG pesa na CPU e
oferece `ImageTransport { MMAP }`: o cliente cria uma região de memória
compartilhada, o emulador escreve os pixels nela e o campo `image` da resposta
vem vazio (arquivo `emulator/lib/emulator_controller.proto`, emulador 36.4.10,
SDK local). Para uso remoto, o Google publica uma arquitetura WebRTC com
gateway gRPC
([android-emulator-container-scripts](https://github.com/google/android-emulator-container-scripts)).

**Lição.** São dois caminhos, e nos dois o controle e o pixel viajam em canais
diferentes: vídeo comprimido por socket no aparelho físico, memória
compartilhada no emulador.

### 3.6 Warp

**O que é.** Terminal em Rust com UI própria, construída em parceria com Nathan
Sobo (cofundador do Zed) e "inspirada no Flutter". Os shaders Metal cobrem só
retângulos, imagens e glifos, em cerca de 200 linhas.

**Desempenho.** Mais de 144 quadros/s em 4K e redesenho médio de 1,9 ms na
semana da publicação
([How Warp Works, 12/07/2021](https://www.warp.dev/blog/how-warp-works)).
No Linux migrou para wgpu, winit e cosmic-text
([Warp for Linux](https://www.warp.dev/blog/warp-for-linux)).

**Licença.** Cliente proprietário. Abertura recente de partes: não verificado.

**Lição.** Poucas primitivas bem feitas bastam, e a abstração de renderização
fica isolada do resto. Isso vale para o espelho do Mo baile: o quadro deve ir
direto para uma camada de vídeo, não atravessar a árvore de views.

### 3.7 Ghostty

**O que é.** Terminal com núcleo multiplataforma `libghostty`, uma biblioteca em
Zig com ABI C. No macOS a interface é Swift com AppKit e SwiftUI, e o render é
Metal. No Linux é GTK4 e OpenGL. Cada terminal tem threads dedicadas de
leitura, escrita e render
([About Ghostty](https://ghostty.org/docs/about);
[libghostty is coming](https://mitchellh.com/writing/libghostty-is-coming)).
Licença MIT (repositório).

**Desempenho.** O autor evita números absolutos: "deve ser impossível dizer que
o Ghostty é lento" (About). Benchmark oficial: não publicado.

**Lição.** É o precedente mais próximo do Mo baile: núcleo headless e casca
nativa por plataforma. A diferença é que o núcleo do Ghostty roda no mesmo
processo, via ABI C, e por isso não paga IPC por quadro. Isso reforça que o
quadro não deve atravessar a fronteira de controle.

### 3.8 Playwright

**O que é.** Automação de navegador da Microsoft, Apache 2.0.

**Estrutura e arquitetura.**
- Um núcleo em Node (`playwright-core`) roda como **processo driver**. As
  bindings de Python, Java e .NET são clientes finos que o sobem e conversam
  por pipe ([playwright-python #1850](https://github.com/microsoft/playwright-python/issues/1850)).
- Enquadramento por **prefixo de 4 bytes com o tamanho** (little-endian) mais o
  JSON, e não por linha
  ([`packages/utils/pipeTransport.ts`](https://github.com/microsoft/playwright/blob/main/packages/utils/pipeTransport.ts)).
- Protocolo especificado em YAML (`packages/protocol/spec/*.yml`: page,
  frame, network, tracing, **android** etc.), com validadores e tipos gerados.
  O tipo `binary` trafega **como base64** dentro do JSON
  ([`validatorPrimitives.ts`](https://github.com/microsoft/playwright/blob/main/packages/protocol/src/validatorPrimitives.ts)).
- **Codegen e Inspector**: grava interação e gera código em Node, Python, Java
  e .NET, com prioridade para localizadores por papel, texto e test id. Gera
  asserções de visibilidade, texto e valor, oferece "pick locator" e emula
  dispositivo ([Codegen](https://playwright.dev/docs/codegen)).
- **Trace Viewer**: `trace.zip` com snapshots de DOM por ação, rede, console,
  fonte e tempos. Servido por um backend Node e uma UI React
  ([Trace viewer](https://playwright.dev/docs/trace-viewer)).
- **UI mode**: modo *watch*, linha do tempo, snapshots antes e depois de cada
  ação, playground de localizador, rede e console
  ([UI mode](https://playwright.dev/docs/test-ui-mode)).
- **Para agentes**: o Playwright MCP usa snapshots de acessibilidade com `ref`
  por elemento em vez de screenshot. Em 2026 surgiu o Playwright CLI, que grava
  os snapshots em disco e é recomendado para *coding agents* por gastar menos
  tokens. O MCP fica para laços agênticos com estado persistente
  ([playwright-mcp README](https://github.com/microsoft/playwright-mcp);
  [Playwright CLI](https://playwright.dev/agent-cli/introduction)).
  A redução de cerca de 4 vezes em tokens é número de blogs de terceiros,
  não verificado em fonte da Microsoft.

**Pontos fortes.** Um motor e N linguagens, sem divergência de regra. O
contrato é gerado a partir de uma especificação. Ferramentas de depuração
excelentes, com trace portátil.

**Pontos fracos.** Distribui um runtime Node inteiro com cada binding (dezenas
de MB, número secundário).

**Lição.** É a validação mais forte do desenho do Mo baile: um núcleo, clientes
finos e processo filho por stdio. O Playwright ainda vai além em três pontos:
especificação do protocolo em arquivo, trace portátil e superfície para
agentes.

### 3.9 Chrome DevTools Protocol (CDP)

**O que é.** O protocolo pelo qual o DevTools, o Puppeteer e parte do
Playwright dirigem o Chromium. JSON sobre WebSocket ou pipe, definido em
arquivos `.pdl`.

**Transmissão de tela.** `Page.startScreencast` aceita `format` (jpeg ou png),
`quality`, `maxWidth`, `maxHeight`, `everyNthFrame` e **`maxFramesInFlight`**
("número máximo de quadros enviados até que `screencastFrameAck` seja exigido",
padrão 3). Tem ainda `sendLastFrame`, que troca desempenho total por latência
menor. Cada `screencastFrame` traz `data` em base64 e o cliente responde com
`screencastFrameAck(sessionId)`
([Page.pdl](https://github.com/ChromeDevTools/devtools-protocol/blob/master/pdl/domains/Page.pdl);
[referência](https://chromedevtools.github.io/devtools-protocol/tot/Page/)).

**Lição.** É exatamente o problema do Mo baile, com solução documentada:
**controle de fluxo por confirmação**. O produtor nunca manda mais que N
quadros sem retorno do consumidor. O Mo baile hoje só descarta quadro igual; se
o front ficar lento, os quadros diferentes empilham.

### 3.10 Cypress

**Arquitetura.** O teste roda **dentro do navegador**, no mesmo laço de eventos
da aplicação. Um processo Node faz proxy de todo o tráfego e orquestra. As
restrições que isso impõe são declaradas "permanentes": nada de múltiplas abas
nativas e nada de dois navegadores ao mesmo tempo
([Trade-offs](https://docs.cypress.io/app/references/trade-offs)). Licença MIT.
O modelo de negócio é o Cypress Cloud, pago.

**Lição.** O acoplamento íntimo dá velocidade e depuração ótimas, mas trava a
evolução. Para o Mo baile, que precisa dirigir aparelho remoto, o modelo de
fora para dentro (Playwright e Appium) é o certo.

### 3.11 Puppeteer

**Arquitetura.** Biblioteca Node sobre CDP. Desde a v23 (2024) tem suporte
estável a Firefox via **WebDriver BiDi**. No Chrome o padrão continua CDP, para
não quebrar automação existente
([Chrome for Developers](https://developer.chrome.com/blog/firefox-support-in-puppeteer-with-webdriver-bidi)).
Licença Apache 2.0.

**Lição.** Protocolo proprietário vira dívida quando o padrão aberto chega. No
mundo mobile, o equivalente é W3C WebDriver e Appium. O Mo baile deve continuar
falando Appium na geração de código e usar atalhos (scrcpy, uiautomator)
apenas por baixo.

### 3.12 scrcpy

**O que é.** Espelho e controle de Android, Apache 2.0, versão 4.1 de
12/07/2026 (API de releases do GitHub). É a referência de baixa latência.

**Arquitetura** ([doc/develop.md](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md)):
- O servidor Java (APK renomeado para `scrcpy-server.jar`) é empurrado para
  `/data/local/tmp` e roda como `shell` via `app_process`.
- **Até três sockets separados**: vídeo, áudio e controle. Cada um tem thread
  própria nos dois lados.
- O vídeo é H.264 por padrão (também H.265 e AV1), codificado por `MediaCodec`
  a partir de uma `Surface`. Só produz quadro quando a superfície muda, com
  `KEY_REPEAT_PREVIOUS_FRAME_AFTER` para não deixar o último quadro borrado.
- Cada pacote de mídia leva um cabeçalho de 12 bytes: flags de configuração e
  de quadro-chave, PTS de 62 bits e tamanho de 32 bits. Na rotação, chega um
  pacote de sessão com largura e altura.
- O cliente decodifica e exibe "o mais rápido possível, sem buffer".
- Na rede os papéis se invertem (o cliente escuta e o servidor conecta), o que
  evita condição de corrida sem polling.
- **O servidor recusa cliente de versão diferente.** O protocolo muda entre
  versões, sem compatibilidade.

**Desempenho.** De 30 a 120 quadros/s conforme o aparelho, e **de 35 a 70 ms**
de latência ([README](https://github.com/Genymobile/scrcpy);
[PR #646](https://github.com/Genymobile/scrcpy/pull/646)). A taxa padrão é 8
Mbps, cerca de 1 MB/s
([doc/video.md](https://github.com/Genymobile/scrcpy/blob/master/doc/video.md)).

**Como o Mo baile usa hoje.** `scrcpy.start` sobe o binário do scrcpy numa
**janela SDL separada**, sempre no topo (`adapters/scrcpy.py`). Ou seja: está
fora do espelho do app, sem hierarquia sobreposta e sem toque projetado.

### 3.13 Stacks de app desktop

| Stack | Motor de UI | Licença | Memória, app vazio, macOS arm64 (release) | Subida (release) | Pacote |
|---|---|---|---|---|---|
| Electron | Chromium e Node | MIT | ≈369 MB (soma de processos) | ≈640 ms | ≈319 MB |
| Tauri | WebView do sistema (WKWebView) | Apache-2.0/MIT | ≈95 MB | ≈2044 ms (sic) | ≈5 MB |
| Wails | WebView do sistema | MIT | ≈100 MB | ≈1740 ms | ≈8 MB |
| Flutter desktop | Engine própria (Skia ou Impeller) | BSD-3 | ≈781 MB (só debug medido) | não medido em release | ≈25 MB (Windows) |
| Compose MP (JVM) | Skia via skiko | Apache-2.0 | não publicado | não publicado | Toolbox: instalador caiu cerca de 50% ao sair do Electron |
| SwiftUI/AppKit | Nativo | proprietário da Apple, sem custo | não medido aqui | não medido aqui | só o binário |

Fonte das linhas 1 a 4:
[Elanis/web-to-desktop-framework-comparison](https://github.com/Elanis/web-to-desktop-framework-comparison),
medido em CI do GitHub e atualizado em 09/2026. **Ressalva do próprio autor:**
os números dependem da carga da máquina de CI, e a subida do Tauri acima da do
Electron é, muito provavelmente, ruído ou artefato de medição. A issue
[tauri#5889](https://github.com/tauri-apps/tauri/issues/5889) discute como a
memória de WebView é contada. Blogs de 2026 citam Tauri com 30 a 50 MB e
Electron com 200 a 300 MB em ociosidade, mas são fontes secundárias. O
Compose vem do
[estudo de caso do Toolbox](https://blog.jetbrains.com/kotlin/2021/12/compose-multiplatform-toolbox-case-study/).

**Leitura para o Mo baile.** Para um app só de macOS que precisa de camada de
vídeo com decodificação por hardware, captura de tela e integração com
CoreMediaIO, AVFoundation, VideoToolbox e ScreenCaptureKit, **SwiftUI com
AppKit é a escolha certa**. Electron e Tauri colocariam o vídeo dentro de uma
WebView (WebCodecs ou MSE) e adicionariam de 100 a 300 MB. Flutter e Compose
exigiriam ponte nativa para todas essas APIs. A decisão de front da ADR 0001
se sustenta.

### 3.14 Motor em processo separado: IPC e transmissão de quadros

**Padrões de transporte em uso nas ferramentas estudadas:**

| Padrão | Quem usa | Enquadramento | Serve para |
|---|---|---|---|
| stdio, JSON-RPC por linha | MCP stdio, **Mo baile** | `\n`, sem quebra de linha interna | controle |
| stdio, JSON-RPC com `Content-Length` | LSP, DAP | cabeçalho e corpo | controle; aceita conteúdo com `\n` |
| pipe com prefixo de tamanho | driver do Playwright | uint32 LE e JSON | controle; binário em base64 |
| WebSocket e JSON | CDP, Cypress | frame do WebSocket | controle e screencast em JPEG base64 com ack |
| gRPC (HTTP/2 e protobuf) | emulador Android, split mode (RPC próprio) | protobuf | controle e *streaming* tipado |
| Socket bruto e cabeçalho binário | scrcpy, agente do Android Studio | cabeçalho de 12 bytes e payload | **vídeo comprimido** |
| Memória compartilhada | emulador (`MMAP`), IOSurface no macOS | região mapeada e sinalização | **pixels crus** |
| WebRTC | emulador remoto | RTP/SRTP | vídeo em rede com controle de congestionamento |

**Largura de banda, conta simples.** RGBA 1080×2400 dá 10,4 MB por quadro,
igual ao medido pelo projeto. A 60 quadros/s são cerca de 620 MB/s: só memória
compartilhada aguenta. PNG de 900 px, no caminho atual, dá cerca de 0,4 MB por
quadro, ou 25 MB/s a 60 quadros/s, e esbarra na CPU do Python antes da banda.
H.264 a 8 Mbps dá cerca de 1 MB/s: qualquer socket aguenta, inclusive stdio.
**A escolha do codec importa muito mais que a do transporte.**

**Backpressure: como cada um faz.**
- CDP: `maxFramesInFlight` e ack, com opção de guardar só o último quadro.
- scrcpy: o cliente decodifica e exibe sem fila. Quem manda o ritmo é o
  codificador, que só produz quando a tela muda.
- Mo baile na interface Tk legada: a fila é drenada e só o último quadro é
  desenhado, o padrão "o mais recente vence" (`docs/RELATORIO_QA.md`).
- Mo baile no front SwiftUI: `AsyncStream` com `bufferingPolicy` padrão
  (ilimitada) em `EngineClient`. Quadros, eventos HTTP e analytics dividem a
  mesma fila, e o quadro é decodificado dentro de `EngineSession.handle`, que é
  `@MainActor`. **Sem limite e sem descarte.**

**Decodificação no macOS.** O VideoToolbox dá acesso direto ao decodificador de
hardware (`VTDecompressionSession`), e o `AVSampleBufferDisplayLayer` aceita
`CMSampleBuffer` H.264 ou HEVC e exibe sem passar pela main thread
([WWDC14 513](https://developer.apple.com/videos/play/wwdc2014/513/)).

**Caminhos de captura no iOS:**
- **Simulador**: o framebuffer é uma IOSurface. O idb (Meta, MIT) oferece
  `video-stream` em H.264, MJPEG ou minicap
  ([idb video](https://fbidb.io/docs/video/)), por meio de frameworks privados
  (SimulatorKit), o que o torna frágil entre versões do Xcode. A alternativa
  pública é o **ScreenCaptureKit** capturando a janela do Simulator: amostras
  apoiadas em IOSurface, a 60 quadros/s com `minimumFrameInterval` de 1/60
  ([WWDC22 10156](https://developer.apple.com/videos/play/wwdc2022/10156/)).
  Exige permissão de Gravação de Tela (TCC). `simctl io recordVideo` (H.264 ou
  HEVC) só grava em arquivo. O Mo baile hoje chama `simctl io screenshot` por
  quadro (`adapters/ios_wda.py`).
- **Aparelho físico por USB**: ligando `kCMIOHardwarePropertyAllowScreenCaptureDevices`
  via CoreMediaIO, o iPhone aparece como `AVCaptureDevice` externo *muxed*. É o
  caminho do QuickTime. Há armadilhas sem documentação: a propriedade leva
  segundos para valer, e é preciso "aquecer" com `AVCaptureDevice.devices()`
  ([codejam.info, 06/2025](https://www.codejam.info/2025/06/usb-iphone-screen-recording-swift.html),
  secundária; [Apple forum 759245](https://developer.apple.com/forums/thread/759245)).
- **Via WDA (simulador e físico)**: o WebDriverAgent transmite MJPEG na porta
  9100 (`mjpegServerPort`), com `mjpegServerFramerate` e `mjpegScalingFactor`
  ([capabilities do XCUITest driver](https://appium.github.io/appium-xcuitest-driver/latest/reference/capabilities/)).
  Há relato de o WDA cair com taxa e escala altas
  ([appium#15264](https://github.com/appium/appium/issues/15264)). O Mo baile
  já depende do WDA para hierarquia, então esse caminho não traz dependência
  nova.

### 3.15 Empacotamento de Python em app macOS, atualização, falhas e telemetria

| Ferramenta | O que faz | Estado | Licença | Observação |
|---|---|---|---|---|
| PyInstaller | Congela o interpretador e as dependências | ativo | GPL-2.0 com exceção para o bootloader | A doc **não recomenda** `--onefile` em `.app`: descompacta a cada execução e não funciona assinado com sandbox ([usage](https://pyinstaller.org/en/stable/usage.html)) |
| Briefcase (BeeWare) | Gera `.app`, DMG ou PKG com Python de suporte | ativo | BSD-3 | **Assina e notariza por padrão.** `--adhoc-sign` só roda na própria máquina ([macOS](https://briefcase.beeware.org/en/stable/reference/platforms/macOS/)) |
| PyOxidizer | Python embutido em binário Rust | **"estado zumbi"** desde 17/03/2024, nas palavras do autor | MPL-2.0 | [Gregory Szorc](https://gregoryszorc.com/blog/2024/03/17/my-shifting-open-source-priorities/) |
| python-build-standalone | CPython relocável e pré-compilado | ativo; Astral assumiu em 12/2024 | MPL-2.0 (scripts) | É a base do `uv python install`. O `install_only` 3.12 para aarch64-darwin tem **25 MB** (release `20260929`) ([Astral](https://astral.sh/blog/python-build-standalone)) |
| uv | Gerenciador de pacotes e de Python | ativo | MIT/Apache-2.0 | A OpenAI anunciou a compra da Astral em 19/03/2026; o fechamento não foi verificado ([Simon Willison](https://simonwillison.net/2026/Mar/19/openai-acquiring-astral/)) |

**Assinatura e notarização.** O serviço de notarização exige *hardened runtime*
em todo executável principal, inclusive nos auxiliares embutidos, e a
assinatura aninhada vai de dentro para fora, com Developer ID e *timestamp*
seguro ([Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).
Na prática, cada `.so` e `.dylib` de Pillow, pyobjc e do próprio CPython
precisa ser assinado. O `tools/package_macos_app.sh` do Mo baile assina ad-hoc
com `--deep` e copia só `engine/src`. As dependências (Pillow, requests e
pyobjc) e o interpretador ficam fora do bundle. O `EngineLocator` procura
Python em `.venv`, `/opt/homebrew`, `/usr/local` e `/usr/bin`. **Hoje o app não
roda num Mac limpo.**

**Atualização.** Sparkle 2 (licença MIT-like, cerca de 9,8 mil estrelas): appcast
RSS, assinatura EdDSA (ed25519) obrigatória para `.pkg` e delta, e serviços XPC
para app com sandbox
([docs](https://sparkle-project.org/documentation/);
[sandboxing](https://sparkle-project.org/documentation/sandboxing/)).

**Falhas.** `sentry-cocoa` e `sentry-python` são MIT e cobrem os dois processos
([macOS](https://docs.sentry.io/platforms/apple/guides/macos/)). Hoje o Mo baile
não tem relato de falha: nenhuma ocorrência de sentry, faulthandler ou
excepthook em `engine/src` e `apps/MoBaile/Sources`.

**Telemetria opt-in.** O modelo de referência é o do VS Code: um ajuste, quatro
níveis (all, error, crash, off). Para uma ferramenta de QA que vê tráfego e
telas de clientes, o padrão tem que ser `off`, e nenhum payload (XML de
hierarquia, corpo HTTP, quadro) pode sair da máquina.

### 3.16 Extensibilidade: plugins, MCP e CLI headless

**Plugins.** O VS Code isola extensões num processo por janela. O Zed as roda
em sandbox Wasm. O IntelliJ, em split mode, divide o plugin em módulos de
frontend e de backend. Os três custaram anos de engenharia de plataforma.

**MCP.**
- O transporte stdio do MCP é, literalmente, o do Mo baile: subprocesso,
  JSON-RPC por stdin e stdout, "mensagens delimitadas por nova linha e que
  NÃO DEVEM conter quebras internas", log só em stderr
  ([MCP 2025-11-25, transports](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/transports.mdx)).
- A revisão **2026-07-28** tornou o protocolo sem estado. Tirou o handshake
  `initialize`, passou versão e capacidades para `_meta` em cada requisição e
  criou `server/discover`
  ([changelog](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/changelog.mdx)).
  O protocolo mudou de forma incompatível em menos de um ano. Implementar à
  mão é pedir retrabalho; o SDK oficial em Python é MIT.
- Concorrentes e vizinhos já no mercado:
  - **mobile-mcp** (mobile-next, Apache-2.0, cerca de 8,4 mil estrelas):
    snapshot de acessibilidade, com screenshot como alternativa, para iOS e
    Android, em simuladores e aparelhos
    ([repo](https://github.com/mobile-next/mobile-mcp)).
  - **appium-mcp** (projeto Appium, Apache-2.0): localizadores por prioridade
    (accessibility id, id, predicados nativos, xpath por último), Page Object e
    geração de teste Java/TestNG
    ([repo](https://github.com/appium/appium-mcp)).
  - **Playwright MCP e CLI**: ver 3.8.
  - **Xcode 26.3**: ver 3.4.

**CLI headless.** O Playwright tem CLI para testes, codegen, trace e agentes. O
VS Code tem `code`. O Mo baile tem `make run-engine` (JSON-RPC cru) e
`qa/engine_client.py`, um cliente Python de teste, mas nenhuma CLI de produto
para CI, do tipo "dump de hierarquia", "gerar Page Object" ou "diagnóstico do
ambiente em JSON".

---

## 4. Matriz comparativa

| | Processo do núcleo | Transporte de controle | Transporte de pixel | Contrato | Extensão e agentes | Empacotamento e atualização |
|---|---|---|---|---|---|---|
| VS Code | extension host separado | MessagePorts; LSP e DAP por stdio | n/a | TypeScript e specs LSP/DAP | extensões em processo; MCP no chat | Electron; atualizador próprio |
| Zed | mesmo processo | interno | GPU direta (Metal) | Rust | Wasm | binário Rust |
| IntelliJ (split) | backend separado | RPC com kotlinx.serialization | UI no front | Kotlin compartilhado | plugins em módulos front e back | Toolbox |
| Android Studio | agente no aparelho, emulador separado | sockets e gRPC | **vídeo comprimido; MMAP** | proto | plugins IntelliJ | Toolbox ou instalador |
| Playwright | driver Node separado | pipe com prefixo de tamanho | screenshot em base64 | **spec YAML gerada** | MCP e CLI para agentes | npm e pip (Node embutido) |
| CDP | navegador | WebSocket e JSON | **JPEG base64 com ack** | `.pdl` gerado | n/a | n/a |
| scrcpy | servidor no aparelho | socket de controle | **H.264, H.265 ou AV1 cru** | versão travada | n/a | Homebrew e releases |
| Ghostty | mesmo processo (libghostty) | ABI C | Metal | cabeçalho C | n/a | nativo |
| **Mo baile** | motor Python separado | **stdio, JSON-RPC por linha** | **PNG base64 no mesmo canal** | fixtures geradas pelo motor | nenhuma | ad-hoc; depende de Python do sistema |

---

## 5. Confronto com o código do Mo baile

O que existe e está certo:

- **Fronteira única e disciplinada.** `engine/src/mobaile/rpc/server.py` concentra
  a tabela de métodos. O stdout é exclusivo do protocolo, o log vai para
  stderr, e há um lock de escrita para as notificações vindas de outras
  threads. É o que o MCP exige, palavra por palavra.
- **Contrato verificado dos dois lados.** O motor gera as fixtures
  (`tools/generate_fixtures.py`), e o CI reprova se estiverem desatualizadas. É
  a metade do que o Playwright faz com a spec em YAML.
- **Descarte de quadro igual** (`services/streaming.py`) e métricas embutidas no
  próprio `stream.frame`. Foi uma boa correção do defeito 4 do relatório de QA.
- **Remontagem ordenada do stdout** em `EngineClient`. É a correção certa para o
  PNG corrompido: um único consumidor aplica os pedaços em ordem.
- **Ciclo de vida atrelado ao processo filho**, com `engine.shutdown` antes do
  `terminate` para desfazer o proxy do aparelho.

O que falta ou dói:

| Achado | Onde | Evidência |
|---|---|---|
| Despacho em série na thread principal: uma chamada longa bloqueia todas | `EngineServer.serve_forever` chama `handle_message` e depois `handler(params)` em sequência | `wda_start` avisa que "leva minutos"; `hierarchy_dump` chama `uiautomator` ou `/source` com timeout de até 30 s (`adapters/appium.py:222`). A medição "15 ms de p95 com captura de 700 ms" do relatório de QA só cobre a captura em thread própria, não uma requisição lenta concorrente |
| Nem cancelamento nem progresso | protocolo | não há equivalente a `$/cancelRequest` e `$/progress` |
| `call` sem timeout no cliente | `EngineClient.call` | a continuação espera para sempre, e o `refreshDaemonStatus` a cada 5 s pode empilhar atrás de um `wda.start` |
| Notificações sem limite e misturadas | `EngineClient.notifications` (`AsyncStream` sem `bufferingPolicy`) | quadro, `proxy.event` e `analytics.event` dividem a mesma fila; não dá para descartar quadro sem perder evento |
| Decodificação de PNG na main actor | `EngineSession.handle` (`@MainActor`) com `EngineDTO.Frame.image` e `NSImage(data:)` | cerca de 7 ms por quadro a 900 px (M11); com 30 quadros/s, seria 21% da main thread |
| O pixel atravessa o motor | `stream_start` → `_encode_png` → base64 → `notify` | 25 ms de CPU por quadro no Python (M7) |
| O scrcpy fica fora do app | `adapters/scrcpy.py` abre janela SDL própria | sem sobreposição de hierarquia nem toque projetado no espelho do app |
| Toque via `adb shell input` | `adapters/adb.py:285` | de 115 a 150 ms por comando (M13) |
| Import pesado na subida | `adapters/input_events` importa Quartz no topo | 120 ms de 265 ms (M3) |
| Sem handshake de versão | `engine.info` devolve `version` e `methods`, mas o front não negocia | front e motor de versões diferentes só falham em tempo de execução |
| O app não roda num Mac limpo | `tools/package_macos_app.sh` e `EngineLocator` | só `engine/src` é copiado; Python e dependências vêm do sistema; assinatura ad-hoc |
| Sem auto-restart do motor | `EngineClient.handleTermination` | falha as chamadas pendentes (correto), mas não religa |
| Sem relato de falha, atualizador ou telemetria | todo o repositório | busca sem ocorrência |
| Sem CLI de produto nem MCP | — | só `make run-engine` e `qa/engine_client.py` |
| Lógica fora do motor | `web_app.py` (Streamlit, não versionado) reimplementa a busca do adb | contraria a regra de disciplina do `README`; registro apenas |

---

## 6. A decisão "motor Python + SwiftUI + JSON-RPC stdio" se sustenta?

**Sim, como plano de controle.** O desenho coincide com o do LSP, do DAP, do
Playwright e do MCP. O custo medido é desprezível: de 10 a 20 µs por ida e volta
e menos de 1 ms para decodificar envelope e base64 no Swift. A memória do motor
ocioso é de cerca de 74 MB, a da ordem de um app Tauri vazio e bem abaixo de um
Electron vazio. O isolamento por processo filho resolve o problema de processo
órfão e dispensa superfície de rede. E, de brinde, o protocolo é quase um
servidor MCP pronto.

**Não, como plano de vídeo, e a ADR já intuía isso.** A ADR 0001 aceita "a
serialização de quadro em base64 tem custo" e aponta "um socket dedicado para
os quadros". O diagnóstico está meio certo:

1. O custo não está no base64 nem no JSON (M9 e M10 somam cerca de 0,7 ms). Está
   em **o motor reduzir e recodificar cada quadro** (M5 e M7) e o front
   decodificar uma imagem estática por quadro na main thread (M11).
2. Um socket dedicado carregando os mesmos PNGs só tira 0,7 ms do caminho. O
   ganho real vem de **mudar o codec e o dono do pixel**: vídeo comprimido
   produzido no aparelho (scrcpy-server ou MediaCodec), repassado como bytes
   opacos e decodificado por hardware no Mac (VideoToolbox).
3. Com isso o Python volta a fazer o que faz bem, orquestrar adb, WDA, proxy e
   logcat, e sai do caminho quente onde o GIL pesa.

**Onde a decisão vai doer, em ordem de probabilidade:**

1. **Bloqueio na fila de requisições** (já dói). É a próxima reclamação de
   usuário: "cliquei e não aconteceu nada enquanto o WDA subia".
2. **Distribuição.** Python embutido, com dezenas de `.so` para assinar e
   notarizar, e pyobjc em universal2. É trabalho de engenharia real, e a
   Briefcase prova que dá para fazer.
3. **Espelho fluido** (ver acima). Não se resolve dentro do desenho atual; exige
   o plano de vídeo separado.
4. **GIL.** Proxy HTTP, leitura de logcat, laço RPC e stream na mesma instância
   Python. Aguenta com carga de QA. Se o proxy precisar de alta vazão, o
   caminho é outro processo ou o proxy como adapter externo, a exemplo do
   `mockttp` citado em `docs/research/estudo-http-toolkit.md`.
5. **Divergência entre as duas linguagens.** Está controlada pelas fixtures.
   Ficaria melhor com um esquema como fonte da verdade (ideia 7).

**O que não fazer.** Não migrar o front para Electron ou Tauri: o custo de
memória sobe e o acesso a VideoToolbox, CoreMediaIO e ScreenCaptureKit piora.
Não reescrever o motor em Swift: joga fora a suite e as integrações. Não
construir um sistema de plugins agora: MCP e CLI são a extensão certa para este
público. Não partir para memória compartilhada ou IOSurface entre processos
agora: com vídeo comprimido, 1 MB/s cabe em qualquer socket.

---

## 7. Lições para o Mo baile

Esforço: P (até 3 dias), M (de 1 a 2 semanas), G (3 semanas ou mais).
Ordenadas por valor sobre esforço.

### 1. Despacho concorrente, cancelamento e progresso no motor

- **Problema.** `serve_forever` executa cada método na thread que lê o stdin.
  Um `wda.start` de minutos ou um `hierarchy.dump` de segundos congela toque,
  parada de stream e encerramento.
- **Evidência.** LSP tem `$/cancelRequest` e `$/progress`. O driver do
  Playwright é assíncrono por natureza. Nenhuma ferramenta madura atende em
  série.
- **Proposta.** Ler o stdin numa thread e despachar para um pool pequeno. Criar
  filas seriais por domínio: `input.*` e `stream.*` numa fila rápida, `wda.*`,
  `simulators.*` e `hierarchy.*` numa fila lenta. Proteger o estado de sessão
  (`device_id`, `current_xml`, `platform`) com lock. Adicionar
  `$/cancelRequest` e a notificação `progress` com `token`.
- **Esforço.** M. **Risco.** Médio: condição de corrida no estado do
  `EngineServer`, hoje escrito sem lock.
- **Pronto quando** um teste de contrato com `wda.start` falso de 10 s mostrar
  `input.tap` e `stream.stop` com p95 abaixo de 50 ms no meio dele; um
  `$/cancelRequest` interromper `hierarchy.dump`; e `engine.shutdown` responder
  em menos de 2 s em qualquer estado.

### 2. Backpressure e timeout no cliente Swift

- **Problema.** `call` sem timeout; `AsyncStream` ilimitado misturando quadros e
  eventos; PNG decodificado na main actor.
- **Evidência.** O CDP usa `maxFramesInFlight` e `screencastFrameAck`. A
  interface Tk do próprio projeto drena a fila e desenha só o último quadro.
  Custo medido: cerca de 7 ms por quadro na main (M11).
- **Proposta.** Um fluxo exclusivo para `stream.frame` com
  `bufferingPolicy: .bufferingNewest(1)`; eventos seguem no fluxo ilimitado.
  Decodificação fora da main actor (`Task.detached` ou `CGImageSource`),
  publicando só o `CGImage`. Timeout por chamada, com padrão de 10 s e
  `wda.start` e `simulators.boot` longos com progresso. Opcionalmente,
  `stream.ack` no estilo do CDP, com `max_in_flight=2`.
- **Esforço.** P. **Risco.** Baixo.
- **Pronto quando** um teste com main actor artificialmente lenta (200 ms por
  quadro) mostrar a latência do quadro exibido estável (sem acúmulo) e a memória
  limitada; e uma chamada pendurada falhar com `EngineError.timeout` em vez de
  spinner eterno.

### 3. Ganho rápido no caminho atual: JPEG, sem PNG

- **Problema.** PNG é o pior formato para foto de tela reduzida: mais CPU e
  mais bytes.
- **Evidência.** M7 contra M8: 25,2 ms e 416 KB contra 15,5 ms e 142 KB (−38% de
  CPU, −66% de bytes). O CDP usa JPEG no screencast por padrão.
- **Proposta.** `stream.frame` passa a mandar `image_base64` e `mime`
  (`image/jpeg`, qualidade 80) e mantém PNG só em `screen.capture`, onde a
  fidelidade importa para o inspetor. Regerar as fixtures.
- **Esforço.** P. **Risco.** Baixo: artefato de compressão em texto pequeno,
  aceitável num espelho que já é reduzido.
- **Pronto quando** `qa/perf_espelho.py` mostrar pelo menos 60% menos bytes por
  quadro, a suite de contrato passar com o campo novo e o front decodificar os
  dois formatos.

### 4. Plano de vídeo separado: H.264 do scrcpy-server decodificado no Swift

- **Problema.** Com `screencap`, o espelho fica em cerca de 0,8 quadro/s e não
  há como ficar fluido. O scrcpy já está instalado, mas abre fora do app.
- **Evidência.** scrcpy: de 30 a 120 quadros/s, de 35 a 70 ms, cerca de 1 MB/s,
  protocolo documentado com cabeçalho de 12 bytes. Android Studio: agente
  MediaCodec com sockets de vídeo e controle separados e FFmpeg na IDE.
  Emulador: gRPC para controle e MMAP para pixel.
- **Proposta.**
  1. O motor orquestra: empurra o `scrcpy-server` na versão travada, faz
     `adb forward` ou `reverse`, sobe o servidor com `control=true` e devolve
     ao front `{video_socket, codec, width, height}` pelo RPC.
  2. O pixel não passa pelo Python. O front conecta direto no socket de vídeo
     (loopback do adb) ou num Unix domain socket em diretório `0700` repassado
     pelo motor. Então lê os cabeçalhos de 12 bytes, monta `CMSampleBuffer` e
     entrega a um `AVSampleBufferDisplayLayer`, ou ao `VTDecompressionSession`
     quando precisar do `CVPixelBuffer` para sobreposição.
  3. A hierarquia sobreposta, a projeção de coordenada e o `stream.settled`
     continuam no motor (settle por tempo sem pacote novo ou por notificação do
     front).
  4. Se falhar, volta ao caminho de screencap automaticamente.
- **Regra de disciplina.** Decodificar vídeo é "comportamento genuinamente de
  interface", como a projeção. Nenhuma regra de negócio migra para o Swift.
- **Esforço.** G. **Risco.** Alto. O servidor recusa versão diferente, então é
  preciso embutir o `scrcpy-server` (Apache-2.0, com NOTICE) e acompanhar as
  versões. Há variação de codificador entre fabricantes, quadro-chave na
  rotação e sessão de vídeo reiniciada ao girar.
- **Pronto quando** o espelho no moto g55 passar de 30 quadros/s, com latência
  medida por carimbo de tempo abaixo de 150 ms e CPU do motor abaixo de 5%
  durante o espelho; e a hierarquia sobreposta continuar alinhada após rotação.

### 5. Toque e texto pelo canal de controle, não por `adb shell input`

- **Problema.** Cada toque sobe um processo `input` no aparelho: de 115 a 150 ms
  (M13).
- **Evidência.** O scrcpy e o Android Studio mantêm um socket de controle aberto
  e injetam eventos sem subir processo.
- **Proposta.** Com a ideia 4 no ar, `input.tap` e `input.text` usam o socket de
  controle do scrcpy-server (mensagens de toque e texto do protocolo). Sem
  scrcpy, cai para `adb shell input`, com validação idêntica em
  `security/`.
- **Esforço.** M, depois da 4. **Risco.** Médio: o formato das mensagens de
  controle muda com a versão do scrcpy.
- **Pronto quando** o p95 entre clique no espelho e evento no aparelho ficar
  abaixo de 30 ms, com teste de regressão de coordenada (`ProjectionTests`)
  verde.

### 6. Espelho iOS sem screenshot por quadro

- **Problema.** `simctl io screenshot` por quadro no simulador; aparelho físico
  sem espelho.
- **Evidência.** O WDA transmite MJPEG na porta 9100, e o Mo baile já depende
  do WDA. ScreenCaptureKit dá 60 quadros/s em IOSurface. CoreMediaIO expõe o
  iPhone por USB como `AVCaptureDevice` (o caminho do QuickTime). O idb
  transmite H.264, mas por framework privado.
- **Proposta, em etapas.**
  1. Consumir o MJPEG do WDA (`mjpegServerFramerate` de 15 a 30,
     `mjpegScalingFactor` com cautela por causa do appium#15264). É simples,
     vale para simulador e físico e não traz dependência nova.
  2. Para aparelho físico por USB, captura via CoreMediaIO no front (sem motor
     no caminho).
  3. Avaliar ScreenCaptureKit para o simulador, se a permissão de Gravação de
     Tela for aceitável para o público.
- **Esforço.** M (etapa 1: P). **Risco.** Médio: CPU do WDA, permissões TCC e
  comportamento de CoreMediaIO sem documentação oficial.
- **Pronto quando** o simulador passar de 15 quadros/s pelo MJPEG com o
  `hierarchy.dump` funcionando em paralelo, e um iPhone por USB aparecer no
  espelho sem QuickTime aberto.

### 7. Handshake versionado e contrato a partir de esquema

- **Problema.** Front e motor não negociam versão. As fixtures pegam campo
  renomeado, mas não geram tipos, e o esquema de ferramenta para MCP ou CLI
  teria que ser escrito à mão.
- **Evidência.** O Playwright especifica o protocolo em YAML e gera validadores
  e tipos. O LSP negocia capacidades no `initialize`. O MCP 2026-07-28 usa
  `server/discover` e versão por requisição.
- **Proposta.** Criar `engine.hello`, devolvendo `protocol_version` e
  `capabilities` (por exemplo `video.h264`, `input.control_socket`,
  `progress`). Adotar um arquivo de esquema (JSON Schema ou YAML) por método,
  que gera os DTOs Swift e a validação Python e serve de fonte para as
  ferramentas MCP.
- **Esforço.** M. **Risco.** Baixo; é refatoração com rede de proteção.
- **Pronto quando** o front recusar com mensagem clara um motor de versão
  incompatível; o CI reprovar DTO gerado desatualizado; e `EngineDTO.swift`
  deixar de ser escrito à mão.

### 8. Servidor MCP e CLI headless sobre o mesmo motor

- **Problema.** Agentes (Claude Code, Codex, Xcode 26.3, Cursor) já dirigem
  navegador e IDE, mas não o Mo baile. E não há ferramenta de CI.
- **Evidência.** O MCP stdio tem o mesmo enquadramento do Mo baile. O
  mobile-mcp e o appium-mcp provam a demanda, mas **não juntam** hierarquia
  normalizada entre plataformas, ranking de localizador, proxy HTTP com redação
  e tagueamento de analytics na mesma sessão. O Playwright mostra que uma CLI
  que grava em disco é a variante mais econômica em tokens para *coding
  agents*.
- **Proposta.**
  1. `python -m mobaile.mcp`, usando o SDK oficial (MIT), com ferramentas
     finas sobre os serviços existentes: `devices_list`, `hierarchy_snapshot`
     (com `ref` por elemento, como o Playwright), `tap_ref`,
     `locators_for_ref` (as três estratégias do codegen), `network_events`
     (já redigidos), `analytics_events` e `codegen_page_object`.
  2. `mobaile` como CLI: `doctor --json`, `hierarchy dump`, `codegen`,
     `analytics tail`, gravando em arquivo quando a saída for grande.
  3. Opt-in explícito. Qualquer ferramenta que toca no aparelho exige
     confirmação no cliente, e nada que não esteja redigido sai do motor.
- **Esforço.** M. **Risco.** Médio: o MCP mudou de forma incompatível entre
  2025-11-25 e 2026-07-28 (o SDK absorve isso), e há o risco de agente agindo
  no aparelho errado (exigir `device_id` explícito).
- **Pronto quando** o Claude Code conseguir, sem a interface aberta, listar
  aparelhos, obter o snapshot, tocar por `ref`, gerar o Page Object de um
  elemento e ler eventos de rede redigidos; houver teste de contrato das
  ferramentas; e `mobaile doctor --json` rodar num job de CI.

### 9. App autossuficiente, assinado e notarizado

- **Problema.** O bundle leva só `engine/src`. Python e dependências vêm do
  sistema, a assinatura é ad-hoc e o app não roda num Mac limpo.
- **Evidência.** O python-build-standalone oferece CPython relocável de 25 MB e
  é a base do `uv`. A Briefcase assina e notariza por padrão. A Apple exige
  *hardened runtime* e assinatura de dentro para fora. O PyInstaller desaconselha
  onefile em `.app`. O PyOxidizer está parado.
- **Proposta.** Build reprodutível:
  1. `uv` baixa o python-build-standalone fixado.
  2. Instalar as dependências do motor num `site-packages` dentro de
     `Contents/Resources/engine`.
  3. `EngineLocator` passa a preferir o Python do bundle.
  4. Assinar cada Mach-O com Developer ID, `--options runtime` e
     `--timestamp`, de dentro para fora (sem `--deep`).
  5. `notarytool` e `stapler`.
  6. Avaliar a Briefcase para o motor, se simplificar os passos 4 e 5.
  7. Congelar a versão da árvore (MPL-2.0 permite fork se a Astral ou a OpenAI
     mudarem a política).
- **Esforço.** M. **Risco.** Médio: wheels universal2 do pyobjc e do Pillow,
  entitlements para JIT (não usados) e tempo de notarização.
- **Pronto quando** o app abrir e reconhecer um aparelho num usuário novo do
  macOS, sem Homebrew nem `.venv`; e `spctl -a -vv` e
  `codesign --verify --strict` passarem no CI.

### 10. Subida mais rápida do motor

- **Problema.** 265 ms de import, dos quais 120 ms são Quartz e 77 ms são
  requests, carregados mesmo sem uso (M3).
- **Evidência.** O VS Code trata subida como métrica de produto: *code caching*
  e ESM.
- **Proposta.** Import tardio de `input_events` (Quartz) e de `appium` e
  `requests` dentro dos métodos que os usam. Opcionalmente, pré-compilar o
  bytecode no bundle.
- **Esforço.** P. **Risco.** Baixo.
- **Pronto quando** a primeira resposta de `engine.info` sair em menos de
  120 ms com cache quente no M4 Pro, com um teste em CI que falhe se
  `-X importtime` passar do orçamento.

### 11. Supervisão, relato de falha, atualização e telemetria opt-in

- **Problema.** Se o motor cai, o front fica desconectado até reabrir. Não há
  atualização nem relato de falha.
- **Evidência.** O VS Code detecta a queda do extension host e oferece
  reinício, e tem telemetria em quatro níveis. Sparkle 2 com EdDSA. Sentry em
  Cocoa e Python, ambos MIT.
- **Proposta.** Auto-restart do motor com backoff (três tentativas), que
  restaura dispositivo e serviços pelo estado do front. Sentry nos dois
  processos, com `before_send` removendo qualquer payload (XML, HTTP, imagem).
  Sparkle 2 com appcast assinado. `telemetryLevel`, com padrão `off`.
- **Esforço.** M. **Risco.** Médio de privacidade: dado de cliente em
  stacktrace. Mitigar com lista de permissão de campos, não de bloqueio.
- **Pronto quando** um `kill -9` no motor fizer o front reconectar em menos de
  2 s e voltar a espelhar; uma falha no motor aparecer no Sentry com versão e
  pilha, sem nenhum conteúdo de tela ou rede; e uma versão nova instalar por
  Sparkle a partir da anterior.

### 12. Trace de sessão portátil, no espírito do Trace Viewer

- **Problema.** Quem acha o defeito precisa reproduzir para mostrar. Não
  existe artefato que junte o que aconteceu.
- **Evidência.** O `trace.zip` do Playwright junta snapshots antes e depois de
  cada ação, rede, console e fonte, e abre offline.
- **Proposta.** `trace.start` e `trace.stop` no motor gravam um `.mobaile-trace`
  (zip) com, por passo do fluxo: quadro, XML da hierarquia, ação e localizador,
  eventos HTTP redigidos e eventos de analytics correlacionados. O front abre
  em modo leitura.
- **Esforço.** G. **Risco.** Médio: tamanho do arquivo e dado sensível (a
  redação é obrigatória).
- **Pronto quando** um fluxo gravado de 10 passos gerar um trace abaixo de 20 MB
  que outra pessoa abra, navegando passo a passo com antes e depois, rede e
  eventos.

---

## 8. Sequência sugerida

1. Ideias 2, 3 e 10 (P): alívio imediato, sem mexer em arquitetura.
2. Ideia 1 (M): acaba com o bloqueio na fila, que é o defeito com maior chance
   de virar reclamação.
3. Ideia 7 (M): prepara a 8 e dá segurança para mudanças de contrato.
4. Ideias 9 e 11 (M): o app passa a ser distribuível para o time.
5. Ideia 8 (M): diferencial de mercado, reaproveitando os serviços existentes.
6. Ideias 4, 5 e 6 (G e M): espelho fluido no Android e no iOS.
7. Ideia 12 (G): quando o fluxo de gravação estiver estável.

---

## 9. O que não foi verificado

- Números absolutos de subida do VS Code, do Zed e do Xcode (não publicados
  oficialmente).
- A lista exata de ferramentas do `xcrun mcpbridge`: a contagem de 20 vem de
  fonte secundária.
- H.264 e HEVC no agente do Android Studio (só VP8 e AV1 aparecem literais) e
  taxa adaptativa (inferida de strings).
- A economia de tokens do Playwright CLI sobre o MCP (números de blogs).
- Memória e subida do front SwiftUI do Mo baile: não medidos, para não abrir o
  app do usuário com aparelho conectado.
- Latência real de ponta a ponta do scrcpy no moto g55: a tela estava
  possivelmente apagada durante a pesquisa (`INVALID_LAYER_STACK`).
- O fechamento da compra da Astral pela OpenAI.

## 10. Fontes

Protocolos e especificações:
[LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) ·
[DAP overview](https://microsoft.github.io/debug-adapter-protocol/overview) ·
[MCP 2025-11-25 transports](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/transports.mdx) ·
[MCP 2026-07-28 changelog](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/changelog.mdx) ·
[CDP Page.pdl](https://github.com/ChromeDevTools/devtools-protocol/blob/master/pdl/domains/Page.pdl) ·
[Playwright pipeTransport](https://github.com/microsoft/playwright/blob/main/packages/utils/pipeTransport.ts) ·
[Playwright validatorPrimitives](https://github.com/microsoft/playwright/blob/main/packages/protocol/src/validatorPrimitives.ts) ·
[scrcpy develop.md](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md) ·
`emulator_controller.proto` (Android SDK Emulator 36.4.10, local)

Ferramentas:
[VS Code sandbox](https://code.visualstudio.com/blogs/2022/11/28/vscode-sandbox) ·
[VS Code extension host](https://code.visualstudio.com/api/advanced-topics/extension-host) ·
[VS Code 1.94](https://code.visualstudio.com/updates/v1_94) ·
[VS Code telemetria](https://code.visualstudio.com/docs/configure/telemetry) ·
[vscode#79782](https://github.com/microsoft/vscode/issues/79782) ·
[Zed GPUI](https://zed.dev/blog/videogame) ·
[Zed CRDTs](https://zed.dev/blog/crdts) ·
[Zed open source](https://zed.dev/blog/zed-is-now-open-source) ·
[Zed extensões](https://zed.dev/blog/zed-decoded-extensions) ·
[Fleet Below Deck I](https://blog.jetbrains.com/fleet/2022/01/fleet-below-deck-part-i---architecture-overview/) ·
[Fleet Noria](https://blog.jetbrains.com/fleet/2023/02/fleet-below-deck-part-vi-ui-with-noria/) ·
[Future of Fleet](https://blog.jetbrains.com/fleet/2025/12/the-future-of-fleet/) ·
[IntelliJ Split Mode](https://plugins.jetbrains.com/docs/intellij/split-mode-and-remote-development.html) ·
[Depurador 2026.1](https://blog.jetbrains.com/platform/2026/01/platform-debugger-architecture-redesign-for-remote-development-in-2026-1/) ·
[Toolbox e Compose](https://blog.jetbrains.com/kotlin/2021/12/compose-multiplatform-toolbox-case-study/) ·
[Apple Xcode 26.3](https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/) ·
[Rudrank, Xcode MCP](https://rudrank.com/exploring-xcode-using-mcp-tools-cursor-external-clients) (secundária) ·
[Android Studio, aparelho físico](https://developer.android.com/studio/run/device) ·
[Emulator container scripts (WebRTC)](https://github.com/google/android-emulator-container-scripts) ·
[How Warp Works](https://www.warp.dev/blog/how-warp-works) ·
[Warp for Linux](https://www.warp.dev/blog/warp-for-linux) ·
[About Ghostty](https://ghostty.org/docs/about) ·
[libghostty](https://mitchellh.com/writing/libghostty-is-coming) ·
[Playwright codegen](https://playwright.dev/docs/codegen) ·
[Trace viewer](https://playwright.dev/docs/trace-viewer) ·
[UI mode](https://playwright.dev/docs/test-ui-mode) ·
[playwright-python#1850](https://github.com/microsoft/playwright-python/issues/1850) ·
[Playwright MCP](https://github.com/microsoft/playwright-mcp) ·
[Playwright CLI](https://playwright.dev/agent-cli/introduction) ·
[Cypress trade-offs](https://docs.cypress.io/app/references/trade-offs) ·
[Puppeteer e WebDriver BiDi](https://developer.chrome.com/blog/firefox-support-in-puppeteer-with-webdriver-bidi) ·
[scrcpy README](https://github.com/Genymobile/scrcpy) ·
[scrcpy PR #646](https://github.com/Genymobile/scrcpy/pull/646) ·
[scrcpy video.md](https://github.com/Genymobile/scrcpy/blob/master/doc/video.md) ·
[mobile-mcp](https://github.com/mobile-next/mobile-mcp) ·
[appium-mcp](https://github.com/appium/appium-mcp)

Stacks, vídeo e captura:
[Web-to-desktop comparison](https://github.com/Elanis/web-to-desktop-framework-comparison) ·
[tauri#5889](https://github.com/tauri-apps/tauri/issues/5889) ·
[WWDC14 513, VideoToolbox](https://developer.apple.com/videos/play/wwdc2014/513/) ·
[WWDC22 10156, ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/) ·
[idb video](https://fbidb.io/docs/video/) ·
[XCUITest capabilities](https://appium.github.io/appium-xcuitest-driver/latest/reference/capabilities/) ·
[appium#15264](https://github.com/appium/appium/issues/15264) ·
[CoreMediaIO USB iPhone](https://www.codejam.info/2025/06/usb-iphone-screen-recording-swift.html) (secundária) ·
[Apple forum 759245](https://developer.apple.com/forums/thread/759245)

Empacotamento e operação:
[Apple, notarização](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) ·
[PyInstaller usage](https://pyinstaller.org/en/stable/usage.html) ·
[Briefcase macOS](https://briefcase.beeware.org/en/stable/reference/platforms/macOS/) ·
[PyOxidizer, estado](https://gregoryszorc.com/blog/2024/03/17/my-shifting-open-source-priorities/) ·
[python-build-standalone na Astral](https://astral.sh/blog/python-build-standalone) ·
[uv, instalar Python](https://docs.astral.sh/uv/guides/install-python/) ·
[OpenAI e Astral (comentário)](https://simonwillison.net/2026/Mar/19/openai-acquiring-astral/) ·
[Sparkle](https://sparkle-project.org/documentation/) ·
[Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/) ·
[Sentry macOS](https://docs.sentry.io/platforms/apple/guides/macos/)

Código do Mo baile consultado: `engine/src/mobaile/rpc/server.py`,
`engine/src/mobaile/rpc/protocol.py`, `engine/src/mobaile/services/streaming.py`,
`engine/src/mobaile/adapters/{adb,ios_wda,scrcpy,appium}.py`,
`apps/MoBaile/Sources/MoBaile/Engine/{EngineClient,EngineSession,EngineLocator,EngineDTO}.swift`,
`apps/MoBaile/Package.swift`, `Makefile`, `tools/package_macos_app.sh`,
`engine/pyproject.toml`, `.github/workflows/ci.yml`, `docs/ESTADO_ATUAL.md` e
`docs/RELATORIO_QA.md`.

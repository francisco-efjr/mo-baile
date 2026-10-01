# Estudo de mercado 01: inspeção de UI, espelhamento e automação mobile

Frente 1 de 4. Pesquisa feita em 29/09/2026. Todo número tem fonte e data de
consulta (29/09/2026, salvo indicação). Onde a fonte é secundária (blog,
agregador de preço, material de marketing), está marcado como **[secundária]**.
Onde não achei fonte, está escrito **não verificado**.

---

## 1. Resumo executivo

1. **O gargalo do Mo baile é o transporte do quadro, não a detecção de mudança.**
   Hoje cada quadro é um processo novo (`adb exec-out screencap` ou
   `xcrun simctl io screenshot`), vira PNG, vira base64 e atravessa o stdout
   JSON-RPC. O próprio código registra 1,23 s por captura crua num Motorola g55.
   Toda ferramenta de referência abandonou esse modelo: scrcpy (H.264 por
   socket, 35 a 70 ms), Android Studio (agente nativo com vídeo VP8/H.264),
   WebDriverAgent e UiAutomator2 (MJPEG contínuo, 10 fps por padrão), Radon IDE
   e idb (servidor que já guarda o framebuffer), simframe e SimView (IOSurface
   direto, cerca de 20 ms).
2. **O WebDriverAgent que o Mo baile já exige tem um servidor MJPEG pronto**, na
   porta 9100, a 10 fps. Usar isso no iOS é a vitória mais barata do estudo.
3. **A hierarquia Android é lenta por desenho.** `uiautomator dump` espera a
   interface ficar ociosa por no mínimo 1 s e até 10 s, e sobe um processo novo
   a cada chamada. Maestro e Appium mantêm um servidor persistente no aparelho.
   O Mo baile já sabe abrir sessão UiAutomator2, mas só usa como plano B.
4. **O replay do Mo baile é por coordenada e `sleep` fixo.** Maestro, Detox e o
   gravador do Xcode 26 fazem o contrário: localizador, espera automática até o
   elemento aparecer e verificação de que o toque mudou a tela. É a diferença
   entre demo e ferramenta de QA.
5. **Agentes de IA viraram cliente de primeira classe em 2025/2026.** Maestro,
   Appium, mobile-next, Callstack, Software Mansion e o próprio Google (Android
   CLI, Journeys) expõem MCP ou CLI para agente. O motor do Mo baile já fala
   JSON-RPC 2.0 por stdio, que é o mesmo transporte do MCP. Nenhum concorrente
   entrega, na mesma ferramenta, UI, rede HTTP e eventos de analytics para o
   agente. Esse é o diferencial defensável.
6. **Nuvem e low-code não são concorrência direta.** Cobram por dispositivo ou
   minuto (US$ 0,17/min na AWS, US$ 199 a 250/mês por slot na Sauce Labs, Maestro
   Cloud e AWS unmetered) e resolvem escala, não o ciclo local de inspecionar e
   gravar. O Mo baile deve exportar para eles (Appium, Maestro YAML), não
   competir.

---

## 2. Ponto de partida: como o Mo baile funciona hoje (lido no código)

| Área | O que o código faz | Onde |
|---|---|---|
| Captura Android | `adb exec-out screencap` cru (RGBA), com PNG como fallback. Comentário mede 1,23 s cru contra 2,14 s PNG num Motorola g55 | `engine/src/mobaile/adapters/adb.py`, `take_screenshot` |
| Captura iOS | `xcrun simctl io <udid> screenshot -` por quadro, subprocesso novo a cada vez | `adapters/ios_wda.py`, `take_screenshot` |
| Laço do espelho | Thread captura na cadência pedida (padrão 3,5 fps no motor, 6 fps pedido pelo front), miniatura 32x32 em tons de cinza, envia só se mudou, emite `stream.settled` após 0,4 s parado | `services/streaming.py`, `config.py` |
| Transporte do quadro | PNG `compress_level=1`, largura máx. 900, base64 dentro de notificação JSON-RPC no stdout | `rpc/server.py`, `_encode_png` e `stream_start` |
| Decodificação no front | `Data(base64Encoded:)` e `NSImage(data:)` por quadro | `apps/MoBaile/.../Engine/EngineDTO.swift` |
| scrcpy | Abre **janela separada** do scrcpy, sem integração com o canvas | `adapters/scrcpy.py`, `scrcpy.start` |
| Hierarquia Android | `uiautomator dump` + `cat` numa chamada; se falha (SIGKILL no Android 14 da Motorola), abre sessão UiAutomator2 via Appium com `disableWindowAnimation` e passa a usar ela | `adapters/adb.py`, `rpc/server.py::_android_hierarchy`, `adapters/appium.py` |
| Hierarquia iOS | `GET {WDA}/source` sem parâmetros (XML completo, todos os atributos) | `adapters/ios_wda.py::get_ui_hierarchy` |
| Cache | Hierarquia reaproveitada por 1,2 s; `element_at` resolve sobre o último XML | `rpc/server.py::hierarchy_dump` |
| Interação | Só `input.tap` e `input.text` (texto só Android). Nada de swipe, long press, tecla voltar/home | `rpc/server.py`, `DeviceDock` inerte segundo `docs/ESTADO_ATUAL.md` |
| Geração de código | Ranking de localizadores por robustez e unicidade (id, accessibility id, texto, xpath, posição). XPath sempre marcado `matches: 1`, sem contar de verdade | `services/codegen.py::rank_locators` |
| Replay | Script gerado que repete **coordenadas** com `adb shell input tap` ou `wda/tap` e `sleep` fixo (0,5 s, 0,8 s, 1,0 s) | `services/flows.py` |
| Escuta passiva | `getevent` no Android; no iOS, Quartz com altura de barra de título chutada (28 px) | `adapters/input_events.py` |

Ponto forte já presente: o motor só manda quadro quando a tela muda e avisa
quando a tela assentou. Maestro faz a mesma coisa para decidir quando agir
(seção 4.3). O que falta é o cano por onde o quadro passa.

---

## 3. Metodologia

- Fonte primária primeiro: repositório, código-fonte, documentação oficial,
  changelog. Li código do WebDriverAgent (`FBConfiguration.m`,
  `FBDebugCommands.m`, `FBMjpegServer.m`) direto do GitHub.
- Benchmarks de fabricante (ex.: Maestro contra Appium) estão marcados como
  indício, não como fato.
- Não rodei nenhuma ferramenta em aparelho nesta frente. Números de latência
  são os publicados.

---

## 4. Fichas: inspeção e automação

### 4.1 Appium 3 e o ecossistema de drivers

**O que é.** Servidor Node.js que implementa o protocolo W3C WebDriver e
delega para drivers por plataforma. O Appium 2 (2023) tirou drivers e plugins
do núcleo e criou a CLI de extensões (`appium driver install`,
`appium plugin install`). O Appium 3 saiu em 07/08/2025 como limpeza: remove
endpoints JSONWP, exige Node 20.19+, prefixa flags de segurança por driver
(`uiautomator2:adb_shell`), sobe o Express para v5, permite instalar o
Inspector como plugin (`appium plugin install inspector`) e aceita o cabeçalho
`X-Appium-Is-Sensitive` para não logar senha em texto puro.

**Arquitetura.** Cliente (qualquer linguagem) → HTTP WebDriver → servidor
Appium no host → driver → servidor no aparelho:

- **UiAutomator2 driver**: instala um APK de instrumentação
  (appium-uiautomator2-server) que sobe um servidor HTTP no aparelho, porta
  6790 por padrão, redirecionado para `systemPort` 8200-8299 no host. Lê a
  hierarquia com o framework UiAutomator (AccessibilityNodeInfo). Tem servidor
  MJPEG opcional (`mjpegServerPort`, histórico na porta 7810).
- **XCUITest driver**: compila e sobe o **WebDriverAgent**, app de teste
  XCTest que é um servidor HTTP (porta 8100) e traduz WebDriver em chamadas
  XCTest. Tem servidor MJPEG embutido na porta 9100.
- Appium está migrando o controle do simulador de `simctl` para ligação nativa
  com CoreSimulator (`@appium/coresim`, agora no monorepo `appium-ios`,
  v1.10.0 de 29/09/2026), com captura de tela, gravação e stream JPEG sem
  subprocesso por chamada.

**Configurações que determinam a velocidade (defaults lidos na fonte).**

| Driver | Configuração | Padrão | Efeito |
|---|---|---|---|
| UiAutomator2 | `waitForIdleTimeout` | 10.000 ms | Espera ociosidade antes de buscar elemento ou ler árvore |
| UiAutomator2 | `snapshotMaxDepth` | 70 | Profundidade máxima da árvore |
| UiAutomator2 | `ignoreUnimportantViews` | false | Compressão da árvore |
| UiAutomator2 | `simpleBoundsCalculation` | false | Pula cálculo de cobertura, mais rápido |
| UiAutomator2 | `mjpegServerFramerate` / `mjpegScalingFactor` / `mjpegServerScreenshotQuality` | 10 fps / 50% / 50 | Stream contínuo |
| WDA | `mjpegServerPort` | 9100 | Stream MJPEG |
| WDA | `mjpegServerFramerate` / `mjpegServerScreenshotQuality` / `mjpegScalingFactor` | 10 fps / 25 / 100% | idem |
| WDA | `waitForIdleTimeout` / `animationCoolOffTimeout` | 10 s / 2 s | Espera antes de agir |
| WDA | `snapshotMaxDepth` | 50 | Profundidade |
| WDA | `GET /source?format=xml&excluded_attributes=...` | nenhum excluído | `visible` e `accessible` são os atributos caros |

**Desempenho publicado.** `GET /source` do WDA numa lista SwiftUI com 2.847
nós (458 KB): 19 a 21 s de mediana, com timeout acima de 60 s em aparelho
recém-ligado; com 94 a 250 nós, 1,2 a 1,7 s (iPhone real na Sauce Labs,
iOS 18.7 e 26). A documentação do driver diz que o custo vem de resolver
`visible` e `accessible` em toda a árvore e recomenda `snapshotMaxDepth`,
`pageSourceExcludedAttributes` e `format=description`.

**Licença e preço.** Apache-2.0, gratuito.

**Fortes.** Padrão de mercado, multilinguagem, suportado por todas as nuvens.
Ecossistema de plugins. Configurações finas de desempenho.
**Fracos.** Latência por comando (HTTP + WebDriver + driver), defaults
conservadores (10 s de espera por ociosidade), árvore iOS lenta em telas
grandes, curva de configuração alta.

**Fontes.**
[Appium 3 (blog oficial)](https://appium.io/docs/en/3.1/blog/2025/08/07/-appium-3/),
[Migração 2→3](https://appium.io/docs/en/3.1/guides/migrating-2-to-3/),
[UiAutomator2 driver](https://github.com/appium/appium-uiautomator2-driver),
[Issue sobre reduzir waitForIdleTimeout](https://github.com/appium/appium/issues/18451),
[WDA slowness](https://appium.github.io/appium-xcuitest-driver/10.43/troubleshooting/wda-slowness/),
[FBConfiguration.m](https://github.com/appium/WebDriverAgent/blob/master/WebDriverAgentLib/Utilities/FBConfiguration.m),
[FBDebugCommands.m](https://github.com/appium/WebDriverAgent/blob/master/WebDriverAgentLib/Commands/FBDebugCommands.m),
[Medição de /source em 2.847 nós](https://github.com/devicelab-dev/maestro-runner/issues/173),
[@appium/coresim](https://github.com/appium/coresim),
[appium-ios monorepo](https://github.com/appium/appium-ios/releases/tag/%40appium/coresim%401.10.0).

---

### 4.2 Appium Inspector

**O que é.** Cliente Appium com interface gráfica. Por baixo é um cliente
WebdriverIO. Última versão: v2026.9.2 (20/09/2026).

**Arquitetura.** Electron + React + TypeScript + Vite + WebdriverIO. Conecta a
um servidor Appium já rodando (local ou nuvem). Também distribuído como plugin
do servidor (`/inspector`), com paridade de funções. A versão web hospedada em
`inspector.appiumpro.com` não pertence mais ao time do Appium.

**Como captura tela e hierarquia.** Por padrão a captura é **estática**:
screenshot e page source só atualizam quando o usuário pede. Se a sessão for
criada com `appium:mjpegServerPort`, o painel passa a espelhar a tela ao vivo
pelo MJPEG, e dá para alternar entre MJPEG e o endpoint de screenshot W3C.

**Funcionalidades.** Três modos no screenshot (selecionar elemento, tocar por
elemento, tocar por coordenada), aba de comandos, editor de gestos (ticks
reordenáveis desde v2026.9.2), gravador de ações, busca de elemento com
localizador, integração com várias nuvens (Sauce Labs, BrowserStack, HeadSpin,
RobotActions, AstroFarm), anexar a sessão existente por ID (v2026.5.1),
melhoria de geração de XPath (v2026.5.1), troca de display (v2026.7.1).

**Desempenho.** Herdado do Appium: cada atualização custa um page source. Não
achei número oficial de tempo por atualização; o "dez segundos por captura" do
README do Mo baile é **não verificado** como número publicado, mas é coerente
com os 19 a 21 s medidos em telas grandes (4.1) e com o `waitForIdleTimeout`
de 10 s.

**Licença e preço.** Apache-2.0, gratuito.

**Fortes.** Onipresente, fala com qualquer driver e nuvem, gera localizador.
**Fracos.** Modelo "tirar foto e esperar", espelho ao vivo só se o usuário
souber configurar MJPEG, sem rede nem analytics, hierarquia desatualizada em
relação à imagem se a tela mudar entre as duas leituras.

**Fontes.**
[Repositório](https://github.com/appium/appium-inspector),
[Releases](https://github.com/appium/appium-inspector/releases),
[Painel de screenshot](https://appium.github.io/appium-inspector/latest/session-inspector/screenshot/),
[Visão geral](https://appium.github.io/appium-inspector/2025.8/overview/).

---

### 4.3 Maestro, Maestro Studio e Maestro Viewer (mobile.dev)

**O que é.** Framework de E2E caixa-preta para Android, iOS e web, com fluxos
em YAML plano (`launchApp`, `tapOn`, `assertVisible`). CLI 2.11.0 publicada em
29/09 (adiciona Android 17/API 37). Studio Desktop (beta desde 17/07/2025) é
app gratuito e proprietário; o Studio embutido na CLI foi descontinuado nas
versões 2.6/2.7, que lançaram o **Maestro Viewer** (hierarquia e comandos ao
vivo).

**Arquitetura.**
- CLI em Kotlin (JVM 17+), módulos `maestro-orchestra` (motor de fluxo),
  `maestro-client`, `maestro-android`, `maestro-ios-driver`, `maestro-ai`,
  `maestro-web`.
- Android: dois APKs (`dev.mobile.maestro` e `.test`). Um `@Test` de
  instrumentação sobe um **servidor gRPC Netty dentro do aparelho**, que fica
  vivo durante a sessão. A hierarquia vem do UiAutomator e é serializada em
  XML. Algumas ações vão direto por adb.
- iOS: runner XCTest em Swift (`maestro-driver-ios`) com servidor HTTP,
  chamado por cliente Kotlin. A partir da 2.11 recusa aparelho físico cedo;
  foco em simulador.
- Não injeta nada no binário do app (caixa-preta), ao contrário de Espresso,
  XCUITest in-process e Detox.

**Tolerância a flakiness (lida por terceiros no código-fonte).**
- Busca de elemento: 17 s de timeout; elemento opcional: 7 s (`Orchestra.kt`).
- `tapOn` com "retry se nada mudou": compara screenshot antes e depois; se
  menos de 0,5% dos pixels mudou, considera o toque perdido e tenta de novo
  (até 2 tentativas).
- Espera de assentamento: até 10 leituras a cada 200 ms (`ScreenshotUtils`).
  No iOS, `waitUntilScreenIsStatic` compara hash SHA-256 de dois PNGs, com
  limite de 3 s.
- `assertVisible` e `extendedWaitUntil` são esperas ativas: repetem sobre a
  hierarquia mais nova até passar ou estourar o tempo.
- Crítica recorrente: esses tempos são fixos no código e não configuráveis por
  comando.

**Funcionalidades.** Seletores por texto, id, posição relativa (`below`,
`childOf` etc.), `waitForAnimationToEnd`, modo escuro (2.9), artefatos com
screenshot antes de cada passo e hierarquia pareada na falha (2.8), execução
paralela em simuladores (2.7). IA: `assertWithAI` e `extractTextWithAI`
(experimentais, mandam screenshot para LLM), MaestroGPT no Studio, **Maestro
MCP** para agentes (Claude Code, Cursor etc.), "self-healing com agentes
locais" no plano gratuito.

**Desempenho.** O fabricante publica "2 a 3x mais rápido que o Appium" e casos
de 12 s contra 24 s até a home **[secundária, marketing do próprio Maestro]**.

**Licença e preço.** Framework Apache-2.0. Studio gratuito e fechado. Plano
Local grátis (CLI, Studio, Viewer, MCP). Cloud: **US$ 250 por dispositivo/mês**
(concorrência máxima). Enterprise sob consulta.

**Fortes.** Espera automática certa por padrão, YAML legível por QA, servidor
persistente no aparelho, MCP gratuito, ótima adoção em React Native e Flutter.
**Fracos.** Timeouts fixos, iOS sem aparelho físico, YAML limita lógica
complexa, Studio fechado, sem inspeção de rede ou analytics.

**Fontes.**
[Repositório](https://github.com/mobile-dev-inc/Maestro),
[CHANGELOG](https://github.com/mobile-dev-inc/Maestro/blob/main/CHANGELOG.md),
[Releases](https://github.com/mobile-dev-inc/Maestro/releases),
[Preços](https://maestro.dev/pricing),
[Wait commands](https://docs.maestro.dev/maestro-flows/flow-control-and-logic/wait-commands),
[waitForAnimationToEnd](https://docs.maestro.dev/reference/commands-available/waitforanimationtoend),
[assertWithAI](https://docs.maestro.dev/api-reference/commands/assertwithai),
[Análise do código de flakiness](https://dev.to/omnarayan/maestro-flakiness-source-code-analysis-13ng) **[secundária, mas cita arquivos]**,
[Implementação Android (Handstand Sam)](https://handstandsam.com/2024/11/18/demystifying-maestros-ui-testing-implementation/),
[Driver iOS (DeepWiki)](https://deepwiki.com/mobile-dev-inc/Maestro/4.1-ios-driver),
[Studio Desktop no Product Hunt](https://www.producthunt.com/products/maestro-studio-beta),
[Benchmark do fabricante](https://maestro.dev/blog/maestro-vs-appium-the-benchmark).

---

### 4.4 Android Studio: Layout Inspector, Running Devices, Espresso Test Recorder, UI Automator Viewer, Journeys, Android CLI

**Layout Inspector.** Embutido na janela Running Devices. Conecta a processos
**depuráveis** em primeiro plano. Árvore de componentes ao vivo (View, Compose
ou híbrida), painel de atributos, modo de inspeção profunda, isolar subárvore,
**exportar e importar snapshot** (renderização + árvore + atributos),
sobreposição de mockup com transparência, contagem de recomposições e skips do
Compose (API 29+, Compose 1.2+) com gradiente na tela. Alternativa em linha de
comando: `android layout`.

**Running Devices / Device Mirroring.** Espelha aparelho físico dentro do IDE
com toque, rotação, dobra, volume e áudio opcional. Implementação: um agente
nativo ("ScreenSharingAgent") no aparelho codifica vídeo com o encoder de
hardware; o log de erro documentado mostra `c2.android.vp8.encoder`, bitrate
máximo de 20 Mbps. Aparelho com encoder fraco falha. Canal com o adb não é
criptografado.

**Espresso Test Recorder.** Grava interação e gera teste Espresso. Só três
asserções (texto é, existe, não existe). Exige animações desligadas e app
depurável. A página oficial continua publicada sem aviso de descontinuação.

**UI Automator Viewer.** Removido do SDK; a recomendação comum é migrar para o
Appium Inspector **[secundária]**.

**Journeys (Gemini).** Testes E2E em linguagem natural, em XML, com editor
código/design. Cada passo manda **screenshot** (não a árvore) ao Gemini, que
decide a ação. Disponível desde Android Studio Otter 3 Feature Drop
(2025.2.3), exige AGP 9+ e login. Limitações: sem multi-toque, long press,
duplo toque, rotação, condicional ou memória entre passos. Roda também por
Android CLI e CI.

**Android CLI (2026).** CLI oficial para agentes: emulador, SDK, instalar e
rodar app, captura de tela, `android layout` (hierarquia em JSON, `--flat`,
`--full`, `--no-idle` para não esperar ociosidade), render de preview Compose,
comandos do Studio (`find-usages`, `analyze-file`). Página atualizada em
21/09/2026.

**Licença e preço.** Android Studio gratuito; Journeys depende de conta Gemini.

**Fortes.** Inspeção com dados de runtime que acessibilidade não vê
(atributos de View/Compose, recomposição), espelho com vídeo de hardware,
snapshot compartilhável.
**Fracos.** Só Android, só app depurável para o Layout Inspector, nenhum
gerador de Page Object Appium, gravador Espresso limitado.

**Fontes.**
[Layout Inspector](https://developer.android.com/studio/debug/layout-inspector),
[Debug de Compose](https://developer.android.com/develop/ui/compose/tooling/debug),
[Device mirroring](https://developer.android.com/studio/run/device),
[Espresso Test Recorder](https://developer.android.com/studio/test/other-testing-tools/espresso-test-recorder),
[UI Automator Viewer removido](https://dev.to/svendster/fix-for-missing-android-ui-automator-viewer-1eh2) **[secundária]**,
[Journeys](https://developer.android.com/studio/gemini/journeys),
[Agent tools](https://developer.android.com/tools/agents),
[android layout](https://developer.android.com/tools/agents/android-cli/commands/layout).

---

### 4.5 Xcode: Accessibility Inspector, gravação de UI tests, View Debugger

**Accessibility Inspector.** App do Xcode que inspeciona elemento por
apontador (label, value, traits, hint) no Simulator ou aparelho, simula
navegação do VoiceOver e roda **auditoria** (label faltando, contraste,
tamanho de alvo). Desde o Xcode 15 a auditoria também roda dentro do XCUITest
(`performAccessibilityAudit`).

**Gravação de UI tests (Xcode 26, WWDC25 sessão 344).** Grava toque, swipe,
texto e botões físicos e gera código XCUITest em tempo real com um novo sistema
de geração. Para cada linha, oferece **menu de consultas alternativas** para o
mesmo elemento (por texto, por identificador, `firstMatch`) com recomendação:
preferir accessibilityIdentifier, consulta curta, consulta genérica para
conteúdo dinâmico. Replay em várias línguas e aparelhos via test plans.
Relatório com vídeo, pontos de toque sobrepostos, linha do tempo com falhas e
**inspeção dos elementos presentes no momento da falha** (Automation
Explorer).

**View Debugger.** Pausa o app e captura a hierarquia de views em 3D
explodido, com restrições e propriedades. Funciona com SwiftUI, com relatos de
crash em telas mistas UIKit/SwiftUI.

**Licença e preço.** Gratuito com o Xcode, só macOS.

**Fortes.** Fonte de verdade da Apple, gravação com escolha de localizador,
relatório de falha excelente.
**Fracos.** Só iOS, só XCUITest em Swift, exige projeto e target de teste; não
serve para quem escreve Appium em Python ou Java.

**Fontes.**
[WWDC25 344: Record, replay, and review](https://developer.apple.com/videos/play/wwdc2025/344/),
[Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector),
[Auditorias de acessibilidade](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app),
[Crash no View Debugger](https://developer.apple.com/forums/thread/791379).

---

### 4.6 Detox (Wix)

**O que é.** Framework E2E caixa-cinza para React Native.

**Arquitetura.** Biblioteca de sincronização roda **dentro do processo do app**
(DetoxSync no iOS; Espresso no Android) e acompanha recursos ocupados:
requisições de rede em voo, fila da main thread, layout, animações, timers,
ponte do React Native. O teste só age quando o app está ocioso.

**Desempenho.** Sem número oficial encontrado (**não verificado**). O ganho
declarado é estabilidade, não velocidade.

**Licença e preço.** MIT, gratuito.

**Fortes.** Elimina `sleep` pela raiz, ótimo para RN.
**Fracos.** Exige build instrumentado, só RN na prática, app com animação
infinita ou polling nunca fica ocioso.

**Fontes.**
[How Detox works](https://wix.github.io/Detox/docs/articles/how-detox-works/),
[Sincronização](https://wix.github.io/Detox/docs/troubleshooting/synchronization/),
[DetoxSync](https://github.com/wix/DetoxSync).

---

### 4.7 Radon IDE e Argent (Software Mansion)

**O que é.** Radon: extensão de VS Code e Cursor que roda simulador iOS e
emulador Android dentro do editor, para React Native e Expo, com inspetor de
elemento, depurador, inspetor de rede, logs, replays, gravação e assistente de
IA. Argent: toolkit para agentes controlarem simulador, emulador e aparelho por
CLI, com gravação e replay determinístico de fluxos, regressão visual com OCR e
profiling.

**Arquitetura.** Um binário proprietário, `simulator-server`, codifica **cada
quadro** da tela do dispositivo para o stream ao vivo em **MJPEG**, com o
overlay de toque desenhado. Em julho/2026 a gravação passou a ser feita pelo
próprio `simulator-server` (30 fps, recorta trechos estáticos, gera mp4 a
partir dos quadros que ele já guarda), eliminando uma segunda codificação via
ffmpeg no host.

**Licença e preço.** Radon: comercial. Free (uso não comercial), Pro US$ 25/mês
(US$ 252/ano), Team US$ 75/mês, Enterprise sob consulta. Argent: código
Apache-2.0, binários proprietários.

**Fortes.** Espelho fluido embutido, integração com Maestro e Storybook.
**Fracos.** Nicho React Native, binário fechado, preço por dev.

**Fontes.**
[Radon (repo)](https://github.com/software-mansion/radon-ide),
[Preços](https://radon.swmansion.com/pricing),
[Argent](https://github.com/software-mansion/argent),
[PR 587: gravação via simulator-server](https://github.com/software-mansion/argent/pull/587).

---

### 4.8 Flipper (Meta)

**Situação.** O React Native anunciou o desacoplamento na 0.73 e removeu a
integração padrão na 0.74 (abril/2024) por custo de manutenção. Flipper segue
como ferramenta avulsa de integração manual; o RN recomenda o novo depurador
baseado em Chrome DevTools e as ferramentas nativas do Android Studio e do
Xcode.

**Arquitetura (histórica).** SDK dentro do app + app desktop Electron, com
plugins (layout, rede, banco, logs).

**Licença.** MIT.

**Lição.** Ferramenta que exige SDK dentro do app perde adoção quando o
framework deixa de embuti-la. Reforça a escolha do Mo baile de não instrumentar
o app sob teste.

**Fontes.**
[RN 0.74](https://reactnative.dev/blog/2024/04/22/release-0.74),
[Proposta de desacoplamento](https://github.com/react-native-community/discussions-and-proposals/blob/main/proposals/0641-decoupling-flipper-from-react-native-core.md).

---

## 5. Fichas: espelhamento

### 5.1 scrcpy (Genymobile)

**O que é.** Espelho e controle de Android via adb, sem root nem app
instalado. v4.0 (maio/2026: SDL3, flex display com virtual display
redimensionável, torch e zoom de câmera, `--keep-active`); v4.1 é a mais
recente listada (encoders VP8 e VP9).

**Arquitetura (documento `develop.md`, versão 4.0).**
- O cliente faz push de `scrcpy-server.jar` e executa
  `adb shell CLASSPATH=... app_process / com.genymobile.scrcpy.Server <versão>`.
  Servidor e cliente precisam ter **exatamente a mesma versão**; o protocolo é
  interno e muda sem aviso.
- Até **três sockets**: vídeo, áudio e controle, por túnel adb
  (`adb reverse localabstract:scrcpy_<SCID>` preferido, `adb forward` como
  fallback). O cliente escuta antes de subir o servidor para evitar corrida.
- Vídeo: `MediaCodec` no aparelho, H.264, H.265, AV1, VP8, VP9. Pacote de
  sessão de 12 bytes (largura, altura) a cada reinício de captura, e pacote de
  mídia com cabeçalho de 12 bytes (flags config/keyframe, PTS de 61 bits,
  tamanho de 32 bits).
- Controle: protocolo binário próprio; o servidor injeta com
  `InputManager.injectInputEvent()`. A documentação admite que a única
  especificação são os testes unitários.
- Cliente: FFmpeg decodifica, SDL desenha "assim que possível, sem buffer".

**Desempenho publicado.** 30 a 120 fps (depende do aparelho), latência de
**35 a 70 ms**, início em cerca de 1 s. Android 5.0 (API 21)+; áudio 11+;
câmera 12+.

**Licença.** Apache-2.0, gratuito.

**Fortes.** Latência de referência do mercado, codec de hardware, controle de
baixa latência, gravação, virtual display.
**Fracos.** Protocolo instável entre versões, janela própria (SDL) difícil de
embutir, sem hierarquia de UI.

**Fontes.**
[Repositório](https://github.com/Genymobile/scrcpy),
[develop.md](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md),
[Release 4.0](https://github.com/Genymobile/scrcpy/releases/tag/v4.0),
[Notícia 4.0](https://alternativeto.net/news/2026/5/scrcpy-4-0-brings-sdl3-support-dynamic-aspect-ratio-enhanced-camera-controls-and-more/).

### 5.2 QtScrcpy

Reimplementação do cliente do scrcpy em C++/Qt com renderização por GPU, que
reaproveita o servidor do scrcpy. Alega latência abaixo de 30 ms em 1080p por
USB **[alegação do próprio projeto]**. Apache-2.0. Interessa ao Mo baile como
**prova de que dá para embutir o protocolo do scrcpy numa UI nativa própria**.
Fontes: [QtScrcpy (fork com README)](https://github.com/toantk238/QtScrcpy),
[SourceForge](https://sourceforge.net/projects/qtscrcpy.mirror/).

### 5.3 Vysor

Espelho Android por adb, fechado, com decodificador H.264 do Chrome (trocou o
decodificador próprio após disputa de patente com a MPEG LA em 2016). Pro a
partir de US$ 2,50/mês ou US$ 40 vitalício **[secundária]**. Fontes:
[vysor.app](https://www.vysor.app/),
[Android Authority](https://www.androidauthority.com/koushik-dutta-pulls-vysor-due-patent-licensing-demand-mpeg-la-692446/),
[preço](https://vysor.org/vysor-pro/) **[secundária]**.
Lição: codec tem questão de patente; usar o decodificador do sistema
(VideoToolbox no macOS) evita o problema.

### 5.4 idb (Meta)

**O que é.** iOS Development Bridge: `idb_companion` (macOS, agora em Swift) +
cliente Python por gRPC. Usa frameworks privados do Xcode
(FBSimulatorControl, FBDeviceControl, XCTestBootstrap). Simulador e aparelho.
MIT. Compila com Xcode 26.

**Tela.** `idb video-stream` com formatos h264, mjpeg, minicap e bgra, com
codificação no VideoToolbox. Há bugs abertos de parâmetros de baixa latência no
encoder JPEG.

**Hierarquia.** `idb ui describe-all` só no simulador, via
`sendAccessibilityRequestAsync` do CoreSimulator e AXPTranslator. Medição
pública (projeto Quern): 134 ms para ler a árvore, mas **2.967 ms** quando
precisa sondar contêineres (tab bar não aparece na caminhada estática), 92% do
tempo em sondagem. Há relatos de incompatibilidade com o simulador iOS 26.3.

**Fontes.**
[Repositório](https://github.com/facebook/idb),
[Vídeo](https://fbidb.io/docs/video/),
[Acessibilidade](https://fbidb.io/docs/accessibility/),
[PR do encoder JPEG](https://github.com/facebook/idb/pull/958),
[Medição de sondagem](https://github.com/quern-dev/quern/issues/196),
[Incompatibilidade 26.3](https://github.com/beastoin/agent-swift/issues/1).

### 5.5 `simctl io` e como a Apple expõe o Simulator

- `xcrun simctl io <udid> screenshot` gera PNG por chamada.
  `recordVideo` grava h264 ou hevc (padrão hevc) **só para arquivo**: saída
  para stdout "não é mais suportada".
- Não existe API pública de stream contínuo do Simulator. Por baixo, o
  framebuffer de cada display é um **IOSurface** acessível pelos frameworks
  privados CoreSimulator e SimulatorKit (`-[SimDevice io]`, porta do display
  principal, `framebufferSurface` desde o Xcode 13.2), e o toque entra por
  funções HID "Indigo" do SimulatorKit.
- Quem usa isso:
  - **simframe** (MIT): daemon Swift lê o IOSurface quando o display reporta
    dano; captura em **~20 ms** contra **130 a 400 ms** do screenshot via simctl;
    detecção de mudança em ~2 ms (iPhone 17 Pro, iOS 26.5). Avisa que uma
    atualização do Xcode pode mover símbolo (e já precisou de correção para o
    Xcode 27, que moveu o SimulatorKit para SharedFrameworks).
  - **SimView** (Apache-2.0): IOSurface + H.264 no VideoToolbox + HID Indigo;
    no Android, agente próprio temporário e UIAutomator para a árvore; binário
    único com protocolo binário versionado; exposto como MCP App.
  - **@appium/coresim**: ligação nativa a CoreSimulator em Node, com
    screenshot, vídeo, stream JPEG e áudio sem subprocesso por chamada.

**Fontes.**
[simctl recordVideo sem stdout](https://developer.apple.com/forums/thread/694901),
[simframe](https://github.com/lvlrSajjad/simframe),
[correção Xcode 27](https://github.com/lvlrSajjad/simframe/pull/1),
[SimView](https://github.com/ToolingTools/SimView),
[FBSimulatorControl](https://fbidb.io/docs/idb/fbsimulatorcontrol/),
[@appium/coresim](https://github.com/appium/coresim).

---

## 6. Fichas: nuvem e low-code

Resumo por ficha curta, porque nenhuma disputa o ciclo local do Mo baile.

| Ferramenta | Arquitetura e funcionalidade-chave | Preço (29/09/2026) | Fortes / fracos | Fontes |
|---|---|---|---|---|
| **BrowserStack** App Live, App Automate, Low Code | Fazenda de aparelhos reais, sessão manual no navegador (App Live), grade Appium/Espresso/XCUITest (App Automate), gravador low-code com self-healing e agentes de autoria. Declara 30.000+ aparelhos | App Live a partir de US$ 29/mês; App Automate de US$ 129 a 249/mês por paralelo **[secundária; tabela oficial não expõe tudo]** | Cobertura imensa / latência de rede no espelho, custo por paralelo | [Low Code](https://www.browserstack.com/low-code-automation), [self-heal](https://www.browserstack.com/docs/low-code-automation/test-recording/browserstack-ai/ai-self-heal), [App LCA](https://www.browserstack.com/docs/app-lca), [preço](https://bug0.com/knowledge-base/browserstack-pricing) |
| **Sauce Labs** | Real Device Cloud e Virtual Device Cloud, Appium/Espresso/XCUITest, integração com Appium Inspector | RDC US$ 199/mês anual ou 249 mensal; VDC US$ 149/199 **[secundária, verificada 31/07/2026 pela fonte]** | Maduro, enterprise / preço opaco acima do básico | [Preços](https://saucelabs.com/pricing), [análise](https://bug0.com/knowledge-base/sauce-labs-pricing) |
| **TestMu AI** (ex-LambdaTest, rebatizada em 12/01/2026), HyperExecute, KaneAI | 10.000+ aparelhos reais; HyperExecute distribui testes sem hub-nó (alega até 70% mais rápido); KaneAI gera e re-ancora testes a partir de intenção | Sob consulta / tabela no site | Foco em IA / números de marketing | [Rebrand](https://www.testmuai.com/lambdatest-is-now-testmuai/), [KaneAI](https://www.testmuai.com/blog/what-is-lambdatest-kaneai/), [preços](https://www.testmuai.com/pricing/) |
| **Kobiton** | Aparelhos reais, sessão manual convertida em script Appium, self-healing, conectar aparelho local (plano Scale) | Start Up US$ 83/mês (500 min), Accelerate US$ 399/mês, Scale US$ 9.000/ano **[secundária]** | Replay de sessão manual / minutos contados | [Preços](https://kobiton.com/pricing/), [review](https://thectoclub.com/tools/kobiton-review/) |
| **AWS Device Farm** | Aparelhos reais, testes automatizados e acesso remoto | US$ 0,17 por minuto-aparelho (1.000 min grátis); unmetered US$ 250 por slot/mês | Barato no avulso, integrado à AWS / espelho remoto básico | [FAQ](https://aws.amazon.com/device-farm/faqs/), [preço](https://aws.amazon.com/device-farm/pricing) |
| **Katalon Studio** | IDE sobre Selenium e Appium, Mobile Recorder e Spy Mobile; iOS híbrido não suportado no recorder | Free; Professional a partir de US$ 84/usuário/mês | Tudo-em-um / pesado, pouco controle | [Mobile Recorder](https://docs.katalon.com/katalon-studio/record-and-spy/mobile-record-and-spy-utilities/mobile-recorder-utility), [preços](https://katalon.com/pricing) |
| **Repeato** | Record & play no-code com **visão computacional**, independe da árvore; Flutter, RN, Unity | Até ~US$ 120/mês, versão gratuita limitada **[secundária]** | Funciona onde não há acessibilidade / frágil a mudança visual | [Site](https://www.repeato.app/), [preços](https://www.repeato.app/pricing/) |
| **Waldo** | No-code mobile, comprado pela Tricentis em 07/07/2023 | Sob consulta | Status atual do produto avulso **não verificado** | [Tricentis](https://www.tricentis.com/news/tricentis-acquires-codeless-mobile-test-automation-platform-waldo) |
| **Mobot** | Robôs mecânicos com visão computacional tocando aparelhos físicos, supervisionados por humanos; cliente manda vídeo do teste | Sob consulta | Biometria, câmera, deep link / serviço, não ferramenta | [Como funciona](https://www.mobot.io/how-it-works) |

---

## 7. Fichas: agentes de IA para mobile (2025/2026)

| Ferramenta | Como lê a tela | Como age | Licença / preço | Destaque | Fontes |
|---|---|---|---|---|---|
| **mobile-mcp** (mobile-next) | Árvore de acessibilidade primeiro, sem modelo de visão; screenshot + coordenada só como recurso | Android por adb; iOS por `mobilecli` (Go) com agente no aparelho físico e ferramentas do Xcode no simulador | Apache-2.0; `mobilecli` em FSL-1.1-Apache-2.0 | 8,4 mil estrelas; `mobilecli` tem modo servidor **JSON-RPC 2.0** (HTTP e WebSocket), stream MJPEG e H.264, snapshot da árvore em texto indentado com `ref` | [mobile-mcp](https://github.com/mobile-next/mobile-mcp), [mobilecli](https://github.com/mobile-next/mobilecli) |
| **Appium MCP** | Page source XML; visão opcional por descrição em linguagem natural, com cache de 5 min | Sessão Appium | Apache-2.0 | Gera localizador com prioridade accessibility id > resource id > predicado nativo > XPath, e gera código de teste | [appium-mcp](https://github.com/appium/appium-mcp) |
| **Maestro MCP / Maestro AI** | Hierarquia; `assertWithAI` e `extractTextWithAI` por screenshot | Comandos Maestro | Grátis no plano Local | Agente escreve YAML repetível enquanto desenvolve | [preços](https://maestro.dev/pricing), [assertWithAI](https://docs.maestro.dev/api-reference/commands/assertwithai) |
| **GPT Driver** (MobileBoost) | Comando determinístico com visão como fallback | SDK sobre XCUITest, Espresso, Appium | Comercial; já cobrou a partir de US$ 799/mês por passos de IA **[secundária, preço saiu do site]** | Híbrido determinístico + IA | [site](https://www.mobileboost.io/), [preço](https://www.sota2.com/products/mobileboost-gpt-driver) |
| **Arbigent** | Árvore otimizada + screenshot anotado; dicas `[[aihint:...]]` no label | Drivers do **Maestro** | Apache-2.0 | Decompõe cenários dependentes, cache de resposta da IA quando árvore e objetivo são iguais, `replayWithFallback`, detecção de tela travada | [arbigent](https://github.com/takahirom/arbigent) |
| **Drizz** | Visão pura | Proprietário | Comercial; seed de US$ 2,7 mi (jul/2025) | Testes em inglês simples | [SiliconANGLE](https://siliconangle.com/2025/07/28/drizz-launches-2-7m-provide-vision-based-testing-ai-mobile-apps/) |
| **Midscene.js** (ByteDance/web-infra) | Visão pura (evita mandar árvore ao modelo) | Android via scrcpy e adb; iOS via WDA | MIT, 15 mil estrelas | Multi-modelo (UI-TARS, Qwen, Gemini) | [midscene](https://github.com/web-infra-dev/midscene) |
| **DroidRun / Mobilerun** | Árvore de acessibilidade via app Portal no aparelho | Serviço de acessibilidade | Open source; pré-seed de € 2,1 mi | 91,4% no AndroidWorld | [repo](https://github.com/droidrun/mobilerun), [review](https://blog.jerrryy.com/blog/droidrun-review/) **[secundária]** |
| **agent-device** (Callstack) | Snapshot de acessibilidade com refs (`@e2`), válido só até o próximo comando; `--settle` | XCTest no aparelho iOS, ponte de acessibilidade no simulador, adb no Android | MIT | CLI + MCP + API Node, várias plataformas | [agent-device](https://github.com/callstack/agent-device) |
| **simframe / SimView** | IOSurface direto (ver 5.5), OCR do Vision | HID Indigo | MIT / Apache-2.0 | simframe: ~330 tokens por leitura contra ~1.600 com imagem | ver 5.5 |
| **Journeys** (Google) e **App Testing agent** (Firebase) | Screenshot para o Gemini | Ações no aparelho | Gratuito com Gemini / Firebase | Casos em linguagem natural, CLI e CI | [Journeys](https://developer.android.com/studio/gemini/journeys), [App Testing agent](https://firebase.google.com/docs/app-distribution/android/app-testing-agent) |

**Padrões que se repetem nos agentes.**
1. Árvore compacta com referência curta por elemento vence imagem em custo e
   precisão; imagem entra como fallback.
2. A referência vale só para o snapshot atual (agent-device); ler a árvore e
   agir precisa ser atômico ou validado.
3. Esperar a tela assentar antes de ler (`--settle`, `waitForAnimationToEnd`).
4. Replay determinístico do que funcionou, IA só quando quebra (Arbigent,
   GPT Driver, self-healing de BrowserStack e Kobiton).

---

## 8. Matriz comparativa

### 8.1 Captura de tela

| Ferramenta | Mecanismo | Formato | Cadência / latência publicada | Processo por quadro? |
|---|---|---|---|---|
| **Mo baile hoje, Android** | `adb exec-out screencap` | RGBA cru → PNG → base64 | 1,23 s por captura (Moto g55, medido no código) | Sim |
| **Mo baile hoje, iOS** | `simctl io screenshot` | PNG → base64 | 130 a 400 ms por captura (medida do simframe para simctl) | Sim |
| scrcpy | MediaCodec no aparelho, socket via adb | H.264/H.265/AV1 | 30 a 120 fps, 35 a 70 ms | Não |
| Android Studio mirroring | Agente nativo, encoder de hardware | VP8 (log oficial), outros | Não publicado | Não |
| UiAutomator2 MJPEG | Screenshot no servidor do aparelho | MJPEG | 10 fps padrão, até 60 | Não |
| WDA MJPEG | `XCUIScreen` dentro do WDA | MJPEG, qualidade 25 | 10 fps padrão | Não |
| idb | FBSimulatorControl, VideoToolbox | h264, mjpeg, bgra | Não publicado | Não |
| simframe / SimView | IOSurface do framebuffer | bruto / H.264 | ~20 ms por leitura (simframe) | Não |
| Radon | `simulator-server` proprietário | MJPEG | Não publicado | Não |

### 8.2 Hierarquia

| Ferramenta | Android | iOS | Custo conhecido |
|---|---|---|---|
| **Mo baile hoje** | `uiautomator dump` por chamada; UiAutomator2 como plano B | WDA `/source` completo | `dump` espera ociosidade de 1 s a 10 s (`waitForIdle(1000, 10000)` no `DumpCommand`) |
| Appium | Servidor UiAutomator2 persistente | WDA | idle 10 s padrão; `/source` 19 a 21 s com 2.847 nós |
| Maestro | Servidor gRPC persistente com UiAutomator | Runner XCTest | Timeouts fixos 17 s / 7 s |
| idb | não se aplica | AXPTranslator no simulador | 134 ms sem sondagem, 2.967 ms com |
| Android Studio | Agente do Layout Inspector (app depurável) | não se aplica | Não publicado |
| Android CLI | `android layout` (JSON, opção `--no-idle`) | não se aplica | Não publicado |

### 8.3 Posicionamento

| | Espelho ao vivo | Árvore | Gera código | Replay robusto | Rede HTTP | Analytics | Agente/MCP | Licença |
|---|---|---|---|---|---|---|---|---|
| **Mo baile** | Sim, lento | Sim | Page Object Appium | Não (coordenada) | Sim | Sim | Não | Próprio |
| Appium Inspector | Só com MJPEG configurado | Sim | Sim | Via Appium | Não | Não | Appium MCP à parte | Apache-2.0 |
| Maestro Studio/Viewer | Sim | Sim | YAML | Sim | Não | Não | Sim | Framework Apache-2.0, Studio fechado |
| Android Studio | Sim (físico) | Sim (depurável) | Espresso limitado | Journeys (IA) | App Inspection | Não | Android CLI | Grátis |
| Xcode 26 | Simulator | Accessibility Inspector | XCUITest | Sim | Instruments | Não | Não | Grátis |
| Radon | Sim | Sim (RN) | Não | Replays | Sim | Não | Argent | Comercial |
| mobile-mcp | Stream via mobilecli | Sim (texto) | Não | Não | Não | Não | Sim | Apache-2.0 |

A última coluna de rede + analytics é o espaço vazio. Nenhuma ferramenta
estudada mostra, lado a lado com a árvore de UI, o tráfego HTTP e o evento de
tagueamento disparados pelo toque.

---

## 9. Opinião: o que isso significa para o Mo baile

Separado dos fatos acima, de propósito.

- **Não brigar com Appium nem Maestro na execução em escala.** Eles já ganharam
  nisso e são gratuitos. O Mo baile ganha no ciclo local de "olhar, entender,
  gravar, conferir rede e tagueamento" e deve exportar para o executor que o
  time já usa.
- **A promessa do README ("cansou de esperar dez segundos") hoje só é cumprida
  pela metade.** A detecção de mudança é boa, mas a captura por subprocesso e o
  PNG em base64 deixam o espelho em 1 a 3 fps reais no Android físico. Sem
  resolver isso, o argumento de venda não se sustenta numa demonstração lado a
  lado com o Maestro Viewer ou o Android Studio.
- **O motor por stdio é um ativo subestimado.** Ele é exatamente o que um
  servidor MCP precisa ser. Com pouco código, o Mo baile vira a primeira
  ferramenta que dá a um agente a tela, a árvore, o tráfego e o analytics na
  mesma sessão.
- **Evitar frameworks privados da Apple no primeiro passo.** O ganho do IOSurface
  é real (20 ms contra centenas), mas cada Xcode novo pode quebrar. O MJPEG do
  WDA entrega a maior parte do ganho sem esse risco.

---

## 10. Lições para o Mo baile

Cada ideia traz problema, evidência, o que já existe no código, esforço
(P = até 3 dias, M = 1 a 2 semanas, G = mais de 2 semanas), risco e critério de
pronto. Ordenadas por valor sobre esforço.

### L1. Espelho iOS pelo MJPEG do WebDriverAgent

- **Problema.** Cada quadro iOS é um `simctl io screenshot` novo: processo,
  PNG, leitura do disco virtual. Espelho travado em poucos quadros por segundo.
- **Evidência.** WDA sobe servidor MJPEG na porta 9100 a 10 fps, qualidade 25
  (`FBConfiguration.m`, `FBMjpegServer.m`). Appium Inspector usa exatamente isso
  para espelho ao vivo. simframe mede 130 a 400 ms por screenshot via simctl.
- **O que existe.** O Mo baile já exige WDA rodando e conhece a URL
  (`settings.wda_url`). Nenhuma referência a 9100 ou MJPEG no código.
- **O que fazer.** Novo adapter `ios_mjpeg.py`: lê `multipart/x-mixed-replace`
  de `http://localhost:9100`, entrega o último JPEG ao `RealTimeStreamEngine`
  (que continua fazendo diff e settle). Ajustar
  `mjpegServerFramerate`/`mjpegScalingFactor` via settings da sessão. Fallback
  automático para `simctl` se a porta não responder. Em aparelho físico, exige
  encaminhamento de porta (fora do escopo inicial).
- **Esforço.** P.
- **Risco.** Baixo. MJPEG do WDA pode cair quando o app está ocupado (o próprio
  WDA faz backoff de 1 a 10 s em falha); o fallback cobre.
- **Pronto quando.** `stream.stats` mostra fonte `wda_mjpeg`, fps efetivo ≥ 8
  num simulador animando, e desligar o WDA faz o espelho cair para `simctl` sem
  erro na interface.

### L2. Espelho Android por vídeo H.264 (protocolo do scrcpy), desenhado no canvas do app

- **Problema.** 1,23 s por quadro no Android físico. E o modo scrcpy atual abre
  uma janela separada, fora do canvas, o que obriga a escuta passiva a adivinhar
  geometria de janela.
- **Evidência.** scrcpy: 35 a 70 ms, 30 a 120 fps, codec de hardware, protocolo
  documentado (três sockets, cabeçalho de 12 bytes). QtScrcpy prova que dá para
  embutir o servidor do scrcpy numa UI própria. Android Studio e SimView fazem o
  mesmo com agente próprio.
- **O que existe.** `adapters/scrcpy.py` localiza o binário e sobe janela.
  Nenhum código fala o protocolo.
- **O que fazer.** Passo 1 (M): motor sobe o `scrcpy-server` da mesma
  instalação do binário (versão igual, exigência do protocolo), abre o túnel e
  repassa os pacotes de vídeo ao front por um **canal binário separado** (ver
  L3). O front decodifica com VideoToolbox e desenha em
  `AVSampleBufferDisplayLayer`. Controle de toque pelo socket de controle
  (injeção direta, sem subir `input` a cada toque). Passo 2: diff e settle
  passam a rodar sobre quadro decodificado em baixa resolução, pedido ao front
  ou decodificado no motor só na cadência de settle.
  Alternativa mais barata e intermediária (P): quando já houver sessão
  UiAutomator2, ler o MJPEG dela (10 fps).
- **Esforço.** G (caminho H.264), P (caminho MJPEG do UiAutomator2).
- **Risco.** Alto no H.264: protocolo interno muda a cada versão do scrcpy.
  Mitigar fixando versão suportada, testando o handshake no `diagnostics.check`
  e caindo para screencap quando a versão não bater.
- **Pronto quando.** Latência toque→quadro p50 < 150 ms num aparelho físico de
  referência (Moto g55), medida com vídeo em câmera lenta ou timestamp de
  injeção; janela externa do scrcpy deixa de ser necessária.

### L3. Tirar o quadro do JSON: JPEG já, canal binário depois

- **Problema.** Todo quadro vira PNG, depois base64 (+33%), depois linha JSON
  no mesmo stdout que carrega as respostas RPC. Quadro grande atrasa resposta de
  `hierarchy.dump` e vice-versa (o próprio `EngineSession.swift` documenta o
  engarrafamento de notificações).
- **Evidência.** Nenhuma ferramenta de referência trafega imagem em texto: WDA
  e UiAutomator2 usam MJPEG binário; scrcpy, pacotes binários por socket
  dedicado; SimView, protocolo binário versionado; Radon grava do buffer que já
  tem, sem recodificar.
- **O que existe.** `_encode_png` com `compress_level=1`, largura 900.
- **O que fazer.** Passo 1 (P): `stream.start` aceita `format: "jpeg"` com
  qualidade 70; o front já decodifica com `NSImage`. Passo 2 (M): quadros
  saem por um segundo pipe herdado (fd 3) ou socket Unix criado pelo front, com
  cabeçalho binário curto (id do quadro, dimensões, timestamp) e a notificação
  JSON leva só metadados. Mantém a regra de não abrir porta TCP.
- **Esforço.** P + M.
- **Risco.** Médio no passo 2: muda o contrato e as fixtures; precisa de teste
  de enquadramento dos dois lados.
- **Pronto quando.** Tamanho médio por quadro cai pelo menos 3 vezes (medir);
  `hierarchy.dump` com espelho ligado responde no mesmo tempo que com espelho
  desligado (±10%).

### L4. Hierarquia Android por servidor persistente e sem espera de ociosidade

- **Problema.** `uiautomator dump` sobe um processo novo e espera a interface
  ficar ociosa entre 1 s e 10 s antes de ler. Em tela com animação contínua,
  paga os 10 s ou falha. Em Motorola com Android 14, morre com SIGKILL.
- **Evidência.** `DumpCommand` usa `waitForIdle(1000, 1000 * 10)`. Maestro e
  Appium mantêm servidor no aparelho. UiAutomator2 permite baixar
  `waitForIdleTimeout` (padrão 10.000 ms) e há proposta aberta para default
  pequeno. Android CLI oferece `--no-idle` pelo mesmo motivo.
- **O que existe.** `AppiumBridge.ensure_android_session` e o cache de
  backend por aparelho em `_android_hierarchy`. Nenhuma chamada de settings.
- **O que fazer.** Quando o Appium estiver instalado, preferir a sessão
  UiAutomator2 desde o início (não só após falha), e aplicar settings
  `waitForIdleTimeout` baixo (ex.: 100 a 300 ms) e `ignoreUnimportantViews`
  opcional. Como o motor já emite `stream.settled`, a espera de ociosidade do
  Android vira redundante: o Mo baile já sabe quando a tela parou. Médio prazo:
  servidor de instrumentação próprio e mínimo (sem Appium) se o Appium virar
  dependência pesada demais.
- **Esforço.** P (settings + preferência), G (servidor próprio).
- **Risco.** Baixo. Árvore lida no meio de animação pode vir intermediária; o
  gatilho continua sendo `stream.settled`.
- **Pronto quando.** Tempo p50 de `hierarchy.dump` medido antes e depois no
  aparelho de referência, com meta de < 700 ms numa tela típica e sem nenhum
  caso de 10 s em tela com animação infinita.

### L5. Hierarquia iOS mais barata no WDA

- **Problema.** `GET /source` sem parâmetros resolve `visible` e `accessible`
  para todos os nós, que são os atributos caros. Em lista SwiftUI grande,
  segundos a dezenas de segundos.
- **Evidência.** `FBDebugCommands.m` aceita `excluded_attributes` e
  `format=json|description`; a documentação do driver aponta esses atributos e
  `snapshotMaxDepth` como principais causas. Medição pública: 19 a 21 s em
  2.847 nós.
- **O que existe.** `IOSBridge.get_ui_hierarchy` sem parâmetro. O parser usa
  `accessible` para decidir `clickable` no iOS.
- **O que fazer.** Pedir `/source?format=xml&excluded_attributes=visible` como
  padrão e medir; avaliar também excluir `accessible` e inferir clicável só
  pelo tipo. Expor `snapshotMaxDepth` como opção avançada.
- **Esforço.** P.
- **Risco.** Baixo, mas pode mudar quais elementos são considerados clicáveis;
  cobrir com fixture de XML real.
- **Pronto quando.** Medição antes/depois num simulador com lista de 1.000+
  nós, e a suíte de hierarquia continua verde.

### L6. Replay por localizador, com espera automática e verificação de efeito

- **Problema.** O fluxo gravado repete coordenadas com `sleep` fixo. Quebra
  com outra resolução, teclado aberto, lista rolada ou rede lenta. É o tipo de
  teste que QA aprende a não confiar.
- **Evidência.** Maestro: procura o elemento até 17 s (7 s se opcional),
  espera assentar (10 leituras a cada 200 ms), refaz o toque se menos de 0,5%
  dos pixels mudou. Detox: espera ociosidade real do app. Xcode 26: gera
  `waitForExistence`. Crítica ao Maestro: tempos fixos; o Mo baile deve deixá-los
  configuráveis.
- **O que existe.** `AutomationStep` já guarda `locator_value`, `strategy` e
  coordenada; `rank_locators` já escolhe o melhor; o motor já detecta settle.
  Falta o executor usar isso.
- **O que fazer.** Executor dentro do motor (não script gerado): para cada
  passo, espera `settled`, resolve o localizador na hierarquia atual (com
  polling até timeout configurável), toca no centro do elemento encontrado,
  confirma mudança de tela pelo diff; se nada mudou, uma nova tentativa; se o
  elemento não existe, falha com screenshot e hierarquia anexados. Coordenada
  vira último recurso, explícito no relatório.
- **Esforço.** M.
- **Risco.** Médio. Replay mais lento quando o elemento some (espera o timeout).
  Localizador ambíguo precisa de erro claro.
- **Pronto quando.** Um fluxo gravado num emulador Pixel de uma resolução passa
  num emulador de outra resolução, onde o replay por coordenada falha; e a
  falha de um passo gera pacote com screenshot + hierarquia daquele instante.

### L7. Localizador honesto: unicidade real, escape e alternativas nativas

- **Problema.** `rank_locators` marca XPath sempre como único (`matches: 1`),
  não escapa aspas no XPath gerado e não oferece estratégias nativas mais
  rápidas que XPath.
- **Evidência.** Xcode 26 mostra menu de consultas alternativas por passo com
  recomendação. Appium MCP ordena accessibility id > resource id > predicado
  nativo > XPath. Documentação do WDA: XPath é o localizador mais lento porque
  exige snapshot completo.
- **O que existe.** Ranking por robustez e contagem para id, accessibility id e
  texto.
- **O que fazer.** Avaliar o XPath contra a árvore parseada e contar
  resultados; escapar aspas com `concat()`; adicionar `-ios predicate string`,
  `-ios class chain` e `-android uiautomator` (UiSelector); botão "testar
  localizador" que conta ocorrências na árvore atual e destaca no espelho.
- **Esforço.** P a M.
- **Risco.** Baixo.
- **Pronto quando.** Teste com dois botões de mesmo texto mostra o XPath por
  texto como ambíguo; texto com aspas gera XPath válido; predicado iOS gerado
  roda no Appium sem ajuste.

### L8. Snapshot consistente: quadro e árvore com o mesmo id, exportável

- **Problema.** O clique no espelho é resolvido contra "o último XML", que
  pode ser de outra tela (cache de 1,2 s, dump lento, tela mudou). Elemento
  errado vira código errado, e ninguém percebe.
- **Evidência.** agent-device invalida refs a cada comando. Maestro 2.8 pareia
  hierarquia e screenshot na falha. Layout Inspector exporta snapshot com
  imagem, árvore e atributos. Appium Inspector sofre do mesmo problema de
  imagem e árvore descasadas.
- **O que existe.** `stream.settled` já é o momento certo; `current_xml` e
  `_last_hierarchy_time` guardam o último.
- **O que fazer.** Em cada `settled`, o motor captura árvore e quadro juntos e
  os identifica com `snapshot_id`; o front envia o `snapshot_id` no
  `hierarchy.element_at` e no `codegen.record`; o motor recusa se o snapshot não
  for o vigente. Exportar e importar snapshot (arquivo com PNG + XML +
  metadados) para anexar em bug e para inspecionar sem aparelho.
- **Esforço.** M.
- **Risco.** Médio: muda contrato (fixtures) e fluxo da interface.
- **Pronto quando.** Teste de contrato prova que `element_at` com snapshot
  antigo devolve erro tipado; um snapshot exportado reabre com a árvore e a
  imagem idênticas.

### L9. Servidor MCP sobre o motor, com rede e analytics como diferencial

- **Problema.** Agentes de código já escolhem ferramenta por MCP. Sem isso, o
  Mo baile fica fora do fluxo de quem usa Claude Code, Cursor ou Codex.
- **Evidência.** mobile-mcp (8,4 mil estrelas), Appium MCP, Maestro MCP
  gratuito, agent-device, SimView, Android CLI. `mobilecli` já expõe JSON-RPC
  2.0. Nenhum oferece tráfego HTTP e eventos de analytics correlacionados ao
  toque.
- **O que existe.** O motor já é JSON-RPC 2.0 por stdio, com métodos para
  dispositivo, tela, árvore, toque, proxy e analytics, e credenciais já
  redigidas antes de sair do motor.
- **O que fazer.** Entrada `python -m mobaile.mcp` que traduz um subconjunto de
  métodos em ferramentas MCP: `devices_list`, `snapshot` (árvore compacta em
  texto com refs curtas, como mobile-mcp e agent-device), `tap(ref)`,
  `type_text`, `screenshot`, `network_since(ref)` e `analytics_since(ref)`
  (eventos entre dois snapshots), `generate_page_object`. Reaproveita os
  serviços, sem duplicar regra.
- **Esforço.** M.
- **Risco.** Médio: agente tocando em aparelho real. Mitigar com modo somente
  leitura por padrão e confirmação para `tap` fora de emulador. Manter a
  redação de credencial.
- **Pronto quando.** Claude Code conectado ao servidor lista o aparelho, lê um
  snapshot típico em menos de 2 mil tokens, toca por ref e recebe os eventos de
  rede e analytics disparados por aquele toque; suíte de contrato cobre as
  ferramentas.

### L10. Exportar Maestro YAML além do Page Object Appium

- **Problema.** Parte do público já migrou para Maestro. Hoje o Mo baile só
  gera Appium.
- **Evidência.** Maestro é gratuito, Apache-2.0, e o Studio gera YAML a partir
  de gravação. Arbigent e Radon integram com Maestro.
- **O que existe.** `AutomationStep` com texto, id e accessibility id: mapeia
  direto para `tapOn: {id: ...}` / `tapOn: "texto"` / `inputText`.
- **O que fazer.** Novo gerador `codegen_maestro.py` e opção no `codegen.save`.
- **Esforço.** P.
- **Risco.** Baixo. Diferença semântica em seletor por posição (evitar).
- **Pronto quando.** Fluxo exportado roda com `maestro test` sem edição no
  mesmo emulador em que foi gravado.

### L11. Gestos e teclas de sistema

- **Problema.** Só existe `input.tap` e `input.text` (Android). Os botões
  Voltar, Home, Girar e Screenshot do `DeviceDock` estão inertes; arrastar no
  espelho não rola a tela.
- **Evidência.** Appium Inspector tem editor de gestos e modo coordenada com
  swipe; scrcpy e Android Studio repassam gestos e teclas; WDA aceita W3C
  actions (o Mo baile já usa para toque).
- **O que existe.** `press_key` no adapter adb; payload de W3C actions em
  `ios_wda.py::tap`.
- **O que fazer.** `input.swipe`, `input.long_press`, `input.key`
  (back/home/app switch), `input.text` no iOS via WDA; `DragGesture` no
  `ScreenCanvas`; passos gravados de swipe no codegen.
- **Esforço.** P a M.
- **Risco.** Baixo.
- **Pronto quando.** Os quatro botões do dock funcionam nas duas plataformas e
  arrastar no espelho rola uma lista de verdade.

### L12. Asserções na gravação

- **Problema.** O gravador só produz clique e digitação. Teste sem asserção
  não testa nada.
- **Evidência.** Espresso Test Recorder: "texto é", "existe", "não existe".
  Xcode 26: `waitForExistence` e `wait(for:toEqual:)`. Maestro:
  `assertVisible` como espera ativa.
- **O que existe.** Seleção de elemento e codegen por passo.
- **O que fazer.** Menu de contexto no elemento: "verificar visível", "verificar
  texto igual", "verificar ausente"; gera código Appium com espera explícita e
  entra no replay de L6.
- **Esforço.** M.
- **Risco.** Baixo.
- **Pronto quando.** Fluxo com asserção falha de forma legível quando o texto
  muda e passa quando não muda.

### L13. Auditoria de acessibilidade a partir da árvore já lida

- **Problema.** QA mobile também responde por acessibilidade, e o Mo baile já
  tem a árvore em mãos.
- **Evidência.** Accessibility Inspector audita label ausente, contraste e alvo
  pequeno; o Xcode 15+ roda auditoria em XCUITest.
- **O que existe.** `UIElement` com bounds, texto, content_desc, clicável.
- **O que fazer.** Regras baratas sobre a árvore: clicável sem rótulo, alvo
  menor que 48 dp (Android) ou 44 pt (iOS), rótulos duplicados na mesma tela.
  Contraste fica para depois (exige pixel).
- **Esforço.** P a M.
- **Risco.** Baixo. Falso positivo em elemento decorativo.
- **Pronto quando.** Painel lista achados por tela com destaque no espelho,
  coberto por fixtures de XML.

### Não recomendado agora

- **Captura por IOSurface com SimulatorKit privado.** Ganho real (~20 ms), mas
  quebra com atualização do Xcode (simframe já precisou de correção para o
  Xcode 27). Revisitar depois de L1, só se o MJPEG do WDA não bastar.
- **Agente de IA próprio (visão pura).** Mercado lotado (Drizz, Midscene,
  Journeys, KaneAI). Melhor servir os agentes existentes via L9.
- **Nuvem de aparelhos.** Capital intensivo e sem diferencial; exportar para
  quem já faz.

---

## 11. Prioridade sugerida

| Ordem | Ideia | Esforço | Por quê primeiro |
|---|---|---|---|
| 1 | L1 MJPEG do WDA | P | Maior ganho visível por dia de trabalho |
| 2 | L3 passo 1 (JPEG) | P | Destrava L1 e L2 sem mudar contrato |
| 3 | L4 hierarquia Android persistente | P | Corta os 1 a 10 s de espera por dump |
| 4 | L5 `/source` enxuto | P | Idem no iOS |
| 5 | L7 localizador honesto | P-M | Código gerado correto é o produto |
| 6 | L6 replay por localizador | M | Transforma gravação em teste confiável |
| 7 | L8 snapshot consistente | M | Elimina elemento errado silencioso |
| 8 | L9 MCP com rede e analytics | M | Diferencial que ninguém tem |
| 9 | L2 H.264 do scrcpy + L3 passo 2 | G + M | Paridade de latência com scrcpy |
| 10 | L10, L11, L12, L13 | P-M | Completam a experiência |

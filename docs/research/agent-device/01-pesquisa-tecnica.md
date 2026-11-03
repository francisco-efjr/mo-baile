# agent-device (Callstack): pesquisa técnica

- **Data da pesquisa:** 2026-10-10
- **Repositório:** https://github.com/callstack/agent-device
- **Commit analisado (HEAD de `main`):** `87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2`, de 2026-10-10T08:00:40+02:00. É o commit "docs(interaction): state that click and press report dispatch, not landing (#3355)".
- **Clone local (somente leitura, nada foi executado):** `/private/tmp/claude-502/agent-device-src/repo`, com `--depth 50`.
- **Escopo:** só pesquisa factual. A comparação com o Mo baile fica para outra etapa.

## Convenções deste documento

- **Fato** é o que está no código, na documentação versionada do repositório, nas ADRs, nas releases ou na API do GitHub/npm, e vem com link.
- **Inferência** é dedução minha a partir do código, marcada com "(inferência)".
- **Não verificado** aparece quando não achei fonte.
- **Marketing** marca texto de blog da Callstack, que vale só como indício.
- Os links para o código apontam para o SHA analisado. As referências ficam no fim do documento, como `[r-...]`.
- "Doc do site" é a documentação versionada em `website/docs/docs/*.md`, publicada em https://oss.callstack.com/agent-device/docs/.

---

## Resumo executivo

1. **O que é.** CLI, servidor MCP (stdio) e API Node tipada para agentes de IA de código inspecionarem, controlarem e verificarem apps. Cobre iOS, Android, HarmonyOS, tvOS, Android TV, Vega OS, web, macOS e Linux. A licença é MIT e a linguagem principal é TypeScript sobre Node ≥ 22.12 ([README][r-readme], [package.json][r-pkg]).
2. **Modelo de processos.** O CLI e o servidor MCP são clientes finos. Um **daemon Node de longa duração por diretório de estado** é dono das sessões e encerra sozinho depois de 5 min ocioso. O daemon fala com helpers nativos persistentes:
   - um runner XCUITest via HTTP local;
   - um APK de instrumentação Android via `adb forward` + TCP;
   - uma ponte de acessibilidade em Objective-C dentro do Simulador iOS, com frames JSON prefixados por tamanho;
   - um helper Swift no macOS e AT-SPI no Linux.
3. **Árvore e refs.** A UI vem da árvore de acessibilidade, apresentada como texto compacto com refs `@e1…`. As refs são autorizadas por um **"ref frame"** com geração (`@e12~s3`) que expira antes de qualquer efeito colateral no aparelho ([ADR 0014][r-adr14]).
4. **O estado da sessão vive em memória** (`Map` no `SessionStore`). Não sobrevive a reinício do daemon e nunca é reconstruído a partir do disco ([session-store.ts][r-session-store], [ADR 0019 §5][r-adr19], [ADR 0018][r-adr18]).
5. **O que vai para disco** é observabilidade, artefatos e registros de recuperação, nunca o estado vivo. A raiz é `~/.agent-device/` (ou `AGENT_DEVICE_STATE_DIR`), com `daemon.json`, `daemon.lock`, `daemon.log` e `sessions/<sessão>/`. Cada sessão tem:
   - `events.ndjson`: diário de requisições e ações, já redigido;
   - `requests/<id>.ndjson`: diagnóstico por requisição;
   - `app.log` e `runner.log`;
   - `*.resource.json`: descritores duráveis de gravação, logs e perf;
   - `owned-processes.json`;
   - tombstones.
6. **Formatos.** Quase tudo é JSON/NDJSON com campo de versão (`version: 1`, `schemaVersion: 2`, `envelopeVersion: 1`). Scripts gravados usam o formato texto **`.ad`**: uma linha por comando, com comentários `# agent-device:target-v1 {...}` como evidência de identidade do alvo. Artefatos binários são PNG/JPEG, MP4/WebM, `.trace`, `.hprof`, `.perfetto-trace` e assim por diante. **Não há SQLite nem banco de dados** (não encontrei nenhuma dependência ou uso).
7. **Escrita atômica e concorrência são levadas a sério:**
   - arquivo temporário no mesmo diretório + `rename`, ou `link` exclusivo ("first writer wins");
   - `fsync` de arquivo e diretório para registros duráveis;
   - permissões `0600`/`0700`;
   - recusa de symlinks;
   - locks de processo em diretório com `owner.json` e identidade (pid + start time + token);
   - fila serializada por caminho para o diário de eventos.
8. **Rotação e retenção.** `events.ndjson` e `app.log` rotacionam aos 5 MB e guardam uma geração (`.1`). O diário mantém cursores absolutos estáveis através da rotação usando um sidecar `events.ndjson.window.json` com digest SHA-256 da primeira linha. Artefatos para download expiram em 15 min. **Os diretórios de sessão não são apagados automaticamente**; a doc manda inspecionar e apagar à mão.
9. **Privacidade.** A redação é centralizada: chaves sensíveis, tokens `Bearer`, query strings de URL, strings truncadas em 400 caracteres e stderr em 8.192. O diário omite conteúdo digitado. Valores de `fill` podem ser gravados como `${VAR}` (`--record-as`, [ADR 0017][r-adr17]). Há padrões de redação configuráveis para `app.log`.
10. **Saída para o agente.** Árvore enxuta (visível primeiro, fora da tela resumido) e diffs após `--settle`, com três níveis de resposta (`digest`/`default`/`full`). Artefatos pesados voltam **como caminho + metadados**, nunca inline. Um teste de "economia de saída" com baseline versionada impede regressão de bytes ([test/output-economy][r-econ]).
11. **Maturidade.** Projeto muito ativo:
    - 551 commits em `main` e 510 PRs mergeados entre 2026-09-10 e 2026-10-10;
    - 66 contribuidores, 4.954 estrelas e 33 ADRs;
    - 1.815 arquivos de teste TS e 129 de teste Swift;
    - mutation testing (Stryker), fuzz e lanes noturnas em aparelho.

---

## 1. Visão geral

### 1.1 Propósito e público

- **Fato.** Na descrição do pacote: "Mobile app automation and verification for AI coding agents. CLI, MCP server, and typed Node.js API for iOS, Android, HarmonyOS, TV, web, macOS, and Linux" ([package.json][r-pkg]).
- **Fato.** O público é agentes de código como Claude Code, Codex, Cursor, Windsurf, Cline e Goose, além de quem constrói agentes com o AI SDK da Vercel ou o Eve ([README][r-readme]). O README se posiciona contra Appium, Detox e Maestro assim: "an agent reads app state and chooses each command at run time", enquanto aquelas ferramentas servem para "write and maintain test suites". Fluxos podem ser salvos como `.ad` ou exportados como Maestro YAML ([README][r-readme]).
- **Fato.** O projeto declara inspiração explícita no `agent-browser` da Vercel ("inspect-act-verify"). A plataforma web roda o próprio `agent-browser` por baixo ([README][r-readme]).
- **Marketing.** A Callstack cita Expensify, Shopify, JPMorgan Chase e outros como usuários ([README][r-readme]).

### 1.2 Licença, versão e atividade

| Item | Valor | Fonte |
| --- | --- | --- |
| Licença | MIT | [LICENSE][r-license], [package.json][r-pkg] |
| Versão em `main` | `0.21.25-dev` | [package.json][r-pkg] |
| Última release | `v0.21.24`, publicada em 2026-10-09T19:15Z | `gh release list` (2026-10-10), [releases][r-releases] |
| npm | `agent-device@0.21.24`, unpacked 5,1 MB | `npm view agent-device` (2026-10-10), [npm][r-npm] |
| Criação do repo | 2026-01-30 | API do GitHub (2026-10-10) |
| Estrelas / forks / issues+PRs abertos | 4.954 / 330 / 103 | API do GitHub (2026-10-10) |
| Contribuidores | 66 | API do GitHub `contributors` (2026-10-10) |
| Ritmo | 551 commits em `main` e 510 PRs mergeados de 2026-09-10 a 2026-10-10. Releases saem quase diariamente (0.21.17 a 0.21.24 entre 30/09 e 09/10). | API do GitHub |
| CHANGELOG | Não há arquivo `CHANGELOG.md` na raiz. As notas ficam nas GitHub Releases, geradas por PR. | árvore do repo, [releases][r-releases] |

### 1.3 Stack

- **Linguagens (fato, contagem no clone):**
  - TypeScript: cerca de 736 mil linhas, incluindo testes;
  - Swift: cerca de 35 mil (runner XCUITest, helper macOS, apresentação de snapshot);
  - Objective-C: cerca de 4,5 mil (ponte AX do Simulador e helper de dobra);
  - Kotlin/Java: 21 arquivos (APKs Android);
  - Python: `linux/atspi-dump.py`.
- **Runtime (fato):** Node ≥ 22.12, ESM. A web exige Node 24 ([package.json][r-pkg], [README][r-readme]).
- **Dependências de runtime (fato):** o `package.json` publicado **não tem `dependencies`**. Tudo é empacotado com `tsdown` a partir de um monorepo pnpm com cerca de 27 pacotes internos `@agent-device/*`. A única peer opcional é `ai` (^6 ou ^7) ([package.json][r-pkg]). Ferramentas de dev:
  - `vitest`, `oxlint`/`oxfmt` e `typescript`;
  - `@stryker-mutator/*`, `fast-check` e `fallow`;
  - `pngjs`, `jpeg-js`, `yaml`, `yauzl` e `tar-stream`, que são vendorizados no bundle (inferência pelo campo `files` e pela ausência de deps).
- **Ferramentas externas exigidas no host:**
  - Xcode, com `xcodebuild`, `simctl`, `devicectl` e `clang`;
  - Android SDK (`adb`), HDC (HarmonyOS), Vega CLI/VDA;
  - AT-SPI no Linux, AVFoundation para contact sheets ([README][r-readme], [doc commands][r-doc-commands]).

---

## 2. Arquitetura

### 2.1 Modelo de processos

```
 agente de IA
   ├─ CLI  `agent-device <cmd>` ─────────────┐
   ├─ MCP  `agent-device mcp` (stdio) ───────┤  cliente do daemon (mesmo caminho de execução)
   └─ Node `createAgentDeviceClient()` ──────┘
                     │  TCP loopback NDJSON (modo "socket", padrão)
                     │  ou HTTP JSON-RPC `POST /rpc` (modo "http"/"dual"), token por requisição
                     ▼
        DAEMON Node (um por AGENT_DEVICE_STATE_DIR)
         ├─ SessionStore (memória) + diário em disco
         ├─ registro de comandos → runtimes de plataforma (packages/platform-*)
         └─ helpers persistentes por aparelho:
             ├─ iOS/tvOS/macOS: runner XCUITest (HTTP `POST /command` em 127.0.0.1:<porta>)
             ├─ iOS Simulator: ponte AX em ObjC dentro do simulador (frames JSON com prefixo de tamanho)
             ├─ Android: APK de instrumentação (UiAutomation) em `adb forward` + TCP; IME de teste
             ├─ macOS: helper Swift; Linux: AT-SPI (python); HarmonyOS: hdc/uitest; Vega: VDA
             └─ web: `agent-browser`
```

- **Fato.** A frase do repositório é "A long-lived daemon owns sessions; registry-derived commands route to platform runtimes" ([AGENTS.md][r-agents]).
- **Fato.** O cliente acha o daemon lendo `daemon.json` no diretório de estado, e esse registro é a única resposta para "quem serve este state dir" ([daemon-registration.ts][r-daemon-reg]). Se não há daemon, o cliente lança um em background (`runCmdDetachedMonitored` em `src/daemon-client/`, inferência pelos mocks nos testes de [daemon-client-lifecycle][r-daemon-client-lifecycle]).
- **Fato.** O cliente reaproveita um daemon só se a versão e o código forem os mesmos. A comparação usa tamanho e mtime dos arquivos, não o conteúdo. Um cliente mais antigo se recusa a substituir um daemon mais novo ([doc security-trust][r-doc-security]).
- **Fato.** O daemon sai sozinho depois de 5 min ocioso, quando não tem sessões, requisições em voo nem gravação ativa. `AGENT_DEVICE_DAEMON_IDLE_TIMEOUT_MS` ajusta o tempo e `0` desliga ([cli-help.ts:534][r-cli-help], [daemon-idle-reap.ts:21][r-idle-reap]).
- **Fato.** Cada `AGENT_DEVICE_STATE_DIR` roda o seu próprio daemon. Num checkout de código-fonte, o state dir padrão vira `~/.agent-device/dev/<slug>-<sha1(realpath)[0:12]>`, isolado por worktree ([daemon-resolution.ts:56-70][r-daemon-resolution]).

### 2.2 Transporte e protocolos

| Enlace | Protocolo | Fonte |
| --- | --- | --- |
| CLI/Node para o daemon, modo "socket" (padrão) | TCP em `127.0.0.1:<porta efêmera>`, uma requisição JSON por linha e uma resposta JSON por linha. Se a requisição pede progresso, eventos de progresso NDJSON são multiplexados antes da resposta. Desconectar cancela só as requisições daquela conexão. O campo `internal` vindo do cliente é descartado para impedir falsificação. | [transport.ts:26-153][r-transport] |
| CLI/Node para o daemon, modo "http"/"dual" | HTTP com `GET /health` (sem autenticação; devolve versão, `rpcProtocolVersion` e instance id) e `POST /rpc` (JSON-RPC, método `agent_device.command`), além de `/upload` e `/artifacts/*`. Há cabeçalhos condicionais de instance id contra daemon trocado (HTTP 409). | [ADR 0006][r-adr06], [http-server.ts][r-http-server], [doc sessions][r-doc-sessions] |
| Autenticação | Token de 24 bytes aleatórios, gerado a cada start e gravado em `daemon.json` com `0600`. Bind só em loopback. Um hook de auth customizável (`AGENT_DEVICE_HTTP_AUTH_HOOK`) atende cenários remotos. | [daemon-runtime.ts:349][r-daemon-runtime], [daemon-registration-owner.ts:92][r-reg-owner], [doc security-trust][r-doc-security] |
| Daemon para o runner Apple | HTTP+JSON em `POST /command` no listener local do runner. Envelope `{ ok, data?, error? }` e `commandId` para recuperação via `status`. | [RUNNER_PROTOCOL.md][r-runner-proto] |
| Daemon para a ponte AX do Simulador | Frames com `uint32` big-endian de tamanho + JSON UTF-8. O host é dono de identidade, limites e deadlines; o convidado devolve a árvore crua limitada. | [snapshot-bridge/README][r-bridge-readme] |
| Daemon para o helper Android | `adb shell am instrument` em modo one-shot, ou sessão persistente (`-e sessionPort`) num servidor TCP em `127.0.0.1:<porta>` alcançado por `adb forward`, com comandos `snapshot <id>`, `viewport <id>` e `gesture <id> <base64>`. O snapshot volta em XML. | [android snapshot-helper README][r-android-helper] |
| MCP | JSON-RPC 2.0 delimitado por linha em stdin/stdout. O servidor processa mensagens em fila serial e aceita batch. | [src/mcp/server.ts][r-mcp-server] |
| Proxy remoto | Pacote `@agent-device/proxy`: "Transport-neutral authenticating proxy in front of an agent-device daemon". `agent-device proxy` não repassa `/admin/*`. | [packages/proxy/package.json][r-pkg-proxy], [doc security-trust][r-doc-security] |

### 2.3 Ciclo de vida da sessão

- **Fato.** A sessão é o "estado do daemon para um alvo selecionado e seu app/superfície aberto" ([CONTEXT.md][r-context]). Ela começa no `open` e termina no `close`, no reap por ociosidade (opt-in, #2833), no fim de lease remota ou no desligamento do daemon ([session-store.ts][r-session-store]).
- **Fato. Endereçamento:**
  - Sem `--session`, a sessão implícita é escopada ao **worktree git** (ou cwd) **e à plataforma**.
  - A chave interna é `cwd:<sha256(raiz)[0:16]>:<nome>`, onde o nome é `default` ou a plataforma ([session-routing.ts:18,306-314][r-session-routing], [doc sessions][r-doc-sessions]).
  - Com `--session <nome>`, a sessão é nomeada e compartilhada entre worktrees.
  - Também existe escopo `tenant`, para uso remoto multi-inquilino ([session-scope.ts][r-session-scope]).
- **Fato.** A exclusão entre agentes paralelos usa **device claims** globais do host, arquivos em `~/.agent-device/device-claims/`. Um `open` num aparelho já reivindicado falha com `DEVICE_IN_USE` ou espera com `--wait` ([doc sessions][r-doc-sessions], [device-claim-store.ts][r-claim-store]).
- **Fato.** Comandos mutantes na mesma sessão devem ser seriais. O daemon serializa por chave de sessão e aparelho com locks em memória (cadeias de `Promise`) ([request-execution-locks.ts][r-exec-locks], [doc sessions][r-doc-sessions]).

### 2.4 Integração com agentes de IA

- **MCP (fato).** `agent-device mcp` expõe os comandos instalados como *tools* estruturadas, "over the same execution path as the CLI". O nome de registro é `io.github.callstack/agent-device` ([README][r-readme], [doc agent-setup][r-doc-agent-setup]). Detalhes:
  - No `initialize`, o servidor devolve `instructions` curtas com o fluxo `open → snapshot -i → agir com settle → verificar → close`.
  - Uma tool `help` devolve os guias da CLI.
  - Erros saem como `isError: true`.
  - O servidor nunca expõe shell genérico ([doc agent-setup][r-doc-agent-setup]).
  - O servidor MCP mantém em memória um mapa de **ref pins** por escopo (state dir + sessão) e fixa automaticamente refs simples na geração que as emitiu ([tool-ref-pins.ts][r-mcp-pins]).
- **Skills (fato).** Diretório `skills/` com `agent-device`, `ios-simulator`, `android-emulator` e `dogfood`, cada um um `SKILL.md` curto. A regra do repo é "Skills stay minimal routing cards". A instalação é `npx skills add callstack/agent-device` ([skills/agent-device/SKILL.md][r-skill], [AGENTS.md][r-agents]).
- **Node API (fato).** `createAgentDeviceClient({ session })` dá acesso tipado aos mesmos comandos, com subpaths como `agent-device/ai-sdk` e `agent-device/plugins` ([README][r-readme], [package.json][r-pkg]).
- **Prompts (fato).** A doc sugere uma "regra de projeto" textual para o agente: não sondar com `--help`/`devices` antes, abrir o app direto e seguir o snapshot inicial ([doc agent-setup][r-doc-agent-setup]).

---

## 3. Plataformas

### 3.1 Matriz de mecanismos

| Plataforma | Hierarquia / snapshot | Toque / digitação / gestos | Tela | Fonte |
| --- | --- | --- | --- | --- |
| iOS Simulator | Ponte AX do host, um leitor ObjC privado compilado com `clang` no primeiro uso e rodando no simulador. Usa `XCTAccessibilityFramework`/`userTestingSnapshotForElement`, com forma fixada no idb v1.5.2. Se falha, cai para o XCTest recursivo, e o circuito é desligado para aquela "geração" do app. | Runner XCUITest (HTTP) | `simctl io … screenshot`; vídeo por `simctl io … recordVideo` | [ADR 0004][r-adr04], [bridge README][r-bridge-readme], [doc commands][r-doc-commands], [screenshot.ts][r-apple-screenshot] |
| iOS físico | XCTest recursivo no runner. Sem backend semântico alternativo. | Runner XCUITest, que precisa de assinatura | `devicectl device capture screenshot`; vídeo por frames repetidos de `XCUIScreen.main.screenshot()` (15 fps por padrão, best-effort) | [physical-device-screenshot.ts][r-apple-phys-shot], [doc commands][r-doc-commands] |
| tvOS / macOS | Runner XCUITest. No macOS há também um helper Swift e um backend nativo sem XCTest ([ADR 0031][r-adr31]). | Runner, helper ou ações de acessibilidade | idem | [README][r-readme] |
| Android | APK de instrumentação com `UiAutomation.getWindows()` (todas as janelas interativas, inclusive teclado e overlays). Sessão persistente por TCP, com one-shot como fallback. Nunca usa `uiautomator dump`. | `adb shell input tap/text`; gestos planejados pelo mesmo APK (protocolo `android-touch-plan-v1`); IME de teste próprio para texto não-ASCII | `adb exec-out screencap -p`; vídeo `adb shell screenrecord` (limite de 180 s, em pedaços) | [ADR 0002][r-adr02], [android helper README][r-android-helper], [input-actions.ts][r-android-input], [android screenshot.ts][r-android-screenshot], [doc known-limitations][r-doc-limits] |
| HarmonyOS | HDC + ArkUI `uitest` (subconjunto de comandos) | idem | JPEG servido pelo aparelho | [README][r-readme], [doc commands][r-doc-commands] |
| Vega OS (TV) | Vega CLI/VDA, só no Vega Virtual Device | controle remoto | — | [README][r-readme] |
| Web | `agent-browser`, cujas refs são preservadas | `agent-browser` | WebM | [README][r-readme], [snapshot.ts:300-310][r-kernel-snapshot] |
| Linux | AT-SPI (`linux/atspi-dump.py`) | — | — | [README][r-readme] |
| Nuvens | BrowserStack, AWS Device Farm e TestMu AI via WebDriver; Limrun direto | idem | servidor do provedor | [README][r-readme] |

- **Fato.** `agent-device capabilities --platform <p>` informa o que cada alvo suporta ([README][r-readme]).

### 3.2 Snapshot e refs

- **Projeções (fato).** `raw` ⊇ `regular` ⊇ `interactive` (`snapshot -i`) ([CONTEXT.md][r-context]).
  - A apresentação "visible-first" corta o que está fora da tela e o resume, por exemplo `[off-screen below] 3 interactive items: "Privacy", …`.
  - Tudo passa por um único interpretador de visibilidade (o "clip fold") para todos os backends ([doc snapshots][r-doc-snapshots], [ADR 0004][r-adr04]).
- **Saída em texto (fato, exemplo da doc):**

  ```
  Snapshot: 9 visible nodes (14 total)
  @e1 [application] "Contacts"
    @e2 [window]
  ...
  [off-screen below] 2 interactive items: "All Contacts", "New List"
  ```

- **Nó JSON (fato).** Campos de `SnapshotNode`:
  - identidade e papel: `ref`, `type` (classe nativa), `kind` (papel neutro), `role` (só iOS);
  - textos: `label`, `value`, `identifier`, `contentDescription`, `placeholder`;
  - geometria: `rect`;
  - estados: `enabled`, `selected`, `checked`, `focused`, `editable`, `password`, `hittable`, `visibleToUser`;
  - estrutura: `depth`, `parentIndex`;
  - dicas de conteúdo oculto: `hiddenContentAbove/Below`;
  - opt-in: `actions`.

  O estado do snapshot (`SnapshotState`) carrega `nodes`, `createdAt`, `truncated`, `snapshotQuality` e `comparisonSafe` ([kernel/snapshot.ts:255-310,664][r-kernel-snapshot]).
- **Cunhagem de refs (fato).** `attachRefs` numera de forma densa por posição (`e${idx + 1}`), a não ser que o backend já traga uma ref, como no web ([kernel/snapshot.ts:767-772][r-kernel-snapshot]).

  ```ts
  export function attachRefs(nodes: RawSnapshotNode[]): SnapshotNode[] {
    return nodes.map((node, idx) => ({ ...node, ref: node.ref ?? `e${idx + 1}`, kind: formatRole(node.type ?? 'Element') }));
  }
  ```

- **Gerações e "ref frame" (fato):**
  - Cada substituição da árvore incrementa `snapshotGeneration`. A primeira de cada sessão começa num número aleatório de 6 dígitos (`randomInt(100_000, 1_000_000)`), para que um pin de uma vida anterior raramente colida ([session-snapshot.ts:76][r-session-snapshot]).
  - A ref pode ser fixada como `@e12~s3`. Toda folha mutante expira o frame **logo antes** do efeito no aparelho, mesmo que a operação falhe depois.
  - Uma ref num frame expirado é rejeitada com razões tipadas, nesta ordem: `ref_frame_expired`, `ref_generation_mismatch`, `plain_ref_requires_complete_frame`, `ref_not_issued` ([ADR 0014][r-adr14]).
  - Leituras continuam permitidas, com aviso ([session-snapshot.ts][r-session-snapshot]).
- **Limites (fato):**
  - helper Android e ponte AX: 5.000 nós, com `truncated: true` e aviso;
  - runner Apple: não devolve árvore parcial; acima de 50.000 nós (5.000 com `--raw`) falha com dica ([doc snapshots][r-doc-snapshots]).
- **Qualidade (fato).** Snapshot esparso ou degradado vem com um "quality verdict" estruturado em vez de fingir tela vazia ([ADR 0004][r-adr04]).

### 3.3 Ações e sincronização

- **Fato.** `click`/`press` informam **despacho, não chegada**. Para confirmar, a doc indica três caminhos ([doc commands][r-doc-commands], issue [#3335][r-i3335]):
  - `--verify`, que devolve `changedFromBefore`;
  - `--settle`, que espera a UI ficar quieta e devolve um diff contra a árvore anterior, emitindo refs parciais novas;
  - `wait <seletor>`.
- **Fato.** `wait` aceita várias formas:
  - duração;
  - `text`;
  - `@ref`, que é resolvida para texto e não rastreia identidade;
  - seletor, por polling de snapshot;
  - `absent <seletor>`, de ausência estrita.

  Falhas trazem `details.reason` tipado e a evidência de cada poll, guardando os 5 primeiros e os 25 últimos ([doc commands][r-doc-commands]).
- **Fato.** Seletores usam sintaxe `id="…"`, `label="…"` e `role="…"` e podem ser encadeados com `||`. Depois de resolver um `@ref`, o daemon grava a **cadeia de seletores** para o replay ([AGENTS.md][r-agents], [session-script-writer.ts][r-script-writer]).
- **Fato.** No Android, logo após navegação ou submit, a captura repete árvores que parecem velhas por uma janela curta. Um snapshot sem filtros repetido sem mudança volta como "acknowledgement" curto em vez da árvore ([doc snapshots][r-doc-snapshots]).

---

## 4. Persistência e armazenamento dos dados coletados (foco principal)

### 4.1 Princípio arquitetural: memória é a verdade, disco é evidência

- **Fato.** O `SessionStore` guarda as sessões num `Map<string, SessionEntry>` em memória ([session-store.ts:50-58][r-session-store]):

  ```ts
  export class SessionStore {
    private readonly sessions = new Map<string, SessionEntry>();
  ```

- **Fato.** `SessionState` contém dispositivo, app, último snapshot, `snapshotGeneration`, `refFrame`, `actions: SessionAction[]` (a gravação do script), handles vivos de log, gravação e perf, `lease`, `deviceClaim` e outros ([session-state.ts:121-278][r-session-state]). O próprio arquivo avisa: "Nothing here belongs on the wire."
- **Fato.** A ADR 0018 é explícita: "The journal is an observability spine, **not** a source of truth: `session.actions` and all other session state remain owned by their stores. No state is ever rebuilt from journal events" ([ADR 0018][r-adr18]).
- **Fato.** A ADR 0019 §5 diz: "Reattachment does not rehydrate `SessionState` or change `SESSION_NOT_FOUND` policy" ([ADR 0019][r-adr19]). A doc de segurança completa: "Holds and leases live in memory; neither survives a daemon restart" ([doc security-trust][r-doc-security]).
- **Consequência (inferência, sustentada pelo código acima).** Se o daemon morre, perde sessões, refs, a gravação `.ad` ainda não publicada e o baseline de `diff snapshot`. O que fica no disco:
  - diários e logs;
  - descritores de recursos duráveis, que permitem **finalizar ou limpar** gravações e logs órfãos;
  - registros de processos e claims, que permitem **recuperar a posse** de aparelhos e matar processos órfãos.

### 4.2 Mapa de diretórios

Raiz do estado do daemon. Por padrão é `~/.agent-device/` em instalações npm, `~/.agent-device/dev/<slug>-<hash>/` em checkout de fonte, ou `AGENT_DEVICE_STATE_DIR` ([daemon-resolution.ts:33-70][r-daemon-resolution]).

```
<stateDir>/                                  (~/.agent-device por padrão)
├─ daemon.json            registro do daemon (porta(s), token, pid, start time, versão, policyDigest) – 0600
├─ daemon.lock/           lock de registro (diretório + owner.json; protocolo "hardened", ADR 0030)
├─ daemon.log             log do ciclo de vida do daemon (truncado a cada publicação)
├─ daemon-shutdown.json   relatório do último desligamento (claims e releases de provedores) – 0600
├─ owned-processes.json   processos filhos de escopo daemon (v1) – 0600
├─ allocations/<sha(requester)>/<sha(attempt)>.json   operações de alocação gerenciada (ADR 0021) – dir 0700
├─ expired-provider-leases.json   releases pendentes de leases de provedores – 0600
├─ remote-connections/<sessão>.json, .active-session.json   perfis de conexão remota – 0600
├─ remote-diagnostics/<sessão>/requests/<id>.ndjson         cópia local de diagnóstico de daemon remoto
├─ metro-sessions/<sessão>.json                             dicas de runtime Metro
├─ auth/cli-session.json                                    sessão de login na nuvem – 0600
├─ update-check.json                                        cache do aviso de versão nova
└─ sessions/
   ├─ <sessão>-<ISO-ts>.ad            script gravado (padrão quando --save-script sem caminho)
   ├─ <sessão>-<ISO-ts>.trace.log     trace (padrão de `trace start` sem caminho)
   └─ <sessão sanitizada>/            ex.: cwd_<hash16>_ios, my-session
      ├─ events.ndjson                diário da sessão (v1)
      ├─ events.ndjson.1              geração rotacionada
      ├─ events.ndjson.window.json    sidecar de janela de cursores (v2)
      ├─ requests/<requestId>.ndjson  diagnóstico por requisição
      ├─ runner.log                   saída do runner Apple / xcodebuild
      ├─ app.log, app.log.1           logs do app (logs start)
      ├─ app-log.resource.json        descritor durável do stream de log
      ├─ screen-recording.resource.json  descritor durável da gravação de tela
      ├─ perf-capture.resource.json   descritor durável de profiler nativo
      ├─ audio-probe.resource.json    descritor durável de sonda de áudio
      ├─ owned-processes.json         processos filhos de escopo sessão
      ├─ repair-tombstone.json        marcador de sessão de reparo encerrada
      └─ idle-expiry.json             marcador de expiração por ociosidade
```

Fontes do mapa:

- [daemon-resolution.ts][r-daemon-resolution]
- [session-artifact-paths.ts][r-artifact-paths]
- [session-event-log.ts:20][r-event-log]
- [session-event-log-window.ts][r-event-window]
- [owned-process-record.ts:10][r-owned-proc]
- [screen-recording-resource-store.ts][r-rec-store]
- [app-log-resource-store.ts][r-applog-store]
- [perf-capture-resource-store.ts][r-perf-store]
- [audio-probe-resource-store.ts][r-audio-store]
- [session-repair-tombstone.ts:29-31][r-repair-tomb]
- [session-idle-tombstone.ts:24][r-idle-tomb]
- [session-store.ts:433-437][r-session-store]
- [session-script-writer.ts:160-168][r-script-writer]
- [daemon-shutdown-report.ts:5][r-shutdown-report]
- [provider-lease-expiry.ts:14][r-provider-expiry]
- [remote-connection-state.ts:351-361][r-remote-conn]
- [metro-session-hints.ts:18][r-metro-hints]
- [auth-session.ts:317][r-auth]
- [update-check.ts:11][r-update-check]
- [store-creation.ts:31-35][r-alloc-store]
- [doc sessions][r-doc-sessions]

O nome de diretório da sessão vem de `safeSessionName`, que troca todo caractere fora de `[a-zA-Z0-9._-]` por `_`. A codificação é muitos-para-um, e o código trata colisões comparando o campo `owner` dos marcadores ([session-paths.ts][r-session-paths], [session-store.ts:384-395][r-session-store]).

**Estado global do host, fora do state dir:**

```
~/.agent-device/
├─ config.json                     configuração do usuário (ou <AGENT_DEVICE_HOME>/config.json)
├─ plugins/<instalação>/…          projetos npm de plugins + plugins.lock
├─ device-claims/<sha256(deviceKey)>.json   (+ <arquivo>.lock/)   posse global de aparelhos – 0600/0700
├─ apple-runner/derived/<pasta>/<chave>/    cache do runner XCUITest compilado
├─ apple-runner/leases/                      leases dos processos runner (v1)
├─ snapshot-source/                          binário da ponte AX compilado, por hash de fonte + toolchain
├─ fold-helper/                              helper de dobra (Fold.m) compilado
├─ macos-helper/current/manifest.json        helper macOS instalado
└─ logs/<sessão>/<AAAA-MM-DD>/<ts>-<diagnosticId>.ndjson   diagnósticos sem sessão (fallback)
<projeto>/.agent-device/test-artifacts/<suite-id>/…   artefatos de `test` (relativo ao cwd)
<projeto>/.agent-device/metro.log                     log do companion Metro
$TMPDIR/agent-device-*                                 temporários (screenshots sem caminho, downloads, uploads…)
```

Fontes:

- [cli-config.ts:60-64][r-cli-config]
- [doc plugins][r-doc-plugins]
- [device-claim-paths.ts:28-37][r-claim-paths]
- [runner-cache-metadata.ts:22][r-runner-cache]
- [runner-lease.ts:436-440][r-runner-lease]
- [snapshot-source/cache.ts:53-54][r-snapshot-cache]
- [fold-helper-cache.ts:62][r-fold-cache]
- [macos helper.ts:82-88][r-macos-helper]
- [diagnostics.ts:245][r-diagnostics]
- [session-test-artifacts.ts:14][r-test-artifacts]
- [client-metro.ts:688][r-client-metro]

### 4.3 Inventário de dados coletados

| Dado | Onde fica | Formato | Sobrevive a reinício do daemon? | Fonte |
| --- | --- | --- | --- | --- |
| Árvore do último snapshot e baseline de diff | `SessionState.snapshot`, `lastComparisonSafeSnapshot` | objeto em memória | Não | [session-state.ts][r-session-state], [session-snapshot.ts][r-session-snapshot] |
| Ref frame, geração e pins MCP | `SessionState.refFrame`; mapa no processo MCP | memória | Não. A proteção entre vidas é probabilística, pela semente aleatória. | [ADR 0014][r-adr14], [tool-ref-pins.ts][r-mcp-pins] |
| Ações gravadas (base do `.ad`) | `SessionState.actions` | memória até publicar o `.ad` | Não, salvo os tombstones de reparo | [session-action-recorder.ts:57-101][r-action-recorder] |
| Linha do tempo de requisições e ações | `sessions/<s>/events.ndjson` | NDJSON v1, redigido | Sim | [session-event-log.ts][r-event-log] |
| Diagnóstico detalhado por requisição | `sessions/<s>/requests/<id>.ndjson`, ou `~/.agent-device/logs/...` sem sessão | NDJSON | Sim | [session-artifact-paths.ts][r-artifact-paths], [diagnostics.ts][r-diagnostics] |
| Logs do app (stdout/stderr, Unified Logging, logcat) | `sessions/<s>/app.log` (+`.1`) | texto, com marcadores de `logs mark` | Sim | [app-log-files.ts][r-applog-files], [doc commands][r-doc-commands] |
| Rede | Não há proxy nem interceptação TLS. `network dump` faz parse dos HTTP(s) presentes em `app.log` (no máximo 4.000 linhas, 200 entradas, campos de 2.048 caracteres). Na web, usa o histórico do `agent-browser`. | derivado | — | [doc commands][r-doc-commands] |
| Saída do runner/xcodebuild | `sessions/<s>/runner.log`; runner sem sessão em `$TMPDIR/agent-device/apple-runner/logs/<device>.log` | texto | Sim | [session-artifact-paths.ts][r-artifact-paths], [runner-io.ts:140][r-runner-io] |
| Screenshot | caminho do usuário, ou temporário `$TMPDIR/agent-device-screenshot-*/screenshot.png` | PNG (JPEG no HarmonyOS) | arquivo sim | [screenshot-runtime.ts:384-420][r-screenshot-runtime], [io.ts:117-150][r-io] |
| Vídeo | caminho do usuário, `.mp4`/`.webm`, mais um sidecar de telemetria de gestos quando há overlay de toques | MP4/WebM + JSON | Recuperável via `screen-recording.resource.json` (Android: só os pedaços listados no manifesto) | [doc commands][r-doc-commands], [ADR 0024][r-adr24] |
| Contact sheet | `<gravação>.contact-sheet.png` | PNG | — | [doc commands][r-doc-commands] |
| Trace | `--out` ou `sessions/<s>-<ts>.trace.log` | texto, anexado pelas ferramentas de plataforma (inferência pelo `traceLogPath` repassado aos handlers) | Arquivo sim; `session.trace` não | [trace-runtime.ts][r-trace-runtime] |
| Perf (xctrace, simpleperf, perfetto, hprof, memgraph) | `--out` | binários nativos + relatório JSON compacto | Recuperável via `perf-capture.resource.json` | [doc debugging-profiling][r-doc-debug] |
| Scripts gravados | `--save-script <path>` ou `sessions/<s>-<ts>.ad` | texto `.ad` | Sim, só depois de publicado | [session-script-writer.ts][r-script-writer] |
| Artefatos de suíte `test` | `.agent-device/test-artifacts/<suite>/<slug>/attempt-N/` | `replay.ad`, `result.txt`, `failure.txt`, `replay-timing.ndjson` e cópias | Sim | [session-test-artifacts.ts][r-test-artifacts], [session-test-attempt.ts:144][r-test-attempt], [doc replay-e2e][r-doc-replay] |
| Posse de aparelho | `~/.agent-device/device-claims/*.json` | JSON `schemaVersion: 2` (3 se for do alocador) | Sim; o daemon reconcilia no start | [device-claim-record.ts][r-claim-record], [daemon-runtime.ts:722-727][r-daemon-runtime] |
| Holds de controle humano e leases | memória | — | Não | [doc security-trust][r-doc-security] |

### 4.4 O diário da sessão: `events.ndjson`

**Esquema (fato,** [session-event-log.ts:20-38][r-event-log]**):**

```ts
const SESSION_EVENT_LOG_FILENAME = 'events.ndjson';
const EVENT_LOG_VERSION = 1;
export type SessionEventLogEntry = {
  version: 1; ts: string; session: string;
  kind: 'request.started' | 'request.finished' | 'action.recorded';
  requestId?: string; command?: string; status?: 'ok' | 'error';
  summary?: string; details?: Record<string, unknown>;
};
```

Exemplo de linha. É **ilustrativo**, montado a partir dos construtores `buildRequestFinishedEvent` e `buildActionDetails`, e não foi capturado de execução:

```json
{"version":1,"ts":"2026-10-10T12:00:00.000Z","session":"cwd:ab12…:ios","kind":"request.finished","requestId":"9f…","command":"press","status":"ok","summary":"Tapped @e7","details":{"durationMs":412}}
{"version":1,"ts":"…","session":"…","kind":"action.recorded","requestId":"9f…","command":"press","summary":"Tapped @e7","details":{"command":"press","ref":"@e7","targetLabel":"@e7","selectorChainLength":2}}
```

**Escrita (fato):**

- Cada `appendSessionEvent` passa o objeto por `redactDiagnosticData` e o enfileira numa **fila serializada por caminho** (`Map<path, Promise>`). Cada etapa faz `mkdir -p`, roda a rotação se preciso e então `fs.promises.appendFile` ([session-event-log.ts:66-112][r-event-log]).
- Falhas viram diagnóstico `session_event_log_write_failed` e **não** quebram a requisição. É fire-and-forget; um teste chegou a correr contra essa escrita assíncrona (issue [#1998][r-i1998]).
- `flushEvents()` aguarda as escritas pendentes ([session-store.ts:206-210][r-session-store]).

**Quem escreve (fato).** Há três pontos no ciclo da requisição (`request.started`/`finished`) mais `SessionStore.recordAction`, que espelha cada `session.actions.push` como `action.recorded`. Também há escrita fora de requisição: o `close` sintético registrado no teardown de uma sessão de reparo ([ADR 0018, Contexto][r-adr18], [session-store.ts:189-197,281-292][r-session-store]). O comando `events` não grava a si mesmo (`shouldRecordEventForRequest`).

**Conteúdo (fato, doc).** O diário omite conteúdo digitado:

> `events.ndjson` leaves out user-entered content. It keeps command names, status, durations, bounded device/app inventory previews, lifecycle outcomes, artifact basenames, and structural action details such as scroll distance/direction, safe refs, and coordinates. User-entered text, clipboard contents, push/event payloads, selector values, free-form flags/messages/paths, and raw unknown command arguments are omitted or replaced with content-free placeholders.

([doc sessions][r-doc-sessions]). O código confirma que o "rótulo do alvo" é só `@ref`, coordenadas `(x, y)` ou nome do app, nunca o texto do elemento ([session-event-action.ts:128-150][r-event-action]). `--no-record` suprime `action.recorded`.

**Rotação com cursores estáveis (fato,** [session-event-log-window.ts][r-event-window]**):**

- O limite padrão é **5 MiB** (`AGENT_DEVICE_EVENT_LOG_MAX_BYTES`, só inteiros; `5MB` é ignorado). Acima dele, `events.ndjson` é renomeado para `events.ndjson.1` (`RETAINED_GENERATIONS = 2`: a ativa + uma rotacionada).
- O cursor do comando `events` é um **índice absoluto de linha desde a criação do log**. Para não renumerar cursores na rotação, um sidecar `events.ndjson.window.json` (`version: 2`) registra por geração `{ firstLineIndex, lineCount, firstLineDigest }`. O digest é `sha256(primeira linha)[0:32]` ([session-event-log-lines.ts:20-21][r-event-lines]).
- **Ordem crash-safe.** O sidecar é escrito antes do rename destrutivo, via temp `.<pid>.tmp` + `rename`. Se uma rotação gravou o registro e morreu antes do rename, a próxima reaproveita o registro de mesmo digest em vez de contar a geração duas vezes.
- **Leitura verificada.** O leitor identifica cada arquivo pelo digest e confere a contagem de linhas e a contiguidade. Ele relê o sidecar antes e depois, por inode, tamanho e mtime, e tenta 3 vezes para descartar leituras "rasgadas". Quando não consegue provar a janela, falha tipado com `EVENT_LOG_WINDOW_UNVERIFIED`, em vez de adivinhar offset. Um cursor anterior à janela falha com `EVENT_LOG_CURSOR_EXPIRED` e `earliestCursor`.
- O arquivo de log não pode ser symlink.
- **Paginação.** `limit` padrão de 100 e máximo de 500 ([session-event-log.ts:22-23][r-event-log]). O cliente Node lê por `client.observability.events({ cursor, limit })` ([doc client-api][r-doc-client-api]).

### 4.5 Diagnóstico por requisição

- **Fato.** Cada requisição roda num escopo `AsyncLocalStorage` com `requestId` (8 bytes hex) e `diagnosticId` (`<base36(ts)>-<4 bytes hex>`). `emitDiagnostic` acumula eventos `{ ts, level, phase, session, requestId, command, durationMs, data }` em memória, com `data` já redigido ([diagnostics.ts:1-170][r-diagnostics]).
- **Quando vai para disco (fato).**
  - Em **erro**, sempre, por `flushDiagnosticsToSessionFile({ force: true })`.
  - Em sucesso, só com `--debug` ou `flushOnSuccess`. No modo debug, cada evento é anexado ao vivo ([request-finalization.ts:21-75][r-req-final], [diagnostics.ts:154-168][r-diagnostics]).
  - O destino é `sessions/<s>/requests/<requestId>.ndjson`. Sem `logPath` de sessão, vai para `~/.agent-device/logs/<sessão>/<AAAA-MM-DD>/<ts>-<diagnosticId>.ndjson` ([diagnostics.ts:240-255][r-diagnostics]).
  - O erro devolvido ao agente carrega `diagnosticId` e `logPath`.
- **Fato.** Valores literais declarados como sensíveis (por exemplo um `fill` com `--record-as`) são registrados no escopo e substituídos por `[REDACTED]` também no flush, do mais longo para o mais curto ([diagnostics.ts:100-108,265-285][r-diagnostics]).
- **Fato.** Com daemon remoto, o cliente guarda a própria cópia em `<stateDir>/remote-diagnostics/<sessão>/requests/<id>.ndjson`, para o CI arquivar ([session-artifact-paths.ts:39-50][r-artifact-paths], [doc debugging-profiling][r-doc-debug]).
- **Fato.** `daemon.log` cobre só o ciclo de vida do daemon. Ele é truncado no lugar, preservando o inode, a cada publicação de registro ([daemon-registration-owner.ts:89,170-190][r-reg-owner], [AGENTS.md][r-agents]).

### 4.6 `app.log`, `runner.log` e trace

- **`app.log` (fato):**
  - É anexado por `logs start` e rotaciona para `app.log.1` acima de 5 MiB. `AGENT_DEVICE_APP_LOG_MAX_BYTES` e `AGENT_DEVICE_APP_LOG_MAX_FILES` (padrão 1) ajustam ([app-log-files.ts:6-35][r-applog-files]). Recusa symlink.
  - `AGENT_DEVICE_APP_LOG_REDACT_PATTERNS` (regex separadas por vírgula) é aplicada **na escrita** ([platform-runtime-app-log-output.ts:25-110][r-applog-output]).
  - `logs clear` trunca e remove as rotações; `logs mark` insere marcadores.
  - O agente deve fazer `logs path` e depois `grep`, para não trazer o log inteiro ao contexto ([doc debugging-profiling][r-doc-debug]).
- **`runner.log` (fato).** Guarda a saída de build e start do runner e do `xcodebuild` por sessão ([session-artifact-paths.ts:6-9][r-artifact-paths]).
- **Trace (fato).** `trace start` cria um arquivo vazio e guarda `session.trace = { outPath, startedAt }` em memória. `trace stop [path]` move o arquivo, se pedido, e o devolve como artefato `trace-log`. O caminho é repassado como `traceLogPath` aos handlers de plataforma ([trace-runtime.ts:27-90][r-trace-runtime]). O conteúdo exato que cada plataforma anexa **não foi verificado**.

### 4.7 Recursos duráveis: gravação de tela, logs, perf e áudio

O que pode sobreviver a uma requisição é modelado como **par handle vivo + descritor durável** ([ADR 0019 §5][r-adr19]):

- **Fato.** "Starting durable work returns a **live resource handle** (process-local authority) and a **durable resource descriptor** (bounded, JSON-safe, versioned state sufficient for the exact runtime owner to make a deterministic recovery attempt)."
- **Fato. Envelope persistido** ([durable-resource-envelope.ts][r-durable-envelope]):

  ```ts
  export type DurableResourceEnvelope<ResourceKind extends string = string> = Readonly<{
    envelopeVersion: 1; resourceKind: ResourceKind; sessionId: string;
    device: DeviceIdentity; owner: RuntimeOwnerRef; fence: ResourceOwnershipFence;
    lifecycle: 'open' | 'completed'; descriptor: { version: number; body: JsonObject }; metadata?: JsonObject;
  }>;
  ```

- **Fato. Armazenamento.** Há um arquivo por tipo no diretório da sessão (`screen-recording.resource.json`, `app-log.resource.json`, `perf-capture.resource.json`, `audio-probe.resource.json`), gravado com `publishDurableFileSync` ([durable-capture/store.ts:29-79][r-durable-store], [atomic-file.ts:41-82][r-atomic]):
  - temp exclusivo `wx` em `0600`;
  - `fsync` do arquivo;
  - `rename` (ou `link` exclusivo);
  - `fsync` do diretório, best-effort.

  A enumeração após crash varre `sessions/*/<arquivo>`.
- **Fato. Leitura defensiva.** O JSON reentra como `unknown`. O envelope é validado primeiro, e só o dono exato decodifica o `descriptor`. Envelope inválido ou de versão desconhecida vira `unreattachable: descriptor-invalid | descriptor-version-unsupported` e é **mantido como evidência**: nunca apagado nem "migrado no chute" ([ADR 0019 §5][r-adr19]).
- **Fato. Reanexação.** Ela devolve `active`, `completed`, `missing` ou `unreattachable` (`owner-unavailable`, `transport-not-reattachable`, `ownership-fence-lost`). Cada passo destrutivo segura um "fence" de posse ([ADR 0019 §5][r-adr19]).
- **Fato. Gravação de tela** ([ADR 0024][r-adr24], proposta para esse tipo):
  - vira "stop-and-collect" e guarda checkpoints de stop no manifesto;
  - `record stop` pode ser repetido: se a exportação terminou depois do timeout, a segunda chamada devolve o resultado;
  - no Android, depois de reiniciar o daemon, só os pedaços MP4 listados no manifesto são recuperados;
  - no Limrun, nada sobrevive ([doc commands][r-doc-commands]).
- **Fato. Startup do daemon** ([daemon-runtime.ts:655-727][r-daemon-runtime]):
  - adquire o lock de registro;
  - recupera marcadores legados de app-log e recursos de app-log;
  - colhe (`reap`) processos de gravação `simctl` órfãos a partir de `owned-processes.json`;
  - limpa navegadores órfãos;
  - dispara a recuperação do IME de teste Android;
  - abre os servidores e publica `daemon.json`;
  - reconcilia device claims.
- **Fato. `owned-processes.json`** (`{ version: 1, processes: [...] }`, `0600`, `fsync` + `rename`) existe por daemon e por sessão. O escopo de sessão precisa resolver para um filho direto de `sessions/` ([owned-process-record.ts:10-80][r-owned-proc]).

### 4.8 Gravação de scripts `.ad` (record & replay)

**Como gravar (fato,** [doc replay-e2e][r-doc-replay]**):**

```bash
agent-device open Settings --platform ios --session e2e --save-script [./caminho.ad]
agent-device snapshot -i --session e2e
agent-device click @e13 --session e2e
agent-device close --session e2e        # publica o .ad
agent-device session save-script [path] # publica sem fechar (ADR 0016)
```

**Formato (fato).** É texto, uma linha por comando na grafia da CLI, com cabeçalho `context`, `env`, aspas JSON ou literais e `${VAR}`. Exemplo real do repositório ([examples/test-app/replays/checkout-form.ad][r-ad-example]):

```
context platform=ios timeout=60000
env APP_TARGET="Agent Device Tester"
open "${APP_TARGET}" --relaunch --launch-url "${APP_URL}"
wait "label=\"Form\"" 30000
click "label=\"Form\""
fill id="field-name" "Ada Lovelace"
scroll down 0.6
click id="submit-order"
wait "Order summary" 5000
close
```

**Como o writer serializa** ([session-script-writer.ts:136-537][r-script-writer]):

- **Fato.** A primeira linha é `context platform=<ios|android|…> device="<nome>" [kind=…] theme=unknown` ([session-script-writer.ts:445-466][r-script-writer]).
- **Fato.** `snapshot` não entra no script. Ações com alvo trocam o `@ref` pela **cadeia de seletores** resolvida (`selectorChain.join(' || ')`). Se a ref nunca resolveu para seletor, uma sessão de reparo ou de publicação ativa **recusa gravar** um `@ref` solto, que seria inútil fora da sessão ("fail loud").
- **Fato.** Pins `~sN` são removidos do script. Quando há `refLabel`, uma linha `snapshot -i -s <label>` é emitida antes da ação, como escopo de apoio.
- **Fato.** Antes de cada ação vai uma linha `# agent-device:target-v1 {json}` com evidência de identidade: id único, senão role+label, prefixo de ancestrais, `sibling`, `viewportOrder`, `scrollRegion`, `verification`. O `rect` vai só como diagnóstico. Exemplo dos testes ([script.test.ts:742][r-ad-script-test]):

  ```
  # agent-device:target-v1 {"id":"save","role":"button","label":"Save","ancestry":[{"role":"toolbar","label":"Editor"},{"role":"window"}],"sibling":0,"viewportOrder":0,"scrollRegion":{"role":"scrollview","id":"editor-scroll"},"verification":"verified"}
  click @e12 "Save"
  ```

  A anotação precisa vir **imediatamente** antes da ação. Linha em branco, outro comentário no meio ou JSON malformado dão `INVALID_ARGS`, não são ignorados ([script.test.ts:744-800][r-ad-script-test]). O replay verifica essa identidade **antes** de agir e, se não consegue isolar o elemento, diverge (`identity-unverifiable`) em vez de escolher em silêncio ([ADR 0012][r-adr12]).
- **Fato.** Um script de reparo concluído termina com `# agent-device:heal-complete` ([session-script-writer.ts:67][r-script-writer]).

**Publicação atômica e sem sobrescrita (fato,** [session-script-writer.ts:250-300][r-script-writer], [atomic-file.ts:18-35][r-atomic]**):**

- O temp fica no **mesmo diretório** do destino, nunca em `/tmp`.
- Por padrão, a publicação é `linkSync`, um "create-exclusive" atômico em que o primeiro a escrever vence. Se o destino existe, dá `script_target_exists`.
- Com `--force`/`--overwrite`, a publicação é `renameSync`, uma substituição atômica.
- O caminho padrão é `sessions/<nome>-<ISO com : e . trocados por ->.ad`.

**Segredos (fato,** [ADR 0017][r-adr17]**).** `fill <alvo> "$AD_VAR_PASSWORD" --record-as PASSWORD` envia o literal ao app. A resposta, a gravação, o diário e o script recebem `${PASSWORD}`. O replay resolve por `AD_VAR_PASSWORD` ou `--env`. O mapa literal → `${VAR}` fica só em memória durante a sessão (`recordedFillLiterals`), para que ecos posteriores na UI também sejam parametrizados ([session-state.ts:250-262][r-session-state]). **Sem `--record-as`, o valor de `fill`/`type` vai literal para o `.ad`** ([ADR 0016][r-adr16]).

**Replay e seletores frágeis (fato,** [ADR 0012][r-adr12], [doc replay-e2e][r-doc-replay]**):**

- `replay <arquivo>` executa o plano, verificando `target-v1` antes de cada ação.
- Uma falha vira `REPLAY_DIVERGENCE` com:
  - `kind` (`action-failure`, `selector-miss`, `identity-mismatch`, `identity-unverifiable`);
  - um `screen`, que é um snapshot novo com refs ranqueadas;
  - até 5 `suggestions` ranqueadas (id > role+label > label, depois mesma `scrollRegion`, depois ordem do documento);
  - `resume: { from, planDigest }`.

  O tamanho é limitado por nível de resposta: 8/24/64 KiB.
- **O `--update` foi aposentado como "ator":** não reescreve mais `.ad`, só sugere.
- O reparo é feito pelo agente, numa transação ARMED → COMPLETE → COMMITTED (`replay --save-script`), com publicação exclusiva.
- Se a sessão de reparo é colhida antes do commit, fica um `repair-tombstone.json` (`{ owner, reapedAt, expiresAt, sourcePath?, commitFailure? }`, TTL de 1 h). O próximo comando recebe `REPAIR_SESSION_EXPIRED` ou `REPAIR_COMMIT_FAILED` em vez de `SESSION_NOT_FOUND` ([session-store.ts:244-340][r-session-store], [session-repair-tombstone.ts][r-repair-tomb]).
- O análogo para ociosidade é `idle-expiry.json` (`{ owner, expiredAtMs, expiresAt, idleExpiryMs, deviceKey? }`) ([session-idle-tombstone.ts][r-idle-tomb]).
- `replay --from N --plan-digest <sha256>` retoma no passo N **sem** reconstruir estado.

**Suíte `test` (fato).** Ela descobre `.ad` (e flows Maestro) e roda em série, com retries ≤ 3, timeout e JUnit. Os artefatos vão para `.agent-device/test-artifacts/<suite-id>/<slug>/attempt-N/` ([session-test-artifacts.ts][r-test-artifacts], [session-test-attempt.ts:144][r-test-attempt], [session-test-runtime.ts:366][r-test-runtime]):

- `replay.ad` (cópia da fonte);
- `result.txt` e `failure.txt` (manifesto chave: valor);
- `replay-timing.ndjson`, com início e fim de cada passo e duração;
- cópias de logs e artefatos com nomes de-duplicados.

**Maestro (fato).** O pacote `@agent-device/maestro` executa YAML do Maestro direto ([ADR 0015][r-adr15]). Também existe exportação `.ad` → Maestro YAML "estrito" ([doc replay-e2e][r-doc-replay]).

**Em proposta (fato).** Fragmentos gravados componíveis, com `include` fixado por digest de conteúdo e sem "latest" implícito ([ADR 0020][r-adr20], Proposed).

### 4.9 Artefatos binários e temporários

- **Fato.**
  - Saída sem caminho explícito reserva `$TMPDIR/agent-device-<campo>-XXXX/<campo><ext>`, com `cleanup` que remove a pasta. Para screenshot, é `agent-device-screenshot-*/screenshot.png` ([screenshot-runtime.ts:384-420][r-screenshot-runtime], [io.ts:117-150][r-io]).
  - Política de caminho: `allowLocalOutputPaths` e, opcionalmente, um `rootDir` que confina saídas ([io-policy.ts:33-50][r-io-policy], [io.ts][r-io]).
- **Fato. Downloads (daemon remoto).**
  - Cada artefato recebe um id aleatório (`randomUUID`) e é removido **depois do download ou em 15 min**, a não ser que `AGENT_DEVICE_RETAIN_ARTIFACTS` esteja ligado ([artifact-tracking.ts:18-80][r-artifact-tracking], [daemon-runtime.ts:325][r-daemon-runtime]).
  - Diretórios são servidos como `.tar.gz`. Downloads resolvem por id do servidor, nunca por caminho do cliente.
  - Uploads têm limite de tamanho, nomes sanitizados e extração que rejeita path traversal ([doc security-trust][r-doc-security]).
- **Fato.** Caminhos materializados vivem 15 min (`DEFAULT_MATERIALIZED_PATH_TTL_MS`). Uploads e resumable uploads expiram em 5 min ([materialized-path-registry.ts:7][r-materialized], [artifact-tracking.ts:323][r-artifact-tracking]).
- **Fato.** Artefatos de profiling e heap voltam como **caminho + metadados compactos**, "not printed or embedded in JSON by default". Um exemplo da doc é `Memory artifact (android-hprof): /tmp/app.hprof (42MB)` ([doc debugging-profiling][r-doc-debug]).

### 4.10 Estado global: registro, locks, claims e caches

- **`daemon.json` (fato).** Contém `{ port?, httpPort?, transport, token, pid, processStartTime, version, codeOrigin, codeSignature, policyDigest, stateDir, … }`. É publicado com `publishFileSync` em `0600` e só enquanto o lock está seguro (`assertHeld`). Na saída, só é removido se o registro ainda nomeia este processo (pid **e** start time) ([daemon-registration-owner.ts:63-140][r-reg-owner], [daemon-client-metadata.ts:12-55][r-daemon-meta]).
- **Locks de processo (fato,** [ADR 0030][r-adr30], [process-lock.ts][r-process-lock]**):**
  - O lock é um diretório `<nome>.lock/` com `owner.json` (`{ pid, startTime, acquiredAtMs, claimToken, claimIssuerId }`).
  - A guarda de mutação **não expira**: "Age never proves abandonment".
  - Para reclamar um lock, é preciso provar que o dono morreu (pid + start time).
  - Timeout padrão de 30 s com poll de 100 ms.
- **Device claims (fato).** Um arquivo `~/.agent-device/device-claims/<sha256(deviceKey)>.json` por aparelho, onde `deviceKey = local:<plataforma>:<appleOs|none>:<id>`. O conteúdo é `{ schemaVersion: 2, deviceKey, device, session, workspace, stateDir, ownerPid, ownerStartTime, ownerToken, createdAtMs, updatedAtMs }`. A escrita roda sob o lock `<arquivo>.lock`, com `0600` em diretório `0700`. `AGENT_DEVICE_CLAIMS_DIR` sobrepõe o local ([device-claim-paths.ts][r-claim-paths], [device-claim-store.ts][r-claim-store], [device-claim-record.ts][r-claim-record]). `device status` inspeciona sem daemon e `device release --stale` libera donos mortos ([README][r-readme]).
- **Leases do runner Apple (fato).** `~/.agent-device/apple-runner/leases/` guarda `{ schemaVersion: 1, deviceId, ownerToken, ownerPid, ownerStartTime, ownerStateDir, sessionId, runnerPid, port, xctestrunPath, cacheKey, jsonPath, runnerLogPath, … }`. Uma lease órfã (dono morto ou state dir apagado) é reclamada automaticamente ([runner-lease.ts:41-62,436-440][r-runner-lease], [cli-help.ts:536][r-cli-help]).
- **Cache do runner (fato).**
  - Fica em `~/.agent-device/apple-runner/derived/<ios-simulator|ios-device|…>/<chave>`, com uma chave nova a cada mudança de fonte ou Xcode.
  - A reutilização só é autorizada pelo **manifesto de conteúdo**: digests, modos e alvos de symlink.
  - Depois do build, o scratch é aparado (165,7 MB → 5,9 MB numa medição).
  - Mantém as 3 chaves mais recentes ou usadas no último dia (`AGENT_DEVICE_IOS_RUNNER_CACHE_KEEP`).
  - A certificação falha fechada (`runner_cache_uncertifiable`) ([doc commands, "Prepare Apple runner"][r-doc-commands]).

### 4.11 Primitivas de atomicidade, concorrência e recuperação

| Primitiva | Uso | Fonte |
| --- | --- | --- |
| `publishFileSync`: temp irmão + `rename` ou `link` exclusivo; o temp é sempre removido | `daemon.json`, `.ad`, device claims, shutdown report | [atomic-file.ts:18-35][r-atomic] |
| `publishDurableFileSync`: `open('wx', 0600)` + `fsync` + `rename`/`link` + `fsync` do diretório; recusa destino inseguro | descritores duráveis | [atomic-file.ts:41-82][r-atomic] |
| Fila serializada por caminho (`Map<path, Promise>`) | `events.ndjson` | [session-event-log.ts:84-112][r-event-log] |
| Sidecar escrito antes do rename + verificação por digest | rotação do diário | [session-event-log-window.ts][r-event-window] |
| Lock de processo em diretório com identidade e guarda sem expiração | `daemon.lock`, claims, plugins, caches nativos | [ADR 0030][r-adr30], [process-lock.ts][r-process-lock] |
| Recusa de symlink (`lstat`) | `events.ndjson`, `app.log`, registros | [session-event-log-window.ts][r-event-window], [app-log-files.ts][r-applog-files] |
| Contenção de caminho: `resolveSessionDir` recusa `.`, `..` e vazio; artefato gerenciado precisa resolver (por `realpath`) dentro de `sessions/` | todos os artefatos de sessão | [session-artifact-paths.ts:52-70][r-artifact-paths], [managed-session-artifact-path.ts][r-managed-path] |
| Identidade de processo = pid + start time (não basta pid) | registro, claims, leases, locks | [daemon-registration.ts][r-daemon-reg] |
| Locks de execução em memória por sessão e aparelho | serialização de comandos | [request-execution-locks.ts][r-exec-locks] |

### 4.12 Retenção e limpeza

| Item | Política | Fonte |
| --- | --- | --- |
| `events.ndjson` | 5 MiB ativa + 1 rotacionada | [session-event-log-window.ts:33-37][r-event-window] |
| `app.log` | 5 MiB + 1 rotacionada (configurável) | [app-log-files.ts:6-7][r-applog-files] |
| `requests/*.ndjson`, `runner.log`, `logs/…` | **Sem rotação ou limpeza encontrada** (inferência: só se apagados à mão) | código lido; [doc sessions][r-doc-sessions]: "inspect or delete it after the run" |
| Diretórios `sessions/<s>/`, `.ad` e `.trace.log` padrão | **Não removidos** no `close`. Não achei `rm` do diretório de sessão no código de lifecycle. O script `clean:daemon --prune-dev` aposenta state dirs de dev com mais de 14 dias, mas diz "session artifacts retained". | [clean-daemon.ts][r-clean-daemon] |
| Downloads do daemon | após o download ou 15 min | [artifact-tracking.ts:18][r-artifact-tracking] |
| Tombstones | TTL 1 h para reparo; `expiresAt` para ociosidade; limpos no próximo `open`/`replay --save-script` | [session-store.ts:46,330-420][r-session-store] |
| Cache do runner | 3 chaves recentes / último dia | [doc commands][r-doc-commands] |
| `~/.agent-device/ios-runner` (legado) | não removido automaticamente | [doc commands][r-doc-commands] |
| Diretórios temporários | removidos pelo `cleanup` do adaptador | [io.ts][r-io] |

### 4.13 O que volta inline e o que fica em disco (economia de contexto)

- **Inline (fato):**
  - snapshot em texto compacto com refs;
  - diffs após `--settle`/`diff snapshot` (`+`, `-`, contexto);
  - erros com `code`, `hint`, `details.reason`, `diagnosticId`, `logPath`;
  - `resolution` (como o alvo foi resolvido, até 5 alternativas);
  - divergências de replay com teto de 8/24/64 KiB por nível ([doc snapshots][r-doc-snapshots], [ADR 0012][r-adr12]).
- **Em disco, devolvido por caminho (fato):**
  - screenshots, vídeos, perf e heap, `.ad`;
  - logs: o agente faz `grep` em `app.log` a partir de `logs path`;
  - diagnóstico completo (`logPath`) ([doc debugging-profiling][r-doc-debug]).
- **Truncamento e compactação (fato):**
  - nível de resposta `digest | default | full` (`RESPONSE_LEVELS`) ([kernel/contracts.ts:125][r-kernel-contracts]);
  - o snapshot "visible-first" resume conteúdo fora da tela;
  - `-s`/`-d` escopam a árvore;
  - snapshot Android inalterado vira um ack curto;
  - `screenshot --scale` (ou `AGENT_DEVICE_SCREENSHOT_SCALE=0.3`) reduz a imagem, e `--overlay-refs` queima as refs no PNG;
  - strings de diagnóstico são cortadas em 400 caracteres e stderr em 8.192 (cabeça + `...<truncated>` + cauda) ([redaction.ts:8-80][r-redaction]).
- **Contrato testado (fato).** `test/output-economy/` mantém uma baseline versionada de bytes, linhas e refs. Um PR não pode subir o teto contra o qual é medido, e cada aumento precisa de uma *waiver* revisada ([test/output-economy/README.md][r-econ]).
- **Marketing.** Snapshots custam 3–4x menos tokens que screenshots. Uma sessão de depuração caiu de cerca de 150 mil para 69,2 mil tokens. O corte de itens fora da tela economiza até 80% em listas longas ([blog Callstack, 2026-04-03][r-blog-opt]).

### 4.14 Privacidade e segurança dos dados

- **Fato. Redação central `redactDiagnosticData`** ([redaction.ts][r-redaction]):
  - chave que casa com `token|secret|password|authorization|cookie|api[_-]?key|access[_-]?key|private[_-]?key|user[_-]?code|device[_-]?code|refresh[_-]?credential` vira `[REDACTED]`;
  - `Bearer …` e `adc_(agent|live|refresh|cli)_…` também são redigidos;
  - atribuições `x_token=…` são redigidas;
  - URLs perdem a query (`?REDACTED`) e as credenciais;
  - há proteção contra ciclos.
- **Fato.** A ADR 0018 (proposta) prevê redação **uma vez na fronteira do diário** e um esquema allowlist para qualquer telemetria que saia da máquina. Ela documenta que o trace de replay tinha um helper sem redação, cuja correção está declarada como mudança intencional ([ADR 0018][r-adr18]).
- **Fato. Permissões:**
  - `0600` em `daemon.json`, claims, registros duráveis, `cli-session.json`, `remote-connections/*.json`, `expired-provider-leases.json` e cache de assinatura;
  - `0700` nos diretórios de claims, allocations, auth e plugins ([grep `0o600`/`0o700`][r-claim-store], [doc security-trust][r-doc-security]).
- **Fato.** A doc trata screenshots, vídeos, traces, logs, dumps de rede, scripts e URLs de nuvem como sensíveis, e manda não versioná-los ([doc security-trust][r-doc-security]).
- **Fato. Lacunas abertas:**
  - [#3261][r-i3261]: entradas parametrizadas no iOS ainda aparecem em logs de diagnóstico nativos do XCTest;
  - [#3260][r-i3260]: falta `fill` por stdin para tirar o segredo do argv.

---

## 5. Desempenho

- **Fato (ADR, protótipo).** Uma sessão persistente do helper Android contra o modo one-shot ([ADR 0002][r-adr02]):
  - snapshot do launcher: p50 de 227 ms → 5,8 ms;
  - playground do React Navigation: 265,7 ms → 16,5 ms.
- **Fato (evidência versionada, iOS Simulator, 2026-09-21).** Medianas, 10 amostras por célula, em host carregado ([ios-snapshot-convergence-final][r-evidence-ios]):
  - **cold-cold** (simulador rebootado e derived data limpo): 6,5–8,1 s de parede, contra 17,5–20,8 s na baseline, uma queda de 57–68%;
  - **cold** (daemon parado, app encerrado): 5,0–6,1 s, de 9% a 26% melhor que a baseline;
  - **warm**, snapshot `interactiveOnly` de uma árvore de 4 nós (cerca de 3,4 KB): **cerca de 86–96 ms** no daemon, contra cerca de 45 ms numa baseline anterior. O próprio documento registra essa regressão de cerca de 40 ms fixos e lista os PRs suspeitos.
  - O RTT extra pesa: de 0 a 80 ms de RTT adicionado custam 178–387 ms por snapshot.
- **Fato. Otimizações no código e na doc:**
  - helpers persistentes (runner XCUITest e APK Android) reaproveitam infraestrutura, mas não dados ([ADR 0002][r-adr02]);
  - preflight `uptime` adaptativo, pulado em loops quentes de mutação saudável ([ios-runner-protocol-optimizations.md][r-runner-opt]);
  - recuperação por `status(commandId)` antes de invalidar o runner;
  - "accepted-depth hints" da ponte AX: lembra profundidades aceitas por app e geração e expira após 8 capturas ([bridge README][r-bridge-readme]);
  - circuito por geração do app quando a ponte falha;
  - worker de PNG pré-aquecido no start do daemon ([daemon-runtime.ts][r-daemon-runtime]);
  - cache de cliente HTTP condicionado ao instance id ([ADR 0006][r-adr06]);
  - carregamento preguiçoso (lazy-load) de Maestro e orçamento de "eager closure" de imports ([release v0.21.24][r-releases], [ADR 0027][r-adr27]).
- **Fato.** `scripts/perf/` e `perf-nightly.yml` dão sinal de latência que não bloqueia o CI. O bloqueio fica com a economia de saída ([test/output-economy/README.md][r-econ], [.github/workflows][r-workflows]).
- **Marketing.** A sessão de depuração ficou 33% mais rápida, de 9 para 6 min ([blog Callstack][r-blog-opt]).

---

## 6. Extensibilidade, empacotamento e distribuição

- **Distribuição (fato).**
  - Pacote npm `agent-device` com bin `bin/agent-device.mjs`. O campo `files` inclui `dist`, o fonte do helper macOS, a ponte AX (fonte `.m`), `fold-helper`, os **APKs Android já compilados** (`android/*/dist`), `linux/atspi-dump.py`, `server.json` (registro MCP) e `smithery.yaml` ([package.json][r-pkg]).
  - Instalação: `npm install -g agent-device@latest` ([README][r-readme]).
- **Helpers iOS (fato).** O runner XCUITest é **compilado localmente com `xcodebuild` no primeiro uso** (`prepare ios-runner`) e cacheado ([doc commands][r-doc-commands]). A ponte AX é compilada com `clang` no primeiro uso, "never downloaded, pre-signed, or built by npm installation" ([bridge README][r-bridge-readme]). Há um workflow `release-ios-runner.yml` que publica artefatos do runner em GitHub Releases ([workflow][r-wf-runner]). Se o runtime baixa esses artefatos **não foi verificado**: não achei URL de download no código.
- **Helpers Android (fato).** APKs assinados com um `debug.keystore` versionado, que precisa ser estável para `adb install -r`. São instalados automaticamente no primeiro snapshot quando faltam ou estão desatualizados ([android helper README][r-android-helper]).
- **Plugins de provedor (fato, interface experimental):**
  - `agent-device plugins add <pacote npm>` instala em `AGENT_DEVICE_HOME/plugins/<instalação>/` sem scripts de ciclo de vida;
  - o manifesto `agentDevicePlugin: { apiVersion: 1, provider, entry, connection?, credentialVariables? }` declara o plugin, e a fábrica devolve `{ runtime, platformModule }` ou `{ webDriver }`;
  - plugins **não** registram comandos arbitrários;
  - mudanças só valem depois de reiniciar o daemon ([doc plugins][r-doc-plugins]).
  - Há issues para mover BrowserStack, AWS Device Farm e Limrun para plugins ([#3309][r-i3309], [#3310][r-i3310], [#3311][r-i3311]).
- **Política do daemon (fato).** `AGENT_DEVICE_DAEMON_POLICY` confina comandos e aparelhos. Uma política inválida impede o start, e o digest vai para `daemon.json` ([ADR 0029][r-adr29], [daemon-runtime.ts:326-335][r-daemon-runtime]).
- **Configuração (fato).** `~/.agent-device/config.json` (ou `<AGENT_DEVICE_HOME>/config.json`), `./agent-device.json` (só defaults seguros de projeto), `--config` e `AGENT_DEVICE_CONFIG` ([cli-help.ts:31][r-cli-help], [cli-config.ts][r-cli-config]).
- **SDKs (fato).** `agent-device/ai-sdk` (AI SDK da Vercel), integração com Eve e subpaths públicos (`/selectors`, `/finders`, `/batch`, `/artifacts`, `/remote-config`, `/plugins/webdriver`…) ([package.json][r-pkg]).

---

## 7. Testes e qualidade

- **Fato. Volume:** 1.815 arquivos `*.test.ts` (vitest) e 129 arquivos de teste Swift. Os testes espelham a topologia do código-fonte um a um ([AGENTS.md][r-agents]).
- **Fato. Portões e ferramentas** ([package.json scripts][r-pkg], [.github/workflows][r-workflows]):
  - mutation testing com Stryker, em lanes `mutation-affected` e `mutation-weekly`;
  - fuzz de parsers;
  - checagem de camadas (`check:layering`);
  - grafo de dependências (`depgraph`), `fallow` com baselines;
  - compatibilidade de wire e replay (`check:daemon-wire-compat`, `check:replay-compat`);
  - `publint` e `attw`;
  - limite de tamanho;
  - conformância Maestro (diferencial);
  - lanes iOS, Android, macOS e Linux;
  - noturnas de XCTest, replays, perf e "concurrency torture".
- **Fato. Contratos entre linguagens.** Tabelas golden em `contracts/fixtures/` são consumidas por testes TS e nativos, por exemplo a conformância de recuperação AX ([bridge README][r-bridge-readme], [AGENTS.md][r-agents]).
- **Fato. Matriz de garantias de interação.** Cada caminho de despacho é classificado por garantia (`enforced`, `delegated`, `inapplicable`, `waived`) em `packages/contracts/src/interaction-guarantees.ts` ([ADR 0011][r-adr11]).
- **Fato. Regras do repo:**
  - arquivos acima de 1.000 linhas são dívida;
  - nenhum comportamento depende do texto de um erro;
  - compatibilidade só se for pedida ([AGENTS.md][r-agents]).
- **Fato. Fragilidade conhecida.** A lane de smoke do Simulador iOS falha em `main` com várias assinaturas rotativas ([#2491][r-i2491], aberta).

---

## 8. Limitações conhecidas, issues relevantes e roadmap

**Limitações documentadas (fato,** [doc known-limitations][r-doc-limits], [doc commands][r-doc-commands], [doc snapshots][r-doc-snapshots]**):**

- O diálogo "Allow Paste" do iOS nunca aparece sob XCUITest.
- `simctl pbcopy` não grava nada no Xcode 27.
- Texto não-ASCII em Android real exige `--test-ime`.
- O primeiro install de helper pode travar num diálogo do OEM.
- No WSL, `adb.exe` do Windows quebra caminhos.
- O clipboard do Android 16 não funciona via adb.
- Gravação em iOS físico é por frames, best-effort e sem áudio.
- O `screenrecord` do Android tem limite de 180 s e só codifica quadros quando a tela muda.
- Contact sheet só funciona com host macOS.
- Árvores com mais de 5.000 nós são truncadas, cortando o fim do documento, inclusive tab bars.
- `network dump` no iOS depende de Unified Logging e pode não nomear requisições keep-alive.
- `wait @ref` acompanha o texto, não a identidade do nó.

**Issues abertas relevantes (fato, lista em 2026-10-10,** [issues][r-issues]**):**

| Issue | Tema |
| --- | --- |
| [#3335][r-i3335] | `click`/`press` informam despacho, não chegada; lacuna de `outcomeObservation` |
| [#3354][r-i3354] | clique por seletor no iOS usa ponto de captura pré-toque; uma mudança de layout redireciona em silêncio |
| [#3346][r-i3346] | Android: evidência durável de flush para reinício do daemon na janela do IME de teste |
| [#3261][r-i3261] / [#3260][r-i3260] | segredo parametrizado em logs nativos do XCTest; `fill` por stdin |
| [#3106][r-i3106] | proposta de observações sem ativação, reaproveitamento inline de screenshot e evidência antecipada |
| [#3325][r-i3325]–[#3327][r-i3327] | prova de pior caso dos envelopes de requisição compostos (batch/replay) |
| [#3264][r-i3264]–[#3270][r-i3270] | "Host": verificação remota com aparelhos frescos via Simlock ([ADR 0021][r-adr21]), em espera |
| [#2491][r-i2491] | lane de smoke iOS instável |

**Issues fechadas que explicam o desenho de persistência (fato):**

- [#1788][r-i1788]: `events.ndjson` não tinha limite. Daí veio a janela com sidecar.
- [#1998][r-i1998]: corrida entre a escrita assíncrona do diário e a limpeza de teste.

**Roadmap (fato, ADRs em estado "Proposed"):**

- [ADR 0018][r-adr18]: diário unificado com catálogo de eventos, sinks e escopo de teardown. "Nothing here is implemented" na data da ADR. Hoje coexistem quatro vocabulários (diagnósticos, `events.ndjson`, progresso, trace de replay).
- [ADR 0020][r-adr20]: fragmentos `.ad` componíveis com `include` fixado por digest.
- [ADR 0024][r-adr24]: coordenador único de gravação de tela.
- [ADR 0028][r-adr28]: vocabulário de células de capacidade.
- Extração de provedores para plugins ([#3309][r-i3309]–[#3311][r-i3311]).

---

## 9. Glossário e tabela-resumo

### 9.1 Glossário (de [CONTEXT.md][r-context], resumido)

| Termo | Significado |
| --- | --- |
| Sessão | Estado do daemon para um alvo selecionado e seu app/superfície |
| Device claim | Posse exclusiva global no host de um aparelho local, por sessão, comando ou alocador |
| Runner lease | Exclusão mútua do processo helper (runner XCUITest); não é posse remota |
| Device lease | Posse lógica remota de um aparelho por tenant/run/cliente |
| Ref frame | Namespace de autorização das `@ref` mutantes: época congelada + escopo de emissão |
| Ref generation pin | Sufixo `~s<n>` que fixa a geração do snapshot da qual a ref saiu |
| Settled observation | Observação pós-ação que espera a UI quieta e faz diff contra a árvore anterior |
| Snapshot projection | `raw` ⊇ `regular` ⊇ `interactive` |
| Clip fold | Interpretador único de visibilidade (viewport, scroll, resumo fora da tela) |
| Snapshot quality verdict | Declaração estruturada do estado da captura, backend e degradação |
| Script recording | Modo de sessão que grava ações portáveis + evidência de alvo num `.ad` |
| Recorded input parameterization | `fill --record-as VAR`: literal vai ao app, `${VAR}` vai ao disco |
| Live resource handle / Durable resource descriptor | Autoridade em processo / estado versionado em disco para reanexar |
| Reattachment | Recuperação cercada (fenced) pelo dono exato do descritor |
| Replay divergence | Erro estruturado `REPLAY_DIVERGENCE` com tela, sugestões e `resume` |
| Human-control hold | Pausa das mutações do agente enquanto um humano opera o aparelho |

### 9.2 Componente → arquivo → responsabilidade

| Componente | Arquivo / pacote | Responsabilidade |
| --- | --- | --- |
| Resolução de caminhos do daemon | [src/daemon-resolution.ts][r-daemon-resolution] | `stateDir`, `daemon.json`, `daemon.lock`, `daemon.log`, `sessions/`, `allocations/` |
| Registro do daemon | [src/daemon-registration-owner.ts][r-reg-owner], [src/daemon-registration.ts][r-daemon-reg] | Lock, publicação/remoção de `daemon.json`, shutdown report |
| Runtime do daemon | [src/daemon/server/daemon-runtime.ts][r-daemon-runtime] | Start, recuperação, servidores, token, shutdown |
| Transporte socket | [src/daemon/server/transport.ts][r-transport] | TCP loopback NDJSON, progresso, cancelamento |
| Transporte HTTP | [src/daemon/server/http-server.ts][r-http-server] | `/health`, `/rpc`, uploads, artefatos |
| Store de sessões | [src/daemon/session-store.ts][r-session-store] | `Map` em memória, diário, tombstones, caminhos |
| Estado da sessão | [src/daemon/session-state.ts][r-session-state] | Tipo `SessionState` (não persistido) |
| Roteamento de sessão | [src/daemon/session-routing.ts][r-session-routing] | Chave `cwd:<hash>:<nome>`, escopos |
| Caminhos de artefatos | [src/daemon/session-artifact-paths.ts][r-artifact-paths] | `requests/`, `runner.log`, `app.log`, contenção |
| Diário de eventos | [packages/session-journal/src/session-event-log.ts][r-event-log] | `events.ndjson` v1, fila, leitura paginada |
| Janela de rotação | [packages/session-journal/src/session-event-log-window.ts][r-event-window] | Rotação, sidecar, cursores absolutos |
| Diagnósticos | [packages/host-kit/src/internal/diagnostics.ts][r-diagnostics] | Escopo por requisição, flush NDJSON |
| Redação | [packages/kernel/src/redaction.ts][r-redaction] | Redação e truncamento |
| Escrita atômica | [packages/host-kit/src/internal/atomic-file.ts][r-atomic] | `publishFileSync`, `publishDurableFileSync` |
| Locks de processo | [packages/host-kit/src/internal/process-lock.ts][r-process-lock] | Locks em diretório com identidade |
| Processos possuídos | [packages/host-kit/src/internal/owned-process-record.ts][r-owned-proc] | `owned-processes.json` |
| Recursos duráveis | [packages/capture-kit/src/durable-capture/store.ts][r-durable-store], [contracts/durable-resource-envelope.ts][r-durable-envelope] | `*.resource.json`, envelope v1 |
| Device claims | [src/daemon/device/device-claim-store.ts][r-claim-store], [device-claim-paths.ts][r-claim-paths] | Posse global de aparelhos |
| Gravação de ações | [src/daemon/session-action-recorder.ts][r-action-recorder] | `session.actions`, parametrização de fill |
| Writer de `.ad` | [src/daemon/session-script-writer.ts][r-script-writer] | Serialização, publicação atômica, reparo |
| Codec `.ad` | `packages/ad-script` | Parse/format, `target-v1` |
| Motor de replay | `packages/ad-replay`, `packages/replay-port` | Execução, divergência, resume |
| Suíte `test` | [packages/replay-test][r-test-artifacts] | Agendamento, artefatos por tentativa |
| Snapshot/refs | [packages/kernel/src/snapshot.ts][r-kernel-snapshot], [src/daemon/session-snapshot.ts][r-session-snapshot] | Modelo de nó, `attachRefs`, gerações |
| Apresentação de snapshot iOS | `packages/capture-kit`, `apple/snapshot-presentation` | Clip fold, compactação |
| Runner Apple | [apple/runner][r-runner-proto], `packages/platform-apple/src/runner/` | XCUITest HTTP, leases, cache |
| Ponte AX Simulador | [apple/snapshot-bridge][r-bridge-readme] | Leitura AX privada no simulador |
| Helper Android | [android/snapshot-helper][r-android-helper], `packages/platform-android` | UiAutomation, gestos, screencap |
| MCP | [src/mcp/server.ts][r-mcp-server], [tool-ref-pins.ts][r-mcp-pins] | stdio JSON-RPC, tools, pins de ref |
| Plugins | `src/plugins/store.ts`, [doc plugins][r-doc-plugins] | Instalação e carga de provedores |
| Economia de saída | [test/output-economy][r-econ] | Baseline de bytes/refs |

---

## Fontes

Código e docs no SHA `87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2`. Dados de API do GitHub e npm consultados em 2026-10-10.

[r-readme]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/README.md
[r-pkg]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/package.json
[r-license]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/LICENSE
[r-agents]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/AGENTS.md
[r-context]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/CONTEXT.md
[r-releases]: https://github.com/callstack/agent-device/releases
[r-npm]: https://www.npmjs.com/package/agent-device
[r-issues]: https://github.com/callstack/agent-device/issues
[r-workflows]: https://github.com/callstack/agent-device/tree/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/.github/workflows
[r-wf-runner]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/.github/workflows/release-ios-runner.yml
[r-blog-opt]: https://www.callstack.com/blog/how-we-optimized-agent-device-for-mobile-app-automation

[r-adr02]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0002-persistent-platform-helper-sessions.md
[r-adr04]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0004-ios-snapshot-backend-strategy.md
[r-adr06]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0006-daemon-rpc-protocol-version.md
[r-adr11]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0011-interaction-guarantee-contract.md
[r-adr12]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0012-interactive-replay.md
[r-adr14]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0014-session-ref-frame-lifetime.md
[r-adr15]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0015-direct-maestro-engine.md
[r-adr16]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0016-active-session-script-publication.md
[r-adr17]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0017-parameterized-recorded-inputs.md
[r-adr18]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0018-unified-event-journal.md
[r-adr19]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0019-request-bound-platform-runtime.md
[r-adr20]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0020-composable-recorded-fragments.md
[r-adr21]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0021-host-simlock-managed-device-allocation.md
[r-adr24]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0024-screen-recording-provable-signal.md
[r-adr27]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0027-descriptor-root-vs-eager-closure-budget.md
[r-adr28]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0028-capability-family-cell-vocabulary.md
[r-adr29]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0029-daemon-policy.md
[r-adr30]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0030-process-lock-exclusion.md
[r-adr31]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/adr/0031-macos-native-app-backend.md

[r-doc-sessions]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/sessions.md
[r-doc-snapshots]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/snapshots.md
[r-doc-commands]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/commands.md
[r-doc-replay]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/replay-e2e.md
[r-doc-debug]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/debugging-profiling.md
[r-doc-security]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/security-trust.md
[r-doc-limits]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/known-limitations.md
[r-doc-agent-setup]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/agent-setup.md
[r-doc-plugins]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/plugins.md
[r-doc-client-api]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/website/docs/docs/client-api.md

[r-daemon-resolution]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon-resolution.ts
[r-daemon-reg]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon-registration.ts
[r-reg-owner]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon-registration-owner.ts
[r-daemon-meta]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon-client/daemon-client-metadata.ts
[r-daemon-client-lifecycle]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon-client/daemon-client-lifecycle.ts
[r-daemon-runtime]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/server/daemon-runtime.ts
[r-idle-reap]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/server/daemon-idle-reap.ts
[r-transport]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/server/transport.ts
[r-http-server]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/server/http-server.ts
[r-cli-help]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/commands/schema/cli-help.ts
[r-cli-config]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/commands/schema/cli-config.ts
[r-session-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-store.ts
[r-session-state]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-state.ts
[r-session-routing]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-routing.ts
[r-session-scope]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/contracts/src/session-scope.ts
[r-session-snapshot]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-snapshot.ts
[r-session-paths]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/host-kit/src/session-paths.ts
[r-artifact-paths]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-artifact-paths.ts
[r-managed-path]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/managed-session-artifact-path.ts
[r-event-log]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/session-journal/src/session-event-log.ts
[r-event-window]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/session-journal/src/session-event-log-window.ts
[r-event-lines]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/session-journal/src/session-event-log-lines.ts
[r-event-action]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/session-journal/src/session-event-action.ts
[r-diagnostics]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/host-kit/src/internal/diagnostics.ts
[r-req-final]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/request-finalization.ts
[r-redaction]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/kernel/src/redaction.ts
[r-atomic]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/host-kit/src/internal/atomic-file.ts
[r-process-lock]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/host-kit/src/internal/process-lock.ts
[r-owned-proc]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/host-kit/src/internal/owned-process-record.ts
[r-durable-envelope]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/contracts/src/durable-resource-envelope.ts
[r-durable-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/capture-kit/src/durable-capture/store.ts
[r-rec-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/capture-kit/src/capture-admission/screen-recording-resource-store.ts
[r-perf-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/capture-kit/src/capture-admission/perf-capture-resource-store.ts
[r-audio-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/capture-kit/src/capture-admission/audio-probe-resource-store.ts
[r-applog-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/app-log-resource-store.ts
[r-applog-files]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/app-log-files.ts
[r-applog-output]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/platform-runtime-app-log-output.ts
[r-repair-tomb]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/session-repair-tombstone.ts
[r-idle-tomb]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-idle-tombstone.ts
[r-shutdown-report]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon-shutdown-report.ts
[r-provider-expiry]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/provider-lease-expiry.ts
[r-remote-conn]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/remote/remote-connection-state.ts
[r-metro-hints]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/metro/metro-session-hints.ts
[r-client-metro]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/metro/client-metro.ts
[r-auth]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/cli/auth-session.ts
[r-update-check]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/cli/update-check.ts
[r-alloc-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/managed-allocation/src/store-creation.ts
[r-claim-paths]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/device/device-claim-paths.ts
[r-claim-store]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/device/device-claim-store.ts
[r-claim-record]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/device/device-claim-record.ts
[r-exec-locks]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/request-execution-locks.ts
[r-action-recorder]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-action-recorder.ts
[r-script-writer]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/session-script-writer.ts
[r-ad-example]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/examples/test-app/replays/checkout-form.ad
[r-ad-script-test]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/ad-script/src/internal/__tests__/script.test.ts
[r-test-artifacts]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/replay-test/src/internal/session-test-artifacts.ts
[r-test-attempt]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/replay-test/src/internal/session-test-attempt.ts
[r-test-runtime]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/replay-test/src/internal/session-test-runtime.ts
[r-trace-runtime]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/handlers/trace-runtime.ts
[r-screenshot-runtime]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/screenshot-runtime.ts
[r-io]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/io.ts
[r-io-policy]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/commands/io-policy.ts
[r-artifact-tracking]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/artifact-tracking.ts
[r-materialized]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/daemon/materialized-path-registry.ts
[r-clean-daemon]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/scripts/clean-daemon.ts
[r-kernel-snapshot]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/kernel/src/snapshot.ts
[r-kernel-contracts]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/kernel/src/contracts.ts
[r-mcp-server]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/mcp/server.ts
[r-mcp-pins]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/src/mcp/tool-ref-pins.ts
[r-skill]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/skills/agent-device/SKILL.md
[r-pkg-proxy]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/proxy/package.json
[r-econ]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/test/output-economy/README.md
[r-runner-proto]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/apple/runner/RUNNER_PROTOCOL.md
[r-runner-opt]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/ios-runner-protocol-optimizations.md
[r-runner-cache]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/runner/runner-cache-metadata.ts
[r-runner-lease]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/runner/runner-lease.ts
[r-runner-io]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/runner/runner-io.ts
[r-snapshot-cache]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/snapshot-source/cache.ts
[r-fold-cache]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/foldable/fold-helper-cache.ts
[r-macos-helper]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/os/macos/helper.ts
[r-apple-screenshot]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/core/screenshot.ts
[r-apple-phys-shot]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-apple/src/core/physical-device-screenshot.ts
[r-bridge-readme]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/apple/snapshot-bridge/README.md
[r-android-helper]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/android/snapshot-helper/README.md
[r-android-input]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-android/src/input-actions.ts
[r-android-screenshot]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/packages/platform-android/src/screenshot.ts
[r-evidence-ios]: https://github.com/callstack/agent-device/blob/87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2/docs/evidence/ios-snapshot-convergence-final-2026-09-21.md

[r-i1788]: https://github.com/callstack/agent-device/issues/1788
[r-i1998]: https://github.com/callstack/agent-device/issues/1998
[r-i2491]: https://github.com/callstack/agent-device/issues/2491
[r-i3106]: https://github.com/callstack/agent-device/issues/3106
[r-i3260]: https://github.com/callstack/agent-device/issues/3260
[r-i3261]: https://github.com/callstack/agent-device/issues/3261
[r-i3264]: https://github.com/callstack/agent-device/issues/3264
[r-i3270]: https://github.com/callstack/agent-device/issues/3270
[r-i3309]: https://github.com/callstack/agent-device/issues/3309
[r-i3310]: https://github.com/callstack/agent-device/issues/3310
[r-i3311]: https://github.com/callstack/agent-device/issues/3311
[r-i3325]: https://github.com/callstack/agent-device/issues/3325
[r-i3327]: https://github.com/callstack/agent-device/issues/3327
[r-i3335]: https://github.com/callstack/agent-device/issues/3335
[r-i3346]: https://github.com/callstack/agent-device/issues/3346
[r-i3354]: https://github.com/callstack/agent-device/issues/3354

# Contrato da Rodada 3 (3.12.0) — escrito antes do código

Rodada orquestrada pelo protocolo Brain of Agent (modo melhoria). Seis
especialistas leram o sistema (`revisao/*.md`), três validadores fizeram a
contraprova, e este é o corte. `PROTOCOL_VERSION` continua **2**: tudo o que
toca o contrato é aditivo, com `make fixtures` e `docs/PROTOCOLO_RPC.md`.

Ordem de implementação (dependências entre parênteses): MEL-2, MEL-1, MEL-4,
MEL-3 (depois de MEL-4: os dois mexem em `services/flows.py`), MEL-5 (depois
de MEL-1, que cria `logs_dir()`, e de MEL-4, que tira texto digitado do
`logger`), MEL-6.

Um commit por melhoria, com o ID na mensagem. Antes de cada commit:
`make check` e `make test-swift` verdes, e `git diff --cached` sem segredo,
dado real nem arquivo gerado. As pastas não rastreadas que já existiam
(`docs/SESSAO_2026-10-08_REDESENHO_3.0.md`, `docs/design/telas/arquivo-2.x/`,
`docs/research/agent-device/`, `docs/status/`) não entram em commit.

## Decisões tomadas pelo orquestrador (revisáveis pelo dono)

- **D-A.** Fluxo cancelado volta ao estado ocioso (`.idle`) com a linha `STOP`
  no log; não nasce caso novo em `RunState`.
- **D-B.** `flow.step` e `cancelled` em `flow.finished` entram no contrato
  (aditivos). Resolve a decisão 1 pendente desde 14/10.
- **D-C.** Log do motor em disco: arquivo 0600, pasta 0700, rotação, redação
  de URL e sem texto digitado. Linha de política em `docs/SEGURANCA.md`.
  Log é diagnóstico, não estado: não precisa de ADR.
- **D-D.** O motor não sobe Appium próprio quando `APPIUM_URL` aponta para fora
  de loopback ou para a porta 0 (o harness de QA usa `http://127.0.0.1:0`).
- **D-E.** O log bruto do CFNetwork em disco ignora `MOBAILE_REDACT=0`: o
  opt-out vale para a tela, não para o arquivo.

## MEL-2 · Bytecode fora do bundle assinado (PLAT-2)

Problema verificado no app instalado: 8 pastas `__pycache__` dentro de
`Contents/Resources/engine` e `codesign --verify --deep --strict` com "a sealed
resource is missing or invalid". Dois escritores: o motor subido pelo app
(`apps/MoBaile/Sources/MoBaile/Engine/EngineClient.swift:109-119`) e o handshake
do `tools/verify_native_app.sh:151`, que roda depois de o selo ser conferido.

- `EngineClient.swift`: `environment["PYTHONPYCACHEPREFIX"] =
  ~/Library/Caches/Mo baile/pycache` (variável, não `-B`: assim o cache continua
  existindo fora do bundle e os filhos `sys.executable -m …` herdam).
- `tools/verify_native_app.sh:151`: `PYTHONDONTWRITEBYTECODE=1` no handshake;
  ao fim, `codesign --verify --deep --strict` no app instalado, falhando o
  verify se o selo estiver quebrado.
- `tools/setup/instalar-mac.sh`, se roda o motor do bundle, recebe o mesmo
  tratamento.
- **Aceite:** XCTest em `EngineClientTransportTests` sobe o motor falso a partir
  de uma raiz temporária, para, e afirma que não há `__pycache__` na raiz (falha
  hoje). Depois do `make update-native`, `codesign --verify --deep --strict`
  passa no app instalado, mesmo após abrir e fechar o app.

## MEL-1 · Appium só em 127.0.0.1 (SEG-1)

Verificado: Appium 3.2.2 escuta por padrão em `0.0.0.0`
(`@appium/schema/.../appium-config-schema.js:26`); o motor sobe com
`[binary, "--log-timestamp", "--local-timezone"]`
(`engine/src/mobaile/adapters/appium.py:134-135`), sem autenticação. Qualquer
máquina da mesma rede comanda o aparelho conectado.

- `appium.py`: `--address 127.0.0.1 --port <porta>`, com host e porta
  derivados de `settings.appium_url` (`parsed.port if parsed.port is not None`,
  nunca `or 4723`). Host fora de loopback ou porta 0 → não sobe servidor (D-D),
  devolve o mesmo erro de "Appium indisponível" que já existe.
- Nova função `logs_dir()` em `engine/src/mobaile/security/paths.py` (camada
  que adapters e services podem importar): `MOBAILE_LOG_DIR` ou
  `~/Library/Logs/Mo baile` no macOS (`~/.mobaile/logs` fora dele), criada com
  0700, recusando symlink. O log do Appium passa a ir para
  `logs_dir()/appium.log`, aberto com 0600 (`os.open` + `fchmod`, como
  `ios_cfnetwork.py:447-449`).
- **Aceite:** `test_appium.py` com `subprocess.Popen` falso: argv contém
  `--address 127.0.0.1` e `--port 4723`; com `APPIUM_URL=http://127.0.0.1:0` ou
  `http://10.0.0.5:4723`, `Popen` não é chamado. `logs_dir()` cria 0700 e
  respeita `MOBAILE_LOG_DIR`.
- Fica para o dono conferir (`VERIFY`): `lsof -nP -iTCP:8100 -sTCP:LISTEN` com o
  WDA de pé no simulador (o WDA e o MJPEG são subidos pelo Appium e o
  `--address` não os cobre).

## MEL-4 · Texto sensível fora do disco e dos logs (SEG-2, SEG-3)

- **(a)** `adapters/ios_cfnetwork.py:317-331` `_mask_block`: mascarar também a
  forma de dicionário (`"Set-Cookie" = (` com o valor nas linhas seguintes até
  `);`), com estado, para os mesmos nomes sensíveis da redação; e o arquivo em
  disco ignora `MOBAILE_REDACT=0` (D-E). Aceite: bloco com
  `"Set-Cookie" = (\n "sid=SEGREDO"\n);` não deixa `SEGREDO` no texto gravado,
  com e sem `MOBAILE_REDACT=0`.
- **(b)** `services/flows.py`: na subida do motor (ou no primeiro `flow.run`),
  apagar `flow_runner_*.py` órfãos em `secure_runtime_dir()` com mais de alguns
  minutos (o script embute o texto digitado e sobra após SIGKILL). O modo
  exportado (`output_path`) e a API usada pelo Tk (`apps/tk-legacy`) não mudam.
  Aceite: arquivo órfão antigo some; um recente (de execução em andamento) fica.
- **(c)** `adapters/adb.py:311-313`: não logar `exc` de `TimeoutExpired` (o
  `cmd` repete o texto); logar só o tipo e o tempo. Aceite: `assertLogs` com
  `TimeoutExpired([... "'SEGREDO'"], 5)` não contém `SEGREDO`.
- **(d)** `services/maestro_flow.py`: aplicar a máscara de `self._segredos` à
  mensagem do `FlowResult` (hoje `selector.describe()` pode repetir o valor de
  `${VAR}`). Aceite: flow com `SENHA=SEGREDO` e `assertVisible: ${SENHA}` num
  aparelho falso sem o elemento → `result.message` sem `SEGREDO`.

## MEL-3 · Progresso do fluxo e cancelado (M4 = CODE-1, QA-2, ARQ-1 fase A)

Hoje o front só avança com a regex `(?i)passo\s+(\d+)`
(`EngineSession.swift:1738-1741`), que só casa na linha de falha; parar vira
"FAIL" (`EngineSession.swift:1686`) porque `flow.finished` manda
`success: false` sem distinguir (`server.py:1840-1848`, `:1974-1979`).

**Contrato (aditivo):**

- Notificação nova `flow.step` `{index: int, total: int}`, emitida no início de
  cada passo de nível superior. `index` começa em 1. Sem `run_id` nesta versão
  (a trava `_flow_running` já impede duas execuções).
- `flow.finished` ganha `cancelled: bool` (sempre presente no motor novo; o
  front lê com `decodeIfPresent ?? false`). `success` continua
  `sucesso and not cancelado`.

**Motor:**

- O contrato interno é um callback `on_step(index, total)`, igual nos dois
  runners. O servidor não interpreta texto de log.
- Runner por subprocesso (`flows.py`): o script imprime, no início de cada
  passo, uma linha-marcador própria, antes e fora do `log()` com timestamp:
  `\x1emobaile.step {"index":i,"total":n}`. `FlowExecution.run` reconhece a
  linha que começa com `\x1emobaile.step `, chama `on_step` e **não** a repassa
  como `flow.log`. O `▶ [i/n] …` continua no log para leitura humana.
- Maestro (`maestro_flow.py`): `on_step` só no laço de topo de `run()`
  (`:717-720`), não em `_passo` (que também roda `onFlowStart`,
  `onFlowComplete` e subpassos de `runFlow`/`retry`). `total` = comandos de
  topo do YAML.
- `server.py`: um helper único `_notify_flow_finished(success, message,
  cancelled)` usado pelos dois caminhos (`flow.run` e `flow.maestro_run`); o
  `_remember` do Maestro continua onde está. `"flow.step"` em
  `contract.NOTIFICATIONS`; fixtures de `flow.step` e de `flow.finished` com
  `cancelled` por `make fixtures`; `docs/PROTOCOLO_RPC.md` atualizado.

**Front:**

- `EngineSession` trata `flow.step` (`currentRunStep = index`, guarda `total`)
  e apaga a regex, sem fallback (motor e front vão juntos no bundle).
- `cancelled == true` → `.idle` e linha `STOP` (D-A), nunca "FAIL".
- `FlowRunnerSheet` usa o `total` de `flow.step` para a barra; só move o
  destaque da lista de passos gravados quando a execução veio de `flow.run`
  (no `flow.maestro_run` mostra só `i/total`).

**Aceite:** pytest (`test_flows.py` / `test_rpc_contract.py`): `flow.run` com
runner real e aparelho falso emite `flow.step` 1..n, a linha-marcador não
aparece em `flow.log`, e `flow.stop` leva a `flow.finished.cancelled == true`;
Maestro emite só índices de topo. XCTest com `FakeEngine`: `flow.step
{index:2,total:3}` → `currentRunStep == 2`; `flow.finished
{success:false,cancelled:true}` → `runState == .idle`.

## MEL-5 · Log do motor em arquivo (PLAT-1 = M10 + A7, parte)

Hoje `server.py:2334-2340` só configura o stderr; o app aberto pelo Finder perde
tudo; `EngineClient.swift:162-171` decodifica o stderr por pedaço (descarta o
pedaço quando corta um caractere UTF-8) e diz no comentário que "vai para o
Console", o que é falso.

- Motor: `configure_logging()` (ao lado do `serve()`): mantém o stderr e soma
  `RotatingFileHandler` em `logs_dir()/engine.log` (0600; 1 MB × 3), um filtro
  que passa mensagens por `redact_url`, e `faulthandler.enable(<arquivo>)` com o
  descritor mantido aberto. Testes usam `MOBAILE_LOG_DIR`.
- `engine.hello` e `engine.info` ganham `log_path` (aditivo; fixture e
  PROTOCOLO_RPC).
- Front: o stderr do motor é lido por linha (buffer de `Data` cortado em `\n`,
  decodificado por linha), e o comentário falso sai. `os.Logger`
  (`subsystem: "com.qa.mobaile"`, `category: "engine"`) registra só o ciclo de
  vida do motor (subiu, caiu com código, caminho do log), sem duplicar o
  conteúdo do log. A mensagem de queda (`EngineError.swift:36-37`) cita o
  `log_path` conhecido, ou um texto genérico.
- `docs/SEGURANCA.md`: uma linha sobre o log (onde, permissão, rotação,
  redação, sem texto digitado). `docs/ARQUITETURA.md`: o lugar na tabela de onde
  cada coisa mora, se houver.
- **Aceite:** pytest: com `MOBAILE_LOG_DIR` em tmp, `configure_logging()` + um
  `logger.info` com URL que tem token → arquivo 0600, pasta 0700, token
  redigido. XCTest: o separador de linhas recebe `"á\n"` partido entre dois
  pedaços e devolve uma linha íntegra.

## MEL-6 · Escuta de Analytics que não morre e listas com teto (QA-4 + CODE-2 metade)

- Motor, `adapters/analytics_logcat.py`: o laço de `_stream_reader`
  (`:398-411`) ganha `try/except Exception` por linha (`logger.debug`, segue);
  `Popen` com `errors="replace"`; `_handle_device_line` valida
  `isinstance(payload, dict)`. Hoje uma linha JSON que não é objeto, ou um byte
  fora de UTF-8, mata a thread em silêncio e a escuta fica muda com a flag
  ligada.
- Front, `EngineSession.swift`: `trimTraffic()` também em `analytics.event`
  (`:1714-1716`); `runLog` com teto (5000 linhas, as mais antigas saem).
- Fora desta rodada: tirar os `await` do laço de notificações e inverter
  espelho/hierarquia (precisa de medição).
- **Aceite:** pytest no molde de `test_analytics_logcat.py:128-140`: stdout
  falso entrega `"1\n"` e depois uma linha válida (`source="ios_device"`) → o
  evento válido chega. XCTest: 1001 `analytics.event` → lista com o teto; 5001
  `flow.log` → `runLog.count == 5000`.

## Release (orquestrador)

Depois das seis: versão 3.12.0 (`python3 tools/version.py bump minor`),
CHANGELOG, `make fixtures`, commit `chore(release): 3.12.0`, tag local,
`MELHORIAS.md` e `COMO-TESTAR.md`, `make update-native` com o app fechado.
Sem push.

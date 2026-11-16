# Contrato entre o motor e o front

JSON-RPC 2.0, uma mensagem por linha, sobre stdin e stdout do processo do motor.

O front sobe o motor assim:

```bash
PYTHONPATH=engine/src python3 -m mobaile.rpc
```

O stdout carrega só protocolo. Log vai para stderr. Misturar os dois quebraria
o enquadramento, e é por isso que o motor configura o logging para stderr
explicitamente.

## Requisição e resposta

```json
{"jsonrpc":"2.0","id":1,"method":"hierarchy.dump","params":{}}
{"jsonrpc":"2.0","id":1,"result":{"count":42,"elements":[...]}}
```

## Notificação

Mensagem sem `id`, empurrada pelo motor. A interface não faz polling.

```json
{"jsonrpc":"2.0","method":"stream.frame","params":{"format":"jpeg","image_base64":"...","width":900,"device_id":"emulator-5554",...}}
```

| Notificação | Quando chega |
|---|---|
| `stream.frame` | Um quadro novo, apenas quando a tela mudou. `device_id` diz de qual aparelho ele veio; quadro capturado antes de uma troca de aparelho não é emitido. Desde a 3.6 traz `format` (`jpeg`, o padrão, ou `png`) e `image_base64`; `png_base64` continua presente só quando o formato é PNG. No iOS, com o MJPEG do WebDriverAgent no ar (porta `WDA_MJPEG_PORT`, padrão 9100), o motor pede ao WDA quadros reduzidos (`mjpegScalingFactor`) para caberem no `max_width` e repassa o JPEG sem reencodar; se ainda vier maior, reduz e reencoda |
| `stream.settled` | A tela parou de mudar. É o momento certo de reler a hierarquia |
| `proxy.event` | Uma requisição HTTP foi observada |
| `analytics.event` | Um evento de tagueamento foi capturado |
| `device.changed` | Um alvo foi conectado ou desconectado. `device_id` nulo significa que sumiu. Não é emitida pela escolha manual (`session.select_device`) nem ao ligar o vigia com um alvo já escolhido: só a chegada e a saída de um alvo geram a notificação (3.5.2) |
| `home.changed` | O que a tela Início mostra mudou: aparelho chegou ou saiu (`reason: "device"`), ou um recente entrou ou saiu (`"recent"`). A interface relê `home.summary`; não há polling (3.11.0) |
| `passive.step` | A escuta passiva transformou um toque no aparelho em passo gravado. Mesmo formato de `codegen.record` |
| `passive.skipped` | Um toque no aparelho não virou passo, com `x`, `y` e o motivo |
| `passive.text` | O texto digitado num campo foi lido e guardado no último passo de entrada |
| `flow.log` | Uma linha de saída da execução do fluxo |
| `flow.step` | Começou um passo de nível superior do fluxo: `{index, total}`, com `index` a partir de 1. Vale para `flow.run` (cada passo gravado) e `flow.maestro_run` (cada comando de topo do YAML; `onFlowStart`, `onFlowComplete` e os subpassos de `runFlow`/`retry` não contam). Sem `run_id`: a trava de execução já impede duas ao mesmo tempo (3.12.0) |
| `flow.finished` | A execução do fluxo terminou, com `success`, `message` e `cancelled`. `cancelled` é `true` quando a execução parou por `flow.stop` (ou encerramento do motor); nesse caso `success` é sempre `false`, então quem não lê `cancelled` continua sem contar a parada como aprovada. `cancelled` existe desde a 3.12.0: front que fala com motor anterior trata a ausência como `false` |
| `run.log` | Uma linha do console da execução do projeto do dono (`run.start`): `{run_id, line}`. A linha já vem mascarada (segredos literais das configs, constantes de nome sensível dos arquivos de config, usuário e senha de URLs com o `Basic` em base64 deles, e valores das `envs` da run configuration viram `***`, também nas formas URL-encoded e com `\\` de `repr`), sem cores ANSI e cortada em 4.000 caracteres com `…`. O front guarda as últimas 5.000 (3.23.0) |
| `run.finished` | A execução do projeto terminou: `{run_id, status, counts, exit_code, folder, video, video_warning, message, duration_s}`. Ver `run.start` (3.23.0) |
| `perf.profile` | O perfil de desempenho efetivo mudou. Mesmo formato de `perf.status`. Ver "Perfis de desempenho" |
| `$/progress` | Andamento de um método longo. Ver "Progresso" |

## Erros

Códigos padrão do JSON-RPC para problemas de protocolo. A faixa `-32000` é
reservada a erro de domínio, e o campo `data.code` carrega o código estável que
a interface usa para decidir entre exibir diálogo e apenas registrar.

```json
{"jsonrpc":"2.0","id":7,"error":{
  "code":-32000,
  "message":"Coordenada x fora da faixa: -1",
  "data":{"code":"invalid_input","message":"Coordenada x fora da faixa: -1"}}}
```

| `data.code` | Significado |
|---|---|
| `invalid_input` | Entrada recusada na validação, antes de tocar em qualquer processo |
| `tool_not_found` | Binário externo obrigatório ausente (adb, scrcpy, xcrun) |
| `device_not_found` | O alvo pedido não está na lista ativa |
| `device_not_ready` | O alvo existe, mas está `offline` ou `unauthorized` |
| `adapter_error` | Falha ao conversar com ferramenta externa |
| `engine_error` | Falha prevista sem categoria mais específica |
| `incompatible_protocol` | O front e o motor falam versões diferentes do contrato. Ver "Versão do protocolo e handshake" |
| `file_changed` | O arquivo mudou no disco depois do `workspace.read` (outro editor gravou, ou ele sumiu). Ver "Árvore Projeto" |
| `request_cancelled` | O cliente cancelou a requisição. Vem com o código `-32800`, e não `-32000`. Ver "Cancelamento" |
| `project_not_trusted` | `run.start` de um projeto que o dono ainda não marcou como confiável. O front abre o diálogo "Confiar neste projeto?" (interpretador, arquivo de entrada e pasta de trabalho, de `project.inspect`) e repete o pedido com `trusted: true` (3.23.0) |
| `device_busy` | O aparelho está ocupado por outra execução: o projeto do dono (`run.*`) ou um flow. A mensagem diz qual projeto, para o front mostrar como está (3.23.0) |
| `hub_unknown` | `run.start` de um projeto cujo hub a análise não prova local (`hub_state: "unknown"`: hub montado em tempo de execução, config não encontrada, mais de um `init` ativo, `init` dentro de if/try ou recebendo variável). O front confirma com o dono que a execução é local e repete o pedido com `allow_unknown_hub: true` (B1-5) |

## Versão do protocolo e handshake

`PROTOCOL_VERSION = 2`. A versão 1 é o contrato anterior, sem handshake.

O front chama `engine.hello` antes de qualquer outra coisa:

```json
{"jsonrpc":"2.0","id":1,"method":"engine.hello","params":{"protocol_version":2,"client":"MoBaile/0.1"}}
{"jsonrpc":"2.0","id":1,"result":{
  "protocol_version":2,
  "engine_version":"0.1.0",
  "capabilities":["cancel","progress","lanes"],
  "methods":{"hierarchy.dump":{"lane":"capture","timeout_s":60,"progress":true}, "...":{}},
  "notifications":["stream.frame","stream.settled","$/progress","..."],
  "log_path":"/Users/qa/Library/Logs/Mo baile/engine.log"}}
```

- Se `protocol_version` do cliente for diferente da do motor, o motor responde
  erro `-32000` com `data.code = "incompatible_protocol"` e uma mensagem que
  cita as duas versões. O front mostra essa mensagem e não segue conectando.
- `methods` é a tabela declarativa do motor (`mobaile/rpc/contract.py`), a
  mesma que decide a fila de cada método. `timeout_s` é o tempo que o front deve
  esperar antes de desistir da chamada, **contado do envio e incluindo o tempo
  que o pedido passa na fila** atrás de outros do mesmo domínio. O front usa esse
  valor, e não uma tabela própria: há uma fonte de verdade só.
- `log_path` é o arquivo de log deste motor (`engine.log` na pasta de
  `logs_dir()`, 0600, rotação de 1 MB × 3, URLs redigidas), ou `null` quando a
  pasta de logs não pôde ser usada e o motor subiu só com o stderr. O front o
  cita na mensagem de queda. Campo aditivo, sem mudar a versão do protocolo; o
  `engine.info` traz o mesmo campo.
- `engine.hello` não é obrigatório para o motor atender. Clientes antigos, o
  harness de QA e a interface Tk continuam funcionando sem ele.

## Concorrência

O motor lê o stdin numa thread e despacha cada requisição para uma **fila
serial por domínio**. Uma chamada lenta numa fila não atrasa as outras filas.

| Fila | Para quê | Métodos |
|---|---|---|
| `inline` | responde na própria thread de leitura, sempre em milissegundos | `engine.hello`, `engine.shutdown`, `$/cancelRequest` |
| `fast` | interação e estado; nada ali passa de uns 2 s | o padrão: `input.*`, `stream.*`, `perf.*`, `codegen.*`, `session.*`, `devices.watch_*`, `hierarchy.element_at`, `engine.info`, `scrcpy.*`, `recording.status`, `passive.status`, `run.status` |
| `capture` | leitura de tela e árvore, que pode levar segundos, e a escuta passiva | `hierarchy.dump`, `screen.capture`, `screen.size`, `passive.start`, `passive.stop` |
| `services` | serviços de fundo que o motor liga e desliga | `proxy.*`, `analytics.*` (menos `analytics.ios_devices`), `flow.*`, `recording.start`, `recording.stop`, `run.start`, `run.stop` |
| `query` | consultas ao ambiente, que levam segundos mas nunca minutos | `devices.list`, `wda.status`, `simulators.list`, `emulators.list`, `diagnostics.check`, `setup.check`, `home.summary`, `analytics.ios_devices` |
| `environment` | preparo de ambiente, que pode levar minutos | `wda.start`, `simulators.boot`, `simulators.shutdown`, `emulators.boot` |
| `report` | aba Relatório: ler spec e log, auditar, gravar arquivos e OCR dos prints. Não toca aparelho | `report.spec`, `report.audit`, `report.export`, `report.import`, `report.checklist_export` |
| `project` | aba Execução lendo o projeto de automação do dono: registro, análise estática e doctor. Só o doctor roda o Python do projeto, e só depois de o dono confiar nele (3.23.0) | `project.open`, `project.list`, `project.forget`, `project.inspect`, `project.configure`, `project.trust`, `project.doctor` |

`passive.start` e `passive.stop` dividem a fila para o `stop` nunca passar na
frente de um `start` em andamento. Como o prazo conta a fila, um pedido que
estoura esperando sai dela sem efeito; por isso cada `*.stop` fora da fila
rápida tem prazo maior que o pior caso de quem pode estar na frente dele, e
perder um `stop` não deixa escuta, proxy, fluxo ou gravação ligados.

Garantias:

- Dentro de uma fila, a ordem de chegada é a ordem de execução.
- Entre filas, as respostas podem chegar fora de ordem. O cliente casa
  resposta e pedido pelo `id`.
- Uma notificação emitida por um método antes de ele terminar chega antes da
  resposta desse método.
- `engine.shutdown` responde em menos de 2 s em qualquer estado, mesmo com
  `wda.start` em andamento.
- Encerramento: depois de `engine.shutdown`, do fim do stdin ou de SIGTERM, as
  filas têm até 2 s para terminar o que já tinham; pedido que ainda não
  começou depois disso não roda. Em seguida o desmonte roda até o fim, uma vez
  só, e nenhum SIGTERM o interrompe: o primeiro só pede a parada, os seguintes
  são ignorados. O front que quer o desmonte completo espera o processo sair.
- Estado de sessão (`platform`, `device_id`, `current_xml`) é protegido por
  lock. Trocar de aparelho incrementa uma época de sessão, e um resultado lento
  que chega depois da troca não sobrescreve o estado do aparelho novo.

## Cancelamento

Notificação do cliente para o motor, no modelo do LSP:

```json
{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":7}}
```

- Pedido ainda na fila: sai da fila e recebe erro.
- Pedido em execução: recebe o erro na hora, e o resultado que vier depois é
  descartado. Métodos longos checam o cancelamento entre etapas e param cedo
  quando conseguem.
- Pedido já respondido ou `id` desconhecido: ignorado.

O erro de cancelamento usa o código do LSP:

```json
{"jsonrpc":"2.0","id":7,"error":{"code":-32800,"message":"Requisicao cancelada.",
  "data":{"code":"request_cancelled","message":"Requisicao cancelada."}}}
```

O front manda `$/cancelRequest` sozinho quando o `timeout_s` de uma chamada
estoura, e então falha a chamada com erro de timeout.

## Progresso

Uma requisição pode levar `progress_token` (texto ou número) em `params`.
Métodos com `"progress": true` no contrato emitem, enquanto trabalham:

```json
{"jsonrpc":"2.0","method":"$/progress","params":{"token":"wda-1","message":"Compilando o WebDriverAgent","percent":null}}
```

`percent` é número de 0 a 100 ou `null` quando não há como medir. Sem
`progress_token`, nada é emitido.

## Métodos

### Sessão e diagnóstico

| Método | Parâmetros | Devolve |
|---|---|---|
| `engine.hello` | `protocol_version`, `client` | versão do contrato, versão do motor, capacidades, tabela de métodos e notificações, `log_path` |
| `engine.info` | — | versão, plataforma, caminhos, disponibilidade de adb e scrcpy, estado do proxy, lista de métodos, `log_path` |
| `engine.shutdown` | — | `{stopped}` na hora; o desmonte roda depois que a resposta sai. Fim do stdin e SIGTERM encerram pelo mesmo caminho, sem interromper o desmonte |
| `session.select_device` | `platform`, `device_id` | plataforma e alvo em uso. Se o proxy estava configurado em outro aparelho Android, desfaz a configuração nele. O alvo escolhido fica fixo no vigia: a varredura seguinte não o troca pelo primeiro da lista, e não há `device.changed` redundante (3.5.2) |
| `session.correlate` | `step_num`, `before_s` (padrão 1), `after_s` (padrão 4) | requisições (`requests`, ids de `proxy.event`) e eventos de analytics (`events`, ids de `analytics.event`) cuja hora cai na janela do passo: de `recorded_at - before_s` até `recorded_at + after_s` ou até o `recorded_at` do passo seguinte, o que vier antes. `window` é `[início, fim]` em epoch; `probable` é sempre `true` (atribuição por tempo, não causal). Todos os carimbos são do relógio do Mac na recepção. Passo inexistente ou sem hora: `invalid_input` (3.6) |
| `devices.list` | `platform` | alvos conectados |
| `devices.watch_start` | `poll_interval` | liga a detecção automática. Parte do alvo já escolhido na sessão, se houver; se ele não estiver conectado, a primeira varredura elege outro ou avisa que sumiu |
| `devices.watch_stop` | — | desliga. Idempotente |

### Ambiente e inicialização

| Método | Parâmetros | Devolve |
|---|---|---|
| `diagnostics.check` | — | estado medido do ambiente nas duas plataformas, com detalhe e ação sugerida por checagem |
| `setup.check` | — | o que está instalado (tela Ambiente; até a 3.10.0, tela Início): `system`, `python` (`version`, `path`), `groups` (`motor`, `android`, `ios`, `extras`, cada um com `components`: `id`, `label`, `state`, `detail`, `required`, `install` = alvo de `tools/setup/instalar-mac.sh`, `link`, `needed_for`), `features` (`page_objects`, `network`, `analytics`, `report`, com o estado por plataforma), `pending` (obrigatórios que faltam) e `next_step`. Só procura arquivos: responde em décimos de segundo. Desde a 3.10.0 |
| `home.summary` | — | o que a tela Início mostra (3.11.0). `state`: `first_run` (nenhuma plataforma utilizável) ou `daily`. `python` como no `setup.check`. `environment`: `ready` e `total` (só obrigatórios, das plataformas que contam) e `pending` (`id`, `title`, `install`, `link`, `blocks`: `area` — `*` é a plataforma inteira —, `platform`, `effect`). `platforms`: cartões da Primeira vez (`platform`, `ready`, `found`, `missing`, `install`, `link`). `suggested_platform`. `targets`: até 6 alvos (`id`, `name`, `platform`, `kind` = `simulator`, `emulator` ou `physical`, `running`, `connected`, `capabilities` com `mirror`, `tap`, `record`, e `blocked_by` com ids de `pending`). `recent`: até 20 itens dos últimos 30 dias (`kind` = `flow`, `maestro`, `report` ou `page_object`, `title`, `subtitle`, `path`, `at` em epoch), guardados em `~/Library/Application Support/Mo baile/recentes.json` (`MOBAILE_DATA_DIR` troca a pasta). O motor não confere se o arquivo ainda existe. `whats_new`: `{version, items}` da seção da versão no CHANGELOG embutido, ou nulo |
| `home.forget_recent` | `path` | `{removed}`. Tira o item dos recentes; a interface chama quando reabrir falha porque o arquivo sumiu (3.11.0) |
| `simulators.list` | — | todos os simuladores instalados, ligados ou não, com os ligados primeiro |
| `simulators.boot` | `udid`, `open_app` | liga o simulador e traz a janela do Simulator para a frente. Sem `udid`, escolhe o primeiro (preferindo um já ligado) |
| `simulators.shutdown` | `udid` | desliga |
| `emulators.list` | — | AVDs do Android |
| `emulators.boot` | `name` | liga um AVD. Sem `name`, usa o primeiro |
| `wda.status` | — | estado do WebDriverAgent e do servidor Appium |
| `wda.start` | `udid`, `platform_version` | pede ao Appium que suba o WDA. Sem `udid`, usa o simulador ligado |

### Gravação de tela

| Método | Parâmetros | Devolve |
|---|---|---|
| `recording.start` | — | grava o vídeo do alvo ativo: caminho do arquivo, plataforma e limite em segundos |
| `recording.stop` | — | encerra e devolve caminho, tamanho e duração. Idempotente |
| `recording.status` | — | se há gravação em andamento |

### Tela e hierarquia

| Método | Parâmetros | Devolve |
|---|---|---|
| `screen.capture` | `max_width` | PNG em base64, com dimensões de origem e de saída, e o `device_id` do aparelho capturado |
| `screen.size` | — | resolução real do alvo |
| `hierarchy.dump` | `force` (opcional) | árvore de acessibilidade já normalizada entre Android e iOS (usa cache <1.2s se recente) |
| `hierarchy.element_at` | `x`, `y` | menor elemento que contém o ponto |

### Interação

| Método | Parâmetros | Devolve |
|---|---|---|
| `input.tap` | `x`, `y` | `{ok}` |
| `input.text` | `text` | `{ok}` |

### Espelho

| Método | Parâmetros | Devolve |
|---|---|---|
| `stream.start` | `fps`, `max_width`, `format` (`jpeg` padrão ou `png`), `quality` (JPEG, 10–95), `idle_fps` (cadência com a tela parada; `0` desliga). O que não vier sai do perfil de desempenho (completo: 6 fps, 900 px, 80, 2) e acompanha as trocas de perfil com o espelho ligado | confirma o início; devolve `fps`, `max_width`, `format`, `quality`, `idle_fps`, `profile` e `source` (`wda_mjpeg` quando o espelho iOS vem do MJPEG do WDA, `capture` quando vem de `simctl`/`screencap`). Formato inválido: `invalid_input` |
| `stream.stop` | — | idempotente |
| `stream.stats` | — | quadros capturados, emitidos, descartados, fps medido |
| `stream.pause` | — | para de capturar sem desligar o espelho (janela oculta, coberta ou minimizada). Vale também para o espelho que ligar depois, até o `stream.resume`. Durante `flow.run`, `flow.maestro_run` ou a escuta passiva o espelho continua, e a pausa passa a valer quando eles terminam. Devolve `{running, paused, kept_for}`: `kept_for` é `flow`, `passive` ou nulo. Idempotente |
| `stream.resume` | — | volta a capturar e reenvia o quadro atual mesmo se a tela não mudou. Devolve `{running, paused, kept_for}`. Idempotente |
| `scrcpy.start` | `fps`, `max_size`, `title`, `always_on_top` | inicia janela nativa a 60 FPS com baixíssima latência |
| `scrcpy.stop` | — | encerra o espelhamento scrcpy |
| `scrcpy.status` | — | `{available, running}` |

### Rede e tagueamento

| Método | Parâmetros | Devolve |
|---|---|---|
| `proxy.start` | `configure_device` | estado do proxy e se o aparelho aceitou a configuração |
| `proxy.stop` | — | desfaz também a configuração de proxy no aparelho em que `proxy.start` a ligou, mesmo que a sessão tenha trocado de aparelho |
| `proxy.events` | `limit` | histórico recente |
| `proxy.clear` | — | limpa o histórico |
| `proxy.diagnose` | — | "por que não vejo tráfego?": `proxy_running`, `device_configured` (Android com proxy ligado; `null` quando não se aplica), `netlog_running`, `platform`, `requests_total`, `tunnels_total`, `tunnels_failed` (túneis que o proxy não conseguiu conectar), `tunnels_active` (abertos agora, ainda sem evento), `last_event_age_s` e `causes` (lista de `{code, title, detail, fix}`, da causa mais à menos provável; vazia quando nada aponta problema). Códigos: `proxy_stopped`, `ios_no_proxy_support`, `proxy_not_on_device`, `no_connections`, `tunnels_failing`, `only_tunnels`, `netlog_running_no_events`. Pinning não é diagnosticado: o proxy repassa o TLS sem abrir (ADR 0004), então o app vê o certificado real. Lê o aparelho pelo adb: fila `services` (3.6) |
| `netlog.start` | iOS: `udid` (opcional; sem ele, o primeiro iPhone confiado). Android: `device_id` (opcional; sem ele, o aparelho da sessão) | tráfego HTTPS do app em debug, sem proxy nem certificado, emitido como `proxy.event`. Escolhe pela plataforma da sessão. **iOS:** lê pelo cabo o log `CFNETWORK_DIAGNOSTICS` (o app roda com `CFNETWORK_DIAGNOSTICS=3` no scheme; corpo normalmente indisponível). **Android:** lê do `adb logcat` o log do `HttpLoggingInterceptor` do OkHttp (o build de debug precisa do interceptor; BASIC traz a linha, HEADERS os headers, BODY os corpos), funciona com o debugger do Android Studio conectado; sem aparelho na sessão, `device_not_found`. Devolve `running`, `device_id`, `raw_log` (iOS: caminho do arquivo de blocos brutos na pasta dos logs do motor, headers sensíveis sempre mascarados, `null` se a pasta for recusada; Android: `null`) e `source` (`cfnetwork` ou `okhttp_logcat`) |
| `netlog.stop` | — | para a leitura nas duas plataformas; devolve `running` |
| `analytics.start` | `package` (opcional), `ios_source` (iOS: `auto`, `simulator` ou UDID do iPhone) | começa a escutar o tagueamento; no iOS sem simulador, `auto` usa o iPhone conectado por cabo. Devolve `running`, `source`, `device_id` |
| `analytics.stop` | — | para de escutar |
| `analytics.events` | `limit` | histórico recente |
| `analytics.clear` | — | limpa o histórico |
| `analytics.ios_devices` | — | iPhones por cabo (`udid`, `name`, `ios_version`, `connection`, `problem` opcional) e `available` (pymobiledevice3 instalado) |

### Geração de código

| Método | Parâmetros | Devolve |
|---|---|---|
| `codegen.record` | `x`, `y`, `strategy` | nome da variável, linha do Page Object (`NOME = (AppiumBy.X, "valor")`), bloco da ação (`def` + `wait_to_be_visible(..., 15)` + `click(..., 2)` ou `send_keys`). A coordenada não entra no código: fica no passo, em `coords` |
| `codegen.steps` | — | passos gravados. Desde a 3.6 cada passo traz `recorded_at` (epoch do Mac na gravação; `null` em passo antigo), e `codegen.record`/`passive.step` trazem `step_num` e `recorded_at` do passo criado. Desde a 3.17.0 cada passo traz `anchor`: `{"id": …}` ou `{"text": …}`, um elemento estável e único da tela da gravação, perto do alvo e fora dele (nunca campo editável nem senha), ou `null` |
| `codegen.reset` | — | limpa a gravação |
| `codegen.save` | `key`, `directory`, `actions_code`, `locators_code` | grava `pages/<key>.py` e `locators/<key>.py` e devolve os caminhos. `directory` precisa ficar dentro de `~/Documents/Mo baile` (link simbólico e `..` resolvidos); fora dele, `invalid_input`. Grava os bytes do PyCharm: CR e CRLF viram LF, UTF-8 sem BOM, sem normalização Unicode, sem tirar espaço do fim nem forçar quebra final |

### Árvore Projeto (Page Objects)

Desde a PO-5 (rodada 2026-11-03). Só a pasta de trabalho `~/Documents/Mo baile`, e só `pages/`, `locators/` e `flows/`. `path` é relativo à pasta (`pages/tela.py`), sem `..`, sem link simbólico em nenhum nível, com extensão `.py`, `.yaml`, `.yml`, `.json`, `.txt` ou `.md`; fora disso, `invalid_input`.

| Método | Parâmetros | Devolve |
|---|---|---|
| `workspace.tree` | — | `{root, name, exists, nodes, truncated}`. Cada nó tem `name`, `path` e `kind` (`dir` ou `file`); pasta traz `children`, pastas primeiro e nomes em ordem alfabética. Ocultos e links simbólicos ficam de fora. `truncated` diz que algo ficou de fora: mais de 2.000 nós ou pasta além de 8 níveis. Pasta que não dá para ler vem com `children: []` e `error` (o motivo do sistema) |
| `workspace.read` | `path` | `{path, text, encoding, line_separator, bom, read_only, size, mtime_ns}`. `text` vem com LF; o separador original (`LF`, `CRLF` ou `CR`, o primeiro do arquivo) vai em `line_separator`. Arquivo que não é UTF-8 vem com `read_only: true`. `mtime_ns` é a hora de modificação lida, para o `write` detectar conflito. Acima de 1 MB (bytes), `invalid_input` |
| `workspace.write` | `path`, `text`, `line_separator?` (`LF`), `bom?` (`false`), `expected_mtime_ns?` | grava com o separador e o BOM pedidos (o front devolve os que leu) e devolve `{path, saved, bytes, mtime_ns}`. Com `expected_mtime_ns`, recusa com `file_changed` se o arquivo mudou ou sumiu desde o `read`; sem ele, sobrescreve. A gravação é atômica (temporário na mesma pasta + rename, sem seguir link simbólico) e mantém o modo do arquivo. Recusa com `invalid_input`: texto acima de 1 MB em bytes, arquivo que não é UTF-8, arquivo sem permissão de escrita e qualquer erro de disco (com o motivo do sistema) |

### Execução de fluxo

| Método | Parâmetros | Devolve |
|---|---|---|
| `flow.run` | `runner?`, `launch_app?` | roda os passos gravados no alvo ativo. No Android, por padrão (`runner: "locator"`, ou `MOBAILE_FLOW_RUNNER`), cada passo é procurado pelo localizador gravado, com as esperas do `flow.maestro_run`; passo sem localizador estável (`position`, xpath só com a classe, toque em área vazia) toca a coordenada gravada e diz isso no log; desde a 3.16.0 ele só toca quando o elemento sob o ponto tem a classe gravada (no prazo da busca, toca com aviso), e nenhuma tela com indicador de carregamento visível conta como assentada (até 5 s). Cada passo ganha no `flow.log` uma linha `sincronia:` com o tempo, as leituras e o motivo da espera; num flow que falha, as últimas telas lidas vão para `<logs>/flow-rastro/` (`MOBAILE_FLOW_TRACE` = `falha`, `sempre` ou `nunca`). Desde a 3.17.0 o passo com `anchor` espera a âncora aparecer antes de agir (opcional, até 5 s; depois de duas âncoras que não aparecem, as outras do flow não são esperadas, e o log não repete o texto da âncora), e `launch_app: true` abre o app gravado do zero (`stopApp` + `launchApp`, esperando o app em primeiro plano) antes do primeiro passo, sem contar como passo; `launch_app` que não é booleano dá `invalid_input`. `runner: "coordinates"` roda o script de coordenadas de antes, o único caminho no iOS por enquanto, e ignora `launch_app` com uma linha no `flow.log`. O texto digitado fica só em memória. Devolve `{running, steps, runner, script?}`, com `script` só no runner de coordenadas (3.15.0). O andamento chega por `flow.step`, `flow.log` e `flow.finished` |
| `flow.stop` | — | pede a interrupção após o passo atual. Idempotente |
| `flow.status` | — | `{running, cancelled}` |
| `flow.maestro_check` | `yaml` ou `path`, `env?` | valida um flow no formato do Maestro sem tocar o aparelho: `{valid, app_id, name, tags, steps}`. Comando fora do subconjunto suportado, JavaScript e comandos de IA/nuvem dão `invalid_input` com o motivo |
| `flow.maestro_export` | `app_id?`, `name?`, `save?` | os passos gravados como flow do Maestro: `{yaml, variables, steps, path?}`. Texto digitado não vai para o YAML: vira `${VARIAVEL}`, listada em `variables`. Passo com âncora por id ganha antes um `extendedWaitUntil` opcional de 5 s por ela (3.17.0). Âncora por texto não vai para o arquivo, porque um texto da tela pode ser dado pessoal, e âncora que contém um texto digitado fica de fora. Com `save`, grava em `~/Documents/Mo baile/flows/` sem sobrescrever |
| `flow.maestro_run` | `yaml` ou `path`, `env?` | roda o flow no alvo ativo com as esperas do Maestro (elemento até 17 s, 7 s se `optional`; hierarquia assentada após cada ação). Divide trava, `flow.stop`, `flow.step`, `flow.log` e `flow.finished` com `flow.run`. Devolve `{running, app_id, name, tags, steps}` |

O formato e o que fica de fora estão em
[research/maestro-modelo-de-automacao.md](research/maestro-modelo-de-automacao.md).
Ler YAML pede o PyYAML no Python do motor; sem ele, os três métodos devolvem
`invalid_input` explicando o que instalar, e o resto do motor segue igual.

### Perfis de desempenho

Três perfis, `completo`, `equilibrado` e `leve`, mais a preferência `auto`, que
escolhe entre eles. A política mora no motor (`services/perf.py`); o front manda
os sinais do Mac e aplica a parte visual (`knobs.glass`, `knobs.animations`). O
motor aplica a dele no que estiver ligado: cadência, largura e qualidade do
espelho que o chamador não fixou no `stream.start`, intervalo do vigia de
aparelhos sem `poll_interval` pedido, e quanto do corpo de cada requisição
nova o proxy guarda. O leve reduz apresentação e cadência, nunca captura: todo
`proxy.event` e `analytics.event` continua saindo, e o histórico já capturado
de rede (2.000) e analytics (5.000) tem o mesmo teto em todos os perfis.

Regras: o sinal do sistema piora o perfil na hora; a melhora espera 60 s com o
alvo melhor e sobe um degrau por vez (`reason: "recuperando"` no degrau do
meio); a escolha manual vale na hora e ganha do automático, exceto com
`thermal: "critical"`, que leva ao leve em qualquer preferência.

| Método | Parâmetros | Devolve |
|---|---|---|
| `perf.signals` | qualquer subconjunto de `thermal` (`nominal`, `fair`, `serious`, `critical`), `low_power` (bool), `memory_pressure` (`normal`, `warning`, `critical`), `physical_memory_gb` (número), `arch` (`arm64`, `x86_64`), `translated` (bool, Rosetta). Campo ausente fica como estava | o status. Prazo de 5 s: sem resposta, o front aplica sozinho a parte visual do leve |
| `perf.set_preference` | `preference`: `auto`, `completo`, `equilibrado` ou `leve` | o status |
| `perf.status` | — | `{profile, reason, preference, knobs, signals, history_full, improving}`. `history_full` (`{proxy, analytics}`) diz se o histórico já passou do teto e está descartando o mais antigo (o motor também avisa no log); `analytics: true` significa que uma auditoria da sessão não vê o começo. `reason`: `manual`, `sinais_normais`, `recuperando`, `thermal_fair`, `thermal_serious`, `thermal_critical`, `low_power`, `memory_warning`, `memory_critical` ou `hardware_modesto` (até 8 GB, Intel ou Python sob Rosetta). `knobs`: `stream_fps`, `stream_idle_fps`, `stream_max_width`, `stream_quality`, `stream_capture_jpeg`, `poll_interval`, `proxy_body_capture_kb` (256, 128 ou 64; só vale para capturas novas), `glass`, `animations` |

Entrada inválida é `invalid_input`. Sem o front mandar nada, o motor fica em
`completo` com os valores de antes (6 fps, 900 px, JPEG 80, vigia a 1,5 s).

### Escuta passiva

| Método | Parâmetros | Devolve |
|---|---|---|
| `passive.start` | — | liga a gravação do que é feito direto no aparelho. Os passos chegam por `passive.step`. No iOS responde erro (`adapter_error`) quando o Python do motor não tem o `pyobjc-framework-Quartz`; antes respondia `listening: true` sem ouvir nada (3.5.2) |
| `passive.stop` | — | desliga. Idempotente |
| `passive.status` | — | `{listening}` |

### Relatório de tagueamento

Auditoria do tagueamento contra a spec do Figma, com o núcleo do `tag_audit`
(ver [ADR 0003](adr/0003-relatorio-tagueamento.md)). Caminhos são absolutos ou
com `~`; o motor normaliza, confere tipo e tamanho (spec até 5 MB, log até
64 MB) e recusa com `invalid_input` antes de abrir o arquivo.

| Método | Parâmetros | Devolve |
|---|---|---|
| `report.spec` | `path` (spec-modelo `.json`) | resumo da spec: `path`, `projeto`, `versao_especificacao`, `plataforma`, `prints_dir`, `prints_dir_exists`, `fluxos` (lista ordenada de `{key, label}`), `cards`, `variants`, `sections` |
| `report.audit` | `spec_path`, `source` (`session`: eventos que a escuta de Analytics capturou; `file`: um log), `log_path` (com `file`), `platform` (opcional; sem ele, a da spec) | `spec` (resumo), `platform`, `source`, `log_path`, `log_stats` (`total_lidos`, `da_plataforma`, `duplicados`, `uteis`), `summary` (`total`, `ok`, `divergent`, `missing`, `compliance_rate`, `extras`, `alerts`), `results` (uma por variação: `id`, `card_index`, `section`, `card_title`, `print_path`, `flow`, `flow_label`, `event`, `variation`, `status` = `ok`, `error` ou `missing`, `checks` com `field`, `expected`, `obtained` e `ok`, `expected` (o que a variação espera, já com o fluxo aplicado: lista ordenada de `{key, value}` em texto; na não disparada é a única fonte dos valores), `matched` com `id`, `time`, `event_name` e `params`, `occurrences`, `older_divergent`, `older_divergences`, `ga_screen`, `note`, `divergences`, `block`), `extras` e `alerts` (`event`, `screen`, `flow_name`, `component`, `detail`, `count`), `observations`, `markdown` e `tsv`. Guarda o relatório para `report.export` |
| `report.export` | `directory` (opcional; sem ele, `~/Documents/Mo baile/Relatórios/<projeto>-<plataforma>-<data>`), `info` (opcional: objeto com `versao`, `conta`, `cooperativa` e `codigo_usuario`, todos texto e opcionais; os preenchidos aparecem no topo do HTML, junto à plataforma e à data) | grava `board_auditoria.excalidraw`, `relatorio_<projeto da spec>_<ios|android>_<dd-mm-aaaa>.html`, `relatorio_auditoria.md` e `relatorio_auditoria.tsv` do último `report.audit`. Devolve `directory` e `files` (`kind`, `name`, `path`, `bytes`) |
| `report.import` | `prints_dir`, `projeto` (opcional), `platform`, `spec_path` (opcional; sem ele, `~/Documents/Mo baile/Specs/<projeto>.json`) | OCR local (Vision) dos prints dos cards e rascunho da spec, sem sobrescrever arquivo existente. Devolve `spec_path`, `review_path` (`.revisao.md`), `checklist_path` (`.checklist.md`: parâmetros esperados, dúvidas do OCR e um item por disparo a conferir), `spec` (resumo, ou `null` se o rascunho ainda não valida), `spec_error`, `review` (`print`, `event`, `doubts`) e `doubts_total` |
| `report.checklist_export` | `checklist_path` (o `.checklist.md`, até 2 MB) ou `spec_path` (a spec aberta: usa o `.checklist.md` ao lado dela ou gera um da spec; não precisa de log), `directory` (opcional; sem ele, a pasta do `.md`) | grava `checklist_<nome>_<dd-mm-aaaa>.html`: arquivo único e offline no padrão do design system, com o que estiver marcado `[x]` no Markdown. Devolve `path`, `name`, `bytes`, `total` e `done` (itens marcados) |
| `report.card` | `spec_path`, `card_index` (o `card_index` dos resultados, a partir de 0) | o card como está no JSON, para editar: `card_index`, `cards` (total), `secao`, `titulo`, `evento`, `print`, `params` (lista ordenada de `{key, value}`; `value` é o valor do JSON, texto ou não), `variacoes` (lista de listas de `{key, value}`), `obs` (texto, ou `null`), `obs_por_fluxo` (a `obs` é um objeto por fluxo e não vai para o formulário) e `params_por_fluxo` (chaves dos fluxos com parâmetros próprios) |
| `report.card_update` | `spec_path`, `card_index`, `card` com os campos do formulário (`secao`, `titulo`, `evento`, `params`, `variacoes`, `obs`, no formato de `report.card`; campo ausente fica como estava) | grava o card na spec e devolve `spec` (resumo relido) e `card` (como `report.card`). Muda só o que o formulário mostra: o print, `por_fluxo`, `params_por_fluxo`, uma `obs` por fluxo e chaves desconhecidas ficam. Texto vazio tira a chave do JSON; evento vazio, parâmetro sem nome ou repetido e expressão regular inválida respondem `invalid_input` sem gravar. A spec inteira é validada antes, e o arquivo é trocado de uma vez |
| `report.cards` | `spec_path` | todos os cards como estão no JSON, para o editor de spec: `path`, `projeto`, `spec_error` (`null`, ou a mensagem de validação com o card e o campo; um rascunho que ainda não valida também abre), `prints_dir` (absoluto, ou `null`), `fluxos` (`{key, label}` na ordem da spec) e `cards` (cada um no formato de `report.card`) |
| `report.cards_update` | `spec_path`, `cards` (lista de `{card_index, card}`, com o `card` de `report.card_update`; cada índice uma vez só) | aplica todas as edições juntas, valida a spec inteira uma vez e troca o arquivo de uma vez. Devolve `spec` (resumo relido) e os campos de `report.cards`. Lista vazia, índice repetido ou fora da spec e qualquer card inválido respondem `invalid_input` sem gravar nada |

`report.audit` com `source: "session"` e nenhum evento capturado responde
`invalid_input`: um relatório com tudo "não disparado" pareceria verdadeiro.

### Projeto de automação do dono (aba Execução)

Desde a 3.23.0 (B1, [contrato](melhorias/2026-11-12-execucao-projeto/CONTRATO.md)).
O dono escolhe a pasta do projeto que ele roda no PyCharm, e o motor mostra o
`main` resumido **sem importar nem executar nada**: `ast.parse` do arquivo de
entrada no processo do motor e `tokenize` para os `# init(...)` comentados.

Regras de leitura, iguais em todos os métodos:

- O motor **nunca grava na pasta do projeto**. O registro fica em
  `projetos.json`, no mesmo diretório de dados do `recentes.json`
  (`MOBAILE_DATA_DIR`, ou `~/Library/Application Support/Mo baile`), com
  gravação atômica.
- Só texto (`.py`, `.feature`, `.ini`, `.cfg`, `.toml`, `.txt` e `.xml` dentro
  de `.idea`), sem seguir link simbólico em nenhum nível, até 1 MB por arquivo
  e 200 arquivos por análise. `.env*`, `*.pem`, `*.p12`, keystores,
  `local.properties` e `google-services.json` nunca são abertos; `.venv`,
  `venv`, `.git`, `node_modules` e `__pycache__` nunca são lidos por dentro.
  Arquivo recusado, grande demais ou com erro de sintaxe vira item de
  `problems`, e não erro do método.
- Das configs sai o valor literal só de `platformName`, `automationName`,
  `udid`, `deviceName`, `platformVersion`, `app`, `appPackage`, `appActivity` e
  `bundleId` (com ou sem o prefixo `appium:`), e o `host:porta` da URL do hub
  (nunca usuário, senha nem caminho). Do resto sai **só o nome da chave**, em
  `keys`. Valor que não é literal (`os.environ[...]`, f-string, chamada) vem
  como `"dinâmico"`.
- Os **valores** das `envs` da run configuration nunca saem do motor: só os
  nomes, em `run_configuration.env_names`. `$PROJECT_DIR$` e `$USER_HOME$`
  valem dentro deles, como no PyCharm.
- **Nuvem falha fechada** (`hub_state`, B1-5). Por config: `cloud` quando
  qualquer URL literal da config, em qualquer chave, tem host fora do loopback,
  ou quando o nome da config ou um host contém `kobiton`; `unknown` quando a
  config não foi achada ou o valor de uma chave de hub (`url`, `hub`,
  `command_executor`…) é montado em tempo de execução (variável, concatenação,
  f-string); `local` no resto (config sem URL nenhuma conta como o Appium local
  padrão). Para a execução inteira: `cloud` se qualquer `init(...)` ativo
  possível for nuvem; senão `unknown` com qualquer dúvida (alguma config
  `unknown`, mais de um `init` ativo, `init` dentro de if/try/laço ou recebendo
  uma variável, nenhum `init`); senão `local`. `cloud: bool` continua, igual a
  `hub_state == "cloud"`.
- **Confiança presa ao que o diálogo mostrou** (B1-5). Confiar grava uma
  impressão de (pasta real, interpretador, entrada, pasta de trabalho, nomes
  das `envs`). Qualquer mudança, por `project.configure` ou por um `git pull`
  que mude `.idea`, zera `trusted` na próxima análise, com um item em
  `problems` dizendo o que mudou. A impressão fica no registro e não sai no RPC.

| Método | Parâmetros | Devolve |
|---|---|---|
| `project.open` | `path` (pasta do projeto, absoluta ou com `~`) | `{project}`: `id` (sha1 curto do caminho real; o mesmo projeto aberto de novo tem o mesmo id), `root` (caminho real), `name` (nome da pasta), `entry` (arquivo de entrada relativo à raiz, ou `null` quando não achou), `trusted` (se o dono já confirmou "Confiar neste projeto?" e nada do que roda mudou desde então), `opened_at` (epoch), `interpreter_override` e `entry_override` (o que o dono escolheu em `project.configure`, ou `null`; desde a B1-4). Reabrir só atualiza `opened_at` e mantém `trusted` e os overrides. Pasta que não existe ou arquivo: `invalid_input` |
| `project.list` | — | `{projects}`: lista no formato de `project`, o aberto mais recentemente primeiro (até 50) |
| `project.forget` | `project_id` | `{removed}`: `false` quando o id não estava na lista. Não apaga nada na pasta do projeto |
| `project.inspect` | `project_id` | o `main` resumido, sem executar nada. `project` (o item do registro); `entry` (`{file, function, found}`: o arquivo e a função que o `if __name__ == "__main__"` chama, ou `main_sem_args`); `interpreter` (`{path, source, exists, candidates}`. `source`, na ordem em que vale: `manual` (o `interpreter_override` de `project.configure`, que ganha de qualquer detecção); `run_configuration` (o `SDK_HOME` da run configuration do PyCharm em `.idea/runConfigurations/*.xml` ou no `RunManager` de `.idea/workspace.xml`, escolhida pelo `SCRIPT_NAME` igual à entrada); `pycharm_sdk` (o PyCharm guardou só o NOME do SDK, no `SDK_NAME` da run configuration ou no `project-jdk-name` de `.idea/misc.xml`, e o caminho saiu do `options/jdk.table.xml` das configurações do PyCharm em `~/Library/Application Support/JetBrains/PyCharm*/`, a versão mais nova primeiro, só leitura e com o parser de XML seguro; nome que não está lá vira item de `problems`); `venv` (`.venv/` ou `venv/` com `pyvenv.cfg`); ou `null` com `path: null`. `candidates` vem vazio quando há interpretador; sem nenhum, lista os Pythons desta máquina que existem (`/opt/homebrew/bin/python3`, `/usr/local/bin/python3`, `/usr/bin/python3` e os shims de pyenv e asdf), sem repetir o mesmo binário, cada um `{path, version, behave}` (`behave` = versão instalada ou `null`), lidos com `-E -c` e `importlib.metadata` numa pasta vazia, até 4 s cada, em paralelo e com cache de 2 min. Nada do projeto é executado); `working_dir` (o `WORKING_DIRECTORY` da run configuration, ou a raiz); `run_configuration` (`{name, file, env_names}` ou `null`); `active_config` (nome da config do primeiro `init(...)` ativo, ou `null`); `hub_state` (`local`, `cloud` ou `unknown`, da execução inteira) e `hub_reason` (o motivo quando não é `local`, senão `null`); `configs` (as ativas primeiro, todas as `init(...)` não comentadas, em ordem, com a variável trocada pela config quando é um apelido local, e depois as alternativas comentadas, na ordem do arquivo: `name`, `active`, `found`, `file`, `line`, `platform` (`android`, `ios` ou `null`), `values` (só as chaves permitidas, sem o prefixo `appium:`), `hub` (`host:porta` da chave de hub, ou da primeira URL quando nenhuma chave de hub tem uma; `"dinâmico"` ou `null`), `hub_state` (`local`, `cloud` ou `unknown`, regra acima), `cloud` (`hub_state == "cloud"`), `keys` (todos os nomes de chave, como estão no arquivo)); `suites` (as funções chamadas pelo main, em ordem: `name`, `defined`, `line` e `runs`, uma por `executar(squad, feature)`: `squad`, `feature`, `line`, `found`, `path` (onde achou, relativo à raiz, procurando em `features/`, `<squad>/`, `<squad>/features/` e na raiz), `title` e `scenarios` (nomes, lidos do `.feature` como texto, em inglês ou português)); `unused_suites` (funções que chamam `executar` mas o main não chama); `problems` (`{file, line, message}`). Projeto desconhecido ou pasta que sumiu: `invalid_input` |
| `project.configure` | `project_id`, `interpreter?` (texto ou `null`), `entry?` (texto ou `null`) | o mesmo que `project.inspect`, já com a escolha aplicada. O que o dono escolhe fica no registro (`interpreter_override`, `entry_override`) e ganha da detecção; `null` remove a escolha e volta para a detecção; parâmetro ausente fica como estava. `interpreter`: caminho absoluto, sem `..`, de um arquivo executável que existe (guardado como veio, sem resolver o link, para `.venv/bin/python` continuar sendo o venv). `entry`: `.py` relativo à raiz, dentro dela, sem link simbólico em nenhum nível e fora das pastas que o motor não lê. Fora disso, `invalid_input` e nada muda (B1-4) |
| `project.trust` | `project_id` | `{project}` (o item do registro, com `trusted: true`). Reanalisa o projeto e grava a impressão do que roda agora: interpretador, entrada, pasta de trabalho e nomes das `envs`. É o "Confiar neste projeto?" respondido; `run.start {trusted: true}` faz o mesmo. Projeto desconhecido: `invalid_input` (B1-5) |
| `project.doctor` | `project_id`, `device_id?` (o aparelho escolhido na barra Rodar; sem ele, vale o `udid` da config ativa), `progress_token?` | pré-requisitos, uma linha por checagem: `{project_id, checks, summary, ready, trusted}`. Cada item de `checks` é `{id, label, state, message, hint, needs_trust}`, com `state` = `ok`, `warn`, `fail` ou `skip`, `hint` (texto ou `null`) dizendo o que o dono faz e `needs_trust` (`true` quando a checagem foi pulada só porque o projeto ainda não é confiável). **Sem confiança, o doctor não roda o Python do projeto** (ele vem do `.venv` ou da run configuration, ou seja, é código do projeto): `interpreter` (se o arquivo existe; se não existe, ele falha como sempre), `packages`, `requirements` e `pip_check` vêm `skip` com `needs_trust: true` e a dica de confiar; o front oferece `project.trust` e roda o doctor de novo. `trusted` repete o estado da confiança. `summary` conta cada estado; `ready` é `true` quando nada falhou. Os `id` são estáveis e vêm sempre nesta ordem: `interpreter` (existe e responde; dá a versão do Python), `packages` (behave, pytest-bdd, Appium-Python-Client, selenium e allure-behave por `importlib.metadata`; falha sem behave nem pytest-bdd, avisa sem o Appium-Python-Client), `requirements` (`requirements.txt` da raiz × instalado; avisa o que falta e o `==` diferente), `pip_check` (`<python> -m pip check`, até 60 s), `appium` (instalado, versão e o driver da plataforma da config ativa), `appium_port` (alguém ouve no `host:porta` da config ativa, só loopback; diz se é o Appium do Mo baile; sem hub na config, usa `127.0.0.1:4723`), `device` (o aparelho da config está conectado e pronto; avisa quando `device_id` difere do `udid` da config e quando a `platformVersion` não bate com o aparelho), `app` (o arquivo de `app` existe, ou o `appPackage` está instalado: `pm list packages`), `uiautomation` (instrumentação de outra ferramenta segurando o UiAutomation, com o `force-stop` na dica), `cloud` (falha com `hub_state: "cloud"` ou sem `init` ativo; avisa com `"unknown"`, com o motivo) e `features` (todas as features dos `executar` encontradas). Checagem que depende de outra que não passou vem `skip`; com a config ativa na nuvem, as de porta e aparelho são puladas sem abrir conexão. **Nada instala, apaga ou reinicia**: o Python do projeto roda só `-E -c` com `importlib.metadata` e `-E -m pip check`, numa pasta vazia (um `json.py` do projeto nunca é importado) e sem as `envs` da run configuration; a saída dele passa pela mesma máscara do console antes de virar mensagem; e no aparelho só há leitura (`adb devices`, `getprop`, `pm list packages`, `dumpsys`). Emite `$/progress` uma vez por checagem e para entre elas quando a requisição é cancelada. `device_id` fora do formato: `invalid_input` |

#### Rodar o `main` (`run.*`)

O motor roda `[interpretador, entrada]` como a run configuration "Python" do
PyCharm faria: `cwd` na pasta de trabalho, `stdin` fechado, grupo de
processos próprio, ambiente = o do motor (sem o `PYTHONPATH` dele) + as `envs`
da run configuration + `PYTHONUNBUFFERED=1`, com a raiz do projeto na frente do
`PYTHONPATH` (o "Add content roots" do PyCharm). Sem `PYTHONPYCACHEPREFIX`, vai
`PYTHONDONTWRITEBYTECODE=1`, para nenhum `.pyc` cair na pasta do projeto. Uma
execução por vez, e nunca junto com `flow.run` ou `flow.maestro_run`.

**O resultado vem do resumo do behave, e não do código de saída**: o `main`
do dono engole exceção com `print(e)` e sai com 0 mesmo quando um cenário
falha. As linhas `N features passed, M failed…`, `… scenarios …` e `… steps …`
de cada chamada do behave são somadas.

| Método | Parâmetros | Devolve |
|---|---|---|
| `run.start` | `project_id`, `device_id?` (sem ele: o `udid` literal da config ativa, senão o aparelho da sessão), `record_video?` (`true`), `trusted?`, `allow_unknown_hub?` (`false`) | reanalisa o projeto primeiro (o que zera a confiança se algo mudou) e recusa com `project_not_trusted` quando ele não é confiável e `trusted` não é `true`; com `trusted: true`, marca o projeto como confiável, com a impressão do que vai rodar, e segue. `hub_state: "cloud"` é recusado sempre, com `invalid_input` citando a config e o host; `"unknown"` é recusado com `hub_unknown` a menos que venha `allow_unknown_hub: true`. Recusa também com `invalid_input` projeto sem `init` ativo, sem entrada ou sem interpretador, e `device_id` diferente do `udid` literal da config ativa (o teste roda no aparelho da config: travar e gravar outro deixaria o de verdade livre); e com `device_busy` quando já há execução, preparo de execução ou flow rodando. A trava do aparelho liga **antes** de fechar a sessão Appium do Mo baile naquele aparelho e a escuta passiva (o servidor Appium do Mo baile continua de pé). Devolve `{run_id, project_id, folder, device_id, platform, config, command, video, started_at}`: `folder` é a pasta da execução, `~/Documents/Mo baile/Execuções/<projeto>/<AAAAMMDD-HHMMSS>/` (`MOBAILE_RUNS_DIR` troca a raiz), com `console.log` (0600, até 50 MB), `video.mp4` e `resumo.json` (o `run.finished` mais `project`, `command`, `config`, `device_id`, `platform`, `started_at`, `video_started_at`, que é o epoch em que o vídeo começou de fato, ou `null` sem vídeo, `finished_at` e `lines`); `command` é `{interpreter, entry, working_dir}`; `video` é `{mode, warning}`, com `mode` = `scrcpy` (Android: `scrcpy -s <serial> --no-playback --no-window --no-audio --record=…`; o `run.start` espera o servidor do scrcpy anunciar o aparelho, `[server] INFO: Device: …`, até 5 s mais 0,2 s de folga, em vez de um tempo fixo; sem o anúncio, segue gravando e o aviso vai em `warning` e no `video_warning` do fim), `screenrecord` (Android sem scrcpy, para em 180 s; vem com aviso), `simctl` (simulador iOS, `--codec h264`) ou `null` (sem vídeo: `record_video: false`, sem aparelho alvo ou iPhone físico, com `warning` dizendo o motivo). O console chega por `run.log`, e o fim por `run.finished` |
| `run.stop` | — | SIGINT no grupo de processos, depois SIGTERM e SIGKILL (3 s, 3 s, 2 s): o processo e os netos param. O vídeo para com SIGINT, para o MP4 fechar. Devolve `{running, stopped, run_id}`; sem execução, `{running: false, stopped: false, run_id: null}`. Idempotente. `stopped: true` só quando o processo principal ainda rodava: aí `run.finished` chega com `status: "cancelled"`. Se ele já tinha saído (o motor ainda drenava a saída ou fechava o vídeo), os netos são encerrados, `stopped` vem `false` e o `status` continua o do resumo |
| `run.status` | — | `{running, run, last}`. `run` (com execução em andamento, senão `null`): `{run_id, project_id, project_name, device_id, platform, folder, started_at, elapsed_s, lines, video, stopping}`. `last`: o último `run.finished` deste motor, ou `null` |

`run.finished` traz `status`: `passed` (nenhuma falha e ao menos um cenário
passado), `failed` (algum `failed`, `error`/`errored` ou `undefined` em
qualquer resumo, ou uma linha `HOOK-ERROR in …` ou `CLEANUP-ERROR in …`: o
behave escreve "passed" no resumo quando um `after_all` ou uma limpeza falha,
mas sai com falha; `message` cita a linha), `indeterminate` (sem resumo
nenhum, por exemplo `init` que lança antes de qualquer cenário, com a última
linha de erro do console em `message`; palavra que o motor não conhece numa
linha de resumo; `ABORTED:` sem `run.stop`; ou menos resumos que as chamadas a
`executar` do main, que é suíte que não rodou) ou `cancelled` (`run.stop` com
o processo vivo, ou encerramento do motor). O resumo é lido da linha crua, e a
máscara vale só para o que sai. `counts` é `null` sem
resumo; senão `{features, scenarios, steps, summaries}`, cada tipo com
`passed`, `failed`, `skipped`, `undefined`, `errors` e `untested`, e
`summaries` = quantas chamadas do behave imprimiram resumo. `exit_code` é o
código do processo (negativo quando morto por sinal), só informativo. `video`
é o caminho do `video.mp4` ou `null`, e `video_warning` explica a ausência.
`duration_s` em segundos.

**Trava do aparelho.** Do preparo do `run.start` até o fim da execução,
`hierarchy.dump`, `passive.start`, `codegen.record`, `input.tap`,
`input.text`, `recording.start`, `scrcpy.start` (a janela repassa toque),
`wda.start` e `simulators.shutdown` no mesmo aparelho, e `flow.run` e
`flow.maestro_run` em qualquer aparelho, respondem `device_busy` com o nome do
projeto. Um `hierarchy.dump` que já estava em andamento reconfere a trava antes
de abrir a sessão do Appium, e a escuta passiva antes de ligar o ouvinte. O
encerramento do motor espera a execução fechar o vídeo (até 20 s). O espelho
(`stream.*`, por `screencap`) continua. O fim da execução solta a trava, e a
próxima leitura do inspetor reabre a sessão como sempre.

## Convenções que importam

**Coordenadas são do aparelho, não da janela.** A conversão é do front, em
`Projection`. Enviar coordenada de tela faria o toque cair no lugar errado.

**Estratégia de localizador tem nomes diferentes nos dois lados.** O motor usa
`position`; a interface, `coords`. A tradução acontece em um lugar só,
`EngineDTO.StepPayload.mappedStrategy`.

**Quadro só é enviado quando a tela muda.** O motor captura na cadência pedida
e descarta quadro idêntico. `stream.stats` mostra a proporção descartada.
Desde a trilha de desempenho (PERF-2), depois de 5 capturas iguais seguidas e
2 s sem toque nem mudança a captura cai para `idle_fps`; `input.tap`,
`input.text`, o toque da escuta passiva ou um quadro diferente voltam à
cadência normal na hora. Quando a captura é mais lenta que o intervalo, o laço
ainda descansa um quarto do tempo dela (no mínimo 50 ms).

**Credencial já chega redigida.** A interface nunca recebe o token. Ver
`docs/SEGURANCA.md`.

**Parâmetro numérico fora da faixa é `invalid_input`** (desde a 3.10.0). Texto,
`true`, `NaN`, `Infinity` e valor fora da faixa são recusados com o nome do
parâmetro na mensagem, em vez de virar erro interno ou passar adiante. Ausente
ou `0` continua valendo o padrão.

| Parâmetro | Métodos | Faixa |
|---|---|---|
| `limit` | `proxy.events`, `analytics.events` | inteiro, 1 a 1.000.000 (padrão 200) |
| `poll_interval` | `devices.watch_start` | 0,01 a 3.600 s |
| `max_width` | `screen.capture`, `stream.start` | inteiro, 16 a 16.384 |
| `fps` | `stream.start` | 0,1 a 120; em `scrcpy.start`, inteiro de 1 a 240 |
| `quality` | `stream.start` | inteiro, 10 a 95 |
| `idle_fps` | `stream.start` | 0 a 120; `0` desliga a cadência de tela parada |
| `max_size` | `scrcpy.start` | inteiro, 16 a 16.384 |
| `step_num` | `session.correlate` | inteiro, 0 a 1.000.000 |
| `before_s`, `after_s` | `session.correlate` | 0 a 60 s |
| `x`, `y` | `input.tap`, `hierarchy.element_at`, `codegen.record` | 0 a 20.000; `NaN` e `Infinity` recusados |

## Mudou o contrato?

```bash
make fixtures
```

As fixtures da suite Swift saem do próprio motor. O CI reprova o PR se elas
estiverem desatualizadas, o que impede que uma divergência entre as duas
linguagens chegue em silêncio até a execução.

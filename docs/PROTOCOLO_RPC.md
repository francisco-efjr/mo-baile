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
| `request_cancelled` | O cliente cancelou a requisição. Vem com o código `-32800`, e não `-32000`. Ver "Cancelamento" |

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
  "notifications":["stream.frame","stream.settled","$/progress","..."]}}
```

- Se `protocol_version` do cliente for diferente da do motor, o motor responde
  erro `-32000` com `data.code = "incompatible_protocol"` e uma mensagem que
  cita as duas versões. O front mostra essa mensagem e não segue conectando.
- `methods` é a tabela declarativa do motor (`mobaile/rpc/contract.py`), a
  mesma que decide a fila de cada método. `timeout_s` é o tempo que o front deve
  esperar antes de desistir da chamada, **contado do envio e incluindo o tempo
  que o pedido passa na fila** atrás de outros do mesmo domínio. O front usa esse
  valor, e não uma tabela própria: há uma fonte de verdade só.
- `engine.hello` não é obrigatório para o motor atender. Clientes antigos, o
  harness de QA e a interface Tk continuam funcionando sem ele.

## Concorrência

O motor lê o stdin numa thread e despacha cada requisição para uma **fila
serial por domínio**. Uma chamada lenta numa fila não atrasa as outras filas.

| Fila | Para quê | Métodos |
|---|---|---|
| `inline` | responde na própria thread de leitura, sempre em milissegundos | `engine.hello`, `engine.shutdown`, `$/cancelRequest` |
| `fast` | interação e estado; nada ali passa de uns 2 s | o padrão: `input.*`, `stream.*`, `codegen.*`, `session.*`, `devices.watch_*`, `hierarchy.element_at`, `engine.info`, `scrcpy.*`, `recording.status`, `passive.status` |
| `capture` | leitura de tela e árvore, que pode levar segundos, e a escuta passiva | `hierarchy.dump`, `screen.capture`, `screen.size`, `passive.start`, `passive.stop` |
| `services` | serviços de fundo que o motor liga e desliga | `proxy.*`, `analytics.*` (menos `analytics.ios_devices`), `flow.*`, `recording.start`, `recording.stop` |
| `query` | consultas ao ambiente, que levam segundos mas nunca minutos | `devices.list`, `wda.status`, `simulators.list`, `emulators.list`, `diagnostics.check`, `setup.check`, `home.summary`, `analytics.ios_devices` |
| `environment` | preparo de ambiente, que pode levar minutos | `wda.start`, `simulators.boot`, `simulators.shutdown`, `emulators.boot` |
| `report` | aba Relatório: ler spec e log, auditar, gravar arquivos e OCR dos prints. Não toca aparelho | `report.spec`, `report.audit`, `report.export`, `report.import` |

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
| `engine.hello` | `protocol_version`, `client` | versão do contrato, versão do motor, capacidades, tabela de métodos e notificações |
| `engine.info` | — | versão, plataforma, caminhos, disponibilidade de adb e scrcpy, estado do proxy, lista de métodos |
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
| `stream.start` | `fps`, `max_width`, `format` (`jpeg` padrão ou `png`), `quality` (JPEG, 10–95, padrão 80) | confirma o início; devolve `format`, `quality` e `source` (`wda_mjpeg` quando o espelho iOS vem do MJPEG do WDA, `capture` quando vem de `simctl`/`screencap`). Formato inválido: `invalid_input` |
| `stream.stop` | — | idempotente |
| `stream.stats` | — | quadros capturados, emitidos, descartados, fps medido |
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
| `codegen.steps` | — | passos gravados. Desde a 3.6 cada passo traz `recorded_at` (epoch do Mac na gravação; `null` em passo antigo), e `codegen.record`/`passive.step` trazem `step_num` e `recorded_at` do passo criado |
| `codegen.reset` | — | limpa a gravação |
| `codegen.save` | `key`, `directory`, `actions_code`, `locators_code` | grava `pages/<key>.py` e `locators/<key>.py` e devolve os caminhos. `directory` precisa ficar dentro de `~/Documents/Mo baile` (link simbólico e `..` resolvidos); fora dele, `invalid_input` |

### Execução de fluxo

| Método | Parâmetros | Devolve |
|---|---|---|
| `flow.run` | — | roda os passos gravados no alvo ativo. O andamento chega por `flow.step`, `flow.log` e `flow.finished` |
| `flow.stop` | — | pede a interrupção após o passo atual. Idempotente |
| `flow.status` | — | `{running, cancelled}` |
| `flow.maestro_check` | `yaml` ou `path`, `env?` | valida um flow no formato do Maestro sem tocar o aparelho: `{valid, app_id, name, tags, steps}`. Comando fora do subconjunto suportado, JavaScript e comandos de IA/nuvem dão `invalid_input` com o motivo |
| `flow.maestro_export` | `app_id?`, `name?`, `save?` | os passos gravados como flow do Maestro: `{yaml, variables, steps, path?}`. Texto digitado não vai para o YAML: vira `${VARIAVEL}`, listada em `variables`. Com `save`, grava em `~/Documents/Mo baile/flows/` sem sobrescrever |
| `flow.maestro_run` | `yaml` ou `path`, `env?` | roda o flow no alvo ativo com as esperas do Maestro (elemento até 17 s, 7 s se `optional`; hierarquia assentada após cada ação). Divide trava, `flow.stop`, `flow.step`, `flow.log` e `flow.finished` com `flow.run`. Devolve `{running, app_id, name, tags, steps}` |

O formato e o que fica de fora estão em
[research/maestro-modelo-de-automacao.md](research/maestro-modelo-de-automacao.md).
Ler YAML pede o PyYAML no Python do motor; sem ele, os três métodos devolvem
`invalid_input` explicando o que instalar, e o resto do motor segue igual.

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
| `report.export` | `directory` (opcional; sem ele, `~/Documents/Mo baile/Relatórios/<projeto>-<plataforma>-<data>`) | grava `board_auditoria.excalidraw`, `relatorio_auditoria.html`, `relatorio_auditoria.md` e `relatorio_auditoria.tsv` do último `report.audit`. Devolve `directory` e `files` (`kind`, `name`, `path`, `bytes`) |
| `report.import` | `prints_dir`, `projeto` (opcional), `platform`, `spec_path` (opcional; sem ele, `~/Documents/Mo baile/Specs/<projeto>.json`) | OCR local (Vision) dos prints dos cards e rascunho da spec, sem sobrescrever arquivo existente. Devolve `spec_path`, `review_path` (`.revisao.md`), `spec` (resumo, ou `null` se o rascunho ainda não valida), `spec_error`, `review` (`print`, `event`, `doubts`) e `doubts_total` |
| `report.card` | `spec_path`, `card_index` (o `card_index` dos resultados, a partir de 0) | o card como está no JSON, para editar: `card_index`, `cards` (total), `secao`, `titulo`, `evento`, `print`, `params` (lista ordenada de `{key, value}`; `value` é o valor do JSON, texto ou não), `variacoes` (lista de listas de `{key, value}`), `obs` (texto, ou `null`), `obs_por_fluxo` (a `obs` é um objeto por fluxo e não vai para o formulário) e `params_por_fluxo` (chaves dos fluxos com parâmetros próprios) |
| `report.card_update` | `spec_path`, `card_index`, `card` com os campos do formulário (`secao`, `titulo`, `evento`, `params`, `variacoes`, `obs`, no formato de `report.card`; campo ausente fica como estava) | grava o card na spec e devolve `spec` (resumo relido) e `card` (como `report.card`). Muda só o que o formulário mostra: o print, `por_fluxo`, `params_por_fluxo`, uma `obs` por fluxo e chaves desconhecidas ficam. Texto vazio tira a chave do JSON; evento vazio, parâmetro sem nome ou repetido e expressão regular inválida respondem `invalid_input` sem gravar. A spec inteira é validada antes, e o arquivo é trocado de uma vez |

`report.audit` com `source: "session"` e nenhum evento capturado responde
`invalid_input`: um relatório com tudo "não disparado" pareceria verdadeiro.

## Convenções que importam

**Coordenadas são do aparelho, não da janela.** A conversão é do front, em
`Projection`. Enviar coordenada de tela faria o toque cair no lugar errado.

**Estratégia de localizador tem nomes diferentes nos dois lados.** O motor usa
`position`; a interface, `coords`. A tradução acontece em um lugar só,
`EngineDTO.StepPayload.mappedStrategy`.

**Quadro só é enviado quando a tela muda.** O motor continua capturando na
cadência pedida, mas descarta quadro idêntico. `stream.stats` mostra a
proporção descartada.

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

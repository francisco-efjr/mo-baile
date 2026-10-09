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
{"jsonrpc":"2.0","method":"stream.frame","params":{"png_base64":"...","width":900,"device_id":"emulator-5554",...}}
```

| Notificação | Quando chega |
|---|---|
| `stream.frame` | Um quadro novo, apenas quando a tela mudou. `device_id` diz de qual aparelho ele veio; quadro capturado antes de uma troca de aparelho não é emitido |
| `stream.settled` | A tela parou de mudar. É o momento certo de reler a hierarquia |
| `proxy.event` | Uma requisição HTTP foi observada |
| `analytics.event` | Um evento de tagueamento foi capturado |
| `device.changed` | Um alvo foi conectado ou desconectado. `device_id` nulo significa que sumiu |
| `passive.step` | A escuta passiva transformou um toque no aparelho em passo gravado. Mesmo formato de `codegen.record` |
| `passive.skipped` | Um toque no aparelho não virou passo, com `x`, `y` e o motivo |
| `passive.text` | O texto digitado num campo foi lido e guardado no último passo de entrada |
| `flow.log` | Uma linha de saída da execução do fluxo |
| `flow.finished` | A execução do fluxo terminou, com `success` e `message` |
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
| `query` | consultas ao ambiente, que levam segundos mas nunca minutos | `devices.list`, `wda.status`, `simulators.list`, `emulators.list`, `diagnostics.check`, `analytics.ios_devices` |
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
| `session.select_device` | `platform`, `device_id` | plataforma e alvo em uso |
| `devices.list` | `platform` | alvos conectados |
| `devices.watch_start` | `poll_interval` | liga a detecção automática |
| `devices.watch_stop` | — | desliga. Idempotente |

### Ambiente e inicialização

| Método | Parâmetros | Devolve |
|---|---|---|
| `diagnostics.check` | — | estado medido do ambiente nas duas plataformas, com detalhe e ação sugerida por checagem |
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
| `stream.start` | `fps`, `max_width` | confirma o início |
| `stream.stop` | — | idempotente |
| `stream.stats` | — | quadros capturados, emitidos, descartados, fps medido |
| `scrcpy.start` | `fps`, `max_size`, `title`, `always_on_top` | inicia janela nativa a 60 FPS com baixíssima latência |
| `scrcpy.stop` | — | encerra o espelhamento scrcpy |
| `scrcpy.status` | — | `{available, running}` |

### Rede e tagueamento

| Método | Parâmetros | Devolve |
|---|---|---|
| `proxy.start` | `configure_device` | estado do proxy e se o aparelho aceitou a configuração |
| `proxy.stop` | — | desfaz também a configuração de proxy do aparelho |
| `proxy.events` | `limit` | histórico recente |
| `proxy.clear` | — | limpa o histórico |
| `netlog.start` | `udid` (opcional; sem ele, o primeiro iPhone confiado) | lê pelo cabo o log `CFNETWORK_DIAGNOSTICS` do app em debug e emite cada requisição como `proxy.event`, sem proxy nem certificado. O app precisa rodar com `CFNETWORK_DIAGNOSTICS=3` no scheme. Corpo normalmente indisponível. Devolve `running`, `device_id`, `raw_log` (blocos brutos, headers sensíveis mascarados) |
| `netlog.stop` | — | para a leitura; devolve `running` |
| `analytics.start` | `package` (opcional), `ios_source` (iOS: `auto`, `simulator` ou UDID do iPhone) | começa a escutar o tagueamento; no iOS sem simulador, `auto` usa o iPhone conectado por cabo. Devolve `running`, `source`, `device_id` |
| `analytics.stop` | — | para de escutar |
| `analytics.events` | `limit` | histórico recente |
| `analytics.clear` | — | limpa o histórico |
| `analytics.ios_devices` | — | iPhones por cabo (`udid`, `name`, `ios_version`, `connection`, `problem` opcional) e `available` (pymobiledevice3 instalado) |

### Geração de código

| Método | Parâmetros | Devolve |
|---|---|---|
| `codegen.record` | `x`, `y`, `strategy` | nome da variável, linha do Page Object (`NOME = (AppiumBy.X, "valor")`), bloco da ação (`def` + `wait_to_be_visible(..., 15)` + `click(..., 2)` ou `send_keys`). A coordenada não entra no código: fica no passo, em `coords` |
| `codegen.steps` | — | passos gravados |
| `codegen.reset` | — | limpa a gravação |
| `codegen.save` | `key`, `directory`, `actions_code`, `locators_code` | grava `pages/<key>.py` e `locators/<key>.py` e devolve os caminhos |

### Execução de fluxo

| Método | Parâmetros | Devolve |
|---|---|---|
| `flow.run` | — | roda os passos gravados no alvo ativo. O andamento chega por `flow.log` e `flow.finished` |
| `flow.stop` | — | pede a interrupção após o passo atual. Idempotente |
| `flow.status` | — | `{running, cancelled}` |

### Escuta passiva

| Método | Parâmetros | Devolve |
|---|---|---|
| `passive.start` | — | liga a gravação do que é feito direto no aparelho. Os passos chegam por `passive.step` |
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
| `report.audit` | `spec_path`, `source` (`session`: eventos que a escuta de Analytics capturou; `file`: um log), `log_path` (com `file`), `platform` (opcional; sem ele, a da spec) | `spec` (resumo), `platform`, `source`, `log_path`, `log_stats` (`total_lidos`, `da_plataforma`, `duplicados`, `uteis`), `summary` (`total`, `ok`, `divergent`, `missing`, `compliance_rate`, `extras`, `alerts`), `results` (uma por variação: `id`, `card_index`, `section`, `card_title`, `print_path`, `flow`, `flow_label`, `event`, `variation`, `status` = `ok`, `error` ou `missing`, `checks` com `field`, `expected`, `obtained` e `ok`, `matched` com `id`, `time`, `event_name` e `params`, `occurrences`, `older_divergent`, `older_divergences`, `ga_screen`, `note`, `divergences`, `block`), `extras` e `alerts` (`event`, `screen`, `flow_name`, `component`, `detail`, `count`), `observations`, `markdown` e `tsv`. Guarda o relatório para `report.export` |
| `report.export` | `directory` (opcional; sem ele, `~/Documents/Mo baile/Relatórios/<projeto>-<plataforma>-<data>`) | grava `board_auditoria.excalidraw`, `relatorio_auditoria.html`, `relatorio_auditoria.md` e `relatorio_auditoria.tsv` do último `report.audit`. Devolve `directory` e `files` (`kind`, `name`, `path`, `bytes`) |
| `report.import` | `prints_dir`, `projeto` (opcional), `platform`, `spec_path` (opcional; sem ele, `~/Documents/Mo baile/Specs/<projeto>.json`) | OCR local (Vision) dos prints dos cards e rascunho da spec, sem sobrescrever arquivo existente. Devolve `spec_path`, `review_path` (`.revisao.md`), `spec` (resumo, ou `null` se o rascunho ainda não valida), `spec_error`, `review` (`print`, `event`, `doubts`) e `doubts_total` |

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

## Mudou o contrato?

```bash
make fixtures
```

As fixtures da suite Swift saem do próprio motor. O CI reprova o PR se elas
estiverem desatualizadas, o que impede que uma divergência entre as duas
linguagens chegue em silêncio até a execução.

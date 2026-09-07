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
{"jsonrpc":"2.0","method":"stream.frame","params":{"png_base64":"...","width":900,...}}
```

| Notificação | Quando chega |
|---|---|
| `stream.frame` | Um quadro novo, apenas quando a tela mudou |
| `stream.settled` | A tela parou de mudar. É o momento certo de reler a hierarquia |
| `proxy.event` | Uma requisição HTTP foi observada |
| `analytics.event` | Um evento de tagueamento foi capturado |
| `device.changed` | Um alvo foi conectado ou desconectado. `device_id` nulo significa que sumiu |

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

## Métodos

### Sessão e diagnóstico

| Método | Parâmetros | Devolve |
|---|---|---|
| `engine.info` | — | versão, plataforma, caminhos, disponibilidade de adb e scrcpy, estado do proxy, lista de métodos |
| `engine.shutdown` | — | encerra o motor de forma ordenada |
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

### Tela e hierarquia

| Método | Parâmetros | Devolve |
|---|---|---|
| `screen.capture` | `max_width` | PNG em base64, com dimensões de origem e de saída |
| `screen.size` | — | resolução real do alvo |
| `hierarchy.dump` | — | árvore de acessibilidade já normalizada entre Android e iOS |
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

### Rede e tagueamento

| Método | Parâmetros | Devolve |
|---|---|---|
| `proxy.start` | `configure_device` | estado do proxy e se o aparelho aceitou a configuração |
| `proxy.stop` | — | desfaz também a configuração de proxy do aparelho |
| `proxy.events` | `limit` | histórico recente |
| `proxy.clear` | — | limpa o histórico |
| `analytics.start` / `.stop` / `.events` / `.clear` | — | equivalente para tagueamento |

### Geração de código

| Método | Parâmetros | Devolve |
|---|---|---|
| `codegen.record` | `x`, `y`, `strategy` | nome da variável, linha do Page Object, bloco da ação |
| `codegen.steps` | — | passos gravados |
| `codegen.reset` | — | limpa a gravação |

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

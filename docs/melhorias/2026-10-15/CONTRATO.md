# Contrato da Rodada 2 (3.6.0) — escrito antes do código

Itens: F3, F11, F8, F12, F5 (nesta ordem de implementação). `PROTOCOL_VERSION`
continua 2: tudo é aditivo. O que muda o contrato exige `make fixtures` e
`docs/PROTOCOLO_RPC.md`.

## F3 · Digitação no iOS no fluxo (sem mudança de contrato)

- O runner gerado (`services/flows.py`, `execute_ios_step`) honra
  `action_type == "input"`: toca no campo (`/wda/tap`, com fallback `/actions`),
  espera 0,3 s e envia o texto por `POST /session/<sid>/wda/keys`
  `{"value": [c, c, ...]}`.
- Sucesso = HTTP 200 **e** `value` sem `error` (o WDA real devolve 200 com erro
  dentro de `value`).
- Passo de digitação sem `input_text` falha, como no Android, sem inventar
  valor. O log do runner (`flow.log`) nunca contém o texto: só o tamanho.
- Teste: runner real com `WdaFalso` (já existe em `aparelho_falso.py`), passos
  injetados no `codegen` com `platform="ios"`.

## F11 · Espelho fluido

**`stream.frame` ganha `format`** (`"jpeg"` ou `"png"`) e **`image_base64`**.
`png_base64` continua sendo enviado quando `format == "png"`, para motor e
front antigos conviverem; quando `format == "jpeg"`, só `image_base64` vai.

- `stream.start` ganha `format` (`"jpeg"` padrão, `"png"` opcional) e
  `quality` (JPEG, padrão 80).
- `screen.capture` **não muda**: continua PNG (`png_base64`), porque é a
  captura usada para OCR e relatório.
- iOS: quando o WDA responde em `<wda_url>` e o MJPEG está no ar na porta
  `settings.wda_mjpeg_port` (padrão 9100), o motor lê o fluxo MJPEG e repassa
  o JPEG **sem reencodar**. Se o MJPEG não responder em 2 s, cai no
  `simctl io screenshot` de hoje. Android segue com `screencap`, agora em JPEG.
- `tools/bench_frame.py`: mede encode PNG × JPEG numa captura de exemplo
  (tempo e bytes) e imprime a tabela; os números vão para o `MELHORIAS.md`.
- Front: `EngineDTO.Frame` decodifica `image_base64` ou `png_base64`
  (`NSImage(data:)` lê os dois formatos).

## F8 · Diagnóstico "por que não vejo tráfego"

**Método novo `proxy.diagnose`** (fila `services`, sem parâmetros). Devolve:

```json
{"checked_at": 1760500000.0,
 "proxy_running": true, "device_configured": true, "netlog_running": false,
 "requests_total": 0, "tunnels_total": 12, "tunnels_failed": 12,
 "last_event_age_s": null,
 "causes": [
   {"code": "proxy_not_on_device", "title": "O aparelho não está apontando para o proxy",
    "detail": "settings get global http_proxy devolveu null.",
    "fix": "Clique em Configurar Proxy de novo; se o aparelho recusar, rode adb shell settings put global http_proxy 127.0.0.1:8082."}
 ]}
```

Causas, do mais ao menos provável, cada uma só entra quando a evidência existe:

| code | Evidência | fix |
|---|---|---|
| `proxy_stopped` | `proxy.is_running() == False` | ligar o proxy |
| `proxy_not_on_device` | Android, `is_proxy_configured(serial) == False` | reconfigurar / comando adb |
| `no_connections` | proxy ligado, aparelho configurado, nenhum evento nem túnel em 30 s | o app pode ignorar o proxy do sistema (Flutter/Dart, OkHttp com proxy próprio, WebSocket). Use "App em Debug" (OkHttp) ou o CFNetwork no iOS |
| `tls_pinning_suspected` | túneis `CONNECT` ≥ 3 e ≥ 80% com `error` ou sem bytes de resposta | certificate pinning: desligue no build de debug ou use "App em Debug" |
| `only_tunnels` | túneis sem erro, nenhuma requisição decodificada | o proxy não abre HTTPS (não há MITM, ADR 0004): use "App em Debug" para ver o conteúdo |
| `ios_no_proxy_support` | sessão iOS com proxy ligado | o proxy configura só Android; no iOS use o CFNetwork por cabo (`netlog.start`) |
| `netlog_running_no_events` | netlog ligado e nenhum evento em 30 s | o app precisa do `HttpLoggingInterceptor` (Android) ou `CFNETWORK_DIAGNOSTICS=3` (iOS) |

Front: botão "Por que não vejo tráfego?" no estado vazio da Rede e na barra
acessória; abre um popover com as causas e o passo de correção, cada causa
com ícone. Comando no `CommandRegistry` e no menu.

## F12 · Busca com tokens, escopo e colunas lembradas (só front)

- `SearchQuery` aprende tokens `chave:valor`: Rede: `status:` (`4xx`, `500`),
  `método:`/`metodo:`/`method:`, `host:`, `tipo:` (`json`, `imagem`, `html`);
  Analytics: `evento:`, `param:` (`chave` ou `chave=valor`), `origem:`. Termo
  sem chave continua valendo para todos os campos. Sugestões de token no
  campo de busca (`.searchable(text:tokens:suggestedTokens:)`).
- Escopo da Rede acima da tabela: **Todos · API · Mídia · Erros · Lentas**
  (API = `content-type` JSON/XML/form; Mídia = imagem/vídeo/fonte; Erros =
  status ≥ 400 ou `error`; Lentas = `durationMs > 1000`).
- `TableColumnCustomization` com `@SceneStorage` nas tabelas de Rede,
  Analytics e Relatório.
- Testes: `SearchQueryTests` (parsing e casamento), `NetworkScopeTests`.

## F5 · Linha do tempo correlacionada

**Premissa registrada:** todos os carimbos já são do relógio do Mac na
recepção (`time.time()` em proxy, analytics e netlog). Não há relógio do
aparelho a corrigir; o único desvio é a latência do `logcat`, sub-segundo,
coberta pela janela. Por isso F5 **não depende de F1**: a correlação é feita
na **gravação** do passo, não na execução.

- `AutomationStep` ganha `recorded_at` (epoch segundos, relógio do Mac),
  preenchido em `generate_entry`. Sai em `codegen.steps`, `codegen.record` e
  `passive.step` (campo `recorded_at` no `element`? não: no nível do passo,
  junto de `step_count`).
- **Método novo `session.correlate`** `{step_num, before_s=1.0, after_s=4.0}`
  → `{step_num, recorded_at, window: [from, to], requests: [ids], events: [ids],
  probable: true}`. Janela: do toque menos `before_s` até o toque mais
  `after_s` ou até o `recorded_at` do passo seguinte, o que vier primeiro.
  `probable` é sempre `true` nesta versão: é atribuição por tempo, não causal.
- Front: `AutomationStep.recordedAt`; clicar num passo na barra lateral
  (seleção) liga o **modo correlacionado**: Rede e Analytics mostram só os ids
  da janela, com um chip "Passo 3 · tocar Entrar · 2 requisições · 1 evento"
  e botão para sair. O inspector do passo mostra a lista dos dois lados
  (`CorrelationCard` passa a usar isso, no lugar do endpoint fixo de hoje).
- Teste do motor: dois passos gravados com `recorded_at` controlado, eventos
  de proxy e analytics injetados com `timestamp` dentro e fora da janela;
  `session.correlate` devolve só os de dentro, e a janela do passo 1 termina
  no `recorded_at` do passo 2. Teste Swift: `FakeEngine` responde
  `session.correlate` e `filteredHTTPRequests` respeita a janela.

## Versão

3.6.0 (minor: `stream.frame` e `stream.start` ganham campos, `proxy.diagnose`
e `session.correlate` novos, `recorded_at` novo). CHANGELOG, `make fixtures`
(fixtures de `proxy.diagnose`, `session.correlate`, `stream.frame` em JPEG,
capturadas da emissão real), `docs/PROTOCOLO_RPC.md`.

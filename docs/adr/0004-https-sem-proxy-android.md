# ADR 0004 — HTTPS sem proxy no Android: o log do OkHttp

Data: 2026-10-09
Status: aceito

## Contexto

No iPhone, o "iPhone em Debug" mostra o tráfego HTTPS do app em debug sem
proxy nem certificado, lendo pelo cabo o log `CFNETWORK_DIAGNOSTICS`. No
Android não havia equivalente: com o app em debug no Android Studio, as URLs
apareciam no App Inspection (Network Inspector) e não no Mo baile, que só tinha
o proxy MITM (certificado instalado, rota reversa e app que confia na CA do
usuário).

## Opções

1. **Log do `HttpLoggingInterceptor` do OkHttp no logcat.** O Retrofit usa
   OkHttp; o build de debug costuma ligar o interceptor. O texto já sai fora do
   TLS, com linha de requisição, headers e corpo conforme o nível. Lido por
   `adb logcat`, não disputa nada com o Android Studio.
2. **JDWP** (`adb jdwp` + breakpoints em `okhttp3.RealCall`). Pega qualquer app
   debuggable, mas o JDWP aceita um depurador só: com o Android Studio
   depurando, que é justamente o caso pedido, não conecta. E cada breakpoint
   pausa a thread do app.
3. **Agente JVMTI, como o App Inspection** (`am attach-agent` + inspetor em
   dex). Vê `OkHttp` e `HttpURLConnection` sem mexer no app, mas reproduz um
   protocolo interno do Android Studio (transporte gRPC, versões do agente por
   ABI). Esforço grande e frágil a cada versão do Studio.

## Decisão

Opção 1, como recurso da mesma ação do iPhone: `netlog.start` escolhe a fonte
pela plataforma da sessão. No Android, `adapters/android_okhttp_log.py` lê
`adb logcat -v threadtime -T 1`, separa as linhas por processo e thread (as
linhas de uma chamada saem na mesma thread), aceita os três níveis do
interceptor e o formato do OkHttp 3 e 4, junta corpo picado pelo limite de
4.000 caracteres do `android.util.Log`, redige credenciais e entrega cada
chamada como `proxy.event`. A interface chama o botão de "App em Debug".

## Consequências

- O app precisa do interceptor no build de debug. No nível BASIC só sai a
  linha; HEADERS traz headers; BODY traz corpos. O tooltip e a mensagem de
  status dizem isso.
- Só OkHttp. `HttpURLConnection`, Volley, Ktor (formato próprio) e Flutter não
  aparecem. A opção 3 fica registrada como estudo
  ([melhorias de 09/10](../MELHORIAS_2026-10-09.md), item R5).
- O contrato não ganhou método: `netlog.start` e `netlog.stop` passam a valer
  nas duas plataformas, e a resposta traz `source` (`cfnetwork` ou
  `okhttp_logcat`).

## Como isso é verificado

`engine/tests/unit/test_android_okhttp_log.py`: os três níveis, falha de rede,
threads intercaladas, outro log na mesma thread, corpo picado, expiração e
redação; e o `netlog.start` pela plataforma da sessão. No front,
`DebugNetTests`.

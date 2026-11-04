# Análise de desempenho: Mo baile (app nativo + motor), contexto para um modo leve

Status: Concluída (com pendências declaradas) · Data: 2026-11-03 e 04 · Ambiente: local, Mac do dono · Plataforma: desktop (macOS)
Analista: perf-analyst (rodada brain-of-agent, modo melhoria). Fiz leitura de código e medição não invasiva. Nenhum código do projeto foi alterado, e nenhum processo do dono foi encerrado ou sinalizado. Este documento foi escrito pelo mesmo modelo que vai propor a mudança, então não conta como validação externa.

Rótulos usados em todo o documento:
- **Medido**: número que eu mesmo medi nesta rodada. A fonte é um arquivo no scratchpad `perf/`.
- **Lido no código**: valor ou comportamento tirado do código, com `arquivo:linha`.
- **Medido (doc)**: número medido por outra pessoa e registrado no repositório.
- **Inferido**: conta feita a partir de valores medidos. A conta está mostrada.
- **Extrapolado**: projeção para outra máquina ou cenário.
- **Não medido**: não houve como medir sem mexer no app em uso.
- **Suposição**: escolha provisória.

Todos os caminhos de código são relativos à raiz do repositório. `apps/MoBaile/Sources/MoBaile/` aparece abreviado como `Swift/`, e `engine/src/mobaile/` como `py/`.

## Pergunta e SLO

**Pergunta do dono:** o app vai rodar em Macs de vários tipos, inclusive modestos (Intel antigos, M1 com 8 GB). Ele quer:
- um modo que use bem a máquina;
- um modo leve, para quando o consumo estiver alto, que não trave e continue bom de usar.

**SLO:** não informado. Proponho os alvos abaixo, todos como **Suposição**, para julgar o modo leve.
- Com o app aberto, aparelho conectado e tela parada, o conjunto app, motor e filhos fica em **≤ 10% de um núcleo**.
- Com tela mudando no espelho, fica em **≤ 35% de um núcleo**.
- Footprint do app **≤ 250 MB** e do motor **≤ 150 MB** fora do Relatório.
- Nenhuma ação de interface bloqueia a main thread por mais de 100 ms.

## Veredito: Não atende (no cenário observado), com causa identificada

Com o espelho iOS ligado e a **tela do simulador parada**, o motor captura sem parar:
- 3,5 a 3,6 capturas por segundo pelo `simctl`, cada uma com cerca de 0,15 s de CPU;
- a soma é **cerca de 0,5 a 0,7 de um núcleo** só para descobrir que nada mudou (Inferido de medições).

O loop do espelho não tem folga: o alvo é 6 fps (167 ms), mas cada captura leva cerca de 270 ms. Por isso a thread captura de novo logo em seguida, sem dormir. Num Mac mais lento ela continua ocupada o tempo todo; só entrega menos quadros (Inferido).

O app Swift, ocioso, gasta perto de zero. O motor sem espelho também. Confiança alta no diagnóstico do espelho, porque as três medidas independentes batem:
- a contagem de processos;
- o tempo de cada captura;
- a CPU por thread do motor.

Confiança média no tamanho exato do efeito em outras máquinas (Extrapolado).

## Estado observado (o que estava rodando)

| Item | Valor | Fonte | Rótulo |
| --- | --- | --- | --- |
| Máquina | Mac16,8, Apple M4 Pro, 12 núcleos (8P+4E), 24 GB, macOS 26.3.1 | `sysctl`, `sw_vers` | Medido |
| Pressão de memória do sistema | nível 2 (aviso); 22 GB usados, 11 GB no compressor | `sysctl kern.memorystatus_vm_pressure_level`, `top_sys.txt` | Medido |
| Energia / térmico | na bateria; `thermalState` 0 (nominal); Low Power desligado | `sinais.out` | Medido (manhã de 04/11) |
| App | PID 80515, `/Applications/Mo baile (nativo).app`, aberto havia 6h30 (18h34 no dia seguinte) | `ps` | Medido |
| Motor | PID 80521, Python 3.14 do python.org, `-S -m mobaile.rpc`, filho do app | `ps` | Medido |
| Filhos do motor | `simctl io <udid> screenshot -` em laço; `simctl list devices` periódico; `simctl spawn … log stream --level debug --predicate 'eventMessage CONTAINS "I-ACS"'` (escuta de analytics iOS, viva desde a subida) | `children_15s.txt` | Medido |
| Aparelhos | simulador iPhone 16e ligado; `adb devices` vazio | `simctl list`, `adb devices` | Medido |
| Fonte do espelho | captura por `simctl`: o MJPEG do WDA recusou conexão às 15:48:00 e o motor caiu no plano B | `~/Library/Logs/Mo baile/engine.log` (linha "MJPEG indisponivel … Connection refused") | Medido |
| Aba aberta no app | não identificada (não tirei captura de tela da janela do dono) | — | Não medido |
| Arquitetura do binário do app | **somente arm64** | `lipo -archs` | Medido |

## Evidências (medições)

### App e motor ao vivo

| Item | Valor | Fonte | Rótulo |
| --- | --- | --- | --- |
| Capturas `simctl screenshot` por segundo | 3,6 (36 em 10 s); 3,5 (52 em 15 s) | `spawn_rate.txt`, `children_15s.txt` | Medido |
| Tempo de uma captura `simctl` (PNG) | 0,26–0,28 s de parede; 0,08 s user + 0,07 s sys = **~0,15 s de CPU**; 1,42 MB de PNG 1170×2532 | `time_simctl.txt` | Medido (5 amostras) |
| Mesma captura em JPEG (`--type=jpeg`) | 0,27 s de parede; ~0,13 s de CPU; 391 KB | `bench_jpeg_decode.out` | Medido (1 amostra) |
| CPU dos filhos `simctl` só para capturar | **≈ 0,5 núcleo** (3,5 capt/s × 0,15 s) | conta | Inferido |
| `simctl list devices` (vigia de aparelhos) | 9 execuções em 15 s (uma a cada ~1,7 s); 0,13 s de parede, ~0,085 s de CPU cada; **≈ 5% de um núcleo** | `children_15s.txt`, `time_simctl_list.txt` | Medido + Inferido |
| CPU do próprio motor (sem filhos) | 6,0 / 7,7 / 8,8 / 8,3% (`top`); 0,85 s em 10 s = 8,5% | `top_app.txt`, `ps -o time` | Medido |
| Média de longo prazo do motor | 873 s de CPU em 6h30 (3,7%); 1.474 s em 18h34 (2,2%), e esse intervalo inclui uma noite em que o Mac pode ter dormido | `ps -o time,etime` | Medido |
| Onde o motor gasta | uma thread acumulou 14:26 dos 14:33 min de CPU do processo (99%) | `ps -M -p 80521` | Medido; que essa thread é a `mobaile-stream` é Inferido (é o único laço contínuo com trabalho pesado) |
| Pipeline em Python por quadro capturado | decodificar o PNG + RGB **15,9 ms**; diff em miniatura 32×32 **2,8 ms**; total ≈ 19 ms × 3,5/s ≈ **6,5% de um núcleo**, o que bate com o `top` | `bench_frame_pipeline.out` | Medido + Inferido |
| Custo extra por quadro que muda | redimensionar para 900 px + JPEG q80 + base64: **16,9 ms**; JPEG de 156 KB; **~208 KB de base64** por notificação `stream.frame` | `bench_frame_pipeline.out` | Medido |
| Decodificar a captura em JPEG em vez de PNG | 4,4 ms inteiro; 2,9 ms com `draft` em 1/4 (contra 15,9 ms do PNG) | `bench_jpeg_decode.out` | Medido |
| Variar largura e qualidade do quadro (codificar + base64) | 900/q80: 16,7 ms, 203 KB · 720/q70: 13,6 ms, 119 KB · 600/q60: 11,8 ms, 79 KB · 450/q60: 10,2 ms, 50 KB | `bench_knobs.out` | Medido |
| App Swift (CPU) | 0,0–0,2% com a tela parada; 1:35 min de CPU em 18h34 | `top_app.txt`, `ps` | Medido |
| App Swift (memória) | footprint **137 MB**; **pico 419 MB**; dominado por `MALLOC_SMALL` 71 MB e `MALLOC_REALLOC` 23 MB | `footprint_app.txt`, `vmmap_app.txt` | Medido |
| Motor (memória) | footprint **75 MB** (`MALLOC_LARGE` 34 MB; VM sem tag 20 MB) | `footprint_engine.txt` | Medido |
| Outros processos na máquina | `iCoreService` (Trend Micro) 46,8% de CPU, `com.trendmicro…` 37,4%, `SimRenderServer` 22,9%, `WindowServer` 45,5% | `top_sys.txt` | Medido; a ligação com o Mo baile não foi medida |

### Motor isolado (cópia do repositório, processo meu, sem aparelho)

| Item | Valor | Fonte | Rótulo |
| --- | --- | --- | --- |
| Do `spawn` à primeira resposta | 236 ms (M4 Pro, bytecode em cache) | `drive_engine.out` | Medido. O driver mandou `protocol_version` 1, o motor respondeu "incompatível (2)" e continuou atendendo, o que não afeta os tempos |
| CPU ociosa (30 s, sem espelho nem vigia) | 0,020 s = **0,07% de um núcleo** | `drive_engine.out` | Medido |
| RSS ocioso | 32–54 MB; 8 threads | `drive_engine.out` | Medido |
| `engine.info` | 0,1–0,5 ms | `drive_engine.out` | Medido |
| `wda.status` (WDA fora do ar) | 65 ms na 1ª chamada; 1,4–2,6 ms depois | `drive_engine.out` | Medido |
| `devices.list` | 11–25 ms | `drive_engine.out` | Medido |
| `home.summary` | 161–195 ms | `drive_engine.out` | Medido |
| `report.audit` / `report.export`, cenário médio (6,8 MB, 20,8 mil eventos) | 220 ms / 48 ms; **pico de RSS 181 MB** | `bench_report_rss.out` | Medido. O pico inclui gerar os dados sintéticos no mesmo processo, então é um teto |
| Mesmo, cenário grande (17,9 MB, 54 mil eventos) | 675 ms / 173 ms; **pico de RSS 468 MB** | `bench_report_rss.out` | Medido (mesmo teto) |
| Mesmo, cenário máximo (62 MB) | 2,25 s de auditoria | `docs/DESEMPENHO_RELATORIO.md` | Medido (doc), M4 Pro |
| Pico de RSS no cenário máximo | ≈ 1,6 GB (468 MB × 62/17,9, crescimento linear) | conta | Extrapolado: precisa medir antes de valer para Mac de 8 GB |

## Inventário de consumidores

### Python (motor)

| # | Consumidor | O que faz | Onde | Custo | Rótulo |
| --- | --- | --- | --- | --- | --- |
| P1 | **Laço do espelho** | Captura, decodifica e compara a cada ciclo, mesmo com a tela parada: o diff só evita emitir, não evita capturar. Quando a captura é mais lenta que o intervalo, a espera fica em 10 ms e o laço não para | `py/services/streaming.py:135-179` (espera em `:179`); `py/rpc/server.py:1083-1155` | ≈ 0,5 núcleo em filhos + ~7–9% no motor no iOS por `simctl` | Medido + Inferido |
| P2 | Captura iOS por `simctl` | `subprocess.run(["xcrun","simctl","io",udid,"screenshot","-"])` a cada quadro: `xcrun` → `bash` → `simctl`, ou seja, 3 `exec` por quadro, e PNG cheio | `py/adapters/ios_wda.py:100-110` | ~0,15 s de CPU por quadro | Medido |
| P3 | Captura Android | `adb exec-out screencap` cru (RGBA, ~10 MB por quadro) em sequência | `py/adapters/adb.py:201-245` | 1,23 s por quadro no Motorola g55 (o PNG levava 2,14 s), conforme comentário no código; ≈ 8 MB/s contínuos no USB mais a CPU do `adbd` no aparelho | Lido no código (medido pelo autor); tráfego Inferido |
| P4 | MJPEG do WDA (caminho bom do iOS) | Thread lendo o `multipart`; repassa o JPEG sem recodificar quando cabe em `max_width` | `py/adapters/mjpeg.py`; `py/rpc/server.py:1110-1118, 468-471` | Não medido (o WDA estava fora do ar) | Lido no código |
| P5 | Codificar o quadro + notificação | Redimensiona para 900 px, JPEG q80, base64 dentro do JSON-RPC | `py/rpc/server.py:454-489`, `STREAM_MAX_WIDTH=900` em `:96` | 16,9 ms e ~208 KB por quadro que muda; até ≈ 0,7 MB/s no pipe a 3,5 fps | Medido + Inferido |
| P6 | Vigia de aparelhos | Consulta `simctl list devices` (iOS) ou `adb devices` (Android) a cada 1,5 s, o tempo todo, mesmo com o alvo escolhido | `py/services/devices.py:191-198`; `POLL_INTERVAL` 1,5 s em `py/config.py:77`; `py/adapters/ios_wda.py:80-98` | ≈ 5% de um núcleo no iOS; no Android, `adb devices` levou 0,01 s sem aparelho (Medido) | Medido |
| P7 | Hierarquia a cada "tela estabilizou" | `stream.settled` leva o front a pedir `hierarchy.dump` (WDA `/source` ou `uiautomator dump`); há cache de 1,2 s | front `Swift/Engine/EngineSession.swift:1744-1747`; motor `py/rpc/server.py:855-870` | No Android o `uiautomator dump` custa segundos e pode falhar no aparelho | Lido no código; Não medido |
| P8 | Proxy de rede | Uma thread por conexão (`ThreadingMixIn`, até 512 conexões); corpo capturado até 256 KB; histórico em `deque(2000)` **e** `queue(4000)` | `py/adapters/proxy.py:48-56, 483-485, 503-516, 559-566` | Memória: a `event_queue` **não tem consumidor no app nativo**, só no Tk (`apps/tk-legacy/...http_viewer.py:1466`). Ela enche e fica com os 4.000 primeiros eventos para sempre. Somados aos 2.000 mais novos do `deque`, são até 6.000 eventos com até 2 × 256 KB de corpo: até ~3 GB no pior caso; com ~20 KB por evento, ~120 MB | Lido no código; memória Inferida |
| P9 | Escuta de analytics | `adb logcat` ou `simctl spawn … log stream --level debug`; `deque(5000)` + `queue(10000)`, que o app nativo também não lê. No Android ainda roda `logcat -G 8M` e `setprop` | `py/adapters/analytics_logcat.py:43, 161-162, 196-201, 322-339, 453-475` | Processo filho contínuo (observado vivo havia 6h30) | Medido (processo) + Lido no código |
| P10 | Logs de rede de debug | Leitura do `logcat` do OkHttp e do `log stream` do CFNetwork, com até 500 pendentes cada; log cru até 5 MB | `py/adapters/android_okhttp_log.py:55-58, 323-340`; `py/adapters/ios_cfnetwork.py:59-63, 432-442` | Só quando ligados | Lido no código |
| P11 | Escuta passiva | Thread do `getevent` (Android); polling do Quartz a **40 Hz** (`sleep(0.025)`) para o clique no Simulator ou no scrcpy | `py/adapters/input_events.py:101-140, 287, 379` | Pequeno e contínuo enquanto ligada | Lido no código; Não medido |
| P12 | Runner de flows (Maestro) | Polling de 0,3 s, assentamento de 0,2 s e limites de 0,1 s, cada um com leitura de hierarquia | `py/services/maestro_flow.py:47-76, 957-1274` | Pesado por natureza durante a execução | Lido no código |
| P13 | Relatório | Log e eventos inteiros em memória (limite de 64 MB de log) | `py/security/files.py:20`; `py/services/report/` | Pico de 181 MB (médio) e 468 MB (grande) | Medido |
| P14 | Filas do RPC | 6 filas seriais, uma thread cada, mais a thread do stdin | `py/rpc/contract.py:43-53`; `py/rpc/server.py:143-188, 2366, 2459` | Ociosas: 0,07% (Medido) | Medido |
| P15 | scrcpy | Janela própria a **60 fps**, 1080 px | `py/rpc/server.py:1181-1205`; o front pede 60 fps em `Swift/Engine/EngineSession.swift:876` | Decodificação H.264 e GPU no processo do scrcpy | Lido no código; Não medido |
| P16 | Log do motor | Rotação de 1 MB × 3; nível INFO | `py/rpc/server.py:2487-2488, 2590-2600` | Desprezível | Lido no código |

### Swift (app)

| # | Consumidor | Onde | Custo | Rótulo |
| --- | --- | --- | --- | --- |
| S1 | **Pedido do espelho a 6 fps**, que nunca se adapta. O espelho **não pausa** com a janela oculta, minimizada ou em segundo plano, nem quando o espelho está escondido (`mirrorVisible`) ou a aba atual não o mostra: não há `occlusionState`, `scenePhase` nem `didResignActive` ligados ao `stopStream`. Só para quando o aparelho sai ou o usuário pede. Começa sozinho por padrão (`autoStartStream` = true) | `Swift/Engine/EngineSession.swift:853-861, 821-829`; `Swift/App/AppState.swift:362-366` | É o gatilho de P1 | Lido no código |
| S2 | Recepção de quadros | `AsyncStream` dos quadros com `bufferingNewest(1)` (bom); JSON + base64 + `NSImage` decodificados fora da main (`Task.detached`) | `Swift/Engine/EngineClient.swift:96-98`; `Swift/Engine/EngineSession.swift:950-966, 1633-1643` | Não medido (a tela estava parada) | Lido no código |
| S3 | Desenho do espelho | `Image(nsImage:).resizable().interpolation(.medium)` com overlay animado | `Swift/Views/Mirror/ScreenCanvas.swift:38-40, 73, 139` | Não medido | Lido no código |
| S4 | Eventos de rede e analytics **decodificados na main** | `handle` é `@MainActor` e `decodeParams` roda `JSONDecoder` em cada `proxy.event` e `analytics.event`, que podem trazer corpos de até 2 × 256 KB. A fila de notificações não tem limite (`.unbounded`) | `Swift/Engine/EngineSession.swift:38, 1622-1627, 1749-1757`; `Swift/Engine/EngineClient.swift:96` | Risco de travar em rajada; Não medido | Lido no código |
| S5 | Tabelas de Rede e Analytics | A cada avaliação de `body`: `filtered*` (inverte + filtra) e `sorted(using:)` em até 1.000 linhas. Cada evento novo invalida (`@Observable` por propriedade), e `removeFirst` custa O(n) no teto | `Swift/App/AppState.swift:205-220`; `Swift/Views/Network/HTTPInspectorView.swift:164`; `Swift/Views/Analytics/AnalyticsInspectorView.swift:46`; `Swift/Engine/EngineSession.swift:1764-1774` | Não medido | Lido no código |
| S6 | Árvore da hierarquia | `buildTree` + filtro + `flatten` dentro do `body`, a cada render | `Swift/Views/Hierarchy/HierarchyTreeView.swift:27-46, 145-203` | Não medido | Lido no código |
| S7 | Polling de status do rodapé a cada 5 s | `engine.info` + `wda.status` + estado da gravação | `Swift/Engine/EngineSession.swift:561-592` | Barato: 0,1–2,6 ms por chamada no motor (Medido) | Medido |
| S8 | Vidro e animações | Liquid Glass em 7 pontos (toolbar, paleta, barra lateral, splash, Início). `GlassSupport` já cai para `.solid` com "Reduzir transparência" e desliga o vidro com `MOBAILE_SEM_VIDRO=1`. Animações com mola de 0,35–0,5 s; várias chamadas `Motion.smooth()` **ignoram** o "Reduzir movimento" do sistema (o padrão é `false`) | `Swift/Views/DesignSystem/Glass.swift:37-57`; `Swift/Theme/DesignTokens.swift:332-337`; `Swift/App/CommandPerformer.swift:46-50`; `Swift/App/AppState.swift:299` | Custo de GPU e WindowServer: Não medido; provavelmente pequeno (poucos pontos) | Lido no código |
| S9 | `TimelineView` de 1 s | Só com o executor de flows aberto | `Swift/Views/Automation/FlowRunnerSheet.swift:50` | Desprezível | Lido no código |
| S10 | Logs de execução | Teto de 5.000 linhas em `LazyVStack` | `Swift/Engine/EngineSession.swift:1779-1783`; `Swift/Views/Automation/FlowRunnerSheet.swift:137` | — | Lido no código |
| S11 | Início | `home.summary` (161–195 ms, Medido) ao abrir, em `home.changed` e ao voltar ao app (no mínimo 3 s de intervalo) | `Swift/Views/Home/HomeView.swift:46-58` | Pequeno | Medido |

### Como o app escolhe e sobe o Python; processos vivos

- **Candidatos, em ordem:** o override por variável de ambiente, o `.venv` do repositório (só fora do bundle), `~/Library/Application Support/Mo baile/python/bin/python3`, `/opt/homebrew/bin/python3`, `/usr/local/bin/python3` e `/usr/bin/python3`. Vale o primeiro que passa na verificação de versão e módulos (`-I -S -c`). Lido no código: `Swift/Engine/EngineLocator.swift:31-80, 171-281`.
- **Subida:** `python -S -m mobaile.rpc`, com `PYTHONPATH` apontando para o motor do bundle, `PYTHONUNBUFFERED=1`, `PYTHONPYCACHEPREFIX` e um dicionário `extraEnvironment` (`Swift/Engine/EngineClient.swift:112-135`). **Não define `qualityOfService`**, então o motor roda com a QoS padrão.
- **Processos vivos observados:** app (1), motor (1), `simctl … log stream` (1, contínuo) e o `simctl io … screenshot` sendo trocado ~3,5 vezes por segundo. Com Android, entram no lugar: `adb` server, `adb exec-out screencap` em laço e `adb logcat`. Opcionais: Appium/Node, scrcpy, `getevent`, Maestro (JVM). Medido no iOS; Lido no código no Android.
- **Intel:** o binário do app é **somente arm64** (`lipo`). O `tools/package_macos_app.sh:102` roda `swift build -c release` sem `--arch x86_64`. Hoje o app **não abre em Mac Intel**: o que trava ali não é desempenho, é o empacotamento. O Python do python.org é universal. Medido.

## Pontos de controle (knobs) para um perfil de desempenho

Ganho estimado para o cenário observado (iOS por `simctl`, tela parada), salvo indicação.

| # | Knob | Hoje | Proposta "Lite" | Ganho estimado | Custo / risco | Rótulo do ganho |
| --- | --- | --- | --- | --- | --- | --- |
| K1 | **Espelho adaptativo**: espaçar a captura quando a tela está parada | 6 fps pedidos; laço sem folga | Depois de N quadros iguais, recuar para 1 fps (ou 0,5); voltar ao normal em toque, digitação ou `stream.frame` com mudança | De ~0,5–0,6 para ~0,15 núcleo a 1 fps (1 × 0,15 s), ou ~0,08 a 0,5 fps: **−70% a −85%** | Primeira mudança espontânea do app aparece com até 1–2 s de atraso | Inferido de Medido |
| K2 | **Pausar o espelho quando ninguém vê**: janela oculta ou minimizada, app em segundo plano, espelho escondido ou aba sem espelho | Não pausa (S1); `RealTimeStreamEngine.pause()` existe mas não está no RPC (`py/services/streaming.py:126-130`) | `NSWindow.occlusionState` / `didResignActive` / `mirrorVisible` → `stream.pause` / `resume` (contrato novo) | ~100% do custo de P1 enquanto oculto | Contrato RPC novo (`make fixtures` + `docs/PROTOCOLO_RPC.md`) | Inferido |
| K3 | Usar a fonte de quadro barata | `simctl` PNG como plano B; MJPEG se o WDA estiver no ar | Tentar `simctl … --type=jpeg` no plano B; religar o MJPEG quando o WDA subir; no Android, scrcpy ou H.264 no lugar do `screencap` em laço | JPEG: decodificar cai de 15,9 para 4,4 ms (−72% da parte Python do P1); a CPU do `simctl` quase não muda (0,15 → 0,13 s, 1 amostra) | JPEG perde fidelidade no inspetor (o motor recaptura em resolução cheia quando precisa) | Medido |
| K4 | Largura e qualidade do quadro | 900 px, q80 (~208 KB de base64) | 600 px, q60 (79 KB) | Codificar: 16,7 → 11,8 ms; −62% de bytes no pipe e na decodificação do Swift | Menos nitidez no espelho | Medido |
| K5 | Intervalo do vigia de aparelhos | 1,5 s, sempre | 5 s, ou suspenso enquanto há alvo e o espelho está saudável | ≈ 5% → ≈ 1,5% de um núcleo (iOS) | Detecção de plugar e desplugar mais lenta | Inferido de Medido |
| K6 | Hierarquia automática em cada `stream.settled` | Sempre | Só com o painel de hierarquia visível, ou só sob demanda | Remove `uiautomator dump` ou WDA `/source` repetidos | O gravador usa a árvore: precisa garantir leitura antes de gravar o passo | Não medido |
| K7 | Históricos e corpos | Proxy: 2.000 + fila de 4.000 sem consumidor. Analytics: 5.000 + 10.000. Corpo de 256 KB. Front: 1.000 | Não criar ou não encher a `event_queue` no app nativo; históricos de 500; corpo de 64 KB; front com 500 | Teto de memória do proxy cai de ~6.000 para ≤ 500 eventos (−90%) | Menos histórico para consultar | Inferido |
| K8 | QoS do processo do motor | Padrão | `process.qualityOfService = .utility` no modo leve (no Apple Silicon tende a ir para os núcleos E) e prioridade baixa nos filhos de captura | Menos disputa com a interface e com o resto do Mac | Captura mais lenta, o que no modo leve é aceitável | Não medido |
| K9 | scrcpy | 60 fps, 1080 px | 30 fps, 720 px | ≈ metade da decodificação | — | Inferido |
| K10 | Vidro e animação | Vidro do macOS 26; molas; `Motion.smooth()` sem respeitar "Reduzir movimento" em vários pontos | No modo leve, usar `.solid` (o caminho já existe) e animação `.linear(0.15)` ou nenhuma; respeitar sempre as preferências de acessibilidade | Pequeno (7 pontos de vidro) | Visual menos rico | Não medido |
| K11 | Main thread e eventos | `JSONDecoder` na main por evento; filtrar e ordenar 1.000 linhas por evento | Decodificar fora da main (como já se faz com o quadro); juntar eventos em lotes de 100–250 ms; teto de 500 | Evita travadas em rajada de rede ou analytics | Pouco código | Não medido |
| K12 | Relatório | Log de até 64 MB inteiro em memória | Avisar acima de X MB em Mac com ≤ 8 GB; liberar o log depois da auditoria | Pico estimado de 1,6 GB no cenário máximo | — | Extrapolado (medir antes) |
| K13 | Polling do rodapé | 5 s | 15 s no modo leve | Pequeno (chamadas de ≤ 3 ms) | — | Medido (baixo valor) |
| K14 | Empacotar para Intel | Somente arm64 | `swift build --arch arm64 --arch x86_64` (universal) | Habilita a plataforma; sem isso não existe modo leve no Intel | Tamanho do binário; testes em Intel | Medido (arch) |

Os knobs já têm onde entrar sem arquitetura nova:
- `stream.start` aceita `fps`, `max_width`, `format` e `quality` (`py/rpc/server.py:1083-1089`).
- `devices.watch_start` aceita `poll_interval` (`py/rpc/server.py:628`).
- `Settings` lê `STREAM_FPS`, `POLL_INTERVAL`, `DIFF_THRESHOLD`, `SETTLE_DELAY`, `STREAM_FORMAT` e `STREAM_QUALITY` do ambiente (`py/config.py:69-95`).
- O app já tem `extraEnvironment` para passar esses valores na subida (`Swift/Engine/EngineClient.swift:132-134`).

O que falta é o front decidir os valores (hoje fixos em `EngineSession.swift:856` e `:876`) e um `stream.pause` / `resume` no contrato.

## Sinais do sistema para decidir sozinho

| Sinal | API | Valor agora (M4 Pro) | Já usado no projeto? |
| --- | --- | --- | --- |
| Estado térmico | `ProcessInfo.thermalState` + `thermalStateDidChangeNotification` | 0 (nominal) | Não |
| Low Power Mode | `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange` (macOS 12+) | false | Não |
| RAM física | `ProcessInfo.physicalMemory` | 24 GB | Não |
| Núcleos | `ProcessInfo.activeProcessorCount`; `sysctl hw.nperflevels` e `hw.perflevel0/1.physicalcpu` (P e E) | 12; 2 níveis (8P + 4E) | Não |
| Arquitetura | `sysctl hw.optional.arm64` (e `sysctl.proc_translated` para Rosetta) | arm64 | Não |
| Pressão de memória | `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])`; leitura avulsa em `kern.memorystatus_vm_pressure_level` | **nível 2 (aviso)** neste Mac | Não |
| Fonte de energia | `IOPSCopyPowerSourcesInfo` / `IOPSGetProvidingPowerSourceType` (IOKit.ps) | "Battery Power" | Não |
| CPU do próprio app e do motor | `task_info` / `getrusage(RUSAGE_SELF)` no Swift; `ps -o time` ou `os.times()` no motor, que pode devolver isso no `engine.info` | — | Não. O motor já manda `fps`, `capture_ms` e `skipped` em cada quadro (`py/rpc/server.py:1136-1141`), um bom sinal de "captura lenta" |
| Visibilidade da janela | `NSWindow.occlusionState` / `didChangeOcclusionStateNotification`; `NSApplication.didResignActive` | — | Não. Só `didBecomeActive` no Início (`Swift/Views/Home/HomeView.swift:48`) |
| Acessibilidade | `accessibilityReduceMotion` / `accessibilityReduceTransparency` | — | **Sim**, em parte (`Glass.swift:97, 186, 210`; `EngineStatusBanner.swift:77`; `Indicators.swift:123`; `SplashWindow.swift:179`) |

Fontes da tabela: `sinais.out` (Medido por um script Swift de leitura) e `grep` no código (Lido no código). Nenhuma das APIs de energia, térmico, memória ou CPU aparece em `engine/src` ou em `apps/MoBaile/Sources`.

**Proposta de regra automática (Suposição, para a rodada decidir).** Ativar o modo leve quando ocorrer qualquer uma das condições:
- `physicalMemory` ≤ 8 GB;
- binário rodando em x86_64;
- Low Power Mode ligado;
- `thermalState` ≥ `.serious`;
- pressão de memória ≥ `.warning`;
- `capture_ms` médio maior que o intervalo pedido por mais de 10 s (o espelho não acompanha).

Voltar só com histerese, por exemplo 60 s sem nenhum gatilho, e nunca no meio de uma gravação ou de um flow. O usuário escolhe em Ajustes entre "Automático", "Desempenho" e "Leve", e o rodapé mostra quando o leve está ativo e por quê.

## Hipóteses de gargalo (ranking)

| # | Hipótese | Sinal que a sustenta | Confirmação sugerida | Estado | Rótulo |
| --- | --- | --- | --- | --- | --- |
| 1 | O espelho captura sem parar com a tela parada e é o maior consumo contínuo | 3,5 capturas/s; 0,15 s de CPU por captura; 99% da CPU do motor numa thread | Com o app fechado pelo dono, subir o motor da branch, ligar `stream.start` no simulador e medir com e sem K1/K3 (CPU somada com os filhos, `ps` a cada 1 s por 60 s, 3 repetições) | Confirmada no iOS | Medido |
| 2 | No Android o mesmo laço pesa mais (10 MB por quadro no USB, 1,2 s por captura) e aquece o aparelho | Comentário medido em `py/adapters/adb.py:202-208` | Medir no g55 o `adb` e o `adbd` com o espelho ligado e parado | Aberta | Lido no código |
| 3 | Rajadas de `proxy.event` ou `analytics.event` travam a interface (`JSONDecoder` na main + ordenar 1.000 linhas) | S4, S5 | Instruments (Time Profiler / Hangs) com o proxy ligado num app ruidoso | Aberta | Não medido |
| 4 | A memória do motor cresce com o proxy ligado por horas (a fila sem consumidor) | `py/adapters/proxy.py:507, 562-565`; consumidor só no Tk | Proxy por 1 h com tráfego; footprint a cada 5 min | Aberta | Lido no código |
| 5 | O antivírus corporativo (Trend Micro observado em 37–47%) amplifica o custo de cada `exec` | 3–4 capturas/s × 3 `exec` cada | Comparar a CPU do `iCoreService` com o espelho ligado e desligado | Aberta | Suposição |
| 6 | O pico de 419 MB do app vem do Relatório (tabelas e HTML) | `footprint_app.txt` (pico) | `footprint` antes e depois de abrir um relatório grande | Aberta | Não medido |

## Medido | Extrapolado | Suposições

- **Medido:**
  - taxa e custo das capturas `simctl`;
  - CPU e memória do app e do motor ao vivo;
  - CPU por thread do motor;
  - pipeline Python por quadro, nos formatos e tamanhos testados;
  - motor isolado ocioso e chamadas leves;
  - memória e tempo do Relatório (médio e grande);
  - sinais do sistema neste Mac;
  - arquitetura do binário.
- **Extrapolado:** comportamento em Intel, M1 8 GB e Android; pico do Relatório no cenário máximo (~1,6 GB).
- **Suposições:**
  - os SLOs propostos;
  - a regra automática;
  - a ligação do custo do antivírus com o Mo baile;
  - que a thread quente seja a `mobaile-stream` (Inferido, muito provável).

## Não verificado e risco residual

- **Interface com tela mudando** (decodificar e desenhar quadros no Swift), rajadas de rede e analytics, e GPU do vidro. Medir exige interagir com o app do dono ou um build próprio com Instruments.
- **Android real e scrcpy.** Não havia aparelho conectado.
- **Máquinas modestas.** Todos os números são de um M4 Pro com 24 GB. Num M1 de 8 GB ou num Intel, a captura e a decodificação devem ser mais lentas. O laço continua ocupado o tempo todo, então o custo relativo à máquina sobe (Extrapolado). Repetir as medições numa máquina modesta antes de fixar os valores do modo leve.
- **Variação.** Cada medição tem 1 sessão; as de CPU, de 10 a 15 s. Para baseline de regressão: mediana de 3 a 5 execuções na mesma máquina.

## Próximo passo

A menor ação que mais reduz incerteza e consumo é **K1 + K2 + K3 (JPEG)** no espelho. É a única fonte contínua grande.

Para medir, há duas opções:
- o dono fecha o app e roda o motor da branch contra o simulador;
- uma ferramenta `tools/bench_stream.py` sobe o motor e liga `stream.start` por 60 s, medindo a CPU somada com os filhos, o que ninguém mede hoje.

Medir com 3 repetições antes e depois. Em seguida, empacotar como universal (K14) para poder medir em Intel.

## Decisões pendentes do humano

- **SLO do modo leve.** Assumi ≤ 10% de um núcleo com a tela parada. Se o dono aceitar mais, K1 pode recuar menos.
- **Suporte a Intel.** Assumi que entra, o que exige binário universal. Se Intel não entra, K14 sai e o piso passa a ser M1 com 8 GB.
- **Comportamento padrão.** Assumi "Automático", que liga o leve sozinho pelos sinais. Se o dono preferir manual, a regra vira só sugestão no rodapé.

## Conteúdo suspeito

Nenhum. Nada no código, nos logs ou nos documentos lidos era dirigido ao agente.

## Arquivos de medição (scratchpad, fora do repositório)

`/private/tmp/claude-502/-Users-francisco-junior-Documents-antigravity-epic-fermi/658c2e96-f13e-4474-b0e8-40f63e72332d/scratchpad/perf/`:
- `top_app.txt`, `top_sys.txt`
- `spawn_rate.txt`, `children_15s.txt`
- `time_simctl.txt`, `time_simctl_list.txt`, `time_adb_devices.txt`
- `bench_frame_pipeline.{py,out}`, `bench_knobs.{py,out}`, `bench_jpeg_decode.{py,out}`
- `footprint_app.txt`, `footprint_engine.txt`, `vmmap_app.txt`
- `drive_engine.{py,out}`, `bench_report_rss.out`
- `sinais.swift`, `sinais.out`

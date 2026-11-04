# Trilha de desempenho: perfis e modo leve (PERF-1 a PERF-5)

Status: implementado na branch `melhoria/2026-11-03-desempenho-dev`, sem
versão, sem push e sem empacotar (o orquestrador versiona e instala) ·
Data: 04/11/2026 · Base: `aeaefca` (3.16.0 + pesquisa).

Escrito pelo mesmo modelo que implementou: não conta como revisão externa.

Rótulos: **Medido** (número desta rodada, com o comando que o reproduz),
**Não medido** (não houve como medir sem mexer no app do dono), **Suposição**
(valor de partida, a calibrar).

## Pedido

> "preciso entender como melhorar a performance do nosso sistema. visando que
> vamos disponibilizar para vários tipos de pc.... deve conter uma arquitetura
> de consumir o pc, mas caso ele esteja consumindo muito, pode haver uma opção
> para rodar uma versão mais amigável com o pc. sem travar, algo lite mas com
> uma boa performance de usabilidade."

Resposta desta entrega: o mesmo app com três perfis (Completo, Equilibrado,
Leve) e o Automático, que escolhe pelo estado do Mac. A política mora no motor
(`engine/src/mobaile/services/perf.py`); o Swift lê os sinais do Mac e aplica a
parte visual. Antes dos perfis, os dois cortes que valem em qualquer perfil: o
espelho para quando ninguém vê (PERF-1) e espaça a captura com a tela parada
(PERF-2).

## O que mudou, por item

### PERF-1: pausar o trabalho invisível (F1, K2)

- RPC aditivo `stream.pause` e `stream.resume`. O motor para de capturar sem
  desligar o espelho; na retomada reenvia o quadro atual mesmo sem mudança, para
  a moldura não voltar com a tela de antes.
- A regra mora no motor: com `flow.run`, `flow.maestro_run` ou a escuta passiva
  ligados o espelho continua (`kept_for: "flow" | "passive"`), e a pausa pedida
  passa a valer quando eles terminam. O pedido vale também para o espelho que
  ligar depois (aparelho plugado com a janela coberta).
- Swift: `WindowVisibility` observa o `occlusionState` da janela principal, que
  cobre janela coberta, minimizada, app oculto (⌘H) e outro Espaço. A pausa
  espera 1 s (alternar de app por um instante não para a captura); a volta é
  imediata. A releitura automática da hierarquia em `stream.settled` espera a
  janela voltar, salvo com a escuta passiva ligada.
- Arquivos: `services/streaming.py` (pausa num Event próprio, `paused`,
  quadro forçado na retomada), `rpc/server.py` (`stream_pause`,
  `stream_resume`, `_aplicar_pausa` nos pontos onde flow e escuta começam e
  terminam), `App/WindowVisibility.swift`, `EngineSession.setWindowVisible`.

### PERF-2: espelho adaptativo (K1) e o laço que não descansava

- Depois de 5 capturas iguais seguidas e 2 s sem toque nem mudança, a captura
  cai para `idle_fps` (Completo 2, Equilibrado 1, Leve 0,5 por segundo).
  `input.tap`, `input.text` e o toque da escuta passiva chamam `wake()`: a
  captura seguinte sai na hora e a cadência volta ao normal. Quadro diferente
  também volta ao normal.
- Correção do laço (`streaming.py`, antes linha 179): quando a captura era mais
  lenta que o intervalo, a espera era de 10 ms e a thread recapturava logo em
  seguida. Agora descansa um quarto do tempo da captura, com piso de 50 ms.
- `stream.start` aceita `idle_fps` (`0` desliga).

### PERF-3: governador de perfis no motor (F3, F2)

- `services/perf.py`: `resolve(sinais, preferencia, anterior, agora)` pura,
  testada por tabela (`test_perf_governador.py`, 16 testes).
  - Piora na hora com sinal do sistema.
  - Melhora só depois de 60 s com o alvo melhor, um degrau por vez
    (`reason: "recuperando"` no degrau do meio). Um temporizador reavalia sem
    precisar de sinal novo.
  - Manual sempre ganha e vale na hora; a exceção é `thermal: "critical"`, que
    leva ao leve em qualquer escolha e sai com a mesma espera de 60 s.
  - Regras automáticas: `critical`/`serious` → leve; pressão de memória
    `critical` → leve; Economia de Energia num Mac modesto → leve; `fair`,
    pressão `warning`, Economia de Energia ou Mac modesto (até 8 GB, Intel ou
    Rosetta) → no máximo equilibrado.
- Knobs aplicados no motor, também com o espelho já ligado: fps, `idle_fps`,
  largura e qualidade do quadro (K4), plano B do iOS em JPEG (`simctl
  --type=jpeg`, K3, só no Equilibrado e no Leve), intervalo do vigia de
  aparelhos (K5) e corpo guardado das requisições novas do proxy (K7; depois
  da revisão, ver R1: o teto do histórico não muda mais com o perfil). O que o
  chamador fixou no `stream.start` (ou `poll_interval` no `devices.watch_start`)
  o perfil não mexe.
- K7: o motor do app nativo deixa de encher as filas `event_queue` do proxy e
  do analytics, que só o Tk lê (`queue_events=False`). Antes elas guardavam os
  4.000 e 10.000 primeiros eventos para sempre.
- RPC aditivo: `perf.signals`, `perf.set_preference`, `perf.status` e a
  notificação `perf.profile`. `PROTOCOLO_RPC.md` e fixtures atualizados.
- Leve nunca perde captura: teste de contagem (N eventos de rede e analytics
  entram, N notificações saem) no perfil leve.

| Knob | Completo | Equilibrado | Leve |
| --- | --- | --- | --- |
| Espelho, fps | 6 (o de hoje) | 4 | 2 |
| Espelho com a tela parada | 2 | 1 | 0,5 |
| Largura / qualidade JPEG | 900 / 80 | 720 / 70 | 600 / 60 |
| Plano B do iOS | PNG | JPEG | JPEG |
| Vigia de aparelhos | 1,5 s | 3 s | 5 s |
| Histórico proxy / analytics no motor | 2.000 / 5.000 | 2.000 / 5.000 | 2.000 / 5.000 (D-6) |
| Corpo guardado por requisição nova | 256 KB | 128 KB | 64 KB |
| Vidro próprio / molas | sim / sim | sim / sim | não / não |

Todos os valores fora do Completo são **Suposição** de partida. Os de largura e
qualidade vêm de custos medidos no M4 Pro (`perf-contexto.md`, K4).

### PERF-4: sensores no Swift (F2)

- `Engine/PerfSensors.swift`: `ProcessInfo.thermalState` e
  `isLowPowerModeEnabled` (com as duas notificações de mudança),
  `physicalMemory`, arquitetura, Rosetta (`sysctl.proc_translated`) e pressão de
  memória (`DispatchSource.makeMemoryPressureSource`). Vão ao motor por
  `perf.signals` na conexão, na volta de uma queda e a cada mudança.
- O espelho deixou de pedir `fps 6` e `max_width 900` fixos: tudo vem do perfil.
- Parte visual do leve, decidida pelo motor (`knobs.glass`, `knobs.animations`):
  - vidro próprio vira sólido pelo mesmo caminho de Reduzir transparência
    (`GlassSurface.resolve(perfLight:)`, ambiente `mbPerfLight`). Respeita o
    ADR 0006: só `Glass.swift` fala com a API do macOS 26;
  - as molas do `Motion` viram o crossfade de Reduzir movimento
    (`Motion.perfReduced`).
- Freio local: se o `perf.signals` falha (prazo de 5 s, ou motor fora), o Swift
  liga sozinho a parte visual do leve até a próxima resposta. Não decide perfil
  nenhum: o badge mostra `leve` com o motivo "o motor não respondeu".

### PERF-5: interface (F6)

- Ajustes › Desempenho (aba nova): segmentado Automático | Completo |
  Equilibrado | Leve, o perfil em uso com o motivo e uma frase do que muda. A
  escolha fica no `UserDefaults` e vai ao motor a cada conexão.
- Badge na barra de status (`PerfBadge`): `leve` ou `equilibrado` em mono,
  nada no Completo; ponto na cor de aviso quando quem escolheu foi o
  Automático. Tooltip e VoiceOver: "Perfil de desempenho, modo leve: Mac
  quente". Clique abre os Ajustes.
- Paleta de comandos (⇧⌘P; no app o ⌘K é "Capturar Agora"): "Ativar Modo Leve" e, com o leve fixado, "Voltar ao
  Desempenho Automático". Acha por "lento", "economia", "desempenho", "lite".

## Tamanho

Código de produção (`engine/src` e `apps/MoBaile/Sources`): +1.016 / −44
linhas com comentários; cerca de 775 sem linhas em branco e comentários de
linha. Passou do teto de ~600 combinado, sobretudo pelos comentários e pela
interface (PERF-5, ~110 linhas). Testes, docs e a bancada não entram na conta.

## Testes, antes e depois

| Suíte | Antes (`aeaefca`) | Depois | Rótulo |
| --- | --- | --- | --- |
| Motor (`make test-engine`) | 793 passaram | 837 passaram | Medido |
| UI Tk / QA de regressão | 20 / 11 | 20 / 11 | Medido |
| QA de ponta a ponta (`make qa`) | 145 verificações | 145 verificações | Medido |
| Swift (`make test-swift`) | 408 (27 puladas) | 422 (27 puladas) | Medido |
| Fixtures do contrato | em dia | regeneradas e em dia | Medido |

Testes novos: `test_perf_governador.py` (tabela da política e histerese),
`test_perf_rpc.py` (contrato `perf.*`, knobs aplicados, leve sem perda de
captura, fila sem leitor vazia), `test_espelho_pausa_rpc.py` (pausa, `kept_for`,
flow que começa com a janela oculta, toque que acorda o espelho),
`test_streaming.py` (pausa sem captura, quadro na retomada em até 500 ms,
cadência ociosa, laço que descansa), `PerfTests.swift` (janela oculta, sinais,
freio local, notificação, preferência, paleta) e `GlassTests` (leve vira
sólido).

## Medição antes × depois

Bancada nova: `tools/bench_stream.py`. Sobe uma cópia do motor (o `engine/src`
do checkout, ou outro com `--engine-src`), liga o espelho e o vigia de aparelhos
como o app faz, e mede por 60 s a CPU do motor e dos filhos que ele esperou (pelo
`getrusage` do próprio motor) e as capturas por segundo. Mediana de 3 rodadas.
Não fala com o WDA nem com o motor do app aberto (WDA e MJPEG apontados para
uma porta morta) e não escreve no log do app.

O simulador iOS estava ligado no início da rodada e foi desligado pelo dono
antes da primeira medição. Não liguei outro. Por isso **todas as medições
abaixo usam a fonte sintética**: um processo filho entrega um PNG de 1170×2532
(ou JPEG, quando o perfil pede) pelo pipe e o motor decodifica, como no
`simctl io screenshot -`. O custo do `simctl` em si (CoreSimulator, cerca de
0,15 s de CPU por captura no `perf-contexto.md`) fica de fora. O "antes" roda a
cópia do motor de `aeaefca`. Máquina: Mac16,8 (M4 Pro), 24 GB, na bateria. Na
fonte sintética o vigia de aparelhos não abre processo (a lista de simuladores
é falsa), então o ganho do K5 também fica de fora.

Cenário: espelho ligado, tela parada, 60 s, CPU em % de um núcleo (motor +
filhos), mediana de 3. **Medido.**

| Cenário | Antes | Depois | Capturas/s antes → depois |
| --- | --- | --- | --- |
| Completo, janela à vista | 19,9% | **6,8%** (−66%) | 5,85 → 1,98 |
| Completo, captura lenta (270 ms de parede, como o `simctl`) | 11,1% | **6,9%** (−38%) | 3,05 → 1,98 |
| Mesmo, cadência ociosa desligada (`idle_fps: 0`): só a correção do laço | 11,1% | **8,3%** (−25%) | 3,05 → 2,57 |
| Equilibrado | — | **2,3%** | 1,00 |
| Leve | — | **1,2%** (−94% contra o antes) | 0,50 |
| Janela oculta (`stream.pause`) | 19,9% (não pausava) | **0,1%** | 5,85 → 0 |

Comandos (o "antes" com `--engine-src` apontando para uma cópia do motor de
`aeaefca`, por exemplo `git archive aeaefca engine/src | tar -x -C /tmp/antes`):

```bash
.venv/bin/python tools/bench_stream.py --engine-src /tmp/antes/engine/src --fonte sintetica --params '{"fps":6,"max_width":900}'
.venv/bin/python tools/bench_stream.py --fonte sintetica
.venv/bin/python tools/bench_stream.py --fonte sintetica --captura-ms 270
.venv/bin/python tools/bench_stream.py --fonte sintetica --captura-ms 270 --params '{"idle_fps": 0}'
.venv/bin/python tools/bench_stream.py --fonte sintetica --perfil equilibrado
.venv/bin/python tools/bench_stream.py --fonte sintetica --perfil leve
.venv/bin/python tools/bench_stream.py --fonte sintetica --pausado
```

Leitura:

- A tela parada é o caso medido no app do dono (`perf-contexto.md`: cerca de
  0,5 a 0,7 núcleo só em `simctl`). Pela proporção de capturas por segundo
  (3,5 → 2 no Completo, → 0,5 no Leve, → 0 com a janela oculta), o ganho no
  caminho real do iOS deve ser parecido ou maior, porque o custo do `simctl` é
  por captura. **Extrapolado**: o caminho real não foi medido.
- RSS do motor ficou entre 119 e 141 MB em todos os cenários, antes e depois
  (Medido; dominado pelo Pillow e pelo quadro sintético).

**Não medido nesta rodada:** caminho real do iOS (`simctl`) e do Android
(`screencap`), tela mudando (custo de codificar e mandar quadro), CPU do app
Swift (decodificação, vidro e animação), M1 de 8 GB e Intel.

## Como validar no app

Depois de o orquestrador empacotar (`make update-native`):

1. **Janela oculta.** Com um simulador ou aparelho e o espelho ligado, cubra a
   janela do Mo baile com outra (ou minimize, ou ⌘H) por mais de 1 s. No
   Monitor de Atividade, o `simctl`/`adb screencap` some e a CPU do Python do
   motor cai perto de zero. Volte: a moldura mostra a tela atual em menos de
   meio segundo. Com um flow rodando ou a escuta passiva ligada, o espelho não
   pausa.
2. **Tela parada.** Com a janela à vista e a tela do app parada, depois de uns
   2 s o número de quadros cai (Monitor de Atividade: menos `simctl` por
   segundo). Toque no espelho: a mudança aparece no tempo de sempre.
3. **Modo leve manual.** ⇧⌘P › "Ativar Modo Leve". A barra de status mostra
   `leve`; a paleta e a cápsula do Início perdem o vidro (ficam sólidas); os
   painéis abrem sem mola. Tooltip do badge: "modo leve: escolhido em Ajustes".
   ⇧⌘P › "Voltar ao Desempenho Automático" tira o badge.
4. **Automático.** Ligue a Economia de Energia (Ajustes do Sistema › Bateria):
   o badge vira `equilibrado` com um ponto amarelo e o motivo "Economia de
   Energia ligada". Desligue: em cerca de 60 s volta ao Completo.
5. **Ajustes › Desempenho.** O segmentado mostra a escolha; "Em uso" mostra o
   perfil e o motivo. A escolha sobrevive a fechar e abrir o app.

## Riscos

- **Atraso de mudança espontânea.** Com a tela parada há 2 s, uma mudança que
  não veio de toque (carregamento que termina, notificação) chega com até
  0,5 s no Completo e até 2 s no Leve. Toque e digitação acordam na hora.
  Aceito pelo orquestrador no Completo (D-8).
- **8 GB conta como modesto.** No Automático, um M1 de 8 GB começa no
  Equilibrado (4 fps em vez de 6). Mantido pelo orquestrador (D-7).
- **Corpo menor no leve.** Requisições capturadas no Equilibrado e no Leve
  guardam até 128 e 64 KB de corpo (o resto marcado como truncado, com o
  tamanho total). O histórico em si não muda com o perfil (D-6, R1).
- **`STREAM_FPS` e `STREAM_QUALITY` do ambiente** deixaram de ser o padrão do
  `stream.start` sem parâmetros: o padrão agora é o perfil.
- **MJPEG do WDA continua lendo com o espelho pausado.** A thread do leitor e o
  WDA seguem codificando enquanto a janela está oculta (Não medido: o WDA
  estava fora do ar). Proposta abaixo.
- **`MotionPolicy.shared`** continua sendo o ponto único que o app lê na hora
  da animação; agora é uma instância com trava, injetável na sessão (R6).
- **Freio local durante a queda do motor.** Se o motor cai, o próximo
  `perf.signals` falha e a parte visual vai ao leve até a reconexão. Visual,
  sem efeito no motor.

## Pendente e decisões do dono

Fora do escopo desta entrega, por pedido:

- **Intel (K14).** O app é só arm64; sem binário universal não existe modo
  leve no Intel. A regra `arch == "x86_64"` já está no governador para quando
  o empacotamento mudar.
- **Cadência padrão do Completo.** Continua 6 fps, 900 px, q80.
- **Telemetria externa.** Nada sai da máquina.

Decisões pendentes:

- **Alvo do modo leve.** SLO proposto no `perf-contexto.md` (Suposição): com a
  tela parada, app + motor + filhos em até 10% de um núcleo. Confirmar.
- **Valores dos knobs num M1 de 8 GB.** Rodar `tools/bench_stream.py --perfil
  leve` e `--perfil equilibrado` lá (e com `--fonte ios` e o simulador ligado)
  antes de fixar fps, `idle_fps` e o corpo guardado.
- Decididas pelo orquestrador em 04/11: histórico igual em todos os perfis
  (D-6), Mac de 8 GB começa no Equilibrado (D-7), cadência ociosa aceita no
  Completo (D-8).

Propostas seguintes, em ordem de ganho:

1. Medir o caminho real do iOS (`--fonte ios`) com o simulador ligado e o app
   fechado, antes e depois. É o número que falta.
2. Pausar também o leitor MJPEG do WDA com a janela oculta e religá-lo na
   retomada.
3. Teto das tabelas da interface (hoje 1.000 fixo em `trimTraffic`) pelo perfil.
4. scrcpy pelo perfil (o front ainda pede 60 fps e 1080 px fixos, K9).
5. Consumo medido como terceira entrada do governador (CPU do motor e dos filhos
   por `getrusage`, quadros atrasados), com o aviso "Ativar modo leve?" quando o
   Completo estiver fixado e o Mac sofrendo (F3, F6).
6. Slot único de quadro no motor (F4): o quadro grande não segura o lock de
   escrita na frente de respostas e eventos.
7. Teto de memória do proxy por bytes (F7).
8. Hierarquia "retrato" no leve (O4) e detecção de Python sob Rosetta no motor
   (O2).

## Correções da revisão

Revisão independente em `scratchpad/revisao-desempenho.md` (mesmo modelo, não
conta como validação externa). Um commit por achado; `make check` e
`make test-swift` verdes antes de cada um.

| Achado | Commit | O que mudou | Teste |
| --- | --- | --- | --- |
| R1 · histórico cortado pelo perfil (D-6) | `94dac6a` | O teto do histórico (proxy 2.000, analytics 5.000) é o mesmo em todos os perfis. Saíram `proxy_history` e `analytics_history`; entrou `proxy_body_capture_kb` (256, 128, 64), que só vale para requisições novas. Teto estourado: aviso no log, uma vez, e `perf.status.history_full`. Texto de Ajustes › Desempenho reescrito | `test_perf_rpc`: teto igual nos três perfis; 600 requisições e 2.500 eventos ficam no histórico depois de o Mac esquentar; `history_full`; corpo truncado no limite |
| R2 · freio local preso | `2d9ffd1` | `applyPerf` zera `semMotor`, e ele roda na resposta do `perf.signals`, do `perf.set_preference` e na notificação `perf.profile` | `PerfTests.testRespostaDoMotorTiraOFreioLocal` |
| R3 · corrida em `_aplicar_pausa` | `3332c34` | Pedido, decisão e `pause()`/`resume()` sob `_pausa_lock` | `TestPausaSemCorrida`: reproduz o fim de flow cruzando com a retomada (falha sem a trava; conferido) |
| R4 · `stream.resume` que falha | `9c5a245` | Retomada que falha é repetida em 0,5, 1, 2 e 4 s enquanto a janela estiver visível; ocultar cancela | `PerfTests.testRetomadaQueFalhaERepetidaSoComAJanelaVisivel` |
| R5 · perfil trocado durante o `stream.start` | `011ba4b` | O start reaplica `_aplicar_knobs()` depois de publicar o espelho | `TestPerfilDuranteOStart` |
| R6 · higiene do Swift | `76b4493` | Observadores e fonte de pressão de memória numa caixa que os desfaz no `deinit`, mais `stop()`; pressão de memória começa no estado atual (`kern.memorystatus_vm_pressure_level`); `WindowVisibility` lê o estado inicial da janela; `Motion.perfReduced` virou `MotionPolicy` injetável (a sessão de teste usa a própria) | `PerfTests.testSensoresParamDeObservar`; teste de sinais confere a política injetada |

Testes depois das correções: motor 837 → 842, Swift 422 → 425 (27 puladas),
QA de ponta a ponta e fixtures em dia.

Não corrigido, com motivo:

- **Leitor MJPEG do WDA com o espelho pausado** e o restante de "Não
  verificado" da revisão (acordar o Mac, troca de Space, protetor de tela,
  `simctl --type=jpeg` no caminho real): pedem o app instalado ou o simulador
  ligado, e esta rodada não mexe no app do dono. Continuam nas propostas e no
  roteiro de validação manual.
- **Repetir o `perf.signals` com recuo** (opcional no R2): com o R2, qualquer
  resposta do motor já tira o freio, e o próximo evento de sensor manda os
  sinais de novo. Ficou de fora para não somar outro temporizador.

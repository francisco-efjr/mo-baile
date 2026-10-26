# Revisão de qualidade de código (papel `codigo`), Mo baile 3.11.0

Data: 26/10/2026 · Branch `melhoria/2026-10-26-rodada3`, HEAD `a74407c` · Status: DONE_WITH_CONCERNS · rascunho.
Revisão por leitura de arquivos, não de diff: não distingue código novo de pré-existente. Nada foi executado (sem `make`, `swift test`, `pytest`). Mesmo modelo do autor: independência parcial; recomendo leitura humana antes de implementar.

Método: filtro de alto sinal do `code-reviewer` (bug real de comportamento, não estilo), `playbook` (check antes de mexer, rótulos de evidência) e `tech-debt-triage` (frequência de mudança x dor; sem histórico git nesta fase, então a ordem é por dor e por área nova nas 3.10/3.11). Não houve painel de saúde (`code-health-report`): ele executa ferramentas, e a fase é só leitura.

Arquivos lidos por inteiro: `engine/src/mobaile/rpc/server.py` (2357 linhas), `rpc/contract.py`, `services/flows.py`, `services/maestro_flow.py`, `services/home.py`, `services/setup.py`, `services/devices.py`, `adapters/proxy.py`, `adapters/analytics_logcat.py`, `adapters/flow_devices.py`, `adapters/ios_wda.py`, `adapters/appium.py` (início), `adapters/adb.py` (até a linha 420), `domain/models.py` (início); `apps/MoBaile/Sources/MoBaile/Engine/EngineSession.swift` (1760 linhas), `Engine/EngineClient.swift`, `App/AppState.swift`, `Views/Home/HomeView.swift`, `Views/Environment/EnvironmentView.swift`.

## Limites desta leitura

- Só tive Read: sem Grep, Glob nem Bash. Não consegui listar pastas. Não abri: a definição de `RunState`, a sheet do executor de fluxo, `SetupInstaller`, `HomeDailyContent`/`HomeFirstRunContent`, os testes Swift e Python. Onde digo "ninguém chama X", vale para os arquivos acima.
- Comportamento em tempo de execução (WDA real, adb real, SwiftUI) é Inferido ou Não verificável. Nenhum "Verificado" abaixo vale para execução.

## Propostas (ordem de prioridade; todas cabem no corte de 6 melhorias e ~600 linhas)

| ID | Origem | Resumo | Esforço | Linhas (sem testes) | Contrato RPC | Regra de negócio |
|---|---|---|---|---|---|---|
| CODE-1 | M4 | Progresso do fluxo avança e "cancelado" deixa de aparecer como FAIL | P (M no backlog) | ~110 | aditivo: `flow.step`, campo `cancelled` | Não muda resultado nem documento; muda o estado mostrado |
| CODE-2 | M8 | Laço de notificações não espera chamada ao motor; teto do analytics no front | P | ~60 | não | Não |
| CODE-3 | novo (3.11) | Início não refaz a varredura inteira a cada abertura da tela | P | ~15 | não | Não |
| CODE-4 | novo (3.10/3.11) | Alvo Android não pronto (`unauthorized`, `offline`, `booting`) some da Início e do vigia | P | ~25 | não | Sim: muda o que a Início oferece como alvo |
| CODE-5 | novo (3.10) | Runner do Maestro: tela 0x0 toca em (0,0); sessão WDA caduca no iOS | P | ~30 | não | Sim: o flow passa a falhar com motivo em vez de tocar no lugar errado |

---

### CODE-1 (origem M4): progresso do fluxo nunca avança; cancelamento aparece como falha

**Problema.** A interface escolhe o passo em execução por regex no texto do log, e a regex não casa com o que o runner imprime.

- Regex do front: `EngineSession.swift:1738-1741`, `#"(?i)passo\s+(\d+)"#`, usada em `flow.log` (`:1671-1681`).
- O runner de `flow.run` imprime `▶ [{i}/{total}] Executando: ...` (`services/flows.py:379`, dentro do script gerado, com prefixo `[HH:MM:SS]`) e `✔ [{i}/{total}] Passo {var_name} concluído` (`flows.py:397`). Nenhuma das duas tem "passo" seguido de número. Só `FALHA no passo {i}` (`flows.py:394`) e `Erro inesperado ao executar o passo {i}` (`flows.py:390`) casam, ou seja, a barra só se mexe quando o fluxo já falhou.
- O runner do Maestro imprime `▶ [{posicao}] {descrição}` (`services/maestro_flow.py:746`), onde `posicao` é `n/total`, `onFlowStart`, `  runFlow` ou `  retry`. Mesmo problema.
- Além disso, `currentRunStep` é índice na lista de passos gravados (`state.steps`). Num flow do Maestro (`runMaestroFlow`, `EngineSession.swift:1228`) o índice seria o do YAML: números de listas diferentes.
- Cancelamento: `flow.finished` leva só `success` e `message` (`server.py:1845-1848` e `:1979`). O front faz `runState = payload.success ? .passed : .failed` (`EngineSession.swift:1686`). Parar o fluxo de propósito vira "FAIL: Automação cancelada." (`flows.py:510`) ou "Flow cancelado." (`maestro_flow.py:724`). O próprio `flow_stop` registra `_flow_cancelled`, mas o contrato não o expõe.
- Duplicação: `ao_terminar` está copiado em `flow_run` (`server.py:1840-1848`) e em `flow_maestro_run` (`:1974-1983`), com a mesma leitura de `_flow_cancelled` sob lock.

Rótulos: regex x formato do log, **Verificado** (linhas lidas); barra parada em execução real, **Inferido**; o backlog (`propostas-priorizadas.md`, item 7) já registrava a primeira metade e a segunda continua aberta.

**Melhoria.**
1. Motor: `notify("flow.step", {"index": i, "total": n, "source": "recorded" | "maestro"})`.
   - `flow_run`: no `ao_sair`, reconhecer a linha do próprio runner (`▶ \[(\d+)/(\d+)\]` depois do prefixo de hora) e emitir `flow.step`. A regra fica no motor, que é o dono do formato do log.
   - Maestro: `FlowRunner` ganha um callback opcional `on_step(index, total)` chamado em `run()` para os passos de nível 1 (`maestro_flow.py:718-720`); `FlowThread` o repassa.
2. Motor: `flow.finished` ganha `cancelled: bool`, hoje já calculado como `cancelado`. Um helper único `_finish_flow(success, message)` substitui as duas cópias de `ao_terminar`.
3. Contrato: `flow.step` entra em `contract.NOTIFICATIONS`; `docs/PROTOCOLO_RPC.md` e `make fixtures`. `PROTOCOL_VERSION` continua 2.
4. Front: tratar `flow.step` (atualiza `currentRunStep` só quando `source == "recorded"`; guardar `total` para a barra) e remover `numeroDoPasso`. Em `flow.finished` com `cancelled`, terminar em `.idle` com a mensagem e linha de log `STOP` (decisão abaixo), sem `FAIL`.

**Ganho.** Quem roda o fluxo gravado vê o andamento real e deixa de ver "falhou" depois de parar. Esforço P: ~45 linhas Python e ~50 Swift. Risco baixo: tudo aditivo; front antigo ignora `flow.step`.

**Aceite e verificação (falham antes, passam depois).**
- pytest: alimentar `ao_sair` com a linha real do runner e esperar `flow.step` com `index=2,total=3`; teste do Maestro com `FakeDevice` esperando `on_step` 1..n; `flow.stop` seguido de fim esperando `cancelled=True` (já existe processo real em `test_flows.py`, citado na revisão de 14/10).
- Swift (`FakeEngine` empurra notificação): `flow.step` index 2 leva `currentRunStep == 2`; `flow.finished` com `cancelled` não deixa `runState == .failed`.
- Fixture regerada e `test_notifications_match_contract` (deriva) passando.

---

### CODE-2 (origem M8): o laço de notificações espera o motor, e o analytics não tem teto no front

**Problema.** Um único laço lê todas as notificações em ordem (`EngineSession.swift:344-349`), e o fluxo `notifications` é `.unbounded` (`EngineClient.swift:88`). Três pontos seguem abertos:

1. `device.changed` chama `await activateDevice()` dentro do laço (`EngineSession.swift:1638`), que faz `screen.size`, `screen.capture`, `hierarchy.dump` e `stream.start` em sequência (`:820-828`). O dump do Android leva de 1 a dezenas de segundos (`server.py:863-904`). Enquanto isso, `proxy.event`, `analytics.event`, `flow.log` e `flow.finished` ficam na fila: não se perdem, mas a interface mostra tudo atrasado, inclusive o fim do fluxo.
2. `home.changed` (3.11) faz `await refreshHome()` no mesmo laço (`:1613-1614`). `home.summary` roda `adb devices`, dois `adb shell` por aparelho, `emulator -list-avds` e `simctl list --json` (`home.py:283-333`); com a fila `query` ocupada, espera até 20 s (`contract.py:93`). O motor emite `home.changed` a cada recente gravado e a cada troca de aparelho (`server.py:640-641`, `:703`, `:709`).
3. O teto de 1000 itens só é aplicado em `proxy.event`: `trimTraffic()` está em `:1712`, e `analytics.event` (`:1714-1716`) só faz `append`. Numa sessão com escuta de Analytics e sem proxy, a lista cresce sem limite (o motor guarda 5000: `analytics_logcat.py:43`). `runLog` (`:1674`) também não tem teto.
4. Ordem em `activateDevice`: o espelho ao vivo só liga depois da hierarquia (`:823-826`). O backlog pedia espelho antes da árvore.

Rótulos: pontos 1 a 4 **Verificado** (linhas); atraso percebido, **Inferido**.

**Melhoria (só Swift, `EngineSession.swift`).**
- `device.changed`, `home.changed` e `passive.step` passam a disparar uma tarefa própria e cancelável (`activationTask`, `homeRefreshTask`), no mesmo padrão de `debouncedRefreshHierarchy` (`:1007-1016`). `device.changed` cancela a ativação anterior e mantém ativação e `refreshDevices` na mesma tarefa. `home.changed` coalescido: no máximo uma leitura em voo e uma pendente.
- `trimTraffic()` também depois de `analytics.append`; teto para `runLog` (por exemplo 2000 linhas).
- `activateDevice`: `startStream()` antes de `refreshHierarchy()`.

**Ganho.** Interface responsiva com USB instável, Android lento ou muitos recentes. Esforço P (~60 linhas). Risco médio-baixo: o cuidado é a ordem entre ativação e `disconnect()`; `stopBackgroundWork` cancela a nova tarefa junto das outras (`:366-378`).

**Aceite e verificação.**
- Swift: 1005 `analytics.event` sem nenhum `proxy.event` leva `analyticsEvents.count <= 1000` (falha hoje: 1005).
- Swift com `FakeEngine.metodosRetidos` segurando `hierarchy.dump`: empurrar `device.changed` e depois `flow.finished`; o estado do fluxo muda antes de liberar o dump (hoje só depois).
- `stream.start` registrado antes de `hierarchy.dump` na ordem de chamadas do `FakeEngine`.

---

### CODE-3 (novo, 3.11): a Início refaz a varredura inteira toda vez que aparece

**Problema.** `HomeContent` chama `conferir(seMaisVelhoQue: 0)` em `.task` (`Views/Home/HomeView.swift:46`), ou seja, toda vez que a pessoa volta à Início. O `0` anula a trava de 3 s que só vale para o retorno ao primeiro plano (`:48-50`). A varredura é `refreshSetup()` (`EngineSession.swift:646-653`): `setup.check` mais `home.summary`, que por dentro roda `setup.run` de novo (`home.py:379-395`). O resultado: duas checagens de instalação, `adb devices`, `getprop` por aparelho, `emulator -list-avds` e `simctl list --json` a cada navegação para a Início, e logo depois do splash, que acabou de fazer o mesmo em `refreshEnvironment` (`:632-641`). Tudo na fila `query`, a mesma de `wda.status`, que a sessão consulta a cada 5 s (`:560-571`).

Rótulos: **Verificado** (linhas); custo medido, **Não verificável** (precisa de cronômetro).

**Melhoria.** Extrair `conferir` para `EngineSession.refreshSetupIfStale(olderThan:)` e usar 10 s na abertura da tela e 3 s no retorno ao primeiro plano. `lastSetupCheck` já existe. Sem mudar `home.summary` agora (fundir `setup.check` dentro dele seria mudança de contrato; fica como follow-up).

**Ganho.** Menos subprocessos e fila `query` livre; sensação de fluidez ao navegar. Esforço P, ~15 linhas, risco baixo (pior caso: a Início mostra dados de até 10 s atrás; o `home.changed` cobre o que importa).

**Aceite e verificação.** Swift: `FakeEngine` conta chamadas; duas chamadas seguidas a `refreshSetupIfStale(olderThan: 10)` fazem uma só a `setup.check` e uma só a `home.summary` (hoje a lógica está na View, sem teste possível).

---

### CODE-4 (novo, 3.10/3.11): alvo Android que ainda não está pronto aparece como utilizável

**Problema.**
- `HomeService._targets` percorre `adb.list_devices_typed()` e monta cada alvo com `running=True` sem olhar `d.state` (`services/home.py:296-302`). `list_devices_typed` devolve `unauthorized`, `offline` e `booting` (`adapters/adb.py:133-152`), com `Device.is_ready` só para `device` (`domain/models.py:47-49`). Esses aparelhos aparecem na Início com "Usar Este" e as mesmas `capabilities` de um pronto (`home.py:286-292`). Clicar leva a `select` e `activateDevice`, que falham sem explicação.
- O vigia já tem a regra certa para `unauthorized`/`offline` (`devices.py:129-131`), mas não confere `sys.boot_completed`. O próprio docstring de `list_devices_typed` diz o efeito de consumir `device` antes da hora: tamanho de tela errado e quadro rasgado, "e nada relia depois". O vigia usa `adb.list_devices()` (`devices.py:131`), sem esse filtro, e o front reage a `device.changed` com `activateDevice` (`EngineSession.swift:1638`), que lê `screen.size` uma vez (`:843-847`).

Rótulos: ausência do filtro, **Verificado** (linhas); falha de usuário no vigia durante o boot de um emulador, **Inferido** (depende do tempo entre `adbd` e `boot_completed`); confiança 75 no segundo ponto.

**Melhoria.**
- `home.py`: ignorar alvos com `not d.is_ready` (ou mantê-los sem "Usar", com `running=False` e um `blocked_by` próprio; a opção simples é ignorar, igual ao vigia).
- `devices.py`: em `_list_targets`, para Android, aceitar o serial só se `adb.is_boot_completed(serial)`, guardando num conjunto os seriais já confirmados (limpar quando somem da listagem) para não pagar um `adb shell` por varredura.

**Ganho.** Início honesta com aparelho de verdade e menos erro depois de plugar ou ligar emulador. Esforço P (~25 linhas). Risco baixo; muda a lista de alvos exibida (regra de negócio, sem mudar contrato: o campo `targets` é o mesmo).

**Aceite e verificação.**
- pytest `HomeService` com adb falso devolvendo `Device(state="unauthorized")`, `"offline"`, `"booting"`: nenhum entra em `targets` (hoje entram).
- pytest `DeviceWatcher.poll_once` com `is_boot_completed` falso e depois verdadeiro: nenhum `device.changed` antes, um depois.

---

### CODE-5 (novo, 3.10): runner do Maestro toca em (0,0) com tela sem medida e não renova a sessão do WDA

**Problema.**
- `IOSFlowDevice.screen_size` devolve `(0, 0)` em qualquer falha (`adapters/flow_devices.py:137-145`), e o `FlowRunner` usa o resultado sem checar: `resolve_point(sel.point, largura, altura)` com `0` dá `(0,0)` (`maestro_flow.py:799-802` e `:557-563`), e `_deslizar` calcula as quatro coordenadas a partir de `(0,0)` (`:862-867`, `:873-875`). O flow toca ou desliza em (0,0) e o log diz `▶ [n/total] tapOn ponto 50%,50%` seguido de sucesso. Só o filtro de visibilidade trata zero (`:764-767`).
- O endpoint usado é `GET {wda}/window/size` sem sessão (`flow_devices.py:141`), enquanto o resto do adapter usa rotas com `/session/{sid}` (`ios_wda.py:166`). Se esse caminho não existir no WDA, a falha é permanente no iOS e vira o caso acima. **Suposição**: não abri o WDA nem executei; confirmar contra um simulador antes de mudar a rota.
- `IOSFlowDevice._wda` (`flow_devices.py:106-124`) usa `ios._ensure_session()` em cache e nunca invalida o id quando o WDA responde `invalid session`, ao contrário de `IOSBridge.tap` (`ios_wda.py:126-158`). Digitar, apertar tecla e deslizar no Maestro falham até reiniciar o motor depois que o WDA recria a sessão. **Inferido**.

**Melhoria.**
- `FlowRunner`: método `_tela()` que lê `device.screen_size()` e levanta `FlowFailed("nao foi possivel medir a tela do aparelho")` se algum lado for 0; usar em `_alvo` (só no caminho `point`), `_deslizar` e `_r_swipe`.
- `IOSFlowDevice._wda`: reaproveitar `IOSBridge._sessao_invalida`; em sessão inválida, limpar `ios.session_id` e repetir uma vez (só em 404 de sessão, como no `tap`: repetir após 500 duplicaria a ação).
- `screen_size`: tentar a rota com sessão se a sem sessão falhar (depois de confirmar).

**Ganho.** O flow falha com motivo em vez de agir no lugar errado e dar sucesso. Esforço P (~30 linhas). Risco baixo.

**Aceite e verificação.** pytest com `FakeDevice.screen_size() == (0, 0)`: `tapOn: {point: "50%,50%"}` e `swipe: {direction: UP}` falham com `FlowFailed` e `device.taps == []` (hoje tocam em (0,0)); `_wda` com `requests` simulado devolvendo 404 `invalid session` uma vez e 200 depois: uma repetição e `session_id` renovado.

---

## Itens do backlog já resolvidos ou que não se sustentam

- **M1** (segundo aparelho volta ao primeiro): resolvido. `DeviceWatcher.set_target` guarda o alvo da sessão (`devices.py:101-116`) e `session_select_device` o chama (`server.py:552-556`). O watcher só notifica na transição (`devices.py:169-189`) e ignora deteção de outra plataforma (`server.py:631-635`).
- **M5** (serviços de fundo morrem em silêncio): resolvido. Rede final em `_on_passive_tap` (`server.py:1788-1792`), `TimeoutExpired` tratado em `_teclado_aberto` (`:1722`), `analytics.start` religa se o `logcat` morreu (`analytics_logcat.py:276-284`, `:413-416`).
- **M2** (desmonte do proxy apaga o valor original): resolvido em memória. `_proxy_previous` guarda o original (`adb.py:46`, `:388-397`) e o motor repete desmontes pendentes quando o serial reaparece (`server.py:1140-1214`). O diário em disco segue adiado, como decidido em 14/10.
- **M6** (sessão WDA em cache nunca caduca): resolvido para `tap` (`ios_wda.py:126-158`). Sobra o caminho do Maestro, tratado em CODE-5.
- **M11** (fila do proxy): rebaixado, fila limitada em `MAX_HISTORY*2` (`proxy.py:507`, `:562-565`) e a do analytics com descarte do mais antigo (`analytics_logcat.py:161`, `:454-464`). `server.py` inteiro não lê nenhuma das duas (só o app Tk, congelado, as consome). Resíduo: a fila do proxy retém os 4000 primeiros eventos mesmo depois de o `deque` de 2000 os ter expulsado; no pior caso são 512 KB por evento (`MAX_BODY_CAPTURE` nos dois corpos), mas o caso típico é de dezenas de MB. Baixa; não remover a fila.
- **M4, primeira metade** (progresso): confirmada aberta, é o CODE-1. A parte Python do cancelamento não era bug (processo real já testado); o buraco é só o contrato.
- **M8, parte "espelho antes da hierarquia"**: ainda aberta (CODE-2, ponto 4). As outras duas partes também.
- **R1** (servidor RPC dividido): continua verdadeiro, `server.py` tem 2357 linhas (Verificado), mas não cabe no corte (mover handlers é diff grande sem ganho de comportamento) e a validação de 14/10 já pedia para não fazer agora. O CODE-1 remove a duplicação `ao_terminar`, que é o pedaço de domínio de fluxo mais fácil de extrair depois.
- **R2** (EngineSession por funcionalidade): continua verdadeiro, 1760 linhas (Verificado). A seção Relatório (`:1400-1585`) é candidata natural a coordenador, mas toca todas as views que chamam `session.runReport`; fora do corte desta rodada. CODE-2 já separa duas tarefas do laço sem mexer nas views.
- **F2** (busca sem travar), **M3**, **M10**, **M13**, **S1/S2**: fora da minha área; não reconferi.

## Dúvidas (confiança abaixo de 80 ou sem linha citável)

1. `passive.step` grava o código no editor, mas `passive.text` (`server.py:1745`) não tem tratamento no front: `handle` não lista o método (`EngineSession.swift:1599-1721`). O passo no motor recebe o texto, e a lista lateral só vê isso se algo chamar `refreshSteps`. Impacto visível, **Não verificável** sem abrir a view dos passos.
2. `flow_run` gera o script do runner (que contém o texto digitado, em claro) e, se `flow.stop` chega entre `generate_hidden_runner_script` e `run_flow_in_background` (`server.py:1857-1868`), o `RequestCancelledError` sobe sem apagar o arquivo: só `FlowExecution.run` remove o temporário. Mesma coisa se `run_flow_in_background` falhar. **Inferido**; encaminhar ao especialista de segurança, é o mesmo tema do S2.
3. `refreshDaemonStatus` consulta `engine.info`, `wda.status` e `recording.status` a cada 5 s (`EngineSession.swift:560-591`), contra a regra de "a interface nunca faz polling" e a especificação da Início (`docs/design/home/README.md`, "sem polling"). Também disputa a fila `query` com `home.summary`. Não propus porque o backlog já registra a decisão (14/10, "Decisões que são suas", item 3).
4. `home.summary` repete `setup.run` que `setup.check` já fez, e `refreshSetup` chama os dois (`EngineSession.swift:646-653`). A solução limpa é um só método; é mudança de contrato, fica como follow-up depois do CODE-3.
5. `RecentStore` grava `recentes.json` com caminhos de arquivos do usuário na pasta de dados padrão, sem restringir permissão (`home.py:121-133`); baixo, tema de segurança.
6. `AndroidFlowDevice.eraseText` chama `adb input keyevent` uma vez por caractere (até 1000, `maestro_flow.py:830-835`); lento, não incorreto.

## O que foi checado e o que não foi

Checado por leitura: caminho completo do fluxo (`flow.run`, `flow.maestro_run`, `flow.stop`, notificações e fim), laço de notificações e supervisão do motor no front, filas e históricos do proxy e do analytics, vigia de aparelhos, `home.*`, `setup.*`, runner e exportação do Maestro, telas Início e Ambiente (partes lidas).
Não checado: testes existentes (Python e Swift), `RunState` e as views do executor, `SetupInstaller`, `HomeDailyContent`/`FirstRun`, `services/report/*`, `services/codegen.py`, `security/*`, `apps/tk-legacy` (congelado), comportamento em aparelho e simulador reais.

## Decisões pendentes do humano

1. **Cancelado na interface** (CODE-1): sem criar caso novo em `RunState`, terminar em `.idle` com mensagem e log `STOP`. Se preferirem um caso `.cancelled`, é preciso revisar os `switch` exaustivos nas views que eu não li (suposição adotada: `.idle`; se errada, o custo é uns 20 linhas Swift a mais).
2. **Contrato** (CODE-1): aceitar `flow.step` e `cancelled` em `flow.finished` (aditivo, `PROTOCOL_VERSION` 2) e a versão minor correspondente.
3. **CODE-4**: alvo não pronto ser ocultado ou aparecer desabilitado com o motivo. Adotei ocultar (como o vigia).
4. **CODE-5**: confirmar a rota `window/size` do WDA contra um simulador real antes de trocá-la.

## Ordem sugerida e ligação com as regras do projeto

CODE-1, CODE-2, CODE-4, CODE-5, CODE-3. Todas mexem em `engine/src/` ou `apps/MoBaile/`: `make check`, `make test-swift`, `make fixtures` (CODE-1), versão SemVer, `make update-native` com o app fechado por ⌘Q do dono e o OK do `verify-native` na entrega. Refatoração pura (extrair `_finish_flow`) e mudança de comportamento em commits separados.

# Revisão independente do front da B1 (área Execução)

Alvo: commit `76f01d2` (feat(ui): área Execução), branch `melhoria/2026-11-12-execucao-projeto`
Intenção: [CONTRATO.md](../CONTRATO.md) (seção Front), [dev-front.md](dev-front.md),
[docs/PROTOCOLO_RPC.md](../../../PROTOCOLO_RPC.md) (versão do checkout, com as mudanças
ainda não commitadas do dev do motor), fixtures em
`apps/MoBaile/Tests/MoBaileTests/Fixtures/engine_payloads.json`.
Modo: agente (sem estilo) | Plataforma: macOS, SwiftUI + AppKit | Data: 2026-11-12
Papel: `code-quality-refactoring:code-reviewer`, com olhar de `ux-ui-design` para estados e acessibilidade.

Status: DONE_WITH_CONCERNS (rascunho, modo sem interação)   Veredito: aprovar com ressalvas
(nenhum achado P0; o FR-01 deve ser corrigido antes de instalar para o dono).

Revisão feita por leitura do código, das fixtures, do protocolo e das capturas. Não rodei
`swift test` nem o app.

## Resumo

- A área Execução está completa: DTOs tolerantes, sessão, estado, telas, 32 testes.
- O fluxo de confiança e o de `hub_unknown` **não entram em laço**. Cada nova tentativa
  depende de um clique do dono, e o motor confere a confiança antes do hub
  (`server.py:2608-2627`). O front repassa `trusted` na repetição do hub
  (`ExecutionModels.swift:193`).
- O problema principal está no **ciclo de vida**:
  - a primeira leitura, se cancelada, deixa o projeto sem análise e sem saída pela UI
    (FR-01);
  - o doctor ocupa a fila `project` sem bloquear as ações que dependem dela (FR-02);
  - as ações do cabeçalho ficam livres durante o `run.start` (FR-03);
  - a queda do motor não limpa o "rodando" (FR-04).
- O console em `NSTextView` está correto quanto ao diff incremental e ao teto. Não achei
  vazamento.
- No quesito segredos, nada sensível é exibido ou registrado no log pelo front.

## Achados

| ID | Sev | Categoria | arquivo:linha | Problema e cenário concreto | Correção sugerida | Conf. | Rótulo |
|---|---|---|---|---|---|---|---|
| FR-01 | P1 | Estado / ciclo de vida | `Views/Execution/ExecutionView.swift:58-60`; `Engine/EngineSession.swift:1865-1890` e `:2139`; `Engine/EngineClient.swift:303,331-333`; `ExecutionView.swift:228`; `Models/ExecutionModels.swift:207` | A primeira leitura roda dentro do `.task(id:)` da view. O `EngineClient.call` transforma o cancelamento da tarefa em `EngineError.cancelled`, e o `executionFailure` engole esse erro em silêncio. Cenário: o dono aperta ⌘6 e sai para ⌘1 antes do `project.inspect` acabar, o que leva alguns segundos quando não há interpretador, porque o motor sonda os Pythons por até 4 s. Resultado: `loadedOnce` fica `true`, `currentProjectID` fica definido e `inspection` fica `nil`. Na volta, o `loadExecution` só chama `refreshRunStatus` (`:1868-1871`). A coluna mostra para sempre "Lendo o main do projeto…", agora sem spinner. O Rodar fica bloqueado com "Abra um projeto para rodar.", e Recentes desabilita justamente o projeto atual. A única saída é Abrir Projeto… na mesma pasta ou trocar de projeto e voltar. | Tirar a primeira leitura do ciclo da view: `Task` própria guardada na sessão, que não é cancelada pelo `.task`. Ou, no `loadExecution` com `loadedOnce`, refazer o `inspectProject()` quando `currentProjectID != nil && inspection == nil`, e o doctor quando `doctor == nil`. Teste: cancelar a tarefa durante o inspect e conferir que a volta à aba recupera a análise. | 88 | Verificado (linhas) / Inferido (efeito) |
| FR-02 | P2 | Concorrência / fila do motor | `ExecutionView.swift:186`; `Views/Execution/ExecutionProjectColumn.swift:145`; `EngineSession.swift:1895`, `:1977`; `engine/src/mobaile/rpc/contract.py:197-208` | Todo `project.*` passa por uma fila serial, e o prazo conta o tempo de espera nela: `project.open`, `forget` e `trust` têm 15 s; `inspect` e `configure`, 30 s. O doctor fica nessa fila por até 180 s (só o `pip check` pode levar 60 s). Mesmo assim, `livre` e `ocupado` não consideram `doctorRunning`. Cenário A: o doctor automático da primeira leitura está rodando, e o dono escolhe outro projeto em Recentes ou clica em Esquecer. O `project.open` espera na fila e pode estourar o prazo com "timeout". Se não estourar, o `runDoctor` do projeto novo sai na hora pelo `guard !ex.doctorRunning`, e o resultado do doctor antigo é descartado. O painel fica sem doctor. Cenário B: "Usar" ou "Trocar…" o interpretador durante o doctor. O doctor novo é pulado, e o antigo, feito com o interpretador anterior, é aplicado ao mesmo projeto. O painel mostra um diagnóstico velho. | Guardar a `Task` do doctor e cancelá-la ao trocar de projeto ou de interpretador (o cliente manda `$/cancelRequest` e o motor para entre checagens), e depois rodar o doctor novo. Também dá para incluir `doctorRunning` em `livre`/`ocupado`. No `runDoctor`, trocar o `return` por "marcar pendente e refazer ao terminar". | 85 | Verificado (linhas) / Inferido (efeito) |
| FR-03 | P2 | Estado | `ExecutionView.swift:23`, `:186`; `EngineSession.swift:1895`, `:1916` | Durante `starting`, enquanto o `run.start` está em voo, o `isRunning` ainda é `false`. O `run.start` pode levar segundos: reanálise, fechar a sessão Appium (até 10 s) e subir o scrcpy. Nessa janela, Recentes, Abrir Projeto… e Esquecer ficam habilitados, e `openProject`/`forgetCurrentProject` não olham `starting`. Cenário: Rodar e, em seguida, Esquecer. O `forgetCurrent` zera `inspection` e `currentProjectID`, a resposta chega e cria `activeRun`, e a view cai em `ExecutionEmptyView` (`:23`). O `main` roda sem nenhum botão Parar na tela, e `openProject` recusa (`!isRunning`) até o fim. Com Recentes em vez de Esquecer, o cabeçalho mostra o projeto B enquanto o console e o `activeRun` são do A. | Incluir `ex.starting` em `livre` e nos `guard` de `openProject`/`forgetCurrentProject`. Na view, mostrar a barra Rodar/Parar sempre que `isRunning`, mesmo sem projeto atual. | 85 | Verificado (linhas) / Inferido (efeito) |
| FR-04 | P2 | Estado / queda do motor | `EngineSession.swift:440-452` | A limpeza da queda do motor desfaz stream, proxy, escuta e `runState`, mas não `state.execution.activeRun`, `stopping` nem `starting`. O comentário de `:442-443` diz que deixar isso ligado seria "afirmar … o que não existe". Cenário: o motor cai no meio de uma execução, e o processo do dono morre junto ou fica órfão. Na barra lateral, a Execução continua "rodando", e o subtítulo diz "· rodando" até alguém abrir a aba. Com a aba aberta, Parar fica habilitado com o motor fora e dá `notRunning`. Na volta, o `refreshRunStatus` só apaga o `activeRun`, porque o motor novo tem `last: null`. A execução some sem resultado e sem explicação. | Na limpeza da queda: `if state.execution.isRunning { state.execution.activeRun = nil; state.execution.lastResult = RunFinished(status: "indeterminate", message: "O motor caiu durante a execução; confira a pasta da execução.", folder: activeRun.folder) }` e `stopping = false`. Teste com o motor falso terminando no meio da execução. | 82 | Verificado (linhas) / Inferido (efeito) |
| FR-05 | P2 | Segurança (confiança) | `EngineSession.swift:2074-2075`, `:1990-1994` (`requestTrustForDoctor`); `Models/ExecutionModels.swift:181-185`; `engine/src/mobaile/rpc/server.py:2608-2611`, `:2668-2670` | O diálogo "Confiar neste projeto?" mostra interpretador, entrada e pasta tirados de `ex.inspection`. Essa análise é feita uma vez, ao abrir o projeto ou ao configurar, e nunca é refeita. O motor, ao receber `trusted: true` (ou `project.trust`), reanalisa e grava a impressão do **que vale agora**, não do que o diálogo mostrou. O protocolo promete "confiança presa ao que o diálogo mostrou" (PROTOCOLO_RPC.md, B1-5). Cenário: o projeto foi aberto de manhã. À tarde, um `git pull` muda o `SDK_HOME` da run configuration. O dono clica em Rodar, vê o interpretador antigo no diálogo e confirma, e o motor confia no interpretador novo, que ele nunca viu. | Front: antes de abrir o diálogo, chamar `project.inspect` e montar o pedido com a análise nova. Contrato (motor e front): mandar o que foi mostrado (`expected: {interpreter, entry, working_dir}`) no `run.start` com `trusted` e no `project.trust`. O motor compara e recusa a divergência. Encaminhar ao `security-appsec`. | 80 | Verificado (linhas) / Inferido (efeito) |
| FR-06 | P2 | Layout / estado visível | capturas `pequena-980x600-execucao.png` e `06m-execucao-rodando-claro.png` (barra "Aparelho"); `ExecutionView.swift:282-305` | O seletor de aparelho (`Menu` com `Label`, D-F5) **não aparece** em duas das capturas do próprio dev: na janela de 980×600 (sem execução) e na 06m (rodando, controle desabilitado). Aparece só o texto "Aparelho", seguido de um vão. Na 06l, mais larga e habilitada, ele aparece. A decisão D-F5 dá o problema como resolvido. Durante a execução, esse é o único lugar que diria em qual aparelho o `main` está rodando (`activeRun.deviceId` não é mostrado em nenhum outro). | Conferir no app real, na aparência clara, em 980×600 e com o controle desabilitado. Mostrar `activeRun.deviceId` como texto ao rodar, em vez de depender do `Menu` desabilitado. Incluir na `WindowSnapshotTests` uma checagem de que o rótulo do aparelho foi desenhado. | 80 | Verificado (capturas) / Não verificável (app real) |
| FR-07 | P3 | Concorrência | `EngineSession.swift:2241-2249`, `:2127-2134` | `run.log` e `run.finished` ignoram `run_id`, que vem no payload e no DTO. O motor espera 3 s e depois mata o grupo quando um neto segura o stdout (`project_run.py:445-451`), mas um neto em outra sessão pode sobreviver. Cenário: linhas atrasadas da execução A caem no console da B, recém-limpo. Um `run.finished` atrasado da A zera o `activeRun` da B, e o Rodar volta a ficar habilitado com a B rodando. | Guardar o `runId` esperado (o do `activeRun`, ou "qualquer um" só enquanto `starting`) e descartar o que não bate. | 70 | Verificado (linhas) / Suposição (neto sobrevivente) |
| FR-08 | P3 | Estado | `EngineSession.swift:2091-2097` | Pelo protocolo atual, `run.stop` só responde depois do SIGINT/SIGTERM/SIGKILL (até ~8 s). O `run.finished` pode chegar antes da resposta. Nesse caso, o `else` escreve "Parando a execução…" na barra de status **depois** de "Cancelado". A barra fica com uma mensagem falsa até o próximo aviso. | Só escrever a mensagem se `ex.activeRun != nil` no momento da resposta, ou escrever antes da chamada. | 80 | Verificado (linhas) / Inferido (ordem) |
| FR-09 | P3 | Contrato / falha aberta | `Engine/EngineDTO+Execution.swift:95-98` | `HubState(rawValue:cloud:)` transforma um valor desconhecido de `hub_state` em `.local`. Um motor futuro com um estado novo (por exemplo `"blocked"`) apareceria com o selo verde "Local", e o Rodar não seria bloqueado pelo front. O motor ainda recusa, mas o selo de segurança engana. Não derruba a decodificação, o que está certo. | Valor desconhecido (não nulo) vira `.unknown` ("Não confirmado"). Só `nil` com `cloud == false` vira `.local`. | 85 | Verificado (linha) |
| FR-10 | P3 | Acessibilidade | `ExecutionView.swift:316-322`; ausência de anúncio em `EngineSession.swift:2127-2134` (padrão em `Views/MainWindow/EngineStatusBanner.swift:105`) | `.accessibilityLabel("Tempo decorrido")` sobre o `TimelineView` substitui o texto. O VoiceOver lê "Tempo decorrido" sem o tempo. O fim da execução (Passou/Falhou) também não é anunciado: quem usa leitor de tela e está no console não percebe o banner. O app já anuncia a queda do motor com `AccessibilityNotification.Announcement`. | `.accessibilityLabel("Tempo decorrido").accessibilityValue(texto)`. No `applyRunFinished`, `AccessibilityNotification.Announcement("Execução: \(resumo.title)").post()`. | 85 | Verificado (linhas) / Inferido (VoiceOver) |
| FR-11 | P3 | Regressão de comando | `App/CommandRegistry.swift:344-348`, `:266`; `App/AppState.swift:310-313` | Na Execução, o ⌘F global vira "Buscar na Hierarquia", desabilitado com o motivo `semAparelho` ("Conecte um aparelho"). O motivo está errado quando há aparelho: o que bloqueia é o inspector, suprimido na Execução. O dev-front diz que o ⌘F abre a barra de busca do console, mas não testou (ver Dúvidas). | Na Execução, motivo próprio ("A Execução não tem hierarquia; use ⌘F no console"), ou tirar o ⌘F desse comando para o `NSTextView` receber `performFindPanelAction`. | 80 | Verificado (linhas) |

## O que foi checado e está correto (sem achado)

- **`@MainActor`.** `EngineSession` é `@MainActor` (`EngineSession.swift:38`). Notificações,
  respostas e mutações de `ExecutionState` passam por ela. O `Coordinator` do console é
  `@MainActor`, e o `boundsChanged` adia a escrita no binding com `DispatchQueue.main.async`.
- **`run.finished` antes da resposta do `run.start`.** Coberto: `guard ex.lastResult?.runId
  != inicio.runId` (`:2062`) e o teste `testFimAntesDaRespostaNaoFicaRodando`.
- **`run.log` antes da resposta.** O console é limpo antes da chamada (`startRun`), e a
  linha nova é aceita.
- **Aba fechada e reaberta no meio da execução.** O estado vive em `AppState.execution`, e
  as notificações chegam com a aba fechada. Na volta, `refreshRunStatus` reconcilia
  `activeRun`. Perde só o aviso de vídeo, como o dev já registrou.
- **Confiança e `hub_unknown`.**
  - No máximo dois diálogos, cada um dependendo de clique. Sem laço e sem dupla execução:
    `startRun` tem `guard !starting`, e tudo roda no main actor.
  - O cancelar não repete nada.
  - O `trusted` é preservado na repetição do hub.
- **DTOs × fixtures e protocolo.**
  - Os campos opcionais são decodificados com `decodeIfPresent` e padrão.
  - `hub_reason` e `doctor.trusted`, novos no protocolo, são ignorados sem erro.
  - `status` desconhecido do `run.finished` vira `indeterminate`, e `state` desconhecido
    do doctor vira "pulada".
  - `values` com número literal não derruba a análise.
  - Ficam obrigatórios: `Project.id/root`, `Config.name`, `Suite.name`, `Check.id`,
    `RunStarted.run_id`, `RunStopped.running/stopped`, `RunStatus.running`,
    `Problem.message` e `Candidate.path`. Todos estão presentes nas fixtures e no protocolo.
  - `Config.id` (`name#line#active`) não duplica, porque o motor deduplica por nome
    (`projects.py:1261`, `:1280`).
- **Console.**
  - O diff incremental está correto: o índice local é `aplicadas - dropped`, protegido
    pela checagem de lacuna, e o corte vem depois do acréscimo.
  - O teto de 5.000 funciona, e o observer é removido em `dismantleNSView`.
  - `scroll` é `weak`, e não há ciclo de retenção.
  - O `NSTextView` não é editável e tem rótulo de acessibilidade.
- **Segredos.**
  - Nenhum `print`/`NSLog`/`Logger` novo.
  - O `UserDefaults` só guarda "Gravar vídeo".
  - Os valores exibidos são os permitidos pelo contrato. As chaves sensíveis aparecem só
    pelo nome (`nameOnlyKeys`), e das `envs` só os nomes.
  - O console exibe e copia o texto já mascarado pelo motor.
- **Atalhos e abas.**
  - `execution` é o último caso: ⌘6, com o Ambiente no ⌘5 e as áreas no ⌘0 a ⌘4.
  - O menu Visualizar percorre `allCases`.
  - A paleta tem palavras-chave da área.
  - A Início tem 5, 3 ou 2 colunas.
  - O inspector fica suprimido, com motivo próprio.
  - A busca da toolbar fica fora da Execução.
  - `WorkspacePane` e `DetailColumn` não montam a `ExecutionView` ao mesmo tempo.
- **Reduzir movimento.** `Motion.smooth()` e `snappy()` passam pelo `MotionPolicy.shared`,
  que segue o ajuste do sistema.

## Dúvidas (sem linha citável ou confiança abaixo de 80)

- **⌘F no console.** Com um item de menu ⌘F definido pelo app ("Buscar na Hierarquia",
  desabilitado na Execução), não sei se o `NSTextView` recebe o ⌘F para a barra de busca.
  Conferir no app real.
- **Sheet seguido de outro sheet.** `confirmExecutionDialog` pode montar `.unknownHub` logo
  depois do `dismiss()` do sheet de confiança. No macOS, apresentar um `sheet(item:)` novo
  durante a animação de saída às vezes falha em silêncio. O ida e volta do `run.start`
  provavelmente dá folga suficiente.
- **Rolagem automática pausando sozinha.** Com o TextKit 2, o layout preguiçoso pode mudar
  a altura do documento depois do `scrollToEndOfDocument` (já com `rolandoSozinho = false`).
  Aí o `boundsChanged` leria "não está no fim" e pausaria a rolagem sem a pessoa subir.
  Precisa de rajada real para confirmar.
- **Desempenho do console.** Não medi. `removeFirst` a cada linha depois do teto,
  `tone(of:)` compilando duas regex por linha e um decode JSON por notificação no main
  actor. Isso deve aguentar centenas de linhas por segundo, mas não sei se aguenta
  milhares.
- **Corrida de `run.status` com `run.start`.** `run.status` está na fila `fast`, e
  `run.start` na `services`. Reabrir a aba durante o `starting` pode recolocar em
  `lastResult` o resultado anterior. Isso some quando a execução nova termina. Em tese, a
  ordem inversa poderia apagar o `activeRun` de uma execução viva, mas é improvável.

## Desvio de escopo e requisitos sem implementação

- Contrato do front: todos os itens foram implementados.
- Lacunas de teste que falhariam com os achados acima:
  - nenhum teste cancela a primeira leitura (FR-01);
  - nenhum troca de projeto ou de interpretador com o doctor em andamento (FR-02);
  - nenhum usa Esquecer ou Recentes durante `starting` (FR-03);
  - nenhum derruba o motor no meio da execução (FR-04);
  - nenhum cobre `refreshRunStatus` com execução ativa (reabrir a aba).

## Decisões pendentes do humano

- **FR-05.** Prender a confiança ao que foi mostrado pede mudança de contrato
  (`expected` no `run.start` e no `project.trust`). Adotei a suposição de que a correção
  mínima, refazer o `project.inspect` antes do diálogo, basta para a B1. Se não bastar,
  motor e front precisam mudar juntos.
- **FR-06.** Suponho que o sumiço do seletor seja real, e não só um artefato da captura
  fora da tela. Se for só da captura, o achado vira P3: mostrar o aparelho como texto ao
  rodar.

## Limites da revisão

- Independência parcial: o revisor é o mesmo modelo que escreveu o código. Recomendo que
  uma pessoa leia o diff.
- Revisei por leitura. Não rodei `swift test`, o app nem o motor, e não usei VoiceOver.
- O protocolo e as fixtures do checkout têm mudanças ainda não commitadas do dev do motor
  (`hub_unknown`, `project.trust`, `stopped` no `run.stop`). Conferi contra a versão atual
  do arquivo.

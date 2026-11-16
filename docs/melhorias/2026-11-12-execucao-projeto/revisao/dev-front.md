# B1, parte do front: relatório do dev do front

Rodada orquestrada de 12/11/2026, branch `melhoria/2026-11-12-execucao-projeto`.
Contrato: [CONTRATO.md](../CONTRATO.md). Formato das RPCs:
[docs/PROTOCOLO_RPC.md](../../../PROTOCOLO_RPC.md), seções "Projeto de
automação do dono" e "Rodar o `main`". Commit local, sem push. `VERSION` e
`CHANGELOG` não foram tocados, e o app nativo não foi reempacotado: as duas
coisas ficam com o orquestrador.

## O que entrou

- **Área Execução** (`WorkspaceTab.execution`, último caso do enum, ⌘6).
  - O Ambiente continua no ⌘5. `needsDevice = false`.
  - Fica na seção Workspace da barra lateral, depois do Relatório. Ícone
    `play.rectangle.on.rectangle`, na cor `cat1` (a do Page Objects).
  - Badge: "rodando" durante a execução; depois, o número de cenários que
    falharam no último resultado.
  - Também aparece:
    - nos cartões de área da Início (o layout passou para 5, 3 ou 2 colunas);
    - na paleta, com as palavras-chave da área;
    - no menu Visualizar;
    - no título e no subtítulo da janela ("projeto · rodando/passou/falhou").
  - O inspector fica suprimido na Execução, e a busca da toolbar não vale
    para ela.
- **DTOs** em `Engine/EngineDTO+Execution.swift`, tolerantes a campo ausente:
  - `Project`, `ProjectList`, `ProjectInspection` (entrada, interpretador e
    candidatos, run configuration, configs, suítes e problemas);
  - `ProjectDoctor`, `RunStarted`, `RunStopped`, `RunStatus`, `RunLogLine`,
    `RunFinished` e `RunCounts`.
  - Campos da revisão do motor: `hub_state` na config e no inspect,
    `needs_trust` nas checagens e `ProjectTrusted`.
- **`EngineSession`**, seção "Execução":
  - `loadExecution`, `openProject`, `forgetCurrentProject`, `inspectProject`,
    `configureInterpreter` e `runDoctor`. O doctor usa um token de
    `$/progress` próprio.
  - `requestTrustForDoctor`, `trustProject` e `confirmExecutionDialog`.
  - `startRun`, `stopRun` e `refreshRunStatus`.
  - Notificações `run.log` e `run.finished`, tratadas ao lado de `flow.log`.
- **Estado** em `Models/ExecutionModels.swift`:
  - `ExecutionState`, guardado em `AppState.execution`;
  - `ExecutionConsole`, com teto de 5.000 linhas;
  - `ExecutionResultSummary`, `ExecutionRules` (motivos de bloqueio do
    Rodar) e `ExecutionCopy`.
- **Telas** em `Views/Execution/`:
  - `ExecutionView`: a raiz, mais o estado vazio, o cabeçalho, a barra Rodar,
    o banner de resultado e o sheet de confirmação.
  - `ExecutionProjectColumn`: a coluna Projeto.
  - `ExecutionDoctorPanel` e `ExecutionConsoleView`.

## Decisões

- **D-F1 Estado fora do `AppState`, mas pendurado nele.**
  - `ExecutionState` é `@Observable` próprio, em `AppState.execution`. Assim
    o `AppState` não cresce mais 20 campos.
  - A sessão continua sendo o único ponto que fala com o motor.
- **D-F2 Projeto atual = o mais recente do `project.list`.**
  - A escolha não vai para `UserDefaults`.
  - Na primeira leitura da aba, o mais recente é aberto, e vêm o inspect e o
    doctor.
  - Escolher um recente chama `project.open` de novo, para validar a pasta e
    atualizar `opened_at`.
  - Depois de "Esquecer", a aba volta ao estado vazio, com a lista dos
    abertos antes.
- **D-F3 Console em `NSTextView`, e não em `LazyVStack`.**
  - O motivo são as rajadas de `run.log`. Numa lista do SwiftUI, cada linha
    nova refaz a diferença de até 5.000 itens.
  - O texto do AppKit só acrescenta no fim e corta no começo. O TextKit 2 faz
    o layout só do que está à vista.
  - De graça, vêm a seleção de várias linhas, ⌘C, ⌘F (barra de busca) e o
    leitor de tela.
  - O buffer é uma classe (`ExecutionConsole`), observada por um contador
    (`consoleRevision`). Com um valor, a view do SwiftUI segurava uma cópia,
    e cada linha nova copiaria o array inteiro.
  - A rolagem automática pausa quando a pessoa sobe e volta com "Ir para o
    Fim" ou rolando até o fim.
- **D-F4 Layout.**
  - Projeto fica ao lado de Doctor/Console com `AdaptivePair`. Abaixo de
    720 pt, os dois viram abas.
  - Doctor e Console dividem a altura com `VerticalSplit`.
  - Não há `.inspector`, `HSplitView` nem `VSplitView`.
  - Os textos longos têm `lineLimit` e truncamento no meio, e o que pode
    ceder tem `layoutPriority(-1)`.
- **D-F5 Seletor de aparelho é `Menu` com rótulo `Label`.**
  - O `Picker` e um `Menu` só com `Text` não eram desenhados na aparência
    clara das capturas (no escuro, sim). Com `Label` e ícone, aparecem nas
    duas.
  - "Automático" deixa o motor decidir e mostra o `udid` da config ativa.
- **D-F6 Confirmações num sheet só.** Um `ExecutionConfirmation` cobre os
  diálogos abaixo, e o pedido vai como parâmetro para a sessão, porque o
  sheet zera o estado ao fechar.
  - `trust(then: .run)`: o erro `project_not_trusted` repete o pedido com
    `trusted: true`.
  - `trust(then: .verify)`: o botão "Confiar no Projeto e Verificar…" do
    doctor chama `project.trust` e refaz o doctor.
  - `unknownHub`: o erro `hub_unknown` repete o pedido com
    `allow_unknown_hub: true`.
- **D-F7 O Rodar fica bloqueado com explicação.** Os motivos:
  - motor fora do ar;
  - sem entrada;
  - interpretador ausente ou inexistente;
  - sem `init` ativo;
  - config ativa na nuvem (`hub_state`/`cloud`).

  O hub "Não confirmado" não bloqueia: quem pergunta é o motor. `invalid_input`
  e `device_busy` aparecem em linha, com a mensagem do motor (por exemplo, o
  aparelho escolhido diferente do `udid` da config).
- **D-F8 `run.log` aceito antes da resposta do `run.start`.** As primeiras
  linhas podem chegar antes dela. Um `run.finished` que chega antes da
  resposta não deixa a aba presa em "rodando".
- **D-F9 Interpretador escolhido com `NSOpenPanel` sem resolver link.** O
  painel usa `resolvesAliases = false` e mostra arquivos ocultos. Sem isso,
  `.venv/bin/python` viraria o Python do sistema.
- **D-F10 Testes da Início e do Relatório ajustados à área nova.** Nenhum
  foi afrouxado.
  - `workspaceAreas` passou a incluir `.execution`.
  - A comparação com `setup.check` exclui a Execução, que não tem linha
    nesse método.
  - O "todas as outras áreas precisam de aparelho" exclui a Execução.

## Testes

| | Antes (6b31528) | Depois |
|---|---|---|
| `make test-swift` | 491 testes, 29 pulados, 0 falhas | 523 testes, 29 pulados, 0 falhas |
| `make check` | — | verde: motor 1076 passed + 963 subtests, Tk 20, gate de QA 11, QA 5 fluxos ok, fixtures em dia (com o trabalho do motor, ainda não commitado, no checkout) |

`ExecutionTests` tem 32 testes novos. Eles cobrem:

- a decodificação de cada fixture: `project.open`, `list`, `inspect`,
  `inspect_sem_interpretador`, `configure`, `doctor`, `forget`, `run.start`,
  `stop`, `status`, `notif_run.log`, `notif_run.finished` e
  `erro_project_not_trusted`;
- as fixtures da revisão: `project.trust`, `project.doctor_confiavel` e
  `erro_hub_unknown`. O teste é pulado enquanto elas não existirem;
- a tolerância a campo ausente;
- o console: o teto de 5.000, o aviso de descarte, a limpeza e a quebra de
  linha;
- o `NSTextView`, que acrescenta e corta sem reconstruir;
- o banner (status, contagens, duração), o badge e os motivos de bloqueio;
- o fluxo de confiança: erro, diálogo e repetição com `trusted`;
- o `hub_unknown` repetido com `allow_unknown_hub`;
- `device_busy` e `invalid_input` em linha;
- `run.finished` antes da resposta do `run.start`;
- o doctor com token próprio;
- "confiar e verificar", que chama `project.trust` e refaz o doctor;
- `configure`, Esquecer e Parar;
- os atalhos: só a Execução no ⌘6 e só o Ambiente no ⌘5;
- o inspector suprimido e o subtítulo da janela.

O teste de tamanho mínimo da janela já percorre todas as áreas. Com o
conteúdo da Execução (helper `preencherExecucao`), mediu:

- `execution`: 353 × 446;
- `execution+conteudo`: 749 × 379.

O teto é de 1.100 × 600. Em `WindowSnapshotTests`, a Execução entrou:

- no tamanho pequeno (980×600 e 1280×720, vazia e com conteúdo);
- no catálogo, nas cenas `06k` a `06n`.

## O que foi verificado de fato

As capturas foram geradas com `WindowSnapshotTests` numa pasta temporária,
fora do repositório.

- **Estado vazio:** frase, "Abrir Projeto…" e ⌘6 na barra lateral.
- **Projeto sem interpretador:**
  - banner "Falhou" com contagens, aviso de vídeo, "Abrir Pasta da Execução"
    e "Abrir Vídeo" desabilitado;
  - Rodar bloqueado, com o cadeado e o motivo;
  - candidato `/usr/local/bin/python3 · Python 3.14.0 · behave 1.2.6` com
    "Usar";
  - config ativa destacada, com os selos "Ativa" e "Local" e as chaves
    sensíveis só pelo nome;
  - as comentadas recolhidas, com "Nuvem (bloqueada)" nas da Kobiton;
  - doctor com ícones e dicas;
  - console escuro, com o resumo do behave colorido.
- **Rodando:** Parar no lugar do Rodar, tempo decorrido e "rodando" na barra
  lateral.
- **Sheet "Confiar neste projeto?":** interpretador, entrada e pasta.
- **Janela 980×600:** coube sem corte.

## O que NÃO foi verificado

- O app instalado não foi aberto, e nada rodou contra o motor real ou o
  aparelho: só o motor falso com as fixtures.
- Não houve teste de desempenho do console com rajadas reais de milhares de
  linhas por segundo. A escolha do `NSTextView` vem do raciocínio, não de
  medição.
- Não testei o `NSOpenPanel` (pasta e interpretador) nem o `NSWorkspace`
  (Abrir Pasta, Abrir Vídeo).
- As fixtures da revisão do motor (`hub_state`, `needs_trust`,
  `project.trust`, `hub_unknown`) estavam sendo regeneradas pelo dev do motor
  durante este trabalho, e não são deste commit.
  - Os testes que dependem delas pulam enquanto elas não existem.
  - Os nomes usados foram os do recado do orquestrador e os das fixtures
    presentes no checkout.

## Falhas ou faltas do motor encontradas

- Nenhuma que bloqueie.
- O formato de `run.status.run.video` é só o modo (`scrcpy`…), sem o aviso.
  Depois de reabrir a aba durante uma execução, o aviso de vídeo não volta.
  Isso é cosmético.

## Riscos

- O console corta linhas do começo enquanto a pessoa lê lá em cima, com a
  rolagem pausada. O texto visível "sobe" quando o teto é atingido.
- A primeira leitura abre o projeto mais recente e roda o doctor, que pode
  levar até um minuto (`pip check`). Ele tem token e progresso próprios e não
  bloqueia a aba, mas consome processo.
- Execução que o motor perde num reinício só é desfeita ao reabrir a aba
  (`run.status` na volta do motor).

## Correções da revisão (revisor-codigo-front.md)

Commit "fix(ui): correcoes da revisao da area Execucao". Os testes agora usam
as fixtures finais do motor (B1-5: `project.trust`,
`project.doctor_sem_confianca`, `project.doctor_confiavel`,
`erro_hub_unknown`), sem `XCTSkip`.

| Achado | Correção | Teste |
|---|---|---|
| FR-01 | `loadExecution` não para no `loadedOnce`: na volta à aba, refaz o inspect quando há projeto sem análise e o doctor quando falta. A coluna Projeto sem análise e sem operação mostra "Ler o Projeto" | `testPrimeiraLeituraCanceladaRecuperaNaVolta` |
| FR-02 | Escolhi cancelar, e não bloquear: o doctor roda numa `Task` guardada na sessão; abrir, esquecer, configurar e confiar cancelam o doctor (o cliente manda `$/cancelRequest`, o motor para entre checagens), esperam ele soltar e rodam o doctor de novo com o estado novo. Resultado de doctor cancelado é descartado | `testTrocarDeProjetoDuranteODoctorRefazODoctor`, `testTrocarInterpretadorDuranteODoctorRefazODoctor` |
| FR-03 | `projectLockReason` (rodando, iniciando, lendo, confiando) desabilita Recentes/Abrir/Esquecer com a explicação no tooltip; os `guard` da sessão também olham `starting`; a tela não cai no estado vazio com execução ativa | `testProjetoTravadoDuranteORunStart` |
| FR-04 | Queda do motor: zera `activeRun`/`starting`/`stopping`/doctor e registra o fim como Indeterminado, "O motor encerrou durante a execução…", com a pasta | `EngineSessionSupervisionTests.testQuedaDoMotorEncerraAExecucaoDoProjetoComoIndeterminada` |
| FR-05 | `project.inspect` imediatamente antes do diálogo de confiança (Rodar e doctor); o diálogo usa esse resultado | `testDialogoDeConfiancaReleOProjetoAntes` |
| FR-06 | Rodando, a barra mostra "Rodando em <aparelho>" (texto, não o menu desabilitado). O menu passou a `Label` com ícone e aparece em 980×600 e nos dois temas (conferido nas capturas) | `testBarraRodarSempreDizOAparelho` (árvore de acessibilidade, parado e rodando) |
| FR-07 | `run.log`/`run.finished` filtrados pelo `run_id` da execução; durante o `run.start`, adota o primeiro `run_id` que chega (D-F8 continua coberto) | `testNotificacoesDeOutraExecucaoSaoIgnoradas`, `testDuranteORunStartAdotaOPrimeiroRunId`, `testFimAntesDaRespostaNaoFicaRodando` |
| FR-08 | "Parando a execução…" sai antes da chamada; a resposta não sobrescreve o fim | `testParadaNaoSobrescreveOFim` |
| FR-09 | `hub_state` desconhecido vira "Não confirmado"; só ausente (motor anterior) e não `cloud` vira Local | `testHubStateDesconhecidoNaoViraLocal` |
| FR-10 | Tempo decorrido com rótulo e valor; fim da execução anunciado (`AccessibilityNotification.Announcement`) | `testBarraRodarSempreDizOAparelho` (valor do tempo) |
| FR-11 | Na Execução, ⌘F é "Buscar no Console" e abre a barra de busca do `NSTextView` (`performTextFinderAction`) | `testBuscaNaExecucaoVaiParaOConsole` |

Também: `run.status` com execução ativa (reabrir a aba) ganhou teste
(`testRunStatusComExecucaoAtiva`), e a faixa "Confiar no Projeto e
Verificar…" do doctor passou a texto em cima e botão embaixo (lado a lado, a
frase ficava espremida em quatro linhas na coluna estreita).

Números depois das correções: `make test-swift` 536 testes, 29 pulados, 0
falhas; `make check` verde (motor 1080 passed + 963 subtests, Tk 20, gate de
QA 11, QA 5 fluxos ok, fixtures em dia). Capturas regeneradas na pasta
temporária do scratchpad (cenas 06k–06n e `pequena-*-execucao*`).

Continua não verificado: o ⌘F do console e o anúncio do VoiceOver no app real;
o diálogo `unknownHub` logo depois do de confiança (dois sheets seguidos);
rajada real de linhas no console. O FR-05 completo (mandar ao motor o que o
diálogo mostrou) pede mudança de contrato e ficou fora.

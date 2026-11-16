# B1, parte do motor: relatório do dev do motor

Rodada orquestrada de 12/11/2026, branch `melhoria/2026-11-12-execucao-projeto`.
Contrato: [CONTRATO.md](../CONTRATO.md). O formato final de cada RPC está em
[docs/PROTOCOLO_RPC.md](../../../PROTOCOLO_RPC.md), nas seções "Projeto de
automação do dono (aba Execução)" e "Rodar o `main` (`run.*`)". Este relatório
resume esse formato. Se os dois divergirem, vale o PROTOCOLO_RPC.md.

Os três commits ficaram locais, sem push. `VERSION` e `CHANGELOG` não foram
tocados, e o app nativo não foi reempacotado: as duas coisas ficam com o
orquestrador.

## Commits

| Commit | Título |
|---|---|
| `3883906` | feat(motor): projetos do dono e analise estatica do main (B1-1) |
| `2ce543b` | feat(motor): doctor do projeto do dono com progresso (B1-2) |
| último (este arquivo vai nele) | feat(motor): execucao do main do dono com video e trava do aparelho (B1-3) |

## RPCs entregues (resumo para o front)

Os métodos novos ficam nas filas `project` (fila nova) e `services`, e
`run.status` fica na `fast`.

| Método | Fila / prazo | Parâmetros | Resultado |
|---|---|---|---|
| `project.open` | project / 15 s | `path` | `{project}` = `{id, root, name, entry, trusted, opened_at}` |
| `project.list` | project / 15 s | — | `{projects: [project…]}`, o mais recente primeiro |
| `project.forget` | project / 15 s | `project_id` | `{removed}` |
| `project.inspect` | project / 30 s | `project_id` | `{project, entry{file,function,found}, interpreter{path,source,exists}, working_dir, run_configuration{name,file,env_names}\|null, active_config, configs[{name,active,found,file,line,platform,values,hub,cloud,keys}], suites[{name,defined,line,runs[{squad,feature,line,found,path,title,scenarios}]}], unused_suites, problems[{file,line,message}]}` |
| `project.doctor` | project / 180 s, progresso | `project_id`, `device_id?`, `progress_token?` | `{project_id, checks[{id,label,state,message,hint}], summary{ok,warn,fail,skip}, ready}`; ids nesta ordem: `interpreter, packages, requirements, pip_check, appium, appium_port, device, app, uiautomation, cloud, features` |
| `run.start` | services / 30 s | `project_id`, `device_id?`, `record_video?`(true), `trusted?` | `{run_id, project_id, folder, device_id, platform, config, command{interpreter,entry,working_dir}, video{mode,warning}, started_at}`; `mode` ∈ `scrcpy`, `screenrecord`, `simctl`, `null` |
| `run.stop` | services / 60 s | — | `{running, stopped, run_id}` |
| `run.status` | fast / 15 s | — | `{running, run{run_id,project_id,project_name,device_id,platform,folder,started_at,elapsed_s,lines,video,stopping}\|null, last}` (`last` = último `run.finished`) |

Notificações:

- `run.log {run_id, line}`: linha já mascarada, sem ANSI, até 4.000 caracteres.
- `run.finished {run_id, status, counts, exit_code, folder, video, video_warning, message, duration_s}`.
  - `status` ∈ `passed`, `failed`, `indeterminate`, `cancelled`.
  - `counts` é `null` ou `{features, scenarios, steps, summaries}`. Cada tipo traz
    `passed, failed, skipped, undefined, errors, untested`.

Códigos de erro novos (`data.code`):

- `project_not_trusted`: o front abre "Confiar neste projeto?" e repete o
  pedido com `trusted: true`.
- `device_busy`: já há uma execução ou um flow rodando. A mensagem cita o
  projeto.

A config ativa na nuvem, a falta de `init` ativo, de entrada ou de
interpretador e os parâmetros inválidos voltam como `invalid_input`, com a
mensagem explicando o motivo.

O que a trava do aparelho recusa com `device_busy` enquanto `run.*` roda:

- no mesmo aparelho: `hierarchy.dump`, `passive.start`, `codegen.record`,
  `input.tap`, `input.text` e `recording.start`;
- em qualquer aparelho: `flow.run` e `flow.maestro_run`.

O espelho continua funcionando durante a execução.

Fixtures novas em `engine_payloads.json` (todas geradas pelo motor):

- métodos: `project.open`, `project.list`, `project.inspect`,
  `project.doctor`, `project.forget`, `run.status`, `run.stop` e `run.start`;
- erro: `erro_project_not_trusted`;
- notificações: `notif_run.log` e `notif_run.finished`.

## Números do portão

| | Antes (60200b9) | Depois (B1-3) |
|---|---|---|
| lint (ruff) / bandit | ok / ok | ok / ok |
| testes do motor | 919 passed, 934 subtests | 1009 passed, 958 subtests |
| UI Tk | 20 passed | 20 passed |
| gate de QA | 11 passed | 11 passed |
| QA (5 fluxos) | 147 verificações ok | 147 verificações ok |
| fixtures-check | em dia | em dia |
| `make test-swift` | — | 491 testes, 29 pulados, 0 falhas |

## O que foi verificado de fato

- **Critério 1:** o projeto de exemplo é lido com a config ativa, as três
  alternativas comentadas, as 3 suítes (time_01, time_02, time_03) e as
  features e cenários certos. `test_suite_canais`, que é definida mas não
  chamada, aparece em `unused_suites`. Testes em `tests/unit/test_projects.py`.
- **Critério 2:** o hash da pasta do exemplo não muda depois de `open`,
  `inspect`, `analyze`, `trust` e `forget`. Ele também não muda depois de rodar
  o behave de verdade numa cópia, porque nenhum `.pyc` vai para o projeto.
- **Critério 3:** com a config Kobiton ativa, `run.start` recusa e o doctor
  falha em `cloud`, sem abrir porta nem tocar no aparelho. `FAKE-KEY-0000`,
  `FAKE-SENHA-1234`, `FAKE-TOKEN-9999` e `usuario-falso` não aparecem no
  stdout do RPC, no `console.log`, no `resumo.json`, no `projetos.json` nem no
  `engine.log`. Isso inclui o caso em que o próprio projeto imprime a config
  inteira (`EXEMPLO_IMPRIMIR_CONFIG=1`).
- **Critério 4:** com o behave 1.2.6 real (`/usr/local/bin/python3`, sem
  aparelho):
  - o console chega ao vivo por `run.log`;
  - o caso padrão termina `passed`, com 5 cenários e 3 resumos somados;
  - `EXEMPLO_CENARIO_FALHA=1` termina `failed` com saída 0, o que prova que o
    código de saída não decide;
  - `EXEMPLO_FALHAR_INIT=1` termina `indeterminate`, com a linha do
    `RuntimeError` em `message`.

  Teste em `tests/contract/test_run_rpc.py::TestRunComBehaveReal`. Ele é
  pulado quando nenhum Python da máquina tem o behave.
- **Critério 5:** `run.stop` encerra o processo e o neto (`sleep 60` lançado
  pelo script). O neto que segura o pipe depois que o principal sai é
  encerrado sem travar o fim. Testes em `tests/unit/test_project_run.py` e
  `test_run_rpc.py`.
- **Critério 6:** durante a execução, os métodos da trava respondem
  `device_busy` citando o projeto. Outro aparelho continua livre, e a trava é
  solta no fim.
- **Doctor:** cada checagem foi coberta com fakes (Python do projeto, adb,
  Appium, porta). Os helpers novos do adb validam o nome da propriedade e do
  pacote antes de mandar o comando ao shell do aparelho.
- **Flags de vídeo:** conferi no `scrcpy --help` 5.0.1 instalado que
  `--no-playback`, `--no-window`, `--no-audio` e `--record=` existem. No
  `xcrun simctl io help`, conferi `--codec h264`.

## O que NÃO foi verificado

- **Critério 7 (vídeo no emulador).** O `adb devices` só mostrou o moto g55
  físico (`SERIAL0002`), e o `emulator-5554` não estava ligado. Pela regra da
  rodada, não toquei no aparelho físico nem iniciei emulador. A escolha do
  gravador e o comando do scrcpy têm teste unitário. A gravação real de um
  `video.mp4` tocável fica para o aceite com o emulador ligado:
  `run.start {project_id, device_id: "emulator-5554"}`.
- O fallback `adb screenrecord` e o `simctl recordVideo` reaproveitam o
  `ScreenRecorder` existente, que já é testado. Não houve gravação real nesta
  rodada.
- O formato real das run configurations do dono (nomes de atributos,
  `SDK_HOME` com macros diferentes de `$PROJECT_DIR$` e `$USER_HOME$`) ficou
  inferido do estudo e do PyCharm.
- **Critério 8:** o `make update-native` e o `verify-native` ficam com o
  orquestrador.

## Decisões

- **D-1 Fila nova `project`** para `project.*`. O doctor leva até um minuto
  (`pip check`) e não pode esperar atrás de um `wda.start` nem segurar
  consultas da fila `query`. O `run.start` e o `run.stop` ficam em `services`
  com `flow.*`: dividir a fila é o que impede um flow e uma execução de
  começarem juntos.
- **D-2 `executar` chama o behave no mesmo processo**
  (`behave.__main__.main([...])`) no projeto de exemplo, como o estudo supõe
  (H2). A suposição está documentada em `core/runner.py`. Também conferi que o
  behave 1.2.6 aceita várias chamadas no mesmo processo.
- **D-3 Resultado.** O resultado soma os resumos de todas as chamadas do
  behave:
  - `failed` quando qualquer `failed`, `error` ou `undefined` passa de zero;
  - `passed` quando há cenário passado;
  - `indeterminate` nos outros casos.

  Se houver menos resumos que chamadas `executar` encontradas na análise,
  `passed` vira `indeterminate`: é o caso de uma suíte que não rodou porque a
  exceção foi engolida pelo `print(e)`.
- **D-4 Máscara.** Os valores literais de chaves sensíveis são mascarados:
  - os da lista da redação do proxy;
  - os de chaves cujo nome contém `key`, `token`, `secret`, `senha`,
    `password`, `user`, `credential`, `auth`, `cpf` ou `pin`;
  - o usuário e a senha de URLs.

  Os valores das `envs` da run configuration são mascarados quando têm 6 ou
  mais caracteres, ou 3 ou mais se o nome da variável for sensível. Isso evita
  que `1` ou `true` estraguem o console.
- **D-5 Ambiente do filho.**
  - Parte do ambiente do motor, sem o `PYTHONPATH` e o `PYTHONHOME` do motor,
    e soma as `envs` da run configuration.
  - Põe a raiz do projeto na frente do `PYTHONPATH`, como o "Add content
    roots" do PyCharm, e define `PYTHONUNBUFFERED=1`.
  - Sem `PYTHONPYCACHEPREFIX`, define `PYTHONDONTWRITEBYTECODE=1`, para nada
    cair na pasta do projeto.
- **D-6 `device_id` padrão do `run.start`:** o informado, senão o `udid`
  literal da config ativa, senão o aparelho da sessão. O doctor avisa quando o
  aparelho escolhido difere do `udid` da config, porque o teste usa o da
  config.
- **D-7 Trava por aparelho.** Inspeção em outro aparelho continua livre. Flow
  é recusado em qualquer aparelho, porque divide a trava de execução. O
  `codegen.record` não toca o aparelho, mas entrou na trava por pedido do
  contrato.
- **D-8 Hub dinâmico não marca nuvem.** `cloud` só é `true` com host provado
  fora de loopback, ou com `kobiton` no nome da config ou no host. Uma URL
  montada em tempo de execução aparece como `"dinâmico"` e não bloqueia. Isso
  é um risco, listado abaixo.
- **D-9 Doctor sem executar o projeto.** O Python do projeto roda com `-E` e
  `cwd` numa pasta temporária vazia, para um `json.py` do dono nunca ser
  importado. O `-I` foi descartado porque esconderia pacotes instalados com
  `--user`.
- **D-10 Erros novos:** `project_not_trusted`, que o contrato pedia, e
  `device_busy`, para o front distinguir "ocupado" de entrada inválida. A
  nuvem continua como `invalid_input`, com mensagem explícita.
- **D-11 Neto segurando o stdout.** Se o processo principal sai e um neto
  continua com o pipe aberto por mais de 3 s, o grupo é encerrado. Sem isso,
  o `run.finished` nunca chegaria.
- **D-12 `.idea/runConfigurations/main.xml` do exemplo** entrou com
  `git add -f`, porque `.idea/` está no `.gitignore`. O gerador de fixtures
  copia o exemplo e depende desse arquivo.

## Riscos

- **Execução de código do dono.** O nível de confiança é o mesmo do PyCharm,
  com o diálogo de confiança. O que o código do dono faz por conta própria,
  como rede, Kobiton chamada por fora ou arquivos, não é controlado.
- **Hub dinâmico (D-8).** Uma config de nuvem com a URL montada por
  `os.environ` passa como local. O doctor só avisa que não conseguiu conferir
  a porta.
- **Vídeo não provado em aparelho real** nesta rodada (critério 7).
- **Muitas linhas por segundo** viram muitas notificações `run.log`. O front
  precisa do teto de 5.000 linhas que o contrato já prevê.
- **behave 1.3.** O parser aceita `error` e `untested`, mas só o 1.2.6 foi
  rodado de verdade.
- **Interpretador em `$PROJECT_DIR$/.venv`** inexistente (o caso do exemplo):
  o doctor falha em `interpreter` e o `run.start` recusa com `invalid_input`.
  É o comportamento esperado, mas o front deve levar o dono ao doctor.

## Swift

O `make test-swift` passou com as fixtures novas: 491 testes executados, 29
pulados (os de snapshot de janela, que já eram pulados antes) e 0 falhas. Os
DTOs de `project.*` e `run.*` ainda não existem no front, então as fixtures
novas só passam a ser decodificadas quando o dev do front criar
`EngineDTO+Execution.swift`.

## B1-4: interpretador que o PyCharm guarda só pelo nome, e escolha manual

Este item foi pedido pelo orquestrador depois do primeiro relatório. O caso
comum é este: o `.idea/misc.xml` traz só o **nome** do SDK
(`project-jdk-name`), e o venv fica fora da pasta do projeto. Sem resolver
esse nome, o dono ficava travado.

### O que mudou no contrato

**`interpreter` em `project.inspect`** passa a ser
`{path, source, exists, candidates}`. A detecção vale nesta ordem:

| `source` | De onde vem |
|---|---|
| `manual` | override do dono, gravado por `project.configure` |
| `run_configuration` | `SDK_HOME` da run configuration |
| `pycharm_sdk` | nome do SDK (`SDK_NAME` da run configuration ou `project-jdk-name` do `misc.xml`), resolvido pelo `options/jdk.table.xml` do PyCharm |
| `venv` | `.venv/` ou `venv/` na pasta do projeto |
| `null` | nada achado |

- O `jdk.table.xml` é procurado em
  `~/Library/Application Support/JetBrains/PyCharm*/` (Professional e CE),
  da versão mais nova para a mais velha.
- A base desse diretório pode ser injetada (`ProjectService(pycharm_options=…)`).
- O arquivo é lido só para leitura, com o `security/xml_safe`.
- Nome de SDK que não está na tabela vira item de `problems`.

**`interpreter.candidates`** vem vazio quando há interpretador. Quando não há
nenhum, lista os Pythons da máquina que existem:

- `/opt/homebrew/bin/python3`, `/usr/local/bin/python3` e `/usr/bin/python3`;
- os shims `~/.pyenv/shims/python3` e `~/.asdf/shims/python3`.

Regras dos candidatos:

- O mesmo binário (pelo `realpath`) não se repete.
- Cada item é `{path, version, behave}`, com `behave` = versão instalada ou
  `null`.
- A sondagem roda `-E -c` com `importlib.metadata` numa pasta vazia: nenhum
  código do projeto é executado.
- Limite de 4 s por candidato, em paralelo, com cache de 2 minutos.
- Só o `project.inspect` (e o `project.configure`) sondam. O `run.start` não.

**`project.open` e `project.list`** ganham, em cada projeto,
`interpreter_override` e `entry_override` (texto ou `null`). São campos
aditivos.

**Método novo `project.configure`.** Fica na fila `project`, com prazo de
30 s.

- Parâmetros: `project_id`, `interpreter?` (texto ou `null`) e `entry?`
  (texto ou `null`).
- Devolve o mesmo que `project.inspect`, já com a escolha aplicada.
- `null` remove o override. Parâmetro ausente fica como estava.
- `interpreter` precisa ser um caminho absoluto, sem `..`, de um arquivo
  executável que existe (`validate_input_file` do `security`). O caminho é
  guardado **como veio, sem resolver o link**, para `.venv/bin/python` não
  virar o Python do sistema e perder o venv.
- `entry` precisa ser um `.py` relativo, dentro da raiz, sem link simbólico e
  legível pelas regras de `read_project_text`.
- Qualquer outro valor responde `invalid_input`, e nada muda no registro.

### Outras mudanças

- **XML malicioso.** Um XML com DOCTYPE ou entidade no projeto (`misc.xml`,
  run configuration) ou no `jdk.table.xml` é ignorado. Antes, ele derrubava
  o `inspect` com `invalid_input`; agora a análise segue sem aquele arquivo.
- **Dica do doctor.** A dica de `interpreter` agora aponta para a escolha
  manual na aba Execução.
- **Fixtures novas:** `project.inspect_sem_interpretador` (com `candidates`)
  e `project.configure` (com `source: "manual"`). Os campos de override também
  aparecem em `project.open`, `project.list` e `project.inspect`.

### Verificação da B1-4

Testes novos em `tests/unit/test_projects.py` (classes
`TestInterpretadorDoPyCharm`, `TestConfigurar` e `TestCandidatos`) e em
`tests/contract/test_project_rpc.py`. Eles cobrem:

- `misc.xml` resolvido pelo `jdk.table.xml` mais novo, com
  `$USER_HOME$` expandido;
- a run configuration ganhando do `misc.xml`;
- `SDK_NAME` na run configuration;
- nome de SDK ausente da tabela virando problema, com queda para o venv;
- XML malicioso ignorado;
- o override ganhando de tudo, e `null` removendo;
- override de entrada;
- recusa de cada entrada inválida;
- a sondagem real com o Python da suíte, a deduplicação de link, o cache e o
  descarte de Python quebrado.

Não houve conferência num `jdk.table.xml` real desta máquina: os testes usam
uma base injetada.

## B1-5: correções da revisão independente

Fontes: [revisor-codigo-motor.md](revisor-codigo-motor.md) (CR-01..11) e
[auditor-seguranca-motor.md](auditor-seguranca-motor.md) (SEC-B1-01..10). As
provas dos dois relatórios viraram testes de regressão:

- `tests/unit/test_revisao_b1.py`: 47 testes;
- `tests/contract/test_run_rpc.py`: classe `TestRevisaoRpc` e o caso de
  `after_all` com o behave real.

### Decisões do orquestrador

**D-O1. O doctor só roda o Python do projeto depois da confiança**
(CR-02, SEC-B1-01).

- Sem confiança, as checagens `interpreter` (quando o arquivo existe),
  `packages`, `requirements` e `pip_check` voltam `skip`, com
  `needs_trust: true` e a dica de confiar. Com o interpretador ausente,
  `interpreter` falha como antes, e as outras três vêm `skip` com
  `needs_trust: true`.
- Fixtures:
  - `project.doctor`: sem confiança e sem interpretador;
  - `project.doctor_sem_confianca`: com interpretador, sem confiança;
  - `project.trust`;
  - `project.doctor_confiavel`;
  - `erro_hub_unknown`.
- O resultado do doctor ganha `trusted`, e cada checagem ganha `needs_trust`.
- RPC nova `project.trust {project_id}`, que devolve `{project}`.
  `run.start {trusted: true}` continua valendo.
- O doctor também deixou de repassar as `envs` da run configuration ao Python
  do projeto (CR-02).

**D-O2. Confiança presa a uma impressão** (SEC-B1-07). A impressão guarda:

- a pasta real;
- o interpretador;
- a entrada;
- a pasta de trabalho;
- os nomes das `envs`.

Qualquer mudança zera `trusted` na próxima análise, com um item em `problems`
dizendo o que mudou. Isso vale para `project.configure` e para um `git pull`
que mexa em `.idea`. A impressão fica no registro (`trusted_with`) e nunca sai
no RPC.

**D-O3. Nuvem falha fechada** (SEC-B1-02, CR-05, CR-08).

- **Por config, `hub_state`:**
  - `cloud`: qualquer URL literal fora do loopback, em qualquer chave, ou
    `kobiton` no nome ou num host;
  - `unknown`: config não encontrada, ou chave de hub com valor montado em
    tempo de execução;
  - `local`: o resto.
- **Para a execução inteira, `hub_state` e `hub_reason`** no `inspect`:
  - `cloud` se qualquer `init` ativo possível for nuvem;
  - `unknown` com mais de um `init` ativo, `init` dentro de if/try/laço,
    `init(variável)` ou config `unknown`;
  - `local` no resto.
- Agora todos os `init` não comentados entram em `configs` com
  `active: true`. Um apelido local (`cfg = config_x; init(cfg)`) é resolvido
  para a config, e a execução fica pelo menos `unknown`.
- O hub mostrado é o da chave de hub. Uma URL de outra chave, como o proxy do
  chromedriver, não toma o lugar dele (CR-08).
- `cloud: bool` continua, igual a `hub_state == "cloud"`.
- **`run.start`:** `cloud` recusa sempre, com `invalid_input`. `unknown`
  recusa com o erro novo `hub_unknown`, a menos que venha
  `allow_unknown_hub: true`.
- **Doctor, checagem `cloud`:** `fail` para nuvem, `warn` para `unknown`.

**D-O4. Resultado** (CR-01).

- `failed`:
  - uma linha `HOOK-ERROR in …` ou `CLEANUP-ERROR in …`;
  - `errored`, `error` ou `errors` no resumo.
- `indeterminate`:
  - qualquer palavra desconhecida numa linha de resumo, mesmo com 0;
  - `ABORTED:` sem `run.stop`.
- A mensagem do `failed` cita a linha `HOOK-ERROR`.
- O resumo agora é lido da linha crua, e a máscara vale só para a saída. Isso
  resolve a dúvida do revisor sobre um segredo numérico.
- O exemplo ganhou `EXEMPLO_FALHAR_AFTER_ALL=1`. Com o behave 1.2.6 real, ele
  termina `failed`.

**D-O5. Trava do aparelho** (SEC-B1-08, CR-03).

- **Aparelho diferente da config:** um `device_id` diferente do `udid` literal
  da config ativa responde `invalid_input` com a explicação.
- **Pontos novos na trava:** `simulators.shutdown`, `wda.start` e
  `scrcpy.start` no aparelho da execução.
- **Reserva antes de mexer no aparelho:** a trava agora liga por uma reserva
  (`_run_reserva`), feita **antes** do `delete_session` e da parada da escuta
  passiva.
- **Reconferência:** a trava é conferida de novo antes de cada
  `ensure_android_session` do `hierarchy.dump` e antes de ligar o ouvinte da
  escuta passiva.

**D-O6. Expansão nas `envs`:** `$PROJECT_DIR$` e `$USER_HOME$` agora são
expandidos nos valores das `envs`.

### Outras correções

- **CR-04, disco cheio ou erro de E/S no `console.log`:**
  - o console segue só na tela, com um aviso no `run.log`;
  - a leitora continua drenando o pipe;
  - o `stop()` mata o grupo antes de escrever;
  - o `_run` sempre chega ao `_finish` (`try/finally`), o que solta a trava.
- **CR-06:** o `shutdown` espera a execução fechar o vídeo, até
  `VIDEO_CLOSE_S + 5`.
- **CR-07:** `cancelled` só quando o processo principal ainda rodava no
  `run.stop`. Depois que ele sai, o `stop` encerra os netos, devolve
  `stopped: false` e o `status` continua o do resumo. Depois que o `_finish`
  começa, o `stop` não vale mais.
- **CR-09 / SEC-B1-04:**
  - `_calls_in_order` e a coleta de `init` agora usam pilha explícita;
  - `analyze` captura `RecursionError` e `MemoryError` e os transforma em item
    de `problems`.
- **CR-10:** o pipe do filho é lido com buffer. 100 mil linhas passaram em
  menos de 2 s no teste.
- **CR-11:** a gravação do scrcpy foi para o adapter
  (`adapters/scrcpy.ScrcpyRecording`), que também valida o serial (SEC-B1-09).
  O serviço só compõe.
- **SEC-B1-03, máscara:**
  - fragmentos novos de nome sensível: `pass` (cobre `passwd` e `password`),
    `pwd`, `bearer`, `session` (cobre `sessionid`), `cookie` e `segredo`;
    `apikey` e `authorization` já eram cobertos;
  - `env` com nome sensível é mascarada a partir de 3 caracteres;
  - formas derivadas também são mascaradas: URL-encoded, a `\` dobrada de
    `repr` e o `Basic` em base64 de cada par usuário/segredo, tanto da URL
    quanto de chave `*user*` com chave sensível;
  - constantes de módulo com nome sensível no arquivo da config entram na
    máscara.
- **SEC-B1-05:** ganhou teste de regressão para DOCTYPE no `workspace.xml`.
- **SEC-B1-06:** `read_project_text` agora desce componente por componente com
  `dir_fd` e `O_NOFOLLOW`. Não sobra janela entre conferir e abrir, e não
  houve risco a aceitar. O teste simula a troca da pasta por um link no meio
  da leitura.
- **SEC-B1-09:** o `udid` da config passa por `validate_device_id` no
  `run.start` e no adapter do scrcpy.
- **SEC-B1-10:** a mensagem e a dica de cada checagem do doctor passam pela
  máscara do plano.
- **Dúvida do revisor sobre o `_emit` em duas threads:** a escrita no
  `console.log` e os contadores agora ficam sob um lock.

### O que não mudou

- Sem run configuration que case com a entrada, ainda vale a primeira (dúvida
  de paridade com o PyCharm). Fica para a B2.
- Netos que não seguram o pipe sobrevivem ao fim natural da execução. O
  contrato só exige matá-los no `run.stop`.
- Entre o `inspect` que alimentou o diálogo e o `run.start`, o motor
  reanalisa e confere a impressão, mas o front não manda a impressão que
  mostrou. A janela é pequena (SEC-B1-07, cenário 3).

### Portão da B1-5

- `make check` verde: motor 1076 testes (963 subtests), UI Tk 20, gate de QA
  11, os 5 fluxos de QA, fixtures em dia.
- `make test-swift` verde: 523 testes, 29 pulados, 0 falhas. A conta inclui o
  `ExecutionTests.swift` do dev do front, ainda em andamento no mesmo
  checkout.

## B1-6: início do vídeo pelo servidor do scrcpy

O orquestrador mediu no emulador que o vídeo do `run.start` funciona (H.264
1080×2424; 8,2 s gravados para cerca de 8,6 s reais). O `ScrcpyRecording.start`,
porém, esperava 0,5 s fixos, e no aparelho físico o primeiro step podia ficar
fora do vídeo.

**O que mudou:**

- O `start` agora espera a linha `[server] INFO: Device: …`, até 5 s, mais
  0,2 s de folga.
- Conferido no emulador com o scrcpy 5.0.1: essa linha chega pelo **stdout**,
  na hora, porque vem do processo do servidor (0,6 s no teste avulso). O
  "Recording started" do próprio scrcpy só aparece no fim, porque o stdout
  dele vai bufferizado para o pipe.
- O stdout e o stderr do scrcpy agora são drenados por uma thread cada.
- Sem a linha no prazo, a gravação segue e o aviso vai em `warning`/`video_warning`.
- `resumo.json` ganhou `video_started_at`: o epoch em que a gravação começou
  de fato, ou `null` sem vídeo. A B4 vai usar esse campo para alinhar os steps.
  - No scrcpy, ele é marcado depois da folga.
  - No `screenrecord` e no `simctl`, ele é marcado quando o `ScreenRecorder`
    volta.

**Provas:**

- Três testes com um scrcpy falso: o anúncio chega depois de 0,8 s; o anúncio
  não chega e a gravação segue com aviso; o scrcpy sai na hora e o erro traz o
  motivo.
- Um teste de que `video_started_at` vai para o `resumo.json`.
- Uma prova manual no `emulator-5554`, sem tocar no aparelho físico:
  `ScrcpyRecording` pronto em 0,43 s, sem aviso, com 223 KB gravados em 2 s.

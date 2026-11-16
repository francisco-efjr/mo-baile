# Relatório de revisão: motor da B1 (revisor de código independente)

Alvo: branch `melhoria/2026-11-12-execucao-projeto`, commits `3883906` (B1-1), `2ce543b` (B1-2), `f279bb9` (B1-3) e `6b31528` (B1-4, que entrou durante a revisão), só `engine/` e `docs/`.
Referências: [CONTRATO.md](../CONTRATO.md), [dev-motor.md](dev-motor.md), `docs/PROTOCOLO_RPC.md`, `docs/ARQUITETURA.md`.
Modo: agente (correção, segurança, contrato; sem estilo). Plataforma: motor Python local (servidor JSON-RPC por stdio), não coberta pela tabela do papel; revisado com o checklist geral mais concorrência e processos.
Data: 2026-11-12.

**Status:** DONE_WITH_CONCERNS (rascunho, modo sem interação).
**Veredito:** bloquear a integração e o empacotamento até corrigir CR-01 e CR-02. Os demais achados podem entrar em seguida.

Revisão por leitura, com provas executadas fora do repositório. Os scripts estão em
`<scratchpad>/rev/`
e rodaram contra uma cópia do código commitado (`git archive`).

Também rodei os testes novos do motor com `-p no:cacheprovider` e `PYTHONDONTWRITEBYTECODE=1`:
`test_project_run.py`, `test_project_doctor.py`, `test_projects.py`, `test_run_rpc.py` e
`test_project_rpc.py`. Foram 103 testes, todos passando. Nenhum deles cobre os cenários abaixo.

Linhas citadas: `project_run.py` e `project_doctor.py` não mudam entre `f279bb9` e `6b31528`.
`server.py` e `projects.py` estão citados como ficaram em `6b31528`.

## Resumo

- O núcleo está bem cuidado:
  - grupo de processos próprio com escada de sinais;
  - drenagem do pipe com neto pendurado;
  - máscara antes de qualquer saída;
  - leitura do projeto sem seguir link;
  - travas no mesmo `_state_lock` (RLock).
- **Pior defeito (CR-01):** um falso verde provado com o behave 1.2.6 real. Quando o
  `after_all` ou uma limpeza falha, o behave sai com falha (rc 1), mas o resumo diz
  "passed" e o Mo baile mostra **Passou**.
- **Segundo defeito (CR-02):** o `project.doctor` executa o interpretador escolhido pelo
  próprio projeto (`.venv/bin/python` ou `SDK_HOME`) sem o projeto ser confiável. A
  barreira "Confiar neste projeto?" fica sem efeito.
- O resto:
  - corridas na trava do aparelho e entre `run.stop` e o fim;
  - travamento quando a escrita do `console.log` falha;
  - dois jeitos de uma config de nuvem passar como local;
  - robustez da análise AST.

## Achados

Severidade: P0 = perda de dados ou resultado errado sempre; P1 = resultado errado ou
falha de segurança num cenário plausível; P2 = falha num cenário plausível menos comum,
ou contrato violado; P3 = robustez, desempenho ou cenário raro.

### CR-01 · P1 · Falso verde: erro no `after_all` ou numa limpeza do behave vira `passed`

- **Onde:** `engine/src/mobaile/services/project_run.py:131-163`. O `BehaveSummary.feed`
  só lê as linhas de resumo (`_SUMMARY_HEAD`, linha 77), e `status()` decide só pelas
  contagens:
  `if self._counts["scenarios"]["passed"] > 0: return PASSED`.
- **Cenário:** o `after_all` do dono chama `context.driver.quit()`, e a chamada lança
  exceção. O mesmo vale para um `context.add_cleanup(...)` que falha.
  - No behave 1.2.6 (`runner.py`, `run_model`), o hook marca `hook_failures` e
    `aborted`, imprime `HOOK-ERROR in after_all: ...` e `ABORTED: By user.`, e mesmo
    assim escreve `1 feature passed, 0 failed, 0 skipped`.
  - O behave devolve falha:
    `failed = (... or self.aborted or (self.hook_failures > 0) ... or cleanups_failed)`.
  - O Mo baile mostra **Passou**.
- **Prova** (behave 1.2.6 real em `/usr/local/bin/python3`, saída alimentada no
  `BehaveSummary` commitado; `scratchpad/rev/exp/` e `scratchpad/rev/check_summary.py`):

  ```text
  out_after_all.txt => status Mo baile: passed   (HOOK-ERROR in after_all ... ABORTED: By user. ... BEHAVE_RC 1)
  out_cleanup.txt   => status Mo baile: passed   (CLEANUP-ERROR in boom ... BEHAVE_RC 1)
  out_before_feature / out_before_scenario => failed (correto)
  ```

- **Agravante:** a linha 143 descarta em silêncio qualquer palavra do resumo que não
  conhece (`if chave in self._counts[tipo]`). Uma versão do behave que conte
  `hook_error` ou `cleanup_error` no resumo também passaria como verde. O dev já lista
  o behave 1.3 como risco não rodado.
- **Correção sugerida:**

  ```text
  _ABORT = re.compile(r"^(HOOK-ERROR in |CLEANUP-ERROR in |ABORTED:)")
  # BehaveSummary.feed: antes do match do resumo
  if _ABORT.match(line): self._hard_errors += 1; return
  # parte do resumo com palavra desconhecida e número > 0: também conta como erro
  if chave not in self._counts[tipo] and int(numero) > 0: self._hard_errors += 1
  # status(): if self._hard_errors: return FAILED
  ```

  A mensagem do `run.finished` deve citar a linha `HOOK-ERROR`. Falta um teste com
  `after_all` lançando, no estilo de `TestRunComBehaveReal`.
- **Confiança:** 95. **Rótulo:** Verificado (linha e execução).

### CR-02 · P1 · Segurança: `project.doctor` executa código do projeto sem a confiança do dono

- **Onde:**
  - `engine/src/mobaile/rpc/server.py:2519-2527`: `project_doctor_check` chama
    `self.projects.analyze(...)` e o doctor sem olhar `projeto["trusted"]`.
  - `engine/src/mobaile/services/project_doctor.py:150-154`:
    `return self._run([python, "-E", *args], ...)`, onde `python` é
    `plan.interpreter`.
  - O interpretador vem do próprio projeto:
    - `projects.py:781` (`_venv_python`: `.venv/bin/python` dentro da pasta);
    - `projects.py:1016` (`SDK_HOME` do XML de `.idea/runConfigurations`, com
      `$PROJECT_DIR$` expandido).
  - `project_doctor.py:148` ainda passa as `envs` da run configuration ao filho:
    `return {**os.environ, **plan.env, ...}`.
- **Cenário:** o dono abre uma pasta clonada de outra pessoa e o front roda o Doctor.
  - O `.venv/bin/python` pode ser um script, ou um Python legítimo com um `.pth` no
    `site-packages` do venv. O `-E` não impede o `.pth`, e o `-I` também não.
  - Um `SDK_HOME="$PROJECT_DIR$/tools/x"` aponta direto para um binário do projeto.
  - As `envs` podem trazer `DYLD_INSERT_LIBRARIES` apontando para o projeto.
  - Em todos os casos, código do projeto roda no Mac sem o diálogo "Confiar neste
    projeto?", que o contrato põe antes de qualquer execução.
  - `PROTOCOLO_RPC.md:123` afirma que a fila `project` "Não executa nada do projeto".
- **Prova** (`scratchpad/rev/poc/poc_doctor.py`): o projeto tem `trusted: False` e
  `.venv/bin/python` é um script que registra a chamada. O doctor rodou o script três
  vezes:

  ```text
  trusted: False
  executado pelo doctor: -E -c import sys; print(sys.version.split()[0])
  executado pelo doctor: -E -c import importlib.metadata as m, json ...
  executado pelo doctor: -E -m pip check
  ```

- **Correção sugerida:**
  - Sem `trusted` e sem `interpreter_override` manual, `interpreter`, `packages`,
    `requirements` e `pip_check` voltam `skip`, com a mensagem "Confie no projeto para
    o Mo baile rodar o Python dele" (ou o front abre o diálogo antes do doctor).
  - O doctor não repassa `plan.env`.
  - `PROTOCOLO_RPC.md` passa a dizer quando o doctor roda o Python do projeto.
- **Confiança:** 92. **Rótulo:** Verificado (linha e execução).

### CR-03 · P2 · Trava do aparelho com janela: a inspeção automática reabre a sessão do Appium entre o fechamento e a trava

- **Onde:** em `engine/src/mobaile/rpc/server.py`, o `run_start`:
  - fecha a sessão em `2619-2620`
    (`if self.appium.session_id and (alvo is None or ...): self.appium.delete_session()`);
  - para a escuta passiva em `2621-2622`;
  - grava `self._project_run = execucao` só em `2660`.

  A trava (`_projeto_rodando`, `2531-2534`) só vale quando `execucao.active`, e o
  `_starting` só liga dentro de `start()` (`project_run.py:345,360`). Nesse intervalo
  passam `new_run_folder`, `make_video` e a montagem do ambiente.
- **Cenário:** o inspetor do espelho pede `hierarchy.dump` a cada tela assentada (fila
  `capture`, que corre em paralelo à `services`).
  - No moto g55, o backend memorizado é `appium`, e `_android_hierarchy` chama
    `self.appium.ensure_android_session(device)` (`server.py:955`).
  - Um dump que chega na janela, ou que já estava em andamento (`server.py:922` confere
    a trava só na entrada), reabre a sessão UiAutomator2 do Mo baile.
  - O `init` do dono disputa o UiAutomation e falha. Ou, se o dump terminar depois, a
    sessão do Mo baile derruba a do teste no meio.
  - A falha vira `indeterminate`, ou um vermelho falso.
- **Correção sugerida:** reservar a trava antes de mexer no aparelho, por exemplo com
  `self._run_reservado = alvo` sob `_state_lock`, antes do `delete_session`, e
  considerar a reserva em `_recusar_se_projeto_rodando`. Conferir a trava de novo
  imediatamente antes de `ensure_android_session` e de `passive_start`.
- **Confiança:** 82. **Rótulo:** Verificado (ordem das linhas); Inferido (efeito no
  aparelho; não toquei no g55).

### CR-04 · P2 · Falha ao escrever o `console.log` trava a execução e o `run.stop` não para nada

- **Onde:** `engine/src/mobaile/services/project_run.py`:
  - `408-409`: `self._console.write(dados)` e `self._console.flush()` sem tratamento;
  - `416-419`: `_read` sem `try`;
  - `478-481`: `stop()` chama `self._emit(...)` **antes** de `self._kill_group()`;
  - `430`: o `_emit` do `_run` também fica sem proteção antes de `_finish`.
- **Cenário:** disco cheio (`ENOSPC`) ou volume do `MOBAILE_RUNS_DIR` com erro de E/S.
  Com 50 MB de console e vídeos acumulando em `~/Documents`, o disco cheio é plausível.
  1. A thread leitora morre na primeira escrita.
  2. Ninguém drena o pipe, e o filho bloqueia no `write` quando os 64 KB enchem.
  3. O `processo.wait()` nunca volta, e `run.finished` nunca chega.
  4. O `run.stop` levanta `OSError` antes de sinalizar o grupo.
  5. A trava do aparelho e a recusa de `run.start` (`device_busy`) ficam presas até
     reiniciar o motor, e o processo do dono fica órfão.
- **Prova** (`scratchpad/rev/poc2/poc_c.py`):

  ```text
  terminou em 5 s? False | processo vivo: True
  stop() levantou: [Errno 28] No space left on device
  processo ainda vivo depois do stop: True | active: True
  ```

- **Correção sugerida:**
  - No `_emit`, pôr `try: write/flush except OSError: self._console_full = True` e
    avisar uma vez pelo `run.log`.
  - No `stop()`, matar primeiro e escrever a linha de aviso depois.
  - No `_run`, usar `try/finally: self._finish(codigo)`.
- **Confiança:** 90. **Rótulo:** Verificado (linha e execução).

### CR-05 · P2 · Config de nuvem passa como local quando o `main` tem mais de um `init(...)` ativo

- **Onde:** `engine/src/mobaile/services/projects.py:1075-1076`:
  `if chamada.args and isinstance(chamada.args[0], ast.Name) and not ativa_ja_achada:`.
  O segundo `init` não comentado é descartado: não entra em `configs`, e a nuvem dele
  nunca é conferida. `run_start` (`server.py:2578` e seguintes) só olha
  `plano.active_config`.
- **Cenário:**

  ```python
  try:
      init(config_android_local_HLG)
  except Exception:
      init(config_kobiton_android_HLG)
  ```

  Também vale `if os.environ.get("NUVEM"): ... else: ...`, com a env vindo da run
  configuration. O contrato manda recusar config de nuvem, mas aqui o fallback roda na
  Kobiton pelo Mo baile. Se a mesma config também estiver num comentário, a tela a
  mostra como "alternativa comentada", o que engana o dono.
- **Prova** (`scratchpad/rev/poc3/`): `ativa: config_android_local_HLG cloud: False`, e
  `config_kobiton_android_HLG` aparece com `active= False`.
- **Correção sugerida:** juntar todos os `init` não comentados. Com mais de um,
  registrar um item em `problems` e recusar o `run.start` se qualquer um for nuvem, ou
  recusar o caso ambíguo.
- **Confiança:** 85. **Rótulo:** Verificado (linha e execução).

### CR-06 · P2 · Encerramento do motor não espera o vídeo da execução fechar

- **Onde:**
  - `engine/src/mobaile/rpc/server.py:2868-2872`: o `shutdown` chama
    `self.run_stop({})`, que só mata o grupo, e segue.
  - O vídeo fecha em `ProjectRun._finish` (`project_run.py:510-515`), numa thread
    daemon (`project_run.py:390`), com até `VIDEO_CLOSE_S = 15` s.
  - O `self.recorder.stop()` do shutdown não cobre essa gravação, porque o
    `ScreenRecorder` da execução é outro (`server.py`, `recorder_factory=lambda destino: ScreenRecorder(...)`).
- **Cenário:** o dono fecha o app durante a execução.
  - O processo do motor termina antes de a thread mandar SIGINT ao `scrcpy` ou ao
    `simctl`.
  - O `scrcpy` (sem sessão própria) segue gravando órfão, ou o MP4 fica sem índice.
  - É exatamente o que o próprio `shutdown` evita para a gravação avulsa ("Sem isto o
    MP4 fica sem indice final").
- **Correção sugerida:** no `shutdown`, depois do `run_stop`, chamar
  `execucao.wait(project_run.VIDEO_CLOSE_S + 5)`.
- **Confiança:** 80. **Rótulo:** Verificado (linhas); Inferido (corrida com o fim do
  interpretador).

### CR-07 · P3 · `run.stop` contra o fim natural: resposta e `run.finished` se contradizem, e `cancelled` esconde `failed`

- **Onde:** `engine/src/mobaile/services/project_run.py`:
  - `474-482`: o `stop()` aceita enquanto `active`, o que inclui a drenagem pós-saída
    e o fechamento do vídeo;
  - `505`: `status = CANCELLED if self.cancelled else ...` é calculado antes do
    `video.stop()`.
- **Cenários:**
  - **(a)** O `stop` chega durante o fechamento do vídeo. Ele devolve `stopped: true`,
    mas `run.finished.status` sai `passed` ou `failed`. Isso contradiz
    `PROTOCOLO_RPC.md:417` ("`run.finished` chega depois, com `status: "cancelled"`").
  - **(b)** O processo já saiu com falha e um neto segura o pipe. O `stop` dentro da
    janela de 3 s vira `cancelled`, e o `failed` some do banner.
- **Prova** (`scratchpad/rev/poc2/poc_run.py`):

  ```text
  A: stop() devolveu True | run.finished.status = passed
  B: stop() devolveu True | status = cancelled | counts.failed = 1
  ```

- **Correção sugerida:**
  - Gravar `cancelado_com_processo_vivo = processo.poll() is None` sob `_stop_lock` no
    `stop()`, e só isso decide `CANCELLED`.
  - Marcar `_finishing` no começo de `_finish` e fazer o `stop()` devolver
    `stopped: false` depois disso.
- **Confiança:** 85. **Rótulo:** Verificado (linha e execução).

### CR-08 · P3 · Config de nuvem passa como local quando outra URL de loopback aparece antes do hub

- **Onde:** `engine/src/mobaile/services/projects.py:701-705`. Qualquer valor literal
  com `://`, em qualquer chave, vira hub, e só o primeiro fica:
  `if info.hub is None or info.hub == DYNAMIC:`.
- **Cenário:** config `config_nuvem_HLG` (sem "kobiton" no nome) com
  `"appium:chromedriverProxy": "http://127.0.0.1:8888"` antes de
  `"url": "https://hub-cloud.browserstack.com/wd/hub"`. O resultado é
  `hub=127.0.0.1:8888, cloud=False`, e o `run.start` aceita uma config de nuvem.
- **Prova:** `scratchpad/rev/poc3/` (`config_nuvem_HLG active= False hub= 127.0.0.1:8888 cloud= False`).
- **Correção sugerida:**
  - Preferir as chaves de `HUB_KEYS` para o hub.
  - Marcar `cloud` se **qualquer** URL em chave de hub tiver host fora de loopback.
  - URL em chave que não é de hub não substitui o hub.
- **Confiança:** 85. **Rótulo:** Verificado.

### CR-09 · P3 · `RecursionError` na análise derruba `project.inspect`, `project.doctor` e `run.start`

- **Onde:** `engine/src/mobaile/services/projects.py:563-569`. O `visitar` é recursivo
  em Python, sem limite, e roda sobre **toda** função do arquivo de entrada
  (`projects.py:1103`). Só o `ast.parse` trata `RecursionError` (`tree`).
- **Cenário:** qualquer função do `main.py` com uma expressão longa e aninhada, por
  exemplo uma concatenação de cerca de 1.000 termos. O arquivo é Python válido.
  - O `inspect` levanta e o RPC devolve erro interno.
  - A aba Execução fica inutilizável para esse projeto.
  - O contrato diz que "`SyntaxError`, `RecursionError` e arquivo grande viram `problems`".
- **Prova** (`scratchpad/rev/poc4/`): `ast.parse ok`, seguido de
  `inspect levantou RecursionError: maximum recursion depth exceeded`.
- **Correção sugerida:** percorrer com pilha explícita (sem entrar em
  `FunctionDef`, `ClassDef` ou `Lambda`), ou capturar `RecursionError` em `analyze` e
  registrar um item em `problems`.
- **Confiança:** 90. **Rótulo:** Verificado.

### CR-10 · P3 · Leitura do console byte a byte (`bufsize=0`)

- **Onde:** `engine/src/mobaile/services/project_run.py:375-378` (`bufsize=0`) e `418`
  (`iter(self._process.stdout.readline, b"")`). Num `FileIO` sem buffer, o `readline`
  faz um `read(1)` por byte.
- **Medida** (mesma máquina, 20 MB em 250 mil linhas):
  - `bufsize 0`: 8,40 s;
  - `bufsize -1`: 0,05 s.

  Um teste verboso (log do Appium no stdout) consome CPU e GIL na thread leitora, ao
  lado do espelho.
- **Correção sugerida:** usar o padrão com buffer. O `BufferedReader.readline` num pipe
  devolve assim que chega o `\n`, então o console continua ao vivo.
- **Confiança:** 85. **Rótulo:** Verificado (medida).

### CR-11 · P3 · Arquitetura: o comando de gravação do scrcpy mora no serviço, e não no adapter

- **Onde:** `engine/src/mobaile/services/project_run.py:182-246` (`ScrcpyVideo` faz o
  `subprocess.Popen` do scrcpy). `docs/ARQUITETURA.md:85-86` diz que os adapters
  "conversam com ... scrcpy" e que os services são "casos de uso que compõem adapters".
  O adapter `adapters/scrcpy.py` já existe.
- **Efeito:** não muda o comportamento. Há dois lugares que lançam o scrcpy, e o teste
  do comando fica fora do adapter.
- **Correção sugerida:** mover `command()`, `start()` e `stop()` para
  `ScrcpyBridge.record(...)` e deixar o serviço só compor.
- **Confiança:** 80. **Rótulo:** Verificado.

## Dúvidas (confiança abaixo de 80 ou sem prova completa)

- **Máscara antes do parse do resumo** (`project_run.py:396-399`). Um segredo literal
  de 3 ou mais caracteres que seja só dígitos (por exemplo `appium:unlockKey: "100"`)
  apaga `100 failed` da linha de resumo, e a falha some.
  - O número exige 100 ou mais falhas iguais ao segredo, então o cenário é raro.
  - Mesmo assim, ler o resumo da linha crua e mascarar só para exibir custa nada.
- **behave 1.3:** não confirmei se o resumo traz `hook_error` ou `cleanup_error`.
  O fail-closed proposto no CR-01 cobre o caso de qualquer jeito.
- **Netos que não seguram o pipe** (por exemplo um Appium que o `init` sobe com pipes
  próprios) sobrevivem ao fim natural. A D-11 só mata o grupo quando o pipe fica preso.
  O contrato só exige isso no `run.stop`.
- **`_emit` em duas threads** (leitora e `stop()`): o `TextIOWrapper` não é
  thread-safe, e uma linha do `console.log` pode sair intercalada. Isso não afeta o
  parse, que usa a string e não o arquivo.
- **Paridade com o PyCharm:**
  - os valores das `envs` não expandem `$PROJECT_DIR$` (`projects.py`,
    `env = dict(escolhida["envs"])`);
  - sem run configuration que case com a entrada, vale `configs[0]`, que pode ser de
    outro script, e as `envs` e o SDK dele entram no filho.
- **B1-4:** `trusted` continua valendo depois de `project.configure` trocar
  interpretador ou entrada. Parece decisão de produto, porque é o próprio dono quem
  troca, mas o diálogo de confiança mostrou outros valores.

## Desvio de escopo e requisitos sem implementação

- **Critério 7** (vídeo real no emulador): não verificado pelo dev, como ele mesmo
  declara.
- **Critério 8:** fica com o orquestrador.
- **Trava do contrato** ("`hierarchy.dump`, `passive.start`, `flow.run`,
  `flow.maestro_run`, `codegen.record`, toque/tecla repassados e `recording.start`"):
  está implementada nos sete pontos. Ressalva da janela no CR-03.
- **Fora da lista do contrato:** `wda.start`, `simulators.shutdown` e
  `emulators.boot` podem derrubar o teste do dono durante a execução. Não é defeito
  contra o contrato. Fica a nota para a B2.
- **Sem desvio de escopo nos arquivos alterados.**

## O que foi checado e o que não foi

**Checado:**

- **`project_run.py` inteiro:**
  - resumo do behave;
  - grupo de processos e escada de sinais;
  - drenagem com neto;
  - corrida entre `start` e `stop` na subida do vídeo (inalcançável pelo RPC porque
    `run.start` e `run.stop` dividem a fila `services`);
  - fechamento do pipe;
  - vídeo;
  - `resumo.json` e `console.log` (`O_EXCL | O_NOFOLLOW`, 0600).
- **`server.py` (`run_*`, `project_*`):**
  - os sete pontos da trava, com `_state_lock` sendo um `RLock`, o que torna seguro o
    `_recusar_se_projeto_rodando` dentro do lock no `flow_run`;
  - ordem de `delete_session` e passiva;
  - shutdown.
- **`projects.py`:**
  - leitura sem link;
  - AST e tokenize com entradas estranhas;
  - nuvem;
  - máscara;
  - run configurations;
  - B1-4 (`pycharm_sdk_home`, `configure`, candidatos).
- **`project_doctor.py`:** todas as checagens.
- **Helpers novos de adb e appium:** a validação de propriedade e de pacote antes do
  shell está correta.
- **Conformidade com `PROTOCOLO_RPC.md`** em `run.*` e `project.*`.

**Não checado:**

- front Swift (fora do alvo);
- gravação real de vídeo;
- comportamento no aparelho (proibido tocar o g55);
- behave 1.3;
- `make check` completo e `make test-swift`;
- fixtures (`engine_payloads.json`) campo a campo.

## Decisões pendentes do humano

- **CR-02:** o doctor deve exigir confiança antes de rodar o Python do projeto, ou o
  diálogo de confiança vem antes do primeiro doctor?
  - Suposição adotada: exigir confiança.
  - Se o dono aceitar o risco, basta corrigir o `PROTOCOLO_RPC.md:123`, que hoje diz o
    contrário.
- **CR-01:** `HOOK-ERROR` ou `CLEANUP-ERROR` com todos os cenários passando deve dar
  `failed` ou `indeterminate`?
  - Suposição adotada: `failed`, porque é o veredito do próprio behave.
- **CR-05:** mais de um `init` ativo deve recusar sempre ou só quando algum for nuvem?
  - Suposição adotada: recusar quando algum for nuvem e avisar nos demais casos.

## Limites da revisão

- Plataforma não coberta pela tabela do papel (motor Python por stdio). Usei o
  checklist geral mais concorrência e processos.
- Independência parcial: o revisor é o mesmo modelo do autor. Recomendo leitura humana
  do diff, principalmente de `project_run.py` e `run_start`.
- Os scripts de prova ficam no scratchpad da sessão, fora do repositório, e não foram
  versionados.

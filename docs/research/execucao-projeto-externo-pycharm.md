# Rodar um projeto de automação externo (estilo PyCharm) dentro do Mo baile

Pesquisa de viabilidade, 12/11/2026. Rodada orquestrada (brain-of-agent, modo
pesquisa). Nenhum código foi alterado. O projeto do dono não foi lido: tudo o que
se diz sobre ele é **Suposição** ou **Inferido**, e está marcado assim.

Rótulos usados: **Verificado** (lido na fonte primária ou no código, com link ou
`arquivo:linha`), **Inferido** (consequência direta de fatos verificados, sem
teste) e **Suposição** (hipótese que depende de resposta do dono).

---

## 1. Resumo executivo

- **É viável e fica 100% local.** O PyCharm mostra os steps em tempo real porque
  roda o behave por um runner próprio que registra um formatter e imprime
  *TeamCity service messages* no stdout. A IDE lê essas linhas e monta a árvore.
  O Mo baile pode fazer o mesmo sem instalar nada no venv do dono. Basta um
  "shim" nosso no `PYTHONPATH` do processo filho. **Verificado** em
  `PyCharm.app/.../helpers/pycharm/behave_runner.py:299-350`.
- **O motor já tem metade da peça.** Ele roda um script em subprocesso com
  stdout ao vivo, cancelamento e máscara de segredo (`services/flows.py:445-555`).
  Também já reconhece uma linha-marcador de passo (`flows.py:27`, `:471`), grava
  vídeo (`adapters/screen_recorder.py`), sobe o scrcpy, checa o ambiente
  (`services/setup.py`) e gera HTML offline com o design system
  (`services/report/html_report.py`).
- **O risco técnico é a briga pelo aparelho, não a captura de eventos.** A
  sessão UiAutomator2 do inspetor e a do teste disputam o UiAutomation. O
  Appium do Mo baile ocupa a porta 4723 (`adapters/appium.py:55`), a mesma que
  o teste deve usar.
- **Recomendação: Opção B (PyCharm-like sem tocar no projeto), em 3 fases.**
  Esforço total G, perto de 2 a 3 rodadas. A primeira fase (Opção A) já entrega
  importar, entender o `main`, doctor, rodar, console e vídeo.
- **Antes de codar, faltam respostas do dono.** São 13 perguntas, na seção 2.
  As que mais mudam o plano: behave ou pytest-bdd, o que `executar()` chama e
  como ele roda hoje no PyCharm.

---

## 2. Hipóteses sobre o projeto do dono e perguntas

### 2.1 Hipóteses

| # | Hipótese | Base | Rótulo |
|---|---|---|---|
| H1 | BDD com **behave**, não pytest-bdd | O Python que o app usa (`/usr/local/bin/python3`, 3.14.0) tem `behave 1.2.6`, `allure-behave 2.16.0`, `Appium-Python-Client 5.1.3` e `selenium 4.34.2`. Não tem `pytest`, `pytest-bdd` nem `teamcity-messages`. O comando foi só de leitura (`importlib.metadata`), rodado em 12/11/2026 | Inferido (indício forte, mas o projeto pode ter venv próprio) |
| H2 | `executar(squad, feature)` monta argumentos e chama o behave, dentro do processo (`behave.__main__.main([...])` ou `Runner(Configuration(...)).run()`) ou fora dele (`subprocess`/`os.system("behave ...")`) | Assinatura da função | Suposição |
| H3 | Já gera Allure (`-f allure_behave.formatter:AllureFormatter -o allure-results`) | `allure-behave` instalado | Suposição |
| H4 | `init(config)` abre a sessão Appium (`webdriver.Remote(url, options)`) e guarda o driver num global ou no `context` | Padrão comum | Suposição |
| H5 | Configs são dicts ou objetos num módulo Python: `config_android_local_HLG` e outros | Nome das variáveis no `main` | Suposição |
| H6 | No PyCharm ele roda `main.py` como **run configuration Python**. Nesse modo a IDE mostra só o console, sem árvore de testes. A árvore só aparece numa run configuration Behave, que é recurso do PyCharm Professional | `behave_runner.py` só entra em run configuration de teste ([BDD no PyCharm](https://www.jetbrains.com/help/pycharm/2023.2/bdd-frameworks.html)) | Inferido |
| H7 | O `except Exception as e: print(e)` faz o processo sair com código 0 mesmo com falha. Falha de step no behave nem vira exceção: `Runner.run()` devolve um booleano | API do behave | Inferido. **Consequência:** o resultado tem de vir de eventos, nunca do código de saída |

### 2.2 Perguntas para o dono

| # | Pergunta | Por que muda o plano |
|---|---|---|
| P1 | É behave ou pytest-bdd? Qual versão? (`pip show behave pytest-bdd`) | Define o shim. behave: formatter e hooks, com APIs diferentes entre 1.2.6 e 1.3.x. pytest-bdd: plugin por `PYTEST_PLUGINS`. Runner caseiro: só stdout ou uma API opcional |
| P2 | O que `executar()` faz por dentro? Chama o behave no mesmo processo ou abre um subprocesso (`subprocess`, `os.system`)? | No mesmo processo, um wrapper com `runpy` basta. Em subprocesso, o shim precisa ir por `sitecustomize` no `PYTHONPATH` herdado |
| P3 | Qual interpretador o projeto usa? Venv na pasta (`.venv/`, `venv/`) ou outro? Qual versão do Python? | O doctor e o `run.start` precisam do Python certo. O motor hoje roda o filho com `sys.executable` do próprio motor (`flows.py:499`) |
| P4 | No PyCharm, ele vê uma árvore de steps ou só o console? Usa run configuration "Python" (`main.py`) ou "Behave"? Ela está salva como arquivo de projeto (`.idea/runConfigurations/`) ou só no `workspace.xml`? Tem variáveis de ambiente lá? | Diz o que "como no PyCharm" significa para ele. Se a run configuration for legível, ela vira a fonte do interpretador, do diretório de trabalho e das variáveis |
| P5 | Onde ficam as configs (`config_*`)? Num `.py`, YAML ou JSON? As capabilities são literais ou montadas com `os.environ` e funções? | A análise estática só lê valores literais. Config dinâmica aparece como "não resolvida" |
| P6 | Quem sobe o Appium? Ele, à mão, ou o `init` (`AppiumService`)? Em que porta? | O Mo baile sobe o próprio Appium na 4723 (`appium.py:55`, `:190`). Se o `init` também sobe, dá "address in use" |
| P7 | Já gera Allure? Em que pasta? Já tira print ou grava vídeo nos hooks (`environment.py`)? O driver fica em `context.driver`? | Evita duplicar evidência. Com `context.driver`, o print da falha sai no instante exato, pelo próprio driver |
| P8 | O `init` instala ou reinstala o app (`app`, `fullReset`, `noReset`)? | O doctor confere se o arquivo do app existe. Também muda o tempo e o vídeo |
| P9 | Quanto dura uma suíte típica e quantas features ela roda? | Tamanho do vídeo em disco, segmentação e retenção |
| P10 | No iOS, simulador ou aparelho físico? | `simctl recordVideo` só serve para simulador. Aparelho físico não tem gravador local simples (seção 4.4) |
| P11 | O `main` aceita argumentos? O nome `main_sem_args` sugere que existe um `main(args)` | Com CLI, dá para escolher config e suíte sem gerar script nem editar o arquivo |
| P12 | Se a injeção sem tocar no projeto falhar, ele aceita um arquivo opcional no projeto (`behave.ini` com o formatter, ou `conftest.py`)? | É o plano B de baixo risco |
| P13 | Onde ficam segredos (usuário e chave do Kobiton, senhas de teste)? Em `.env`, nas configs ou na run configuration? | O Mo baile nunca abre `.env*` e só lista chaves. Saber onde eles estão evita mostrá-los por engano |

---

## 3. O que o Mo baile já tem e reaproveita

| Peça | Onde | Serve para | Lacuna |
|---|---|---|---|
| Subprocesso com stdout ao vivo, `SIGTERM` cooperativo, `kill` depois de 6 s e `stdin=DEVNULL` para não comer o canal RPC | `engine/src/mobaile/services/flows.py:445-555` (`FlowExecution`) | Rodar o `main` do dono | Usa `sys.executable` do motor (`:499`); falta escolher o interpretador, o `cwd` e o `env` do projeto. Mata só o processo, não o grupo: um `behave` neto ficaria órfão |
| Linha-marcador de passo no stdout (`"\x1emobaile.step " + JSON`), retirada do log e convertida em `on_step` | `flows.py:27`, `:471-480`, `:511-517` | É o mesmo padrão das TeamCity messages. O parser de eventos nasce daqui | Só carrega `index`/`total`. Falta árvore, status, duração e erro |
| Máscara de segredo no log (`sensitive_texts`, mínimo de 3 caracteres) | `flows.py:20-21`, `:466-469` | Mascarar valores de config sensíveis no console | Hoje recebe só o texto digitado nos passos |
| Trava de execução, `flow.stop` idempotente, `flow.finished` com `cancelled` | `engine/src/mobaile/rpc/server.py:2129-2268` | Modelo de `run.start`/`run.stop`/`run.finished` | É uma trava só para "flow". A execução externa precisa travar o aparelho inteiro (seção 7) |
| Notificações `flow.log`, `flow.step`, `flow.finished` e tabela declarativa | `engine/src/mobaile/rpc/contract.py:161-168`, `:196-210` | Padrão para `run.*` | — |
| Front: `flow.log` vira `runLog`; `flow.step` move o destaque | `apps/MoBaile/Sources/MoBaile/Engine/EngineSession.swift:1944-1972`; sheet `Views/Automation/FlowRunnerSheet.swift` | Base do painel de execução | É lista plana; falta árvore. O `runLog` não tem teto visível: risco de memória com log longo do Appium (PB5 em `docs/RODADA_2026-10-05_PENDENCIAS.md`) |
| Gravação de vídeo: `screenrecord` (limite 180) e `simctl recordVideo --codec h264`, parada por `SIGINT` | `engine/src/mobaile/adapters/screen_recorder.py:33`, `:76-138`; RPC `recording.*` em `server.py:816-831` | Evidência em vídeo | Exige sessão do inspetor (`_require_session`, `server.py:824`). O comentário da `:30` diz que o `screenrecord` "recusa valores acima" de 180; o AOSP atual aceita `--time-limit 0` (seção 4.4) |
| scrcpy: localiza o binário e monta o comando | `engine/src/mobaile/adapters/scrcpy.py:36-75`; RPC `scrcpy.*` em `server.py:1370` | Vídeo sem limite, com `--record` | Hoje só espelha em janela. Falta o modo `--no-window --no-playback --record` |
| Espelho Android por `adb exec-out screencap`, sem UiAutomation | `engine/src/mobaile/adapters/adb.py:216-260`; `services/streaming.py` | Pode seguir ligado durante o teste, só como imagem | Custa CPU e banda de adb. Durante flow, `_espelho_mantido_por` não deixa pausar (`server.py:1247-1252`) |
| Diagnóstico de bloqueio do UiAutomation (instrumentação de outro dono) | `server.py:974-983` (`_mensagem_de_bloqueio`) | Item do doctor: "tem instrumentação ocupando o aparelho" | — |
| Sessão UiAutomator2 própria (`newCommandTimeout: 0`) e `delete_session` | `adapters/appium.py:273-327`, `:442` | Liberar o aparelho antes do teste do dono | Hoje nada fecha a sessão quando outra ferramenta vai usar o aparelho |
| Ambiente do Appium com `node`/`ANDROID_HOME` alcançáveis quando o app abre pelo Finder | `appium.py:170-188` | O mesmo problema vale para o projeto do dono: PATH sem Homebrew | Reaproveitar para o `env` do filho |
| Checagem de ambiente: Python, adb, Appium, uiautomator2, xcuitest, Xcode, scrcpy | `services/setup.py:159-500` (versão do driver lida do `package.json`, `:227`, `:296`); `services/diagnostics.py:67-205` | Metade do doctor (máquina) | Falta a metade do projeto: venv, pacotes, `pip check`, configs × aparelho |
| Validação de pasta de entrada fora do workspace (`validate_input_dir`) | `engine/src/mobaile/security/files.py:56-61`, usado em `report.import` (`services/report/service.py:444`) | Precedente de leitura de pasta externa sem afrouxar o SEC-5 | — |
| Travas SEC-5 do workspace: raiz `~/Documents/Mo baile`, só `pages`, `locators` e `flows`, sem `..`, sem symlink, 1 MB | `services/workspace.py:1-12`, `:26-35`, `:84-103` | **Não mexer.** O projeto externo é outra coisa: só leitura, com raiz própria autorizada | — |
| Pasta de runtime 0700 e script temporário | `security/paths.py:30` (`secure_runtime_dir`), `:99` (`write_executable_script`) | Onde gravar o shim e o arquivo de eventos | — |
| Redação de chaves sensíveis | `security/redaction.py:72` (`_is_sensitive_key`) | Listar chaves da config sem valor | — |
| HTML offline com CSP sem rede, design system, Motion e tema | `services/report/html_report.py:1-16`, `:337-375` (`_ring`, `_tile`, `_csp`), `:377`; assets em `services/report/html/` | Base do relatório de execução | O gerador é amarrado a `AuditReport` (tagueamento). A CSP é `default-src 'none'; img-src data:`, sem `media-src`: vídeo exige ajuste (seção 6) |
| Ambiente (⌘5) e `setup.check`/`diagnostics.check` no front | `Views/Environment/EnvironmentView.swift`; `EngineSession.swift:662`, `:675` | Tela do doctor | — |

---

## 4. Vias técnicas avaliadas

### 4.1 Como o PyCharm mostra steps em tempo real (Verificado no PyCharm 2026.1.2 instalado)

1. A run configuration Behave roda `helpers/pycharm/behave_runner.py` com o
   interpretador do projeto. As features vão em `PY_STUFF_TO_RUN`, separadas por
   `|`, e os cenários em `SCENARIOS` (`_bdd_utils.py:31-45`).
2. O runner registra um formatter com o nome `com.jetbrains.pycharm.formatter`
   (`behave_runner.py:299-321`). Também força `my_config.format = [formatter]`,
   `reporters = []` e `stdout_capture = False`, para o print do step aparecer na
   hora (`:348-351`).
3. O formatter (`teamcity/jb_behave_formatter.py`) trata **cada step como um
   teste**, e cenário e feature como suítes:
   - `match()` abre a feature e o cenário (`testSuiteStarted`) e emite
     `testStarted` do step (`:61-74`);
   - `result()` emite `testFailed` com a mensagem, `testStdErr` com o
     traceback, `testIgnored` para step pulado ou indefinido e `testFinished`
     com `testDuration` (`:92-121`);
   - depois de uma falha, os steps restantes saem como `testIgnored` ("Prev.
     step failed") (`:123-130`).
4. Para hooks do usuário, o runner mescla os dele com os do `environment.py`.
   Nos `before_*` o do usuário roda primeiro; nos `after_*` o do PyCharm roda
   primeiro (`behave_runner.py:98-112`). Isso importa para print de falha antes
   do teardown do dono.
5. O formato das linhas é `##teamcity[testStarted name='...' timestamp='...']`,
   com escape por `|` (`|'`, `||`, `|n`, `|r`, `|[`, `|]`, `|0xNNNN`). A nesting
   é por ordem, e o `flowId` é opcional, para paralelismo
   ([TeamCity service messages](https://www.jetbrains.com/help/teamcity/service-messages.html);
   `teamcity/messages.py:20-23`, `:61-81` no PyCharm).
6. No pytest, o PyCharm usa `_jb_pytest_runner.py`, que carrega o plugin
   `teamcity.pytest_plugin` e passa `--no-header --no-summary -q`
   (`_jb_pytest_runner.py:20`, `:61-67`).

**Dá para reproduzir no Mo baile?** Sim, e de dois jeitos que se somam:

- **Canal próprio (recomendado):** o shim emite eventos JSON por linha (JSONL)
  com id, pai, tipo, status, duração e timestamp. Isso é mais fácil de validar
  que o escape do TeamCity e carrega id explícito.
- **Parser de TeamCity messages (compatibilidade):** o motor também reconhece
  linhas `##teamcity[...]` no stdout. Se o projeto já emitir essas linhas (por
  exemplo, `teamcity-messages` com `TEAMCITY_VERSION` no ambiente), a árvore
  aparece de graça. O pacote é Apache-2.0, versão 1.33 de 30/01/2025, e suporta
  behave, pytest, unittest e outros
  ([PyPI](https://pypi.org/project/teamcity-messages/),
  [GitHub](https://github.com/JetBrains/teamcity-messages)). **Não** instalar no
  venv do dono.

### 4.2 Tabela de vias para obter eventos por step

| Via | Como funciona | Mexe no projeto? | Granularidade ao vivo | Offline | Esforço | Riscos |
|---|---|---|---|---|---|---|
| (a1) Formatter behave próprio | Classe `Formatter` com `feature/scenario/step/match/result/eof`, passada por `-f modulo:Classe` ou alias em `[behave.formatters]` ([behave formatters](https://behave.readthedocs.io/en/latest/formatters/), [CLI](https://behave.readthedocs.io/en/stable/behave/)) | Sim, se for por CLI ou `behave.ini`. **Não**, se o shim a injetar | Feature, cenário e step (inclui step indefinido e os pulados) | Sim | M | `executar()` monta os argumentos e não temos acesso a eles; resolvido em (f). API muda entre 1.2.6 e 1.3.x |
| (a2) Hooks `before_/after_step` | `environment.py` com `before_step(context, step)`; `step.status`, `step.duration`, `step.error_message` ([API behave](https://behave.readthedocs.io/en/stable/api/)) | Sim (editar `environment.py`). **Não**, se o shim mesclar hooks como o PyCharm faz | Step, com acesso ao `context` (driver, para print na hora) | Sim | M | No 1.2.6, hook que lança exceção é engolido e logado (`behave/runner.py:541-553`): o shim tem de ser à prova de falha |
| (a3) Plugin pytest/pytest-bdd | `pytest_bdd_before_step`, `pytest_bdd_after_step`, `pytest_bdd_step_error` e `pytest_runtest_logreport` ([pytest-bdd 9.0.1](https://pytest-bdd.readthedocs.io/en/latest/)); carga por `PYTEST_PLUGINS` ou `-p` ([pytest plugins](https://docs.pytest.org/en/stable/how-to/plugins.html)) | **Não** (variável de ambiente) | Step | Sim | M | Registrar o mesmo plugin por dois caminhos dá erro (doc do pytest) |
| (b) `teamcity-messages` do pip | Plugin pronto que emite TeamCity messages | Sim (instalar no venv) | Step | Sim | P | Fere "não mexer no projeto". O behave exige registrar o formatter em código (README do projeto). Serve só se já existir |
| (c) Allure results | `allure-behave` grava `{uuid}-result.json` com steps, `start`/`stop` e anexos ([test result file](https://allurereport.org/docs/how-it-works-test-result-file/)) | Precisa do formatter nos argumentos (ou já existe) | **Por cenário**: o arquivo só é escrito em `close_test`, no fim do cenário. Verificado em `allure_commons/reporter.py:120-123` e `allure_behave/listener.py:103-121` (2.16.0 instalado) | Sim | M | Sem step ao vivo. Bom para importar execuções feitas fora do Mo baile (PyCharm, CI). O Allure 3 tem `watch` ao vivo ([Allure 3](https://allurereport.org/docs/v3/)), mas é Node e telemetria não foi verificada |
| (d) JUnit XML | `behave --junit` grava XML no fim de cada feature | Precisa do argumento | Feature, no fim | Sim | P | Sem tempo real. O PyCharm recusa `--junit` no runner dele (`behave_runner.py:328-330`). Útil como **saída** para CI |
| (e) Parse de stdout puro | Regex no formatter `pretty`/`plain` padrão do behave (`Feature:`, `Scenario:`, steps, `passed/failed`) | Não | Cenário e step, quando o formatter padrão imprime | Sim | P | Frágil: depende de formatter, idioma (`Funcionalidade:`/`Cenário:`) e captura. Com captura ligada, o print do step some até a falha. Serve como **fallback** e para runner caseiro |
| (f) Shim por `PYTHONPATH` (wrapper com `runpy` + `sitecustomize`) | O motor roda `python -m mobaile_shim main.py`. O shim aplica os patches (formatter, hooks ou plugin) e chama `runpy.run_path(main, run_name="__main__")` ([runpy](https://docs.python.org/3/library/runpy.html)). Um `sitecustomize.py` na mesma pasta cobre netos (`subprocess`), que herdam o `PYTHONPATH` ([site](https://docs.python.org/3/library/site.html)) | **Não** | O que (a1), (a2) ou (a3) derem | Sim | M | Se o projeto ou o venv já tiver `sitecustomize`, o nosso o esconde: detectar e encadear. `python -S` desliga o `site`. O shim roda dentro do processo do dono e não pode quebrar nada |
| (g1) Rodar o `main` como está | Subprocesso com o interpretador, `cwd` e `env` do projeto | Não | Depende de (f) | Sim | P | Exceção engolida por `print(e)`; código de saída sem valor (H7) |
| (g2) Chamar o runner direto por feature ou cenário | `behave <feature> -n <regex>`, ou um script gerado que importa o módulo do `main` e chama `init(config_X)`, `executar(...)` e `finish()` | Não (script em `secure_runtime_dir`) | Fina, e permite reexecutar só o que falhou | Sim | G | Pula o que o `main` faz além disso (setup e argumentos de `executar`). Importar o módulo executa código de topo |

**Combinação recomendada:** (g1) + (f) com (a1) e (a2) para behave ou (a3) para
pytest-bdd. Ficam como fallback o parser de TeamCity e o (e). O (c) entra como
importação.

**Canal dos eventos:** um arquivo JSONL em `secure_runtime_dir()`, com caminho
passado por variável de ambiente (`MOBAILE_RUN_EVENTS`), e o motor lendo o fim
do arquivo. Por que não o stdout:

- a captura do behave engole o que é impresso dentro de um step;
- o print do dono se mistura com os eventos;
- um neto aberto por `subprocess` não herda um fd passado por `pass_fds`, mas
  herda a variável de ambiente.

O arquivo vira artefato da execução. **Inferido.**

**Funciona com `print(e)` engolindo exceção?** Sim, porque o status vem dos
eventos. Se o `init` falhar (por exemplo, Appium fora), nenhum teste começa. O
motor mostra "nenhum cenário iniciou" e destaca a última linha de erro do
console. O código de saída não serve (H7).

### 4.3 Entender o `main` sem executar

- `ast.parse` do arquivo cru, no processo do motor, nunca no Python do projeto.
  Ele não executa nada ([ast](https://docs.python.org/3/library/ast.html)).
  Detecta:
  - `def main_sem_args` e o que o `if __name__ == "__main__":` chama;
  - a chamada `init(<Name>)` ativa no corpo;
  - os `test_suite_*()` chamados e as definições `def test_suite_*`;
  - as chamadas `executar(squad=<str>, feature=<str>)` com argumentos literais;
  - os imports, para achar o módulo das configs.
- **Comentários não entram na AST.** Para listar as alternativas comentadas
  (`# init(config_ios_local_HLG)`), use `tokenize`, que devolve tokens
  `COMMENT` ([tokenize](https://docs.python.org/3/library/tokenize.html)).
  Depois, faça `ast.parse` só do texto do comentário. **Verificado** (doc).
- Configs: siga o import até o módulo, sem importar. Ache
  `config_* = {...}`, `dict(...)` ou chamadas `UiAutomator2Options()...`.
  Extraia as chaves e, só para chaves não sensíveis (`platformName`,
  `automationName`, `udid`, `platformVersion`, `app`, `appPackage`,
  `appActivity` e o **host** da URL do hub), o valor literal. Use
  `redaction._is_sensitive_key` para o resto. Valor não literal
  (`os.environ[...]`, f-string, chamada) aparece como "dinâmico".
- Features: resolva `feature='teste/teste.feature'` contra pastas candidatas
  (`features/`, `<squad>/`, raiz) e confira se existem. Liste `Feature:` e
  `Scenario:` lendo o `.feature` como texto. Para o parse completo de Gherkin
  (outlines, tags, idioma pt), dá para rodar `behave --dry-run -f json` no
  Python do projeto. Esse comando **importa os módulos de steps**, ou seja,
  executa código. O `--dry-run` não roda hooks (`runner.py:542` checa
  `dry_run`). Fica para a Opção C, com aviso.
- Limites: código dinâmico (`getattr`, laços que montam suítes, config vinda
  de arquivo externo) não aparece. `ast.parse` pode estourar a pilha com
  arquivo patológico, então limite o tamanho (por exemplo, 1 MB, como no
  workspace) e capture `RecursionError`/`SyntaxError`.

### 4.4 Doctor: pré-requisitos

| Checagem | Como, sem alterar nada | Fonte ou reuso | Rótulo |
|---|---|---|---|
| Interpretador do projeto | 1) Run configuration do PyCharm: `.idea/runConfigurations/*.xml` ou o componente `RunManager` de `.idea/workspace.xml` (`SDK_HOME`, `WORKING_DIRECTORY`, `SCRIPT_NAME`, `envs`). 2) `.idea/misc.xml` (`project-jdk-name`), que é só um **nome**; o caminho mora na configuração global da IDE (`~/Library/Application Support/JetBrains/PyCharm<ver>/options/jdk.table.xml`). 3) `.venv/` ou `venv/` com `pyvenv.cfg`. 4) Perguntar | [Run configurations](https://www.jetbrains.com/help/pycharm/run-debug-configuration.html), [pastas da IDE](https://www.jetbrains.com/help/pycharm/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html) | Verificado o local dos arquivos; nomes de atributos e `jdk.table.xml` **Inferidos**, conferir num projeto real |
| Variáveis da run configuration | Ler os nomes das `envs`. Valores só para repassar ao filho, nunca para exibir ou logar | — | Inferido |
| Versão do Python e pacotes | `<python> -c` com `importlib.metadata` para behave, pytest-bdd, Appium-Python-Client e selenium | `setup.py:135` (`_distribution_version`) | Verificado (técnica) |
| `requirements.txt` ou `pyproject.toml` × instalado | Comparar nome e versão, sem instalar | — | — |
| `pip check` | `<python> -m pip check`; sai com 0 ou 1 e não altera o ambiente ([pip check](https://pip.pypa.io/en/stable/cli/pip_check/)) | — | Verificado |
| Appium e drivers | Versão e drivers pelo `package.json` em `~/.appium` | `setup.py:227`, `:279-318` (hoje: Appium 3.2.2, uiautomator2 e xcuitest instalados) | Verificado |
| Porta do Appium | URL da config ativa × quem ouve na porta. Se for o Appium do Mo baile, avisar ou oferecer encerrar | `appium.py:124-148` | — |
| Aparelho | `adb devices`; `udid` da config bate? `platformVersion` × `getprop ro.build.version.release` (leitura) | `services/diagnostics.py:145` | — |
| App | Caminho de `app` existe? Ou `appPackage` instalado (`pm list packages`, leitura)? | — | — |
| UiAutomation livre | Instrumentação de outro dono rodando | `server.py:974-983` | Verificado (lógica existe) |
| Nuvem | URL do hub fora de loopback ou config com nome `kobiton` vira **bloqueado por padrão** (seção 7) | — | — |
| Feature files | Cada `executar(feature=...)` resolvido existe | 4.3 | — |

### 4.5 Vídeo de evidência local

| Meio | Limite | Conflito com o teste do dono | Custo | Rótulo |
|---|---|---|---|---|
| `adb shell screenrecord` (já no motor) | A documentação diz que 180 s é o padrão **e o máximo** ([adb](https://developer.android.com/tools/adb#screenrecord)). O código atual do AOSP aceita `--time-limit 0` = sem limite ([screenrecord.cpp](https://android.googlesource.com/platform/frameworks/av/+/main/cmds/screenrecord/screenrecord.cpp)). A remoção foi anunciada para o Android 14 ([issue tracker](https://issuetracker.google.com/issues/236721231)). Sem áudio; rotação corta a imagem | Não usa UiAutomation | Grava no aparelho (20 Mbps padrão) e puxa no fim | Verificado o código do AOSP; versão mínima **Inferida** (14). Testar no moto g55 e no emulador |
| `screenrecord` em segmentos de 180 s | Encadear arquivos e juntar com o concat demuxer do ffmpeg ([ffmpeg-formats](https://ffmpeg.org/ffmpeg-formats.html)), ou mostrar vários vídeos em sequência | Não | Perde cerca de 1 s entre segmentos (Inferido). O ffmpeg 9.0.2 existe nesta máquina, mas não vem com o app | Inferido |
| **scrcpy `--no-playback --no-window --no-audio --record=arquivo`** | Sem limite; `--time-limit` é opcional ([recording.md](https://github.com/Genymobile/scrcpy/blob/master/doc/recording.md)) | O servidor roda como `shell` via `app_process` e captura pela API de display/MediaCodec ([develop.md](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md)); a doc não cita UiAutomation | Grava direto no Mac. O tamanho depende de `--video-bit-rate`/`--max-size`/`--max-fps` (padrão não verificado nesta rodada). scrcpy 5.0.1 nesta máquina | Verificado (sintaxe e modelo); "não disputa UiAutomation" **Inferido** |
| Appium `startRecordingScreen` | UiAutomator2: até 1800 s, em pedaços de 180 juntados com ffmpeg **no host do Appium**; sem ffmpeg, volta só o último pedaço ([Java client doc](https://javadoc.io/static/io.appium/java-client/10.1.1/io/appium/java_client/android/AndroidStartScreenRecordingOptions.html)). XCUITest: padrão 180 s, máximo 600 s, via ffmpeg sobre o MJPEG do WDA ([types.ts](https://app.unpkg.com/appium-xcuitest-driver@11.17.3/files/lib/commands/types.ts)) | Exige a sessão **do dono**: o Mo baile teria de chamar dentro do processo dele | Vídeo vem em base64 no fim | Verificado |
| `xcrun simctl io <udid> recordVideo --codec=h264` (já no motor) | Sem limite; para com `SIGINT`, e o simctl fecha o arquivo; "Recording started" sai no stderr. O padrão é HEVC, então manter `--codec h264` para tocar em qualquer navegador (`xcrun simctl io help`, Xcode desta máquina) | Não | Grava no Mac | Verificado |
| iPhone físico | Não há gravador de linha de comando da Apple. Opções locais: `startRecordingScreen` do XCUITest na sessão do dono, ou ler o MJPEG do WDA do dono e gravar com ffmpeg | Disputa o WDA (porta 8100/9100) com o do Mo baile | — | Inferido |

**Marcar steps no vídeo:**

- Cada evento do shim carrega `time.time()`. O motor anota o relógio quando a
  gravação começa: scrcpy ao subir; simctl ao ver "Recording started".
- O motor gera um `capitulos.vtt` (WebVTT, cues de capítulo
  `00:00:12.300 --> 00:00:15.100` com o título do step), definido em
  [WebVTT §3.5](https://www.w3.org/TR/webvtt1/).
- No app, o AVPlayer pula para o step. No HTML, um clique na linha do step faz
  `video.currentTime = offset`.
- Erro esperado de alinhamento: algumas centenas de ms. **Inferido**, medir.
- O Xcode faz o mesmo nos relatórios de UI test: timeline de eventos ligada ao
  quadro do vídeo ([WWDC23 10175](https://developer.apple.com/videos/play/wwdc2023/10175);
  [WWDC25 344](https://developer.apple.com/videos/play/wwdc2025/344)).

**Print do step que falhou:**

- Primeira escolha: o shim chama `context.driver.get_screenshot_as_png()` no
  `after_step` de status `failed`. Ele roda **antes** do `after_step` do dono,
  pela mesma ordem do PyCharm (`behave_runner.py:107-112`). É **Suposição**
  que o driver more em `context.driver` (P7).
- Fallback: o motor tira `adb exec-out screencap` ao receber o evento de
  falha. O print atrasa um pouco e pode pegar o teardown.

### 4.6 Resultado no padrão do Mo baile

- **Modelo novo de domínio** `RunReport`: projeto, config ativa sem segredos,
  aparelho, início e fim, e a árvore suíte > feature > cenário > step. Cada nó
  leva status (`passed`/`failed`/`skipped`/`undefined`/`untested`),
  `duration_ms`, mensagem, traceback, offset no vídeo e print. O `AuditReport`
  não serve: ele é de tagueamento (`domain/report.py`).
- **Gerador `run_html.py` novo**, reaproveitando de `html_report.py`:
  - os assets (`design_system.css`, `report.css`, `icons.json`,
    `motion.min.js`);
  - o tema (`_HEAD_JS`), `_csp`, `_seg`, `_ring` (passou, falhou, pulou),
    `_tile` e o rodapé.
  - A visão "Cards" vira um card por cenário, com a lista de steps, e a
    "Tabela" vira uma linha por step.
- **Vídeo no HTML:** a CSP atual (`html_report.py:371-374`) bloqueia mídia.
  Duas saídas:
  - (1) arquivo ao lado (`relatorio.html` + `video.mp4` + `capitulos.vtt`) com
    `media-src` liberando o arquivo local. O comportamento de `'self'` em
    `file://` varia por navegador: **não verificado**, testar Safari e Chrome;
  - (2) vídeo embutido em `data:`. Ele cresce 33% e pode passar de dezenas de
    MB.
  - Recomendo (1), com teste nos dois navegadores como critério de pronto.
- **Saídas extras baratas:** `junit.xml`, gerado dos mesmos eventos (para CI),
  e o `eventos.jsonl` cru.
- **Onde gravar:** `~/Documents/Mo baile/Execuções/<projeto>/<AAAAMMDD-HHMMSS>/`.
  Segue o padrão de `default_export_dir` (`services/report/service.py:387-390`).
  Nada é gravado na pasta do projeto do dono.

---

## 5. Opções de plano

### Opção A: mínima ("rodar o main com console e vídeo")

- **O que o dono vê:**
  - aponta a pasta do projeto;
  - vê o `main` resumido: config ativa, alternativas comentadas, suítes e
    features (com "existe" ou "não achei");
  - vê um doctor básico;
  - clica em Rodar e acompanha console ao vivo, espelho opcional e vídeo;
  - no fim: passou, falhou ou indeterminado, pelo resumo do behave no stdout,
    e o vídeo.
- **Entregáveis:**
  - A1 `project.open`/`project.inspect`: AST, tokenize e leitura de configs;
  - A2 `project.doctor`: interpretador, pacotes, `pip check`, Appium, porta,
    aparelho, app e UiAutomation;
  - A3 `run.start`/`run.stop`/`run.status`: subprocesso com interpretador,
    `cwd`, `env` e `PYTHONUNBUFFERED=1`, matando o **grupo de processos**;
  - A4 vídeo por scrcpy (Android) ou simctl (simulador), atrelado à execução e
    sem exigir sessão do inspetor;
  - A5 trava de aparelho (seção 7).
- **RPCs:** `project.open`, `project.inspect`, `project.doctor` (com progresso),
  `project.list`, `project.forget`, `run.start`, `run.stop`, `run.status`.
  Notificações: `run.log` e `run.finished`.
- **Front:** seção "Projetos" com três painéis (Projeto, Doctor, Execução) e um
  console com teto de linhas.
- **Esforço:** M (cerca de 1 rodada).
- **Riscos:** status impreciso, porque o código de saída não vale (H7) e o
  parse de stdout é frágil. Sem árvore.
- **Fica fora:** steps, relatório HTML e escolha de config.

### Opção B: PyCharm-like sem tocar no projeto (**recomendada**)

- **O que o dono vê:** tudo da A e mais:
  - **árvore ao vivo** Feature > Cenário > Step, com ícone de status, tempo e
    filtro "só falhas", como o PyCharm;
  - clicar num nó filtra o console e pula o vídeo para aquele step;
  - print do step que falhou;
  - no fim, o relatório HTML no padrão do Mo baile, com vídeo e capítulos, e
    `junit.xml`.
- **Entregáveis por fase:**
  - **B1 = Opção A.**
  - **B2 shim de eventos.** Pacote `mobaile_shim` copiado para
    `secure_runtime_dir`, com:
    - wrapper `runpy` e `sitecustomize` encadeável;
    - adaptador behave: formatter injetado em `Configuration` e hooks mesclados
      em `Runner.load_hooks`, como em `behave_runner.py:98-112`, compatível com
      1.2.6 e 1.3.x;
    - adaptador pytest-bdd por `PYTEST_PLUGINS`;
    - eventos JSONL; captura de stdout desligável (`stdout_capture=False`, como
      o PyCharm) e desligada por padrão;
    - no motor, leitor do JSONL, parser de `##teamcity[...]` como fallback e a
      notificação `run.event`.
  - **B3 árvore no front:** `OutlineGroup`/`List` com `StatusIndicator` do DS,
    contadores, tempo por nó e console por nó.
  - **B4 evidência:** capítulos WebVTT, print de falha (driver do `context` ou
    `screencap`), gerador `run_html.py`, `junit.xml` e a pasta de execução.
- **RPCs:** as da A, mais:
  - `run.report` (gerar ou reabrir o HTML) e `run.history` (execuções da pasta);
  - notificação `run.event` com
    `{run_id, kind: suite_started|test_started|test_finished|test_failed|test_ignored, id, parent_id, name, location, status, duration_ms, message, ts, video_offset_ms?}`.
  - `run.log` ganha `node_id?`.
- **Front:** painel Execução com três colunas adaptáveis (árvore, console,
  vídeo/espelho), reaproveitando o `AdaptivePair` do 3.6.1. Também o botão
  "Abrir relatório".
- **Esforço:** G (B1 M; B2 M; B3 M; B4 M). Perto de 2 a 3 rodadas.
- **Riscos:**
  - monkeypatch em versão do behave não testada: mitigar com teste de contrato
    contra 1.2.6 e 1.3.x e fallback para parse de stdout;
  - `sitecustomize` preexistente;
  - `executar()` chamando o behave por um caminho que não passa pelos pontos
    corrigidos, por exemplo um runner caseiro;
  - alinhamento do vídeo.
- **Fica fora:** escolher config ou cenário e reexecutar falhas (vai para a C).

### Opção C: integração profunda

- **O que o dono vê:** a B e mais:
  - escolher a config no Mo baile (só as locais habilitadas), as suítes e as
    features, sem editar o `main`;
  - rodar um cenário só pelo menu da árvore;
  - "Reexecutar falhas";
  - histórico com comparação entre execuções;
  - doctor com capabilities × aparelho em detalhe.
- **Entregáveis:**
  - C1 script de entrada gerado (importa o módulo do `main`; `init(<config>)`;
    suítes escolhidas; `finish()`), ou CLI do `main` se existir (P11);
  - C2 descoberta Gherkin completa (`--dry-run -f json` no Python do projeto,
    com aviso de que importa steps);
  - C3 `-n` por cenário e rerun;
  - C4 histórico e instabilidade.
- **RPCs:** `project.features`, `run.start` com `selection`, `run.rerun_failed`
  e `run.compare`.
- **Esforço:** G+ (mais 1 a 2 rodadas depois da B).
- **Riscos:**
  - desvio do `main` real (o script gerado pula setup que o dono tenha);
  - `executar()` pode não aceitar cenário;
  - importar o módulo executa código de topo.
- **Fica fora:** nuvem.

### Opção D: Allure-first (complemento, não substituto)

- **O que o dono vê:** importar uma pasta `allure-results` (de execução no
  PyCharm ou em CI) e ver no relatório do Mo baile. Dentro do Mo baile, o
  progresso chega por cenário.
- **Entregáveis:** leitor de `*-result.json` e `*-container.json` com anexos,
  e conversão para `RunReport`.
- **RPC:** `run.import_allure`.
- **Esforço:** M.
- **Riscos:** sem step ao vivo, porque o arquivo só sai no fim do cenário
  (verificado no `allure-commons` 2.16). Formato mantido por terceiro.
- **Fica fora:** execução.

### Recomendação

**Opção B, em fases, começando por B1 (= A).** Motivos:

1. Entrega o que foi pedido nos itens 1 a 5 sem tocar no projeto do dono e sem
   rede.
2. Copia um mecanismo comprovado: o do próprio PyCharm, lido no código
   instalado.
3. Reaproveita o que o motor já tem: `FlowExecution`, marcador de passo,
   gravação, scrcpy, setup e HTML.
4. Cada fase entrega algo usável e tem critério de pronto claro.

A C só vale depois de o dono usar a B e pedir. A D é barata e pode entrar junto
com a B4, se P7 confirmar Allure.

**Critérios de pronto da B:**

1. Com um projeto behave de exemplo e o projeto do dono, a árvore mostra cada
   step ao vivo, com status e tempo iguais aos do PyCharm (run configuration
   Behave) para a mesma feature.
2. O vídeo abre no step que falhou a menos de 1 s do momento real.
3. O HTML abre offline no Safari e no Chrome, com vídeo tocando e capítulos.
4. Nenhum byte sai da máquina durante a execução (conferido com
   `nettop`/`lsof -i`, como na pesquisa do Maestro).
5. Nenhum arquivo do projeto do dono é alterado (hash da pasta antes e depois).
6. Inspetor, passivo e flow ficam bloqueados durante a execução, com mensagem
   clara.

---

## 6. Riscos e travas de segurança

| Risco | Trava proposta |
|---|---|
| **Caminho fora de `~/Documents/Mo baile`** | Não afrouxar o SEC-5 do `workspace.py`. Criar `services/projects.py`: raiz escolhida pelo dono num `NSOpenPanel`, validada com `validate_input_dir` (`security/files.py:56`), guardada numa lista de projetos autorizados. Acesso **somente leitura** e só a extensões de texto (`.py`, `.feature`, `.ini`, `.cfg`, `.toml`, `.txt`, `.xml` de `.idea`), sem seguir symlink e com teto de tamanho. Nunca ler `.env*`, `*.pem`, keystores, `local.properties` nem `google-services.json`; nunca entrar em `.venv`, `venv` ou `.git` para conteúdo, e nunca gravar na pasta do projeto |
| **Executar código do dono** | É o mesmo nível de confiança do PyCharm ao rodar o projeto. Na primeira execução, um diálogo "Confiar neste projeto?" mostra o interpretador, o script e o `cwd`. O filho roda com `stdin=DEVNULL` (como `flows.py:503`), num grupo de processos próprio (`start_new_session=True`) para `run.stop` matar netos, com `cwd` no projeto. O shim é nosso, pequeno e não pode lançar exceção para o código do dono |
| **Segredos em configs, run configurations e env** | Mostrar só **chaves**, nunca valores, de qualquer chave sensível (`_is_sensitive_key`). URL de hub aparece só com o host (`redact_url`). Valores de `envs` da run configuration vão para o filho e nunca para log, RPC ou relatório. Valores literais sensíveis achados na config entram em `sensitive_texts` para mascarar o console (`flows.py:466`). O relatório nunca inclui a config crua |
| **Kobiton e nuvem** | Config cujo hub não é loopback, ou cujo nome ou host contém `kobiton`, aparece como "Nuvem: bloqueada". `run.start` recusa quando o `init` ativo aponta para nuvem, com erro explícito. A liberação exige um ajuste em Configurações com o texto "envia dados para fora desta máquina", desligado por padrão, e um parâmetro `allow_cloud: true` por execução. Fora disso o Mo baile não abre conexão; o que o código do dono faz por conta própria (por exemplo, um `requests` para um serviço) não é controlável, e o doctor só avisa quando achar URL externa literal |
| **Telemetria** | behave, pytest e Appium-Python-Client não enviam nada (não verificado formalmente, verificar com `lsof` no aceite). Não usar Allure 3 nem `allure serve` dentro do Mo baile: telemetria não verificada. O HTML gerado mantém a CSP sem rede |
| **Sobrescrever ambiente** | O `PYTHONPATH` do shim vai na frente do `PYTHONPATH` do dono, sem apagá-lo. Se existir `sitecustomize` no caminho do projeto, o nosso importa o dele depois de agir |
| **Disco** | Vídeo com bitrate reduzido, retenção configurável (por exemplo, últimas N execuções por projeto) e aviso quando a pasta passar de um limite |

---

## 7. Concorrência pelo aparelho (proposta de comportamento)

Fatos:

- A leitura de hierarquia usa `uiautomator dump` ou uma sessão UiAutomator2
  própria, com `newCommandTimeout: 0` (`server.py:914-1002`, `appium.py:273-327`).
- O UiAutomation aceita um cliente por vez (mensagem em `server.py:974-983`).
- O Appium do Mo baile sobe em `127.0.0.1:4723` (`appium.py:55`, `:190`), que é
  o padrão do Appium e, provavelmente, a URL do teste do dono (**Suposição**).

Durante `run.start` (travar o aparelho alvo, não só o "flow"):

1. **Antes de começar:**
   - fechar a sessão Appium do Mo baile para aquele `udid`
     (`appium.delete_session`, `appium.py:442`);
   - parar o WDA próprio no iOS;
   - se o `init` do dono sobe Appium na 4723 (P6), parar o Appium do Mo baile;
     se o dono usa o servidor já de pé, mantê-lo;
   - parar a escuta passiva.
2. **Durante:** recusar, com erro claro ("o aparelho está rodando o projeto X"):
   `hierarchy.dump`, `passive.start`, `flow.run`, `flow.maestro_run`,
   `codegen.record`, toque e tecla repassados, `wda.start`, e o
   `recording.start` avulso (o vídeo é o da execução).
3. **Espelho:** no Android ele pode continuar, porque usa `screencap` sem
   UiAutomation (`adb.py:216`). Ele custa CPU e banda de adb junto com o scrcpy
   de gravação. Proposta: pausar o espelho por padrão e mostrar o vídeo ao vivo
   do scrcpy no lugar (Inferido: mais barato). No iOS, o espelho por MJPEG
   depende do WDA (`server.py:1108-1131`), então fica desligado.
4. **Depois:** soltar a trava e não reabrir sessão automaticamente. A próxima
   leitura do inspetor abre, como hoje.
5. **Teste no aparelho certo:** o doctor confere que o `udid` da config ativa é
   o aparelho escolhido (há um moto g55 e um emulador conectados).

---

## 8. Referências de mercado (só o que vira ideia)

| Ferramenta | Como resolve "rodar e ver por step + vídeo" | Ideia para o Mo baile | Fonte |
|---|---|---|---|
| PyCharm (Professional) | Runner próprio por framework e TeamCity messages no stdout; árvore com step = teste; captura desligada | Copiar o protocolo e a ordem dos hooks; aceitar `##teamcity` como entrada | `helpers/pycharm/*` instalado (2026.1.2); [BDD no PyCharm](https://www.jetbrains.com/help/pycharm/2023.2/bdd-frameworks.html) |
| Xcode test report | Timeline de eventos sincronizada com o vídeo; clicar no evento mostra o quadro | Capítulos e "pular para o step" no player | [WWDC23 10175](https://developer.apple.com/videos/play/wwdc2023/10175), [WWDC25 344](https://developer.apple.com/videos/play/wwdc2025/344) |
| Allure Report (Apache-2.0) e TestOps (pago) | Adaptador grava JSON por teste; HTML estático; Allure 3 com `watch` | Importar `allure-results` (Opção D); não depender do gerador | [Allure behave](https://allurereport.org/docs/behave/), [Allure 3](https://allurereport.org/docs/v3/); pesquisa anterior em `docs/research/estudo-mercado/04-qualidade-codegen-mercado.md:413-421` |
| ReportPortal (Apache-2.0, self-hosted) | Agente envia resultados por API durante a execução; pilha pesada (PostgreSQL, OpenSearch, RabbitMQ, MinIO) | Confirma o modelo "agente no processo de teste empurra eventos". A pilha é pesada demais para um app local | [agent-python-behave](https://github.com/reportportal/agent-python-behave); `04-qualidade-codegen-mercado.md:423-429` |
| Appium Inspector | Não roda suíte; só inspeciona | Nada a copiar aqui; o diferencial do Mo baile é juntar inspeção e execução | — |
| Maestro Studio | Roda o flow com passo destacado; telemetria barrada pelo dono | Já coberto em `docs/research/maestro-modelo-de-automacao.md` | — |

---

## 9. O que precisa de outra área (não aberto nesta rodada)

- **Design** (antes de B3): layout do painel Execução com árvore, console e
  vídeo em monitor pequeno, seguindo o 3.6.1, e o fluxo de "Confiar neste
  projeto?".
- **QA:**
  - um projeto behave de exemplo versionado em `engine/tests/fixtures/`, com
    uma feature que passa, uma que falha e uma com step indefinido, para teste
    de contrato do shim com behave 1.2.6 e 1.3.x;
  - um projeto pytest-bdd mínimo.

---

## Fontes

Código local, lido em 12/11/2026:

- PyCharm 2026.1.2: `/Applications/PyCharm.app/Contents/plugins/python-ce/helpers/pycharm/behave_runner.py`, `_bdd_utils.py`, `_jb_pytest_runner.py`, `teamcity/jb_behave_formatter.py`, `teamcity/messages.py`, `teamcity/README.txt`
- behave 1.2.6 instalado: `behave/runner.py:541-553`
- allure-behave e allure-python-commons 2.16.0 instalados: `allure_behave/listener.py:103-121`, `allure_commons/reporter.py:120-123`
- Mo baile: arquivos e linhas citados na seção 3

Web:

- TeamCity service messages: https://www.jetbrains.com/help/teamcity/service-messages.html
- teamcity-messages: https://github.com/JetBrains/teamcity-messages e https://pypi.org/project/teamcity-messages/
- behave, formatters: https://behave.readthedocs.io/en/latest/formatters/
- behave, CLI e configuração: https://behave.readthedocs.io/en/stable/behave/
- behave, API (hooks, `Step.status`, `duration`, `error_message`): https://behave.readthedocs.io/en/stable/api/
- behave, versões (1.3.3, 04/09/2025): https://pypi.org/project/behave/
- pytest-bdd (hooks, `--cucumberjson`, 9.0.1): https://pytest-bdd.readthedocs.io/en/latest/
- pytest, carga de plugins: https://docs.pytest.org/en/stable/how-to/plugins.html
- Allure behave: https://allurereport.org/docs/behave/
- Allure, arquivo de resultado: https://allurereport.org/docs/how-it-works-test-result-file/
- Allure 3: https://allurereport.org/docs/v3/
- Python `site`: https://docs.python.org/3/library/site.html
- Python `runpy`: https://docs.python.org/3/library/runpy.html
- Python `ast`: https://docs.python.org/3/library/ast.html
- Python `tokenize`: https://docs.python.org/3/library/tokenize.html
- pip check: https://pip.pypa.io/en/stable/cli/pip_check/
- PyCharm, run configurations: https://www.jetbrains.com/help/pycharm/run-debug-configuration.html
- PyCharm, pastas da IDE: https://www.jetbrains.com/help/pycharm/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html
- PyCharm, BDD: https://www.jetbrains.com/help/pycharm/2023.2/bdd-frameworks.html
- adb screenrecord: https://developer.android.com/tools/adb#screenrecord
- AOSP screenrecord.cpp: https://android.googlesource.com/platform/frameworks/av/+/main/cmds/screenrecord/screenrecord.cpp
- Issue tracker do Android (limite de 3 min): https://issuetracker.google.com/issues/236721231
- scrcpy, gravação: https://github.com/Genymobile/scrcpy/blob/master/doc/recording.md
- scrcpy, arquitetura: https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md
- Appium, gravação Android (Java client): https://javadoc.io/static/io.appium/java-client/10.1.1/io/appium/java_client/android/AndroidStartScreenRecordingOptions.html
- Appium XCUITest, tipos de gravação: https://app.unpkg.com/appium-xcuitest-driver@11.17.3/files/lib/commands/types.ts
- `xcrun simctl io help` (Xcode desta máquina, 12/11/2026)
- WebVTT: https://www.w3.org/TR/webvtt1/
- ffmpeg formats (concat demuxer, capítulos): https://ffmpeg.org/ffmpeg-formats.html
- WWDC23 10175: https://developer.apple.com/videos/play/wwdc2023/10175
- WWDC25 344: https://developer.apple.com/videos/play/wwdc2025/344
- ReportPortal agent-python-behave: https://github.com/reportportal/agent-python-behave
- Kobiton (hub com usuário e chave na URL): https://docs.kobiton.com/automation-testing/basic-appium-server/launch-a-basic-appium-2-session

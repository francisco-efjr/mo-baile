# Auditoria de segurança do motor: B1 (execução do projeto do dono)

12/11/2026 · Status: **FINAL** para o motor em `f279bb9` (uma decisão pendente do humano, no fim) · Papel: `desktop-security-auditor` com `security-review-diff` e `verify-finding` (security-appsec) · Profundidade 1, sem subagentes.

- **Alvo:** branch `melhoria/2026-11-12-execucao-projeto`, diff `60200b9..f279bb9` em `engine/`, ou seja, os commits B1-1, B1-2 e B1-3. A B1-4 ainda não estava commitada. Ela foi lida como trabalho em andamento (WIP) do working tree e está na seção "B1-4 (WIP)".
- **Referências:** CONTRATO.md (seções "Registro de projetos", "Análise estática", "Execução" e "Trava do aparelho"), estudo `execucao-projeto-externo-pycharm.md` §6 e `docs/SEGURANCA.md`.
- **Método:** leitura do código e prova de conceito (PoC) em pasta temporária contra uma cópia exportada com `git archive f279bb9`. O app não foi executado. Não toquei em aparelho, não usei rede e não abri nenhum `.env*`, keystore ou `*.pem` real. Todo `arquivo:linha` abaixo é do commit `f279bb9`.
- **PoCs:** `<scratchpad>/sec/poc/test_poc_b1.py`. São 24 testes e cada um passa quando o comportamento descrito existe: **24/24 passam no `f279bb9`**. Rodando sobre o working tree com a B1-4 WIP, 23/24 passam. Só o SEC-B1-05 já está corrigido no WIP.

## Mapa da fronteira de confiança

| Origem (não confiável) | Entra no motor por | O que o motor faz com ela | Controle existente |
|---|---|---|---|
| Pasta escolhida pelo dono (`project.open {path}`) | `ProjectService.open` (`services/projects.py:759`) | registra `root` resolvido em `projetos.json` | `validate_input_dir` (`security/files.py:56`: `resolve`, byte nulo, tamanho) |
| `.py` do projeto (entrada, configs importadas) | `read_project_text` (`projects.py:117`) → `ast.parse`/`tokenize` | extrai entrada, configs, suítes | `lstat` por componente, `O_NOFOLLOW`, 1 MB, 200 arquivos, lista de proibidos e de pastas puladas |
| `.feature` | `_read_run` (`projects.py:895`) | título e cenários como texto | mesma leitura; candidato com `..` ou absoluto descartado (`:918`) |
| `.idea/runConfigurations/*.xml`, `.idea/workspace.xml` | `_read_run_configurations` (`projects.py:701`) | `SDK_HOME` → **interpretador**, `WORKING_DIRECTORY` → **cwd**, `envs` → **ambiente do filho** | `parse_untrusted_xml` (expat sem DOCTYPE/entidade) |
| `.venv/bin/python` do projeto | `_venv_python` (`projects.py:738`) | **interpretador** | só confere a existência de `pyvenv.cfg`, sem ler o conteúdo |
| Interpretador + env do projeto | `ProjectDoctor._python` (`project_doctor.py:150`) | **executa** `python -E -c …` e `-m pip check` | `cwd` vazio, `-E`, prazo. **Sem trava de confiança** |
| Interpretador + entrada + env | `run_start` (`rpc/server.py:2548`) → `ProjectRun._start` (`project_run.py:375`) | **executa** o `main` | `project_not_trusted` (`server.py:2566`), bloqueio de nuvem (`:2576`), lista de argumentos, `start_new_session`, `stdin=DEVNULL` |
| stdout/stderr do filho | `ProjectRun._emit` (`project_run.py:395`) | RPC `run.log`, `console.log`, `resumo.json` | `mask_line` (`project_run.py:106`), teto de linha e de arquivo |
| Nome da pasta do projeto | `new_run_folder` (`project_run.py:91`) | pasta de saída em `~/Documents/Mo baile/Execuções` | `safe_file_stem` (`security/files.py:87`), `0700`, `O_EXCL` |

O RPC é stdio entre o app Swift e o motor. Nada de fora da máquina fala com ele. Por isso o adversário aqui é a **pasta do projeto**: um repositório clonado, um `.idea` versionado por outra pessoa, um `.venv` copiado. O dono não é o adversário.

## Achados

| ID | Severidade | Confiança | Evidência | Resumo |
|---|---|---|---|---|
| SEC-B1-01 | **Alta** | Alta (PoC) | `project_doctor.py:147-154,177,242`; `projects.py:818-820,738-744`; `server.py:2513-2521` | O doctor executa o interpretador e o env que o projeto define **antes** do "Confiar neste projeto?" |
| SEC-B1-02 | **Média** | Alta (PoC) | `projects.py:325-329,658-669,860-863` | O bloqueio de nuvem falha aberto: hub dinâmico, URL concatenada, primeira URL vencendo, alias e `init` condicional passam como "Local" |
| SEC-B1-03 | **Média** | Alta (PoC) | `projects.py:87-88,387-392,673,838-840`; `project_run.py:106-110` | A máscara (D-4) deixa escapar segredo de chave com nome neutro, env curta, forma derivada (Basic/base64, `repr`) e constante fora da config |
| SEC-B1-04 | Baixa | Alta (PoC) | `projects.py:516-530,858` | `RecursionError` de um `main` hostil escapa da análise e derruba `inspect`, `doctor` e `run.start` |
| SEC-B1-05 | Baixa | Alta (PoC) | `projects.py:712,718`; `security/xml_safe.py` | `.idea/*.xml` com DOCTYPE derruba a análise inteira em vez de ser ignorado. **Corrigido no WIP** (`_safe_xml`) |
| SEC-B1-06 | Baixa | Média (PoC com corrida simulada) | `projects.py:141-153` | TOCTOU: uma pasta intermediária trocada por link entre o `lstat` e o `open` faz ler arquivo fora do projeto |
| SEC-B1-07 | Baixa | Alta | `projects.py:269,779-781`; `server.py:2566-2609` | A confiança fica presa ao caminho, e não ao que o diálogo mostrou. Interpretador, entrada, cwd ou env que mudam depois rodam sem perguntar de novo |
| SEC-B1-08 | Baixa | Alta | `server.py:2594`; `project_doctor.py:348-349`; `server.py:810,864,1395` | Trava do aparelho: trava o aparelho errado quando o `device_id` escolhido difere do `udid` da config, e `wda.start`, `simulators.shutdown` e `scrcpy.start` ficam sem trava |
| SEC-B1-09 | Info | Alta | `project_run.py:198-200,288`; `server.py:2594` | O `udid` da config chega ao argv do scrcpy sem passar por `validate_device_id` |
| SEC-B1-10 | Info | Alta | `project_doctor.py:162,183,250` | A saída do Python do projeto no doctor (stderr, `pip check`) vai ao RPC sem a máscara do plano |

---

### SEC-B1-01: o doctor executa código do projeto sem confiança (Alta)

**Invariante do contrato.** "Rodar executa o código dele nesta máquina". O diálogo "Confiar neste projeto?" mostra o interpretador e o script antes da primeira execução, e `run.start` recusa sem `trusted`. O doctor "só olha" (`project_doctor.py:1-13`).

**Cadeia.**
1. O interpretador vem de dado do projeto. Pode ser o `SDK_HOME` do XML, com `$PROJECT_DIR$` expandido (`projects.py:818-820`), ou o `.venv/bin/python` da pasta (`projects.py:738-744`).
2. `project_doctor_check` (`server.py:2513-2521`) chama `analyze` e `ProjectDoctor.run` **sem olhar `trusted`**.
3. `_interpreter` executa `[python, "-E", "-c", …]` (`project_doctor.py:154,177`), e `_pip_check` executa `-m pip check` (`:242`). O ambiente é `{**os.environ, **plan.env}` (`:147-148`), com as `envs` do XML.

**Por que `-E` e o `cwd` vazio não bastam.** Os dois protegem contra um `json.py` do projeto. Não protegem contra:
- o próprio binário ser um script do projeto;
- um `.pth` no `site-packages` do `.venv`, que roda em todo start do Python mesmo com `-E`;
- variáveis não-`PYTHON*` das `envs`. Um exemplo é `DYLD_INSERT_LIBRARIES` num Python do Homebrew, que não tem hardened runtime (Inferido, não testado).

**Cenário.**
1. O dono clona ou recebe um projeto com `.idea/runConfigurations/main.xml` contendo `SDK_HOME=$PROJECT_DIR$/tools/python`, ou com um `.venv/bin/python` que é um script.
2. Ele abre o projeto no Mo baile "só para ver o main resumido" e o doctor roda, automaticamente ou com um clique em "Rodar de novo".
3. O script roda como o usuário, sem diálogo nenhum. O projeto continua `trusted: false`.

**Prova.** `test_sec_b1_01_doctor_executa_interpretador_do_projeto_sem_confianca` e `test_sec_b1_01b_venv_do_projeto_tambem_e_executado_sem_confianca`. O marcador é gravado e `trusted` continua `False`. Os dois também passam no working tree com a B1-4 WIP.

**Refutadores examinados.**
- "O doctor faz parte do contrato": o contrato prevê `<python> -c`, mas não diz que isso dispensa a confiança, e o estudo §6 põe o diálogo antes de executar código do dono.
- "É o mesmo que o PyCharm": não confirmado. Pela documentação pública, o PyCharm abre projeto não confiável em modo de segurança, que não executa o projeto. Não verifiquei isso nesta rodada.

**Correção mínima.** No `ProjectDoctor.run`, se `not plan.project["trusted"]`, devolver `interpreter`, `packages`, `requirements` e `pip_check` como `skip`, com a mensagem "Confie no projeto para o Mo baile rodar o Python dele" e o caminho do interpretador. As checagens sem execução (Appium, aparelho, nuvem, features) continuam. Outra saída é o front abrir o mesmo diálogo de confiança antes do primeiro doctor, e o motor recusar com `project_not_trusted`, como já faz o `run.start`:

```python
# project_doctor.py, no começo de _python()
if not estado.plan.project.get("trusted"):
    raise ProjectNotTrustedError("Confie no projeto antes de o Mo baile rodar o Python dele.")
```

---

### SEC-B1-02: o bloqueio de Kobiton/nuvem falha aberto (Média)

**Invariante.** O CONTRATO.md manda o `run.start` recusar quando a config ativa está na nuvem, e o estudo §6 diz "o Mo baile não abre conexão" para fora sem `allow_cloud`. O estudo **aceita** que o código do dono possa conectar por conta própria em tempo de execução, por exemplo com `requests`. Ele **não aceita** que uma config de nuvem passe como "Local" por limitação da análise.

**Causa raiz.** `ConfigInfo.cloud` (`projects.py:325-329`) só dá verdadeiro quando há um `hub_host` literal fora do loopback, ou "kobiton" no nome da config ou no host. Tudo o que é desconhecido vira **local**.

| Variante | Código no projeto | Resultado | Teste |
|---|---|---|---|
| Hub dinâmico | `"url": os.environ.get("HUB_URL")` | `hub="dinâmico"`, `cloud=False` (`:665-669`) | `02a` |
| URL concatenada | `"url": "https://" + HOST + "/wd/hub"` | não é literal, `cloud=False` | `02b` |
| Primeira URL literal vence | `"appium:proxy": "http://127.0.0.1:8888"` antes de `"url": "https://…cloud…"` | `hub=127.0.0.1:8888`, `cloud=False` (`:661`) | `02c` |
| Alias local | `cfg = config_kobiton_android_HLG; init(cfg)` | ativa=`cfg`, `found=False`, `cloud=False` | `02d` |
| `init` condicional | `if X: init(config_local) else: init(config_kobiton)` | só o primeiro conta (`:860-863`); o Kobiton nem aparece como alternativa | `02e` |
| Hub fora do dict de caps | `webdriver.Remote("https://…kobiton…", options=…)` no `runner.py` | não analisado, `cloud=False` | (leitura; padrão comum em projetos Appium) |

**Cenário.** O dono troca o `init` para uma config Kobiton cujo hub vem de variável de ambiente, ou cujo `init` está dentro de um `if`. A aba mostra o selo "Local", o doctor dá `cloud` ok (`project_doctor.py:420`) e o `run.start` sobe o filho, que manda caps e app para a nuvem. Esse é justamente o caso de **engano** que a trava existe para pegar. Não é ataque.

**Correção mínima.** Falhar fechado e tratar a incerteza como desconhecida:
- `cloud` passa a ser três estados: `local`, `nuvem` ou `desconhecido`;
- `desconhecido` vale para hub dinâmico ou config não encontrada;
- o `run.start` recusa `desconhecido` com uma mensagem própria. Pode haver um `allow_unknown_hub: true` explícito por execução, no espírito do `allow_cloud` do estudo;
- considerar **todas** as URLs literais da config (qualquer uma fora do loopback é nuvem) e **todos** os `init(...)` do `main` (qualquer um na nuvem bloqueia, ou pelo menos aparece como alternativa).

Procurar o literal `kobiton` nos `.py` já lidos é um aviso barato no doctor.

---

### SEC-B1-03: lacunas da máscara de segredos (D-4) (Média)

**Invariante.** O critério de aceite 3 diz que "valores sensíveis nunca aparecem em RPC, log ou disco". A máscara vale para `run.log`, `console.log` e o `message` de `resumo.json` (`project_run.py:396,525`).

**O que escapa (todos provados):**
1. **Nome de chave neutro.** `_sensitive` (`projects.py:387-392`) usa `_is_sensitive_key` e os fragmentos de `:87-88`. Não pega `pwd`, `pass`, `bs_pass`, `kobiton:pwd`, `accessCode`, `apiSegredo`, `sessionId` nem `bearer` (`03a`). O valor literal dessas chaves não entra em `secrets` (`:673`) e sai em claro se o `init` imprimir a config. A fixture `EXEMPLO_IMPRIMIR_CONFIG=1` (`core/runner.py`) existe justamente para esse caso.
2. **Env curta com nome neutro.** `KOBITON_PWD=Ab#12` não é mascarada: tem menos de 6 caracteres e o nome não é "sensível" (`:838-840`) (`03b`).
3. **Formas derivadas.** `Authorization: Basic base64(usuario:chave)` e o `repr` de um valor com `\` saem sem máscara, porque `mask_line` só faz substituição literal (`project_run.py:106-110`) (`03c`). Que o cliente Appium/Selenium imprima o cabeçalho depende do nível de log do projeto (Não verificável aqui).
4. **Constante fora da config.** `KOBITON_API_KEY = "…"` no `configs.py`, usada pelo runner e não pelo dict, não entra na máscara (`03d`).

**Impacto.** O segredo fica no `console.log` (`0600`, em pasta `0700`) e na tela. O risco real é print de tela, demonstração, ou anexar o console a um bug (a casa tem "Copiar Bug"). Não há envio para fora pelo motor.

**Correção mínima.**
- Acrescentar `pass`, `pwd`, `bearer`, `session`, `cookie`, `apikey` e `segredo` aos fragmentos.
- Para env da run configuration, mascarar todo valor de 3 caracteres ou mais quando o nome bate com o fragmento, e documentar o resto.
- Em `ProjectPlan.masks`, acrescentar as formas derivadas de cada par usuário+segredo: `base64(f"{u}:{s}")`, `urllib.parse.quote(s)` e `repr(s)[1:-1]`.
- Juntar à máscara as constantes de módulo com nome sensível nos arquivos de config já lidos (`_module_assignments` já existe).

---

### SEC-B1-04: `RecursionError` escapa da análise (Baixa)

`_calls_in_order` (`projects.py:516-530`) é recursivo em Python e roda fora do `try` que cerca o `ast.parse` (`:450-456`). Uma expressão longa e legítima, como `f(a + a + … + a)` com 5 000 termos dentro de `main_sem_args`, passa pelo `ast.parse` e estoura no `visitar` (`:858`). O `RecursionError` sobe até o RPC como "Erro interno no motor" (`server.py:2750-2755`, que também devolve o traceback). `inspect`, `doctor` e `run.start` desse projeto ficam inutilizáveis. Falha fechado: nada roda.

Prova: `test_sec_b1_04_recursion_error_escapa_da_analise`.

Correção: trocar `visitar` por uma pilha explícita (`ast.walk` não serve porque perde a ordem e entra em `def`), ou envolver `_read_main` e `_resolve_configs` num `except RecursionError` que vira `problem`.

### SEC-B1-05: DOCTYPE em `.idea/*.xml` derruba a análise (Baixa; corrigido no WIP)

`parse_untrusted_xml` **levanta** `InvalidInputError` diante de DOCTYPE ou entidade. Em `f279bb9`, `_read_run_configurations` (`projects.py:712,718`) não captura essa exceção. Um `workspace.xml` com DOCTYPE faz `inspect`, `doctor` e `run.start` recusarem o projeto inteiro. A defesa contra XXE e contra o billion laughs **funciona**: a entidade é recusada e nada se expande (`05b`).

Prova: `05` (passa em `f279bb9` e falha no WIP).

O WIP (B1-4) já troca por `_safe_xml`, que devolve `None`. Falta um teste de regressão com DOCTYPE no `workspace.xml` na suíte do motor.

### SEC-B1-06: TOCTOU entre o `lstat` e o `open` (Baixa)

`read_project_text` confere cada componente com `lstat` (`projects.py:141-151`) e abre o caminho completo com `O_NOFOLLOW` (`:153`). O `O_NOFOLLOW` protege só o **último** componente. Se uma pasta intermediária for trocada por link depois da conferência, o `open` atravessa o link.

Prova: `06`, com a corrida simulada por monkeypatch do `os.lstat`.

Exige outro processo gravando na pasta do projeto durante a análise. O impacto é ler um `.py`/`.feature` de até 1 MB fora do projeto, e dele só saem nomes de chave e valores da lista permitida. Os arquivos proibidos continuam recusados, porque o filtro é pelo nome.

Correção: descer com `dir_fd`, abrindo cada componente com `os.open(parte, O_RDONLY | O_DIRECTORY | O_NOFOLLOW, dir_fd=pai)` e o arquivo com `O_NOFOLLOW` relativo à última pasta. É o mesmo padrão que `write_file_atomic` já usa (`security/paths.py:123`).

### SEC-B1-07: a confiança não fica presa ao que o diálogo mostrou (Baixa)

- O `trusted` é um booleano por `id = sha1(caminho)` (`projects.py:208,269,779-781`).
- O `run.start` reanalisa e, com `trusted: true`, confia no que achar naquele momento (`server.py:2572,2609`).

**Cenários.**
1. O dono confia no projeto. Um `git pull` traz um `.idea/runConfigurations/main.xml` com outro `SDK_HOME`, `WORKING_DIRECTORY` ou `envs`, e o próximo Rodar executa sem diálogo.
2. A pasta é apagada e outro repositório é clonado no mesmo caminho: continua confiável.
3. Entre o `inspect` que alimentou o diálogo e o `run.start {trusted: true}`, o XML muda, e o dono aprova uma coisa e roda outra. A janela de tempo é pequena.

O PyCharm também confia por pasta, por isso a severidade é Baixa.

**Correção.** Gravar na confiança uma impressão `{interpreter, entry, working_dir, sorted(env_names)}`. O `run.start` compara e, se divergir, volta a `project_not_trusted` com a diferença. Na primeira vez, o front manda a impressão que mostrou no diálogo, e o motor recusa se ela não bater.

### SEC-B1-08: lacunas na trava do aparelho (Baixa)

1. **Aparelho errado.** `alvo = device_id or udid_da_config or sessão` (`server.py:2594`). Quando o dono escolhe o aparelho X na barra e a config fixa Y, o motor trava e grava X, mas o teste do dono usa Y. O próprio doctor admite isso: "o teste usa o da config" (`project_doctor.py:348-349`). `hierarchy.dump`, `flow.run` e `passive.start` em Y passam durante a execução. A correção é preferir o `udid` literal da config quando ele existe, e avisar.
2. **Handlers sem trava.** Ficam sem `_recusar_se_projeto_rodando`:
   - `simulators.shutdown` (`server.py:810`): desliga o simulador sob teste;
   - `wda.start` (`:864`): abre uma sessão XCUITest pelo Appium do Mo baile no mesmo simulador;
   - `scrcpy.start` (`:1395`): a janela do scrcpy repassa toque e tecla, e "toque/tecla repassados" está na lista do contrato.

   Conferi com a lista de chamadas da trava em `f279bb9`: `recording_start`, `hierarchy_dump`, `input_tap`, `input_text`, `codegen_record`, `passive_start`, `flow_run` e `flow_maestro_run`.
3. A trava compara strings de serial. O mesmo Android visto por USB e por `adb connect ip:porta` tem dois seriais (Inferido).

O efeito é sobre a integridade da execução, não confidencialidade, e depende de ação do próprio dono.

### SEC-B1-09: o `udid` da config vai ao scrcpy sem validação (Info)

`ScrcpyVideo` monta `[scrcpy, "-s", serial, …]` (`project_run.py:198-200`) com o `alvo` vindo do `udid` literal da config (`server.py:2594`, `project_run.py:288`). O caminho do `ScreenRecorder` valida (`screen_recorder.py:80`), mas o do scrcpy não.

Não há injeção hoje: é lista de argumentos sem shell, e o `-s` consome o próximo argumento mesmo que ele comece com `-`. É inconsistente com `docs/SEGURANCA.md`, onde serial é entrada externa. Correção: `validate_device_id(alvo)` no `run_start`, antes de `make_video`.

### SEC-B1-10: a saída do doctor não passa pela máscara (Info)

A mensagem de `interpreter` com stderr (`project_doctor.py:183`), o erro de `_versions` (`:162`, que também vai ao `logger.info` em `:140`) e as linhas do `pip check` (`:250`) vão ao RPC sem `mask_line(…, plan.masks)`. Só vira problema se o Python do projeto imprimir segredo no start (um `sitecustomize`, por exemplo). Correção barata: passar as mensagens do doctor pela máscara do plano.

## Conforme (pontos fortes)

- **Leitura.** O caminho absoluto, `..` e componente vazio são recusados (`projects.py:126`). Há `lstat` em todo componente e `O_NOFOLLOW` no arquivo, `fstat` exige arquivo comum, o teto de 1 MB vale antes e depois da leitura, e a leitura para em 200 arquivos.
  - Os proibidos são recusados sem diferenciar caixa: `.env*`, `*.pem`, `*.p12`, `*.key`, `*.keystore`, `*.jks`, `local.properties` e `google-services.json`.
  - As pastas `.venv`, `venv`, `.git` e `node_modules` são puladas.
  - O teste `test_refutado_arquivos_proibidos_e_symlink` passa.
  - Do `.venv` só a existência de `pyvenv.cfg` é conferida; o conteúdo não é lido.
- **XML.** `parse_untrusted_xml` recusa DOCTYPE e entidade e não resolve entidade externa (`05b`).
- **AST.** Nada é importado. Os `SyntaxError`, `RecursionError` e `MemoryError` do `ast.parse` e o erro do `tokenize` viram `problem`. A exceção é o SEC-B1-04, que fica fora desse `try`.
- **Execução.**
  - É lista de argumentos sem shell, com `stdin=DEVNULL`, `start_new_session=True` e escada SIGINT → SIGTERM → SIGKILL no **grupo** (`project_run.py:452-472`).
  - Se um neto segura o pipe, o grupo é encerrado (`:428-433`).
  - O `PYTHONPATH` e o `PYTHONHOME` do motor não vazam (`server.py:2633`).
  - O ambiente do motor não carrega segredo do Mo baile: o `EngineClient.swift:120-133` só põe `PYTHONPATH`, `PYTHONUNBUFFERED` e `PYTHONPYCACHEPREFIX`. As `envs` do XML no filho têm o mesmo nível de confiança de executar o `main`.
- **Pasta de execução.**
  - `safe_file_stem` reduz o nome a `[a-z0-9-]`, então não há travessia pelo nome do projeto (`test_refutado_nome_de_projeto_nao_atravessa_pasta`).
  - A pasta é criada com `0700` e nunca reaproveitada.
  - O `console.log` é aberto com `O_EXCL | O_NOFOLLOW` e modo `0600`, e o `resumo.json` é gravado por `write_file_atomic`.
- **Registro.** `projetos.json` fica fora de `~/Documents` (`home.data_dir`) e é gravado de forma atômica. Contém só id, caminho, nome, entrada, `trusted` e data; nenhum valor de config ou env.
- **RPC de análise.** `to_dict` não inclui `env` nem `masks`. O hub sai como `host:porta`, sem userinfo nem caminho (`_host_port`). O userinfo da URL entra na máscara cru e decodificado.
- **Confiança no RPC.** Não há como rodar sem `trusted` por um caminho de rede. O RPC é stdio do app, e `trusted` só é aceito como booleano (`server.py:2557-2570`). Esquecer o projeto e abri-lo de novo zera a confiança (`projects.py:269`).
- **adb novo.** `get_prop` e `package_installed` validam a propriedade e o pacote por regex antes de `adb shell` (`adapters/adb.py:44-45,204-231`).

## B1-4 (WIP no working tree, não commitada): leitura rápida

- `_safe_xml` corrige o SEC-B1-05.
- `project.configure` aceita `interpreter` com caminho absoluto de executável existente (`validate_interpreter_path`) e `entry` validado por `read_project_text`. O override é escolha explícita do dono e não é dado do projeto. Mesmo assim, o doctor executa esse override sem confiança, pelo SEC-B1-01.
- `pycharm_sdk_home` lê o `jdk.table.xml` global do PyCharm pelo **nome** vindo de `.idea/misc.xml` ou de `SDK_NAME`. O projeto só consegue escolher entre SDKs que o próprio dono cadastrou. O parser é seguro e o teto é de 4 MB.
- `find_candidate_pythons` executa os Pythons da máquina (Homebrew, `/usr/bin`, shims do pyenv e do asdf) com `-E` em pasta vazia durante o `project.inspect`, quando não há interpretador. Isso não é código do projeto. Vale ajustar a docstring "sem executar nada" para "sem executar nada do projeto".
- Rodei as PoCs sobre a cópia do working tree: 23/24 passam. SEC-B1-01 a 04 e 06 continuam valendo.

## Descartados ou sem evidência

- **Travessia pelo nome do projeto:** refutada por `safe_file_stem`, com teste.
- **XXE e billion laughs:** refutados com teste.
- **Injeção de shell no filho:** não há shell. `entry` vem de `detect_entry`, que só aceita nomes da raiz, ou do override validado, e vai como `str(root / entry)`.
- **Injeção de argumento no scrcpy:** sem efeito, porque o `-s` consome o argumento seguinte. Ficou registrado como Info (SEC-B1-09).
- **Diferença de parser de URL** (por exemplo `\@` entre o `urlsplit` e o urllib3): não testei e não incluí. Ainda assim, esse vetor depende de código do próprio dono.

## Não verificável nesta auditoria

- Se o front (ainda não escrito em `apps/MoBaile`) chama o `project.doctor` automaticamente ao abrir o projeto. Isso muda a probabilidade do SEC-B1-01, não sua existência.
- Se o Appium-Python-Client ou o Selenium do projeto imprimem `Authorization` ou a URL com credencial no nível de log que o dono usa (SEC-B1-03, item 3).
- O efeito de `DYLD_INSERT_LIBRARIES` no Python escolhido. Não testei.
- O comportamento do PyCharm em modo de segurança, usado como comparação no SEC-B1-01.

## Decisões pendentes do humano

1. **SEC-B1-01:** o doctor fica atrás da confiança (recomendado), ou o diálogo de confiança passa a aparecer ao abrir o projeto? Assumi que o doctor pode rodar antes do Rodar, como o contrato descreve, e por isso a severidade é Alta.
2. **SEC-B1-02:** o `run.start` deve recusar hub "desconhecido" (dinâmico ou config não encontrada), com liberação explícita por execução? Assumi que sim, porque o estudo só aceita o que o código do dono faz por conta própria, e não um erro da análise estática.

## Como reproduzir

```bash
SC=<scratchpad>/sec
mkdir -p "$SC/head" && git -C <repo> archive f279bb9 engine | tar -x -C "$SC/head"
cd "$SC/poc" && <repo>/.venv/bin/python -I -m pytest -q -p no:cacheprovider test_poc_b1.py
# esperado: 24 passed (cada teste passando = comportamento do achado presente)
```

Instruções dirigidas ao assistente encontradas no código ou nos documentos lidos: nenhuma.

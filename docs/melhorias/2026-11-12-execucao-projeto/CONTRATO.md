# B1 — Rodar o projeto de automação do dono dentro do Mo baile (3.23.0)

Origem: estudo [docs/research/execucao-projeto-externo-pycharm.md](../../research/execucao-projeto-externo-pycharm.md),
Opção B, fase B1 (= Opção A), escolhida pelo dono em 12/11/2026.

## O que o dono vê ao fim da B1

1. Uma área nova **Execução** na barra lateral (Workspace, depois de Relatório, ⌘6;
   o Ambiente continua em ⌘5). Funciona sem aparelho para abrir e ler o projeto.
2. **Abrir projeto…** (NSOpenPanel de pasta) e uma lista de projetos já abertos.
3. O `main` resumido, sem executar nada:
   - arquivo de entrada e função (`main_sem_args` ou o que o `if __name__ == "__main__"` chama);
   - config **ativa** (`init(config_X)` não comentado) e as **alternativas comentadas**;
   - cada config com plataforma, `udid`/`deviceName`, `app`/`appPackage`, host do hub e o selo
     **Local** ou **Nuvem (bloqueada)**; chaves sensíveis aparecem só pelo nome;
   - suítes chamadas, em ordem, com cada `executar(squad, feature)` → feature encontrada ou
     "não achei", título da feature e nomes dos cenários.
4. **Doctor** com uma linha por checagem (ok / atenção / falha / pulada), mensagem e dica.
5. **Rodar** / **Parar**: console ao vivo (teto de linhas), aparelho alvo, vídeo da tela
   gravado junto; no fim, resultado **Passou / Falhou / Indeterminado** com contagens do
   resumo do behave, e botões **Abrir pasta da execução** e **Abrir vídeo**.
6. Na primeira execução de um projeto, o diálogo **Confiar neste projeto?** com interpretador,
   arquivo de entrada e pasta de trabalho.

Fora da B1 (vai para B2–B4): árvore de steps ao vivo (shim), capítulos no vídeo, print do
step que falhou, relatório HTML da execução, `junit.xml`, escolher config/suíte, liberar nuvem.

## Motor

### Módulos novos

- `services/projects.py` — registro de projetos autorizados e análise estática.
- `services/project_doctor.py` — checagens de pré-requisitos.
- `services/project_run.py` — execução do `main` (subprocesso), resumo, vídeo, pasta da execução.
- Reaproveitar: `security/files.validate_input_dir`, `security/redaction._is_sensitive_key` e
  `redact_url`, `services/setup.py` (versões de Appium e drivers, `_distribution_version`),
  `adapters/adb.py`, `adapters/appium.py` (`delete_session`), `adapters/screen_recorder.py`
  (simctl), `adapters/scrcpy.py` (só o localizador do binário; o comando de gravação é novo),
  máscara de `FlowExecution` (`services/flows.py`).

### Registro de projetos

- Arquivo local `projetos.json` no mesmo diretório de dados onde o motor já guarda
  `recentes.json` (`services/home.py`), gravação atômica (`security.paths.write_file_atomic`).
- Item: `{id, root, name, entry, trusted, opened_at}`. `id` = sha1 curto do caminho real.
- **Nunca grava nada na pasta do projeto.** Leitura só de texto (`.py`, `.feature`, `.ini`,
  `.cfg`, `.toml`, `.txt`, `.xml` dentro de `.idea`), sem seguir symlink, até 1 MB por arquivo,
  profundidade e número de arquivos limitados. Nunca abrir `.env*`, `*.pem`, `*.p12`,
  keystores, `local.properties`, `google-services.json`; nunca descer em `.venv`, `venv`,
  `.git`, `node_modules`, `__pycache__` para conteúdo.
- As travas SEC-5 do `workspace.py` **não mudam**.

### Análise estática (`project.inspect`)

- `ast.parse` no processo do motor (nunca importar o código do dono); `tokenize` para os
  `# init(...)` comentados. `SyntaxError`, `RecursionError` e arquivo grande viram `problems`.
- Entrada: `entry` do registro ou, por padrão, o primeiro de `main.py`, `run.py`, `__main__.py`
  na raiz; senão o `.py` da raiz (1 nível) que define `main_sem_args` ou tem `if __name__ == "__main__"`.
- Configs: seguir `from X import ...` / `import X` até arquivo do projeto e achar atribuições
  `config_* = {...}` / `dict(...)`. Valores literais só das chaves `platformName`,
  `automationName`, `udid`, `deviceName`, `platformVersion`, `app`, `appPackage`,
  `appActivity`, `bundleId` (e variantes com prefixo `appium:`), e o **host:porta** de qualquer
  URL de hub. Resto: só o nome da chave. Valor não literal → `"dinâmico"`.
- `cloud = true` quando o host do hub não é loopback, ou o nome da config/host contém
  `kobiton` (sem diferenciar caixa).
- Features: resolver `feature=` contra `features/`, `<squad>/`, `<squad>/features/` e a raiz;
  ler `Feature:`/`Funcionalidade:`, `Scenario:`/`Cenário:`/`Cenario:`/`Scenario Outline:`/
  `Esquema do Cenário:` como texto.
- Interpretador: (1) `.idea/runConfigurations/*.xml` e `RunManager` de `.idea/workspace.xml`
  (`SDK_HOME`, `WORKING_DIRECTORY`, `SCRIPT_NAME`, nomes das `envs`); (2) `.venv/` ou `venv/` com
  `pyvenv.cfg`; (3) nenhum → `null` e o doctor avisa. Os **valores** das `envs` só vão para o
  ambiente do filho; nunca para RPC, log ou disco.

### Doctor (`project.doctor`, com progresso)

Checagens (id estável): `interpreter`, `packages` (behave, pytest-bdd, Appium-Python-Client,
selenium — por `<python> -c` com `importlib.metadata`), `requirements` (requirements.txt ×
instalado, sem instalar), `pip_check`, `appium` (instalado, versão, drivers), `appium_port`
(alguém ouve no host:porta da config ativa? é o Appium do Mo baile?), `device` (aparelho da
config conectado; `platformVersion` × aparelho), `app` (caminho existe ou `appPackage`
instalado, só leitura), `uiautomation` (instrumentação de outro dono ativa), `cloud` (config
ativa na nuvem → falha), `features` (todas resolvidas). Nada instala, apaga ou reinicia.

### Execução (`run.*`)

- `run.start {project_id, device_id?, record_video=true, trusted?}`:
  - recusa se o projeto não é confiável e `trusted != true` (erro com código próprio que o front
    trata abrindo o diálogo); com `trusted: true`, marca o projeto como confiável;
  - recusa config ativa na nuvem (`cloud`) com mensagem explícita;
  - recusa se já houver execução, `flow.run` ou `flow.maestro_run` rodando;
  - antes de começar: fecha a sessão Appium do Mo baile para aquele aparelho e para a escuta
    passiva (o servidor Appium do Mo baile pode continuar de pé);
  - subprocesso `[interpretador, entry]`, `cwd` = pasta de trabalho, `stdin=DEVNULL`,
    `start_new_session=True`, env = ambiente do motor + `envs` da run configuration +
    `PYTHONUNBUFFERED=1`; máscara dos valores literais sensíveis achados nas configs;
  - vídeo: Android → `scrcpy -s <serial> --no-playback --no-window --no-audio --record=<arquivo>`
    (se o scrcpy não existir: `adb screenrecord` com o limite atual e aviso); simulador iOS →
    `simctl recordVideo --codec h264`; iPhone físico → sem vídeo, com aviso;
  - pasta da execução: `~/Documents/Mo baile/Execuções/<projeto>/<AAAAMMDD-HHMMSS>/` com
    `console.log`, `video.mp4` e `resumo.json`.
- `run.stop` — SIGINT no grupo, depois SIGTERM, depois SIGKILL (prazos curtos); para o vídeo
  com SIGINT para o MP4 fechar.
- `run.status` — estado atual.
- Notificações: `run.log {run_id, line}`, `run.finished {run_id, status, counts, exit_code,
  folder, video?, message}`.
- `status`: `passed` / `failed` / `indeterminate` / `cancelled`, lido do resumo do behave no
  stdout (`N features passed, M failed…`, `scenarios`, `steps`). **O código de saída não decide**
  (o `main` engole exceção com `print(e)`); sem resumo → `indeterminate` com a última linha de
  erro do console.
- **Trava do aparelho** durante a execução: `hierarchy.dump`, `passive.start`, `flow.run`,
  `flow.maestro_run`, `codegen.record`, toque/tecla repassados e `recording.start` avulso
  respondem erro claro ("o aparelho está rodando o projeto X"). O espelho por `screencap` segue.

### RPCs novas

`project.open {path}`, `project.list`, `project.forget {project_id}`,
`project.inspect {project_id}`, `project.doctor {project_id, device_id?}` (progresso),
`run.start`, `run.stop`, `run.status`; notificações `run.log` e `run.finished`.
Entram em `rpc/contract.py`, `docs/PROTOCOLO_RPC.md` e nas fixtures (`make fixtures`).

## Front (SwiftUI)

- `WorkspaceTab.execution` como **último** caso (⌘6), `needsDevice = false`, ícone e cor do DS.
- `Views/Execution/`: cabeçalho (projeto atual, Abrir projeto…, recentes, Esquecer), coluna
  Projeto (entrada, configs com selos, suítes → features → cenários), Doctor (lista + Rodar de
  novo), Console (teto de 5 000 linhas, rolagem automática pausável) e barra Rodar/Parar com
  aparelho alvo e "Gravar vídeo". Layout com `AdaptivePair` para monitor pequeno.
- Diálogo de confiança, banner de resultado, Abrir pasta / Abrir vídeo (`NSWorkspace`).
- DTOs em `Engine/EngineDTO+Execution.swift`; chamadas e notificações em `EngineSession`.

## Critérios de aceite da B1

1. Projeto de exemplo versionado (`engine/tests/fixtures/projeto_exemplo_behave/`, no formato do
   `main` do dono, com config local Android, iOS e uma Kobiton com valores falsos) é lido com
   config ativa, alternativas comentadas, suítes, features e cenários corretos.
2. Nenhum arquivo da pasta do projeto muda (hash antes e depois, em teste).
3. Config Kobiton ativa → `run.start` recusa; valores sensíveis nunca aparecem em RPC, log ou disco.
4. Rodar o exemplo com behave 1.2.6 real (sem aparelho, steps que só imprimem) mostra o console ao
   vivo e termina `passed`; um cenário que falha termina `failed`; `init` que lança antes de
   qualquer cenário termina `indeterminate`.
5. `run.stop` encerra o processo **e os netos**.
6. Durante a execução, `hierarchy.dump`/`flow.run`/`passive.start` recusam com mensagem clara.
7. Com o emulador ligado, o vídeo sai em `video.mp4` tocável.
8. `make check`, `make test-swift` verdes; `make update-native` + `verify-native` OK.

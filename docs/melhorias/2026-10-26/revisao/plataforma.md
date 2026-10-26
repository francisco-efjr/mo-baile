# Plataforma desktop macOS: revisão da rodada de 26/10/2026 (fase 2, especialista `plataforma`)

Data: 2026-10-26 · Status: RASCUNHO · Versão do app: 3.11.0, HEAD `a74407c`, branch `melhoria/2026-10-26-rodada3`
Método: leitura estática. Nada foi executado, compilado, assinado, instalado ou publicado. Critérios do `release-readiness-auditor` e das skills `playbook`, `desktop-release-checklist` e `dx-audit` (cli-desktop-tooling), com apoio do `playbook` de mobile-apps para SwiftUI.
Limites desta leitura:

- Só havia `Read` e `Write`. Sem `Grep`, `Glob` e `Bash`, não consegui varrer o repositório inteiro. Quando afirmo que algo **não existe no código** (ex.: `UserNotifications`, `UndoManager`, `TipKit`, `os.Logger`), o rótulo é **Inferido**: li os arquivos citados e os documentos do backlog, não o repositório todo. O primeiro passo de cada implementação é rodar `grep -rn` por esses nomes em `apps/MoBaile/Sources`.
- Os arquivos lidos para esta revisão: `tools/package_macos_app.sh`, `tools/verify_native_app.sh`, `tools/setup/instalar-mac.sh`, `tools/create_local_signing_identity.sh`, `Makefile`, `.github/workflows/{ci,release}.yml`, `docs/RELEASE.md`, `docs/INSTALACAO.md`, `README.md`, e no front `Engine/EngineClient.swift`, `Engine/EngineLocator.swift`, `Engine/EngineError.swift`, `Engine/EngineSession.swift` (linhas 1-700 e 700-1760), `App/AppDelegate.swift`, `App/AppState.swift`, `App/SetupInstaller.swift`, `Theme/ThemeManager.swift`, `Views/MainWindow/ContentView.swift`, `Views/Environment/EnvironmentView.swift`, `Package.swift`; no motor `rpc/server.py` (fim do arquivo), `mobaile/__init__.py`, `mobaile/_site.py`, `pyproject.toml`.
- Revisão feita pelo mesmo modelo que costuma escrever este código: é autoavaliação, não validação independente.
- Fatos de comportamento da Apple e do Python citados abaixo vêm de conhecimento estável e não foram reconferidos na fonte nesta sessão (sem acesso à rede). Cada um leva a URL para reconferir.

## Veredito de plataforma: PRONTO COM RESSALVAS (para uso local do dono); NÃO PRONTO (para distribuir a terceiros)

O caminho de empacotamento local é maduro: staging, troca atômica com backup, `swift test` antes, recusa com o app aberto, commit gravado no `Info.plist`, `verify-native` com três provas. Para distribuir a terceiros falta o que o backlog já sabe (A1: Python embutido, Developer ID, notarização). O achado novo mais importante desta leitura é **PLAT-2**: o motor, ao rodar, tende a escrever `__pycache__` dentro do bundle já assinado.

---

## Propostas (até 5, em ordem de ganho por risco)

Legenda de corte: "cabe" = encaixa no teto da rodada (6 melhorias, cerca de 600 linhas de diff sem contar testes e docs). Somadas, PLAT-1 a PLAT-5 passam de pouco (cerca de 300 linhas), então o corte depende do que os outros papéis pedirem. Minha ordem de prioridade: PLAT-2, PLAT-1, PLAT-4, PLAT-3, PLAT-5.

### PLAT-2 · O motor não deve escrever dentro do bundle assinado (achado novo)

| Campo | Conteúdo |
|---|---|
| Origem | Novo. Toca A1 (assinatura e notarização futuras) |
| Problema | O front sobe o motor com `PYTHONPATH` apontando para `Contents/Resources/engine/src` e só define `PYTHONUNBUFFERED` (`EngineClient.swift:111-119`). Não há `PYTHONDONTWRITEBYTECODE` nem `PYTHONPYCACHEPREFIX`, e `EngineLocator.resolve()` cria a configuração sem `extraEnvironment` (`EngineLocator.swift:13-17`). O Python grava `.pyc` em `__pycache__` ao lado dos módulos. O script de empacotamento apaga esses diretórios antes de assinar (`package_macos_app.sh:165`), o que mostra que o autor sabe que eles aparecem; ao rodar, eles voltam, dentro de `Contents/Resources`, que está selado pela assinatura. O próprio `verify_native_app.sh` mostra o sintoma: o `diff -rq` ignora `__pycache__` (`:117-118`), e o handshake roda com `PYTHONPATH="$ENGINE_SRC"` direto no app instalado (`:150-151`), ou seja, o verify também grava no bundle depois de conferir a assinatura (`:140`). O mesmo vale para `alvo_verificar` em `instalar-mac.sh:204-211`, que roda `mobaile.services.setup` com o motor embutido. |
| Rótulo | Leitura do código: **Verificado** (as linhas acima). Efeito sobre `codesign --verify --deep --strict` (arquivo adicionado dentro do bundle selado invalida a verificação): **Inferido**, a testar. Gravação de `.pyc` por padrão: conhecimento estável do Python, reconferir em https://docs.python.org/3/using/cmdline.html#envvar-PYTHONPYCACHEPREFIX (não lido nesta sessão). Conferir também https://developer.apple.com/library/archive/technotes/tn2206/_index.html (não lido). |
| Consequência | Hoje: um `make verify-native` repetido depois de abrir o app tende a falhar na linha de assinatura, o que ensina o dono a desconfiar do alvo certo. Amanhã (A1): com Developer ID e notarização, o app deixa de passar em `codesign --verify` depois do primeiro uso, e um atualizador (Sparkle) ou uma verificação de integridade passam a recusar o bundle. |
| Melhoria | (1) `EngineClient.start()`: `environment["PYTHONPYCACHEPREFIX"]` apontando para `~/Library/Caches/Mo baile/pycache` (a mesma pasta-mãe do cache do OCR). Mantém o ganho de partida rápida e tira os `.pyc` do bundle. Extrair a montagem do ambiente para uma função estática pura (`EngineClient.environment(for:base:)`) para poder testar. (2) `verify_native_app.sh:150` e `instalar-mac.sh:210`: prefixar `PYTHONDONTWRITEBYTECODE=1`. (3) `verify_native_app.sh`: depois do handshake, falhar se aparecer `__pycache__` em `$ENGINE_SRC`. |
| Ganho | Para o dono: `verify-native` confiável a qualquer hora. Para o código: pré-requisito barato de A1. |
| Esforço, risco | **P** (cerca de 15 linhas de código, mais teste). Risco baixo: só muda onde o bytecode mora. Em desenvolvimento (`swift run`), o bytecode também vai para o cache, o que é neutro. |
| Contrato RPC | Não muda. Não é regra de negócio. |
| Critério de aceite | (a) Teste Swift novo em `EngineClientTests`: `environment(for:)` contém `PYTHONPYCACHEPREFIX` fora de `sourcePath`, preserva `PYTHONPATH` e `PYTHONUNBUFFERED`. Falha antes (a chave não existe) e passa depois. (b) Teste de shell em `qa/tests` (o harness já testa o verify com `VERIFY_PYTHON_CANDIDATES`): copiar `engine/src` para um temporário, rodar o handshake como o verify roda, `find -name __pycache__` vazio. (c) Manual, pelo dono: `make update-native`, abrir o app, encerrar com ⌘Q, `codesign --verify --deep --strict "/Applications/Mo baile (nativo).app"` deve sair 0 e `make verify-native` deve passar uma segunda vez. **Antes da mudança, esse passo (c) é o teste da hipótese**: se já passar hoje, rebaixar este item para endurecimento. |
| Corte | Cabe (cerca de 15 linhas). Exige `make update-native` (muda `apps/MoBaile`). |

### PLAT-1 · Log do motor em arquivo, `faulthandler` e ponte para o `os.Logger` (M10 + A7)

| Campo | Conteúdo |
|---|---|
| Origem | M10 e A7 do backlog, reconfirmados abertos hoje |
| Problema | `serve()` configura só `logging.basicConfig(stream=sys.stderr)` (`server.py:2334-2340`) e não há arquivo, rotação nem `faulthandler`. No front, o stderr do motor é repassado a `FileHandle.standardError` com o prefixo `[motor]` (`EngineClient.swift:162-171`), e o comentário acima dele diz "Vai para o Console do sistema", o que não é verdade: escrever no descritor 2 de um app aberto pelo Finder não chega ao Console (esse destino é do `os_log`). Falha extra: o tratador decodifica cada pedaço com `String(data:encoding:.utf8)` e descarta o pedaço inteiro se a fronteira cair no meio de um caractere multibyte (`:169`), e o prefixo vai só no começo do pedaço, não de cada linha. Quando o motor cai, o usuário vê só "O motor encerrou inesperadamente (codigo N)" (`EngineError.swift:37-38`) e a supervisão tenta de novo (`EngineSession.swift:441-509`), sem rastro para investigar. Pastas de log já existem em três grafias diferentes (`~/Library/Logs/MoBaile/cfnetwork-diagnostics.log`, `~/Library/Logs/mobaile-appium.log`, e a proposta do backlog `~/Library/Logs/Mo baile/`), segundo `docs/research/agent-device/02-analise-comparativa.md` (itens 10 e 13, linhas de commit antigo). O front não usa `os.Logger` (A7): nos arquivos que li não há `import os`. |
| Rótulo | Estado do motor e do repasse do stderr: **Verificado**. Ausência de `os.Logger` e de `faulthandler` no repositório inteiro: **Inferido** (o doc de 10/10 diz que o grep por `faulthandler` não devolveu nada; não repeti). Comportamento do descritor 2 num app aberto pelo Finder: conhecimento estável, reconferir em https://developer.apple.com/documentation/os/logger (não lido). |
| Melhoria | **Motor** (onde a regra mora): extrair de `serve()` uma `configure_logging(log_dir=None)` que mantém o stderr e acrescenta um `RotatingFileHandler` em `~/Library/Logs/Mo baile/engine.log` (5 MiB + 1 geração, pasta 0700, arquivo 0600, só biblioteca padrão, sem dependência nova para o Python do app) e liga `faulthandler.enable(file=...)` num `engine-fault.log` com o arquivo mantido aberto. `MOBAILE_LOG_DIR` sobrescreve a pasta (para teste). Filtro de `logging` que passa URLs por `redact_url` (já existe em `security/redaction.py`). **Front**: um `StderrForwarder` que acumula bytes até `\n`, decodifica por linha e encaminha para `Logger(subsystem: "com.qa.mobaile", category: "engine")` (o identificador do app é `com.qa.mobaile`, `package_macos_app.sh:184`, e não o `br.com.mobaile` que o backlog sugeriu). Mensagem de queda passa a terminar com "Detalhes em ~/Library/Logs/Mo baile/engine.log". Opcional e barato: item "Abrir Pasta de Logs" no menu Ajuda. `docs/SEGURANCA.md` ganha a linha de política (o log passa a guardar host, serial e pacote). |
| Ganho | Todo relato de "travou" passa a ter evidência; o dono deixa de depender de rodar o app pelo Terminal. Destrava o diagnóstico de A1. |
| Esforço, risco | **P** (cerca de 45 linhas Python e 50 Swift). Risco baixo: o arquivo é aditivo; o stdout continua exclusivo do protocolo. Risco de privacidade tratado pelo filtro e pela política. |
| Contrato RPC | Não muda. O `diagnostic_id` em `error.data` (proposta M3 do doc de 10/10) fica **fora** deste corte, por ser aditivo mas exigir `make fixtures` e `PROTOCOLO_RPC.md`. Não é regra de negócio. |
| Critério de aceite | Teste Python novo `engine/tests/unit/test_logging_setup.py`: com `MOBAILE_LOG_DIR` temporário, `configure_logging()` faz uma mensagem de `logger.info` chegar ao `engine.log`; pasta 0700 e arquivo 0600; com `max_bytes` pequeno, a rotação cria `engine.log.1`; `faulthandler.is_enabled()` é verdadeiro; nada é escrito no stdout (`capsys`); uma URL com `?access_token=...` sai redigida. Falha hoje (a função não existe). Teste Swift novo: `StderrForwarder` recebe "…ç" e "ão\n" em dois pedaços e entrega uma linha íntegra; falha com o código atual (o pedaço é descartado). Manual: abrir pelo Finder, provocar uma falha de motor, achar a linha em `engine.log`. |
| Corte | Cabe (cerca de 100 linhas). Exige `make update-native` e a linha em `SEGURANCA.md`. |

### PLAT-4 · Portão de release: rodar o `verify-native` no CI e testar o Python 3.14

| Campo | Conteúdo |
|---|---|
| Origem | Novo (toca A1 e M17) |
| Problema | O `release.yml` roda pytest e os fluxos de QA com o Python do runner (`:64-68`), empacota (`:95-99`), gera o zip e publica (`:101-112`, `:172-183`), mas nunca sobe o motor embutido do jeito que o app sobe (`python -S -m mobaile.rpc`). O handshake com `-S`, que foi a correção da 3.10.0 (Documentos), só roda no `verify-native` local. O `ci.yml` testa o motor em Linux, nos Pythons 3.10, 3.12 e 3.13 (`:60`), sem 3.14 e sem macOS no motor; o `front` roda `swift build` e `swift test` (`:129-132`). Uma regressão no empacotamento (arquivo do motor faltando, `_site` quebrado) chegaria ao zip publicado. |
| Rótulo | Estado dos workflows: **Verificado**. Que nenhum teste pytest cobre o `-S` ponta a ponta: **Inferido** (não vi a pasta de testes inteira). Que o dono usa Python 3.14: **Suposição** (o mock de `docs/design/home/README.md` cita "Python 3.14.0"). |
| Melhoria | No `release.yml`, depois de "Empacotar" e antes de "Zip e SHA-256": um passo `bash tools/verify_native_app.sh` com `DEST_DIR` e `MOBAILE_PYTHON="$(which python)"` (o verify aceita `MOBAILE_PYTHON` executável sem sonda, `verify_native_app.sh:57-59`). No `ci.yml`, incluir `"3.14"` na matriz do motor. |
| Ganho | O zip publicado passa pela mesma prova do app instalado. Pega a classe de defeito que já aconteceu. |
| Esforço, risco | **P** (cerca de 8 linhas de YAML). Risco: o verify exige `git rev-parse HEAD` igual ao commit gravado e árvore limpa para não avisar; no runner o checkout é limpo, mas **Suposição**: confirmar com *Run workflow* sem "publicar" (`docs/RELEASE.md:30-32`) antes de uma tag. |
| Contrato RPC | Não muda. Não é regra de negócio. |
| Critério de aceite | O workflow manual (`workflow_dispatch`, publicar desmarcado) termina verde com o passo novo. Prova de que o passo pega o defeito: num commit descartável, apagar `engine/src/mobaile/_site.py` do bundle de teste (ou renomear) e ver o passo falhar. Matriz com 3.14 verde, ou falha registrada como achado de compatibilidade. |
| Corte | Cabe (YAML apenas). Não toca o app instalado: não exige `update-native`. |

### PLAT-3 · Notificação de operação longa e selo no Dock (A3)

| Campo | Conteúdo |
|---|---|
| Origem | A3 do backlog (e item B4 antigo, "tempo decorrido"), reconfirmado aberto |
| Problema | Operações que passam de dezenas de segundos só atualizam a barra de status: `wda.start` (minutos na primeira vez, `EngineSession.swift:751-770`), `emulators.boot` (`:772-789`), `flow.finished` (`:1683-1690`), `report.audit` (`:1430-1461`). Quem troca de janela não fica sabendo que acabou. Nos arquivos que li não há `UserNotifications` nem `dockTile` (Inferido). |
| Rótulo | Pontos de gancho: **Verificado**. Ausência de `UserNotifications`: **Inferido**. Se a autorização funciona num app assinado com identidade local ou ad-hoc, montado por script: **Suposição** (reconferir em https://developer.apple.com/documentation/usernotifications/unusernotificationcenter). |
| Melhoria | Protocolo `OperationNotifier` com a implementação real em `UNUserNotificationCenter` e uma falsa para teste. Pede autorização só na primeira operação longa (contextual, nunca na abertura). Notifica só se o app **não** está ativo e a operação durou mais de cerca de 10 s: fim do WDA (sucesso ou falha), do boot do emulador, do fluxo (com resultado) e da auditoria (com o número de divergências). Selo no Dock (`NSApp.dockTile.badgeLabel`) com `needsAction` da auditoria até o app ficar ativo. Guarda obrigatória: `UNUserNotificationCenter.current()` falha em processo sem bundle de aplicativo (`swift run`, host do `swift test`), então a implementação real só é criada se `Bundle.main.bundleURL.pathExtension == "app"` (Inferido; comportamento conhecido, reconferir na documentação acima). Texto no padrão da voz do projeto: pt-BR, sem emoji, sem código. |
| Ganho | Quem espera compilar o WDA ou um fluxo longo pode trabalhar em outra janela. |
| Esforço, risco | **P** (cerca de 100 linhas Swift). Risco médio-baixo: pedido de permissão do sistema na primeira vez; precisa de aceite manual do dono porque não consigo exercitar a autorização. |
| Contrato RPC | Não muda. Não é regra de negócio (é apresentação); o "limiar de 10 s" fica no front, como constante. |
| Critério de aceite | Teste Swift com notificador falso: `flow.finished` com app inativo e operação longa gera 1 aviso com título e corpo esperados; com app ativo ou operação curta, nenhum; a implementação real nunca é instanciada sob `swift test`. Manual: rodar `wda.start` num simulador, trocar de app, ver o banner e o selo. |
| Corte | Cabe em linhas; é a de maior incerteza de plataforma. Exige `make update-native`. |

### PLAT-5 · O que o `verify-native` ainda não confere, e três ajustes baratos de empacotamento

| Campo | Conteúdo |
|---|---|
| Origem | Novo, tocando A1 |
| Problema | (a) O empacotamento copia `CHANGELOG.md` e `tools/setup/instalar-mac.sh` para o bundle (`package_macos_app.sh:168`, `:174`), mas o `verify_native_app.sh` só compara o motor com `engine/src` (`:117`). Se o script de instalação mudar sem reempacotar, o botão "Instalar no Terminal…" roda a versão antiga, e a lista de gatilhos do `AGENTS.md` ("`engine/src/`, `apps/MoBaile/` ou `assets/`") não cita `tools/setup/` nem `CHANGELOG.md`. (b) O tipo de assinatura não aparece em lugar nenhum do relatório: o package avisa ad-hoc (`:217-223`), o verify só diz "assinatura valida" (`:144`). A consequência é invisível: com ad-hoc, o macOS esquece permissões a cada build (`docs/RELEASE.md:57-65`); só a identidade "Mo baile Local" (criada uma vez por `create_local_signing_identity.sh`) as mantém. Não sei, por leitura, se a identidade existe nesta máquina. (c) O `Info.plist` tem `NSLocalNetworkUsageDescription` (`package_macos_app.sh:210-211`) mas não `NSDocumentsFolderUsageDescription`, embora o motor grave por padrão em `~/Documents/Mo baile` (Page Objects, relatórios, specs); o aviso de acesso aparece com o texto genérico do sistema. (d) `criar_venv` decide por `[ -x "$APP_VENV/bin/python3" ]` (`instalar-mac.sh:82`): um venv do Mo baile cujo Python-base do Homebrew foi removido tem o link quebrado, `-x` falha e o script tenta criar por cima de uma pasta quebrada. |
| Rótulo | (a) e (b): **Verificado** (linhas citadas). (c): **Inferido** (comportamento do TCC com a chave ausente, reconferir na documentação de privacidade da Apple, não lida). (d): **Suposição**: o venv de `python -m venv` aponta para o interpretador do Homebrew, e se `venv` sobre um link quebrado se recupera sozinho não foi testado. |
| Melhoria | (a) `verify_native_app.sh`: `cmp` do `Resources/setup/instalar-mac.sh` e do `Resources/CHANGELOG.md` com os do repositório; `AGENTS.md` e `docs/CONTEXTO_DO_PROJETO.md` passam a listar `tools/setup/` e `CHANGELOG.md` entre os gatilhos de `update-native`. (b) Verify imprime `codesign -dv` resumido: "assinatura: ad-hoc (o macOS vai pedir as permissões de novo a cada build)", "identidade local Mo baile Local" ou "Developer ID"; `REQUIRE_STABLE_SIGNATURE=1` faz o ad-hoc falhar (uso no `update-native` do dono, não no CI). (c) Acrescentar `NSDocumentsFolderUsageDescription` com uma frase em pt-BR dizendo para que o app grava ali. (d) `instalar-mac.sh`: se existir `$APP_VENV` mas o `-x` falhar, recriar com `--clear` e avisar. Em todos: sem mudança de contrato. |
| Ganho | Verify que diz toda a verdade, permissão que o macOS lembra e explica, instalador que se recupera. |
| Esforço, risco | **P** (cerca de 40 linhas de shell e plist). Risco baixo; (d) pede teste em máquina descartável. |
| Contrato RPC | Não muda. Não é regra de negócio. |
| Critério de aceite | `qa/tests` já cobre o verify com Python falso: acrescentar casos (script do bundle diferente do do repositório falha; ad-hoc com `REQUIRE_STABLE_SIGNATURE=1` falha). Manual: `plutil -p` mostra a chave nova; trocar o Python-base de um venv de teste e ver o script recriar. |
| Corte | Cabe. Exige `make update-native`. |

---

## Itens do backlog da minha área: situação no código de hoje

| ID | Situação | Evidência |
|---|---|---|
| **A1** Python embutido, Developer ID, notarização | **Aberto, G, fora do corte.** O texto do backlog está desatualizado em parte: desde a 3.10.0 existe o Python do Mo baile em `~/Library/Application Support/Mo baile/python`, a sonda por candidato (PY-1) e a mensagem acionável; mas a dependência de um Python **externo** continua, porque esse venv é criado a partir do Python do Homebrew (`instalar-mac.sh:71-94`, Inferido: o venv aponta para o interpretador-base). O release segue ad-hoc e sem notarização, com os passos comentados (`release.yml:71-91`, `:114-137`). A branch wip `worktree-agent-a803987a556e5938e` (PB7: `bundle_runtime.py`, `verify_bundle.sh`, entitlements) não foi integrada: `tools/bundle_runtime.py` não existe na árvore (Verificado, leitura de caminho). Notarização e conta Apple Developer são ações do dono; esta revisão não assina nem notariza | `EngineLocator.swift:26-53`, `RELEASE.md:77-106` |
| **A7** Log no Console.app | **Aberto**, absorvido por PLAT-1 | `EngineClient.swift:162-171` |
| **M10** Log do motor em arquivo | **Aberto**, é a PLAT-1 | `server.py:2334-2340` |
| **A3** Notificação e selo no Dock | **Aberto**, é a PLAT-3 | `EngineSession.swift:751-789`, `:1430-1461`, `:1683-1690` |
| **A2** Desfazer (⌘Z) | **Aberto, M, fora do corte.** Os textos de confirmação ainda dizem "Essa ação não pode ser desfeita" (`ContentView.swift:177-188`). Não dá para fazer só no front: o motor apaga de verdade, e uma "restauração" só no `AppState` divergiria do histórico do motor (`session.correlate`, `report.audit` com `source=session`), o que a regra de ouro proíbe. Precisa de `*.restore` no motor (aditivo) | `ContentView.swift:177-200` |
| **A4** Dicas (TipKit) | **Aberto**, P, sem evidência de dor medida. Decisão de UX: o estilo de popover do TipKit precisa casar com o Liquid Glass do design system; recomendo deixar com o especialista de interface | Inferido |
| **A5** Atalhos e linha de comando | **Não se sustenta como escrito.** O `AppIntent` depende de metadados que o Xcode gera no build; o app é um executável SwiftPM montado por script (`package_macos_app.sh:101-215`), sem projeto Xcode. Rótulo: **Inferido**, reconferir em https://developer.apple.com/documentation/appintents (não lido). Reescrever como "CLI do motor com `--fail-on-divergence` (saída 2)", que é caso de uso do motor, não de plataforma; o App Intent só depois de existir um projeto Xcode | `Package.swift:10-22` |
| **R4** Concorrência estrita do Swift 6 | **Aberto, M, fora do corte.** O `Package.swift` segue em `swift-tools-version: 5.10` com `StrictConcurrency` como recurso futuro, ou seja, avisos (`Package.swift:1`, `:16-21`); o CI já exige o compilador 6.2 (`ci.yml:120-121`), então subir o modo de linguagem não depende de toolchain. Já há migração parcial (`nonisolated(unsafe)` guardado por lock em `EngineLocator.swift:239-240`). Exemplo concreto que vira erro no modo 6: `ThemeManager` é `class` sem isolamento e o `addObserver` captura `self` num fechamento `@Sendable` (`ThemeManager.swift:16`, `:44-56`; o rótulo `@Sendable` do SDK é Inferido). Não medi a contagem de avisos (sem build nesta fase). Plano em 3 passos: medir (`swift build -Xswiftc -strict-concurrency=complete` e registrar o número), zerar os avisos (`@MainActor` em `ThemeManager` e `AppState` exige testes `@MainActor`), só então trocar para `swift-tools-version: 6.0` | `Package.swift`, `ThemeManager.swift` |

## Já resolvidos ou que não se sustentam

- **"O app usa o Python do sistema e dependência nova quebra o app" (texto do A1 e do `status-2026-10-26.html`)**: parcialmente resolvido na 3.10.0 (Python do Mo baile, sonda, mensagem). Resta a dependência de Python externo (ver A1).
- **"Assinatura ad-hoc muda a cada build" como problema permanente**: já existe a saída local (`create_local_signing_identity.sh`, usada automaticamente pelo `package_macos_app.sh:39-48`). O que falta é torná-la visível (PLAT-5b).
- **Pedido de acesso à pasta Documentos a cada abertura**: resolvido na 3.10.0 (`python -S`, `mobaile/_site.py`, sonda com `-I -S`: `EngineLocator.swift:277-281`, `EngineClient.swift:105-109`). Segue válido que `.pyc` no bundle (PLAT-2) é outro efeito colateral do mesmo desenho.
- **"Instalar no Terminal…" por AppleScript**: não é o caso; o app escreve um `.command` e o abre, sem permissão de Automação (`SetupInstaller.swift:4-12`, `:68-80`). Está correto.
- **Troca atômica do bundle, backup e restauração em falha**: implementada e consistente (`package_macos_app.sh:104-128`, `:237-246`).
- **Workflow de release**: `permissions: {}` no topo, ações fixadas por SHA, `persist-credentials: false`, `timeout-minutes: 45` (`release.yml:21`, `:31`, `:37-39`). Nada a corrigir.
- **Notas de release dizem só "clique direito > Abrir"** (`release.yml:166-169`) enquanto o README já cita "Abrir Mesmo Assim" (`README.md:78-80`): inconsistência de texto, sem risco; alinhar quando se mexer no workflow (PLAT-4). Reconferir o comportamento do Gatekeeper nas versões novas em https://support.apple.com/pt-br/guide/mac-help/mh40616/mac (não lido).

## Achados fora da minha área (para o orquestrador repassar)

- **M4** continua aberto: a regex `passo\s+(\d+)` (`EngineSession.swift:1738-1741`) só casa em falha; é o item de fluxo/produto.
- **M8**: `analytics.event` entra sem teto no front (`EngineSession.swift:1714-1716`); só `proxy.event` chama `trimTraffic()` (`:1709-1713`), embora `trimTraffic` já limite os dois (`:1725-1733`). Correção de uma linha, de fluidez.
- **Documentação × código**: `CONTEXTO_DO_PROJETO.md` e `ARQUITETURA.md` dizem "a interface nunca faz polling", mas `startWatchingDaemons` chama `engine.info` e `wda.status` a cada 5 s (`EngineSession.swift:560-591`). Ajustar o texto ou mover para notificação.
- **Voz pt-BR**: `EngineError` perdeu os acentos nas mensagens ao usuário ("nao esta em execucao", "codigo", `EngineError.swift:34-38`), contra a regra de voz do design system.
- **README**: a tabela de requisitos manda `python3 -m pip install Pillow requests` (`README.md:46`) e dois parágrafos depois explica que esse caminho falha com o Python do Homebrew (`:56-58`). É o primeiro passo de quem chega; apontar já para "Instalar no Terminal…".
- **Registro do que o motor muda no aparelho (S3)**: o motor roda como filho; se o app for morto com SIGKILL, o desmonte de proxy não acontece. É segurança, não plataforma.

## Ações do usuário (nenhuma executada por mim)

Não há assinatura, notarização, publicação ou aceite de termos nesta fase. Os passos que dependem do dono:

1. Conferir se a identidade de assinatura local existe: `security find-identity -v -p codesigning` (o resultado decide a prioridade de PLAT-5b). A criação, se faltar, é `bash tools/create_local_signing_identity.sh`, que pede a senha do macOS.
2. Testar a hipótese de PLAT-2 antes de implementar: abrir o app, encerrar com ⌘Q, rodar `codesign --verify --deep --strict "/Applications/Mo baile (nativo).app"` e `make verify-native`. Se passar sem erro, rebaixar PLAT-2.
3. Ao implementar qualquer item que muda `apps/MoBaile/` ou o motor: encerrar o app com ⌘Q (eu não encerro o processo) e rodar `make update-native`, como manda o `AGENTS.md`. Para PLAT-5, acrescentar `tools/setup/` e `CHANGELOG.md` como gatilhos no próprio `AGENTS.md`.
4. Notarização e Developer ID (A1): continuam decisão e ação do dono (conta Apple Developer, secrets do repositório, `docs/RELEASE.md:82-106`). A sintaxe de `notarytool`, `stapler` e `security` nos passos comentados do `release.yml` **não foi verificada**: conferir com `xcrun notarytool --help` e `xcrun stapler --help` antes de ligar. Ficha de ação externa só será preparada quando o dono decidir ligar a notarização.

## Decisões pendentes do humano (com a opção assumida)

- Nome da pasta de logs do motor: assumi `~/Library/Logs/Mo baile/` (com espaço, como o resto de `Application Support/Mo baile`). As pastas antigas (`MoBaile`, `mobaile-appium.log`) ficam como estão, sem migração.
- Política de log: o `engine.log` guarda host, serial e pacote; assumi aceitável localmente com URL redigida e uma linha em `SEGURANCA.md`. Se o dono preferir nenhum log em disco, PLAT-1 vira só `faulthandler` mais `os.Logger`.
- Notificações (PLAT-3): assumi autorização pedida só na primeira operação longa.
- R4: assumi "medir primeiro" antes de decidir o esforço.

## Não verificável nesta sessão

- Se o app instalado hoje está assinado com "Mo baile Local" ou ad-hoc; se `codesign --verify` já falha depois do primeiro uso; se a autorização de notificação funciona com a assinatura atual; número real de avisos do modo estrito de concorrência; comportamento em Intel (o app é montado com o binário da máquina de build); fluxo de instalação na primeira abertura em máquina limpa.
- Linux e Windows: não aplicável ao app nativo (o Tk no Windows está congelado, ADR 0005).

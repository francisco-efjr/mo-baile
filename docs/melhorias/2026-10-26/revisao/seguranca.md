# Segurança e privacidade: propostas da rodada de 26/10/2026

Status: completo para o escopo abaixo, com lacunas declaradas   Documento: rascunho
Papel: `seguranca` (fase 2, somente leitura)   Modo: sem interação   Plataforma: macOS (SwiftUI + motor Python), alvos Android e iOS
Alvo: branch `melhoria/2026-10-26-rodada3`, HEAD `a74407c`, versão 3.11.0   Base: código de hoje (não há diff; é revisão de sistema)

Método: leitura de código com `Read`. Nesta sessão `Grep` e `Glob` não estavam disponíveis e `Bash` era proibido, então a busca foi por arquivo conhecido, não por varredura do repositório. Nada foi executado: nenhum teste, scanner, `make` ou processo. Onde escrevo "Verificado" é leitura do trecho exato em `arquivo:linha`; onde escrevo "Inferido" depende de comportamento de terceiro (Appium, macOS) ou de código que não li.

## 1. Escopo e modelo de ameaças curto

Ativos: credenciais e dados pessoais do app sob teste (token, cookie, CPF, senha digitada, PII em eventos de analytics), estado do aparelho do QA (proxy global, propriedades do sistema), o Mac do QA (processos locais, arquivos).

Atores: (a) quem está na mesma rede Wi-Fi; (b) outro processo ou usuário do mesmo Mac; (c) o app sob teste e o servidor dele, que escrevem texto na tela, nos logs e nas respostas (entrada não confiável); (d) o próprio QA, que compartilha prints, relatórios e logs com o time.

Fronteiras e fluxos relevantes:

| Id | Fluxo | Dado | Fronteira cruzada |
|---|---|---|---|
| F1 | app Mo baile -> motor, stdin/stdout | JSON-RPC, texto digitado | nenhuma (processo filho, sem porta) |
| F2 | motor -> Appium (porta 4723) -> aparelho/simulador | sessão WebDriver, hierarquia | Mac -> rede local (ver SEG-1) |
| F3 | iPhone -> `os_trace_relay` -> motor -> arquivo de log bruto | blocos do CFNetwork | aparelho -> disco do Mac (ver SEG-2) |
| F4 | motor -> script do runner (arquivo) -> adb/WDA | passos gravados, texto digitado | motor -> disco -> processo filho (ver SEG-3) |
| F5 | motor -> adb `settings put` / `setprop` | proxy global, debug do Firebase | Mac -> estado persistente do aparelho (ver SEG-5) |
| F6 | motor -> HTML/MD/TSV exportados | valores do log, prints da spec | Mac -> mãos do time (e-mail, PR, Jira) |
| F7 | tela do app sob teste -> hierarquia -> Page Object / flow Maestro | texto da UI | conteúdo de terceiro -> código gerado |

STRIDE em uma linha por fluxo que importa: F2 (Elevation, Information disclosure: serviço de automação sem autenticação alcançável pela rede); F3 e F4 (Information disclosure em repouso); F5 (Denial of service contra o aparelho do QA, Tampering de configuração); F6 (Information disclosure ao compartilhar; XSS no HTML foi avaliado e está mitigado); F7 (Tampering/injeção em comentário YAML, achado menor m1). Sem ameaça nova em F1: não há porta TCP no motor.

Suposições: o Mo baile roda como um usuário de macOS em máquina pessoal ou de trabalho, em Wi-Fi que o QA não controla (escritório, café). O front Swift é confiável e é o único cliente do stdio.

## 2. Resumo das propostas

| ID | Origem | Tema | Severidade | Esforço | Linhas (sem teste) | Contrato RPC | Regra de negócio | No corte |
|---|---|---|---|---|---|---|---|---|
| SEG-1 | novo | Appium sobe em todas as interfaces e com log aberto | Alta (se Inferido confirmar) | P | ~25 | não | não | sim |
| SEG-2 | S1 (resíduo) | Log bruto do CFNetwork ainda grava `Set-Cookie` e depende de `MOBAILE_REDACT` | Média | P | ~45 | não | não | sim |
| SEG-3 | S2 + PB1 (motor) | Texto digitado: script em disco, log do adb e mensagem do Maestro | Média | P | ~75 | não | não | sim |
| SEG-4 | M13 (reformulado) | Redação por token: chaves compostas e JWT/Bearer em qualquer valor | Média | P a M | ~80 | não | sim (muda o que a tela e a exportação mostram) | se sobrar teto |
| SEG-5 | S3 (reduzido) | Registro durável do que o motor muda no aparelho | Média | M | ~200 | aditivo opcional | sim (restauração automática) | não |

Sugestão para o teto de 6 melhorias e ~600 linhas da rodada: levar SEG-1, SEG-2 e SEG-3 (cerca de 145 linhas, as três com teste que falha antes e passa depois). SEG-4 é a próxima. SEG-5 fica para outra rodada porque precisa de decisão do dono (ver seção 6).

---

## 3. Propostas

### SEG-1. Appium escuta só em 127.0.0.1 e grava log privado (origem: novo)

- Categoria: A02 Security Misconfiguration (e A01/API, exposição de serviço de gestão). Severidade: Alta se a premissa Inferida valer. Confiança: Média (Verificado no código do Mo baile; Inferido no padrão do Appium). Evidência: estático suportado (não executado por mim).
- Problema, Verificado: `adapters/appium.py:134-140` sobe `[binary, "--log-timestamp", "--local-timezone"]` sem `--address` nem `--port`. O motor só se refere ao servidor por `http://127.0.0.1:4723` (`config.py:80`), o que dá a falsa impressão de loopback.
- Inferido: o Appium 2 escuta por padrão em todas as interfaces (`0.0.0.0`) e não tem autenticação. Com o servidor no ar, quem estiver na mesma rede alcança `:4723` e pode abrir uma sessão WebDriver contra o simulador ou aparelho ligado ao Mac (ler a árvore, capturar tela, tocar). As funções "inseguras" do Appium (shell, instalação) ficam desligadas por padrão, mas leitura de tela e toque já bastam para vazar o que o app mostra. Depende da versão instalada e de `~/.appiumrc`.
- Problema agravante, Verificado: o processo nasce com `start_new_session=True` (`appium.py:139`) e `stop_server` só encerra o que este motor iniciou, com o motor vivo (`appium.py:154-166`). Numa queda o Appium sobrevive, segue exposto e a próxima subida o trata como "do usuário" (`appium.py:115-116`). Isso contradiz `docs/ARQUITETURA.md:58-60`, que diz que o stdio elimina processos órfãos.
- Problema de log, Verificado: `appium.py:125-128` abre `~/Library/Logs/mobaile-appium.log` em modo `a` com o umask padrão (legível pelo grupo e por outros, 0644 típico), sem rotação e sem `--log-level`. Inferido: no nível padrão o Appium registra capabilities, comandos e trechos de resposta, inclusive `getPageSource`, ou seja, texto que estava na tela do app (PII).
- Cenário: 1. QA liga "Iniciar WDA" (ou o fallback de hierarquia do Android) num Wi-Fi compartilhado. 2. O motor sobe o Appium em `*:4723`. 3. Outra máquina na rede abre uma sessão e lê a tela do simulador do QA enquanto ele testa um app com dados reais.
- Melhoria: em `_start_server_locked`, derivar host e porta de `settings.appium_url` e passar `--address 127.0.0.1 --port <porta>` (host sempre loopback; se `APPIUM_URL` apontar para outro host, não subir). Abrir o log com `os.open(..., O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW, 0o600)`, pasta `~/Library/Logs` intacta, truncar ou girar quando passar de 5 MiB, e subir com `--log-level info` (decidir com o dono se aceita `warn`). Não mexer no ciclo de vida do processo nesta proposta (ver SEG-5).
- Ganho: fecha a única superfície de rede encontrada no motor e tira PII do log. Esforço P. Risco: baixo; quem usa Appium fora do Mac contra este servidor deixa de alcançá-lo (cenário que o app não suporta: `appium_url` é loopback).
- Contrato RPC: não muda. Regra de negócio: não.
- Aceite e verificação: teste unitário em `engine/tests/unit/test_appium.py` que faz patch em `subprocess.Popen` e `AppiumBridge.is_running`, chama `start_server()` e afirma que `argv` contém `--address 127.0.0.1` e a porta de `settings.appium_url`; outro teste, com `HOME` temporário, afirma `stat.S_IMODE(log) == 0o600` e que um log antigo 0644 vira 0600. Falha hoje nos dois. Verificação manual para o dono (não executada por mim): com o Appium iniciado pelo app, `lsof -nP -iTCP:4723 -sTCP:LISTEN` deve mostrar `127.0.0.1:4723`, e não `*:4723`.
- Observação fora do motor: o WebDriverAgent do simulador também tende a escutar em todas as interfaces (Não verificável aqui; é do projeto WDA). Vale uma linha em `docs/SEGURANCA.md`.

### SEG-2. Log bruto do CFNetwork: fechar o que o S1 deixou aberto (origem: S1, reconfirmado)

- Categoria: A09 Logging, A04. Severidade: Média. Confiança: Alta. Evidência: estático suportado, com o fixture do próprio teste como prova do formato.
- O que já está resolvido, Verificado: query e userinfo de toda URL do bloco passam por `redact_url` (`ios_cfnetwork.py:329`), `Name: value` sensível sai redigido (`:325-328`), pasta 0700 e arquivo 0600 com `fchmod` (`:433-449`), com testes em `engine/tests/unit/test_ios_cfnetwork.py:124-161`.
- Problema restante, Verificado: `_mask_block` só reconhece linhas que casam `_HEADER_LINE` (`ios_cfnetwork.py:71`, `^\s*([A-Za-z0-9][A-Za-z0-9\-]*):\s?(.*)$`), isto é, `Nome: valor`. Os headers de resposta chegam em formato de dicionário, `"Set-Cookie" = ( "valor" );` (o próprio fixture `RESPONSE`, `test_ios_cfnetwork.py:22-29`, mostra `"Content-Type" =     (`). A linha começa com aspas, não casa o regex, e passa inteira para o arquivo. Resultado: `Set-Cookie` de sessão, e qualquer `Authorization`/`X-Api-Key` em dicionário, ficam em claro em `~/Library/Logs/MoBaile/cfnetwork-diagnostics.log`. O evento que vai à tela está certo (`redact_headers` em `_event`, `:260`), só o arquivo vaza. O teste existente confere só o `Authorization` da requisição (`:54,60`).
- Segundo defeito, Verificado: `redact_url` e `redact_headers` retornam o valor cru quando `MOBAILE_REDACT=0` (`redaction.py:83-84,141-142`). Como `_mask_block` as usa, desligar a redação "só para depurar a tela" também grava tudo em disco (`ios_cfnetwork.py:325-329`). Isso é a pergunta 3 do estudo de 10/10.
- Terceiro, menor: `os.open` do log bruto sem `O_NOFOLLOW` (`ios_cfnetwork.py:445`).
- Cenário: 1. QA liga "iPhone em Debug" num app com login. 2. A resposta de login traz `Set-Cookie: sessao=...`. 3. O bloco bruto grava o cookie; um backup do Time Machine, um zip de `~/Library/Logs` mandado ao time em um bug ou outro processo do usuário lê a sessão de produção.
- Melhoria, em `adapters/ios_cfnetwork.py` e `security/redaction.py`:
  1. em `_mask_block`, acompanhar o estado "dentro de `Headers {`" e redigir pares `"Nome" = ( "valor" );` (inclusive o valor na linha seguinte, que `_headers_from_dict` já sabe juntar) quando o nome é sensível;
  2. varrer toda linha por valores com forma de segredo, independentemente da chave: `Bearer|Basic <token>` e JWT (`eyJ...\.eyJ...\.`), ver SEG-4;
  3. dar a `redact_headers`/`redact_url` um parâmetro `force=True` e usá-lo em `_mask_block`, para o arquivo em disco ignorar `MOBAILE_REDACT=0` (a variável continua valendo só para a tela);
  4. `O_NOFOLLOW` na abertura.
- Ganho: credencial de produção deixa de ficar em disco por rotina. Esforço P. Risco: baixo; só muda o arquivo de diagnóstico.
- Contrato RPC: não. Regra de negócio: não (o arquivo bruto é diagnóstico).
- Aceite: em `test_ios_cfnetwork.py`, (a) bloco de resposta com `"Set-Cookie" = ( "sessao=SENTINELA-COOKIE; Path=/" );` e `"X-Auth-Token" = ( "SENTINELA-TOKEN" );` e asserção de que nenhuma sentinela está em `raw[...]`; (b) mesmo bloco com `monkeypatch.setenv("MOBAILE_REDACT", "0")` e a mesma asserção; (c) `Authorization: Bearer eyJ...` solto numa linha qualquer. (a) e (b) falham hoje (Verificado pela leitura do regex; não executado).
- Pergunta ao dono (seção 6): o log bruto deve ser opt-in em vez de sempre ligado enquanto o App em Debug roda?

### SEG-3. Texto digitado fora do disco, do log e da mensagem final (origem: S2 + resíduo do PB1 no motor)

Três pontos da mesma classe (segredo do QA digitado num campo), todos no motor.

**3a. Script do runner leva o texto em claro e sobrevive a uma queda (S2).**
- Verificado: `generate_hidden_runner_script` embute `input_text` em `STEPS` (`flows.py:146,151,176`) e grava `flow_runner_<uuid>.py` em `$TMPDIR/mobaile-runtime-<uid>/` (`flows.py:421-423`, `security/paths.py:21-42`). O arquivo só é apagado no `finally` de `FlowExecution.run` (`flows.py:511-515`). SIGKILL, crash ou queda de energia deixam o arquivo, com a senha, até a limpeza do `$TMPDIR` pelo sistema. Está em 0600/0700, o que reduz o alcance, mas o dado persiste e entra em backup de usuário que tenha o `$TMPDIR` indexado. Nada limpa esses arquivos na subida.
- Melhoria: o runner lê `STEPS = json.load(sys.stdin)` e `FlowExecution.run` abre o filho com `stdin=PIPE`, escreve o JSON e fecha (hoje `stdin=DEVNULL`, `flows.py:472`; o comentário em `:471` existe para não herdar o stdin do motor, e `PIPE` próprio não herda). As chamadas `subprocess.run` dentro do script passam `stdin=subprocess.DEVNULL` explícito. Na subida (ou no primeiro `flow.run`) apagar `flow_runner_*.py` com mais de 1 h. O arquivo continua existindo, mas sem segredo.
- Limite residual, Verificado: `adb shell input text '<texto>'` expõe o texto no `argv` do processo `adb` no Mac durante a execução e no `ps` do aparelho. É inerente ao adb; registrar em `docs/SEGURANCA.md`.

**3b. O log do motor repete o texto digitado quando o `adb` demora.**
- Verificado: `adapters/adb.py:311-313` faz `logger.warning("Digitação recusada em %r: %s", device_id, exc)`. Para `subprocess.TimeoutExpired` (o `timeout=5` de `:309`), `str(exc)` é "Command '[...]' timed out after 5 seconds" com a lista de argumentos, ou seja, o `input text '<texto>'`. O mesmo risco já foi tratado no runner (`flows.py:388-390`, comentário "So o tipo"), mas não aqui. O destino é o stderr do motor hoje, e o futuro `engine.log` (M10) se for criado sem filtro.
- Melhoria: para `TimeoutExpired`, logar só `type(exc).__name__`; manter a mensagem para `InvalidInputError` e `ToolNotFoundError`, que não carregam o texto (`security/shell.py:96-104` Verificado).

**3c. A mensagem final do flow Maestro não é mascarada.**
- Verificado: `FlowRunner.log` mascara `Flow.secrets` (`maestro_flow.py:697-702`), mas `run()` monta `FlowResult(sucesso, mensagem, ...)` com a mensagem crua (`:735-736`), e `FlowThread.run` entrega `self.result.message` a `on_finished` (`:961-964`), que vira `flow.finished.message` (`rpc/server.py:1974-1979`). A mensagem de falha inclui `Selector.describe()` (`maestro_flow.py:98-113`, `:806,847`), que imprime o texto do seletor. Se o QA digitou `${SENHA}` ou um e-mail e depois fez `assertVisible` do mesmo valor, a falha manda o valor, sem máscara, para a interface.
- Melhoria: extrair `_mascarar(linha)` e aplicá-la também a `mensagem` e a `failed_step` antes de montar o `FlowResult`.

- Ganho: nenhum segredo digitado em disco após queda, em log ou na notificação final. Esforço P. Risco: baixo; a 3a é a mais delicada (mudar o canal de entrada do runner), por isso o teste abaixo.
- Contrato RPC: não. Regra de negócio: não.
- Aceite: (3a) estender `engine/tests/unit/test_flow_execucao.py` (adb falso e sentinela): durante e depois do `flow.run`, ler todos os arquivos sob `secure_runtime_dir()` e afirmar que a sentinela não aparece; teste de subida cria um `flow_runner_antigo.py` com `mtime` velho e confere que foi removido; (3b) `adb.type_text` com `_run_cmd` levantando `TimeoutExpired` e um handler de log capturando: a sentinela não está em nenhuma linha; (3c) flow `inputText: ${SENHA}` + `assertVisible: ${SENHA}` com `lookup_timeout_s` mínimo: `flow.finished.message` não contém o valor. Os três falham hoje.

**3d. Resíduo do PB1 fora do corte (decisão necessária).**
- Verificado no motor: `passive.text` envia o texto lido do campo (`rpc/server.py:1745`) e `codegen.steps` devolve `input_text` de todo passo (`domain/models.py:156`, `rpc/server.py:1996-1997`). `AutomationStep` não tem `sensitive` (`models.py:125-142`) e o parser não guarda o atributo `password` do Android nem distingue `SecureTextField` do iOS como sensível (`services/hierarchy.py:47-138`). Inferido: campo de senha vem mascarado pelo sistema (bolinhas), então o vazamento é de campos sensíveis que não são senha (CPF, cartão, OTP, e-mail).
- Proposta: o motor decide `sensitive` (classe `SecureTextField`, atributo `password`, ou `resource_id`/nome com os tokens do SEG-4) e, nesses passos, `to_dict()` e `passive.text` devolvem `input_text: null`, `input_length` e `sensitive: true`; o texto real fica só em memória para o `flow.run`. Mudança de contrato é aditiva (campos novos), mas muda o que o usuário vê (regra de negócio). O lado Swift (`StepsList` e o tratamento de `passive.text`) é Não verificável: não li o front. Esforço P no motor, mais um ajuste pequeno no front. Fica para depois de o dono decidir se quer ver o texto digitado em campos comuns.

### SEG-4. Redação por token, e por forma do valor (origem: M13, reformulado)

- Categoria: A09, A04. Severidade: Média. Confiança: Alta no defeito, Média na lista exata de nomes.
- O diagnóstico do backlog mudou. O item M13 diz "redação por substring erra (passage, monkey)". No código de hoje a comparação é por igualdade exata depois de normalizar `_` e `-` (`security/redaction.py:72-73`, com `_SENSITIVE_KEYS` em `:67`). O falso positivo sumiu, e entrou falso negativo: `new_password`, `confirmPassword`, `current_password`, `auth_token`, `sessionToken`, `userPassword`, `otp`, `jwt` e `passwd` não são redigidos em corpo JSON, form nem query (`redact_body`, `_redact_form`, `redact_url`, `redaction.py:96-153`). Em header, a lista `_SENSITIVE_HEADERS` (`:22-36`) é de nomes exatos e não cobre `x-amz-security-token`, `x-goog-api-key`, `x-xsrf-token`, `ocp-apim-subscription-key`, `x-auth`, nem os `X-<Marca>-Token` que apps de banco costumam criar. Todos os adapters (proxy, OkHttp, CFNetwork) passam por essas funções, então o buraco é comum.
- Também, Verificado: valor com forma de segredo em chave inocente (`{"data":"eyJ..."}`, `Bearer ...` num header com nome qualquer, JWT na query com nome livre) passa. E corpo que não é JSON nem form (XML/SOAP com `<password>`) não é tratado (`redaction.py:96-126`).
- Analytics, Verificado: `analytics_logcat.py` guarda `params` e `raw_log` sem nenhuma redação (`:581-590`, `:498-507`) e o dado vai à tela, ao JSON/TSV exportado e ao Relatório. Não recomendo redigir na captura: a auditoria compara valores (`services/report`), e PII em evento é justamente achado de QA. Ver decisão D3.
- Melhoria, em `security/redaction.py` (uma função, usada por todos):
  1. separar a chave em tokens (fronteira não alfanumérica e camelCase) e considerar sensível quando algum token está num conjunto curto (`password`, `passwd`, `pwd`, `senha`, `secret`, `token`, `cookie`, `jwt`, `bearer`, `otp`, `cvv`, `cvc`, `cpf`, `cnpj`, `pin`, `auth`, `authorization`, `signature`, `credential`) ou quando forma um par conhecido (`api key`, `access key`, `private key`, `card number`, `security code`, `session id`); `passage`, `monkey`, `keyboard`, `tokenizer`, `author` continuam livres porque são um token só e diferente;
  2. aplicar a mesma regra aos nomes de header e de campo de query;
  3. varrer valores por `Bearer|Basic <base64>` e por JWT (`eyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]*`) em corpo, URL e no log bruto (SEG-2);
  4. XML simples: redigir `<password>...</password>` para os mesmos tokens (opcional; cortar se estourar o teto).
- Ganho: reduz vazamento de credencial de login/troca de senha na tela, no HAR e no relatório. Esforço P a M. Risco: médio-baixo; mascarar demais atrapalha depuração, por isso o teste inclui falsos positivos.
- Contrato RPC: não. Regra de negócio: sim (muda o que aparece e o que se exporta). Documentar em `docs/SEGURANCA.md` (item 5).
- Aceite: tabela de 20 variações em `engine/tests/unit/test_security.py` (a lista do backlog): sensíveis (`new_password`, `confirmPassword`, `current_password`, `auth_token`, `refreshToken`, `X-Auth-Token`, `x-api-token`, `X-Goog-Api-Key`, `Ocp-Apim-Subscription-Key`, JWT em chave `data`) viram `«redigido»`; livres (`passage`, `monkey`, `keyboard`, `author`, `session_duration`) ficam. Falha hoje nas sensíveis.

### SEG-5. Registro durável do que o motor muda no aparelho (origem: S3, reduzido)

- Categoria: A10 Exceptional Conditions. Severidade: Média. Confiança: Alta no defeito residual. Evidência: estático suportado.
- O que já está resolvido, Verificado: o proxy é desfeito no aparelho em que foi ligado (`rpc/server.py:250-267,1140-1166,1227-1241`), o valor anterior de `http_proxy` e de `captive_portal_mode` é guardado e restaurado (`adapters/adb.py:388-397,442-461`), desmonte que falha é retentado quando o serial volta (`server.py:1168-1214`), o encerramento ordenado e o SIGTERM desfazem tudo (`server.py:2233-2279,2343-2357`), e o debug do Firebase é desligado no `stop` (`analytics_logcat.py:223-243,375`).
- O que continua aberto, Verificado: todo esse estado é memória do processo: `_proxy_previous` (`adb.py:48`), `_proxy_device`/`_proxy_pending` (`server.py:250-267`) e `_firebase_debug_on` (`analytics_logcat.py:180`). SIGKILL, crash do Python, força-sair do app ou queda de energia deixam o aparelho com `http_proxy=127.0.0.1:8082` apontando para porta morta (sem internet), `captive_portal_mode=0`, `adb reverse` ativo e `debug.firebase.analytics.app` apontando para o app do cliente (eventos de teste no DebugView/BigQuery dele). O valor original some junto com o processo.
- Efeito colateral, Verificado: sem registro, `proxy_stop` num motor novo cai no ramo "recuperação do front" (`server.py:1240-1241`), que chama `teardown_reverse_proxy` com `_proxy_previous` vazio; isso apaga `http_proxy` e `captive_portal_mode` em vez de restaurar (`adb.py:442-452,459-461`), o que desfaz também um proxy corporativo que o QA já tinha. O arquivo `/data/local/tmp/mobaile_dump_<pid>.xml` (`adb.py:44,255-283`) também pode ficar no aparelho com o texto da tela.
- Melhoria mínima: `security/storage.py` com escrita atômica 0600 (`mkstemp` + `fsync` + `os.replace`, como `home.py:121-133` já faz para `recentes.json`) e `services/device_state.py` com um arquivo por aparelho em `~/Library/Application Support/Mo baile/state/` (`schema`, `version: 1`, `owner {pid, start_time}`, entradas `{kind, key, previous, applied}`). Gravar antes de `settings put`/`setprop`. Na transição ausente -> presente do serial (já existe o gancho `_on_targets_listed`, `server.py:1189-1214`), restaurar se e só se o valor atual for igual a `applied` e nada estiver escutando em `127.0.0.1:<porta>` (a cerca); caso contrário manter e avisar. Notificação aditiva opcional `device.restored {device_id, entries}`.
- Ganho: um QA que perdeu o motor não fica com o celular sem rede nem com o Firebase de teste ligado. Esforço M (~200 linhas e testes com `AdbFalso`). Risco: médio, porque restaurar mexe em configuração de terceiros; a cerca é obrigatória.
- Contrato RPC: aditivo opcional (uma notificação). Regra de negócio: sim, restaurar automaticamente é decisão do dono (D4).
- Aceite: com `AdbFalso`, ligar o proxy, descartar o `EngineServer` sem `shutdown()`, subir outro e ver `http_proxy` e `captive_portal_mode` iguais ao original; a cerca não restaura valor alterado por terceiro; o registro tem modo 0600 e não contém texto digitado.
- Fora do corte.

---

## 4. Achados menores (sem proposta própria)

- **m1. Injeção no comentário do flow Maestro exportado** (VERIFY, Baixa a Média, confiança Média). `services/maestro_flow.py:1053-1054` escreve `# passo N: {rotulo}` com `rotulo = passo.element_name or passo.var_name` e só troca `\n` por espaço. O nome vem do texto do elemento na tela do app sob teste (`models.py:96-104`, atacável por conteúdo de terceiro, como um nome de contato ou mensagem). `\r`, U+0085, U+2028 e U+2029 são quebras de linha em YAML 1.1 (Inferido) e o parser do atributo preserva `&#13;` (Inferido). Cenário: 1. o QA grava um toque em um item cujo nome contém `CR - runScript: ...`. 2. `flow.maestro_export` salva o `.yaml`. 3. rodar esse arquivo no Maestro real (uso previsto pelo projeto) executa o comando injetado; o runner do Mo baile recusa `runScript` (`maestro_flow.py:59-67`), o Maestro não. Pergunta a resolver: o export com texto de elemento com CR chega ao arquivo? Correção de uma linha: `" ".join(rotulo.split())` (separa em qualquer espaço Unicode, inclusive esses) e limitar a 120 caracteres; teste de regressão com `"a\r- runScript: x"`. Seletores e `appId` já saem por `json.dumps` e estão seguros (`:989-991`).
- **m2. Ramo morto sem `O_NOFOLLOW`.** `flows.generate_hidden_runner_script(output_path=...)` abre com `os.open` sem `O_NOFOLLOW` e dá 0600 (`flows.py:414-419`). O estudo de 10/10 informa que não há chamador; não confirmei por falta de busca. Remover o ramo.
- **m3. `secure_runtime_dir` segue symlink e não confere o dono** (`security/paths.py:23-28`). No macOS `$TMPDIR` é por usuário, então o risco é baixo; ao criar `ensure_private_dir` (SEG-5) trocar por `lstat` + `getuid`.
- **m4. `flow.run` devolve o caminho do script** (`rpc/server.py:1877`). Sem segredo depois do SEG-3a; opcional remover do contrato.
- **m5. Erro interno devolve `traceback.format_exc(limit=3)` ao front** (`rpc/server.py:2132-2137`). A última linha é a mensagem da exceção, que em outro caminho pode repetir texto digitado (mesma classe do 3b). Higiene: passar por `redact_url` e cortar em 2 KiB. Entra junto com M10 se o `engine.log` sair.
- **m6. `recentes.json`** é gravado por `mkstemp` (0600, `home.py:126`), então o arquivo está certo; a pasta `Application Support/Mo baile` nasce com o umask padrão (`home.py:123`). Nada sensível dentro (título, subtítulo, caminho). Baixo; resolver junto com `ensure_private_dir`.
- **m7. Exportações** (`report.export`, `service.py:321-322`) saem com o umask padrão e podem conter valores de analytics e prints da spec. `~/Documents` é 0700 por padrão no macOS, então o risco é de compartilhamento, não de leitura local. Ver D3.

## 5. Backlog da minha área: resolvido ou que não se sustenta

- **S1 (log bruto do CFNetwork)**: resolvido em parte. Query/userinfo, `Name: value`, 0600/0700 e rotação estão no código (`ios_cfnetwork.py:317-331,433-449`, testes `test_ios_cfnetwork.py:124-161`). Falta `Set-Cookie` em dicionário e o acoplamento a `MOBAILE_REDACT=0` (SEG-2). O texto do backlog ("query com token ... em claro") está desatualizado na parte da query.
- **S2 (escrita atômica e passos em claro)**: aberto na parte que importa para privacidade (SEG-3a). A escrita atômica geral continua sem primitiva comum; `home.py:121-133` e `service.py:270-272` já fazem a sua. Não é segurança crítica; fica para quando `security/storage.py` nascer (SEG-5).
- **S3 (registro do que o motor muda no aparelho)**: mitigado em processo (proxy no aparelho certo, valor anterior restaurado, retentativa, Firebase desligado no `stop`: ver SEG-5), aberto na queda do processo.
- **M13 (redação por token e Analytics)**: aberto, mas o diagnóstico mudou: hoje é igualdade exata, não substring (SEG-4). Analytics sem redação confirmado; decisão do dono (D3).
- **PB1 (texto digitado em log)**: motor concluído (`flows.py:258-259,339-340`, `maestro_flow.py:145-147,825-828`), com teste de sentinela (`test_flow_execucao.py:90-105`). Resíduo em 3b, 3c e 3d.
- **COD-1 (fila de analytics sem limite)**: resolvido (`analytics_logcat.py:159-161`, `_enqueue` `:454-464`).
- **COD-2 (debug do Firebase ligado após `stop`)**: resolvido em processo (`analytics_logcat.py:223-243,375`); `log.tag.*` e `logcat -G 8M` não são restaurados (`:196-201`), baixo.
- **A4/WEB-1 (`web_app.py` executando upload)**: resolvido, arquivo removido (`RODADA_2026-10-05_PENDENCIAS.md:71`).
- **`.flow_runner.py` 0755 na raiz do projeto, injeção por serial, `input text`, XXE**: seguem resolvidos (`flows.py:129,171,421-423`, `security/shell.py:74-107`, `services/hierarchy.py:39`).
- **HTML exportado (CSP)**: sem achado. `html_report.py:371-374` define `default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src <sha256 dos 3 scripts>; base-uri 'none'; form-action 'none'`, o hash é calculado sobre os mesmos textos que são injetados (`:387,419,473`), todo texto da spec e do log passa por `html.escape(quote=True)` (`:90-91`), e `report.js` não usa `innerHTML` (`report.js:5`, lido inteiro: só `textContent`, `dataset` e `classList`). Sem rede possível.
- **Proxy como serviço local**: não é achado. Escuta em loopback, avisa fora dele, limita cabeçalho, corpo, conexões e túneis ociosos (`proxy.py:48-58,576-580`), e o erro ao cliente é genérico (`:427`).

## 6. Decisões pendentes do humano

- D1. SEG-1: pode o motor impor `--address 127.0.0.1` e `--log-level info` no Appium que ele mesmo sobe? E aceitar que `APPIUM_URL` fora de loopback faça o motor não subir servidor próprio?
- D2. SEG-2: o log bruto do CFNetwork deve ser opt-in (ou só em memória, com "Exportar diagnóstico") em vez de gravar sempre enquanto o App em Debug roda? A redação do arquivo passa a ignorar `MOBAILE_REDACT=0`?
- D3. Analytics e exportações: mascarar PII (e-mail, CPF, telefone) por chave na tela e nos arquivos exportados, ou manter os valores (a auditoria precisa deles) e só **apontar** PII como divergência? Sugestão: manter na captura, oferecer "Mascarar dados pessoais" ligado por padrão apenas nos arquivos que saem do Mac (HTML, Markdown, TSV, JSON).
- D4. SEG-5: restaurar automaticamente o aparelho na próxima subida quando a cerca confirmar, ou perguntar antes?
- D5. SEG-3d: mostrar o texto digitado em campos comuns na lista de passos, e mascarar só os sensíveis?

## 7. Exclusões aplicadas

Negação de serviço e esgotamento de recurso teórico (limites do proxy já existem); proxy que aceita `CONNECT` para qualquer host (é a função dele, em loopback; processo local do mesmo usuário já tem o mesmo alcance); hardening genérico sem cenário; corrida teórica; dependência desatualizada sem CVE conhecido; arquivos de teste e documentação como alvo; SSRF que só controla caminho; MD5 como checksum (não encontrado). Não valem como exclusão e foram tratados: serviço de gestão exposto (SEG-1), segredo em log e disco (SEG-2, SEG-3).

## 8. Cobertura

Lidos por inteiro: `adapters/ios_cfnetwork.py`, `adapters/proxy.py`, `adapters/android_okhttp_log.py`, `adapters/analytics_logcat.py`, `adapters/flow_devices.py`, `adapters/appium.py` (linhas 1-210), `adapters/adb.py` (linhas 1-480), `services/flows.py`, `services/maestro_flow.py`, `services/codegen.py`, `services/home.py`, `services/report/service.py`, `services/report/documents.py`, `services/report/html_report.py`, `services/report/html/report.js`, `security/redaction.py`, `security/paths.py`, `security/files.py`, `security/shell.py`, `security/__init__.py`, `config.py`, `rpc/server.py` (1-980, 1000-2357), `domain/models.py` (100-220), `services/hierarchy.py` (1-140), os testes `test_ios_cfnetwork.py`, `test_flow_execucao.py` (1-120), `test_security.py` (1-60), `test_appium.py` (1-80), `docs/SEGURANCA.md`, `docs/ARQUITETURA.md`, `docs/CONTEXTO_DO_PROJETO.md`, `docs/RODADA_2026-10-05_PENDENCIAS.md`, `docs/research/agent-device/02-analise-comparativa.md` (inteiro) e o array `B` do status de 26/10.

Não examinados, e por quê: todo o front Swift (sem `Grep`/`Glob` para achar os arquivos; os pontos do front são Não verificável); `ios_device_log.py`, `screen_recorder.py`, `vision_ocr.py`, `scrcpy.py`, `input_events.py`, `services/report/board.py`, `firebase_log.py`, `card_reader.py`, `rpc/contract.py`, `docs/PROTOCOLO_RPC.md`; scripts de empacotamento, assinatura e instalação (`tools/`, `Makefile`), CI (`.github/`), `tools/maestro_offline/` e o `motion.min.js` embutido (13.5.1, protegido por hash na CSP, procedência não conferida); manifestos e lockfiles Python/npm (cadeia de suprimentos, incluindo o Appium global por npm sem versão fixada); segredos no repositório e no histórico git (não procurei: sem `Grep` e sem `git log`). Nada foi executado: nenhum teste, scanner nem processo.

## 9. Limites da revisão

Revisão de leitura por modelo, do mesmo tipo do autor do código. Camada de defesa em profundidade, não validação externa; um humano decide o que entra. As proposições SEG-1 (padrão do Appium) e m1 (parser YAML e atributos XML) dependem de comportamento de terceiros que não consegui conferir; as verificações manuais de cada uma estão descritas, para o dono executar em ambiente próprio. Recomendado `finding-verifier` para SEG-1 antes de classificar como severidade Alta. Não há score de conformidade nem taxa de falso positivo neste documento. Nenhuma instrução dirigida a mim foi encontrada no material lido.

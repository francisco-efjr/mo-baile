# Auditoria da Rodada 1 (3.5.2) — 15/10/2026

Escopo: commits `efcc5f9..313fcf8` na branch `melhoria/2026-10-14-rodada1-comportamento`, o app instalado e os relatórios em `docs/melhorias/2026-10-14/`.
Método: releitura do diff pela sessão (com execução pontual do gerador de código) e um auditor independente (Opus) focado nos commits que a primeira revisão não viu (`5c85125`, `313fcf8`), no processo e nos testes. Ambos são do mesmo modelo que escreveu o código.

Resultado: **nada que invalide a entrega, mas 2 regressões reais, 1 corrida e uma lista de promessas que o código não cumpre inteiras.**

## Defeitos no código

| ID | Sev. | Onde | O que acontece | Como provei | Correção mínima |
|---|---|---|---|---|---|
| **A-1** | **Média** | `codegen.py` `is_input = var_name.startswith("CAMPO_")` (M7) | Regressão. Campos cujo prefixo não é `CAMPO` perderam a classificação por nome: `android.widget.AutoCompleteTextView` com id `campo_nome` → antes `input`, agora **`click`**; `android.view.View` id `campo_data` idem. `EditText`, `SearchView` e classes com "input" continuam certos. | **Verificado por execução** do gerador | `is_input` também por classe: `EDITTEXT`, `TEXTFIELD`, `SEARCH`, `AUTOCOMPLETE`; e teste com `AutoCompleteTextView`. |
| **A-2** | **Média** | `codegen.py:270` `@value=X or @label=X` vs. contagem `e.text == element.text` (REV-1) | No iOS o xpath casa **mais** elementos do que `matches` conta: botão A (label "Adicionar", sem value → text "Adicionar") e botão B (label "Adicionar", value "1" → text "1"). O xpath pega os dois, `matches=1`, `unique=True`, e o modo auto escolhe um localizador ambíguo. É o defeito que o M7 dizia corrigir, reintroduzido pela correção do REV-1. O teste do REV-1 só confere a string. | Verificado por leitura (`hierarchy.py:121` `text=value if value else label`) | Contar com o mesmo critério do xpath (value **ou** label). Hoje `UIElement` não guarda value e label separados: ou guardar os dois, ou gerar só `@label` quando o `text` veio do label. |
| **A-3** | Média | `server.py` `_retry_pending_proxy` × `shutdown()` (REV-3/4) | Duas chamadas seguidas a `teardown_reverse_proxy` no mesmo serial: a 1ª restaura `corp:3128` e faz `pop` do original; a 2ª não acha original e **apaga** o que acabou de restaurar. Acontece quando (a) uma retentativa está em voo no `shutdown`, que tira retrato de `_proxy_pending` antes; (b) um `proxy.start` entra entre a checagem `ainda_pendente` e o desmonte. | Verificado por leitura; janela estreita | Serializar por serial e reconferir pendência **dentro** de `_teardown_proxy_device` sob lock; `shutdown` espera (`join`) as retentativas antes do laço final. |
| **A-4** | Baixa | `devices.py:153` callback antes de `if self._stop_event.is_set()` | Varredura atrasada depois do `stop()` ainda dispara `on_targets_listed` → abre thread daemon de retentativa durante o encerramento (alimenta A-3) ou morre no meio dos `settings`. | Verificado por leitura | Checar `_stop_event` antes do callback; `_retry_pending_proxy` recusa se `_shutdown_done`. |
| **A-5** | Baixa | `server.py:963` `if platform != "android": return`; `_on_targets_listed` a cada poll | (a) Com a sessão em iOS, pendências Android nunca são retentadas. (b) Se o desmonte falha sempre (`settings put` recusado), saem ~6 comandos adb + 1 warning a cada `poll_interval`, sem limite. O CHANGELOG diz "quando o aparelho reaparece", e não é só isso. | Verificado por leitura | Retentar só na transição ausente→presente (o vigia sabe: ids da listagem anterior), ou espera crescente por serial. Tirar o gate de plataforma. |
| **A-6** | Baixa | `apps/tk-legacy/.../main_window.py:2466-2468` (REV-5) | `_start_passive_listeners` falha, desmarca o checkbox e escreve "indisponível"; `_on_passive_mode_toggled` sobrescreve com **"Modo Passivo ativado."**. Como `passive_mode_var` nasce `True`, a primeira troca para iOS sem Quartz zera a flag em silêncio e o passivo fica desligado depois, também no Android. | Verificado | `_start_passive_listeners` devolve `bool`; só escreve "ativado" se deu certo. |
| **A-7** | Baixa | `ios_wda.py`/`appium.py` `_sessao_invalida` (REV-2) | Critério ficou mais estrito: 404 com corpo vazio, HTML ou JSONWP (`{"status":6,...}`) não limpa o id → o sintoma original do M6 volta nesse caso. Nenhum teste cobre 404 sem JSON. | **Suposição** (depende da versão do WDA) | Tratar também 404 com corpo não-JSON **em `/session/<sid>/...`** como caduco, mantendo "unknown command" com JSON válido para o fallback. |
| **A-8** | Baixa | `server.py:485` `set_target` fora do `_state_lock` (M1) | Varredura em voo com alvo anterior `None` elege `ids[0]`, e o `on_changed` sobrescreve a escolha B com A. Janela estreita, pré-existente em parte. | Inferido | Chamar `set_target` dentro do `_state_lock` (a ordem de locks já permite: servidor nunca segura o do vigia). |
| **A-9** | Baixa | `adb.py:451` `delete global_http_proxy_host/port` sempre; `:369` `ret != 0 → None` | "O proxy volta ao que era" é mais do que o código faz: proxy global de MDM (`global_http_proxy_*`) nunca é guardado nem restaurado; uma falha momentânea de `settings get` grava "sem valor anterior" e o desmonte apaga o proxy corporativo. `AparelhoFalso` não modela `global_http_proxy_*`. | Verificado | Guardar e restaurar `global_http_proxy_host/port/exclusion_list`; tratar falha do `get` como "desconhecido" (não como "vazio") e, nesse caso, não apagar. Ajustar a frase do CHANGELOG. |

## Documentação e processo

| ID | O que está errado | Onde |
|---|---|---|
| **P-1** | "Nenhuma mudança de contrato RPC" vale para o esquema, não para a semântica. Três comportamentos observáveis mudaram sem registro: `passive.start` no iOS pode responder `AdapterError`; `devices.watch_start` não anuncia mais o alvo já escolhido; `session.select_device` não provoca mais `device.changed`. | `docs/PROTOCOLO_RPC.md:36,181,269`; `CHANGELOG.md` |
| **P-2** | Pendências resolvidas nesta rodada continuam "Pendente": A1 (M7) e o P0 #2 do pesquisador (M2, em parte). O doc diz "Nenhum item dele foi aplicado". | `docs/RODADA_2026-10-05_PENDENCIAS.md:68,113,116` |
| **P-3** | Números defasados: "437 + 133 subtests", "225 executados, 23 skips". Hoje: 511 / 298 / 26. | `docs/QA.md:10-11` |
| **P-4** | `MELHORIAS.md` afirma coisas que o repositório não sustenta: "linha de base medida na efcc5f9" (é afirmação da sessão, sem artefato; e a coluna "Antes" não tem número — o baseline foi rodado com `-q`, só pontos); "cada uma com o teste que falhava antes" não vale para 4 testes de caracterização (`test_sem_valor_anterior_apaga_como_antes`, `test_desmonte_bem_sucedido_nao_deixa_pendencia`, `test_erro_do_servidor_nao_repete_o_toque`, `testMetodoHTTPComumFicaSemAspas`); o ramo `reconfigurado` do REV-4 não tem teste que o exercite. | `docs/melhorias/2026-10-14/MELHORIAS.md:23,13` |
| **P-5** | O CHANGELOG não cita o Tk legado (REV-5) nem que a retentativa roda a cada varredura (A-5). | `CHANGELOG.md` |
| **P-6** | Regra do `AGENTS.md` ("`make check` e `make test-swift` antes de qualquer commit"): nos commits M1–M6 rodei pytest + ruff + `make qa`, mas o `make check` completo e o `swift test` completo só rodaram ao fim. O estado final passou; o processo por commit, não. | — |
| **P-7** | O app foi empacotado a partir da branch de melhoria, antes de integrar em `main`. O `AGENTS.md` pede empacotar "da branch onde o trabalho foi integrado". Se a integração mudar algo, `make update-native` precisa rodar de novo. | — |
| **P-8** | A árvore suja (3 caminhos de docs não rastreados) não foi resolvida antes de criar a branch, como o protocolo manda e como eu tinha proposto. Não atrapalhou, mas ficou. | `git status` |
| **P-9** | `_espera` nos testes (polling de até 3 s) não falha ao estourar o tempo; o assert seguinte pega, mas pode ficar intermitente sob carga. `ExportersEscapeTests` só cria arquivo em `/tmp` se o escape regredir, e nesse caso não o apaga. | `engine/tests/unit/test_proxy_restaura_aparelho.py`, `apps/MoBaile/Tests/MoBaileTests/ExportersEscapeTests.swift` |

## Confirmado como correto

- Base da branch: `efcc5f9` é ancestral de `origin/main` (que só tem os merges dos PRs #1–#4 a mais) e o conteúdo é idêntico (`git diff efcc5f9 origin/main` vazio). Um PR para `main` sai limpo.
- Tag anotada `v3.5.2` → `313fcf8`, `VERSION`=3.5.2, cópias consistentes, fixtures em dia. Nada foi enviado ao remoto.
- Sem inversão de locks: `on_targets_listed` roda fora do lock do vigia e só toma `_state_lock`.
- `passive.start` só grava `_passive` depois de `start()`; erro de Quartz não deixa `listening:true`. O Python do app instalado tem Quartz.
- Escape de cURL e do literal Python corretos; não há outro ponto no app que monte comando com dado do tráfego.
- Contagens coerentes: `def test` 480 → 517 no motor (511 aprovados), 292 → 298 no front.
- App instalado na 3.5.2, motor embutido idêntico a `engine/src` (`diff -rq` limpo), `verify-native` OK.

## O que eu faria agora, em ordem

1. **A-1** e **A-2** (regressões do M7): correção pequena, com teste de `AutoCompleteTextView` e de value≠label no iOS.
2. **A-3 + A-4** (corrida no encerramento) e **A-6** (Tk): pequenas.
3. **A-5**: retentar só na transição ausente→presente, sem gate de plataforma.
4. **P-1 a P-5**: `PROTOCOLO_RPC.md`, `RODADA_…PENDENCIAS.md`, `QA.md`, `MELHORIAS.md`, `CHANGELOG`.
5. **A-9**, **A-7**, **A-8**: decisão sua (escopo cresce; A-9 pede modelar `global_http_proxy_*`).

Tudo isso cabe em 3.5.3 (ou na própria 3.5.2 se ainda não foi publicada), com `make check`, `swift test` e `make update-native` de novo.

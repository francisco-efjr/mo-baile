# Revisão de QA: suítes, harness, fixtures e CI

Status: Rascunho (sem execução; a linha de base estava rodando) · Data: 2026-10-26 · Plataforma: macOS (SwiftUI) + motor Python
Papel: `qa` (test-auditor). Revisão feita pelo mesmo modelo que pode ter escrito partes do código; não é validação independente.
Modo: análise somente leitura. Nenhum teste, build ou `make` foi executado. Nada foi alterado fora deste arquivo.

## Resumo

Escopo auditado: `engine/tests/` (679 `def test_`, 52 arquivos de teste mais 3 módulos de apoio), `apps/MoBaile/Tests/` (363 `func test`, 39 arquivos), `qa/` (5 fluxos, 11 testes do gate), `tools/generate_fixtures.py`, `.github/workflows/ci.yml` e `release.yml`, `Makefile`.

Comandos de pré-filtro (todos de leitura): `git grep -L` por palavra de asserção (só módulos de apoio saem), `git grep` de `XCTSkip` e `skipUnless`, `git grep -w -F` do nome de cada adapter e serviço contra `engine/tests` e `qa`, leitura de `contract.py`, `server.py`, `generate_fixtures.py`, `EngineSession.swift` e dos testes citados.

Resultado em uma linha: a suíte do motor é forte (oráculos independentes, regressões nomeadas por defeito, gate de QA que recusa falso verde), mas há quatro buracos de confiança concentrados em fronteiras: skips silenciosos no CI do front, notificações sem fixture capturada, o progresso do fluxo sem teste que ligue emissor e consumidor, e parsers de log sem teste de entrada hostil.

Rótulos: **Verificado** = li o trecho exato nesta sessão; **Inferido** = dedução do código; **Suposição**; **Não verificável**.

## Propostas (até 5; aqui, 4)

| ID | Origem | Resumo | Esforço | Contrato RPC | Regra de negócio | Cabe no corte |
| --- | --- | --- | --- | --- | --- | --- |
| QA-1 | M17 | CI conta e limita testes pulados, `timeout-minutes` nos jobs, e prazo estourado deixa de virar skip | P | não | não | sim (~90 linhas, sem testes) |
| QA-2 | M4 | Progresso do fluxo: `flow.step` e `cancelled`, com teste que liga o runner ao consumidor Swift | M | sim, aditivo | sim, muda o que o usuário vê | sim (~150 linhas) |
| QA-3 | M3 | Fixtures capturadas da emissão real para as 8 notificações que faltam, e guarda contra novas sem fixture | M | não | não | sim (~110 linhas, quase tudo teste e ferramenta) |
| QA-4 | Q3 (+ parte de M13) | Fuzz determinístico dos parsers de log e invariante de redação, sem dependência nova | P | não | não | sim (~15 linhas de produção) |

### QA-1 — Skips contados e limitados no CI (origem M17)

**Problema.**
- O job `front` roda `swift build` e `swift test` e nada mais (`.github/workflows/ci.yml`, job `front`, últimas linhas). Ninguém lê quantos testes pularam. **Verificado.**
- Os testes que montam janela real pulam quando o SwiftUI não instala a árvore ou a toolbar: `AccessibilityInspector.swift:152`, `ToolbarLayoutTests.swift:47` e `:192`. Usam `AccessibilityInspector.arvore(...)` pelo menos 12 testes em `AccessibilityTests`, 3 em `CommandPaletteKeyboardTests`, 4 em `ReportTests` e 6 em `ToolbarLayoutTests`, ou seja, cerca de 25 testes COM asserção que viram verde sem verificar nada se o runner não tiver sessão gráfica. **Verificado** (contagem por leitura; número exato: **Inferido**).
- O backlog diz "26 testes com asserção". `docs/QA.md` diz que os 26 skips da 3.5.2 são, na maior parte, outra coisa: geradores de PNG sob demanda (`MOBAILE_SNAPSHOT_DIR`: `WindowSnapshotTests`, `LayoutSnapshotTests`, sem asserção por desenho) e casos com aparelho (`MOBAILE_DEVICE_TESTS`). A frase do backlog mistura as duas famílias. Hoje as duas famílias somam mais que 26 (WindowSnapshotTests tem 20 testes e LayoutSnapshotTests 5, todos com `XCTSkip` em `destino()`). **Inferido.** Se o runner `macos-26` tem sessão gráfica é **Não verificável** daqui; é justamente isso que a proposta mede.
- Pior caso de falso verde: `EngineClientStreamTests.swift:33-36`, a função `comPrazo`, lança `XCTSkip` quando o prazo de 45 s estoura. O comentário do arquivo diz que o defeito original foi "travar em vez de falhar", e a saída desse defeito hoje é um teste **pulado**, não vermelho. Só roda com `MOBAILE_DEVICE_TESTS=1`, então o dano é pequeno, mas é o único lugar em que o teste foi desenhado para flagrar o defeito e o tratamento do prazo o esconde. **Verificado.**
- Nenhum job tem `timeout-minutes` (`grep timeout-minutes .github/workflows/*.yml` só acha `release.yml:31`). Os testes de janela usam `RunLoop.current.run(until:)` (28 ocorrências em `Tests/`), e um travamento num runner macOS consome até o limite padrão de 360 min. **Verificado** (ausência) / **Inferido** (efeito).
- Paridade com `make check`: o CI não roda `test-ui` (Tkinter, congelado; aceitável) e roda `bandit` só em `engine/src` enquanto `make security` cobre também `apps/tk-legacy`. Diferença pequena e aceitável pelo ADR 0005; fica registrada, sem proposta.

**Melhoria.**
1. Novo `tools/ci_skips.py` (stdlib): lê a saída do `swift test` (ou o XML de `--xunit-output`, conferir a flag em `swift test --help`) e agrupa os pulados pelo motivo da mensagem do `XCTSkip`. Imprime a tabela no `$GITHUB_STEP_SUMMARY`.
2. Fase 1: só publica. Fase 2: um arquivo `tools/ci_skips_esperados.txt` com os motivos permitidos (snapshot sob demanda, aparelho, sem Python) e falha se aparecer motivo fora da lista, em especial "sem sessão gráfica". Se o runner não tiver sessão gráfica, a fase 2 fica vermelha de propósito e o dono decide entre mover esses testes para um job com sessão ou aceitar o buraco por escrito.
3. `pytest -rs` no job do motor e falha se os motivos fugirem da lista (hoje são 2 `skipUnless`: bash e OCR real com `swiftc`, e a pasta do design system).
4. `timeout-minutes` em todos os jobs de `ci.yml` (sugestão de partida: versao 5, contrato 5, engine 20, front 30).
5. `comPrazo` passa a lançar um erro de falha (por exemplo `struct PrazoEstourado: Error`) em vez de `XCTSkip`.

**Ganho.** Quem lê o CI sabe o que foi de fato verificado no front; um runner sem sessão gráfica deixa de dar verde falso para 25 testes de acessibilidade e toolbar.
**Esforço.** P. **Risco.** Baixo; a fase 2 pode acender o CI de vermelho por um motivo real.
**Contrato RPC:** não. **Regra de negócio:** não.
**Critério de aceite.** (a) Teste do parser em `qa/tests/test_ci_skips.py` com saída sintética do `swift test`: com um skip de motivo desconhecido o script sai com código 1 (falha antes da mudança porque o script não existe; passa depois); (b) `ci.yml` com `timeout-minutes`; (c) um PR de teste com um `XCTSkip("sem sessão gráfica")` extra deixa o job vermelho.
**Rótulo.** Verificado (evidências de arquivo e linha); Inferido (efeito no runner).

### QA-2 — Progresso do fluxo que anda e "cancelado" no fim (origem M4)

**Problema.**
- O runner Android/iOS imprime `▶ [{i}/{total}] Executando: {var_name} ...` (`engine/src/mobaile/services/flows.py:379`, com `var_name` padrão `PASSO_{i}`), e o runner Maestro imprime `▶ [n/total] ...` (`engine/src/mobaile/services/maestro_flow.py:746`, chamado em `:718-720` com `f"{n}/{total}"`). **Verificado.**
- O front só avança o passo atual com a regex `(?i)passo\s+(\d+)` (`apps/MoBaile/Sources/MoBaile/Engine/EngineSession.swift:1738-1741`, usada em `:1679`). Ela não casa `PASSO_2` (sublinhado, sem espaço) nem `[2/5]`. Só casa as linhas de falha ("FALHA no passo {i}", `flows.py:394`) e "Erro inesperado ao executar o passo {i}" (`:390`). **Verificado.**
- Efeito na tela: `currentRunStep` (`AppState.swift:164`) fica em 0 enquanto o fluxo roda, e `FlowRunnerSheet.swift:181-186` marca todo passo como pendente e a barra (`:211-217`) fica parada. No Maestro nenhuma linha de sucesso ou falha tem "passo N", então o passo que falhou também não é marcado. **Inferido** (leitura do consumidor, sem executar a UI).
- "Cancelado": `flows`/`maestro` entregam `flow.finished {success, message}` com `success = sucesso and not cancelado` (`server.py:1845-1848`, `:1979`). O front mapeia `success=false` para `.failed` (`EngineSession.swift:1683-1690`), então cancelar aparece como falha. **Verificado.**
- Lacuna de teste: `grep "▶"` em `engine/tests`, `apps/MoBaile/Tests` e `qa` não acha nada. Nenhum teste liga o formato que o motor emite ao que o front interpreta. `numeroDoPasso` é `private static` e não tem teste. `engine/tests/unit/test_flow_execucao.py` cobre o fim (`flow.finished`) e o texto digitado, mas não a sequência de passos. **Verificado.**

**Melhoria.**
- Motor (a regra mora num lugar só): `server.py` interpreta a linha `▶ [i/n]` no callback `ao_sair` (as duas execuções passam por ele) e emite `flow.step {index, total}` antes do `flow.log`. Alternativa mais limpa, se o orquestrador aceitar o diff maior: o runner chama um callback estruturado. Acrescentar `cancelled: bool` a `flow.finished`.
- Contrato: `flow.step` entra em `contract.NOTIFICATIONS` e em `docs/PROTOCOLO_RPC.md`; `cancelled` é campo aditivo. `PROTOCOL_VERSION` continua 2. O teste de deriva `TestDeriva` (`test_contrato_declarativo.py:121-155`) já força a documentação.
- Front: `EngineSession.handle` usa `flow.step` para `currentRunStep` e mostra "Cancelado" quando `cancelled` é verdadeiro. A regex fica só como compatibilidade com motor antigo, ou sai.

**Ganho.** O usuário vê o andamento real do fluxo, inclusive no Maestro, e deixa de ver cancelamento como falha.
**Esforço.** M. **Risco.** Baixo a médio: toca `RunState` na interface, e `FlowRunnerSheet` depende de `currentRunStep` para ok, rodando e falhou.
**Contrato RPC:** sim, aditivo. **Regra de negócio:** sim, no sentido do que o usuário vê (resultado e estado do passo); não muda documento gerado.
**Critério de aceite.**
- Motor: em `test_flow_execucao.py`, gravar 3 passos, rodar e afirmar `flow.step` com `index` 1, 2, 3 e `total` 3, em ordem e antes de `flow.finished`. Falha antes (a notificação não existe), passa depois. Outro teste cancela no passo 2 e afirma `cancelled: true`.
- Fixture: `notif_flow.step` gerada pelo `generate_fixtures.py` (ver QA-3); `make fixtures-check` verde.
- Swift: teste em `EngineSessionTests` que alimenta `flow.step` e afirma `currentRunStep`; e um teste que alimenta a linha real `▶ [2/5] Executando: PASSO_2 (...)` capturada de `flows.py` e afirma que o fallback não regride.
**Rótulo.** Verificado (emissor, regex e ausência de teste); Inferido (efeito visual).

### QA-3 — Fixtures capturadas da emissão real (origem M3)

**Problema.**
- `NOTIFICATIONS` tem 12 entradas (`contract.py:177-190`). O arquivo de fixtures tem 4 chaves `notif_*`: `$/progress`, `stream.frame`, `proxy.event`, `analytics.event` (`engine_payloads.json`; geradas em `tools/generate_fixtures.py:336`, `:359`, `:370`, `:377`). Faltam `stream.settled`, `device.changed`, `home.changed`, `passive.step`, `passive.skipped`, `passive.text`, `flow.log` e `flow.finished`. **Verificado.** (O backlog fala em 3 de 11; o número envelheceu.)
- Na ponta Swift, essas notificações são testadas com JSON escrito à mão, por exemplo `#"{"params":{"platform":"android","device_id":"emulator-5554"}}"#` em `EngineSessionTests.swift:360-363` e `:381-385`, e com structs locais (`Linha`, `Fim`, `Pulado` em `EngineSession.swift:1660-1685`) que nenhum teste de contrato exerce. Se o motor renomear `line` ou `success`, nada quebra até alguém rodar o fluxo. **Verificado.**
- `proxy.event` e `analytics.event` nas fixtures vêm de `protocol.notification(..., obj.to_dict())`, não de `server.notify`, portanto cobrem o formato do modelo, não a emissão pelo servidor. **Inferido.**
- O que já protege: o teste de deriva garante que os NOMES estão declarados, emitidos e documentados (`test_contrato_declarativo.py:128-155`). Não garante a forma do payload.

**Melhoria.**
1. Em `tools/generate_fixtures.py`, capturar via o mesmo mecanismo que já captura `$/progress` (lista `avisos` do servidor) as 8 notificações faltantes, usando o aparelho falso do próprio gerador. `flow.log`/`flow.finished` pedem um `flow.run` curto com `AdbFalso` (padrão de `test_flow_execucao.py`).
2. Mover `Linha`, `Fim`, `Pulado` para `EngineDTO` e decodificar as fixtures em `EngineContractTests`.
3. Teste de guarda em Python (novo, em `engine/tests/contract/`): toda entrada de `NOTIFICATIONS` tem chave `notif_<nome>` nas fixtures, com uma lista de exceções que só pode encolher. Falha hoje com 8 itens; é o oráculo independente do trabalho.

**Ganho.** Renomear ou remover campo do contrato quebra o PR, não o app em uso. É o complemento natural de `make fixtures-check`.
**Esforço.** M. **Risco.** Baixo; fixtures com campo instável (tempo, id) precisam passar pela normalização que o `generate_fixtures.py` já tem (`_normalizar`, `_pixels`).
**Contrato RPC:** não (só fixtures e DTO). **Regra de negócio:** não.
**Critério de aceite.** O teste de guarda falha antes (8 ausentes) e passa depois; `EngineContractTests` ganha um teste por notificação; `make fixtures-check` e `make test-swift` verdes. Combina com QA-2: `flow.step` já nasce com fixture.
**Rótulo.** Verificado (contagens e linhas); Suposição (esforço do `flow.run` dentro do gerador).

### QA-4 — Fuzz determinístico dos parsers de log e invariante de redação (origem Q3, parte de M13)

**Problema.**
- Os parsers de texto externo são `analytics_logcat.py` (620 linhas), `android_okhttp_log.py` (387), `ios_cfnetwork.py` (449), `firebase_log.py` (200) e o leitor de OCR. Os testes existentes usam entradas bem formadas. Entre os nomes de teste dos arquivos, os únicos que miram entrada ruim são `test_corpo_grande_picado_pelo_logcat_volta_inteiro`, `test_framing_invalido...` do proxy e `test_regex_invalida_e_apontada_no_card`. Não há `hypothesis` nem fuzz em `engine/`, `qa/` ou `tools/` (`git grep -i hypothesis` vazio). **Verificado.**
- Os três laços de leitura tratam exceção de forma diferente: `ios_cfnetwork.py:402-425` captura `Exception`; `android_okhttp_log.py:376-382` captura só `ValueError` e `KeyError`; `analytics_logcat.py:389-413` (`_stream_reader`) não captura nada em torno de `_parse_line` e `_parse_ios_record`. Uma exceção inesperada (IndexError, AttributeError, TypeError, RecursionError) mata a thread de leitura do OkHttp ou do Analytics e o app segue mostrando "escuta ligada" sem eventos. **Verificado** (as três leituras); **Inferido** (existência de uma entrada que dispare a exceção).
- Candidatos a custo quadrático ou pior em `_parse_line` (`analytics_logcat.py:556-582`): `re.search(r"params\s*=\s*\{(.*?)\}", line, re.DOTALL)` e `re.split(r",\s*(?=...)` sobre um `Bundle[{...}]` muito longo. **Inferido** (não medi).
- Redação: `security/redaction.py` agora casa pela chave normalizada inteira (`_is_sensitive_key`, `:73`), o que resolve o "erra em passage/monkey" do backlog (ver Resolvidos). `test_security.py:TestRedacao` tem 9 testes, bons, mas nenhum atravessa os três adapters (okhttp, cfnetwork, proxy) com uma credencial-sentinela. `grep` de `authorization|redigido|«` acha 2 ocorrências em okhttp, 2 em cfnetwork e 4 em `test_proxy_unit.py`. O eventos de Analytics carregam `raw_log` e `params` sem nenhuma redação (`models.py:228-249`; `analytics_logcat.py` só importa `validate_device_id`). **Verificado.**

**Melhoria.**
1. Novo `engine/tests/unit/test_fuzz_parsers.py`, só stdlib: `random.Random(semente fixa)` gera 2 mil entradas por parser, mutando as linhas dos testes existentes (truncar, duplicar, inserir `\x00`, UTF-8 inválido, linha de 1 MB, aninhamento de chaves/colchetes). Invariantes: não levanta, retorna dentro de um prazo folgado (por exemplo 0,5 s por entrada, para pegar ReDoS sem flake) e `feed` devolve lista. A semente e o corpus ficam no arquivo para reproduzir uma falha.
2. Invariante de redação: injetar a sentinela `SEGREDO-SINTETICO-123` em `Authorization`, em query string, em corpo JSON e em corpo de form nos formatos do okhttp e do cfnetwork, e afirmar que ela não aparece em nenhum `NetworkEvent.to_dict()` nem no arquivo bruto do CFNetwork (`RAW_LOG_PATH`, com `MOBAILE_DATA_DIR` temporário, que o `conftest.py` já fornece).
3. Produção (uns 15 linhas): `_stream_reader` do Analytics ganha `try/except Exception` com `logger.exception` ao redor do parse (mesmo padrão do cfnetwork), e o okhttp passa de `(ValueError, KeyError)` para `Exception`. Se o fuzz achar uma exceção real, a correção entra com o caso mínimo como teste fixo.
4. Opcional, só se o dono aceitar dependência de dev: trocar o gerador por `hypothesis` em `engine[dev]`. Não é necessário para o ganho.
5. Decisão que NÃO é de QA: se `params` e `raw_log` de Analytics devem ser redigidos. Redigir valores quebraria a validação contra a spec do Relatório (regra de negócio). Registrado em Decisões pendentes.

**Ganho.** Texto de fora (logcat, log do iPhone, OCR) deixa de poder derrubar a escuta em silêncio, e a promessa de redação ganha um teste que atravessa as camadas.
**Esforço.** P. **Risco.** Baixo; fuzz com semente fixa é determinístico. O prazo por entrada precisa de folga (CI Linux e Mac) para não virar flake.
**Contrato RPC:** não. **Regra de negócio:** não.
**Critério de aceite.** O teste de invariante de redação passa hoje se a redação funciona (é uma rede de segurança, não um defeito conhecido). O teste de "a thread do Analytics sobrevive a um registro hostil" deve falhar antes: alimentar `_stream_reader` com um `_parse_line` que levanta e afirmar que a linha seguinte ainda vira evento; passa depois do `try/except`.
**Rótulo.** Verificado (laços e ausência de fuzz); Inferido (entrada que quebra); Suposição (ReDoS).

## Backlog da minha área: resolvido ou que não se sustenta

| ID | Estado | Evidência |
| --- | --- | --- |
| M13 (parte "redação por substring erra passage/monkey") | Resolvido na parte de chave | `security/redaction.py:73-74` normaliza a chave inteira e compara com um conjunto exato (`_SENSITIVE_KEYS`); `passage` e `monkey` não casam. Permanece aberta a parte "Analytics não redige nada" (ver Decisões pendentes). |
| M3 (número "3 de 11") | Desatualizado | Hoje são 4 de 12 (`$/progress`, `stream.frame`, `proxy.event`, `analytics.event`); a proposta QA-3 cobre as 8 restantes. |
| M17 (número "26 testes com asserção") | Impreciso | `docs/QA.md` atribui os 26 skips da 3.5.2 principalmente a snapshots sob demanda e aparelho; os que têm asserção e dependem de sessão gráfica são cerca de 25 e são outra conta. Item continua aberto. |
| Q1 Regressão visual por pixel | Aberto, não proposto | `WindowSnapshotTests.swift:12-13` se declara "ferramenta de inspeção, não asserção"; sem comparação de pixels em lugar nenhum. Esforço M, e depende de runner com sessão gráfica (ligado a QA-1). |
| Q2 `performAccessibilityAudit()` | Aberto, não proposto | `git grep performAccessibilityAudit` vazio; a acessibilidade é testada por rótulos escolhidos à mão em `AccessibilityTests`. Também depende de sessão gráfica. |
| Q5 Desempenho com orçamento | Aberto, não proposto | `git grep "XCTMetric\|measure("` vazio no front. No motor há um teste de orçamento folgado (`test_report_desempenho.py:165`, limite 1,0 s contra 0,07 s medidos). |
| M4 | Aberto (ver QA-2) | Regex e formato do runner incompatíveis. |

Não propostos por não caberem no corte ou dependerem de decisão: Q1, Q2 e Q5 (M cada, os dois primeiros bloqueados por sessão gráfica no CI), piso de cobertura (não há número medido hoje; `ci.yml` roda `--cov` sem `--cov-fail-under`, e o último número em `docs/QA.md` é de antes de 05/10).

## Retidos (candidatos de auditoria que NÃO devem ser podados)

Auditoria de testes de baixo valor: não encontrei candidato `retire` com confiança 7 ou mais.

- Arquivos sem palavra de asserção: só `conftest.py`, `aparelho_falso.py`, `relatorio_dados.py`, `relatorio_ocr.py`, que são apoio.
- `test_contrato_declarativo.py:TestDeriva` lê o código-fonte como texto (regex de `notify("...")`), mas é guarda de contrato público (nomes declarados, emitidos, documentados). Fica.
- Testes de `HomeTests.swift:185` e `PaletteTests.swift:42-46` leem arquivos do repositório (`instalar-mac.sh`, `palettes.css`): protegem a equivalência entre artefato de design/instalação e código. Ficam.
- Os testes de concorrência de `test_despacho_concorrente.py` usam `Event.wait(1)` e alguns `time.sleep(0.1 a 0.3)` seguidos de asserção negativa (`:459`, `:492`, `:514`). Risco de flake em CI carregado: baixo a médio (Inferido); uma asserção negativa depois de `sleep` não prova ausência, mas aqui o gancho é uma thread bloqueada e solta por `Event`, o que dá oráculo razoável. Sem proposta; se aparecer intermitência, aplicar `flaky-triage` e trocar o `sleep` por espera pela condição.
- `markers` `integration` e `requires_device` em `engine/pyproject.toml` não são usados por nenhum teste (`git grep pytest.mark` só acha o `parametrize` de `qa/tests/test_run_all.py`), apesar de `requires_device` dizer "pulado em CI". Marcador morto, inofensivo; vale limpar junto com QA-1. Severidade Baixa.
- O gate do harness (`qa/run_all.py` e `qa/tests/test_run_all.py`) é sólido: recusa zero verificações, resumo duplicado, resumo ausente, código de saída diferente de zero e timeout, e mata o grupo de processos. Fica como está. Uma melhoria opcional é fixar um piso de verificações por fluxo (um fluxo que passa a pular blocos continuaria verde), de baixo valor hoje.

## Efeito estimado por lote (LOC; Inferido, por contagem das linhas lidas)

| Lote | Produção | Teste e ferramenta |
| --- | --- | --- |
| QA-1 | ~5 (Swift, `comPrazo`) | ~80 (`tools/ci_skips.py`, lista, YAML, teste) |
| QA-2 | ~90 (motor ~40, Swift ~40, contrato e doc ~10) | ~80 |
| QA-3 | ~40 (DTO Swift) | ~120 |
| QA-4 | ~15 | ~150 |
Total de produção ~150 linhas, dentro do teto de ~600 da rodada junto com as demais áreas.

## Comandos de validação sugeridos (para a sessão principal, depois da aprovação)

- Motor: `cd engine && python -m pytest tests/unit/test_fuzz_parsers.py tests/unit/test_flow_execucao.py tests/contract -q` e depois `make check`.
- Contrato: `make fixtures` (QA-2 e QA-3), `make fixtures-check`, `make test-swift`.
- QA-1: `python -m pytest qa/tests/test_ci_skips.py -q`; conferir a saída real do `swift test` para o formato dos skips antes de fixar o parser.
- `git diff --check`.
- Regressão nos dois sentidos (QA-2, QA-4): rodar o teste novo num worktree limpo da base (falha) e na branch com a correção (passa).
- Como o app nativo é afetado (QA-2 toca `apps/MoBaile`): `make update-native` ao fim, com o app fechado (AGENTS.md).

## Não verificado

- Nada foi executado: contagens de testes e de skips vêm de leitura; o número real de skips por família só sai de um `swift test` (QA-1 existe para isso).
- Se o runner `macos-26` tem sessão gráfica: **Não verificável** daqui.
- O formato exato da saída de skip do `swift test` e a flag `--xunit-output` na versão instalada do Swift: conferir.
- ReDoS em `_parse_line` e a existência de uma exceção não tratada nos parsers: hipóteses (Inferido/Suposição) até o fuzz rodar.
- O efeito visual da barra de progresso (QA-2) foi deduzido do código do consumidor, sem abrir a interface.
- Não li `engine/tests/unit/test_report_*.py` linha a linha (só nomes e padrões); a cobertura de `report/` por nome de módulo está presente (audit, board, firebase_log, card_reader, rules, html_report).

## Decisões pendentes do humano

1. Eventos de Analytics (`params`, `raw_log`) devem ser redigidos? Hoje não são (`analytics_logcat.py` não usa `redaction`). Redigir valor afetaria a validação contra a spec do Relatório. Isso é decisão de produto e segurança; recomendo ouvir o especialista de segurança desta rodada.
2. Se o runner do CI não tiver sessão gráfica (QA-1, fase 2): mover os ~25 testes de acessibilidade e toolbar para um job com sessão, aceitar o buraco por escrito, ou marcar como teste local obrigatório no `make check`.
3. Aceitar `hypothesis` como dependência de dev, ou ficar no fuzz com stdlib (recomendado: stdlib).
4. QA-2 mexe em `RunState` e na folha de execução; confirmar com quem cuida da interface que "cancelado" vira estado próprio e não só mensagem.

## Conteúdo suspeito

Nenhum. Os arquivos de teste, comentários e documentos lidos não continham texto dirigido a agentes.

## Outras áreas a recomendar

- Segurança: decisão sobre redação de Analytics e `raw_log` (item 1 acima).
- Interface/design: estado visual de fluxo cancelado e acessibilidade da barra de progresso (QA-2).
- DevOps/CI: tempo de execução dos jobs macOS e política de runner com sessão gráfica (QA-1).

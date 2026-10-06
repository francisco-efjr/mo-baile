# Rodada de melhorias 05–06/10/2026 — entregue e pendente

Rodada orquestrada a partir de dois prompts:
[`PROMPT_MELHORIAS_DEV_UX_QA.md`](PROMPT_MELHORIAS_DEV_UX_QA.md) (Prompt A: épicos A–D)
e um segundo prompt com 7 itens de privacidade, robustez e distribuição (Prompt B, PB1–PB7).
A rodada foi encerrada a pedido antes de terminar. Os seis agentes de implementação
pararam duas vezes: primeiro no limite de uso da API e depois por encerramento manual.
Este documento registra o que entrou na versão 2.1.1, o que ficou pela metade e em
que branch, e a ordem sugerida para retomar.

## Como a rodada foi organizada

| Papel | Modelo | Resultado |
|---|---|---|
| Analista (somente leitura) | Sonnet | Concluído. Veredito por item na seção [Análise](#análise-item-a-item) |
| Pesquisador (`consultor-pesquisador`) | Opus | Concluído. [`research/pontos-de-melhoria-2026-10-05.md`](research/pontos-de-melhoria-2026-10-05.md) |
| motor-execucao | Opus | PB1 concluído e integrado. PB2 iniciado. PB4, PB6 e o fluxo 5 de QA pendentes |
| motor-sessao-codegen | Opus | Parcial: `session_store.py` e modelo de domínio em andamento |
| motor-transporte | Opus | Parcial: `rpc/transport.py` escrito, sem testes |
| front-integracao | Opus | Parcial: DTOs e modelos novos. `EngineSession` ainda não foi alterado |
| front-ux | Sonnet | Acessibilidade concluída e integrada. Navegação por teclado em andamento |
| distribuicao | Sonnet | Parcial: `EngineLocator` com validação e empacotamento com runtime, sem verificação |

Método: um contrato comum escrito antes (apêndice A). Cada implementador trabalhou num
git worktree próprio, com dono por arquivo para evitar conflito. Merge e revisão
independente estavam previstos ao final, e não chegaram a acontecer.

## Entregue na 2.1.1

| Commit | O que muda | Evidência |
|---|---|---|
| `4436082` fix(qa) | Correções locais da revisão de 05/10 ([`QA_2026-10-05.md`](QA_2026-10-05.md)): redação no proxy, cancelamento cooperativo, preservação de estado no Swift, harness de QA | Linha de base verde antes da rodada |
| `3bc2d87` fix(fluxo) | **PB1.** O texto digitado não aparece mais em `flow.log`, nas notificações nem no stdout do motor; o runner registra só tamanho e campo. Foram removidos os textos inventados "Texto de Exemplo" e "Texto de Teste": um passo de digitação sem texto agora falha | `engine/tests/unit/test_flow_execucao.py` com adb falso. A sentinela chega ao aparelho e não aparece em lugar nenhum. **Falha no código anterior** (a sentinela aparece no `flow.log`) e passa no novo. Os dois testes foram conferidos pelo orquestrador num worktree em `4436082` |
| `6281d1e` feat(a11y) | **Épico B5.** Rótulos, estados e papéis para VoiceOver na toolbar, nos controles segmentados, nas abas, nas tabelas HTTP e de analytics, nos editores, no espelho e no estado vazio | `AccessibilityTests.swift` lê a árvore de acessibilidade real do macOS |
| — docs | Este documento e o relatório do pesquisador | — |

Verificação final na branch `etapa-1/motor-que-nao-trava`:

| Verificação | Antes da rodada | Depois |
|---|---|---|
| `make check` (versão, ruff, bandit, suítes Python, fluxos de QA) | ok | ok |
| Motor | 326 aprovados, 110 subtests | 328 aprovados, 110 subtests |
| Tkinter / harness | 18 / 11 | 18 / 11 |
| Fluxos sem device / iOS / Android / HTTPS | 19 / 31 / 35 / 34 | 19 / 31 / 35 / 34 |
| `swift test` | 130 testes, 10 skips, 0 falhas | 142 testes, 10 skips, 0 falhas |

## Análise item a item

Veredito do analista contra o código em `4436082`, seguido do estado ao encerrar.
Os vereditos são: CONF (confirmado), PARC (parcial), RESOLV (já resolvido) e NÃO (não aplicar).

### Prompt B

| Item | Veredito e achado principal | Estado |
|---|---|---|
| PB1 texto digitado em log | CONF. O vazamento era mais amplo do que o prompt dizia: chegava também ao `runLog`, que vai para `/tmp` e para o clipboard; à notificação `passive.text`; e à `StepsList` | **Feito** no motor (`3bc2d87`). Pendente: mascarar a `StepsList` e a `passive.text` nos campos sensíveis |
| PB2 digitação iOS | PARC. `execute_ios_step` ignora `input_text`, então um passo de digitação no iOS vira só um toque | Iniciado: `ios_wda.py` com 134 linhas na branch de motor-execucao, sem teste |
| PB3 sessão após reinício | CONF. O `restore()` do Swift não toca nos passos, e o motor novo nasce vazio | Parcial: `session_store.py` com 514 linhas, sem RPC completo e sem testes. O lado Swift não começou |
| PB4 execução por localizador | CONF. O executor só usa `coords`, as esperas são fixas e os textos padrão eram inventados | Textos inventados removidos (`3bc2d87`). Localizador e espera por condição pendentes |
| PB5 memória e transporte | PARC. Defeitos reais: `analytics.event_queue` não tem limite nem consumidor (20.000 eventos ficam retidos); `proxy.event_queue` não é drenada; o Swift não limita os eventos de analytics. Bloquear o stdin quebraria o cancelamento | Parcial: `transport.py` com 588 linhas e contadores nos adapters, sem testes |
| PB6 progresso estruturado | CONF, e pior do que o descrito. A regex do Swift nunca casa numa execução bem-sucedida, então o destaque do passo não avança. Cancelamento aparece como falha, e uma falha do `flow.stop` é engolida | Pendente. Contrato desenhado (apêndice A §1). `FlowRun.swift` foi iniciado no front |
| PB7 distribuição | CONF. O `/usr/bin/python3` 3.9.6 sem Pillow é aceito, e o app empacotado entra em laço de reinício | Parcial: `EngineLocator` validando candidatos, `bundle_runtime.py` e `verify_bundle.sh`, ainda não executados |

### Prompt A

| Item | Veredito | Estado |
|---|---|---|
| A1 unicidade de seletor | PARC. `matches: 1` só é fixo em xpath e position. Um `//tag` sem atributos aparece como "único". No iOS, o candidato `text` conta por texto, mas a expressão gerada usa `@name` | Pendente (pequena mudança em `codegen.py` na branch) |
| A2 `click_at_position` / BasePage / `ast` | CONF. Aspas no texto geram `SyntaxError`, e um teste e uma fixture travavam o defeito. Só `ast.parse` não basta: o XPath também precisa ser válido | Pendente |
| A3 replay por coordenada | CONF. O analista sugeriu etapa própria (G) | Pendente, junto com PB4 |
| A4 `web_app.py` | PARC. Chama o adb direto, `streamlit` não está declarado, fica fora do lint e **executa um `main.py` recebido por upload** | Pendente: mover para `tools/experimental/` e documentar o risco |
| B1 CorrelationCard | PARC. O endpoint fixo é o fallback; `status ?? 200` também é um valor inventado; `wait_for_request` não existe; o Tk repete a mesma fachada | Pendente. Contrato `codegen.http_contract` desenhado (apêndice A §2). `Correlation.swift` foi iniciado |
| B2 FlowRunnerModal | CONF, e pior do que o descrito. "Aprovados" conta passos gravados, "falhas" só vale 0 ou 1, e as portas são literais | Pendente (depende de PB6) |
| B3 teclado na árvore | PARC. `visible` não existe no motor. O "Copiar tudo" é um stub. A linha "enabled" mostra `clickable` | Em andamento: `HierarchyNavigation.swift` e `ElementLocatorCopy.swift` na branch de front-ux |
| B4 operações longas | PARC. `$/progress` já é consumido; falta mostrar o tempo decorrido | Pendente |
| B5 acessibilidade | PARC. Havia 0 hints | **Feito** (`6281d1e`) nas views fora do escopo de integração. Pendente: FlowRunnerModal, StatusBar, CorrelationCard e DiagnosticCard |
| C1 testes de codegen + `ast` | PARC | Pendente, junto com A2 |
| C2 deriva contrato × Swift | PARC. Nomes, notificações, documentação e fixtures já são cobertos no CI | Pendente: teste estático `call("x")`/`case "n"` do Swift ⊂ contrato |
| C3 desconexão abrupta | PARC. Há teste unitário, mas falta integração. O motor não para o stream sozinho | Pendente |
| C4 Fluxo 5 de QA | PARC. HAR existe só no Swift; o TSV está duplicado e não tem RPC | Pendente (depende de PB6) |
| D1 espelho em JPEG | CONF. Ganho de CPU de cerca de 70%. Em bytes depende da imagem: em UI plana o JPEG chega a 12–26% **maior** | Pendente: medir com tela real e com tela plana antes de decidir o padrão |
| D2 descarte de quadros | RESOLV no consumidor (`bufferingNewest(1)`, com teste) | Não aplicar |
| tk-legacy: 488 cores literais | CONF | Não aplicar, porque a UI está em transição |

Conflitos entre os prompts e a decisão tomada:

- **Fallback para coordenada:** não haverá fallback automático. Coordenada só vale quando a estratégia gravada é `position`.
- **Duração do passo:** o motor mede e envia `duration_ms`; o Swift só exibe. Nada vai pelo `flow.log`.
- **Fila do stdin:** não será limitada com bloqueio, porque carrega `$/cancelRequest` e `engine.shutdown`.

## Trabalho parcial preservado

Cada branch abaixo é **local** (não foi enviada ao remoto) e termina num commit
`wip:`. Todas partem de `4436082`. O worktree de cada uma fica em
`.claude/worktrees/agent-<id>/`, excluído do git só nesta máquina.
**Nada disso foi testado nem revisado. Não integre sem revisão.**

| Branch local | Dono | Conteúdo |
|---|---|---|
| `worktree-agent-a453a97ddda7b343e` | motor-execucao | PB1 (já integrado) + `ios_wda.py` com digitação via WDA iniciada |
| `worktree-agent-ad7d472dd0b5a7130` | motor-sessao-codegen | `session_store.py` (514 linhas), `sensitive`/`recorded_at` no `AutomationStep`, ajustes em `codegen.py`/`hierarchy.py`/`server.py` |
| `worktree-agent-a87b49272d043ad8c` | motor-transporte | `rpc/transport.py` (588 linhas), integração em `server.py`, `evicted`/`capacity` nos adapters, entradas no contrato; documentação desatualizada |
| `worktree-agent-aacc1948ad44fa5a9` | front-integracao | DTOs novos (`EngineDTO`, `EngineClient` com limite de linha), `FlowRun.swift`, `Correlation.swift`, `RunState`; `EngineSession` intocado |
| `worktree-agent-a032e5551b5cd5a34` | front-ux | Acessibilidade (já integrada) + navegação por teclado da árvore (`HierarchyNavigation.swift`, `ElementLocatorCopy.swift`, reescrita de `HierarchyTreeView.swift`). Nasceu de `origin/main`; para integrar, aplicar só o diff de `0a10d4a..HEAD` |
| `worktree-agent-a803987a556e5938e` | distribuicao | `EngineLocator.swift` com validação de versão e imports, `tools/bundle_runtime.py`, `tools/verify_bundle.sh`, entitlements, `package_macos_app.sh` com runtime embutido |

Para inspecionar: `git log -p 4436082..worktree-agent-<id>`. Para descartar:
`git worktree remove .claude/worktrees/agent-<id> && git branch -D worktree-agent-<id>`.

## Fora dos prompts: achados do pesquisador

O relatório completo está em [`research/pontos-de-melhoria-2026-10-05.md`](research/pontos-de-melhoria-2026-10-05.md).
Nenhum item dele foi aplicado. Os P0 são:

1. **O callback do proxy é registrado a cada `proxy.start`.** Religar a captura multiplica as linhas da aba Rede e do HAR (`server.py:868`, `proxy.py:535`). O defeito foi reproduzido. Correção pequena (quick win).
2. **O motor não registra nem desfaz o que muda no aparelho.** O proxy é removido do aparelho atual, não do que foi configurado. O `captive_portal_mode` não é restaurado. O `stop` do analytics não desliga o debug do Firebase, que continua ligado e vai para o BigQuery.
3. **O app instalado por padrão (Tk) chama os adapters direto** e não recebe as correções da etapa 1 nem as desta rodada.
4. **O log do motor some no app Swift aberto pelo Finder.** Também não há `faulthandler` nem exportação de diagnóstico.

Quick wins sugeridos:

- registrar o callback do proxy uma vez só;
- desligar o debug do Firebase no `stop`;
- ligar o espelho antes de ler a hierarquia em `activateDevice`;
- gravar o log do motor em arquivo com rotação e `faulthandler`;
- ativar a regra `S110` do ruff e corrigir os 14 `except Exception: pass`.

## Ordem sugerida para retomar

1. **Quick wins do pesquisador** (proxy duplicado, debug do Firebase): são pequenos, independentes e corrigem dado errado na tela.
2. **PB6 + B2 + C4.** Eventos estruturados de fluxo, rodapé real no modal e fluxo 5 de QA. É a dependência central do front.
3. **PB2 + PB4/A3.** Digitação iOS e execução por localizador, partindo da branch de motor-execucao.
4. **PB3.** Sessão persistida no motor (branch de sessao-codegen) e restauração no front (branch de front-integracao).
5. **A1 + A2 + C1 + B1.** Codegen executável, XPath válido, `codegen.http_contract` e o card de correlação real (Swift e Tk).
6. **PB5.** Vazamentos de `event_queue` primeiro, que são pequenos; depois o transporte, partindo da branch de transporte; por fim o limite de histórico de analytics no Swift.
7. **B3/B4/C2/C3/A4/D1.** Teclado na árvore (branch de front-ux), tempo decorrido, teste estático de deriva, desconexão, `web_app.py` e JPEG medido.
8. **PB7.** Validação de candidatos do `EngineLocator` (branch de distribuição). O app autossuficiente depende da decisão de licença do ADR 0002 (plano 5.1).

Cada item ainda precisa de regressão que falhe antes e passe depois, e de
`make check` e `swift test`. Se o contrato mudar, também precisa de `make fixtures`
e da documentação em `PROTOCOLO_RPC.md`. Antes de liberar para aparelho real,
rode o roteiro manual de [`QA.md`](QA.md).

## Apêndice A — contrato desenhado para a rodada

Todas as mudanças são aditivas: `PROTOCOL_VERSION` continua 2. As capabilities
`flow_events`, `session_store` e `backpressure` entrariam no merge.

### §1 Execução de fluxo

- `flow.run` devolve `{running, run_id, steps, script}`.
- Notificação nova `flow.step`: `{run_id, index, total, var_name, action, status: started|passed|failed|cancelled, duration_ms, locator: {strategy, value}|null, message}`. O texto digitado nunca entra.
- `flow.log`: `{run_id, line}`, só texto humano. O front não deriva progresso dele.
- `flow.finished`: `{run_id, result: passed|failed|cancelled, success, message, duration_ms, passed, failed, total}`.
- `flow.stop` devolve `{run_id, running, stop_requested}`. Se não conseguir sinalizar, responde com erro JSON-RPC.
- `flow.status` devolve `{run_id, running, stop_requested, current_index, total, result, passed, failed}`.

### §2 Sessão e codegen

- **Arquivo:** `$MOBAILE_SESSION_DIR/session.json`, ou `~/Library/Application Support/Mo baile/session.json` sem a variável. Diretório 0700, arquivo 0600. Gravação atômica: tmp, fsync, `os.replace`.
- **Documento v1:** `{schema: "mobaile.session", version: 1, saved_at, engine_version, platform, device_id, settings: {page_objects_key, strategy}, steps, editors: {actions_code, locators_code}}`.
- **`AutomationStep` ganha dois campos:** `sensitive` (campo de senha; nesse caso o `input_text` não vai para o disco) e `recorded_at`.
- **`session.save`:** recebe `{actions_code?, locators_code?}`.
- **`session.restore`:** não executa nada. Arquivo inválido ou incompatível devolve erro com `data.kind = session_invalid | session_incompatible` e deixa arquivo e memória intactos.
- **`session.import {path}`:** mesma validação do restore.
- **Autosave "desarmado":** um motor recém-iniciado não sobrescreve a sessão anterior antes de `restore`, `import`, `save` ou `codegen.reset`.
- **`codegen.http_contract {event_id}`:** gera, a partir de um evento real do proxy, uma função Python que passa em `ast.parse` e verifica o status e as chaves do JSON. Valores redigidos nunca entram.

### §3 Transporte e espelho

- **Linha de entrada acima do teto:** é descartada inteira até o `\n` e respondida com `INVALID_REQUEST` (`data.kind = message_too_large`), sem quebrar o enquadramento.
- **Saída:**
  - respostas e eventos essenciais nunca são descartados;
  - `stream.frame` é coalescido;
  - `proxy.event` e `analytics.event` têm teto, e o excedente é contado.
- **Notificação nova `engine.backpressure`:** `{channel, dropped, total_dropped}`, no máximo 1 por segundo por canal.
- **Histórico:** `proxy.events` e `analytics.events` ganham `{evicted, capacity}`.
- **`stream.frame`:** `{image_base64, format: jpeg|png, ...}`, JPEG 80 por padrão. `screen.capture` continua em PNG (`png_base64`).

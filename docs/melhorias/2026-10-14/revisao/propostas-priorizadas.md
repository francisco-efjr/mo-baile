# Propostas priorizadas — Mo baile 3.5.1 (fase de leitura do orquestrador)

Data: 14/10/2026 · Escopo: auditoria somente leitura, **nada foi alterado, executado ou medido** (sem `make check`, sem `swift test`; linha de base = Não verificado).
Método: 5 especialistas (arquitetura, segurança, QA, código, UX/a11y) → junção de 25 propostas em 22 itens → 5 validadores independentes (`skeptic-architect`, `finding-validator`, `finding-verifier`, `test-auditor`, `design-evaluator`) que releram as linhas citadas.
Limitação: todos os agentes são do mesmo modelo do autor; é revisão, não validação externa. Comportamento com VoiceOver/Controle Total por Teclado: **não testado**. `apps/tk-legacy` e as 11 branches `worktree-agent-*` não foram revisados (podem já conter parte de M2, M5, M10 e PB6; compare antes de implementar).

Legenda: **V** = confirmado pelo validador · **V\*** = confirmado com ajuste (o ajuste vale mais que a proposta original) · **R** = refutado/rebaixado. Esforço P/M/G.

## Rodada 1 — correções de comportamento (6 itens, dentro do teto de 600 linhas)

| # | Item | Sev. | Esf. | Veredito | Corte mínimo (o que vai de fato) |
|---|---|---|---|---|---|
| 1 | **M1** Escolher o 2º aparelho volta para o 1º | Alta | P/M | V\* | `watcher.set_target(platform, device_id)` (atualiza `current_*` e geração sob lock); `notify` só quando o estado muda. *Só pular `set_platform` não basta*: o vigia deixaria a sessão num aparelho morto. Testes: 2 alvos, select B, 3 polls → segue B, 0 notificações; desconectar B com A presente → volta p/ A, 1 notificação; desconectar A com B selecionado → 0. Evidência: `devices.py:94-98,137`; `server.py:477,507-518`; `EngineSession.swift:1464`. |
| 2 | **M5** Serviços de fundo morrem em silêncio (escuta passiva, analytics) | Alta | M | V | Capturar `TimeoutExpired` em `_teclado_aberto`; rede final em `_on_passive_tap` com `logger.exception` + `passive.skipped`; trocar o `pass` do getevent por `logger.exception`; erro explícito sem Quartz; `start()` do analytics reinicia se o `logcat` morreu. **Não** converter `TimeoutExpired` dentro de `_run_cmd` (chamadores em `adb.py:391,411,425` o capturam). Sem mudar contrato. Evidência: `server.py:1302,1364`; `input_events.py:203-207,296`; `analytics_logcat.py:274-276,390-409`. |
| 3 | **M2** Desmonte do proxy apaga o valor original e esquece a falha | Alta | P | V\* | Só em memória: ler `http_proxy`/`captive_portal_mode` antes de gravar e restaurá-los; conferir com `is_proxy_configured`; falha → lista de desmontes pendentes, retentada quando o vigia vê o serial. O diário em disco foi **rebaixado** (ver "Adiado"). Evidência: `adb.py:378-382,404-412`; `server.py:922-923`. |
| 4 | **M7** Seletor "único" que não é; botão "…campo…" vira digitação | Média | P/M | V | `matches` contado pela mesma expressão que se emite; passo gravado precisa de estratégia de texto até `generate_entry` (consertar só `rank_locators` não basta: o passo usa `resource_id` por prioridade); `is_input` por classe (EditText/TextField/SecureTextField) ou prefixo `== "CAMPO"`. O teste existente `test_hierarchy_codegen.py:114-122` passa *por causa* do bug (confere `unique`, nunca o `value`). Mesmo defeito em `accessibility_id → id` (`server.py:1092`). Fecha a pendência A1. |
| 5 | **M6** Sessão WDA/Appium em cache nunca caduca | Média (Alta no Android/Appium) | P | V\* | Limpar `session_id` em 404/"invalid session id" e refazer **uma vez** (não repetir após 500: toque duplo); limpeza sob `_lock`, comparando com o id lido. `ensure_android_session` também não ressuscita um servidor Appium morto. Evidência: `ios_wda.py:31,142-145`; `appium.py:217,259-261`; `server.py:716-725`. O 404 do WDA é inferido pelo protocolo. |
| 6 | **M12** Comando/código gerado a partir de tráfego não confiável | Média (curl) / Baixa (Python) | P | V\* | **curl**: entre aspas método e nome de header, `'\''` na URL, recusar método fora de `[A-Z]+` (`Exporters.swift:33-35`). **Python**: literal com escape no padrão `repr` (`MirrorRefreshButton.swift:105-110`). Ataque do curl: URL `/a'$(…)'` vinda do app sob teste, "Copiar como cURL", colar no terminal → executa no Mac. O Mo baile nunca executa o snippet Python (`flow.run` usa `codegen.get_steps()`). Teste: `ast.parse` e `sh -n`. |

Cada item leva o teste que falha antes e passa depois (regra do `AGENTS.md`/protocolo). Guardas baratas juntas na mesma rodada: teste do proxy duplicado já corrigido (`server.py:906-911`, sem teste hoje) e teste de `trimTraffic` do analytics.

## Rodada 2 — contrato, observabilidade e CI

| # | Item | Sev. | Esf. | Veredito | Observação |
|---|---|---|---|---|---|
| 7 | **M4 + M3 (parte)** Progresso do fluxo nunca avança; `flow.finished` sem "cancelado" | Alta | M | V (Swift) / R parcial (Python) | A regex `passo\s+(\d+)` (`EngineSession.swift:1565`) só casa em falha; o runner emite `▶ [i/n]` (`flows.py:349`). Teste Swift vermelho no HEAD: `flow.log` real → `currentRunStep == 2` (cuidado: a linha tem prefixo `[HH:MM:SS]`). **O teste Python de cancelamento proposto passaria hoje** (`test_flows.py:175` já cobre com processo real). Para ficar vermelho, "cancelado" precisa entrar no contrato (aditivo; `PROTOCOL_VERSION` segue 2; `make fixtures` + `PROTOCOLO_RPC.md`). Faz junto com `flow.step` (Apêndice A §1). |
| 8 | **M3** Fixtures de notificação capturadas da emissão real | Média | M | V\* | Só 3 de 11 notificações têm fixture. **Fixture montada no gerador não protege** (o payload é literal em `server.py:1419-1421`): capturar o `notify` real com `AdbFalso`; mover structs locais para `EngineDTO`. Teste estático Swift ⊂ contrato e `FakeEngine` estrito passam no HEAD (39 métodos literais ⊂ 55 do contrato): servem de guarda, não de bug. Corrigir a doc (`RODADA_…:78`, `ARQUITETURA.md`). |
| 9 | **M8** Laço de notificações demora; analytics sem teto | Média | P | V\* | `trimTraffic()` em `EngineSession.swift:1542` é seguro e imediato. Tirar `activateDevice` do laço exige cancelar a tarefa anterior a cada `device.changed` e manter ativação + `refreshDevices` na mesma tarefa (`:603-604,780`). É atraso, não perda (buffer `.unbounded`, `EngineClient.swift:88`). Quick win: espelho antes da hierarquia (`:748-756`). |
| 10 | **M10** Log do motor some no Finder; sem `faulthandler` | Média | P | V | `RotatingFileHandler` em `~/Library/Logs/Mo baile/engine.log` (pasta 0700, arquivo 0600) + `faulthandler.enable`. O comentário de `EngineClient.swift:158-166` ("vai para o Console") está errado. Privacidade: o log passa a guardar host/serial/pacote; precisa de uma linha em `SECURITY.md`. Pendência P0 #4. |
| 11 | **M17** CI: contar skips, timeouts, alinhar com `make check` | Alta p/ visibilidade | P | V\* | 26 testes com asserção dependem de sessão gráfica (Accessibility 11, ToolbarLayout 9, Report 4, Palette 2). **Não ligar `MOBAILE_REQUIRE_GUI=1` direto**: primeiro um passo que conte e publique os skips; com uma rodada limpa, ligar o `XCTFail`. Excluir os 24 snapshots (não afirmam nada, de propósito). `timeout-minutes` nos jobs; `fail_under` só depois de medir; bandit do CI cobre só `engine/src` (o `Makefile:56` cobre `apps/tk-legacy`); `test-ui` do Tk não roda no CI. Ajustes do validador: pip-audit não está no `make check`; o OCR real roda no `release.yml`. |
| 12 | **M9** Teste de camadas por AST | Baixa/Média | P | V\* | Hoje a regra é respeitada, então o teste passa já (exceção explícita para `flows.py`). Preferir AST a TID251 (o `ruff.toml` é compartilhado com o Tk). **Não** quebrar o `server.py` (1.806 linhas) agora: risco maior que o ganho. |

## Rodada 3 — UX e acessibilidade

| # | Item | Esf. | Veredito | Observação |
|---|---|---|---|---|
| 13 | **M20** Reduzir movimento num ponto só | P | V | `Motion` lê `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (o `CommandPerformer` não é View); `ScreenCanvas.swift:73,139` pede correção própria. 6 chamadas + 2 literais; 4 delas não estavam na `AUDITORIA_3.5`. |
| 14 | **M22** Desabilitado sempre com o motivo | P | V | 6 locais; `HTTPInspectorView:124` nem tem `.help`. Suposição: `.help` pode não aparecer em `Button` desabilitado (testar). |
| 15 | Contraste do terminal (`TerminalPalette.dim`) + "Código sincronizado" sempre `.ok` | P | V | `#585B70` dá **2,86:1** (escuro) e **2,63:1** (claro); `muted` #7F849C passa (5,17 e 4,75). Indicador falso em `DualEditorPane.swift:132`. |
| 16 | **M18** Gravar e tocar sem mouse | M | V\* | "Tocar" não existe na árvore nem no menu (só "Gravar como Passo"); a premissa da `AUDITORIA_3.5:67` é parcialmente falsa. **Return puro não deve tocar o aparelho**: comandos "Gravar/Tocar no Selecionado" no `CommandRegistry` com `disabledReason`, menu Dispositivo, `accessibilityAction` do espelho. Revê `FLUIDEZ_3.5:101`. |
| 17 | **M19** Menu de barra completo (13 ações) | P | V\* | Contagem confirmada. Trocar ⌥1/⌥2 revê decisão registrada (`FLUIDEZ_3.5:61-62`): polimento, fora. ⌘. duplicaria o do sheet. |
| 18 | **M21** Anunciar fim do fluxo, erros e fim da gravação | M | V\* | Só esses três; os 65 `statusMessage` e o `$/progress` geram ruído. O `.help` já mostra o texto inteiro. |

## Adiado, rebaixado ou descartado

| Item | Motivo |
|---|---|
| **M13** Redação por lista exata | V, Média-Baixa, M. Privacidade, sem atacante. Casar por *token* (camelCase/`_`), não por substring (`passage`, `monkey`). `accessToken`/`refreshToken` já casam. Analytics sem redação nenhuma. Entra quando houver capacidade; teste de 20 variações. |
| **M2 diário em disco** | Rebaixado: a queda do app já é coberta por `serve_forever`→`shutdown()` e por `proxy.stop` no `restore` (`EngineSession.swift:520-524`). Sobra SIGKILL/queda da máquina. Exige **ADR** (primeiro estado persistido do motor) e validar `host:porta`, `null`/`:0`, mesmo serial, `O_NOFOLLOW`. Recomendo adiar. |
| **M14** Artefatos sensíveis | R→endurecimento, Baixa. Tudo em pastas privadas do usuário; sobra o clipboard. Limpar `flow_runner_*` velhos na partida e rotacionar o log do Appium. |
| **M15** `package` sem allowlist | **Refutado como vulnerabilidade**: o front nunca envia `package`; o destino já é o shell do aparelho. Allowlist barata, sem prioridade. |
| **M16** Python/motor/bundle | R→endurecimento. Só vira ataque para quem já controla a conta. Hardened runtime e `--deep` só com Developer ID (e cuidado com o `verify-native`). Barato: `-I` + cwd fixo + hash do binário do OCR. |
| Gravação Android "MP4 fica no aparelho" | Refutado em parte: `stop()` puxa e apaga (`screen_recorder.py:194,200`). Sobra: o botão segue "gravando" após os 180 s. |
| **M11** fila do proxy | Resolvido: fila limitada (4000), **ninguém a drena no motor**; retenção fixa dos primeiros 4000 eventos (dezenas de MB no caso típico). Baixa. Não remover a fila (o Tk a usa). |
| Texto 9,5–10 pt, alvos 12×16, PT-BR inconsistente | Polimento; backlog. |

## Decisões que são suas

1. **Contrato:** aceitar `cancelled` em `flow.finished` e `flow.step` (aditivo, `PROTOCOL_VERSION` 2). Destrava o item 7.
2. **ADR do diário em disco do proxy:** recomendo adiar e entregar só o corte em memória (item 3).
3. **`engine.info.*_running` × "a interface nunca faz polling":** se for exposto, por notificação (entra no item 8); senão fica fora do corte do item 2.
4. **M18/M19:** rever decisões de `FLUIDEZ_3.5`/`AUDITORIA_3.5` (árvore como alternativa ao clique; ⌥1/⌥2).
5. **CI:** staged (contar → depois exigir). Pode deixar o CI vermelho no runner macos-26 se não houver sessão gráfica (Suposição).
6. **Política de log do motor** (item 10): linha em `SECURITY.md`.

## O que a implementação exigirá (AGENTS.md)

Cada item toca `engine/src` ou `apps/MoBaile`: `make check` + `make test-swift` antes de cada commit; `VERSION`/`CHANGELOG`/`make fixtures`/tag (SemVer: correções = patch; contrato aditivo = minor); `make update-native` com o app **fechado** e o OK do `verify-native` na entrega; nunca tocar o `Mo baile.app` Tkinter. Árvore atual tem 3 caminhos não rastreados (`docs/SESSAO_2026-10-08_REDESENHO_3.0.md`, `docs/design/telas/arquivo-2.x/`, `docs/research/agent-device/`): resolver antes de criar a branch.

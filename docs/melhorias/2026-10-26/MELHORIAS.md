# Melhorias de 26/10/2026 — Rodada 3 (versão 3.12.0)

Rodada orquestrada pelo protocolo [Brain of Agent](https://github.com/francisco-efjr/brain-of-agent)
(`ORCHESTRATOR.md`, modo melhoria §3.1), na branch local
`melhoria/2026-10-26-rodada3`, a partir de `a74407c` (3.11.0). Sem push.

## Resumo

Seis especialistas leram o sistema em paralelo (arquitetura, plataforma macOS,
QA, segurança, código e UX) e trouxeram 29 propostas, com o backlog anterior
reconferido no código de hoje ([`revisao/`](revisao/)). Três validadores
independentes (segurança, código e arquiteto cético) fizeram a contraprova
das candidatas. Nenhuma foi refutada, e várias mudaram de desenho. O corte
ficou em seis melhorias ([`CONTRATO.md`](CONTRATO.md)), implementadas uma por
vez, cada uma com teste que falha antes e passa depois. Todo commit passou por
revisão independente, e todos os ajustes pedidos entraram em commits próprios.

Duas correções de segurança e de distribuição foram verificadas por execução
nesta máquina antes de entrar no corte:
- o Appium 3.2.2 escuta por padrão em `0.0.0.0`;
- o app instalado tinha 8 pastas `__pycache__` dentro do bundle e o
  `codesign --verify --deep --strict` falhando.

## Linha de base × depois

| Verificação | Antes (`a74407c`) | Depois (`6f472d2` + release) |
|---|---|---|
| Motor (`pytest`) | 679 passam, 839 subtests | 725 passam, 839 subtests |
| UI Tkinter | 20 | 20 |
| Harness do QA | 11 | 11 |
| Fluxos de QA com aparelho falso | 19 / 31 / 35 / 34 / 26 | 19 / 31 / 35 / 34 / 26 |
| `swift test` | 363, 0 falhas, 27 pulados | 393, 0 falhas, 27 pulados |
| ruff, bandit, `fixtures-check`, versão | ok | ok |

Os 27 pulados são os mesmos de antes: dependem de sessão gráfica ou de
aparelho. A proposta QA-1 trata deles e ficou para a próxima rodada.

Diff de produção, sem testes, docs e fixtures: **+867 / −156**. Passou do teto
de cerca de 600 linhas do protocolo. O MEL-5 (log do motor, +287) e o MEL-3
(contrato e front do andamento, +205) respondem por mais da metade.

## Melhorias

| ID | Especialista | Problema (evidência de origem) | Mudança | Antes → depois | Prova | Commit |
|---|---|---|---|---|---|---|
| MEL-2 | Plataforma | `EngineClient.swift:109-119` e `tools/verify_native_app.sh:151` rodavam o motor do bundle gravando `__pycache__` dentro dele | `PYTHONPYCACHEPREFIX` em `~/Library/Caches/Mo baile/pycache`; `PYTHONDONTWRITEBYTECODE=1` no verify e no `instalar-mac.sh`; o verify confere o selo antes e depois do handshake | selo quebrado no primeiro uso → selo íntegro | XCTest `testMotorNaoGravaBytecodeNaRaizDoCodigo` (vermelho: 2 pastas `__pycache__`); bundle falso assinado no scratchpad (handshake antigo: 8 pastas e selo inválido; novo: OK duas vezes) | `62948cb` |
| MEL-1 | Segurança | `adapters/appium.py:134-135` subia o Appium sem `--address`; padrão `0.0.0.0` sem autenticação | `--address 127.0.0.1 --port <APPIUM_URL>`; não sobe com host remoto ou porta 0; `logs_dir()` (0700, sem symlink); log do Appium 0600 | qualquer máquina da rede comandava o aparelho → só loopback | 15 testes (`TestEnderecoDoServidor`, `TestPastaDeLogs`; 14 vermelhos antes) | `635ea74`, ajuste `862d2d6` |
| MEL-4 | Segurança | `ios_cfnetwork.py:317-331` (Set-Cookie em dicionário em claro), `flows.py:146-176` (script com texto digitado sobra após SIGKILL), `adb.py:311-313` (timeout leva o texto ao log), `maestro_flow.py` (mensagem repete `${VAR}`) | máscara com estado e forçada no disco; varredura de órfãos com mais de 10 min; log só com tipo e tempo; máscara na mensagem e no passo que falhou | quatro vazamentos → nenhum nos testes | 4 testes vermelhos antes, um por item, mais casos de borda da revisão | `da9016f`, ajuste `855aadb` |
| MEL-3 | Código, QA, arquitetura | regex `(?i)passo\s+(\d+)` (`EngineSession.swift:1738`) só casava na falha; parar virava FAIL (`server.py:1840-1848,1974-1979`) | `flow.step {index,total}` por callback `on_step` nos dois runners (marcador privado no stdout do runner, só com `MOBAILE_STEP_MARKER=1`); `cancelled` em `flow.finished`; helper único no servidor; front sem regex, parada → `.idle` + `STOP` | barra parada → avança; parar = FAIL → "Pronto" | 5 pytest (runner real e Maestro) e 12 + 3 XCTest; fixtures geradas pelos helpers reais | `0367034`, ajuste `855aadb` |
| MEL-5 | Plataforma | `server.py:2334-2340` só no stderr; `EngineClient.swift:162-171` perdia pedaço com UTF-8 cortado e dizia ir para o Console | `engine.log` 0600 com rotação e redação; `engine-faults.log` (faulthandler); `log_path` no hello e no info; stderr lido por linha (teto de 64 KB); `os.Logger` só no ciclo de vida | log perdido ao abrir pelo Finder → arquivo persistente | 10 pytest e XCTest do separador de linhas e da mensagem de queda | `22e27e7`, ajustes `855aadb` |
| MEL-6 | QA, código | `analytics_logcat.py:398-411` sem try por linha (thread morria com JSON não-objeto ou byte inválido); `analytics.event` e `runLog` sem teto no front | try por linha, `errors="replace"`, `isinstance(dict)`; `trimTraffic` em analytics; `runLog` em 5000; auto-scroll pela última linha e tempo pelo início real | escuta muda → segue; listas sem fim → com teto | 3 pytest e 3 XCTest (vermelhos antes) | `4142699`, ajuste `6f472d2` |

## Revisões independentes

| Commit | Revisor | Veredito | Ajustes que entraram |
|---|---|---|---|
| `62948cb` MEL-2 | code-reviewer + release-readiness | aprovar | só nota de CHANGELOG (primeira abertura mais lenta) |
| `635ea74` MEL-1 | patch-reviewer | aprovar com ressalvas | `fchmod` recusado não derruba a subida (`862d2d6`) |
| `da9016f` MEL-4 | patch-reviewer | aprovar | duas variantes de dicionário e nota do log antigo em `SEGURANCA.md` (`855aadb`) |
| `0367034` MEL-3 | code-reviewer + api-contract | aprovar | marcador só com `MOBAILE_STEP_MARKER`; `flow.step` só com execução em curso (`855aadb`) |
| `22e27e7` MEL-5 | code-reviewer + patch-reviewer | aprovar | teste do teto de 64 KB; traceback do parser sem trecho do bloco (`855aadb`) |
| `4142699`, `855aadb` | code-reviewer | ajustar | auto-scroll e tempo do resumo com o teto (`6f472d2`) |

Os revisores são do mesmo modelo dos autores, então a independência é parcial.
Recomendo uma leitura humana do diff.

## Propostas descartadas ou adiadas na contraprova

- Passar os passos do runner pelo stdin (MEL-4b): a varredura de órfãos é a
  menor correção suficiente, e o stdin traria risco ao modo exportado e ao Tk.
- Tirar os `await` do laço de notificações e inverter espelho e hierarquia
  (metade do CODE-2): o risco de corrida é alto e não há medição. Volta com
  evidência.
- `result` como enum em `flow.finished` (ARQ-1): duplicaria `success`. Ficou o
  booleano `cancelled`.
- ADR 0006 para o log em disco: log é diagnóstico, não estado. Bastou uma linha
  em `SEGURANCA.md`.
- M13 "redação por substring": a redação já é por igualdade exata
  (`redaction.py:72-73`). O problema real é o oposto, a falta de tokenização,
  que virou a proposta SEG-4.

## Decisões pendentes (tomadas pelo orquestrador, revisáveis)

- **D-A.** Parada → `.idle` com `STOP`, sem caso novo em `RunState`. Na parada,
  o sheet marca como aprovados os passos anteriores ao atual.
- **D-B.** `flow.step` e `cancelled` no contrato (aditivos).
- **D-C.** Log do motor em disco (0600/0700, rotação, redação).
- **D-D.** Sem Appium próprio quando `APPIUM_URL` aponta para fora do loopback
  ou para a porta 0.
- **D-E.** O log bruto do CFNetwork ignora `MOBAILE_REDACT=0`.
- **Para o dono:**
  - conferir com `lsof -nP -iTCP:8100 -sTCP:LISTEN` se o WDA no simulador
    escuta em toda a rede (o `--address` não cobre o WDA nem o MJPEG);
  - decidir se apaga os logs antigos `~/Library/Logs/mobaile-appium.log` (0644)
    e, se existir, `~/Library/Logs/MoBaile/`.

## Incidente registrado

Na primeira execução do teste vermelho do MEL-4(a), o código ainda gravava no
caminho antigo e criou `~/Library/Logs/MoBaile/cfnetwork-diagnostics.log` com
blocos sintéticos. O implementador apagou o arquivo e a pasta, alegando que a
pasta não existia antes, pela data de criação. O orquestrador não tem como
confirmar esse estado anterior. Desde o MEL-1, todo teste usa
`MOBAILE_LOG_DIR` temporário, e o portão final confirmou que nenhum teste
escreve em `~/Library/Logs`.

## Próximos passos (com a proposta pronta em `revisao/`)

1. QA-1: o CI passa a contar os testes pulados e ganha `timeout-minutes` em
   todos os jobs.
2. UX-4: Reduzir Movimento num ponto só. UX-3: motivo em todo controle
   desabilitado (13 pontos).
3. `ios_cfnetwork._reader` com o mesmo `"status" in payload` sem
   `isinstance(dict)` do MEL-6. É uma linha.
4. QA-3: fixtures de todas as notificações a partir da emissão real.
   QA-4: fuzz dos parsers.
5. SEG-4: redação por token. SEG-5: registro do que o motor muda no aparelho.
6. ARQ-2: `storage.py` e ADR do estado em disco. ARQ-3: saúde do motor por
   notificação, no lugar do polling de 5 s. ARQ-4: `server.py` por coesão.
7. PLAT-3: notificação de operação longa. PLAT-4: release com o verify.
   PLAT-5: verify completo.
8. UX-1 (gravar sem mouse), UX-2 (anúncios do VoiceOver), UX-5 (contraste
   do terminal), CODE-3/4/5.

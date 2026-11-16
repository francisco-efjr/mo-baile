# Rodada 12/11/2026: área Execução, fase B1 (3.23.0)

## Resumo

O dono pediu para o Mo baile importar o projeto de automação dele, entender o `main`
(`init(config_*)`, `test_suite_*`, `executar(squad, feature)`), checar o que falta e
rodar com visibilidade, como no PyCharm, tudo local e com vídeo. O estudo
(`docs/research/execucao-projeto-externo-pycharm.md`) propôs 4 opções. O dono escolheu
a **Opção B, fase B1**: abrir o projeto, ler o `main` sem executar, rodar o doctor e
executar com console ao vivo, vídeo e resultado. A árvore de steps ao vivo, os
capítulos no vídeo e o relatório HTML ficam para B2–B4.

Orquestração brain-of-agent:
- consultor-pesquisador (estudo);
- dev do motor;
- dev do front;
- 3 revisores independentes: revisor de código do motor, auditor de segurança do motor
  e revisor de código do front.

Antes da rodada, a 3.21.1 e a 3.22.0 (motion), que estavam instaladas sem commit, foram
commitadas a pedido do dono (`91589eb`, tag `v3.22.0`).

## Linha de base × depois

| | 3.22.0 (`91589eb`) | 3.23.0 |
|---|---|---|
| Testes do motor | 919 (934 subtests) | 1080 (963 subtests) |
| UI Tk / gate de QA / QA | 20 / 11 / 5 fluxos | 20 / 11 / 5 fluxos |
| `make test-swift` | 491, 29 pulados | 536, 29 pulados, 0 falhas |
| ruff, bandit, fixtures | ok | ok |

## Melhorias

| ID | Especialista | Mudança | Como foi provado | Commit |
|---|---|---|---|---|
| B1-1 | dev motor | Registro de projetos autorizados (só leitura, sem gravar na pasta do dono), análise do `main` por `ast`/`tokenize`, configs, features e cenários; projeto de exemplo no formato do dono | testes de análise e hash da pasta antes e depois | `3883906` |
| B1-2 | dev motor | Doctor com 11 checagens e progresso | testes unitários e de contrato | `2ce543b` |
| B1-3 | dev motor | `run.start/stop/status`: subprocesso em grupo próprio, máscara, resumo do behave, vídeo, pasta da execução, trava do aparelho | behave 1.2.6 real: passed, failed e indeterminate; netos encerrados | `f279bb9` |
| B1-4 | dev motor | Interpretador pelo SDK do PyCharm (`jdk.table.xml`), escolha manual (`project.configure`) e candidatos da máquina | testes com pasta base injetada | `6b31528` |
| B1-front | dev front | Área Execução ⌘6: projeto, doctor, console (`NSTextView`, teto de 5.000 linhas), Rodar/Parar, confiança, banner | 32 testes; capturas em claro, escuro, 980×600 e 1280×720 | `76f01d2` |
| B1-5 | dev motor | Correções da revisão: CR-01..11 e SEC-B1-01..10 (detalhe abaixo) | 47 testes de regressão a partir das provas dos revisores | `2e4cd24` |
| B1-6 | dev motor | Vídeo começa quando o servidor do scrcpy conecta; `video_started_at` no `resumo.json` | 4 testes; 0,43 s no emulador | `ca9cf97` |
| B1-front-fix | dev front | Correções FR-01..11 | 13 testes novos; capturas regeneradas | `6b7ae91` |

Correções de destaque da revisão:
- **CR-01:** falso "passou" quando o `after_all` do behave falhava.
- **CR-02 / SEC-B1-01:** o doctor rodava o Python do projeto antes da confiança.
- **SEC-B1-02 / CR-05 / CR-08:** dava para driblar o bloqueio de nuvem.
- **CR-03:** a trava do aparelho ligava tarde.
- **SEC-B1-06:** leitura com troca de pasta por link no meio.
- **FR-01:** o projeto ficava travado sem análise depois de sair da aba.

## Decisões do orquestrador

- **D-O1:** o doctor não roda o Python do projeto sem confiança. A nova RPC
  `project.trust` marca o projeto como confiável.
- **D-O2:** a confiança fica presa ao interpretador, à entrada, à pasta de trabalho e
  aos nomes das envs. Se qualquer um mudar, ela cai.
- **D-O3:** `hub_state` pode ser `local`, `cloud` ou `unknown`. `cloud` é sempre
  recusado. `unknown` pede `allow_unknown_hub`, e o front mostra a confirmação.
- **D-O4:** `HOOK-ERROR`, `CLEANUP-ERROR` ou erros no resumo dão `failed`. Palavra
  desconhecida no resumo dá `indeterminate`.
- **D-O5:** o aparelho diferente do `udid` literal da config é recusado. A trava passa a
  cobrir também `simulators.shutdown`, `wda.start` e `scrcpy.start`, e liga antes de
  fechar a sessão do Appium.
- **D-O6:** `$PROJECT_DIR$` é expandido nas envs.
- Decisões dos devs: D-1..D-12 em `revisao/dev-motor.md` e D-F1..D-F10 em
  `revisao/dev-front.md`.

## Verificação de ponta a ponta (motor real)

Feita no `emulator-5554` (Pixel_9, iniciado pelo orquestrador), com o projeto de exemplo
copiado para fora do repositório:
- `project.open` → `configure` (`/usr/local/bin/python3`) → `trust` → `doctor` → `run.start`
  com vídeo;
- resultado: `passed`, 3 resumos, 5 cenários e 15 steps;
- `video.mp4` em H.264 1080×2424;
- hash da pasta do projeto igual antes e depois.

O moto g55 físico não foi tocado.

## Decisões pendentes do dono

1. **Rodar contra o projeto real.** Recomendo abrir a pasta real na área Execução e
   comparar o interpretador, a config e as features com o PyCharm antes da B2.
2. **FR-05 completo.** Hoje o front relê o projeto antes de mostrar o diálogo de
   confiança. A versão completa manda ao motor o que o diálogo mostrou. Ela muda o
   contrato e ficou para a B2.

## O que ficou de fora (próximos passos)

- **B2:** shim de eventos (formatter e hooks do behave via `PYTHONPATH`), com árvore
  Feature > Cenário > Step ao vivo.
- **B3:** a árvore no front.
- **B4:** capítulos WebVTT a partir do `video_started_at`, print do step que falhou,
  relatório HTML no padrão do Mo baile e `junit.xml`.
- Limitações conhecidas, registradas em `revisao/dev-motor.md`:
  - sem run configuration que case com a entrada, vale a primeira;
  - netos que não seguram o pipe sobrevivem ao fim natural;
  - o scrcpy não grava quadro repetido, então o vídeo de tela parada é curto e o
    alinhamento pelo tempo fica para a B4.
- Opção de liberar nuvem nos Ajustes: fora do escopo da B1.

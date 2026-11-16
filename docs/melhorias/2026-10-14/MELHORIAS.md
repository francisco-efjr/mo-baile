# Melhorias de 14/10/2026 — Rodada 1 (versão 3.5.2)

Rodada orquestrada: fase de leitura com 5 especialistas, contraprova de 5
validadores independentes e revisão independente do diff. Propostas e vereditos
em [`revisao/propostas-priorizadas.md`](revisao/propostas-priorizadas.md).

## Resumo

Seis correções de comportamento, uma por commit, cada uma com ao menos um
teste que falhava antes e passa depois (há também testes de caracterização,
que já passavam e fixam o comportamento: `test_sem_valor_anterior_apaga_como_antes`,
`test_desmonte_bem_sucedido_nao_deixa_pendencia`, `test_erro_do_servidor_nao_repete_o_toque`,
`testMetodoHTTPComumFicaSemAspas`). Nenhuma mudança de contrato RPC
(`PROTOCOL_VERSION` segue 2; só a versão aparece nas fixtures).

## Linha de base × depois

| Verificação | Antes (3.5.1) | Depois (3.5.2) |
|---|---|---|
| Motor (`pytest`) | todos passam (rodado com `-q`, sem contagem registrada; `def test` conta 480) | 528 passam, 238 subtests (`def test` conta 528) |
| Fluxos de QA (sem device / iOS / Android / HTTPS / relatório) | 19 / 31 / 35 / 34 / 26 | 19 / 31 / 35 / 34 / 26 |
| `swift test` | — | 298 testes, 0 falhas, 26 pulados (sessão gráfica; ver M17) |
| `ruff` | ok | ok |
| `make fixtures-check` | ok | ok |

A linha de base do motor foi rodada na `efcc5f9` antes de qualquer mudança, pela própria sessão, e não ficou registrada no repositório: é afirmação da sessão, não artefato.

## Melhorias

| ID | Especialista | Problema | Mudança | Prova | Commit |
|---|---|---|---|---|---|
| M1 | Arquitetura | O vigia elegia sempre `targets[0]`; escolher o 2º aparelho voltava ao 1º (`devices.py`, `server.py`) | `DeviceWatcher.set_target`; o vigia só reelege se o alvo some | `test_devices.py::TestAlvoDaSessao`, `test_selecao_aparelho.py` | `32ec18e` |
| M5 | Código | Escuta passiva e analytics morriam sem aviso (`server.py`, `input_events.py`, `analytics_logcat.py`) | `TimeoutExpired` tratado, rede final por toque, `AdapterError` sem Quartz, analytics religa | `test_servicos_de_fundo.py` | `a690f21` |
| M2 | Arquitetura/Segurança | O desmonte do proxy apagava o valor original e esquecia a falha (`adb.py`) | restaura `http_proxy`/`captive_portal_mode`; pendência retentada | `test_proxy_restaura_aparelho.py` | `0a47356` |
| M7 | Código/QA | Seletor "único" ambíguo; botão "campo" virava digitação (`codegen.py`) | xpath de texto, `matches` honestos, `locator_value` no passo | `test_seletor_unico.py` | `a771514` |
| M6 | Código | Id de sessão WDA/Appium nunca caducava | limpa o id e reabre uma vez | `test_sessoes_caducas.py` | `bb2c6d8` |
| M12 | Segurança | cURL/Python gerados sem escape do tráfego (`Exporters.swift`) | `shellQuoted`, `pythonStringLiteral` | `ExportersEscapeTests.swift` | `01113a9` |
| REV-1…5 | Revisão independente | Achados do revisor | ver commit | testes acrescentados | `5c85125` |
| A-1…A-6 | Auditoria de 15/10 | 2 regressões do M7, corrida no desmonte do proxy ao encerrar, retentativa a cada varredura, status do Tk | ver [`revisao/auditoria-2026-10-15.md`](revisao/auditoria-2026-10-15.md) | testes acrescentados | commits seguintes |

## Propostas descartadas ou rebaixadas na contraprova

- M15 (`package` sem allowlist): refutada como vulnerabilidade.
- M2 diário em disco, M14, M16: rebaixadas a endurecimento. Ficam fora.
- M9 quebrar o `server.py`: risco maior que o ganho agora.

## Decisões pendentes

1. Contrato: aceitar `cancelled` em `flow.finished` e `flow.step` (M4/PB6, Rodada 2).
2. ADR do diário em disco do proxy: recomendado adiar.
3. `*_running` para a interface: por notificação, se for exposto.
4. Rever as decisões de `FLUIDEZ_3.5` e `AUDITORIA_3.5` sobre gravar/tocar pelo teclado (M18).
5. CI do GUI em duas etapas: contar os skips e depois exigir (M17).
6. Linha em `SECURITY.md` para o log do motor em arquivo (M10).

## Limites

- Os testes que dependem de sessão gráfica (26 no `swift test`) pulam fora de
  uma sessão com janela; nesta máquina o `AccessibilityInspector` só roda com
  interface. Não contam como aprovados.
- Nada foi exercitado com um aparelho real: o motor foi testado com adb, WDA e
  Appium falsos. Rode o roteiro manual de [`docs/QA.md`](../../QA.md) antes de
  usar em aparelho físico.
- Revisão por agentes do mesmo modelo que escreveu o código: uma pessoa deve
  ler o diff (`git diff efcc5f9..HEAD`).
- Persistem as pendências da Rodada 2 e 3 (`revisao/propostas-priorizadas.md`).

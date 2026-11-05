# Rodada 03–04/11/2026: Page Objects no modelo do PyCharm, perfis de desempenho e nome do relatório (3.17.0 e 3.17.1)

Rodada orquestrada pelo protocolo brain-of-agent (modo melhoria, §3.1).
Branch: `melhoria/2026-11-03-pycharm-desempenho`, criada a partir de
`melhoria/2026-10-28-automacao-sync` (3.16.0).

Uma sessão paralela, a da fase 2 da automação, juntou esta linha à branch
`melhoria/2026-11-04-automacao-fase2` antes das correções R1–R6 da revisão de
desempenho e publicou a 3.17.0 (tag `v3.17.0`). Esta branch juntou de volta a
fase 2 e publica as correções como **3.17.1**, com a tag `v3.17.1`, sem push.
Ela contém tudo: a fase 2 da automação, Page Objects, desempenho com R1–R6 e
REL-1.

## Resumo

O dono fez três pedidos:
1. aba Page Objects igual ao PyCharm, com o editor recebendo os caracteres do
   mesmo jeito;
2. arquitetura que use o computador, com uma opção leve quando ele estiver
   sobrecarregado;
3. o HTML do relatório com o nome
   `relatorio_{projeto}_{ios|android}_{dd-mm-aaaa}.html`.

Foram três pesquisadores em paralelo, dois desenvolvedores em worktrees
isolados e dois revisores independentes. Cada revisão voltou para o
desenvolvedor da trilha corrigir.

## Plano executado

| Papel | Base (brain-of-agent) | Entrega |
|---|---|---|
| Pesquisador de UX (PyCharm) | `ux-ui-design:ux-researcher` | `docs/research/pycharm-page-objects.md` |
| Analista de desempenho (nosso contexto, medido) | `sre-observability:perf-analyst` | `revisao/perf-contexto.md` |
| Pesquisador de mercado (modo leve em nichos parecidos) | `consultor-pesquisador` + `sre-observability` | `docs/research/modo-leve-desempenho.md` |
| Dev Page Objects | `ux-ui-design:ui-designer` + `engineering-lifecycle` | `revisao/spec-page-objects.md`, `revisao/dev-page-objects.md` |
| Dev desempenho | `engineering-lifecycle` + `sre-observability` | `revisao/dev-desempenho.md`, `tools/bench_stream.py` |
| Revisor de Page Objects | `code-quality-refactoring:code-reviewer` | R-01..R-14, todos tratados |
| Validador de desempenho | `sre-observability:perf-analyst` + `code-reviewer` | R1..R6, todos corrigidos; números reproduzidos com ~10% de diferença |
| Orquestrador | — | REL-1, integração, versão, empacotamento |

Lacuna do registro de conhecimento: não há tag de desempenho para desktop. A
`performance-web` é só web, então usei os fundamentos de `sre-observability`.

## Linha de base × depois

| Suíte | Antes (3.16.0) | Depois (3.17.1) |
|---|---|---|
| Motor (pytest) | 793 | 896 (inclui os testes da fase 2 da automação) |
| Swift (`make test-swift`) | 408 (27 pulados) | 479 (29 pulados) |
| UI Tk / QA de regressão | 20 / 11 | 20 / 11 |
| `make qa` (5 cenários) | ok | ok (relatório com 2 checagens novas do REL-1) |
| Lint, segurança, fixtures | ok | ok |

Desempenho do espelho na bancada sintética (`tools/bench_stream.py`): tela
parada, 60 s, mediana de 3, CPU do motor somada à dos filhos. Rótulo:
Medido; o revisor reproduziu os números.

| Cenário | Antes | Depois |
|---|---|---|
| Completo | 19,9% | 6,8% |
| Equilibrado | — | 2,3% |
| Leve | — | 1,2% |
| Janela oculta | 19,9% | 0,1% |

Editor com um `.py` sintético de 1 MB que tem docstring (Medido, build
debug):

| Ação | Antes | Depois |
|---|---|---|
| Carga | 5.356 ms | 736 ms |
| Tecla comum | 7.075 ms | 12 ms |
| Mover o cursor | 97 ms | 1,7 ms |
| Tecla de aspas | 6.930 ms | 194 ms |

## Melhorias

| ID | Problema | Mudança | Como foi provado | Commits |
|---|---|---|---|---|
| PO-1 | Colar CRLF gravava `0D 0A`; havia substituições do macOS ligadas; o soft wrap separava o recuo do código | Entrada literal, CR/CRLF → LF, save em UTF-8 sem BOM, sem soft wrap | Testes T1–T4 byte a byte | `15c81d7` |
| PO-2 | NBSP, ZWSP e bidi ficavam invisíveis | Etiquetas como no PyCharm; a cópia leva o caractere real | Testes de cópia e de acessibilidade | `de271c4` |
| PO-3 | O editor não seguia o PyCharm (SF Mono 11,5; o realce só rodava ao sincronizar) | JetBrains Mono 13 / 1,2, esquema PyCharm, linha atual realçada, realce incremental | `EditorEsquemaTests`, bench do R-06 | `6c7e600`, `a0d2794` |
| PO-4 | O rodapé mostrava "Código sincronizado" fixo | Linha:coluna, LF, UTF-8, 4 espaços, Python do motor e "salvo às" | Testes do rodapé | `6c1434d` |
| PO-5 | A aba não tinha visão de projeto | Faixa de tool windows, painel Projeto, abas, `workspace.*` com travas | Testes de contrato e de segurança | `0309c0c`, `366d78a`, `f979d07` |
| PERF-1 | O espelho capturava com a janela oculta | `stream.pause`/`resume` pela oclusão da janela | Testes, bancada (19,9% → 0,1%) | `337863c`, `3332c34`, `9c5a245` |
| PERF-2 | A captura nunca descansava | Cadência ociosa; o toque acorda o espelho; o laço descansa | Bancada | `8d63f1b` |
| PERF-3 | Não havia política de consumo | Governador com histerese no motor e RPC `perf.*` | Tabela de testes do governador | `35bfcf5`, `94dac6a`, `011ba4b` |
| PERF-4 | Nenhum sinal do macOS era lido | `PerfSensors`, vidro sólido e animação simples no Leve, freio local | `PerfTests`, `GlassTests` | `9a03e0e`, `2d9ffd1`, `76b4493` |
| PERF-5 | Não havia como escolher o perfil | Ajustes › Desempenho, badge e comando na paleta | Testes da interface | `04bd5e3` |
| REL-1 | O HTML saía sempre como `relatorio_auditoria.html` | `relatorio_<projeto>_<ios\|android>_<dd-mm-aaaa>.html` | pytest, QA fluxo 5, teste Swift | `d0c0070` |

O teto de diff do protocolo (~600 linhas de produção) foi ultrapassado nas
duas trilhas: cerca de 1.760 linhas em Page Objects e cerca de 1.000 em
desempenho, contando comentários. Ficou registrado aqui e nos relatórios dos
desenvolvedores.

## Decisões tomadas pelo orquestrador (para o dono revisar)

- **D-1:** o editor usa por padrão a JetBrains Mono 13 e as cores do PyCharm.
  Ajustes › Geral › Cores do editor volta para a paleta do app. A cor do
  número de linha foi clareada para `#61666E`, com contraste de 3:1.
- **D-2:** nenhum atalho existente mudou; ⌘E continua sendo o Espelho. Os
  comandos do PyCharm que conflitam ficam na paleta.
- **D-3:** ao salvar, o texto não é alterado: não corta espaços no fim da
  linha nem força a quebra final.
- **D-4:** a árvore mostra só `pages/`, `locators/` e `flows/`.
- **D-5:** não há vidro no editor nem na árvore. O espelho e a hierarquia
  ficam onde estavam.
- **D-6:** nenhum perfil reduz o histórico já capturado de rede e analytics.
- **D-7:** um Mac de 8 GB começa no Equilibrado quando o modo é Automático.
- **D-8:** a cadência ociosa vale também no Completo. Uma mudança de tela
  sem toque aparece até 0,5 s depois.
- **Versão:** 3.17.0 (minor), porque a interface mudou só numa aba e não
  considerei redesenho do app inteiro. As correções da revisão saem na
  3.17.1.

## Decisões pendentes do dono

1. **Mac Intel:** hoje o binário é só arm64 e o app não abre em Intel. Para
   suportar, é preciso um binário universal em `package_macos_app.sh`.
2. **Meta do modo leve:** foi suposta em ≤ 10% de um núcleo com a tela
   parada. Precisa ser medida num M1 de 8 GB com
   `tools/bench_stream.py --fonte ios`.
3. **Cores do PyCharm no modo claro:** foram feitas de memória e falta
   conferir com o `expUI_lightScheme.xml`.
4. **Oráculo T1:** colar o texto T1 no PyCharm real e comparar com `xxd`.
   Hoje os bytes testados vêm da previsão da pesquisa.

## Próximos passos

- Realce em segundo plano por blocos visíveis: a aspa num arquivo de 1 MB
  ainda leva 0,2 s.
- Preservar o ⌘Z e a rolagem das abas ao trocar de área do app.
- Itens P1 que faltam: Buscar em Tudo (⇧⇧), histórico de navegação, ⌘L,
  breadcrumbs, ⌘F no editor e `workspace.changed`. Os P2 estão em
  `pendentes/page-objects-proximos-passos.md`.
- Desempenho:
  - pausar o leitor MJPEG do WDA;
  - scrcpy pelo perfil;
  - slot único de quadro (F4);
  - teto de memória do proxy por bytes (F7);
  - consumo medido como entrada do governador.
- Validar com o app aberto: dormir e acordar o Mac, troca de Space, Android
  real e a CPU do próprio app Swift.

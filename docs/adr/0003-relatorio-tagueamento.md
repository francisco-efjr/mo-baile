# ADR 0003 — Aba Relatório: o `tag_audit` como núcleo, dentro do motor

Data: 2026-10-08
Status: aceito

## Contexto

A auditoria de tagueamento era feita fora do Mo baile, em três passos manuais:

1. capturar os eventos na aba Analytics e exportar `log_obtido.json`;
2. rodar o `tag_audit` (projeto `bold-kepler`, Python com Pydantic e Typer)
   contra a spec-modelo dos cards do Figma;
3. abrir o board Excalidraw, o HTML, o Markdown e o TSV que ele gera.

O `tag_audit` já era determinístico e testado (spec-modelo com placeholders,
expansão card × fluxo × variação, casamento pelo disparo mais recente, "fora da
spec", OCR dos prints com o Vision do macOS). O que faltava era ele estar onde a
captura acontece.

## Decisão

Uma área nova na barra lateral, **Relatório**, com o `tag_audit` como núcleo,
seguindo a regra do ADR 0001: a lógica vai para o motor, a interface só escolhe
arquivos e mostra o resultado.

### Motor

| Peça | Onde | Origem no `tag_audit` |
|---|---|---|
| Modelos e validação da spec | `domain/report.py` | `core/models.py`, `parsers/spec_template.py` (Pydantic virou dataclass) |
| Regras puras | `services/report/rules.py` | `core/normalizers.py`, `parsers/spec_template.py`, filtro de ruído de `parsers/log_parser.py` |
| Leitura do log | `services/report/firebase_log.py` | `parsers/firebase_log.py` |
| Auditoria por variação | `services/report/audit.py` | `core/variant_audit.py` |
| Leitura dos cards (OCR → spec) | `services/report/card_reader.py` | `importers/card_reader.py` |
| Board Excalidraw | `services/report/board.py` | `exporters/board.py` |
| Markdown, TSV e HTML | `services/report/documents.py` | `exporters/variant_reports.py` |
| Caso de uso | `services/report/service.py` | `pipeline.py` |
| OCR do Vision | `adapters/vision_ocr.py` | `importers/vision_ocr.py` |
| Porta do OCR | `ports/protocols.py` (`TextRecognizer`) | — |
| Caminhos vindos de fora | `security/files.py` | — |

Contrato: `report.spec`, `report.audit`, `report.export` e `report.import`, numa
fila própria (`report`). O relatório não toca aparelho: não pode esperar um
`wda.start` de minutos nem segurar o espelho. Ver
[PROTOCOLO_RPC.md](../PROTOCOLO_RPC.md#relatório-de-tagueamento).

`report.audit` aceita duas origens: `file` (um log exportado, Logcat em texto ou
os formatos consolidados) e `session`, que usa o histórico da escuta de
Analytics do próprio motor. É o passo 1 que some: capturar e auditar sem
exportar nada.

### Front

`Views/Report/`: barra acessória (spec, origem dos eventos, plataforma,
Auditar, Exportar, Copiar), resumo com conformidade e contagem por status, a
tabela do sistema com uma linha por variação, detalhe com a validação
parâmetro a parâmetro e o bloco com ✓/✗, inspector com o card do Figma e a
sheet de revisão da importação. A aba funciona sem aparelho e ocupa a coluna
central inteira.

## O que mudou em relação ao `tag_audit`, e por quê

- **Sem Pydantic e sem Typer.** O app nativo roda no Python do sistema (ver
  AGENTS.md, item 4); dependência nova quebraria o `verify-native`. A validação
  da spec ficou explícita e diz o card e o campo do problema.
- **Regex inválida na spec** (`re:(abc`) era erro interno no meio da
  auditoria. Agora é recusada ao abrir a spec.
- **`except Exception` ao ler um print** virou erro tipado (`OSError`,
  `DecompressionBombError`), e print acima de 15 MB não é embutido.
- **Ids do board** saíam de `uuid4`. Agora saem de um contador: o mesmo
  relatório gera o mesmo arquivo, e as fixtures do contrato ficam estáveis.
- **Rascunho importado nunca sobrescreve** uma spec existente
  (`nome-2.json`): sobrescrever apagaria a revisão feita à mão.
- **Sessão sem eventos é recusada** em vez de devolver tudo "não disparado",
  que pareceria um resultado verdadeiro.

As regras de casamento não mudaram. A paridade foi conferida com os arquivos
reais do `bold-kepler` (duas specs, quatro logs, Android e iOS): Markdown, TSV
e HTML saíram idênticos byte a byte ao original, e o board com a mesma
geometria e os mesmos textos.

## O que ficou de fora

- **Pipeline antigo `run`** (spec por categorias, `core/engine.py`). O próprio
  README do `tag_audit` recomenda o `auditar`; manter dois motores de casamento
  é o problema que o ADR 0001 resolveu.
- **`webkit_sync`**, que grava no LocalStorage do WebKit de outro app
  (*Francis' DrawCred*). É integração pessoal com um app de terceiro, escreve
  em banco de outro processo e não tem lugar no motor. O board exportado abre
  no Excalidraw normalmente.
- **CLI e interface web** do `tag_audit`. A interface do Mo baile é o front
  nativo; o harness de QA fala o mesmo JSON-RPC para quem precisar automatizar.
- **`--fail-on-error` para CI.** Fica como próximo passo: um comando do motor
  que audita e sai com código 2 quando há divergência.

## Consequências

- Mais quatro métodos e uma fila no contrato, sem mudar `PROTOCOL_VERSION`:
  a mudança é aditiva e o front antigo continua funcionando.
- O OCR compila um binário Swift na primeira importação, em
  `~/Library/Caches/Mo baile/ocr` (pasta 0700). Leva de 20 a 60 s, e por isso
  `report.import` tem prazo de 600 s e emite progresso.
- Spec e log chegam como caminho pelo RPC. Tudo passa por `security/files.py`:
  byte nulo, arquivo que é pasta, extensão errada, spec acima de 5 MB e log
  acima de 64 MB são recusados antes de abrir.

## Como isso é verificado

- `engine/tests/unit/test_report_*.py`: regras, leitura do log, auditoria,
  relatórios, importação, serviço com arquivos de verdade e entradas hostis
  (nome de projeto com `<script>`, tabulação em valor, JSON quebrado, UTF-8
  inválido, byte nulo).
- `engine/tests/contract/test_report_rpc.py` e os testes de deriva do
  contrato: fila, progresso e documentação.
- `qa/qa_fluxo5.py`: o motor de verdade como subprocesso, do `report.spec` ao
  conteúdo dos quatro arquivos exportados, com `HOME` temporário.
- `apps/MoBaile/Tests/MoBaileTests/ReportTests.swift`: decodificação das
  fixtures reais, recortes da tabela, parâmetros que a sessão manda,
  acessibilidade da barra, das linhas e do inspector.

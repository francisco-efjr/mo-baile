"""Relatórios em texto da auditoria: Markdown, TSV e HTML.

Portado do `tag_audit` (exporters/variant_reports):

- Markdown: resumo, uma linha por variação e o quadro "fora da spec" (PR, Jira);
- TSV: a mesma tabela, para colar no Google Planilhas;
- HTML: arquivo único e interativo, com a identidade e o design system do app
  (resumo, filtro, busca, cards com o print da spec, tabela e "fora da spec").
  Fica em `html_report`.

Todo texto que vem da spec ou do log passa por escape no HTML: o nome do
projeto e os valores do log são dados de fora, e o HTML é aberto num navegador.
"""

from __future__ import annotations

from pathlib import Path

from mobaile.domain.report import AuditReport, VariantResult, VariantStatus
from mobaile.services.report.board import observation_lines, summary_lines
from mobaile.services.report.html_report import generate_interactive_html

HEADERS = ["Seção", "Card", "Fluxo", "Evento", "Variação", "Status", "Divergências", "Horário", "Disparos"]

STATUS_TEXT = {
    VariantStatus.OK: "OK",
    VariantStatus.ERROR: "ERRO",
    VariantStatus.MISSING: "NÃO DISPARADO",
}


def variation_text(result: VariantResult) -> str:
    expected = result.variant.expected
    return str(expected.get("detail") or expected.get("screen_name") or "")


def divergences_text(result: VariantResult) -> str:
    if result.status is VariantStatus.MISSING:
        return "Não disparado no log"
    out = [
        f"{c.field}: obtido {c.obtained if c.obtained is not None else 'AUSENTE'}, esperado {c.expected}"
        for c in result.checks if not c.ok
    ]
    if result.older_divergences:
        out.append(f"⚠ {result.older_divergent} disparo(s) anterior(es): " + ", ".join(result.older_divergences))
    return "; ".join(out)


def rows(report: AuditReport) -> list[list[str]]:
    out = []
    for result in report.results:
        card = report.spec.cards[result.variant.card_index]
        flow = report.spec.fluxos.get(result.variant.flow, "") if result.variant.flow else "-"
        out.append([
            card.secao, card.titulo or card.evento, flow, result.variant.event, variation_text(result),
            STATUS_TEXT[result.status], divergences_text(result),
            (result.matched.time_str or "") if result.matched else "", str(result.occurrences),
        ])
    return out


def generate_markdown(report: AuditReport) -> str:
    spec = report.spec
    md = [f"# Auditoria de Tagueamento — {spec.projeto} ({report.platform.upper()})", ""]
    if spec.versao_especificacao:
        md.append(f"Spec: {spec.versao_especificacao}")
    md += [f"- {line}" for line in summary_lines(report)] + [""]
    md.append("| " + " | ".join(HEADERS) + " |")
    md.append("|" + "|".join("---" for _ in HEADERS) + "|")
    for row in rows(report):
        md.append("| " + " | ".join(c.replace("|", "\\|").replace("\n", " ") for c in row) + " |")
    md += ["", "## Fora da spec / Observações", "", *observation_lines(report)]
    return "\n".join(md) + "\n"


def generate_tsv(report: AuditReport) -> str:
    def clean(cell: str) -> str:
        return cell.replace("\t", " ").replace("\n", " ")

    return "\n".join("\t".join(clean(c) for c in row) for row in [HEADERS, *rows(report)]) + "\n"


def generate_html(report: AuditReport, prints_dir: str | Path | None = None) -> str:
    """HTML interativo, com a identidade do Mo baile (ver `html_report`)."""
    return generate_interactive_html(report, prints_dir)

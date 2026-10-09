"""Relatórios em texto da auditoria: Markdown, TSV e HTML.

Portado do `tag_audit` (exporters/variant_reports):

- Markdown: resumo, uma linha por variação e o quadro "fora da spec" (PR, Jira);
- TSV: a mesma tabela, para colar no Google Planilhas;
- HTML: arquivo único, com resumo, filtro por status, print da spec e bloco por
  variação.

Todo texto que vem da spec ou do log passa por escape: o nome do projeto e os
valores do log são dados de fora, e o HTML é aberto num navegador.
"""

from __future__ import annotations

import base64
import html
from pathlib import Path

from mobaile.domain.report import AuditReport, VariantResult, VariantStatus
from mobaile.services.report.board import (
    flow_short_label,
    observation_lines,
    read_image,
    summary_lines,
    variant_block_text,
)

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


_CSS = """
body{font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:24px;color:#212529;background:#fff}
h1{font-size:22px}h2{font-size:17px;margin-top:32px;border-bottom:1px solid #dee2e6;padding-bottom:4px}
.sum{color:#495057}.filters button{margin-right:6px;padding:4px 10px;cursor:pointer}
.card{display:flex;gap:16px;border-top:2px solid #212529;padding:16px 0}.card img{max-width:360px;height:auto}
.spec{flex:0 0 360px}.cols{display:flex;gap:16px;flex-wrap:wrap;flex:1}.col{flex:1;min-width:320px}
.col h3{font-size:14px;margin:0 0 8px}
pre{font:12px ui-monospace,Menlo,monospace;padding:10px;border-radius:8px;border:2px solid;white-space:pre-wrap;margin:0 0 4px}
.ok pre{border-color:#20c997;background:#e6fcf5}.err pre{border-color:#fa5252;background:#fff5f5}
.badge{display:inline-block;font-weight:700;padding:2px 12px;border-radius:6px;margin-bottom:12px}
.ok .badge{background:#b2f2bb;color:#2b8a3e}.err .badge{background:#ffc9c9;color:#c92a2a}
.obs{white-space:pre-wrap;color:#495057}
@media (prefers-color-scheme:dark){body{background:#1e1e1e;color:#e9ecef}.sum,.obs{color:#ced4da}
.ok pre{background:#0b3d2e;color:#e9ecef}.err pre{background:#4a1d1d;color:#e9ecef}}
"""

_JS = """
function f(s){document.querySelectorAll('.v').forEach(e=>{e.style.display=(s==='all'||e.dataset.s===s)?'':'none'})}
"""

_STATUS_CLASS = {VariantStatus.OK: "ok", VariantStatus.ERROR: "err", VariantStatus.MISSING: "miss"}


def _img_tag(path: Path) -> str:
    found = read_image(path)
    if found is None:
        return "<p><em>(print indisponível)</em></p>"
    data, mime, _ = found
    return f'<img alt="{html.escape(path.name)}" src="data:{mime};base64,{base64.b64encode(data).decode()}">'


def _block(result: VariantResult, label: str | None) -> str:
    ok = result.status is VariantStatus.OK
    return (f'<div class="v {"ok" if ok else "err"}" data-s="{_STATUS_CLASS[result.status]}">'
            f"<pre>{html.escape(variant_block_text(result, label))}</pre>"
            f'<span class="badge">{"OK" if ok else "Erro"}</span></div>')


def generate_html(report: AuditReport, prints_dir: str | Path | None = None) -> str:
    spec = report.spec
    pdir = Path(prints_dir or spec.prints_dir or ".")
    projeto = html.escape(spec.projeto)
    parts = [f"<!doctype html><html lang='pt-BR'><head><meta charset='utf-8'>"
             f"<meta name='viewport' content='width=device-width,initial-scale=1'>"
             f"<title>Auditoria {projeto}</title><style>{_CSS}</style><script>{_JS}</script>"
             f"</head><body><h1>Auditoria de Tagueamento — {projeto} · {report.platform.upper()}</h1>"]
    parts += [f'<p class="sum">{html.escape(line)}</p>' for line in summary_lines(report)]
    parts.append(f'<div class="filters"><button onclick="f(\'all\')">Todos ({report.total})</button>'
                 f'<button onclick="f(\'ok\')">OK ({report.total_ok})</button>'
                 f'<button onclick="f(\'err\')">Divergentes ({report.total_divergent})</button>'
                 f'<button onclick="f(\'miss\')">Não disparados ({report.total_missing})</button></div>')
    current = None
    for card_index, card in enumerate(spec.cards):
        if card.secao != current:
            current = card.secao
            parts.append(f"<h2>{html.escape(card.secao)}</h2>")
        results = report.results_by_card(card_index)
        spec_column = _img_tag(pdir / card.print_name) if card.print_name else ""
        parts.append(f'<div class="card"><div class="spec"><strong>{html.escape(card.titulo or card.evento)}'
                     f"</strong><br>{spec_column}</div><div class='cols'>")
        if any(r.variant.flow for r in results):
            for flow in spec.fluxos:
                blocks = "".join(_block(r, flow_short_label(report, flow)) for r in results if r.variant.flow == flow)
                parts.append(f'<div class="col"><h3>{html.escape(spec.fluxos[flow])}</h3>{blocks}</div>')
        else:
            parts.append('<div class="col">' + "".join(_block(r, None) for r in results) + "</div>")
        parts.append("</div></div>")
    parts.append(f'<h2>Fora da spec / Observações</h2><div class="obs">'
                 f'{html.escape(chr(10).join(observation_lines(report)))}</div></body></html>')
    return "".join(parts)

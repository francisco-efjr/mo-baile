"""Board Excalidraw da auditoria por variação.

Portado do `tag_audit` (exporters/board), no layout aprovado em 08/10/2026:

- cabeçalho com o resumo e uma moldura por seção da spec;
- por card, o print da spec uma vez à esquerda e uma coluna por fluxo ao lado;
- por variação, um bloco JSON monoespaçado com ✓/✗ por parâmetro e
  "↳ esperado" nas divergências, e o selo OK/Erro abaixo;
- quadro final "Fora da spec / Observações" com eventos não mapeados e alertas.

`variant_block_text`, `summary_lines` e `observation_lines` também alimentam o
HTML, o Markdown e a aba Relatório do app: o texto de uma variação é o mesmo em
todo lugar.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import textwrap
from pathlib import Path
from typing import Any

from PIL import Image

from mobaile.domain.report import AuditReport, VariantResult, VariantStatus

logger = logging.getLogger(__name__)

TS = 1791500000000
FONT = 13
LINE_H = FONT * 1.25
IMG_W = 400
COL_W = 640
GAP = 30
BADGE_W, BADGE_H = 120, 48
LEFT = 100
X_IMG = LEFT + 30
X_COL0 = X_IMG + IMG_W + 40
FLOW_COLORS = ["#1971c2", "#e67700", "#2f9e44", "#9c36b5"]
# Print maior que isto não é embutido: um board de 20 cards já passa de 10 MB
# com prints normais, e um arquivo de 200 MB trava o Excalidraw.
MAX_IMAGE_BYTES = 15 * 1024 * 1024


def read_image(path: Path) -> tuple[bytes, str, tuple[int, int]] | None:
    """Bytes, MIME e tamanho de um print, ou `None` se não der para usar."""
    try:
        if not path.is_file() or path.stat().st_size > MAX_IMAGE_BYTES:
            return None
        data = path.read_bytes()
        with Image.open(path) as image:
            size = image.size
    except (OSError, Image.DecompressionBombError) as exc:
        logger.info("Print %s ignorado: %s", path.name, exc)
        return None
    mime = "image/jpeg" if path.suffix.lower() in (".jpg", ".jpeg") else "image/png"
    return data, mime, size


class _Canvas:
    """Elementos do board. Ids e sementes saem de um contador, e não de `uuid4`:
    o mesmo relatório gera o mesmo arquivo, que dá para comparar e versionar."""

    def __init__(self) -> None:
        self.elements: list[dict[str, Any]] = []
        self.files: dict[str, dict[str, Any]] = {}

    def _base(self, kind: str, x: float, y: float, w: float, h: float, **extra: Any) -> dict[str, Any]:
        digest = hashlib.sha256(f"mobaile-board-{len(self.elements)}".encode()).hexdigest()
        seed = int(digest[12:19], 16)
        element: dict[str, Any] = {
            "id": digest[:12], "type": kind, "x": x, "y": y, "width": w, "height": h, "angle": 0,
            "strokeColor": "#212529", "backgroundColor": "transparent", "fillStyle": "solid", "strokeWidth": 1,
            "strokeStyle": "solid", "roughness": 1, "opacity": 100, "groupIds": [], "frameId": None,
            "roundness": None, "seed": seed, "version": 1, "versionNonce": seed, "isDeleted": False,
            "boundElements": None, "updated": TS, "link": None, "locked": False,
        }
        element.update(extra)
        self.elements.append(element)
        return element

    def rect(self, x: float, y: float, w: float, h: float, stroke: str = "#ced4da", bg: str = "transparent",
             sw: int = 1, rough: int = 1) -> dict[str, Any]:
        return self._base("rectangle", x, y, w, h, strokeColor=stroke, backgroundColor=bg, strokeWidth=sw,
                          roughness=rough, roundness={"type": 3})

    def text(self, x: float, y: float, s: str, size: int = 15, family: int = 1, color: str = "#212529",
             align: str = "left", width: float | None = None) -> dict[str, Any]:
        lines = s.split("\n")
        char_w = 0.6 if family == 3 else 0.55
        w = width or max(len(line) for line in lines) * size * char_w
        return self._base("text", x, y, w, len(lines) * size * 1.25, strokeColor=color, text=s, originalText=s,
                          fontSize=size, fontFamily=family, textAlign=align, verticalAlign="top",
                          baseline=size, containerId=None, lineHeight=1.25, autoResize=True)

    def hline(self, x1: float, y: float, x2: float) -> None:
        self._base("line", x1, y, x2 - x1, 0, strokeWidth=3, points=[[0, 0], [x2 - x1, 0]],
                   lastCommittedPoint=None, startBinding=None, endBinding=None, startArrowhead=None,
                   endArrowhead=None)

    def image(self, path: Path, x: float, y: float, max_w: float) -> float:
        """Embute o print e devolve a altura desenhada (0 se não der para ler)."""
        found = read_image(path)
        if found is None:
            return 0.0
        data, mime, (width, height) = found
        file_id = hashlib.sha1(data, usedforsecurity=False).hexdigest()
        self.files[file_id] = {"id": file_id, "dataURL": f"data:{mime};base64," + base64.b64encode(data).decode(),
                               "mimeType": mime, "created": TS, "lastRetrieved": TS}
        scale = min(max_w / width, 1.0)
        self._base("image", x, y, width * scale, height * scale, strokeColor="transparent", status="saved",
                   fileId=file_id, scale=[1, 1], roundness={"type": 3})
        return height * scale


def _fmt(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def variant_block_text(result: VariantResult, flow_label: str | None) -> str:
    """Texto do bloco JSON de uma variação (board, HTML e app)."""
    variant = result.variant
    head = f"{flow_label} · " if flow_label else ""
    if result.status is VariantStatus.MISSING:
        lines = [f"// {head}{variant.event} [ERRO]", "// NÃO DISPARADO no log", "{"]
        flat: list[tuple[str, Any]] = []
        for key, value in variant.expected.items():
            if key == "items" and isinstance(value, list) and value and isinstance(value[0], dict):
                flat.extend((f"items[0].{ik}", iv) for ik, iv in value[0].items())
            else:
                flat.append((key, value))
        for i, (key, value) in enumerate(flat):
            lines.append(f'  "{key}": {_fmt(value)}' + ("," if i < len(flat) - 1 else ""))
        lines.append("}  // esperado (spec)")
    else:
        matched = result.matched
        ok = result.status is VariantStatus.OK
        lines = [f"// {head}{variant.event} [{'OK' if ok else 'ERRO'}]",
                 f"// log {matched.time_str if matched and matched.time_str else ''} · "
                 f"{result.occurrences} disparo(s)", "{"]
        for i, check in enumerate(result.checks):
            comma = "," if i < len(result.checks) - 1 else ""
            got = "AUSENTE" if check.obtained is None else _fmt(check.obtained)
            lines.append(f'  "{check.field}": {got}{comma}  {"✓" if check.ok else "✗"}')
            if not check.ok:
                lines.append(f"    // ↳ esperado: {check.expected}")
        lines.append("}")
        if result.ga_screen:
            lines.append(f"// ga_screen: {result.ga_screen}")
        if result.older_divergences:
            lines.append(f"// ⚠ {result.older_divergent} disparo(s) anterior(es) divergente(s):")
            lines.extend(f"//   {d}" for d in result.older_divergences[:4])
    if variant.note:
        lines.append(f"// obs: {variant.note}")
    # Comentário longo é quebrado para caber na largura do bloco.
    wrapped: list[str] = []
    for line in lines:
        if line.startswith("//") and len(line) > 78:
            wrapped.extend(textwrap.wrap(line, width=78, subsequent_indent="//   "))
        else:
            wrapped.append(line)
    return "\n".join(wrapped)


def summary_lines(report: AuditReport) -> list[str]:
    stats = report.log_stats
    return [
        f"{len(report.spec.cards)} cards · {report.total} validações · OK: {report.total_ok} · "
        f"Erro: {report.total_error} (sendo {report.total_missing} não disparadas) · "
        f"Conformidade: {report.compliance_rate:.1f}%",
        f"Plataforma: {report.platform.upper()} · {stats.get('uteis', 0)} eventos únicos "
        f"({stats.get('duplicados', 0)} duplicados removidos de {stats.get('da_plataforma', 0)} da plataforma; "
        f"{stats.get('total_lidos', 0)} lidos no arquivo)",
    ]


def observation_lines(report: AuditReport) -> list[str]:
    lines = ["Eventos dos fluxos da spec que nenhum card cobre:"]
    if not report.extras:
        lines.append("  (nenhum)")
    for extra in report.extras:
        parts = [extra.event, extra.screen or "-"]
        if extra.component:
            parts.append(f"component={extra.component}")
        if extra.detail:
            parts.append(f"detail={extra.detail}")
        lines.append(f"  • {' · '.join(parts)} — {extra.count}x")
    lines += ["", "Alertas (app_exception / error_view nas telas da spec):"]
    if not report.alerts:
        lines.append("  (nenhum)")
    for alert in report.alerts:
        lines.append(f"  • {alert.event} · {alert.screen or '-'} — {alert.count}x")
    lines += ["", "Regra: cada variação é validada pelo disparo mais recente; '⚠' indica disparos anteriores "
                  "com divergência diferente."]
    return lines


def flow_short_label(report: AuditReport, flow: str | None) -> str | None:
    """Rótulo curto do fluxo nos blocos: ``CPA · credito-pessoal`` vira ``CPA``."""
    if flow is None:
        return None
    return report.spec.fluxos.get(flow, flow).split(" · ")[0]


def build_board(report: AuditReport, prints_dir: str | Path | None = None) -> dict[str, Any]:
    canvas = _Canvas()
    spec = report.spec
    pdir = Path(prints_dir or spec.prints_dir or ".")
    flows = list(spec.fluxos)
    col_x = [X_COL0 + i * (COL_W + GAP) for i in range(max(1, len(flows)))]
    frame_w = (col_x[-1] + COL_W + 30) - LEFT

    y = 40.0
    canvas.text(LEFT, y, f"Auditoria de Tagueamento — {spec.projeto} · {report.platform.upper()}", size=32,
                color="#1e1e1e")
    y += 52
    canvas.text(LEFT, y, "\n".join(summary_lines(report)), size=16, color="#495057")
    y += 70
    canvas.text(X_IMG, y, "Spec (Figma)", size=22, color="#868e96")
    for i, flow in enumerate(flows):
        canvas.text(col_x[i], y, spec.fluxos[flow], size=22, color=FLOW_COLORS[i % len(FLOW_COLORS)])
    y += 50

    def column(x: float, top: float, results: list[VariantResult], label: str | None) -> float:
        cy = top
        for result in results:
            text = variant_block_text(result, label)
            ok = result.status is VariantStatus.OK
            h = (text.count("\n") + 1) * LINE_H + 28
            canvas.rect(x, cy, COL_W, h, stroke="#20c997" if ok else "#fa5252",
                        bg="#e6fcf5" if ok else "#fff5f5", sw=2)
            canvas.text(x + 14, cy + 14, text, size=FONT, family=3, width=COL_W - 28)
            by = cy + h + 10
            canvas.rect(x, by, BADGE_W, BADGE_H, stroke="#2b8a3e" if ok else "#e03131",
                        bg="#b2f2bb" if ok else "#ffc9c9", sw=3, rough=2)
            canvas.text(x, by + 8, "OK" if ok else "Erro", size=28, color="#2b8a3e" if ok else "#c92a2a",
                        align="center", width=BADGE_W)
            cy = by + BADGE_H + 24
        return cy - top - 24 if results else 0.0

    sections: list[tuple[str, list[int]]] = []
    for i, card in enumerate(spec.cards):
        if not sections or sections[-1][0] != card.secao:
            sections.append((card.secao, []))
        sections[-1][1].append(i)

    for section, indexes in sections:
        top = y
        frame = canvas.rect(LEFT, top, frame_w, 10, sw=2)
        canvas.text(LEFT + 24, top + 18, section, size=20, color="#868e96")
        iy = top + 64
        for n, card_index in enumerate(indexes):
            card = spec.cards[card_index]
            results = report.results_by_card(card_index)
            ih = canvas.image(pdir / card.print_name, X_IMG, iy, IMG_W) if card.print_name else 0.0
            if not ih:
                canvas.text(X_IMG, iy, f"{card.titulo or card.evento}\n(print indisponível)", size=16,
                            color="#868e96")
                ih = 50.0
            heights = [ih]
            if any(r.variant.flow is not None for r in results):
                for i, flow in enumerate(flows):
                    heights.append(column(col_x[i], iy, [r for r in results if r.variant.flow == flow],
                                          flow_short_label(report, flow)))
            else:
                heights.append(column(col_x[0], iy, results, None))
            iy += max(heights) + 30
            if n < len(indexes) - 1:
                canvas.hline(LEFT + 24, iy, LEFT + frame_w - 24)
                iy += 30
        frame["height"] = iy - top + 10
        y = iy + 70

    notes = canvas.text(LEFT + 24, y + 60, "\n".join(observation_lines(report)), size=15, color="#495057")
    canvas.rect(LEFT, y, frame_w, notes["height"] + 90, sw=2)
    canvas.text(LEFT + 24, y + 18, f"{len(sections) + 1}. Fora da spec / Observações", size=20, color="#868e96")

    return {"type": "excalidraw", "version": 2, "source": "https://excalidraw.com", "elements": canvas.elements,
            "appState": {"gridSize": None, "viewBackgroundColor": "#ffffff"}, "files": canvas.files}

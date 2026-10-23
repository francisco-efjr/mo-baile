"""HTML interativo da auditoria, com a identidade do Mo baile.

É a aba Relatório fora do app: toolbar de vidro com o ícone, barra lateral com
as seções, resumo com a conformidade, filtro por status, busca, visão em cards
(print da spec + validação por fluxo) ou em tabela ordenável, print ampliado e
"Fora da spec". Letras miúdas no rodapé dizem que o arquivo saiu do Mo baile.

Arquivo único e offline: o design system (`html/design_system.css`, gerado de
`docs/design/design-system` por `tools/sync_report_assets.py`), os ícones, o
Motion (animações, MIT) e os prints vão embutidos. O conteúdo inteiro é
desenhado aqui; o JavaScript só filtra, ordena e anima, e a página funciona
sem ele (e na impressão).

Segurança: todo texto da spec e do log passa por `html.escape`. A política de
conteúdo bloqueia rede e só deixa rodar os três scripts embutidos, pelo hash.
"""

from __future__ import annotations

import base64
import hashlib
import html
import json
import math
import re
from datetime import datetime
from functools import cache
from pathlib import Path
from typing import Any

from mobaile import __version__
from mobaile.domain.report import AuditReport, ExtraEvent, VariantResult, VariantStatus
from mobaile.services.report.board import flow_short_label, read_image, summary_lines, variant_block_text

ASSETS = Path(__file__).with_name("html")
MOTION_VERSION = "13.5.1"
THEME_KEY = "mobaile-report-theme"

# status -> (classe da validação, data-s, ícone, texto, variante do StatusIndicator)
_STATUS = {
    VariantStatus.OK: ("ok", "ok", "circle-check", "OK", "ok"),
    VariantStatus.ERROR: ("err", "err", "circle-x", "Divergente", "error"),
    VariantStatus.MISSING: ("err", "miss", "triangle-alert", "Não disparado", "warn"),
}
_RANK = {"err": 0, "miss": 1, "ok": 2}
# Cor de cada fluxo na coluna: as categorias da sidebar do app.
_FLOW_COLORS = ("var(--cat-3)", "var(--cat-1)", "var(--cat-2)", "var(--accent)")

# Roda no <head>, antes de pintar: aparência escolhida (ou a do sistema),
# alto contraste, Reduzir movimento e Reduzir transparência viram os
# atributos que o design system lê.
_HEAD_JS = (
    "(function(){var d=document.documentElement,m=function(q){return !!(window.matchMedia&&matchMedia(q).matches)},"
    "p=null;try{p=localStorage.getItem('" + THEME_KEY + "')}catch(e){}"
    "if(p!=='light'&&p!=='dark')p='auto';d.dataset.themePref=p;"
    "d.dataset.theme=(p==='dark'||(p==='auto'&&m('(prefers-color-scheme: dark)')))?'dark':'light';"
    "if(m('(prefers-contrast: more)'))d.dataset.contrast='high';"
    "if(m('(prefers-reduced-motion: reduce)'))d.dataset.reduceMotion='true';"
    "if(m('(prefers-reduced-transparency: reduce)'))d.dataset.reduceTransparency='true';})();"
)


@cache
def _text_asset(name: str) -> str:
    return (ASSETS / name).read_text(encoding="utf-8")


@cache
def _icon_data_uri() -> str:
    return "data:image/png;base64," + base64.b64encode((ASSETS / "icon.png").read_bytes()).decode()


@cache
def _glyphs() -> dict[str, str]:
    return json.loads(_text_asset("icons.json"))


def _icon(name: str, size: int = 13, stroke: float = 1.6) -> str:
    return (f'<svg class="mb-icon" width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" '
            f'stroke="currentColor" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round" '
            f'aria-hidden="true">{_glyphs()[name]}</svg>')


def _e(value: Any) -> str:
    return html.escape(str(value), quote=True)


def _value(value: Any) -> str:
    """Valor como aparece no Validação do app: texto puro; o resto em JSON."""
    if value is None:
        return "AUSENTE"
    return value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)


def _pct(rate: float) -> str:
    return f"{rate:.1f}".replace(".", ",") + "%"


def _status_indicator(result: VariantResult) -> str:
    _, _, glyph, word, kind = _STATUS[result.status]
    return f'<span class="mb-status mb-status--{kind}">{_icon(glyph, 12, 2.2)}<span>{word}</span></span>'


def _variation(result: VariantResult) -> str:
    expected = result.variant.expected
    return str(expected.get("detail") or expected.get("screen_name") or result.variant.event)


def _expected_pairs(expected: dict[str, Any]) -> list[tuple[str, Any]]:
    """Os parâmetros esperados, com o primeiro item de `items` aberto (como no bloco)."""
    pairs: list[tuple[str, Any]] = []
    for key, value in expected.items():
        if key == "items" and isinstance(value, list) and value and isinstance(value[0], dict):
            pairs.extend((f"items[0].{ik}", iv) for ik, iv in value[0].items())
        else:
            pairs.append((key, value))
    return pairs


def _divergences(result: VariantResult) -> str:
    if result.status is VariantStatus.MISSING:
        return "Não disparado no log"
    return "; ".join(f"{c.field}: obtido {_value(c.obtained)}, esperado {c.expected}" for c in result.checks if not c.ok)


def _search_text(report: AuditReport, result: VariantResult) -> str:
    card = report.spec.cards[result.variant.card_index]
    flow = report.spec.fluxos.get(result.variant.flow, "") if result.variant.flow else ""
    parts = [card.secao, card.titulo or "", card.evento, result.variant.event, flow, _variation(result),
             _divergences(result), _STATUS[result.status][3]]
    parts += [f"{c.field} {_value(c.obtained)} {c.expected}" for c in result.checks]
    return " ".join(parts).lower()


_KEY = re.compile(r"^(\s*)(&quot;[^&]*&quot;)(:)")


def _highlight_block(text: str) -> str:
    """Bloco do board com as cores de sintaxe do app (comentário, chave, ✓/✗)."""
    out = []
    for line in text.split("\n"):
        if line.lstrip().startswith("//"):
            out.append(f'<span class="c">{_e(line)}</span>')
            continue
        safe = _KEY.sub(r'\1<span class="k">\2</span>\3', _e(line))
        safe = re.sub(r"  ✓$", '  <span class="ok">✓</span>', safe)
        safe = re.sub(r"  ✗$", '  <span class="bad">✗</span>', safe)
        safe = re.sub(r"  // (.*)$", r'  <span class="c">// \1</span>', safe)
        out.append(safe)
    return "\n".join(out)


def _checks_table(result: VariantResult) -> str:
    rows = []
    if result.status is VariantStatus.MISSING:
        for key, value in _expected_pairs(result.variant.expected):
            rows.append(f'<tr><td class="v__none">{_icon("minus", 12, 2.2)}</td><td class="v__field">{_e(key)}</td>'
                        f'<td class="v__none">—</td><td class="v__exp">{_e(_value(value))}</td></tr>')
    else:
        for check in result.checks:
            mark = (f'<td class="v__ok">{_icon("circle-check", 12, 2.2)}<span class="rp-sr">ok</span></td>' if check.ok
                    else f'<td class="v__bad">{_icon("circle-x", 12, 2.2)}<span class="rp-sr">diverge</span></td>')
            row_class = "" if check.ok else ' class="is-bad"'
            rows.append(f'<tr{row_class}>{mark}<td class="v__field">{_e(check.field)}</td>'
                        f'<td class="v__got">{_e(_value(check.obtained))}</td><td class="v__exp">{_e(check.expected)}</td></tr>')
    if not rows:
        return ""
    return ('<table class="v__checks"><thead><tr><th><span class="rp-sr">Status</span></th><th>Parâmetro</th>'
            f'<th>Obtido</th><th>Esperado</th></tr></thead><tbody>{"".join(rows)}</tbody></table>')


def _variant(report: AuditReport, result: VariantResult, index: int, flow_label: str | None) -> str:
    css, data_s, *_ = _STATUS[result.status]
    if result.status is VariantStatus.MISSING:
        when = "não disparado no log"
    else:
        time = result.matched.time_str if result.matched and result.matched.time_str else ""
        when = f"{time} · {result.occurrences} disparo{'s' if result.occurrences != 1 else ''}".strip(" ·")
    notes = []
    if result.ga_screen:
        notes.append(f"<span>ga_screen: <span class='mb-mono'>{_e(result.ga_screen)}</span></span>")
    if result.older_divergences:
        notes.append(f'<span class="is-warn">{_icon("triangle-alert", 11, 2)} {result.older_divergent} disparo(s) '
                     f'anterior(es) com outra divergência: {_e(", ".join(result.older_divergences[:4]))}</span>')
    if result.variant.note:
        notes.append(f"<span>obs: {_e(result.variant.note)}</span>")
    variation = _variation(result)
    return (
        f'<article class="v {css}" data-s="{data_s}" id="v-{index}" data-q="{_e(_search_text(report, result))}">'
        f'<header class="v__head">{_status_indicator(result)}'
        f'<span class="v__label" title="{_e(variation)}">{_e(variation)}</span>'
        f'<span class="v__when">{_e(when)}</span></header>'
        f"{_checks_table(result)}"
        + (f'<div class="v__notes">{"".join(notes)}</div>' if notes else "")
        + '<footer class="v__foot">'
        f'<button type="button" class="mb-btn mb-btn--small mb-btn--plain" data-act="block" aria-expanded="false">'
        f'{_icon("braces", 12)}<span>Bloco</span></button>'
        f'<button type="button" class="mb-btn mb-btn--small mb-btn--plain" data-act="copy" '
        f'title="Copia o bloco desta validação, o mesmo do board e do app">{_icon("copy", 12)}<span>Copiar</span></button>'
        "</footer>"
        f'<pre class="v__block" hidden>{_highlight_block(variant_block_text(result, flow_label))}</pre>'
        "</article>"
    )


def _print(path: Path, title: str) -> str:
    found = read_image(path)
    if found is None:
        return (f'<p class="rp-noprint">{_icon("info", 13)}<span>Sem print: a imagem '
                f"<span class='mb-mono'>{_e(path.name)}</span> não está na pasta da spec.</span></p>")
    data, mime, _ = found
    src = f"data:{mime};base64,{base64.b64encode(data).decode()}"
    return (f'<button type="button" class="rp-print" data-title="{_e(title)}" aria-label="Ampliar o print de {_e(title)}">'
            f'<img alt="Print do card {_e(title)}" loading="lazy" src="{src}">'
            f'<span class="rp-print__zoom">{_icon("scan-search", 13)}</span></button>')


def _worst(statuses: list[str]) -> str:
    return min(statuses, key=lambda s: _RANK[s]) if statuses else "off"


def _sections(report: AuditReport, pdir: Path) -> tuple[str, list[tuple[str, str, int, str]]]:
    """Cards agrupados por seção, e a lista (id, nome, total, pior status) para a barra lateral."""
    spec = report.spec
    flow_colors = {flow: _FLOW_COLORS[i % len(_FLOW_COLORS)] for i, flow in enumerate(spec.fluxos)}
    groups: list[tuple[str, list[int]]] = []
    for index, card in enumerate(spec.cards):
        if not groups or groups[-1][0] != card.secao:
            groups.append((card.secao, []))
        groups[-1][1].append(index)

    position = {id(r): i for i, r in enumerate(report.results)}
    parts, nav = [], []
    for s_index, (secao, card_indexes) in enumerate(groups):
        sec_id = f"sec-{s_index}"
        statuses = [_STATUS[r.status][1] for ci in card_indexes for r in report.results_by_card(ci)]
        nav.append((sec_id, secao, len(statuses), _worst(statuses)))
        parts.append(f'<section class="rp-section" id="{sec_id}" aria-labelledby="{sec_id}-t">'
                     f'<div class="rp-section__head"><h2 class="rp-section__title" id="{sec_id}-t">{_e(secao)}</h2>'
                     f'<span class="mb-count mb-count--pill">{len(statuses)}</span></div>')
        for ci in card_indexes:
            card = spec.cards[ci]
            title = card.titulo or card.evento
            results = report.results_by_card(ci)
            spec_col = _print(pdir / card.print_name, title) if card.print_name else ""
            parts.append(f'<div class="rp-card" id="card-{ci}"><div class="rp-card__spec">'
                         f'<h3 class="rp-card__title">{_e(title)}</h3>'
                         f'<span class="rp-card__event">{_e(card.evento)}</span>{spec_col}</div><div class="rp-cols">')
            if any(r.variant.flow for r in results):
                for flow, name in spec.fluxos.items():
                    blocks = "".join(_variant(report, r, position[id(r)], flow_short_label(report, flow))
                                     for r in results if r.variant.flow == flow)
                    if blocks:
                        parts.append(f'<div class="rp-col" style="--flow-color:{flow_colors[flow]}">'
                                     f'<h4 class="rp-col__title">{_e(name)}</h4>{blocks}</div>')
            else:
                parts.append('<div class="rp-col">'
                             + "".join(_variant(report, r, position[id(r)], None) for r in results) + "</div>")
            parts.append("</div></div>")
        parts.append("</section>")
    return "".join(parts), nav


def _table(report: AuditReport) -> str:
    head = [("Status", ""), ("Seção", ""), ("Fluxo", ""), ("Evento", ""), ("Variação", ""),
            ("Divergências", ""), ("Horário", ""), ("Disparos", "num")]
    ths = "".join(f'<th scope="col"{f" data-type={kind!r}" if kind else ""}>{name}'
                  f'{_icon("chevron-down", 10, 2)}</th>'.replace('class="mb-icon"', 'class="mb-icon rp-sort"')
                  for name, kind in head)
    rows = []
    for result in report.results:
        card = report.spec.cards[result.variant.card_index]
        data_s = _STATUS[result.status][1]
        flow = report.spec.fluxos.get(result.variant.flow, "—") if result.variant.flow else "—"
        time = result.matched.time_str if result.matched and result.matched.time_str else ""
        rows.append(
            f'<tr data-s="{data_s}" data-target="card-{result.variant.card_index}" '
            f'data-q="{_e(_search_text(report, result))}" title="Abrir o card">'
            f'<td data-sort="{_RANK[data_s]}">{_status_indicator(result)}</td><td>{_e(card.secao)}</td>'
            f'<td>{_e(flow)}</td><td class="ev">{_e(result.variant.event)}</td>'
            f'<td class="mono">{_e(_variation(result))}</td><td title="{_e(_divergences(result))}">{_e(_divergences(result))}</td>'
            f'<td class="mono">{_e(time)}</td><td class="num">{result.occurrences}</td></tr>')
    return (f'<div class="rp-table-wrap"><table class="rp-table"><thead><tr>{ths}</tr></thead>'
            f'<tbody>{"".join(rows)}</tbody></table></div>')


def _extra_rows(items: list[ExtraEvent], with_details: bool) -> str:
    kind = "extra" if with_details else "alert"
    rows = []
    for item in items:
        cells = [item.event, item.screen or "—"]
        if with_details:
            cells += [item.component or "—", item.detail or "—"]
        q = " ".join(str(c) for c in cells).lower()
        rows.append(f'<tr data-k="{kind}" data-q="{_e(q)}">' + "".join(f"<td>{_e(c)}</td>" for c in cells)
                    + f'<td class="num">{item.count}&#215;</td></tr>')
    return "".join(rows)


def _extras(report: AuditReport) -> str:
    def box(title: str, glyph: str, items: list[ExtraEvent], heads: list[str], with_details: bool, empty: str) -> str:
        body = (f'<table class="rp-mini"><thead><tr>{"".join(f"<th>{h}</th>" for h in heads)}<th></th></tr></thead>'
                f"<tbody>{_extra_rows(items, with_details)}</tbody></table>" if items
                else f'<p class="rp-none">{empty}</p>')
        return f'<div class="mb-card"><h3>{_icon(glyph, 14)}{title} <span class="mb-count mb-count--pill">{len(items)}</span></h3>{body}</div>'

    return (
        '<section class="rp-extras" id="fora-da-spec" aria-labelledby="fora-t">'
        '<div class="rp-section__head"><h2 class="rp-section__title" id="fora-t">Fora da spec e observações</h2></div>'
        '<div class="rp-extras__grid">'
        + box("Eventos dos fluxos que nenhum card cobre", "layers", report.extras,
              ["Evento", "Tela", "component", "detail"], True, "Nenhum evento fora da spec.")
        + box("Alertas nas telas da spec", "circle-alert", report.alerts, ["Evento", "Tela"], False,
              "Nenhum app_exception ou error_view.")
        + "</div><p class=\"rp-rule\">Cada variação é validada pelo disparo mais recente. O aviso de disparos "
        "anteriores aparece quando um disparo antigo teve uma divergência diferente.</p></section>"
    )


def _seg(cls: str, items: list[tuple[str, str]], attr: str, selected: str, label: str) -> str:
    buttons = "".join(
        f'<button type="button" class="mb-seg__item{" is-selected" if value == selected else ""}" '
        f'data-{attr}="{value}" aria-pressed="{"true" if value == selected else "false"}">{content}</button>'
        for value, content in items)
    return f'<div class="mb-seg {cls}" role="group" aria-label="{label}"><span class="mb-seg__thumb"></span>{buttons}</div>'


def _ring(report: AuditReport) -> str:
    radius = 64
    circ = 2 * math.pi * radius
    total = report.total or 1
    parts, start = [], 0.0
    for kind, count in (("ok", report.total_ok), ("err", report.total_divergent), ("miss", report.total_missing)):
        length = circ * count / total
        if count:
            parts.append(f'<circle class="rp-ring__seg rp-ring__seg--{kind}" cx="76" cy="76" r="{radius}" '
                         f'data-len="{length:.2f}" data-start="{start:.2f}" '
                         f'stroke-dasharray="{length:.2f} {circ:.2f}" stroke-dashoffset="{-start:.2f}"/>')
        start += length
    return (f'<div class="rp-ring" data-c="{circ:.2f}" data-rate="{report.compliance_rate}">'
            f'<svg viewBox="0 0 152 152" aria-hidden="true"><circle class="rp-ring__track" cx="76" cy="76" r="{radius}"/>'
            f'{"".join(parts)}</svg><div class="rp-ring__label"><span class="rp-ring__value">{_pct(report.compliance_rate)}</span>'
            f'<span class="rp-ring__caption">conforme</span></div></div>')


def _tile(filter_: str, value: int, kind: str, glyph: str, word: str) -> str:
    return (f'<button type="button" class="rp-tile" data-filter="{filter_}"><span class="rp-tile__value">{value}</span>'
            f'<span class="mb-status mb-status--{kind}">{_icon(glyph, 12, 2.2)}<span>{word}</span></span></button>')


def _csp(scripts: list[str]) -> str:
    hashes = " ".join("'sha256-" + base64.b64encode(hashlib.sha256(s.encode()).digest()).decode() + "'" for s in scripts)
    return (f"default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src {hashes}; "
            "base-uri 'none'; form-action 'none'")


def generate_interactive_html(report: AuditReport, prints_dir: str | Path | None = None,
                              generated_at: datetime | None = None) -> str:
    spec = report.spec
    pdir = Path(prints_dir or spec.prints_dir or ".")
    when = (generated_at or datetime.now()).strftime("%d/%m/%Y %H:%M")
    projeto = _e(spec.projeto)
    platform = report.platform.lower()
    rate = _pct(report.compliance_rate)
    body_sections, nav = _sections(report, pdir)
    icon_uri = _icon_data_uri()
    scripts = [_HEAD_JS, _text_asset("motion.min.js"), _text_asset("report.js")]

    filters = [("all", "Todas", report.total), ("action", "Pedem Ação", report.total_error),
               ("err", "Divergentes", report.total_divergent), ("miss", "Não Disparadas", report.total_missing),
               ("ok", "OK", report.total_ok), ("off", "Fora da Spec", len(report.extras))]
    filter_seg = _seg("rp-filter", [(key, f'<span aria-label="{name} ({n})">{name}</span>'
                                          f'<span class="mb-count mb-count--pill" aria-hidden="true">{n}</span>')
                                    for key, name, n in filters], "filter", "all", "Filtrar por status")
    view_seg = _seg("rp-viewseg mb-seg--small", [("cards", "Cards"), ("table", "Tabela")], "view", "cards", "Visão")
    theme_seg = _seg("rp-theme mb-seg--small", [("auto", _icon("contrast", 12) + '<span class="rp-sr">Automático</span>'),
                                                ("light", _icon("sun", 12) + '<span class="rp-sr">Claro</span>'),
                                                ("dark", _icon("moon", 12) + '<span class="rp-sr">Escuro</span>')],
                     "pick-theme", "auto", "Aparência")

    nav_items = "".join(f'<li><a href="#{sid}"><span class="rp-dot rp-dot--{worst}"></span>'
                        f'<span class="rp-nav__name">{_e(name)}</span><span class="mb-count">{n}</span></a></li>'
                        for sid, name, n, worst in nav)
    extras_n = len(report.extras) + len(report.alerts)
    meta = [f'<span class="rp-chip rp-chip--{_e(platform)}">{_icon("smartphone", 11, 2)}{_e(report.platform.upper())}</span>']
    if spec.versao_especificacao:
        meta.append(f"<span>spec {_e(spec.versao_especificacao)}</span>")
    meta += [f"<span>{len(spec.cards)} cards</span>", f"<span>{report.total} validações</span>",
             f"<span>gerado em {when}</span>"]

    return "".join([
        "<!doctype html><html lang='pt-BR'><head><meta charset='utf-8'>",
        "<meta name='viewport' content='width=device-width,initial-scale=1'>",
        f'<meta http-equiv="Content-Security-Policy" content="{_csp(scripts)}">',
        '<meta name="color-scheme" content="light dark"><meta name="generator" content="Mo baile ', _e(__version__), '">',
        f"<title>Relatório · {projeto}</title>",
        f'<link rel="icon" href="{icon_uri}">',
        f"<script>{_HEAD_JS}</script>",
        f"<style>{_text_asset('design_system.css')}</style><style>{_text_asset('report.css')}</style>",
        "</head><body class='mb-root'>",
        # Toolbar
        '<header class="rp-toolbar"><div class="rp-brand">',
        f'<img src="{icon_uri}" alt="Mo baile"><div class="mb-truncate"><div class="rp-brand__title">Relatório</div>',
        f'<div class="rp-brand__sub mb-truncate">{projeto} · {report.total} validações · {rate} conforme</div></div></div>',
        f'<label class="mb-search">{_icon("search", 12)}<span class="rp-sr">Buscar</span>',
        '<input id="rp-q" type="search" placeholder="Buscar em eventos, parâmetros e divergências" autocomplete="off">',
        '<span class="mb-kbd">/</span></label>', theme_seg, "</header>",
        '<div class="rp-shell">',
        # Barra lateral
        '<nav class="rp-sidebar" aria-label="Seções"><div class="rp-sidebar__label">Relatório</div><ul class="rp-nav">',
        f'<li><a href="#resumo"><span class="rp-dot rp-dot--{_worst([_STATUS[r.status][1] for r in report.results])}"></span>'
        f'<span class="rp-nav__name">Resumo</span><span class="mb-count">{rate}</span></a></li></ul>',
        f'<div class="rp-sidebar__label">Seções da spec</div><ul class="rp-nav">{nav_items}</ul>',
        '<ul class="rp-nav"><li><a href="#fora-da-spec"><span class="rp-dot rp-dot--off"></span>',
        f'<span class="rp-nav__name">Fora da spec</span><span class="mb-count">{extras_n}</span></a></li></ul>',
        '<div class="rp-sidebar__label">Atalhos</div><div class="rp-shortcuts">',
        "<kbd>/</kbd><span>buscar</span><kbd>1&#8211;6</kbd><span>filtrar por status</span>",
        "<kbd>t</kbd><span>cards ou tabela</span><kbd>b</kbd><span>expandir os blocos</span></div></nav>",
        '<main class="rp-main">',
        # Resumo
        f'<section class="rp-hero" id="resumo" aria-label="Resumo">{_ring(report)}<div>',
        f'<h1 class="rp-hero__title">Auditoria de tagueamento · {projeto}</h1>',
        f'<div class="rp-hero__meta">{"".join(meta)}</div><div class="rp-tiles">',
        _tile("ok", report.total_ok, "ok", "circle-check", "OK"),
        _tile("err", report.total_divergent, "error", "circle-x", "Divergentes"),
        _tile("miss", report.total_missing, "warn", "triangle-alert", "Não disparadas"),
        _tile("off", len(report.extras), "off", "minus", "Fora da spec"),
        _tile("off", len(report.alerts), "error" if report.alerts else "off", "circle-alert", "Alertas"),
        f'</div><p class="rp-hero__stats">{_e(summary_lines(report)[1])}</p></div></section>',
        # Filtro
        f'<div class="rp-filterbar">{filter_seg}{view_seg}<span class="rp-filterbar__spacer"></span>',
        '<span class="rp-result-count" aria-live="polite"></span>',
        f'<button type="button" class="mb-btn mb-btn--small" data-act="blocks" aria-pressed="false">{_icon("braces", 12)}'
        "<span>Expandir Blocos</span></button></div>",
        f'<div class="rp-view rp-view--cards">{body_sections}</div>',
        f'<div class="rp-view rp-view--table" hidden>{_table(report)}</div>',
        f'<div class="rp-empty mb-empty" hidden><span class="mb-empty__icon">{_icon("list-filter", 28, 1.4)}</span>',
        '<p class="mb-empty__title">Nada neste filtro</p><p class="mb-empty__text">Nenhuma validação bate com o status '
        'e a busca escolhidos.</p><button type="button" class="mb-btn" data-act="all">Mostrar Todas</button></div>',
        _extras(report),
        # Letras miúdas
        f'<footer class="rp-footer"><img src="{icon_uri}" alt=""><span>Gerado pelo <b>Mo baile</b> {_e(__version__)}</span>',
        f'<span class="rp-footer__sep">·</span><span>{when}</span><span class="rp-footer__sep">·</span>',
        "<span>auditoria de tagueamento contra a spec do Figma</span><span class=\"rp-footer__sep\">·</span>",
        f"<span>animações com Motion {MOTION_VERSION} (MIT) e ícones Lucide (ISC)</span></footer>",
        "</main></div>",
        # Print ampliado e aviso
        '<dialog class="rp-lightbox" aria-label="Print do card"><div class="rp-lightbox__frame"><div class="rp-lightbox__bar">',
        f'<span></span><button type="button" class="mb-btn mb-btn--small mb-btn--plain" data-act="close" aria-label="Fechar">'
        f'{_icon("x", 13)}</button></div><img alt=""></div></dialog>',
        f'<div class="rp-toast" role="status">{_icon("check", 13, 2.2)}<span></span></div>',
        f"<script>{scripts[1]}</script><script>{scripts[2]}</script>",
        "</body></html>",
    ])

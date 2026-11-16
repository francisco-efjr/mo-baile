"""Checklist de conferência gerado da importação dos prints do Figma.

Depois do OCR (`card_reader`), cada card do rascunho vira uma lista de itens
para marcar: o que o OCR pediu para revisar e cada disparo a conferir no app
(card x fluxo x variação), com os parâmetros esperados como referência.

Dois formatos, com o Markdown como fonte:

- `checklist_markdown`: o `.checklist.md` gravado ao lado do rascunho. É texto
  comum: dá para marcar `[x]` em qualquer editor, acrescentar itens e versionar;
- `checklist_html`: o mesmo checklist no padrão do design system do app (os
  tokens e as classes `.mb-*` de `html/design_system.css`, a mesma casca do
  relatório exportado). Lê o Markdown, então o que foi marcado ou editado nele
  vai para o HTML. Na página, as marcações ficam no navegador e o botão
  "Copiar Markdown" devolve o arquivo com o estado novo. "Salvar" baixa uma cópia do
  próprio HTML com as marcações gravadas nele.

Cada item tem três estados: `[ ]` pendente, `[x]` conferido e `[!]` bug (de
desenvolvimento ou do protótipo, que vai gerar correção).

O leitor entende só o subconjunto que `checklist_markdown` escreve (títulos
`#`/`##`/`###`, parágrafos, listas `-`/`*`, caixas `[ ]`/`[x]`, `código` e
**negrito**); o resto vira parágrafo. Todo texto passa por `html.escape`: o
Markdown veio do OCR e pode ter sido editado à mão.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from mobaile import __version__
from mobaile.services.report.html_report import (
    _HEAD_JS,
    _csp,
    _e,
    _icon,
    _icon_data_uri,
    _seg,
    _text_asset,
)

WARN_PREFIX = "⚠"

# Dados do teste que a pessoa preenche no HTML. O rótulo é a chave no Markdown
# (`- Rótulo: valor` no cabeçalho), então o que volta de um `.md` copiado
# preenche o formulário de novo.
TEST_FIELDS: tuple[tuple[str, str, str], ...] = (
    ("nome", "Nome", "text"),
    ("data_inicio", "Data início", "date"),
    ("data_fim", "Data fim", "date"),
    ("hora_inicio", "Hora início", "time"),
    ("hora_fim", "Hora fim", "time"),
    ("versao", "Versão do app", "text"),
    ("plataforma", "Plataforma testada", "platform"),
    ("ambiente", "Ambiente", "text"),
    ("conta", "Número da conta", "text"),
    ("cooperativa", "Cooperativa", "text"),
    ("codigo_usuario", "Código do usuário", "text"),
)
FLOW_TOKEN = "{fluxo}"


# ----------------------------------------------------------------------------- Markdown

def _code(value: Any) -> str:
    """Valor como código inline; usa crase dupla quando o valor tem crase."""
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    text = text.replace("\n", " ")
    if not text:
        return "*(vazio)*"
    return f"`` {text} ``" if "`" in text else f"`{text}`"


def _pairs(params: dict[str, Any]) -> list[tuple[str, Any]]:
    """Parâmetros em pares, com o primeiro item de `items` aberto (como no relatório)."""
    out: list[tuple[str, Any]] = []
    for key, value in params.items():
        if key == "items" and isinstance(value, list) and value and isinstance(value[0], dict):
            out.extend((f"items[0].{ik}", iv) for ik, iv in value[0].items())
        else:
            out.append((key, value))
    return out


def _variation_text(variation: dict[str, Any]) -> str:
    return " · ".join(f"{_code(k)} = {_code(v)}" for k, v in variation.items())


def _card_items(card: dict[str, Any], flows: dict[str, str]) -> list[str]:
    """Os disparos a conferir: um por fluxo x variação."""
    per_flow = FLOW_TOKEN in json.dumps(card, ensure_ascii=False) and bool(flows)
    labels = list(flows.values()) if per_flow else [None]
    variations = card.get("variacoes") or [{}]
    event = _code(card.get("evento") or "?")
    items = []
    for label in labels:
        for variation in variations:
            parts = [f"fluxo **{label}**"] if label else []
            parts.append(_variation_text(variation) if variation else f"disparo de {event}")
            items.append("- [ ] " + " · ".join(parts))
    return items


def checklist_markdown(
    spec: dict[str, Any],
    review: list[dict[str, Any]],
    *,
    spec_name: str = "",
    generated_at: datetime | None = None,
) -> str:
    """O `.checklist.md` do rascunho: revisão do OCR e disparos a conferir, card a card."""
    when = (generated_at or datetime.now()).strftime("%d/%m/%Y %H:%M")
    flows: dict[str, str] = dict(spec.get("fluxos") or {})
    cards: list[dict[str, Any]] = list(spec.get("cards") or [])
    doubts = {i: list(r.get("duvidas") or []) for i, r in enumerate(review)}

    md = [f"# Checklist · {spec.get('projeto') or 'spec'}", ""]
    md.append(f"- Plataforma: {str(spec.get('plataforma') or 'android').upper()}")
    md.append(f"- Gerado em: {when}")
    if spec_name:
        md.append(f"- Spec: {_code(spec_name)}")
    if spec.get("prints_dir"):
        md.append(f"- Prints: {_code(spec['prints_dir'])}")
    if flows:
        md.append(f"- Fluxos: {', '.join(flows.values())}")
    md += ["", "Marque cada item com `[x]` ao conferir. Os itens com ⚠ são do OCR: confira no print e corrija "
           "a spec antes de auditar. Para o HTML no padrão do design system, use **Exportar Checklist…** "
           "na aba Relatório.", ""]

    sections: dict[str, list[int]] = {}
    for index, card in enumerate(cards):
        sections.setdefault(str(card.get("secao") or "Geral"), []).append(index)

    for section, indexes in sections.items():
        md += [f"## {section}", ""]
        for index in indexes:
            card = cards[index]
            title = str(card.get("titulo") or card.get("evento") or f"Card {index + 1}")
            heading = f"### {title}"
            if card.get("print"):
                heading += f" — {_code(card['print'])}"
            md += [heading, ""]
            params = card.get("params") if isinstance(card.get("params"), dict) else {}
            extras = card.get("params_por_fluxo") if isinstance(card.get("params_por_fluxo"), dict) else {}
            if params or extras:
                md += ["**Parâmetros esperados**", ""]
                md += [f"- {_code(k)}: {_code(v)}" for k, v in _pairs(params)]
                for flow, values in extras.items():
                    label = flows.get(flow, flow)
                    if isinstance(values, dict):
                        md += [f"- {_code(k)} (só no fluxo {label}): {_code(v)}" for k, v in _pairs(values)]
                md.append("")
            md += ["**Conferir**", ""]
            md += [f"- [ ] {WARN_PREFIX} Revisar OCR: {d}" for d in doubts.get(index, [])]
            md += _card_items(card, flows)
            md.append("")
    return "\n".join(md).rstrip() + "\n"


# ----------------------------------------------------------------------------- leitura

_CHECK = re.compile(r"^\s*[-*+]\s+\[([ xX!])\]\s+(.*)$")
_BULLET = re.compile(r"^\s*[-*+]\s+(.*)$")
_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")


@dataclass
class CheckItem:
    line: int
    text: str
    done: bool
    warn: bool
    bug: bool = False


@dataclass
class Block:
    kind: str  # "p", "ul" ou "check"
    lines: list[str] = field(default_factory=list)
    items: list[CheckItem] = field(default_factory=list)


@dataclass
class Card:
    title: str
    blocks: list[Block] = field(default_factory=list)

    @property
    def checks(self) -> list[CheckItem]:
        return [item for block in self.blocks for item in block.items]


@dataclass
class Section:
    title: str
    cards: list[Card] = field(default_factory=list)

    @property
    def checks(self) -> list[CheckItem]:
        return [item for card in self.cards for item in card.checks]


@dataclass
class ChecklistDoc:
    title: str = "Checklist"
    meta: list[tuple[str, str]] = field(default_factory=list)
    intro: list[Block] = field(default_factory=list)
    sections: list[Section] = field(default_factory=list)

    @property
    def checks(self) -> list[CheckItem]:
        return [item for section in self.sections for item in section.checks]


def parse_checklist(text: str) -> ChecklistDoc:
    """Lê o Markdown do checklist (o que `checklist_markdown` escreve, editado ou não)."""
    doc = ChecklistDoc()
    in_header = True
    section: Section | None = None
    card: Card | None = None
    block: Block | None = None

    def target() -> list[Block]:
        nonlocal section, card
        if in_header:
            return doc.intro
        if section is None:
            section = Section("Geral")
            doc.sections.append(section)
        if card is None:
            card = Card("")
            section.cards.append(card)
        return card.blocks

    def add(kind: str) -> Block:
        nonlocal block
        if block is None or block.kind != kind:
            block = Block(kind)
            target().append(block)
        return block

    for number, raw in enumerate(text.splitlines()):
        line = raw.rstrip()
        if not line.strip():
            block = None
            continue
        heading = _HEADING.match(line)
        if heading:
            level, title = len(heading.group(1)), heading.group(2)
            block = None
            if level == 1 and in_header and not doc.sections:
                doc.title = title
            elif level <= 2:
                in_header = False
                section, card = Section(title), None
                doc.sections.append(section)
            else:
                in_header = False
                if section is None:
                    section = Section("Geral")
                    doc.sections.append(section)
                card = Card(title)
                section.cards.append(card)
            continue
        check = _CHECK.match(line)
        if check:
            body = check.group(2).strip()
            add("check").items.append(CheckItem(number, body, check.group(1) in "xX", body.startswith(WARN_PREFIX),
                                                    check.group(1) == "!"))
            continue
        bullet = _BULLET.match(line)
        if bullet:
            body = bullet.group(1).strip()
            meta = re.match(r"^([^:`*]{1,40}):\s+(.+)$", body)
            if in_header and meta:
                doc.meta.append((meta.group(1).strip(), meta.group(2).strip()))
            else:
                add("ul").lines.append(body)
            continue
        current = add("p")
        current.lines.append(line.strip())
    return doc


# ----------------------------------------------------------------------------- HTML

_INLINE_CODE = re.compile(r"(`+)\s?(.+?)\s?\1")
_BOLD = re.compile(r"\*\*(.+?)\*\*")
_ITALIC = re.compile(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])")


def _inline(text: str) -> str:
    """Escape + código, negrito e itálico. O código é guardado antes, para não receber ênfase."""
    codes: list[str] = []

    def keep(m: re.Match[str]) -> str:
        codes.append(f'<code class="ck-code">{_e(m.group(2))}</code>')
        return f"\x00{len(codes) - 1}\x00"

    out = _e(_INLINE_CODE.sub(keep, text))
    out = _BOLD.sub(r"<b>\1</b>", out)
    out = _ITALIC.sub(r"<i>\1</i>", out)
    return re.sub("\x00(\\d+)\x00", lambda m: codes[int(m.group(1))], out)


def _plain(text: str) -> str:
    return re.sub(r"[`*]", "", text)


def _slug(text: str, used: set[str]) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", _plain(text).lower()).strip("-") or "secao"
    slug, n = base, 2
    while slug in used:
        slug, n = f"{base}-{n}", n + 1
    used.add(slug)
    return slug


def _copy_values(text: str) -> list[str]:
    """O que o botão de copiar do item leva: os valores à direita de `=` ou, sem `=`, todos os códigos."""
    values = [m.group(2) for m in re.finditer(r"=\s*(`+)\s?(.+?)\s?\1", text)]
    return values or [m.group(2) for m in _INLINE_CODE.finditer(text)]


def _check_html(item: CheckItem) -> str:
    text = item.text
    if item.warn:
        text = text[len(WARN_PREFIX):].strip()
        text = re.sub(r"^Revisar OCR:\s*", "", text)
    state = "true" if item.done else "false"
    values = _copy_values(text)
    copy_btn = (f'<button type="button" class="ck-copy" data-copy="{_e(chr(10).join(values))}" '
                f'title="Copiar {_e(" · ".join(values))}" aria-label="Copiar {_e(" · ".join(values))}">'
                f'{_icon("copy", 12)}</button>' if values else "")
    bug_btn = (f'<button type="button" class="ck-bug" aria-pressed="{"true" if item.bug else "false"}" '
               f'title="Marcar como bug (desenvolvimento ou protótipo)" aria-label="Marcar como bug">'
               f'{_icon("x", 11, 2.6)}</button>')
    badge = (f'<span class="ck-badge">{_icon("triangle-alert", 11, 2.2)}<span>OCR</span></span>' if item.warn else "")
    return (f'<li class="ck-item{" ck-item--warn" if item.warn else ""}{" is-done" if item.done else ""}{" is-bug" if item.bug else ""}" '
            f'data-line="{item.line}" data-warn="{"1" if item.warn else "0"}" data-q="{_e(_plain(item.text).lower())}">'
            f'<button type="button" class="mb-check__box" role="checkbox" aria-checked="{state}" '
            f'aria-label="{_e(_plain(text))}">{_icon("check", 10, 3)}</button>'
            f'{bug_btn}<span class="ck-item__text">{badge}{_inline(text)}{copy_btn}</span></li>')


def _block_html(block: Block) -> str:
    if block.kind == "check":
        return f'<ul class="ck-items">{"".join(_check_html(i) for i in block.items)}</ul>'
    if block.kind == "ul":
        return f'<ul class="ck-list">{"".join(f"<li>{_inline(x)}</li>" for x in block.lines)}</ul>'
    text = " ".join(block.lines)
    if re.fullmatch(r"\*\*[^*]+\*\*", text):
        return f'<h4 class="ck-label">{_e(text[2:-2])}</h4>'
    return f'<p class="ck-p">{_inline(text)}</p>'


def _card_html(card: Card) -> str:
    checks = card.checks
    done = sum(i.done for i in checks)
    head = ""
    if card.title:
        head = (f'<header class="ck-card__head"><h3 class="ck-card__title">{_inline(card.title)}</h3>'
                f'<span class="mb-count mb-count--pill ck-card__count" data-done="{done}" data-total="{len(checks)}">'
                f"{done}/{len(checks)}</span></header>")
    return (f'<article class="ck-card{" is-complete" if checks and done == len(checks) else ""}" '
            f'data-q="{_e(_plain(card.title).lower())}">{head}{"".join(_block_html(b) for b in card.blocks)}</article>')


def _ring(done: int, total: int) -> str:
    radius = 64
    circ = 2 * 3.141592653589793 * radius
    length = circ * done / total if total else 0
    pct = round(done / total * 100) if total else 0
    return (f'<div class="rp-ring ck-ring" data-c="{circ:.2f}"><svg viewBox="0 0 152 152" aria-hidden="true">'
            f'<circle class="rp-ring__track" cx="76" cy="76" r="{radius}"/>'
            f'<circle class="rp-ring__seg rp-ring__seg--ok ck-ring__seg" cx="76" cy="76" r="{radius}" '
            f'stroke-dasharray="{length:.2f} {circ:.2f}"/></svg>'
            f'<div class="rp-ring__label"><span class="rp-ring__value ck-pct">{pct}%</span>'
            f'<span class="rp-ring__caption">concluído</span></div></div>')


def _tile(filter_: str, key: str, value: int, kind: str, glyph: str, word: str) -> str:
    return (f'<button type="button" class="rp-tile" data-filter="{filter_}"><span class="rp-tile__value" data-n="{key}">'
            f'{value}</span><span class="mb-status mb-status--{kind}">{_icon(glyph, 12, 2.2)}<span>{word}</span></span>'
            "</button>")


def _test_form(doc: ChecklistDoc) -> str:
    """Formulário "Dados do teste", preenchido com o que o Markdown já trouxer."""
    known = {k.lower(): _plain(v) for k, v in doc.meta}
    spec_platform = known.get("plataforma", "").lower()
    fields = []
    for key, label, kind in TEST_FIELDS:
        value = known.get(label.lower(), "")
        if kind == "date" and (m := re.fullmatch(r"(\d{2})/(\d{2})/(\d{4})", value)):
            value = f"{m.group(3)}-{m.group(2)}-{m.group(1)}"
        if kind == "platform":
            value = value or spec_platform
            opts = "".join(f'<option value="{v}"{" selected" if value.lower() == v.lower() else ""}>{v}</option>'
                           for v in ("", "Android", "iOS"))
            control = f'<select class="mb-field" id="ck-f-{key}" data-field="{key}" data-label="{_e(label)}">{opts}</select>'
        else:
            control = (f'<input class="mb-field" id="ck-f-{key}" type="{kind}" data-field="{key}" '
                       f'data-label="{_e(label)}" value="{_e(value)}" autocomplete="off">')
        fields.append(f'<label class="ck-field" for="ck-f-{key}"><span>{_e(label)}</span>{control}</label>')
    return (f'<section class="ck-test" id="dados-teste" aria-label="Dados do teste"><div class="rp-section__head">'
            f'<h2 class="rp-section__title">Dados do teste</h2><span class="mb-count ck-test__count"></span></div>'
            f'<p class="ck-p">Preencha antes de conferir. Os dados vão junto no <b>Salvar</b> e no Markdown copiado.</p>'
            f'<div class="ck-test__grid">{"".join(fields)}</div></section>')


def checklist_html(text: str, *, source_name: str = "", generated_at: datetime | None = None) -> str:
    """O checklist em HTML, arquivo único e offline, no padrão do design system do app."""
    doc = parse_checklist(text)
    when = (generated_at or datetime.now()).strftime("%d/%m/%Y %H:%M")
    checks = doc.checks
    total, done = len(checks), sum(i.done for i in checks)
    warn = sum(i.warn for i in checks)
    warn_open = sum(i.warn and not i.done for i in checks)
    bugs = sum(i.bug for i in checks)
    title = _plain(doc.title)
    subtitle = re.sub(r"^Checklist\s*·\s*", "", title)
    icon_uri = _icon_data_uri()
    doc_id = hashlib.sha256(text.encode()).hexdigest()[:16]
    scripts = [_HEAD_JS, _text_asset("checklist.js")]

    used: set[str] = set()
    nav, body = [], []
    for section in doc.sections:
        sid = _slug(section.title, used)
        s_checks = section.checks
        s_done = sum(i.done for i in s_checks)
        nav.append(f'<li><a href="#{sid}"><span class="rp-dot ck-dot{" rp-dot--ok" if s_checks and s_done == len(s_checks) else ""}">'
                   f'</span><span class="rp-nav__name">{_e(_plain(section.title))}</span>'
                   f'<span class="mb-count" data-sec="{sid}">{s_done}/{len(s_checks)}</span></a></li>')
        body.append(f'<section class="rp-section ck-section" id="{sid}"><div class="rp-section__head">'
                    f'<h2 class="rp-section__title">{_inline(section.title)}</h2>'
                    f'<span class="mb-count" data-sec="{sid}">{s_done}/{len(s_checks)}</span></div>'
                    f'{"".join(_card_html(c) for c in section.cards)}</section>')

    meta = []
    test_labels = {label.lower() for _, label, _ in TEST_FIELDS}
    for key, value in doc.meta:
        if key.lower() in test_labels:
            continue
        if key.lower() == "plataforma":
            platform = _plain(value).lower()
            meta.append(f'<span class="rp-chip rp-chip--{_e(platform)}">{_icon("smartphone", 11, 2)}{_e(value.upper())}</span>')
        else:
            meta.append(f'<span><span class="ck-meta__key">{_e(key)}</span> {_inline(value)}</span>')

    filters = [("all", "Todos", total), ("open", "Pendentes", total - done), ("done", "Feitos", done),
               ("warn", "Revisar OCR", warn_open), ("bug", "Bugs", bugs)]
    filter_seg = _seg("rp-filter", [(key, f'<span>{name}</span><span class="mb-count mb-count--pill" data-n="{key}">{n}</span>')
                                    for key, name, n in filters], "filter", "all", "Filtrar itens")
    theme_seg = _seg("rp-theme mb-seg--small", [("auto", _icon("contrast", 12) + '<span class="rp-sr">Automático</span>'),
                                                ("light", _icon("sun", 12) + '<span class="rp-sr">Claro</span>'),
                                                ("dark", _icon("moon", 12) + '<span class="rp-sr">Escuro</span>')],
                     "pick-theme", "auto", "Aparência")
    intro = "".join(_block_html(b) for b in doc.intro)

    return "".join([
        "<!doctype html><html lang='pt-BR'><head><meta charset='utf-8'>",
        "<meta name='viewport' content='width=device-width,initial-scale=1'>",
        f'<meta http-equiv="Content-Security-Policy" content="{_csp(scripts)}">',
        '<meta name="color-scheme" content="light dark"><meta name="generator" content="Mo baile ', _e(__version__), '">',
        f"<title>{_e(title)}</title>",
        f'<link rel="icon" href="{icon_uri}">',
        f"<script>{_HEAD_JS}</script>",
        f"<style>{_text_asset('design_system.css')}</style><style>{_text_asset('report.css')}</style>",
        f"<style>{_text_asset('checklist.css')}</style>",
        f"</head><body class='mb-root' data-doc='{doc_id}'>",
        # Toolbar
        '<header class="rp-toolbar"><div class="rp-brand">',
        f'<img src="{icon_uri}" alt="Mo baile"><div class="mb-truncate"><div class="rp-brand__title">Checklist</div>',
        f'<div class="rp-brand__sub mb-truncate"><span>{_e(subtitle)}</span> · '
        f'<span class="ck-sub">{done} de {total} feitos</span>'
        "</div></div></div>",
        f'<label class="mb-search">{_icon("search", 12)}<span class="rp-sr">Buscar</span>',
        '<input id="ck-q" type="search" placeholder="Buscar em eventos, parâmetros e itens" autocomplete="off">',
        '<span class="mb-kbd">/</span></label>', theme_seg, "</header>",
        '<div class="rp-shell">',
        # Barra lateral
        '<nav class="rp-sidebar" aria-label="Seções"><div class="rp-sidebar__label">Checklist</div><ul class="rp-nav">',
        f'<li><a href="#resumo"><span class="rp-dot ck-dot{" rp-dot--ok" if total and done == total else ""}"></span>'
        f'<span class="rp-nav__name">Resumo</span><span class="mb-count ck-total-count">{done}/{total}</span></a></li>'
        '<li><a href="#dados-teste"><span class="rp-dot ck-dot ck-test-dot"></span><span class="rp-nav__name">Dados do teste</span>'
        '<span class="mb-count ck-test__count"></span></a></li></ul>',
        f'<div class="rp-sidebar__label">Seções da spec</div><ul class="rp-nav">{"".join(nav)}</ul>',
        '<div class="rp-sidebar__label">Atalhos</div><div class="rp-shortcuts">',
        "<kbd>/</kbd><span>buscar</span><kbd>1&#8211;5</kbd><span>filtrar itens</span>",
        "<kbd>c</kbd><span>copiar o Markdown</span><kbd>s</kbd><span>salvar o HTML</span></div></nav>",
        '<main class="rp-main">',
        # Resumo
        f'<section class="rp-hero" id="resumo" aria-label="Resumo">{_ring(done, total)}<div>',
        f'<h1 class="rp-hero__title">{_inline(doc.title)}</h1>',
        f'<div class="rp-hero__meta">{"".join(meta)}</div><div class="rp-tiles">',
        _tile("all", "all", total, "off", "layers", "Itens"),
        _tile("done", "done", done, "ok", "circle-check", "Feitos"),
        _tile("open", "open", total - done, "busy", "minus", "Pendentes"),
        _tile("warn", "warn", warn_open, "warn" if warn_open else "off", "triangle-alert", "Revisar OCR"),
        _tile("bug", "bug", bugs, "error" if bugs else "off", "circle-x", "Bugs"),
        f'</div>{intro and f"<div class=ck-intro>{intro}</div>"}</div></section>',
        _test_form(doc),
        # Filtro
        f'<div class="rp-filterbar">{filter_seg}<span class="rp-filterbar__spacer"></span>',
        '<span class="rp-result-count" aria-live="polite"></span>',
        f'<button type="button" class="mb-btn mb-btn--small" data-act="copy">{_icon("copy", 12)}<span>Copiar Markdown</span></button>',
        f'<button type="button" class="mb-btn mb-btn--small mb-btn--default" data-act="save" '
        f'title="Baixa uma cópia deste HTML com o que já foi conferido">{_icon("save", 12)}<span>Salvar</span></button>',
        '<button type="button" class="mb-btn mb-btn--small" data-act="print"><span>Imprimir</span></button>',
        "</div>",
        f'<div class="ck-body">{"".join(body)}</div>',
        f'<div class="rp-empty mb-empty" hidden><span class="mb-empty__icon">{_icon("list-filter", 28, 1.4)}</span>',
        '<p class="mb-empty__title">Nada neste filtro</p><p class="mb-empty__text">Nenhum item bate com o filtro '
        'e a busca escolhidos.</p><button type="button" class="mb-btn" data-act="all">Mostrar Todos</button></div>',
        # Letras miúdas
        f'<footer class="rp-footer"><img src="{icon_uri}" alt=""><span>Gerado pelo <b>Mo baile</b> {_e(__version__)}</span>',
        f'<span class="rp-footer__sep">·</span><span>{when}</span><span class="rp-footer__sep">·</span>',
        f"<span>checklist dos prints do Figma{f' · {_e(source_name)}' if source_name else ''}</span>",
        f'<span class="rp-footer__sep">·</span><span>{warn} {"item" if warn == 1 else "itens"} do OCR</span>',
        '<span class="rp-footer__sep">·</span><span>ícones Lucide (ISC)</span></footer>',
        "</main></div>",
        f'<textarea id="ck-md" hidden aria-hidden="true">{_e(text)}</textarea>',
        f'<div class="rp-toast" role="status">{_icon("check", 13, 2.2)}<span></span></div>',
        f"<script>{scripts[1]}</script>",
        "</body></html>",
    ])

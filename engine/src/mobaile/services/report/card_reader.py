"""Leitura dos prints de cards do Figma e geração do rascunho da spec-modelo.

Portado do `tag_audit` (importers/card_reader) sem mudar as regras. Cada print
é um card no padrão "Anotações" do Figma:

- cabeçalho com o nome do evento (às vezes precedido do ícone, lido como
  "5 ", "S ", "•", "O ");
- tabela com o parâmetro à esquerda e o valor à direita (o valor pode quebrar
  em várias linhas);
- opcional, o quadro "Observação" com "Preenchimento de [x] no parâmetro P:"
  seguido de itens "• valor".

Tudo é regra fixa, sem LLM. O que foi corrigido ou ficou ambíguo vai para a
lista de dúvidas que acompanha o rascunho: o OCR pode trocar uma letra ou pular
uma linha sem aviso, então o rascunho sempre passa por revisão humana.
"""

from __future__ import annotations

import difflib
import re
import statistics
from collections.abc import Sequence
from dataclasses import dataclass, field
from itertools import product
from pathlib import Path
from typing import Any

from mobaile.domain.report import OcrLine
from mobaile.services.report.rules import value_matches

KNOWN_PARAMS = [
    "screen_name", "flow_name", "component", "detail", "insurance", "currency", "installments", "items",
    "value", "due_date", "installment_value", "operation_type", "loan_insurance_value", "down_payment", "tax",
    "cet", "iof", "transaction_id", "item_list_name", "item_list_id", "text", "title", "section", "sub_section",
    "description", "price", "quantity", "coupon", "payment_type", "shipping_tier", "content_type", "method",
]
KNOWN_EVENTS = [
    "screen_view", "flow_start", "flow_success", "form_input", "modal_view", "error_view", "interaction",
    "view_item_list", "view_item", "select_item", "add_to_cart", "remove_from_cart", "begin_checkout",
    "add_payment_info", "purchase", "refund", "login", "sign_up", "search", "share",
]
ITEM_KEYS = ["item_name", "item_id", "item_category", "item_category2", "item_category3", "item_category4",
             "item_category5", "item_brand", "item_variant", "item_list_name", "item_list_id", "price",
             "quantity", "index", "discount", "coupon"]

NUMBER_WORDS = ("valor", "taxa", "numero", "número", "custo", "preco", "preço", "quantidade", "iof", "cet",
                "juros", "parcelas")
DATE_WORDS = ("data",)
BULLET = re.compile(r"^\s*[•·▪◦*-]\s*")
WORD_ALT = re.compile(r"\[\s*([A-Za-zÀ-ú][\w-]*(?:\s*\|\s*[A-Za-zÀ-ú][\w-]*)+)\s*\]")


@dataclass
class ReadCard:
    file: str
    event: str = ""
    params: dict[str, Any] = field(default_factory=dict)
    bullets: dict[str, list[str]] = field(default_factory=dict)
    doubts: list[str] = field(default_factory=list)


# ----------------------------------------------------------------------------- normalização

def _squash(s: str) -> str:
    return re.sub(r"[\s_.,:;'\"*]", "", s.lower())


def match_vocab(token: str, vocab: Sequence[str], cutoff: float = 0.84) -> tuple[str | None, bool]:
    """Casa um termo lido com o vocabulário. Retorna (termo, corrigido?)."""
    t = token.strip().strip("\"'*:").strip()
    if t in vocab:
        return t, False
    sq = _squash(t)
    for v in vocab:
        if _squash(v) == sq:
            return v, True
    close = difflib.get_close_matches(sq, [_squash(v) for v in vocab], n=1, cutoff=cutoff)
    if close:
        return next(v for v in vocab if _squash(v) == close[0]), True
    return None, False


DESCRIPTIVE_WORDS = ("valor", "numero", "número", "label", "data", "taxa", "elemento", "tipo", "nome", "id",
                     "custo", "vencimento", "quantidade", "campo", "botao", "botão", "texto", "codigo", "código")


def _bracket(m: re.Match[str]) -> str:
    inner = m.group(1)
    inner = re.sub(r"(?<=[A-Za-zÀ-ú])\s*[)(/]\s*(?=[A-Za-zÀ-ú])", "|", inner)  # '[pessoal)investimentos]'
    words = [w for w in re.split(r"[\s|]+", inner.strip()) if w]
    if "|" not in inner and len(words) > 1 and not any(w.lower() in DESCRIPTIVE_WORDS for w in words):
        inner = "|".join(words)  # '[seguro credito]' -> '[seguro|credito]' (o '|' sumiu no OCR)
    return "[" + re.sub(r"\s*\|\s*", "|", inner.strip()) + "]"


def clean_value(v: str) -> str:
    """Corrige ruídos típicos do OCR em valores: aspas, barras, alternâncias sem separador, pontuação final."""
    v = v.replace("“", '"').replace("”", '"').replace("’", "'").replace("‘", "'").strip()  # noqa: RUF001
    v = re.sub(r"\[\s*0\s*[^\]\d]?\s*[1l]\s*\]|\[011\]", "[0|1]", v)
    v = re.sub(r"\[([^\[\]]+)\]", _bracket, v)
    v = re.sub(r"\s*:\s*", ":", v)
    return v.rstrip(".,; ").strip()


def fix_click(v: str) -> tuple[str, bool]:
    """'clickifechar' -> 'click:fechar'; 'click:ir para tela' -> 'click:ir-para-tela'. Retorna (valor, corrigido?)."""
    fixed = v
    m = re.match(r"^click([^:])(.*)$", v)
    if m and not v.startswith("click:"):
        sep, rest = m.groups()
        fixed = "click:" + (rest if sep in "i;l1|.," else sep + rest)
    if "[" not in fixed and " " in fixed:
        fixed = re.sub(r"\s+", "-", fixed.strip())
    return fixed, fixed != v


def placeholder_for(desc: str) -> str:
    d = desc.lower()
    if any(w in d for w in DATE_WORDS):
        return "[data]"
    if any(w in d for w in NUMBER_WORDS):
        return "[numero]"
    return "[preenchido]"


def map_descriptive(v: str) -> str:
    """Troca trechos descritivos ('[valor da parcela]', '[elemento]') por placeholders da spec-modelo."""
    def repl(m: re.Match[str]) -> str:
        inner = m.group(1)
        if "|" in inner or inner.strip().lower() in ("numero", "data", "preenchido"):
            return m.group(0)
        return placeholder_for(inner)

    return re.sub(r"\[([^\[\]]+)\]", repl, v)


def _join(parts: list[str]) -> str:
    out = ""
    for p in parts:
        p = p.strip()
        if not out:
            out = p
        elif out.endswith(("|", "-", ":", "[", "{", "_")) or p.startswith(("|", "]", "-", ":", "_")):
            out += p
        else:
            out += " " + p
    return out


# ----------------------------------------------------------------------------- leitura de um card

def _rows(lines: list[OcrLine], tol: float) -> list[list[OcrLine]]:
    rows: list[list[OcrLine]] = []
    for ln in sorted(lines, key=lambda ln: ln.y):
        if rows and abs(rows[-1][0].y - ln.y) <= tol:
            rows[-1].append(ln)
        else:
            rows.append([ln])
    return [sorted(r, key=lambda ln: ln.x) for r in rows]


def _parse_items(lines: list[OcrLine], doubts: list[str]) -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    cur: dict[str, str] = {}
    for ln in sorted(lines, key=lambda ln: ln.y):
        t = ln.t.strip()
        m = re.match(r"^[\"'*]?\s*([A-Za-z_,.0-9]+?)\s*[\"'*]?\s*[:.]\s*(.*)$", t)
        if not m:
            continue
        key, corrected = match_vocab(m.group(1).replace(",", "_").replace(".", "_"), ITEM_KEYS, cutoff=0.8)
        if not key:
            continue
        if corrected:
            doubts.append(f"items: chave '{m.group(1)}' lida como '{key}'")
        raw = m.group(2).strip().strip(".,;").strip().strip("\"'*").strip()
        if re.search(r"[\[\(]", raw):
            val = placeholder_for(re.sub(r"[\[\]\(\)]", "", raw))
        else:
            val = clean_value(raw).strip("\"'")
            if re.fullmatch(r"[A-Z][a-z0-9-]+", val):
                doubts.append(f"items.{key}: '{val}' lido como '{val.lower()}'")
                val = val.lower()
        if key in cur:
            items.append(cur)
            cur = {}
        cur[key] = val
    if cur:
        items.append(cur)
    return items


def _event_name(header: str, obs_names: list[str], doubts: list[str]) -> str:
    def clean(t: str) -> str:
        t = re.sub(r"^[^\w\[]+", "", t.strip())
        t = re.sub(r"^[A-Z0-9]\s+(?=[a-z])", "", t)
        t = re.sub(r"\s*\|\s*", "|", t)
        return re.sub(r"\s+", "_", t.strip("\"'“” "))

    cands = [clean(c) for c in [header, *obs_names] if c and clean(c)]
    if not cands:
        doubts.append("nome do evento não lido")
        return ""
    known, corrected = match_vocab(cands[0], KNOWN_EVENTS, cutoff=0.86)
    if known and not obs_names:
        if corrected:
            doubts.append(f"evento '{header.strip()}' lido como '{known}'")
        return known
    # Com quadro de Observação, o nome aparece 2-3 vezes: vence a grafia (sem '_') mais frequente,
    # e entre as iguais a que tem mais '_' (o OCR às vezes come o sublinhado).
    groups: dict[str, list[str]] = {}
    for c in cands:
        groups.setdefault(re.sub(r"[_\s]", "", c), []).append(c)
    best = max(groups.values(), key=lambda g: (len(g), max(x.count("_") for x in g)))
    name = max(best, key=lambda x: x.count("_"))
    if _squash(name) != _squash(clean(header)):
        doubts.append(f"cabeçalho '{header.strip()}' corrigido para '{name}' pela Observação")
    return name


def read_card(lines: list[OcrLine], file: str) -> ReadCard:
    card = ReadCard(file=file)
    lines = [ln for ln in lines if ln.x < 0.75 and not re.match(r"(?i)^\s*anota", ln.t)]
    if not lines:
        card.doubts.append("nenhum texto lido")
        return card
    tol = 0.6 * statistics.median(ln.h for ln in lines)

    obs_y = min((ln.y for ln in lines if re.match(r"(?i)^\s*observa", ln.t)), default=2.0)
    table = [ln for ln in lines if ln.y < obs_y - tol]
    obs = [ln for ln in lines if ln.y >= obs_y - tol]

    # Coluna esquerda: cabeçalho + nomes de parâmetros (fragmentos na mesma linha são unidos)
    left = _rows([ln for ln in table if ln.x < 0.3], tol)
    exact = {_squash(k) for k in KNOWN_PARAMS}
    merged: list[list[OcrLine]] = []
    for row in left:
        prev = "".join(ln.t.strip() for ln in merged[-1]) if merged else ""
        cur = "".join(ln.t.strip() for ln in row)
        if merged and _squash(prev) not in exact and _squash(prev + cur) in exact:
            merged[-1] = merged[-1] + row  # 'loan_insurance_va' + 'lue'
        else:
            merged.append(row)
    left = merged
    keys: list[tuple[float, str]] = []
    header = ""
    pending: tuple[float, str] | None = None
    for row in left:
        text = "".join(ln.t.strip() for ln in row) if len(row) > 1 else row[0].t
        if not keys and not header and not match_vocab(text, KNOWN_PARAMS)[0]:
            text = " ".join(ln.t for ln in row)
        y = row[0].y
        if pending:
            joined, _ = match_vocab(pending[1] + text, KNOWN_PARAMS)
            if joined and not match_vocab(text, KNOWN_PARAMS)[0]:
                keys.append((pending[0], joined))
                pending = None
                continue
            keys.append(pending)
            pending = None
        key, corrected = match_vocab(text, KNOWN_PARAMS)
        if key:
            if corrected:
                card.doubts.append(f"parâmetro '{text}' lido como '{key}'")
            keys.append((y, key))
        elif not keys and not header:
            header = " ".join(ln.t for ln in row)
        elif not keys:
            header += " " + " ".join(ln.t for ln in row)
        else:
            # pode ser o começo de uma chave quebrada em duas linhas; decide na próxima
            guess = re.sub(r"\W+", "_", text.strip().lower()).strip("_")
            pending = (y, guess)
            card.doubts.append(f"parâmetro desconhecido '{text}' (mantido como '{guess}')")
    if pending:
        keys.append(pending)

    # Coluna direita: cada linha vai para a chave mais próxima acima dela
    by_key: dict[str, list[OcrLine]] = {}
    for ln in sorted((ln for ln in table if ln.x >= 0.3), key=lambda ln: ln.y):
        owner = [k for k in keys if k[0] <= ln.y + tol]
        if not owner:
            if not header or header.strip() in ('"', "'"):
                header = (header + " " + ln.t).strip()
            continue
        by_key.setdefault(owner[-1][1], []).append(ln)
    for _, key in keys:
        vals = by_key.get(key, [])
        if key == "items":
            items = _parse_items(vals, card.doubts)
            card.params[key] = items
            if not items:
                card.doubts.append("items: não foi possível ler o JSON")
        else:
            val = clean_value(_join([ln.t for ln in vals])) if vals else ""
            if key == "screen_name" and re.search(r"\s", re.sub(r"\[[^\]]*\]", "", val)):
                fixed = re.sub(r"\s+(?![^\[]*\])", ":", val)
                card.doubts.append(f"screen_name '{val}' lido como '{fixed}' (espaço vira ':')")
                val = fixed
            card.params[key] = val
            if not vals:
                card.doubts.append(f"valor de '{key}' não lido")

    # Observação: "Preenchimento de [x] no parâmetro P:" + "• valores"
    obs_names: list[str] = []
    acc = ""
    current: str | None = None
    for ln in sorted(obs, key=lambda ln: (ln.y, ln.x)):
        t = ln.t.strip()
        m = re.match(r"(?i)^observa\S*\s+(.+)$", t)
        if m:
            obs_names.append(m.group(1))
            continue
        if BULLET.match(t) and current:
            val, fixed = fix_click(clean_value(BULLET.sub("", t)))
            if fixed:
                card.doubts.append(f"{current}: item '{BULLET.sub('', t)}' lido como '{val}'")
            card.bullets.setdefault(current, []).append(val)
            continue
        acc = (acc + " " + t).strip()
        m = re.search(r"O evento\s+(\S+)\s+deve", acc)
        if m:
            obs_names.append(m.group(1))
        m = re.search(r"(?i)par[aâ]metro\s+([\w ]+?)\s*:", acc)
        if m:
            key, corrected = match_vocab(m.group(1), KNOWN_PARAMS)
            current = key or m.group(1).strip().replace(" ", "_")
            if corrected or not key:
                card.doubts.append(f"Observação: parâmetro '{m.group(1)}' lido como '{current}'")
            acc = ""
        elif len(acc) > 400:
            acc = acc[-200:]
    card.event = _event_name(header, obs_names, card.doubts)
    return card


# ----------------------------------------------------------------------------- spec-modelo

def _section(screen: str) -> str:
    s = re.sub(r"\[[^\]]*\]", "", screen.replace("{fluxo}", ""))
    parts = [p for p in s.split(":") if p and p != "app"]
    return parts[-1] if parts else "geral"


def _apply(value: Any, fn: Any) -> Any:
    if isinstance(value, str):
        return fn(value)
    if isinstance(value, list):
        return [_apply(v, fn) for v in value]
    if isinstance(value, dict):
        return {k: _apply(v, fn) for k, v in value.items()}
    return value


def _items_template(items: list[dict[str, str]], doubts: list[str]) -> list[dict[str, str]]:
    if not items:
        return []
    first = dict(items[0])
    if len(items) > 1:
        for k in list(first):
            vals = [it.get(k) for it in items if it.get(k)]
            stems = {re.sub(r"\d+$", "", x) for x in vals}
            if len(set(vals)) > 1 and len(stems) == 1 and all(re.search(r"\d+$", x) for x in vals):
                first[k] = stems.pop() + ("[preenchido]" if k.endswith("_id") else "[numero]")
                doubts.append(f"items.{k}: exemplos {vals} viraram o padrão '{first[k]}'")
        doubts.append(f"items: a spec mostra {len(items)} itens; só o primeiro é validado")
    return [first]


def build_spec(
    cards: list[ReadCard],
    projeto: str,
    plataforma: str = "android",
    prints_dir: str | None = None,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Gera (spec-modelo, revisão por card)."""
    flows: list[str] = []
    for c in cards:
        for alt in WORD_ALT.findall(str(c.params.get("flow_name", "")) + " " + c.event):
            for opt in re.split(r"\s*\|\s*", alt):
                if opt not in flows:
                    flows.append(opt)
    flow_re = None
    if flows:
        flow_re = re.compile(r"\[\s*(?:" + "|".join(re.escape(f) for f in flows) + r")(?:\s*\|\s*(?:"
                             + "|".join(re.escape(f) for f in flows) + r"))+\s*\]")

    spec_cards: list[dict[str, Any]] = []
    review: list[dict[str, Any]] = []
    sections: list[str] = []
    for c in cards:
        doubts = list(c.doubts)

        def templ(s: str) -> str:
            return flow_re.sub("{fluxo}", s) if flow_re else s

        event = templ(c.event)
        params: dict[str, Any] = {k: _apply(v, templ) for k, v in c.params.items()}
        bullets = {k: [templ(b) for b in v] for k, v in c.bullets.items()}
        per_flow = flow_re is not None and "{fluxo}" in (event + str(params) + str(bullets))

        # Variações: details (Observação) x alternativas de tela que não são fluxo
        variations: list[dict[str, Any]] = []
        screen_opts: list[dict[str, Any]] = [{}]
        screen = str(params.get("screen_name", ""))
        m = WORD_ALT.search(screen)
        if m:
            opts = re.split(r"\s*\|\s*", m.group(1))
            screen_opts = [{"screen_name": screen[:m.start()] + o + screen[m.end():]} for o in opts]
            params.pop("screen_name")
        detail_opts: list[dict[str, Any]] = [{}]
        table_detail = map_descriptive(str(params.get("detail", "")))
        if bullets.get("detail") and "[numero]" in table_detail:
            # Exemplos ('click:10-parcela-com-seguro') generalizados pelo padrão da tabela
            general = []
            for b in bullets["detail"]:
                g = re.sub(r"\d+", "[numero]", b) if value_matches(table_detail, b) else b
                if g != b:
                    doubts.append(f"detail: exemplo '{b}' generalizado para '{g}' (padrão da tabela)")
                general.append(g)
            bullets["detail"] = list(dict.fromkeys(general))
        if bullets.get("detail"):
            detail_opts = [{"detail": d} for d in bullets.pop("detail")]
            params.pop("detail", None)
        for s_opt, d_opt in product(screen_opts, detail_opts):
            if s_opt or d_opt:
                variations.append({**s_opt, **d_opt})

        for k, vals in bullets.items():
            uniq = list(dict.fromkeys(vals))
            if len(uniq) == 1:
                params[k] = uniq[0]
            else:
                params[k] = "[" + "|".join(uniq) + "]"
                doubts.append(f"{k} aceita {uniq}; se cada variação usa um valor específico, ajuste em 'variacoes'")

        for k, v in list(params.items()):
            if k == "items":
                params[k] = _items_template(v, doubts)
            elif isinstance(v, str):
                params[k] = map_descriptive(v)

        params_por_fluxo: dict[str, dict[str, Any]] = {}
        if per_flow and params.get("items"):
            item = params["items"][0]
            for f in flows:
                if any(re.search(rf"(?<![\w]){re.escape(f)}(?![\w])", str(v)) for v in item.values()):
                    for ik, iv in list(item.items()):
                        if re.search(rf"(?<![\w]){re.escape(f)}(?![\w])", str(iv)):
                            item[ik] = re.sub(rf"(?<![\w]){re.escape(f)}(?![\w])", "{fluxo}", iv)
                        elif ik.endswith("_id") and "[" not in iv:
                            params_por_fluxo.setdefault(f, {"items": [{}]})["items"][0][ik] = iv
                            item[ik] = "[preenchido]"
                    doubts.append(f"items: exemplo da spec é do fluxo '{f}'; item_id fixado só para '{f}'")
                    break

        if per_flow:
            for k, v in params.items():
                for f in flows:
                    if isinstance(v, str) and re.search(rf"(?<![\w]){re.escape(f)}(?![\w])", v):
                        doubts.append(f"{k}='{v}' cita o fluxo '{f}' fixo num card por fluxo — confira")

        sec_src = screen or str(params.get("screen_name", ""))
        sec = _section(sec_src) if sec_src else "geral"
        if sec not in sections:
            sections.append(sec)
        entry: dict[str, Any] = {
            "secao": f"{sections.index(sec) + 1}. {sec}",
            "titulo": f"{event or '?'} · {sec}",
            "print": Path(c.file).name,
            "evento": event,
            "params": params,
        }
        if variations:
            entry["variacoes"] = variations
        if params_por_fluxo:
            entry["params_por_fluxo"] = params_por_fluxo
        if not event:
            doubts.append("card sem nome de evento — preencha 'evento'")
        spec_cards.append(entry)
        review.append({"print": Path(c.file).name, "evento": event, "duvidas": doubts})

    spec: dict[str, Any] = {
        "projeto": projeto,
        "versao_especificacao": "Rascunho gerado por OCR — revisar",
        "plataforma": plataforma,
    }
    if prints_dir:
        spec["prints_dir"] = prints_dir
    spec["fluxos"] = {f: f for f in flows}
    spec["cards"] = spec_cards
    return spec, review


def review_markdown(spec: dict[str, Any], review: list[dict[str, Any]]) -> str:
    total = sum(len(r["duvidas"]) for r in review)
    md = [f"# Revisão do rascunho — {spec['projeto']}", "",
          f"{len(review)} prints lidos · {total} ponto(s) para conferir. "
          "Corrija direto no JSON e audite de novo na aba Relatório.", ""]
    if spec.get("fluxos"):
        md += [f"Fluxos detectados: {', '.join(spec['fluxos'])} (renomeie os rótulos em 'fluxos' se quiser).", ""]
    for i, r in enumerate(review, 1):
        md.append(f"## {i}. {r['evento'] or '(sem evento)'} — `{r['print']}`")
        md += [f"- ⚠ {d}" for d in r["duvidas"]] or ["- ✓ nada a conferir"]
        md.append("")
    return "\n".join(md)

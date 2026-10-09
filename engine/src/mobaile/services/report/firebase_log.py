"""Leitura do log de Firebase Analytics para a auditoria.

Portado do `tag_audit` (parsers/firebase_log). Aceita os formatos que circulam
no time:

- a lista que o próprio Mo baile exporta em ``log_obtido.json`` (e o que a
  escuta tem em memória, que é o mesmo `AnalyticsEvent.to_dict`);
- objeto com ``eventos`` ou com ``jornadas`` (logs consolidados à mão);
- Logcat em texto, onde cada linha ``Logging event:`` vira um evento.

Regras de leitura:

- logs mistos são filtrados pela plataforma: Android é a tag ``FA-SVC`` no
  ``raw_log``; iOS é ``FirebaseAnalytics`` ou a tag ``iOS (Firebase)``;
- no Android os parâmetros são relidos do ``raw_log``, que preserva o Bundle
  aninhado de ``items``;
- disparos repetidos (mesmo horário, nome e parâmetros) contam uma vez;
- a ordem final é a do horário do log, com empate na ordem do arquivo.
"""

from __future__ import annotations

import json
import re
from typing import Any

from mobaile.domain.report import TagEvent
from mobaile.services.report.rules import clean_colon_spacing, strip_event_suffixes, strip_param_key_suffixes

ANDROID_LINE = re.compile(r"Logging event:\s*origin=([^,]+),name=([^,]+),params=(Bundle\[.*\])\s*$")
LOGCAT_TIME = re.compile(r"^(?:\d{2}-\d{2}\s+)?(\d{2}:\d{2}:\d{2}\.\d{3})")
LOG_DATE = re.compile(r"^(?:(\d{4})-)?(\d{2}-\d{2})\s")


def _split_top_level(text: str) -> list[str]:
    """Divide por vírgulas que não estão dentro de [] ou {}."""
    parts: list[str] = []
    depth = 0
    current = ""
    for ch in text:
        if ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    if current.strip():
        parts.append(current)
    return parts


def parse_bundle(text: str) -> dict[str, Any]:
    """``Bundle[{k=v, items=[Bundle[{...}]]}]`` em dicionário.

    As chaves perdem o sufixo do SDK (``ga_screen(_sn)`` vira ``ga_screen``) e
    lista de Bundles vira lista de objetos.
    """
    body = text.strip()
    if body.startswith("Bundle[{") and body.endswith("}]"):
        body = body[8:-2]
    out: dict[str, Any] = {}
    for part in _split_top_level(body):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        key = strip_param_key_suffixes(key.strip())
        value = value.strip()
        if value.startswith("[Bundle[") and value.endswith("]"):
            out[key] = [parse_bundle(b) for b in _split_top_level(value[1:-1])]
        else:
            out[key] = clean_colon_spacing(value)
    return out


def parse_ios_items(text: str) -> list[dict[str, str]]:
    """``[ { item_id = x; price = 1; }, {...} ]`` do iOS em lista de objetos."""
    out: list[dict[str, str]] = []
    for block in re.findall(r"\{([^{}]*)\}", text):
        item = {}
        for key, value in re.findall(r"([\w]+)\s*=\s*([^;]*);", block):
            item[key.strip()] = value.strip().strip('"')
        if item:
            out.append(item)
    return out


def detect_platform(item: dict[str, Any]) -> str:
    """Tag ``FA-SVC`` é Android; ``FirebaseAnalytics`` é iOS; senão, o campo ``platform``."""
    raw = str(item.get("raw_log") or "")
    tag = str(item.get("tag") or "")
    if "FA-SVC" in raw or "FA-SVC" in tag:
        return "android"
    if "FirebaseAnalytics" in raw or tag.lower().startswith("ios"):
        return "ios"
    return str(item.get("platform") or "unknown").lower()


def _from_android_raw(raw: str) -> tuple[str, str, dict[str, Any]] | None:
    match = ANDROID_LINE.search(raw.strip())
    if not match:
        return None
    return match.group(1).strip(), strip_event_suffixes(match.group(2).strip()), parse_bundle(match.group(3))


def items_from_json(data: Any) -> list[dict[str, Any]]:
    """Eventos crus de qualquer um dos formatos JSON aceitos."""
    if isinstance(data, list):
        return [i for i in data if isinstance(i, dict)]
    if isinstance(data, dict):
        if isinstance(data.get("eventos"), list):
            return [i for i in data["eventos"] if isinstance(i, dict)]
        if isinstance(data.get("jornadas"), dict):
            out: list[dict[str, Any]] = []
            for jornada in data["jornadas"].values():
                eventos = jornada.get("eventos") if isinstance(jornada, dict) else jornada
                if isinstance(eventos, list):
                    out.extend(i for i in eventos if isinstance(i, dict))
            return out
        return [data]
    return []


def items_from_text(content: str) -> list[dict[str, Any]]:
    """JSON quando é JSON; senão Logcat em texto, uma linha ``Logging event:`` por evento."""
    try:
        return items_from_json(json.loads(content))
    except json.JSONDecodeError:
        return [{"raw_log": line, "tag": "FA-SVC"} for line in content.splitlines() if "Logging event:" in line]


def events_from_items(
    items: list[dict[str, Any]],
    platform: str,
    dedupe: bool = True,
) -> tuple[list[TagEvent], dict[str, int]]:
    """Normaliza os eventos da plataforma pedida.

    Devolve os eventos em ordem de horário e as estatísticas da leitura:
    ``total_lidos``, ``da_plataforma``, ``duplicados`` e ``uteis``.
    """
    platform = platform.lower()
    stats = {"total_lidos": len(items), "da_plataforma": 0, "duplicados": 0, "uteis": 0}
    seen: set[tuple[Any, ...]] = set()
    events: list[TagEvent] = []
    order: dict[int, str] = {}
    for index, item in enumerate(items):
        if detect_platform(item) != platform:
            continue
        stats["da_plataforma"] += 1
        raw = str(item.get("raw_log") or "")
        parsed = _from_android_raw(raw) if platform == "android" else None
        if parsed:
            origin, name, params = parsed
        else:
            name = strip_event_suffixes(str(item.get("event_name") or item.get("event") or "").strip())
            raw_params = item.get("params") if isinstance(item.get("params"), dict) else {}
            params = {
                strip_param_key_suffixes(k): (clean_colon_spacing(v) if isinstance(v, str) else v)
                for k, v in raw_params.items()
            }
            origin = str(params.get("ga_event_origin") or "")
            if isinstance(params.get("items"), str) and "=" in params["items"]:
                params["items"] = parse_ios_items(params["items"])
        if not name:
            continue
        time_str = item.get("time_str") or item.get("time")
        if not time_str:
            found = LOGCAT_TIME.match(raw)
            time_str = found.group(1) if found else None
        if dedupe:
            key = (time_str, name, json.dumps(params, sort_keys=True, ensure_ascii=False, default=str))
            if key in seen:
                stats["duplicados"] += 1
                continue
            seen.add(key)
        date = LOG_DATE.match(raw)
        order[len(events)] = f"{date.group(2) if date else ''} {time_str or ''}"
        events.append(
            TagEvent(
                id=item.get("id", index),
                event_name=name,
                params=params,
                platform=platform,
                raw_log=raw or None,
                time_str=str(time_str) if time_str else None,
                origin=origin or None,
            )
        )
    events = [event for _, event in sorted(enumerate(events), key=lambda pair: order[pair[0]])]
    stats["uteis"] = len(events)
    return events, stats

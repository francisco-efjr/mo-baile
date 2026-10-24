#!/usr/bin/env python3
"""Mede a auditoria de tagueamento (aba Relatório) num cenário grande e sintético.

Gera uma spec com dezenas de cards e fluxos e um log Android + iOS com milhares
de eventos, cobrindo as armadilhas do casamento (duplicados, disparo antigo
divergente, `screen_name` errado na tela certa, fora da spec, alertas e
ruído do SDK). Mede cada etapa de `report.audit` e do `report.export`, e
imprime uma impressão digital (SHA-256) do payload e dos arquivos: se ela
não muda entre duas versões do motor, o resultado é o mesmo.

    .venv/bin/python tools/bench_report.py [--eventos 20000] [--cards 80] [--fluxos 4] [--repeticoes 3]
    .venv/bin/python tools/bench_report.py --json   # números em JSON, para o relatório em docs/
    MOBAILE_ENGINE_SRC=/tmp/antes/engine/src .venv/bin/python tools/bench_report.py   # outra cópia do motor

Dados inventados: nada de log real de cliente.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import random
import statistics
import sys
import tempfile
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

# MOBAILE_ENGINE_SRC aponta para outra cópia do motor (uma versão antiga, por
# exemplo, tirada com `git archive`), para medir antes e depois com o mesmo cenário.
sys.path.insert(0, os.environ.get("MOBAILE_ENGINE_SRC") or str(Path(__file__).resolve().parents[1] / "engine" / "src"))

from PIL import Image

from mobaile.domain.report import SpecTemplate
from mobaile.services.report import (
    ReportService,
    audit,
)
from mobaile.services.report.board import build_board
from mobaile.services.report.documents import generate_markdown, generate_tsv
from mobaile.services.report.firebase_log import events_from_items, items_from_text
from mobaile.services.report.html_report import generate_interactive_html
from mobaile.services.report.rules import expand_spec

FIXED_NOW = datetime.datetime(2026, 10, 23, 12, 0, 0)
SECTIONS = ("Home", "Simulação", "Contratação", "Pagamento", "Perfil", "Ajuda", "Extrato", "Cartões",
            "Investimentos", "Seguros")


def build_spec(cards: int, flows: int, prints_dir: Path | None) -> dict[str, Any]:
    fluxos = {f"f{i}": f"F{i} · fluxo-{i}" for i in range(flows)}
    out = []
    for n in range(cards):
        secao = SECTIONS[n * len(SECTIONS) // cards]
        kind = n % 4
        card: dict[str, Any] = {"secao": secao, "titulo": f"Card {n}"}
        if prints_dir is not None:
            card["print"] = f"card-{n:03d}.png"
        if kind == 0:
            card |= {"evento": "screen_view",
                     "params": {"screen_name": f"app:s{n}:{{fluxo}}:tela", "flow_name": "fluxo-{fluxo}"}}
        elif kind == 1:
            card |= {"evento": f"interaction_s{n}_{{fluxo}}",
                     "params": {"screen_name": f"app:s{n}:{{fluxo}}:tela", "flow_name": "fluxo-{fluxo}",
                                "component": "button"},
                     "variacoes": [{"detail": "click:parcelas"}, {"detail": "click:[numero]-parcela"},
                                   {"detail": "click:[sim|nao]"}]}
        elif kind == 2:
            card |= {"evento": "add_to_cart",
                     "params": {"screen_name": f"app:s{n}:{{fluxo}}:tela", "flow_name": "fluxo-{fluxo}",
                                "insurance": "[0|1]", "value": "[numero]",
                                "items": [{"item_id": "[preenchido]", "item_name": "item-{fluxo}"}]},
                     "params_por_fluxo": {"f0": {"items": [{"item_id": "14063"}]}}}
        else:
            card |= {"evento": f"view_s{n}",
                     "params": {"screen_name": f"app:s{n}:{{fluxo}}:tela", "flow_name": "fluxo-{fluxo}",
                                "detail": "re:card-[0-9a-f]{4}", "date": "[data]"},
                     "obs": "Confere a data no fuso de Brasília."}
        out.append(card)
    return {"projeto": "Bench", "plataforma": "android", "versao_especificacao": "v1", "fluxos": fluxos,
            "prints_dir": str(prints_dir) if prints_dir else None, "cards": out}


def _android(stamp: str, name: str, params: dict[str, Any], id_: int) -> dict[str, Any]:
    parts = []
    for key, value in params.items():
        if key == "items":
            inner = ", ".join(f"{k}={v}" for k, v in value[0].items())
            parts.append(f"items=[Bundle[{{{inner}}}]]")
        else:
            parts.append(f"{key}={value}")
    bundle = ", ".join(parts)
    raw = f"10-08 {stamp} V/FA-SVC  (1): Logging event: origin=app,name={name},params=Bundle[{{{bundle}}}]"
    return {"id": id_, "event_name": name, "params": {}, "platform": "android", "raw_log": raw, "tag": "FA-SVC",
            "time_str": stamp}


def build_log(spec: dict[str, Any], total: int, seed: int = 7) -> list[dict[str, Any]]:
    """Eventos que exercitam a spec: certos, divergentes, fora da spec, ruído e iOS."""
    rnd = random.Random(seed)
    flows = list(spec["fluxos"])
    out: list[dict[str, Any]] = []
    for i in range(total):
        # O horário é sorteado: a ordenação final precisa fazer o trabalho dela.
        secs = rnd.randint(0, 6 * 3600)
        stamp = f"{10 + secs // 3600:02d}:{secs // 60 % 60:02d}:{secs % 60:02d}.{rnd.randint(0, 999):03d}"
        roll = rnd.random()
        n = rnd.randrange(len(spec["cards"]))
        if n % 13 == 12:
            n -= 1  # um card em cada 13 nunca dispara: vira "não disparado"
        flow = rnd.choice(flows)
        screen = f"app:s{n}:{flow}:tela"
        base = {"screen_name": screen, "flow_name": f"fluxo-{flow}", "ga_event_origin(_o)": "app"}
        if roll < 0.05:
            out.append({"id": i, "event_name": "screen_view", "params": {"ga_screen": screen,
                        "flow_name": f"fluxo-{flow}"}, "platform": "ios", "tag": "iOS (Firebase)",
                        "raw_log": "[FirebaseAnalytics][I-ACS023073] ...", "time_str": stamp})
            continue
        if roll < 0.10:
            out.append(_android(stamp, rnd.choice(("session_start(_s)", "user_engagement(_e)", "CfgFetch_ok",
                                                   "swipe_left", "LS_carga")), {"ga_event_origin(_o)": "auto"}, i))
            continue
        if roll < 0.13:
            out.append(_android(stamp, "modal_view", base | {"component": "modal", "detail": f"extra-{n % 7}"}, i))
            continue
        if roll < 0.14:
            out.append(_android(stamp, "app_exception(_ae)", {"ga_screen(_sn)": screen, "fatal": "1"}, i))
            continue
        if roll < 0.16:
            # mesma ação numa tela fora da spec
            out.append(_android(stamp, "screen_view(_vs)", base | {"screen_name": f"app:s{n}:{flow}:outra"}, i))
            continue
        kind = n % 4
        wrong = rnd.random() < 0.2
        if kind == 0:
            params = {"ga_screen(_sn)": screen, "flow_name": f"fluxo-{flow}", "ga_event_origin(_o)": "app"}
            name = "screen_view(_vs)"
        elif kind == 1:
            detail = rnd.choice(("click:parcelas", f"click:{rnd.randint(1, 24)}-parcela", "click:sim", "click:nao"))
            params = base | {"component": "toggle" if wrong else "button", "detail": detail,
                             "ga_screen(_sn)": screen}
            name = f"interaction_s{n}_{flow}"
        elif kind == 2:
            params = base | {"insurance": "2" if wrong else rnd.choice("01"), "value": f"{rnd.randint(1, 900)}.5",
                             "items": [{"item_name": f"item-{flow}", "item_id": "14063" if flow == "f0" else "9"}]}
            if rnd.random() < 0.1:
                # screen_name errado na tela certa (ga_screen)
                params = params | {"screen_name": f"app:s{n}:{flow}:errada", "ga_screen(_sn)": screen}
            name = "add_to_cart"
        else:
            params = base | {"detail": "card-zzzz" if wrong else f"card-{rnd.randint(0, 0xffff):04x}",
                             "date": "08/10/2026"}
            name = f"view_s{n}"
        event = _android(stamp, name, params, i)
        out.append(event)
        if rnd.random() < 0.05:
            out.append(dict(event))  # duplicado
    return out


def write_prints(folder: Path, cards: int) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for n in range(cards):
        Image.new("RGB", (360, 780), (20 + n % 200, 90, 160)).save(folder / f"card-{n:03d}.png")


def timed(fn: Callable[[], Any], repeat: int) -> tuple[float, Any]:
    """Mediana em milissegundos e o último resultado."""
    times, result = [], None
    for _ in range(repeat):
        start = time.perf_counter()
        result = fn()
        times.append((time.perf_counter() - start) * 1000)
    return statistics.median(times), result


def digest(value: Any) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
    return hashlib.sha256(text.encode()).hexdigest()[:16]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--eventos", type=int, default=20000)
    parser.add_argument("--cards", type=int, default=80)
    parser.add_argument("--fluxos", type=int, default=4)
    parser.add_argument("--repeticoes", type=int, default=3)
    parser.add_argument("--sem-prints", action="store_true", help="não gera prints dos cards")
    parser.add_argument("--json", action="store_true", help="saída em JSON")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="mobaile-bench-") as tmp:
        base = Path(tmp)
        prints = None if args.sem_prints else base / "prints"
        if prints is not None:
            write_prints(prints, args.cards)
        spec_dict = build_spec(args.cards, args.fluxos, prints)
        log = build_log(spec_dict, args.eventos)
        spec_path, log_path = base / "spec.json", base / "log.json"
        spec_path.write_text(json.dumps(spec_dict, ensure_ascii=False), encoding="utf-8")
        log_path.write_text(json.dumps(log, ensure_ascii=False), encoding="utf-8")
        content = log_path.read_text(encoding="utf-8")

        spec = SpecTemplate.from_dict(spec_dict)
        variants = expand_spec(spec)
        r = args.repeticoes
        ms: dict[str, float] = {}
        ms["ler_log"], items = timed(lambda: items_from_text(content), r)
        ms["normalizar"], (events, stats) = timed(lambda: events_from_items(items, "android"), r)
        # Antes da 3.9.1 não havia índice: cada variação varria a lista inteira.
        index_of = getattr(audit, "EventIndex", None)

        def per_variant() -> list[Any]:
            pool = index_of(events) if index_of else events
            return [audit.audit_variant(v, pool) for v in variants]

        ms["variacoes"], results = timed(per_variant, r)
        ms["fora_da_spec"], _ = timed(lambda: audit.find_extras(variants, events), r)

        service = ReportService(documents_dir=base / "docs", now=lambda: FIXED_NOW)
        ms["report.audit"], payload = timed(
            lambda: service.audit(str(spec_path), items, source="file", log_path=log_path), r)
        report = service._last[0]
        ms["board"], board = timed(lambda: json.dumps(build_board(report), ensure_ascii=False), r)
        ms["html"], html_text = timed(lambda: generate_interactive_html(report, generated_at=FIXED_NOW), r)
        ms["markdown"], markdown = timed(lambda: generate_markdown(report), r)
        ms["tsv"], tsv = timed(lambda: generate_tsv(report), r)
        ms["report.export"], _ = timed(lambda: service.export(str(base / "out")), r)

        # A pasta temporária muda a cada execução; a impressão digital não pode mudar com ela.
        def neutral(value: Any) -> Any:
            text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, sort_keys=True)
            return text.replace(str(base), "<tmp>")

        fingerprint = {
            "payload": digest(neutral(payload)),
            "board": digest(neutral(board)),
            "html": digest(neutral(html_text)),
            "markdown": digest(markdown),
            "tsv": digest(tsv),
        }
        scenario = {"log_mb": round(log_path.stat().st_size / 1024 / 1024, 1), "eventos_no_log": len(log), "eventos_uteis": stats["uteis"], "duplicados": stats["duplicados"],
                    "cards": args.cards, "fluxos": args.fluxos, "variacoes": len(variants),
                    "ok": payload["summary"]["ok"], "divergentes": payload["summary"]["divergent"],
                    "nao_disparadas": payload["summary"]["missing"], "fora_da_spec": payload["summary"]["extras"],
                    "alertas": payload["summary"]["alerts"], "results": len(results)}

    if args.json:
        print(json.dumps({"cenario": scenario, "ms": ms, "impressao_digital": fingerprint}, ensure_ascii=False,
                         indent=2))
        return 0
    print("Cenário: " + ", ".join(f"{k}={v}" for k, v in scenario.items()))
    print(f"Mediana de {r} execução(ões), em ms:")
    for key, value in ms.items():
        print(f"  {key:<14}{value:>10.1f}")
    print("Impressão digital: " + " ".join(f"{k}={v}" for k, v in fingerprint.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

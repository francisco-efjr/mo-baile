"""Export de exploração do Google Analytics 4 em TSV, como log da auditoria.

É o arquivo de "Fazer o download dos dados" em TSV de uma exploração de forma
livre. Diferente de um logcat, ele não traz disparos: traz combinações já
somadas (evento + as dimensões escolhidas + métricas). O formato é:

- linhas de comentário com ``#`` no topo (propriedade, nome da exploração, período);
- opcionalmente, uma linha de pivô de colunas: células vazias até o nome da
  dimensão de coluna (``Sistema operacional``), seguido do valor dela em cada
  coluna de métrica (``iOS``, ``Android``) e de ``Totais``;
- o cabeçalho: as dimensões de linha (``Nome do evento``, ``firebase_screen``,
  ``flow_name``…) e, depois, o nome das métricas;
- a linha de totais (dimensões vazias) e as linhas de dados.

Cada linha com métrica maior que zero vira um evento, uma vez por plataforma
da coluna. As dimensões viram parâmetros com o mesmo nome; ``firebase_screen``
(e os nomes de tela do GA4) vira ``ga_screen``, como no logcat. ``(not set)``
é parâmetro exportado e vazio. A lista do que foi exportado vai em cada item
(``exportados``): o que a spec pede e o export não traz não é divergência, é
"não exportado" (`audit.check_params`).
"""

from __future__ import annotations

import re
from typing import Any

EVENT_HEADERS = frozenset({"nome do evento", "event name", "eventname", "event_name"})
PLATFORM_HEADERS = frozenset({"sistema operacional", "operating system", "operatingsystem", "plataforma", "platform"})
SCREEN_HEADERS = frozenset({
    "firebase_screen", "nome da tela", "screen name", "título da página e nome da tela",
    "page title and screen name", "unifiedscreenname",
})
TOTAL_LABELS = frozenset({"totais", "totals", "total", "total geral", "grand total"})
NOT_SET = frozenset({"(not set)", "(não definido)", "(nao definido)"})
# Sem pivô, métrica é a coluna da direita com número em todas as linhas e nome
# de gente ("Total de usuários", "eventCount"), não de parâmetro ("flow_name").
_PARAM_LIKE = re.compile(r"^[a-z0-9_]+$")
_POSITIVE = re.compile(r"[1-9]")
# Plataforma do item quando o export não diz qual: vale para a plataforma auditada.
ANY_PLATFORM = "qualquer"


def _norm(cell: str) -> str:
    return cell.strip().lstrip("﻿").strip().lower()


def _rows(content: str) -> list[list[str]]:
    rows = []
    for line in content.splitlines():
        if not line.strip() or line.lstrip("﻿").lstrip().startswith("#"):
            continue
        rows.append(line.split("\t"))
    return rows


def _header_index(rows: list[list[str]]) -> int | None:
    for i, row in enumerate(rows[:40]):
        if len(row) > 1 and any(_norm(cell) in EVENT_HEADERS for cell in row):
            return i
    return None


def looks_like_ga4_tsv(content: str) -> bool:
    """O texto é um export TSV do GA4 com a coluna do nome do evento?"""
    return "\t" in content and _header_index(_rows(content)) is not None


def _param_key(header: str) -> str:
    return "ga_screen" if _norm(header) in SCREEN_HEADERS else header.strip()


def _platform(value: str) -> str:
    return _norm(value) or ANY_PLATFORM


def _positive(cell: str) -> bool:
    return bool(_POSITIVE.search(cell))


def items_from_ga4_tsv(content: str) -> list[dict[str, Any]]:
    """Itens no formato da leitura do log, um por linha e plataforma com métrica maior que zero."""
    rows = _rows(content)
    header_index = _header_index(rows)
    if header_index is None:
        return []
    header = [cell.strip() for cell in rows[header_index]]
    data = rows[header_index + 1:]

    # Pivô de colunas: a linha logo acima do cabeçalho, vazia até o nome da dimensão.
    pivot = rows[header_index - 1] if header_index > 0 else None
    pivot_at = next((i for i, cell in enumerate(pivot) if cell.strip()), None) if pivot else None
    if pivot is not None and pivot_at is not None and 0 < pivot_at < len(header) - 1:
        dims = list(range(pivot_at + 1))
        metric_cols = list(range(pivot_at + 1, len(header)))
        by_platform = _norm(pivot[pivot_at]) in PLATFORM_HEADERS
        column_value = {j: (pivot[j].strip() if j < len(pivot) else "") for j in metric_cols}
    else:
        def numeric(j: int) -> bool:
            cells = [row[j].strip() for row in data if j < len(row) and row[j].strip()]
            return bool(cells) and all(re.fullmatch(r"[\d.,\s%-]+", cell) for cell in cells)

        first_metric = len(header)
        while first_metric > 1 and numeric(first_metric - 1) and not _PARAM_LIKE.match(header[first_metric - 1]):
            first_metric -= 1
        dims = list(range(first_metric))
        metric_cols = list(range(first_metric, len(header)))
        by_platform = False
        column_value = {}

    event_col = next(i for i in dims if _norm(header[i]) in EVENT_HEADERS)
    platform_col = next((i for i in dims if _norm(header[i]) in PLATFORM_HEADERS), None)
    param_cols = [i for i in dims if i not in (event_col, platform_col)]
    exported = [_param_key(header[i]) for i in param_cols]

    items: list[dict[str, Any]] = []
    for row in data:
        cells = [row[i].strip() if i < len(row) else "" for i in range(len(header))]
        event = cells[event_col]
        if not event or all(not cells[i] for i in dims):
            continue  # linha de totais ou vazia
        params: dict[str, Any] = {}
        for i in param_cols:
            value = cells[i]
            params[_param_key(header[i])] = None if _norm(value) in NOT_SET or not value else value
        row_platform = _platform(cells[platform_col]) if platform_col is not None else ANY_PLATFORM
        if by_platform:
            targets = [
                (_platform(column_value[j]), cells[j]) for j in metric_cols
                if _norm(column_value[j]) not in TOTAL_LABELS and column_value[j]
            ]
        else:
            totals = [j for j in metric_cols if _norm(column_value.get(j, "")) in TOTAL_LABELS]
            col = totals[0] if totals else (metric_cols[0] if metric_cols else None)
            targets = [(row_platform, cells[col] if col is not None else "1")]
        for platform, count in targets:
            if not _positive(count):
                continue
            items.append({
                "event_name": event,
                "params": dict(params),
                "platform": platform,
                "exportados": list(exported),
            })
    return items

"""Caso de uso da aba Relatório: auditar o tagueamento contra a spec do Figma.

Junta as peças portadas do `tag_audit` (projeto bold-kepler) num serviço só,
que o servidor RPC chama:

- `spec`: lê e valida a spec-modelo e devolve o resumo;
- `audit`: cruza a spec com o log (um arquivo, ou os eventos que a escuta de
  Analytics já capturou nesta sessão) e guarda o relatório;
- `export`: grava o board Excalidraw, o HTML, o Markdown e o TSV do último
  relatório;
- `import_prints`: lê os prints dos cards com OCR e grava o rascunho da spec,
  com a lista do que revisar;
- `card` e `update_card`: leem e gravam um card da spec, para corrigir o que o
  OCR leu sem abrir o JSON.

O nome dos arquivos, a pasta padrão e o texto de cada variação são regra do
produto e moram aqui: a interface só mostra e escolhe caminhos.
"""

from __future__ import annotations

import datetime
import json
import logging
import os
import threading
from collections.abc import Callable
from pathlib import Path
from typing import Any

from mobaile.domain.errors import InvalidInputError
from mobaile.domain.report import PLATFORMS, AuditReport, SpecTemplate, TagEvent, VariantResult
from mobaile.ports import TextRecognizer
from mobaile.security import (
    IMAGE_SUFFIXES,
    MAX_LOG_BYTES,
    MAX_SPEC_BYTES,
    prepare_output_dir,
    safe_file_stem,
    unique_path,
    validate_input_dir,
    validate_input_file,
)
from mobaile.services.report.audit import run_audit
from mobaile.services.report.board import build_board, flow_short_label, observation_lines, variant_block_text
from mobaile.services.report.card_reader import build_spec, read_card, review_markdown
from mobaile.services.report.documents import (
    divergences_text,
    generate_html,
    generate_markdown,
    generate_tsv,
    variation_text,
)
from mobaile.services.report.firebase_log import events_from_items, items_from_text
from mobaile.services.report.rules import expand_spec

logger = logging.getLogger(__name__)

Progress = Callable[[str, float | None], None]
CheckCancelled = Callable[[], None]

BOARD_FILE = "board_auditoria.excalidraw"
HTML_FILE = "relatorio_auditoria.html"
MARKDOWN_FILE = "relatorio_auditoria.md"
TSV_FILE = "relatorio_auditoria.tsv"
# Mais que isso não é um card por print: é a pasta errada.
MAX_PRINTS = 300
LOG_SUFFIXES = (".json", ".txt", ".log")


def _no_progress(_message: str, _percent: float | None = None) -> None:
    return None


def _no_check() -> None:
    return None


def _display(value: Any) -> str | None:
    """Valor do log como texto de relatório; `None` quando o parâmetro não veio."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


class ReportService:
    def __init__(
        self,
        ocr: TextRecognizer | None = None,
        documents_dir: Path | None = None,
        now: Callable[[], datetime.datetime] = datetime.datetime.now,
    ) -> None:
        self._ocr = ocr
        self._documents = documents_dir or (Path.home() / "Documents" / "Mo baile")
        self._now = now
        self._lock = threading.Lock()
        self._last: tuple[AuditReport, Path] | None = None

    # ------------------------------------------------------------------- spec

    @staticmethod
    def _read_spec_json(raw_path: object) -> tuple[Any, Path]:
        path = validate_input_file(raw_path, label="spec", max_bytes=MAX_SPEC_BYTES, suffixes=(".json",))
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except UnicodeDecodeError as exc:
            raise InvalidInputError(f"A spec {path.name} não está em UTF-8.") from exc
        except json.JSONDecodeError as exc:
            raise InvalidInputError(
                f"A spec {path.name} não é um JSON válido (linha {exc.lineno}, coluna {exc.colno})."
            ) from exc
        return data, path

    def load_spec(self, raw_path: object) -> tuple[SpecTemplate, Path]:
        data, path = self._read_spec_json(raw_path)
        spec = SpecTemplate.from_dict(data)
        if spec.prints_dir and not Path(spec.prints_dir).expanduser().is_absolute():
            # Relativo à spec, como no tag_audit: a pasta da demanda anda junto.
            spec.prints_dir = str((path.parent / spec.prints_dir).resolve())
        elif spec.prints_dir:
            spec.prints_dir = str(Path(spec.prints_dir).expanduser())
        return spec, path

    def spec(self, raw_path: object) -> dict[str, Any]:
        spec, path = self.load_spec(raw_path)
        return self.spec_summary(spec, path)

    @staticmethod
    def spec_summary(spec: SpecTemplate, path: Path) -> dict[str, Any]:
        sections: list[str] = []
        for card in spec.cards:
            if card.secao not in sections:
                sections.append(card.secao)
        prints_dir = Path(spec.prints_dir) if spec.prints_dir else None
        return {
            "path": str(path),
            "projeto": spec.projeto,
            "versao_especificacao": spec.versao_especificacao,
            "plataforma": spec.plataforma,
            "prints_dir": str(prints_dir) if prints_dir else None,
            "prints_dir_exists": bool(prints_dir and prints_dir.is_dir()),
            # Lista, e não objeto: a ordem dos fluxos é a ordem das colunas.
            "fluxos": [{"key": key, "label": label} for key, label in spec.fluxos.items()],
            "cards": len(spec.cards),
            "variants": len(expand_spec(spec)),
            "sections": sections,
        }

    # --------------------------------------------------------------- auditoria

    def read_log(self, raw_path: object) -> tuple[list[dict[str, Any]], Path]:
        path = validate_input_file(raw_path, label="log", max_bytes=MAX_LOG_BYTES, suffixes=LOG_SUFFIXES)
        content = path.read_text(encoding="utf-8", errors="replace")
        return items_from_text(content), path

    def audit(
        self,
        spec_path: object,
        items: list[dict[str, Any]],
        *,
        source: str,
        log_path: Path | None = None,
        platform: str | None = None,
        progress: Progress = _no_progress,
    ) -> dict[str, Any]:
        """Cruza a spec com os eventos e guarda o relatório para `export`."""
        progress("Lendo a spec", None)
        spec, path = self.load_spec(spec_path)
        chosen = (platform or spec.plataforma).lower()
        if chosen not in PLATFORMS:
            raise InvalidInputError(f"Plataforma inválida: {chosen!r}. Use android ou ios.")
        progress("Normalizando os eventos", 30)
        events, stats = events_from_items(items, chosen)
        progress("Validando as variações", 60)
        report = run_audit(spec, events, chosen, stats)
        with self._lock:
            self._last = (report, path)
        progress("Auditoria concluída", 100)
        logger.info(
            "Auditoria de %s (%s): %d validações, %d OK", spec.projeto, chosen, report.total, report.total_ok,
        )
        return self.report_payload(report, path, source=source, log_path=log_path)

    def report_payload(
        self, report: AuditReport, spec_path: Path, *, source: str, log_path: Path | None = None,
    ) -> dict[str, Any]:
        stats = report.log_stats
        return {
            "spec": self.spec_summary(report.spec, spec_path),
            "platform": report.platform,
            "source": source,
            "log_path": str(log_path) if log_path else None,
            "log_stats": {key: int(stats.get(key, 0)) for key in ("total_lidos", "da_plataforma", "duplicados", "uteis")},
            "summary": {
                "total": report.total,
                "ok": report.total_ok,
                "divergent": report.total_divergent,
                "missing": report.total_missing,
                "compliance_rate": report.compliance_rate,
                "extras": len(report.extras),
                "alerts": len(report.alerts),
            },
            "results": [self._result_payload(report, i, r) for i, r in enumerate(report.results)],
            "extras": [e.to_dict() for e in report.extras],
            "alerts": [a.to_dict() for a in report.alerts],
            "observations": "\n".join(observation_lines(report)),
            "markdown": generate_markdown(report),
            "tsv": generate_tsv(report),
        }

    @staticmethod
    def _result_payload(report: AuditReport, index: int, result: VariantResult) -> dict[str, Any]:
        spec = report.spec
        card = spec.cards[result.variant.card_index]
        flow = result.variant.flow
        prints_dir = Path(spec.prints_dir) if spec.prints_dir else None
        print_path = prints_dir / card.print_name if prints_dir and card.print_name else None
        return {
            "id": index,
            "card_index": result.variant.card_index,
            "section": card.secao,
            "card_title": card.titulo or card.evento,
            "print_path": str(print_path) if print_path and print_path.is_file() else None,
            "flow": flow,
            "flow_label": spec.fluxos.get(flow, flow) if flow else None,
            "event": result.variant.event,
            "variation": variation_text(result),
            "status": result.status.value,
            "checks": [
                {"field": c.field, "expected": c.expected, "obtained": _display(c.obtained), "ok": c.ok}
                for c in result.checks
            ],
            # O que a variação espera, já com o fluxo aplicado e na ordem do
            # card. Na não disparada é a única fonte dos valores (não há checks).
            "expected": [
                {"key": key, "value": _display(value)} for key, value in result.variant.expected.items()
            ],
            "matched": _matched_payload(result.matched),
            "occurrences": result.occurrences,
            "older_divergent": result.older_divergent,
            "older_divergences": list(result.older_divergences),
            "ga_screen": result.ga_screen,
            "note": result.variant.note,
            "divergences": divergences_text(result),
            "block": variant_block_text(result, flow_short_label(report, flow)),
        }

    # --------------------------------------------------------- edição do card

    def card(self, raw_path: object, raw_index: object) -> dict[str, Any]:
        """O card como está no JSON, para o formulário de edição."""
        data, _path, index = self._card_source(raw_path, raw_index)
        return card_payload(data, index)

    def update_card(self, raw_path: object, raw_index: object, raw_card: object) -> dict[str, Any]:
        """Grava os textos editados de um card e devolve a spec relida.

        Só os campos do formulário mudam (seção, título, evento, parâmetros,
        variações e a observação em texto); o print, `por_fluxo`,
        `params_por_fluxo`, uma `obs` por fluxo e chaves desconhecidas ficam
        como estavam. A spec inteira é validada antes de gravar, e a gravação
        troca o arquivo de uma vez: um erro nunca deixa o JSON pela metade.
        """
        data, path, index = self._card_source(raw_path, raw_index)
        data["cards"][index] = edited_card(raw_card, data["cards"][index], index + 1)
        SpecTemplate.from_dict(data)
        temporary = path.with_name(f".{path.name}.mobaile-tmp")
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, path)
        logger.info("Card %d da spec %s editado", index + 1, path.name)
        spec, path = self.load_spec(str(path))
        return {"spec": self.spec_summary(spec, path), "card": card_payload(data, index)}

    def _card_source(self, raw_path: object, raw_index: object) -> tuple[dict[str, Any], Path, int]:
        data, path = self._read_spec_json(raw_path)
        cards = data.get("cards") if isinstance(data, dict) else None
        if not isinstance(cards, list) or not cards:
            raise InvalidInputError(f"A spec {path.name} não tem cards.")
        if isinstance(raw_index, bool) or not isinstance(raw_index, int):
            raise InvalidInputError("card_index precisa ser um número inteiro.")
        if not 0 <= raw_index < len(cards):
            raise InvalidInputError(f"O card {raw_index + 1} não existe: a spec tem {len(cards)}.")
        if not isinstance(cards[raw_index], dict):
            raise InvalidInputError(f"card {raw_index + 1}: cada card precisa ser um objeto JSON.")
        return data, path, raw_index

    # -------------------------------------------------------------- exportação

    def default_export_dir(self, report: AuditReport) -> Path:
        stamp = self._now().strftime("%Y%m%d-%H%M%S")
        name = f"{safe_file_stem(report.spec.projeto)}-{report.platform}-{stamp}"
        return self._documents / "Relatórios" / name

    def export(
        self,
        directory: object = None,
        *,
        progress: Progress = _no_progress,
        check_cancelled: CheckCancelled = _no_check,
    ) -> dict[str, Any]:
        """Grava os quatro artefatos do último relatório."""
        with self._lock:
            last = self._last
        if last is None:
            raise InvalidInputError("Nenhuma auditoria para exportar. Rode a auditoria primeiro.")
        report, _ = last
        target = prepare_output_dir(directory if directory else self.default_export_dir(report))
        artefatos: list[tuple[str, str, Callable[[], str]]] = [
            ("board", BOARD_FILE, lambda: json.dumps(build_board(report), ensure_ascii=False)),
            ("html", HTML_FILE, lambda: generate_html(report)),
            ("markdown", MARKDOWN_FILE, lambda: generate_markdown(report)),
            ("tsv", TSV_FILE, lambda: generate_tsv(report)),
        ]
        files = []
        for step, (kind, name, render) in enumerate(artefatos):
            check_cancelled()
            progress(f"Gerando {name}", round(step / len(artefatos) * 100))
            path = target / name
            path.write_text(render(), encoding="utf-8")
            files.append({"kind": kind, "name": name, "path": str(path), "bytes": path.stat().st_size})
        progress("Relatório exportado", 100)
        logger.info("Relatório exportado em %s", target)
        return {"directory": str(target), "files": files}

    # -------------------------------------------------------------- importação

    def import_prints(
        self,
        prints_dir: object,
        *,
        projeto: str | None = None,
        platform: str = "android",
        spec_path: object = None,
        progress: Progress = _no_progress,
        check_cancelled: CheckCancelled = _no_check,
    ) -> dict[str, Any]:
        """OCR dos prints, rascunho da spec e lista do que conferir."""
        if self._ocr is None:
            raise InvalidInputError("O OCR de prints não está disponível neste motor.")
        folder = validate_input_dir(prints_dir, label="prints")
        chosen = (platform or "android").lower()
        if chosen not in PLATFORMS:
            raise InvalidInputError(f"Plataforma inválida: {chosen!r}. Use android ou ios.")
        images = sorted(
            p for p in folder.iterdir()
            if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES and not p.name.startswith(".")
        )
        if not images:
            raise InvalidInputError(f"Nenhuma imagem em {folder}. Use os prints dos cards em PNG ou JPG.")
        if len(images) > MAX_PRINTS:
            raise InvalidInputError(f"{len(images)} imagens em {folder}; o limite é {MAX_PRINTS} prints por spec.")

        progress(f"Lendo {len(images)} print(s) com o OCR do macOS", None)
        lines = self._ocr.read(images)
        check_cancelled()
        progress("Interpretando os cards", 80)
        cards = [read_card(lines.get(str(p), []), str(p)) for p in images]
        nome = (projeto or "").strip() or folder.name
        spec, review = build_spec(cards, nome, chosen, str(folder))

        if spec_path:
            destination = validate_spec_destination(spec_path)
        else:
            destination = unique_path(self._documents / "Specs" / f"{safe_file_stem(nome, 'spec')}.json")
        prepare_output_dir(destination.parent, label="specs")
        destination.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        review_path = destination.with_suffix(".revisao.md")
        review_path.write_text(review_markdown(spec, review), encoding="utf-8")

        summary: dict[str, Any] | None
        try:
            summary = self.spec_summary(self.load_spec(str(destination))[0], destination)
            spec_error = None
        except InvalidInputError as exc:
            # Rascunho com card sem evento lido, por exemplo: vai assim mesmo para
            # revisão, e a interface diz o que falta antes de auditar.
            summary, spec_error = None, exc.message
        progress("Rascunho da spec gravado", 100)
        return {
            "spec_path": str(destination),
            "review_path": str(review_path),
            "spec": summary,
            "spec_error": spec_error,
            "review": [{"print": r["print"], "event": r["evento"], "doubts": list(r["duvidas"])} for r in review],
            "doubts_total": sum(len(r["duvidas"]) for r in review),
        }


def _pairs(values: Any) -> list[dict[str, Any]]:
    """Objeto do JSON como lista de pares: a ordem dos parâmetros é a do card."""
    if not isinstance(values, dict):
        return []
    return [{"key": key, "value": value} for key, value in values.items()]


def card_payload(data: dict[str, Any], index: int) -> dict[str, Any]:
    card = data["cards"][index]
    obs = card.get("obs")
    variacoes = card.get("variacoes")
    return {
        "card_index": index,
        "cards": len(data["cards"]),
        "secao": card.get("secao") if isinstance(card.get("secao"), str) else None,
        "titulo": card.get("titulo") if isinstance(card.get("titulo"), str) else None,
        "evento": card.get("evento") if isinstance(card.get("evento"), str) else None,
        "print": card.get("print") if isinstance(card.get("print"), str) else None,
        "params": _pairs(card.get("params")),
        "variacoes": [_pairs(v) for v in variacoes] if isinstance(variacoes, list) else [],
        # Observação por fluxo não cabe num campo de texto: fica só no JSON.
        "obs": obs if isinstance(obs, str) else None,
        "obs_por_fluxo": isinstance(obs, dict),
        "params_por_fluxo": sorted((card.get("params_por_fluxo") or {}).keys())
        if isinstance(card.get("params_por_fluxo"), dict) else [],
    }


def _object_from_pairs(raw: Any, where: str) -> dict[str, Any]:
    if not isinstance(raw, list):
        raise InvalidInputError(f"{where} precisa ser uma lista de pares chave e valor.")
    result: dict[str, Any] = {}
    for pair in raw:
        if not isinstance(pair, dict) or "key" not in pair or "value" not in pair:
            raise InvalidInputError(f"{where}: cada item precisa ter key e value.")
        key = pair["key"].strip() if isinstance(pair["key"], str) else ""
        if not key:
            raise InvalidInputError(f"{where}: há um parâmetro sem nome.")
        if key in result:
            raise InvalidInputError(f"{where}: o parâmetro {key!r} aparece duas vezes.")
        result[key] = pair["value"]
    return result


def edited_card(raw: object, original: dict[str, Any], number: int) -> dict[str, Any]:
    """Aplica o formulário sobre o card original, sem tocar no que ele não mostra."""
    where = f"card {number}"
    if not isinstance(raw, dict):
        raise InvalidInputError(f"{where}: o card editado precisa ser um objeto.")
    card = dict(original)
    for field_name in ("secao", "titulo", "evento"):
        if field_name not in raw:
            continue
        value = raw[field_name]
        if value is not None and not isinstance(value, str):
            raise InvalidInputError(f"{where}: '{field_name}' precisa ser texto.")
        text = (value or "").strip()
        if text:
            card[field_name] = text
        elif field_name == "evento":
            raise InvalidInputError(f"{where}: o evento não pode ficar vazio.")
        else:
            card.pop(field_name, None)
    if "params" in raw:
        card["params"] = _object_from_pairs(raw["params"], f"{where}.params")
    if "variacoes" in raw:
        if not isinstance(raw["variacoes"], list):
            raise InvalidInputError(f"{where}: 'variacoes' precisa ser uma lista.")
        variacoes = [
            _object_from_pairs(v, f"{where}.variacoes[{i}]") for i, v in enumerate(raw["variacoes"], 1)
        ]
        variacoes = [v for v in variacoes if v]
        if variacoes:
            card["variacoes"] = variacoes
        else:
            card.pop("variacoes", None)
    if "obs" in raw and not isinstance(original.get("obs"), dict):
        obs = raw["obs"]
        if obs is not None and not isinstance(obs, str):
            raise InvalidInputError(f"{where}: 'obs' precisa ser texto.")
        if obs and obs.strip():
            card["obs"] = obs.strip()
        else:
            card.pop("obs", None)
    return card


def validate_spec_destination(raw: object) -> Path:
    """Caminho de gravação do rascunho: `.json`, e nunca por cima de outro arquivo."""
    if not isinstance(raw, str) or not raw.strip():
        raise InvalidInputError("Informe onde gravar o rascunho da spec.")
    path = Path(raw.strip()).expanduser().resolve()
    if path.suffix.lower() != ".json":
        raise InvalidInputError(f"O rascunho da spec precisa terminar em .json: {path.name}")
    return unique_path(path)


def _matched_payload(event: TagEvent | None) -> dict[str, Any] | None:
    if event is None:
        return None
    return {
        "id": event.id if isinstance(event.id, int) and not isinstance(event.id, bool) else None,
        "time": event.time_str,
        "event_name": event.event_name,
        "params": event.params,
    }

"""Handlers do front web: o mesmo `ReportService` do app, atrás de uma allowlist.

Não passa pelo `EngineServer` (ADR 0007): ele expõe a tabela inteira de métodos
e grava recentes em `~/.mobaile`. Aqui há três métodos `report.*`, com o mesmo
envelope de `rpc/protocol.py` e os mesmos erros tipados, e uma rota de
Analytics que lê um logcat salvo com o parser do Relatório. Nada disso muda o
contrato do app nativo.

Regras da fronteira web, todas aplicadas antes do serviço:

- método fora de `ALLOWED_METHODS` recebe -32601 sem ser despachado;
- todo caminho passa por `Session.confine`;
- `directory` do export é ignorado: a pasta é sempre nova, dentro da sessão;
- `source` é sempre `file` e `platform` só `android` ou `ios`;
- a spec enviada perde `prints_dir` e `print`: uma spec de terceiros não pode
  fazer o motor ler imagens do disco e embuti-las no HTML.
"""

from __future__ import annotations

import dataclasses
import json
import logging
import threading
from collections.abc import Callable
from pathlib import Path
from typing import Any

from mobaile.domain.errors import EngineError, InvalidInputError
from mobaile.domain.report import PLATFORMS, SpecTemplate, TagEvent
from mobaile.rpc import protocol
from mobaile.services.report import ReportService
from mobaile.services.report.firebase_log import events_from_items, items_from_text
from mobaile.web.sandbox import Session, decode_text

logger = logging.getLogger(__name__)

ALLOWED_METHODS = frozenset({"report.spec", "report.audit", "report.export"})
# Mesmas colunas do "Exportar TSV" do Analytics do app (`export_as_tsv`).
TSV_HEADER = "Hora\tPlataforma\tOrigem\tNome do Evento\tParâmetros Principais\tJSON dos Parâmetros"


class WebReportService(ReportService):
    """`ReportService` que ignora os prints da spec: a web não lê imagem do disco."""

    def load_spec(self, raw_path: object) -> tuple[SpecTemplate, Path]:
        spec, path = super().load_spec(raw_path)
        spec.prints_dir = None
        for card in spec.cards:
            card.print_name = None
        return spec, path


def _cell(value: object) -> str:
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")


def analytics_tsv(events: list[TagEvent]) -> str:
    lines = [TSV_HEADER]
    for event in events:
        main = ", ".join(f"{key}: {value}" for key, value in list(event.params.items())[:4])
        params = json.dumps(event.params, ensure_ascii=False, default=str)
        lines.append("\t".join(_cell(v) for v in (
            event.time_str, event.platform.upper(), event.origin, event.event_name, main, params)))
    return "\n".join(lines)


class WebHandlers:
    def __init__(self, session: Session) -> None:
        self.session = session
        self.report = WebReportService(ocr=None, documents_dir=session.root)
        # Um usuário, um relatório por vez: o export usa o último audit.
        self._lock = threading.Lock()
        self._methods: dict[str, Callable[[dict[str, Any]], dict[str, Any]]] = {
            "report.spec": self._spec, "report.audit": self._audit, "report.export": self._export,
        }

    def handle_rpc(self, body: bytes) -> dict[str, Any]:
        """Uma requisição JSON-RPC 2.0; devolve a resposta no envelope do motor."""
        try:
            message = json.loads(body)
        except (UnicodeDecodeError, json.JSONDecodeError):
            return protocol.error(None, protocol.PARSE_ERROR, "JSON invalido.")
        if not isinstance(message, dict) or message.get("jsonrpc") != protocol.JSONRPC_VERSION:
            return protocol.error(None, protocol.INVALID_REQUEST, "Envelope JSON-RPC 2.0 esperado.")
        request_id = message.get("id")
        if isinstance(request_id, bool) or not isinstance(request_id, (str, int, float, type(None))):
            return protocol.error(None, protocol.INVALID_REQUEST, "id deve ser texto, numero ou nulo.")
        method, params = message.get("method"), message.get("params", {})
        if not isinstance(method, str) or method not in ALLOWED_METHODS:
            shown = method if isinstance(method, str) else type(method).__name__
            return protocol.error(request_id, protocol.METHOD_NOT_FOUND, f"Metodo indisponivel na versao web: {shown}")
        if not isinstance(params, dict):
            return protocol.error(request_id, protocol.INVALID_PARAMS, "params deve ser objeto.")
        try:
            with self._lock:
                payload = self._methods[method](params)
        except EngineError as exc:
            return protocol.error(request_id, protocol.ENGINE_ERROR, exc.message, exc.to_dict())
        except Exception:
            # Sem trace na resposta: a página não precisa dele, e ele leva caminho do disco.
            logger.exception("Erro interno em %s", method)
            return protocol.error(request_id, protocol.INTERNAL_ERROR, "Erro interno no motor.")
        return protocol.result(request_id, payload)

    def _spec(self, params: dict[str, Any]) -> dict[str, Any]:
        result = self.report.spec(self.session.confine(params.get("path"), "spec"))
        result["path"] = Path(result["path"]).name
        return result

    def _audit(self, params: dict[str, Any]) -> dict[str, Any]:
        if (params.get("source") or "file") != "file":
            raise InvalidInputError("Na versão web, a auditoria lê só o log enviado por esta página (source: file).")
        platform = params.get("platform") or None
        if platform is not None and platform not in PLATFORMS:
            raise InvalidInputError("platform precisa ser android ou ios.")
        spec_path = self.session.confine(params.get("spec_path"), "spec")
        items, log_path = self.report.read_log(self.session.confine(params.get("log_path"), "log"))
        if not items:
            raise InvalidInputError(f"O log {log_path.name} não tem eventos do Firebase Analytics.")
        result = self.report.audit(spec_path, items, source="file", log_path=log_path, platform=platform)
        result["spec"]["path"] = Path(result["spec"]["path"]).name
        result["log_path"] = log_path.name
        return result

    def _export(self, params: dict[str, Any]) -> dict[str, Any]:
        result = self.report.export(self.session.new_export_dir(), info=params.get("info"))
        return {"files": [
            {"kind": f["kind"], "name": f["name"], "bytes": f["bytes"], "id": self.session.register(Path(f["path"]))}
            for f in result["files"]
        ]}

    def analytics(self, data: bytes) -> dict[str, Any]:
        """Eventos de um logcat salvo (só Android no MVP), com o parser do Relatório."""
        items = items_from_text(decode_text(data, label="log", strict=False))
        events, stats = events_from_items(items, "android")
        return {
            "platform": "android",
            "stats": stats,
            "events": [dataclasses.asdict(event) for event in events],
            "tsv": analytics_tsv(events),
        }

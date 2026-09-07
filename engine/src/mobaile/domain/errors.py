"""Hierarquia de erros do motor.

Regra de ouro: adapters levantam erros tipados; a fronteira RPC os traduz em
códigos JSON-RPC. Nenhuma camada engole exceção silenciosamente com
`except Exception: pass` — quem não sabe tratar, propaga.
"""

from __future__ import annotations


class EngineError(Exception):
    """Raiz de todos os erros previsíveis do motor."""

    code = "engine_error"

    def __init__(self, message: str, *, detail: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.detail = detail

    def to_dict(self) -> dict:
        payload = {"code": self.code, "message": self.message}
        if self.detail:
            payload["detail"] = self.detail
        return payload


class InvalidInputError(EngineError):
    """Entrada rejeitada pela validação antes de tocar em qualquer processo."""

    code = "invalid_input"


class ToolNotFoundError(EngineError):
    """Binário externo obrigatório ausente (adb, scrcpy, xcrun)."""

    code = "tool_not_found"


class DeviceNotFoundError(EngineError):
    """Dispositivo/simulador solicitado não está na lista ativa."""

    code = "device_not_found"


class DeviceNotReadyError(EngineError):
    """Dispositivo existe mas não está em estado utilizável (unauthorized, offline)."""

    code = "device_not_ready"


class AdapterError(EngineError):
    """Falha ao conversar com uma ferramenta externa."""

    code = "adapter_error"

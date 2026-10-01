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


class IncompatibleProtocolError(EngineError):
    """Front e motor falam versoes diferentes do contrato JSON-RPC.

    Seguir conectando assim faria o erro aparecer longe da causa, como campo
    ausente num DTO minutos depois. Recusar no aperto de mao poe a mensagem
    certa na frente do usuario.
    """

    code = "incompatible_protocol"


class RequestCancelledError(EngineError):
    """O cliente desistiu da requisicao com `$/cancelRequest`.

    Tambem serve de sinal interno: o metodo longo que percebe o cancelamento
    entre duas etapas levanta este erro para parar cedo.
    """

    code = "request_cancelled"

    def __init__(self, message: str = "Requisicao cancelada.") -> None:
        super().__init__(message)

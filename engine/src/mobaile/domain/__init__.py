"""Modelos e erros de domínio — puros, serializáveis, sem I/O."""

from mobaile.domain.errors import (
    AdapterError,
    DeviceNotFoundError,
    DeviceNotReadyError,
    EngineError,
    IncompatibleProtocolError,
    InvalidInputError,
    RequestCancelledError,
    ToolNotFoundError,
)
from mobaile.domain.models import (
    AnalyticsEvent,
    AutomationStep,
    DaemonState,
    Device,
    LocatorStrategy,
    NetworkEvent,
    Platform,
    UIElement,
)

__all__ = [
    "AdapterError",
    "AnalyticsEvent",
    "AutomationStep",
    "DaemonState",
    "Device",
    "DeviceNotFoundError",
    "DeviceNotReadyError",
    "EngineError",
    "IncompatibleProtocolError",
    "InvalidInputError",
    "LocatorStrategy",
    "NetworkEvent",
    "Platform",
    "RequestCancelledError",
    "ToolNotFoundError",
    "UIElement",
]

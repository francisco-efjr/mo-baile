"""Protocolos estruturais das bordas do motor.

Por que existir: hoje `DeviceWatcher` recebe `ADBBridge` e `IOSBridge`
concretos e decide o que chamar com `if platform == ...`. Com protocolo, o
serviço passa a depender da capacidade e não da classe, o que permite testar
sem dispositivo e abre espaço para um terceiro alvo (aparelho iOS físico via
`idb`, por exemplo) sem tocar no serviço.

São `Protocol` e não classes-base: os adapters já existentes satisfazem os
contratos sem herdar nada, então a adoção é incremental.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from PIL import Image

from mobaile.domain.models import AnalyticsEvent, Device, NetworkEvent


@runtime_checkable
class DeviceBridge(Protocol):
    """Descoberta e identificação de alvos conectados."""

    def list_devices_typed(self) -> list[Device]: ...

    def get_device_model(self, device_id: str) -> str: ...


@runtime_checkable
class FrameSource(Protocol):
    """Captura de um quadro da tela do alvo."""

    def take_screenshot(self, device_id: str) -> Image.Image | None: ...

    def get_screen_size(self, device_id: str) -> tuple[int, int]: ...


@runtime_checkable
class HierarchySource(Protocol):
    """Árvore de acessibilidade em XML bruto."""

    def get_ui_hierarchy(self, device_id: str) -> str | None: ...


@runtime_checkable
class InputSink(Protocol):
    """Envio de interações para o alvo."""

    def tap(self, device_id: str, x: int, y: int) -> bool: ...

    def type_text(self, device_id: str, text: str) -> bool: ...


@runtime_checkable
class TrafficSource(Protocol):
    """Fonte de eventos HTTP observados."""

    def is_running(self) -> bool: ...

    def start(self) -> bool: ...

    def stop(self) -> None: ...

    @property
    def events_history(self) -> list[NetworkEvent]: ...


@runtime_checkable
class AnalyticsSource(Protocol):
    """Fonte de eventos de tagueamento."""

    def is_running(self) -> bool: ...

    def start(self, platform: str = "android", device_id: str | None = None) -> bool: ...

    def stop(self) -> None: ...

    @property
    def events_history(self) -> list[AnalyticsEvent]: ...

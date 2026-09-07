"""Modelos de domínio.

Estes tipos são o vocabulário compartilhado entre o motor Python e o front
SwiftUI: cada um sabe se serializar em JSON e nada mais. Sem PIL, sem sockets,
sem subprocess — o que permite testá-los sem dispositivo e sem GUI.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class Platform(str, Enum):
    IOS = "ios"
    ANDROID = "android"

    @property
    def display_name(self) -> str:
        return "iOS" if self is Platform.IOS else "Android"


class LocatorStrategy(str, Enum):
    ID = "id"
    XPATH = "xpath"
    POSITION = "position"


class DaemonState(str, Enum):
    OK = "ok"
    BUSY = "busy"
    WARN = "warn"
    ERROR = "error"
    OFF = "off"


@dataclass(frozen=True)
class Device:
    """Um alvo conectado: emulador, aparelho físico ou simulador iOS."""

    id: str
    name: str
    platform: Platform
    state: str = "device"

    @property
    def is_ready(self) -> bool:
        return self.state == "device"

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "platform": self.platform.value,
            "state": self.state,
            "ready": self.is_ready,
        }


@dataclass
class UIElement:
    """Nó da árvore de acessibilidade, normalizado entre Android e iOS."""

    tag: str
    class_name: str
    resource_id: str
    text: str
    content_desc: str
    clickable: bool
    bounds: tuple[int, int, int, int]
    area: int
    package: str
    platform: str = "android"
    depth: int = 0
    parent_idx: int | None = None

    @property
    def chip_type(self) -> str:
        name = (self.class_name or self.tag or "").lower()
        if "button" in name:
            return "B"
        if any(k in name for k in ("edittext", "textfield", "searchfield", "input")):
            return "I"
        if any(k in name for k in ("textview", "statictext", "label")):
            return "T"
        if any(k in name for k in ("application", "window")):
            return "W"
        return "V"

    @property
    def center(self) -> tuple[int, int]:
        x1, y1, x2, y2 = self.bounds
        return ((x1 + x2) // 2, (y1 + y2) // 2)

    @property
    def display_name(self) -> str:
        if self.text:
            return self.text.strip()
        if self.content_desc:
            return self.content_desc.strip()
        if self.resource_id:
            return self.resource_id.split("/")[-1]
        return self.class_name.split(".")[-1]

    def to_dict(self) -> dict[str, Any]:
        return {
            "tag": self.tag,
            "class_name": self.class_name,
            "resource_id": self.resource_id,
            "text": self.text,
            "content_desc": self.content_desc,
            "clickable": self.clickable,
            "bounds": list(self.bounds),
            "area": self.area,
            "package": self.package,
            "platform": self.platform,
            "depth": self.depth,
            "parent_idx": self.parent_idx,
            "chip_type": self.chip_type,
            "display_name": self.display_name,
        }


@dataclass
class AutomationStep:
    """Um passo gravado, pronto para virar código ou execução."""

    step_num: int
    action_type: str  # "click" | "input"
    var_name: str
    element_name: str
    class_name: str
    strategy: LocatorStrategy
    locator_value: str
    coords: tuple[int, int]
    input_text: str | None = None
    package: str = ""
    platform: str = "android"

    def to_dict(self) -> dict[str, Any]:
        strategy = self.strategy.value if isinstance(self.strategy, LocatorStrategy) else str(self.strategy)
        return {
            "step_num": self.step_num,
            "action_type": self.action_type,
            "var_name": self.var_name,
            "element_name": self.element_name,
            "class_name": self.class_name,
            "strategy": strategy,
            "locator_value": self.locator_value,
            "coords": list(self.coords) if self.coords else [0, 0],
            "input_text": self.input_text,
            "package": self.package,
            "platform": self.platform,
        }


@dataclass
class NetworkEvent:
    """Uma requisição/resposta observada pelo proxy.

    `request_body` e `response_body` já chegam aqui truncados e redigidos pelo
    adapter — o domínio nunca guarda payload bruto ilimitado.
    """

    id: int
    timestamp: float
    time_str: str
    method: str
    url: str
    host: str
    path: str
    status_code: int
    status_text: str
    request_headers: dict[str, str] = field(default_factory=dict)
    request_body: str = ""
    response_headers: dict[str, str] = field(default_factory=dict)
    response_body: str = ""
    duration_ms: float = 0.0
    protocol: str = "HTTP/1.1"
    is_tunnel: bool = False
    error: str | None = None
    request_bytes: int = 0
    response_bytes: int = 0
    body_truncated: bool = False

    def summary(self) -> str:
        return f"[{self.method}] {self.status_code} {self.url} ({self.duration_ms:.1f}ms)"

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "timestamp": self.timestamp,
            "time": self.time_str,
            "method": self.method,
            "url": self.url,
            "host": self.host,
            "path": self.path,
            "status_code": self.status_code,
            "status_text": self.status_text,
            "request_headers": self.request_headers,
            "request_body": self.request_body,
            "response_headers": self.response_headers,
            "response_body": self.response_body,
            "duration_ms": self.duration_ms,
            "protocol": self.protocol,
            "is_tunnel": self.is_tunnel,
            "error": self.error,
            "request_bytes": self.request_bytes,
            "response_bytes": self.response_bytes,
            "body_truncated": self.body_truncated,
        }


@dataclass
class AnalyticsEvent:
    """Evento de tagueamento capturado no logcat (Android) ou os_log (iOS)."""

    id: int
    timestamp: float
    time_str: str
    tag: str  # "FA", "FA-SVC" ou "iOS (Firebase)"
    event_name: str
    params: dict[str, Any] = field(default_factory=dict)
    raw_log: str = ""
    platform: str = "android"

    @property
    def param_count(self) -> int:
        return len(self.params)

    def summary(self) -> str:
        param_items = [f"{k}={v}" for k, v in list(self.params.items())[:3]]
        return f"[{self.time_str}] ({self.tag}) {self.event_name} -> {{{', '.join(param_items)}}}"

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "time": self.time_str,
            "timestamp": self.timestamp,
            "platform": self.platform,
            "tag": self.tag,
            "event_name": self.event_name,
            "params": self.params,
            "raw_log": self.raw_log,
        }

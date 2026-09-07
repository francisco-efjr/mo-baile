"""Configuração do motor.

Antes, cada valor era lido com `float(os.getenv(...))` direto no corpo da
dataclass: um `STREAM_FPS=abc` no `.env` derrubava a aplicação no import, sem
mensagem útil, e um `STREAM_FPS=0` causava divisão por zero lá adiante. Aqui
cada campo tem faixa válida, valor fora da faixa vira aviso e cai no padrão, e
a configuração pode ser recarregada em teste sem mexer no processo.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass

logger = logging.getLogger(__name__)


def _env_float(name: str, default: float, *, minimum: float, maximum: float) -> float:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        value = float(raw)
    except ValueError:
        logger.warning("%s=%r não é numérico; usando %s.", name, raw, default)
        return default
    if not (minimum <= value <= maximum):
        logger.warning("%s=%s fora da faixa [%s, %s]; usando %s.", name, value, minimum, maximum, default)
        return default
    return value


def _env_choice(name: str, default: str, allowed: tuple[str, ...]) -> str:
    raw = (os.getenv(name) or "").strip().lower()
    if not raw:
        return default
    if raw not in allowed:
        logger.warning("%s=%r inválido; esperado um de %s. Usando %s.", name, raw, allowed, default)
        return default
    return raw


@dataclass(frozen=True)
class Settings:
    wda_url: str
    adb_path: str | None
    page_objects_key: str
    default_strategy: str
    stream_fps: float
    poll_interval: float
    diff_threshold: float
    settle_delay: float
    proxy_port: int
    proxy_host: str
    appium_url: str

    @classmethod
    def from_env(cls) -> Settings:
        return cls(
            wda_url=(os.getenv("WDA_URL") or "http://localhost:8100").rstrip("/"),
            adb_path=os.getenv("ADB_PATH") or None,
            page_objects_key=os.getenv("PAGE_OBJECTS_KEY") or "onboarding_credito_objs",
            default_strategy=_env_choice("DEFAULT_STRATEGY", "position", ("position", "xpath", "id")),
            # Acima de 60 fps não há ganho: a captura via adb não acompanha.
            stream_fps=_env_float("STREAM_FPS", 3.5, minimum=0.2, maximum=60.0),
            poll_interval=_env_float("POLL_INTERVAL", 1.5, minimum=0.2, maximum=60.0),
            # Média de diferença por pixel (0-255) entre miniaturas 32x32.
            diff_threshold=_env_float("DIFF_THRESHOLD", 3.5, minimum=0.0, maximum=255.0),
            settle_delay=_env_float("SETTLE_DELAY", 0.4, minimum=0.0, maximum=10.0),
            proxy_port=int(_env_float("PROXY_PORT", 8082, minimum=1, maximum=65535)),
            # Escuta só no loopback: o alcance ao aparelho vem do `adb reverse`,
            # não de expor a porta na rede.
            proxy_host=os.getenv("PROXY_HOST") or "127.0.0.1",
            # O Appium gerencia o ciclo de vida do WebDriverAgent no iOS.
            appium_url=(os.getenv("APPIUM_URL") or "http://127.0.0.1:4723").rstrip("/"),
        )


settings = Settings.from_env()


def reload_settings() -> Settings:
    """Relê o ambiente. Usado em teste e quando o front altera preferências."""
    global settings
    settings = Settings.from_env()
    return settings

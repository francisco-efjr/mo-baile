"""Descoberta automatica de alvos conectados.

O aparelho ou simulador aparece sozinho na interface, sem clique em "atualizar".
E a diferenca entre a ferramenta acompanhar o trabalho e o usuario ter que
avisar a ferramenta que plugou o cabo.

Duas correcoes em relacao a versao anterior:

- **Espera interrompivel.** O laco usava `time.sleep(poll_interval)`. Com o
  intervalo padrao, `stop()` demorava ate um segundo e meio para ser notado, e
  com intervalo maior a aplicacao parecia travar ao fechar. Agora a espera e
  feita no proprio `Event`, entao o encerramento e imediato.
- **Falha visivel.** O `except Exception: pass` escondia adb ausente e
  simulador fora do ar. Agora a falha vira log e um aviso de que o alvo sumiu,
  em vez de silencio.
"""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable

from mobaile.config import settings
from mobaile.domain.errors import EngineError
from mobaile.domain.models import Platform

logger = logging.getLogger(__name__)

# `(plataforma, device_id)`. Plataforma "none" e id vazio significam "nada conectado".
DeviceChangedHandler = Callable[[str, str], None]


class DeviceWatcher:
    """Vigia a plataforma ativa e avisa quando o alvo muda."""

    def __init__(
        self,
        adb_bridge,
        ios_bridge,
        on_device_changed: DeviceChangedHandler,
        target_platform: str = "ios",
        poll_interval: float | None = None,
    ):
        self.adb = adb_bridge
        self.ios = ios_bridge
        self.on_device_changed = on_device_changed
        self.target_platform = target_platform
        self.poll_interval = poll_interval or settings.poll_interval

        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

        self.current_platform: str | None = None
        self.current_device_id: str | None = None
        # Sobe a cada `set_platform`. Uma listagem leva ate segundos (`adb
        # devices` com aparelho travado), e se a plataforma mudou no meio dela o
        # resultado descreve a plataforma anterior: aplica-lo punha um serial
        # Android numa sessao iOS.
        self._generation = 0
        # Ordem de locks: este e tomado antes do lock de estado do servidor (o
        # aviso roda com ele), e o servidor nunca chama `set_platform` segurando
        # o dele. Assim nao ha inversao.
        self._lock = threading.Lock()

    # ------------------------------------------------------------ ciclo de vida

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._watch_loop, daemon=True, name="mobaile-devices")
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread and self._thread is not threading.current_thread():
            self._thread.join(timeout=2.0)
            if self._thread.is_alive():
                logger.warning("Vigia de dispositivos nao encerrou no tempo esperado.")
        # Mantém a referência enquanto uma listagem ainda está em voo. Senão
        # start() limparia o Event e reativaria a thread antiga junto da nova.
        if self._thread and not self._thread.is_alive():
            self._thread = None

    def is_running(self) -> bool:
        return bool(self._thread and self._thread.is_alive())

    def set_platform(self, platform: str) -> None:
        """Troca a plataforma vigiada e forca uma nova deteccao."""
        with self._lock:
            self._generation += 1
            self.target_platform = platform
            self.reset_current()

    def reset_current(self) -> None:
        self.current_device_id = None
        self.current_platform = None

    # ------------------------------------------------------------------ deteccao

    def _list_targets(self, platform: str) -> list[tuple[str, str]]:
        """`(id, rotulo)` dos alvos prontos de `platform`."""
        if platform == Platform.IOS.value:
            return list(self.ios.list_booted_simulators())
        if platform == Platform.ANDROID.value:
            # Alvo em `unauthorized` ou `offline` nao serve: selecionar um
            # desses faria toda operacao seguinte falhar sem explicacao.
            return [(dev_id, state) for dev_id, state in self.adb.list_devices() if state == "device"]
        return []

    def poll_once(self) -> str | None:
        """Uma rodada de deteccao. Devolve o alvo atual, ou `None`.

        Separado do laco de proposito: assim da para testar a maquina de estados
        sem thread e sem espera.

        A plataforma e lida antes de listar, e a listagem roda fora do lock. O
        resultado so vale se ninguem trocou a plataforma enquanto ela rodava.
        """
        with self._lock:
            platform, generation = self.target_platform, self._generation
        try:
            targets = self._list_targets(platform)
        except (EngineError, OSError) as exc:
            logger.warning("Falha ao consultar dispositivos: %s", exc)
            targets = []

        with self._lock:
            if self._stop_event.is_set():
                return None
            if generation != self._generation:
                logger.debug("Listagem de %s descartada: a plataforma mudou durante ela.", platform)
                return None

            if targets:
                device_id = targets[0][0]
                if self.current_platform != platform or self.current_device_id != device_id:
                    self.current_platform = platform
                    self.current_device_id = device_id
                    self.on_device_changed(platform, device_id)
                return device_id

            if self.current_device_id is not None:
                self.current_platform = None
                self.current_device_id = None
                self.on_device_changed("none", "")
            return None

    def _watch_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                self.poll_once()
            except Exception:
                logger.exception("Erro inesperado na varredura de dispositivos.")
            # Espera no Event, e nao em sleep: stop() e notado na hora.
            self._stop_event.wait(self.poll_interval)

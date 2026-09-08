"""
Módulo de Coleta de Tagueamento / Analytics em Tempo Real (Android & iOS)
------------------------------------------------------------------------
Executa a escuta contínua de eventos de Firebase Analytics:
- No Android: via ADB logcat (FA e FA-SVC).
- No iOS: via Apple Unified Logging (xcrun simctl spawn booted log stream).

Parseia eventos como 'screen_view', 'interaction', 'Consent_Device' e parâmetros
contidos em Bundles (Android) ou dictionaries (iOS) para alimentar a interface do
usuário e possibilitar auditoria no padrão da skill /tagueamento.

NOTA PARA FUTUROS AGENTES / DESENVOLVEDORES:
Este módulo é complementar e funciona de forma 100% isolada, respeitando
a plataforma ativa selecionada no sistema (Android ou iOS).
"""

from __future__ import annotations

import datetime
import json
import logging
import queue
import re
import subprocess
import threading
import time
from collections import deque
from typing import Any

from mobaile.adapters.adb import ADBBridge
from mobaile.domain.errors import InvalidInputError
from mobaile.domain.models import AnalyticsEvent
from mobaile.security import validate_device_id

logger = logging.getLogger(__name__)

__all__ = ["AnalyticsEvent", "FirebaseAnalyticsListener", "analytics_listener"]

# Teto de eventos em memoria: uma sessao longa de logcat gera milhares deles.
MAX_HISTORY = 5000


class FirebaseAnalyticsListener:
    """Gerencia a captura contínua e o parsing de eventos de Analytics via ADB (Android) ou simctl (iOS)."""

    def __init__(self, adb_bridge: ADBBridge | None = None):
        self.adb = adb_bridge or ADBBridge()
        self.event_queue: queue.Queue = queue.Queue()
        self.events_history: deque[AnalyticsEvent] = deque(maxlen=MAX_HISTORY)
        self._proc: subprocess.Popen | None = None
        self._thread: threading.Thread | None = None
        self._is_running = False
        self._event_counter = 0
        self._lock = threading.Lock()
        self.active_platform: str = "android"
        self.active_device: str | None = None

    def get_next_id(self) -> int:
        with self._lock:
            self._event_counter += 1
            return self._event_counter

    def setup_props(self, device_id: str | None = None) -> bool:
        """Habilita modo VERBOSE para FA e FA-SVC no Android."""
        try:
            cmd_base = [self.adb.adb_path]
            if device_id:
                cmd_base += ["-s", validate_device_id(device_id)]
            subprocess.run([*cmd_base, "shell", "setprop", "log.tag.FA", "VERBOSE"], timeout=5, check=False)
            subprocess.run([*cmd_base, "shell", "setprop", "log.tag.FA-SVC", "VERBOSE"], timeout=5, check=False)
            return True
        except (InvalidInputError, OSError, subprocess.TimeoutExpired) as exc:
            logger.warning("Nao foi possivel habilitar o modo VERBOSE do FA: %s", exc)
            return False

    def clear_device_logcat(self, device_id: str | None = None) -> bool:
        """Limpa o buffer do logcat no dispositivo Android."""
        try:
            cmd_base = [self.adb.adb_path]
            if device_id:
                cmd_base += ["-s", validate_device_id(device_id)]
            subprocess.run([*cmd_base, "logcat", "-c"], timeout=5, check=False)
            return True
        except (InvalidInputError, OSError, subprocess.TimeoutExpired) as exc:
            logger.warning("Nao foi possivel limpar o buffer do logcat: %s", exc)
            return False

    def start(self, platform: str = "android", device_id: str | None = None) -> bool:
        """
        Inicia a coleta em tempo real via thread de streaming.
        - Android: adb logcat -v time -s FA FA-SVC
        - iOS: xcrun simctl spawn <device_id|booted> log stream --predicate '...'
        """
        if self._is_running:
            return True

        self.active_platform = platform.lower()
        self.active_device = device_id

        if self.active_platform == "ios":
            target_sim = validate_device_id(device_id) if device_id else "booted"
            cmd = [
                "xcrun", "simctl", "spawn", target_sim,
                "log", "stream", "--style", "compact",
                "--predicate", 'eventMessage CONTAINS "Logging event" OR eventMessage CONTAINS "FirebaseAnalytics"',
            ]
        else:
            # Android
            self.setup_props(device_id)
            cmd = [self.adb.adb_path]
            if device_id:
                cmd += ["-s", validate_device_id(device_id)]
            cmd += ["logcat", "-v", "time", "-s", "FA", "FA-SVC"]

        try:
            self._proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                # DEVNULL de proposito: sem isto o filho herda o stdin do
                # motor, que e o canal JSON-RPC, e passa a consumir as
                # linhas do protocolo. O sintoma e a chamada seguinte nunca
                # responder — no app, janela travada sem erro.
                stdin=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
            self._is_running = True
            self._thread = threading.Thread(target=self._stream_reader, daemon=True, name="mobaile-analytics")
            self._thread.start()
            return True
        except (InvalidInputError, OSError) as exc:
            logger.error("Nao foi possivel iniciar a captura de analytics: %s", exc)
            self._is_running = False
            return False

    def stop(self):
        """Para a coleta e encerra o processo de streaming."""
        self._is_running = False
        if self._proc:
            try:
                self._proc.terminate()
                self._proc.wait(timeout=1.0)
            except (OSError, subprocess.TimeoutExpired):
                try:
                    self._proc.kill()
                    self._proc.wait(timeout=1.0)
                except (OSError, subprocess.TimeoutExpired) as exc:
                    logger.warning("Processo de logcat nao encerrou: %s", exc)
            finally:
                # stdout precisa ser fechado ou o descritor vaza a cada ciclo.
                if self._proc.stdout:
                    try:
                        self._proc.stdout.close()
                    except OSError:
                        pass
            self._proc = None

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)
            self._thread = None

    def is_running(self) -> bool:
        return self._is_running

    def clear_history(self):
        with self._lock:
            self.events_history.clear()
            while not self.event_queue.empty():
                try:
                    self.event_queue.get_nowait()
                except queue.Empty:
                    break

    def _stream_reader(self):
        """Lê continuamente as linhas do logcat (Android) ou os_log (iOS)."""
        if not self._proc or not self._proc.stdout:
            return

        for line in iter(self._proc.stdout.readline, ""):
            if not self._is_running:
                break
            if not line:
                continue

            # Filtra linhas com 'Logging event'
            if "Logging event" in line:
                event = self._parse_line(line.strip(), platform=self.active_platform)
                if event:
                    with self._lock:
                        self.events_history.append(event)
                    self.event_queue.put(event)

    def _parse_line(self, line: str, platform: str = "android") -> AnalyticsEvent | None:
        """Extrai data, tag, nome do evento e parâmetros tanto para Android quanto iOS."""
        # 1. Extração do timestamp
        m_time = re.search(r"(\d\d:\d\d:\d\d(?:\.\d+)?)", line)
        time_str = m_time.group(1) if m_time else datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]

        # 2. Identificação da Tag/Origem
        if "FA-SVC" in line:
            tag = "FA-SVC"
        elif "FirebaseAnalytics" in line or platform == "ios":
            tag = "iOS (Firebase)"
        else:
            tag = "FA"

        # 3. Nome do evento
        # Exemplo 1: Logging event: origin=app, name=screen_view, params={...}
        # Exemplo 2: Logging event: screen_view, Bundle[{...}]
        m_event = re.search(
            r"Logging event(?:\s*\([^\)]+\))?:\s*(?:origin=[^,\s]+,)?\s*(?:name\s*=\s*\"?([a-zA-Z0-9_\(\)]+)\"?|([a-zA-Z0-9_]+))",
            line,
        )
        event_name = m_event.group(1) or m_event.group(2) if m_event else "unknown_event"

        params: dict[str, Any] = {}

        # 4. Parâmetros Android (Bundle[{...}])
        m_bundle = re.search(r"Bundle\[\{(.*)\}\]", line)
        if m_bundle:
            bundle_content = m_bundle.group(1)
            pairs = re.split(r",\s*(?=[a-zA-Z0-9_]+(?:\([^\)]+\))?=)", bundle_content)
            for pair in pairs:
                if "=" in pair:
                    k, v = pair.split("=", 1)
                    clean_k = re.sub(r"\([^\)]+\)", "", k).strip()
                    params[clean_k] = v.strip().strip("\"'")

        # 5. Parâmetros iOS (params={ key = "val"; key2 = "val2"; })
        m_ios_params = re.search(r"params\s*=\s*\{(.*?)\}", line, re.DOTALL)
        if m_ios_params:
            ios_content = m_ios_params.group(1)
            pairs = re.findall(r"([a-zA-Z0-9_]+)\s*=\s*\"?([^\";]+)\"?\s*;", ios_content)
            for k, v in pairs:
                params[k.strip()] = v.strip()

        return AnalyticsEvent(
            id=self.get_next_id(),
            timestamp=time.time(),
            time_str=time_str,
            tag=tag,
            event_name=event_name,
            params=params,
            raw_log=line,
            platform=platform,
        )

    def export_as_tsv(self) -> str:
        """Exporta os eventos capturados em formato TSV (para colar no Google Planilhas)."""
        lines = ["Hora\tPlataforma\tOrigem\tNome do Evento\tParâmetros Principais\tJSON dos Parâmetros"]
        with self._lock:
            for ev in self.events_history:
                main_params = ", ".join([f"{k}: {v}" for k, v in list(ev.params.items())[:4]])
                json_str = json.dumps(ev.params, ensure_ascii=False)
                lines.append(f"{ev.time_str}\t{ev.platform.upper()}\t{ev.tag}\t{ev.event_name}\t{main_params}\t{json_str}")
        return "\n".join(lines)

    def export_as_json(self) -> str:
        """Exporta os eventos estruturados em formato JSON (padrão log_obtido.json da skill /tagueamento)."""
        with self._lock:
            data = [ev.to_dict() for ev in self.events_history]
        return json.dumps(data, indent=2, ensure_ascii=False)


# Instância compartilhada singleton
analytics_listener = FirebaseAnalyticsListener()

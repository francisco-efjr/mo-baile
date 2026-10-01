"""
Módulo de Coleta de Tagueamento / Analytics em Tempo Real (Android & iOS)
------------------------------------------------------------------------
Executa a escuta contínua de eventos de Firebase Analytics:
- No Android: via ADB logcat (FA e FA-SVC).
- No iOS (simulador): via Apple Unified Logging (xcrun simctl spawn booted log stream).
- No iOS (aparelho fisico por cabo): via os_trace_relay, ver `ios_device_log`.

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
from collections.abc import Callable
from typing import Any

from mobaile.adapters import ios_device_log
from mobaile.adapters.adb import ADBBridge
from mobaile.domain.errors import AdapterError, InvalidInputError
from mobaile.domain.models import AnalyticsEvent
from mobaile.security import validate_device_id

logger = logging.getLogger(__name__)

__all__ = ["AnalyticsEvent", "FirebaseAnalyticsListener", "analytics_listener"]

# Teto de eventos em memoria: uma sessao longa de logcat gera milhares deles.
MAX_HISTORY = 5000

# iOS: todo log do Firebase Analytics tem codigo "[I-ACSxxxxxx]"; filtrar por ele
# no proprio `log stream` evita trazer o resto do sistema para o motor.
IOS_LOG_PREDICATE = 'eventMessage CONTAINS "I-ACS"'

# Cabecalho de registro no `log stream --style compact`. Mensagens multilinha
# (o dicionario de parametros) seguem em linhas cruas, sem esse prefixo.
_IOS_RECORD_START = re.compile(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d")

# O SDK loga o mesmo evento em estagios. Aceitamos os que trazem o evento ja
# processado; I-ACS023051 ("Logging event: origin, name, params") e anterior a
# validacao e sai sem _dbg/_r, entao e ignorado.
_IOS_EVENT_PATTERNS = (
    # I-ACS023073 (debug mode): "... Event name, parameters: nome, {"
    re.compile(r"Event name, parameters:\s*(?P<name>[^,{]+?)\s*,\s*\{"),
    # I-ACS023072: "Event logged. Event name, event params: nome, {"
    re.compile(r"Event name, event params:\s*(?P<name>[^,{]+?)\s*,\s*\{"),
)

# Aparelho fisico: importar o pymobiledevice3 e abrir o stream leva ~1-2 s.
_IOS_DEVICE_READY_TIMEOUT_S = 15.0

# Janela em que dois estagios iguais do mesmo evento sao tratados como um so.
_IOS_STAGE_WINDOW_S = 2.0


class IOSLogRecordAssembler:
    """Remonta registros multilinha do `log stream --style compact`.

    O Firebase iOS loga os parametros como dicionario em varias linhas. O
    registro fecha quando as chaves se equilibram — sem esperar o proximo
    cabecalho, que pode demorar e seguraria o evento na tela.
    """

    def __init__(self) -> None:
        self._lines: list[str] = []
        self._depth = 0

    def feed(self, line: str) -> list[str]:
        line = line.rstrip("\n")
        done: list[str] = []
        if _IOS_RECORD_START.match(line):
            done.extend(self.flush())
            self._lines = [line]
            self._depth = 0
        elif not self._lines:
            # Cabecalhos do proprio `log stream` ("Filtering...", "Timestamp...").
            return done
        else:
            self._lines.append(line)

        self._depth += line.count("{") - line.count("}")
        if self._depth <= 0:
            done.extend(self.flush())
        return done

    def flush(self) -> list[str]:
        if not self._lines:
            return []
        record = "\n".join(self._lines)
        self._lines = []
        self._depth = 0
        return [record]


def _split_top_level(body: str, sep: str = ";") -> list[str]:
    """Divide `body` em `sep` ignorando o que esta dentro de {}, () ou aspas."""
    parts: list[str] = []
    depth = 0
    in_quotes = False
    current: list[str] = []
    prev = ""
    for ch in body:
        if ch == '"' and prev != "\\":
            in_quotes = not in_quotes
        elif not in_quotes:
            if ch in "{(":
                depth += 1
            elif ch in "})":
                depth -= 1
            elif ch == sep and depth == 0:
                parts.append("".join(current))
                current = []
                prev = ch
                continue
        current.append(ch)
        prev = ch
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


def _strip_short_name(name: str) -> str:
    """'ga_debug (_dbg)' -> 'ga_debug', igual ao que o Android faz com '(_o)'."""
    return re.sub(r"\s*\([^)]*\)", "", name).strip()


def _parse_ios_dict(body: str) -> dict[str, Any]:
    params: dict[str, Any] = {}
    for entry in _split_top_level(body):
        if "=" not in entry:
            continue
        key, value = entry.split("=", 1)
        value = " ".join(value.split())  # valores aninhados viram uma linha
        if len(value) >= 2 and value.startswith('"') and value.endswith('"'):
            value = value[1:-1].replace('\\"', '"')
        params[_strip_short_name(key)] = value
    return params


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
        # "android", "ios_simulator" ou "ios_device": de onde vem o log atual.
        self.active_source: str = "android"
        self._device_ready = threading.Event()
        self._device_error: str | None = None
        self._callbacks: list[Callable[[AnalyticsEvent], None]] = []
        # (fingerprint, estagios ja vistos, instante) dos ultimos eventos iOS.
        self._ios_recent: deque[tuple[tuple, set[str], float]] = deque(maxlen=64)

    def add_event_callback(self, cb: Callable[[AnalyticsEvent], None]) -> None:
        self._callbacks.append(cb)

    def get_next_id(self) -> int:
        with self._lock:
            self._event_counter += 1
            return self._event_counter

    def setup_props(self, device_id: str | None = None, package_name: str | None = None) -> bool:
        """Habilita modo VERBOSE para FA, FA-SVC e ativa debug mode no app Android."""
        try:
            cmd_base = [self.adb.adb_path]
            if device_id:
                cmd_base += ["-s", validate_device_id(device_id)]
            subprocess.run([*cmd_base, "shell", "setprop", "log.tag.FA", "VERBOSE"], timeout=5, check=False)
            subprocess.run([*cmd_base, "shell", "setprop", "log.tag.FA-SVC", "VERBOSE"], timeout=5, check=False)
            subprocess.run([*cmd_base, "shell", "setprop", "log.tag.FirebaseAnalytics", "VERBOSE"], timeout=5, check=False)

            # Aumenta buffer do logcat para 8MB para não truncar logs em rajadas
            subprocess.run([*cmd_base, "logcat", "-G", "8M"], timeout=5, check=False)

            # Tenta ativar o modo de debug do Firebase Analytics (DebugView) para o app em primeiro plano
            pkg = package_name
            if not pkg and device_id and hasattr(self.adb, "get_current_package"):
                pkg = self.adb.get_current_package(device_id)

            if pkg:
                subprocess.run(
                    [*cmd_base, "shell", "setprop", "debug.firebase.analytics.app", pkg],
                    timeout=5, check=False,
                )
                logger.info("Firebase Analytics debug mode habilitado para o app: %s", pkg)
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

    def start(
        self,
        platform: str = "android",
        device_id: str | None = None,
        package_name: str | None = None,
        ios_physical: bool = False,
    ) -> bool:
        """
        Inicia a coleta em tempo real via thread de streaming.
        - Android: adb logcat -v time -s FA FA-SVC FirebaseAnalytics FA-GMS
        - iOS simulador: xcrun simctl spawn <device_id|booted> log stream --predicate '...'
        - iOS fisico (`ios_physical`, `device_id` = UDID): filho de `ios_device_log`

        No aparelho fisico, falha para conectar (bloqueado, nao confiado) vira
        `AdapterError` com a mensagem para a pessoa, em vez de escuta muda.

        No iOS o app precisa estar rodando com -FIRDebugEnabled (argumento do
        scheme no Xcode); sem isso o SDK nao loga os eventos.
        """
        if self._is_running:
            return True

        self.active_platform = platform.lower()
        self.active_device = device_id
        popen_extra: dict[str, Any] = {}

        if self.active_platform == "ios" and ios_physical:
            if not device_id:
                raise InvalidInputError("UDID do iPhone nao informado.")
            if not ios_device_log.is_available():
                raise AdapterError("pymobiledevice3 nao esta instalado.", detail=ios_device_log.INSTALL_HINT)
            self.active_source = "ios_device"
            self._ios_recent.clear()
            self._device_ready.clear()
            self._device_error = None
            cmd = ios_device_log.stream_command(validate_device_id(device_id))
            popen_extra = ios_device_log.popen_kwargs()
        elif self.active_platform == "ios":
            self.active_source = "ios_simulator"
            target_sim = validate_device_id(device_id) if device_id else "booted"
            self._ios_recent.clear()
            cmd = [
                "xcrun", "simctl", "spawn", target_sim,
                # --level debug: o SDK loga os eventos em nivel debug, que o
                # `log stream` descarta por padrao.
                "log", "stream", "--style", "compact", "--level", "debug",
                "--predicate", IOS_LOG_PREDICATE,
            ]
        else:
            # Android
            self.active_source = "android"
            self.setup_props(device_id, package_name=package_name)
            cmd = [self.adb.adb_path]
            if device_id:
                cmd += ["-s", validate_device_id(device_id)]
            cmd += ["logcat", "-v", "time", "-s", "FA", "FA-SVC", "FirebaseAnalytics", "FA-GMS"]

        try:
            self._proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                # DEVNULL de proposito: sem isto o filho herda o stdin do
                # motor, que e o canal JSON-RPC, e passa a consumir as
                # linhas do protocolo. O sintoma e a chamada seguinte nunca
                # responder — no app, janela travada sem erro.
                stdin=subprocess.DEVNULL,
                text=True,
                bufsize=1,
                **popen_extra,
            )
            self._is_running = True
            self._thread = threading.Thread(target=self._stream_reader, daemon=True, name="mobaile-analytics")
            self._thread.start()
        except (InvalidInputError, OSError) as exc:
            logger.error("Nao foi possivel iniciar a captura de analytics: %s", exc)
            self._is_running = False
            return False

        if self.active_source == "ios_device":
            ready = self._device_ready.wait(_IOS_DEVICE_READY_TIMEOUT_S)
            if not ready or self._device_error:
                self.stop()
                raise AdapterError(self._device_error or "O iPhone nao comecou a mandar o log a tempo.")
        return True

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

        source = self.active_source
        assembler = IOSLogRecordAssembler()

        for line in iter(self._proc.stdout.readline, ""):
            if not self._is_running:
                break
            if not line:
                continue

            if source == "ios_device":
                self._handle_device_line(line)
            elif source == "ios_simulator":
                for record in assembler.feed(line):
                    self._emit(self._parse_ios_record(record))
            # Filtra linhas de eventos do Firebase
            elif any(marker in line for marker in ("Logging event", "logging event", "Event recorded:", "Log event:")):
                self._emit(self._parse_line(line.strip(), platform=self.active_platform))

        if source == "ios_device" and not self._device_ready.is_set():
            # Filho saiu sem dizer nada (crash, import quebrado): nao deixar o
            # `start` esperando o prazo inteiro.
            self._device_error = self._device_error or "A leitura do log do iPhone encerrou inesperadamente."
            self._device_ready.set()

    def _handle_device_line(self, line: str) -> None:
        """Uma linha JSON do filho `ios_device_log` (ver o protocolo la)."""
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            return
        if "status" in payload:
            self._device_ready.set()
            return
        if "error" in payload:
            logger.warning("Log do iPhone: %s", payload["error"])
            self._device_error = payload["error"]
            self._device_ready.set()
            return
        # Mesmo formato do `log stream` do simulador, para um parser so.
        record = f"{payload.get('time', '')} {payload.get('process', '')}[{payload.get('pid', '')}] {payload.get('message', '')}"
        self._emit(self._parse_ios_record(record))

    def _emit(self, event: AnalyticsEvent | None) -> None:
        if not event:
            return
        with self._lock:
            self.events_history.append(event)
        self.event_queue.put(event)
        for cb in self._callbacks:
            try:
                cb(event)
            except Exception:
                logger.exception("Callback de analytics falhou.")

    def _parse_ios_record(self, record: str) -> AnalyticsEvent | None:
        """Extrai o evento de um registro (ja remontado) do Firebase iOS.

        Formato (I-ACS023073, com -FIRDebugEnabled):
            ... [FirebaseAnalytics][I-ACS023073] Debug mode is enabled. Marking
            event as debug and real-time. Event name, parameters: nome, {
                component = button;
                ga_debug (_dbg) = 1;
            }
        """
        for pattern in _IOS_EVENT_PATTERNS:
            m_event = pattern.search(record)
            if m_event:
                break
        else:
            # Formato antigo de uma linha ("Logging event: origin=app, name=...").
            if "Logging event: origin=" in record:
                return self._parse_line(record, platform="ios")
            return None

        body_start = m_event.end()
        body_end = record.rfind("}")
        params = _parse_ios_dict(record[body_start:body_end]) if body_end >= body_start else {}
        event_name = _strip_short_name(m_event.group("name"))

        m_code = re.search(r"\[(I-ACS\d+)\]", record)
        if self._is_ios_stage_duplicate(event_name, params, m_code.group(1) if m_code else ""):
            return None

        m_time = re.search(r"(\d\d:\d\d:\d\d(?:\.\d+)?)", record)
        time_str = m_time.group(1) if m_time else datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]

        return AnalyticsEvent(
            id=self.get_next_id(),
            timestamp=time.time(),
            time_str=time_str,
            tag="iOS (Firebase)",
            event_name=event_name,
            params=params,
            raw_log=record,
            platform="ios",
        )

    def _is_ios_stage_duplicate(self, event_name: str, params: dict[str, Any], code: str) -> bool:
        """Diz se o registro e outro estagio de um evento ja emitido.

        Com debug ligado o SDK loga o mesmo evento como I-ACS023073 e depois
        I-ACS023072. Um registro repete um evento recente quando algum evento
        de mesma assinatura ainda nao passou por aquele estagio; se todos ja
        passaram, e um disparo novo (ex.: dois toques seguidos no botao).
        """
        # Os ga_* mudam entre estagios (_dbg, _r); os do app, nao.
        fingerprint = (event_name, tuple(sorted((k, str(v)) for k, v in params.items() if not k.startswith("ga_"))))
        now = time.monotonic()
        with self._lock:
            while self._ios_recent and now - self._ios_recent[0][2] > _IOS_STAGE_WINDOW_S:
                self._ios_recent.popleft()
            for fp, stages, _ts in self._ios_recent:
                if fp == fingerprint and code not in stages:
                    stages.add(code)
                    return True
            self._ios_recent.append((fingerprint, {code}, now))
            return False

    def _parse_line(self, line: str, platform: str = "android") -> AnalyticsEvent | None:
        """Extrai data, tag, nome do evento e parâmetros tanto para Android quanto iOS."""
        # 1. Extração do timestamp
        m_time = re.search(r"(\d\d:\d\d:\d\d(?:\.\d+)?)", line)
        time_str = m_time.group(1) if m_time else datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]

        # 2. Identificação da Tag/Origem
        if "FA-SVC" in line:
            tag = "FA-SVC"
        elif "FA-GMS" in line:
            tag = "FA-GMS"
        elif "FirebaseAnalytics" in line or platform == "ios":
            tag = "FirebaseAnalytics" if platform == "android" else "iOS (Firebase)"
        else:
            tag = "FA"

        # 3. Nome do evento
        # Exemplo 1: Logging event: origin=app, name=screen_view, params={...}
        # Exemplo 2: Logging event: screen_view, Bundle[{...}]
        # Exemplo 3: Event recorded: Event{appId='...', name='button_click', ...}
        m_event = re.search(
            r"(?:Logging event|logging event|Log event)(?:\s*\([^\)]+\))?:\s*(?:origin=[^,\s]+,)?\s*(?:name\s*=\s*\"?([a-zA-Z0-9_\(\)]+)\"?|([a-zA-Z0-9_]+))",
            line,
        )
        if not m_event:
            m_event_rec = re.search(r"Event recorded:\s*Event\{.*?name=['\"]?([a-zA-Z0-9_]+)['\"]?", line)
            event_name = m_event_rec.group(1) if m_event_rec else "unknown_event"
        else:
            event_name = m_event.group(1) or m_event.group(2) or "unknown_event"

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

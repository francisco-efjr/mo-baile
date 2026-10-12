"""
Log de iPhone/iPad fisico conectado por cabo, via pymobiledevice3.
------------------------------------------------------------------
O `simctl` so enxerga simulador. Para o aparelho, o log vem do servico
`os_trace_relay` do proprio iOS, que o pymobiledevice3 le pelo usbmuxd — o
mesmo canal que o Xcode usa. Nao precisa de tunel nem de modo desenvolvedor,
so do aparelho ja confiado neste Mac.

O lado que conversa com o aparelho roda como processo filho
(`python -m mobaile.adapters.ios_device_log`), e nao dentro do motor:

- o pymobiledevice3 e assincrono e pesado de importar; isolado, nao mistura
  laco asyncio com as threads do servidor nem pesa na subida do motor;
- parar a escuta e terminar o processo, igual ao logcat e ao `log stream`;
- e dependencia opcional: sem ela o motor sobe normal e so este recurso avisa.

Protocolo do filho: uma linha JSON por mensagem no stdout.
- `list`: `{"devices": [...]}` ou `{"error": "..."}`.
- `stream <udid>`: primeiro `{"status": "ready"}` ou `{"error": "..."}`, depois
  um `{"time", "process", "pid", "message"}` por registro do log.
- `stream <udid> --cfnetwork`: igual, mas so os registros dos blocos de
  diagnostico do CFNetwork (`CFNETWORK_DIAGNOSTICS`), ver `ios_cfnetwork`.
"""

from __future__ import annotations

import argparse
import asyncio
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from mobaile.domain.errors import AdapterError, ToolNotFoundError

MODULE = "mobaile.adapters.ios_device_log"
LIST_TIMEOUT_S = 15

# O aparelho despeja milhares de registros por segundo; filtrar no filho evita
# serializar e mandar tudo isso pelo pipe.
DEFAULT_CONTAINS = "I-ACS"

# O Python do proprio motor: o app instalado nao usa o .venv do repositorio.
INSTALL_HINT = f"Instale com: {sys.executable} -m pip install pymobiledevice3"

# Excecoes do pymobiledevice3 -> o que a pessoa precisa fazer. Pelo nome, para
# este modulo nao importar a biblioteca no motor.
_FRIENDLY_ERRORS = {
    "PasswordRequiredError": "Desbloqueie o iPhone e tente de novo.",
    "NotPairedError": "O iPhone nao confia neste Mac. Conecte-o, toque em \"Confiar\" e tente de novo.",
    "PairingDialogResponsePendingError": "Toque em \"Confiar\" no iPhone e tente de novo.",
    "UserDeniedPairingError": "O iPhone recusou a confianca neste Mac. Reconecte o cabo e toque em \"Confiar\".",
    "NoDeviceConnectedError": "Nenhum iPhone conectado por cabo.",
    "DeviceNotFoundError": "O iPhone escolhido nao esta mais conectado.",
    "ConnectionFailedToUsbmuxdError": "Nao foi possivel falar com o usbmuxd do macOS.",
}


def is_available() -> bool:
    return importlib.util.find_spec("pymobiledevice3") is not None


def _child_env() -> dict[str, str]:
    """Ambiente do filho com o codigo do motor no PYTHONPATH.

    O front ja passa PYTHONPATH, mas pytest e `python -m` direto nao: sem isto
    o filho nao acharia `mobaile`.
    """
    env = dict(os.environ)
    src = str(Path(__file__).resolve().parents[2])
    env["PYTHONPATH"] = os.pathsep.join(p for p in (src, env.get("PYTHONPATH", "")) if p)
    return env


# Marcadores dos blocos de `CFNETWORK_DIAGNOSTICS`: abre com
# `CFNetwork Diagnostics [1:23] ... {` e fecha com `} [1:23]`.
CFNETWORK_MARKER = "CFNetwork Diagnostics ["
_CFNETWORK_CLOSE = re.compile(r"^\s*\}\s*\[\d+:\d+\]\s*$", re.MULTILINE)


def stream_command(udid: str, contains: str = DEFAULT_CONTAINS) -> list[str]:
    return [sys.executable, "-m", MODULE, "stream", udid, "--contains", contains]


def cfnetwork_command(udid: str) -> list[str]:
    return [sys.executable, "-m", MODULE, "stream", udid, "--cfnetwork"]


def popen_kwargs() -> dict[str, Any]:
    return {"env": _child_env()}


def list_devices() -> list[dict[str, Any]]:
    """Aparelhos iOS fisicos conectados. Lista vazia quando nao ha nenhum."""
    if not is_available():
        raise ToolNotFoundError("pymobiledevice3 nao esta instalado.", detail=INSTALL_HINT)
    try:
        proc = subprocess.run(
            [sys.executable, "-m", MODULE, "list"],
            capture_output=True,
            text=True,
            timeout=LIST_TIMEOUT_S,
            stdin=subprocess.DEVNULL,  # o stdin do motor e o canal JSON-RPC
            env=_child_env(),
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise AdapterError("A listagem de iPhones conectados nao respondeu.") from exc
    try:
        payload = json.loads(proc.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise AdapterError("Falha ao listar iPhones conectados.", detail=proc.stderr[-500:]) from exc
    if "error" in payload:
        raise AdapterError(payload["error"])
    return payload.get("devices", [])


# ---------------------------------------------------------------- processo filho


def _friendly(exc: BaseException) -> str:
    return _FRIENDLY_ERRORS.get(type(exc).__name__) or f"{type(exc).__name__}: {exc}"


def _emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


async def _list() -> None:
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.usbmux import list_devices as mux_devices

    devices: list[dict[str, Any]] = []
    seen: set[str] = set()
    # USB primeiro: o mesmo aparelho pode aparecer de novo pela rede (Wi-Fi).
    for dev in sorted(await mux_devices(), key=lambda d: not d.is_usb):
        if dev.serial in seen:
            continue
        seen.add(dev.serial)
        item = {"udid": dev.serial, "name": dev.serial, "ios_version": "", "connection": dev.connection_type}
        try:
            lockdown = await create_using_usbmux(serial=dev.serial, autopair=False)
            values = lockdown.all_values
            item["name"] = values.get("DeviceName") or dev.serial
            item["ios_version"] = values.get("ProductVersion") or ""
        except Exception as exc:  # aparelho bloqueado ou nao confiado: lista mesmo assim
            item["problem"] = _friendly(exc)
        devices.append(item)
    _emit({"devices": devices})


class _CFNetworkFilter:
    """Deixa passar so o que pertence a um bloco de diagnostico do CFNetwork.

    O bloco pode vir num registro so ou quebrado em varios do mesmo processo;
    por isso o estado e por pid: aberto no marcador, fechado no `} [n:m]`.
    """

    def __init__(self) -> None:
        self._open: set[int] = set()

    def keep(self, pid: int, message: str) -> bool:
        if CFNETWORK_MARKER in message:
            if not _CFNETWORK_CLOSE.search(message.split(CFNETWORK_MARKER, 1)[1]):
                self._open.add(pid)
            return True
        if pid in self._open:
            if _CFNETWORK_CLOSE.search(message):
                self._open.discard(pid)
            return True
        return False


async def _stream(udid: str, contains: str, cfnetwork: bool = False) -> None:
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.os_trace import OsTraceService

    lockdown = await create_using_usbmux(serial=udid, autopair=False)
    service = OsTraceService(lockdown=lockdown)
    ready = False
    cf_filter = _CFNetworkFilter() if cfnetwork else None
    async for entry in service.syslog():
        if not ready:
            # So depois do primeiro registro: e quando o aparelho aceitou o stream.
            _emit({"status": "ready"})
            ready = True
        if cf_filter is not None:
            if not cf_filter.keep(entry.pid, entry.message):
                continue
        elif contains and contains not in entry.message:
            continue
        _emit({
            "time": entry.timestamp.isoformat(sep=" ", timespec="milliseconds"),
            "process": Path(entry.filename).name,
            "pid": entry.pid,
            "message": entry.message,
        })


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog=MODULE)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    stream = sub.add_parser("stream")
    stream.add_argument("udid")
    stream.add_argument("--contains", default=DEFAULT_CONTAINS)
    stream.add_argument("--cfnetwork", action="store_true")
    args = parser.parse_args(argv)

    if not is_available():
        _emit({"error": f"pymobiledevice3 nao esta instalado. {INSTALL_HINT}"})
        return 1
    try:
        if args.command == "list":
            asyncio.run(_list())
        else:
            asyncio.run(_stream(args.udid, args.contains, args.cfnetwork))
    except (KeyboardInterrupt, BrokenPipeError):
        return 0
    except Exception as exc:
        _emit({"error": _friendly(exc)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

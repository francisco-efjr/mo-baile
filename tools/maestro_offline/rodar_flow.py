#!/usr/bin/env python3
"""Roda um flow YAML (formato Maestro) pelo runner do motor do Mo baile, sem o app.

    python3 tools/maestro_offline/rodar_flow.py flow.yaml [--device emulator-5554] [-e NOME=valor]

Usa os mesmos adapters do motor (adb no Android; WDA e simctl no iOS com
--platform ios). Nao abre conexao de rede: so adb/WDA em localhost.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "engine" / "src"))

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.flow_devices import AndroidFlowDevice, IOSFlowDevice
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.domain.errors import EngineError
from mobaile.services.maestro_flow import FlowRunner, load_flow


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("flow")
    ap.add_argument("--device", help="serial adb ou UDID do simulador (padrao: o primeiro conectado)")
    ap.add_argument("--platform", choices=("android", "ios"), default="android")
    ap.add_argument("-e", "--env", action="append", default=[], metavar="NOME=valor")
    args = ap.parse_args()

    env = dict(item.split("=", 1) for item in args.env)
    try:
        flow = load_flow(args.flow, env=env)
        if args.platform == "ios":
            aparelho = IOSFlowDevice(IOSBridge(), args.device or "booted")
        else:
            adb = ADBBridge()
            serial = args.device or next((s for s, estado in adb.list_devices() if estado == "device"), None)
            if not serial:
                print("Nenhum aparelho Android conectado.", file=sys.stderr)
                return 2
            aparelho = AndroidFlowDevice(adb, serial)
        resultado = FlowRunner(aparelho, log=print).run(flow)
    except EngineError as exc:
        print(f"Flow invalido: {exc}", file=sys.stderr)
        return 2
    return 0 if resultado.success else 1


if __name__ == "__main__":
    sys.exit(main())

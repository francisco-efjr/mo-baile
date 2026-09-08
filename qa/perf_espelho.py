#!/usr/bin/env python3
"""Mede o espelho: ele acompanha e sem travar quem consome?

Três perguntas, três medições:

1. O motor acompanha uma captura lenta, como a de aparelho real?
2. Com a tela mudando sempre, o motor ainda responde a comandos?
3. Quanto custa o cliente pedir métrica a cada quadro?

Rode com: python3 qa/perf_espelho.py
"""
from __future__ import annotations

import pathlib
import statistics
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from engine_client import Motor  # noqa: E402

SERIAL = "emulator-5554"


def _consumir(m, duracao, com_roundtrip=False, sondar_comando=False):
    chegadas, tamanhos, intervalos, latencias = [], [], [], []
    anterior = None
    inicio = time.time()
    proxima_sonda = inicio + 0.5
    while time.time() - inicio < duracao:
        if sondar_comando and time.time() >= proxima_sonda:
            t0 = time.time()
            try:
                m.ok("engine.info", timeout=25)
                latencias.append((time.time() - t0) * 1000)
            except Exception:
                latencias.append(25_000)
            proxima_sonda = time.time() + 0.5
        try:
            msg = m.notificacoes.get(timeout=0.05)
        except Exception:
            continue
        if msg.get("method") != "stream.frame":
            continue
        agora = time.time()
        if anterior:
            intervalos.append((agora - anterior) * 1000)
        anterior = agora
        chegadas.append(agora)
        tamanhos.append(len(msg["params"]["png_base64"]))
        if com_roundtrip:
            m.ok("stream.stats", timeout=20)
    return chegadas, tamanhos, intervalos, latencias, time.time() - inicio


def _p95(valores):
    return statistics.quantiles(valores, n=20)[18] if len(valores) > 3 else (max(valores) if valores else 0)


def medicao_1_latencia_de_captura():
    print("\n1 · O motor acompanha captura lenta?")
    print(f"   {'captura':>9} {'capturados':>11} {'emitidos':>9} {'descartados':>12} {'p95 comando':>12}")
    for atraso in (0, 150, 350, 700):
        m = Motor(android=True, extra_env={"QA_CAPTURE_DELAY_MS": str(atraso)})
        try:
            m.ok("session.select_device", {"platform": "android", "device_id": SERIAL})
            m.ok("stream.start", {"fps": 6, "max_width": 900})
            _, _, _, latencias, _ = _consumir(m, 5.0, sondar_comando=True)
            st = m.ok("stream.stats", timeout=20)
            m.ok("stream.stop", timeout=20)
            print(f"   {atraso:>7}ms {st['frames_captured']:>11} {st['frames_emitted']:>9} "
                  f"{st['frames_skipped']:>12} {_p95(latencias):>10.0f}ms")
        finally:
            m.encerrar()


def medicao_2_pior_caso():
    print("\n2 · Tela mudando sempre: o motor ainda responde?")
    print(f"   {'captura':>9} {'emitidos/s':>11} {'payload':>9} {'banda':>10} {'p95 comando':>12} {'pior':>8}")
    for atraso in (0, 150, 350):
        m = Motor(android=True, extra_env={"QA_CAPTURE_DELAY_MS": str(atraso), "QA_ANIMADO": "1"})
        try:
            m.ok("session.select_device", {"platform": "android", "device_id": SERIAL})
            m.ok("stream.start", {"fps": 8, "max_width": 900})
            chegadas, tamanhos, _, latencias, dur = _consumir(m, 5.0, sondar_comando=True)
            m.ok("stream.stop", timeout=20)
            med = statistics.mean(tamanhos) if tamanhos else 0
            banda = (sum(tamanhos) / dur) / 1024 / 1024
            print(f"   {atraso:>7}ms {len(chegadas)/dur:>11.2f} {med/1024:>7.0f}KB "
                  f"{banda:>8.2f}MB/s {_p95(latencias):>10.0f}ms {max(latencias or [0]):>6.0f}ms")
        finally:
            m.encerrar()


def medicao_3_roundtrip():
    print("\n3 · Custo de o cliente pedir métrica a cada quadro")
    resultados = {}
    for rotulo, com_rt in (("com ida e volta", True), ("métrica embarcada", False)):
        m = Motor(android=True, extra_env={"QA_ANIMADO": "1", "QA_CAPTURE_DELAY_MS": "120"})
        try:
            m.ok("session.select_device", {"platform": "android", "device_id": SERIAL})
            m.ok("stream.start", {"fps": 8, "max_width": 900})
            chegadas, _, intervalos, _, dur = _consumir(m, 6.0, com_roundtrip=com_rt)
            m.ok("stream.stop", timeout=20)
            resultados[rotulo] = (len(chegadas) / dur, statistics.mean(intervalos) if intervalos else 0)
        finally:
            m.encerrar()
    print(f"   {'':<20} {'quadros/s':>11} {'intervalo médio':>17}")
    for rotulo, (por_s, medio) in resultados.items():
        print(f"   {rotulo:<20} {por_s:>11.2f} {medio:>15.0f}ms")
    a = resultados["com ida e volta"][0]
    b = resultados["métrica embarcada"][0]
    if a:
        print(f"\n   ganho ao embarcar a métrica: {(b / a - 1) * 100:+.0f}%")


if __name__ == "__main__":
    print("=" * 78)
    print("PERFORMANCE DO ESPELHO")
    print("=" * 78)
    medicao_1_latencia_de_captura()
    medicao_2_pior_caso()
    medicao_3_roundtrip()
    print()

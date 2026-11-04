#!/usr/bin/env python3
"""Bancada do espelho: CPU do motor e dos filhos, e quadros, com a tela parada.

Sobe uma copia do motor (o `engine/src` deste checkout, ou outro com
`--engine-src`) como processo proprio, liga o espelho e mede por N segundos:

- CPU do motor e dos filhos que ele esperou (`simctl`, `adb`), pelo
  `getrusage` do proprio motor, lido no comeco e no fim da janela;
- capturas feitas (`stream.stats`) e quadros recebidos (`stream.frame`).

Fonte do quadro:

- `ios`: o simulador iOS ligado (`xcrun simctl list devices booted`), pelo
  `simctl io screenshot`, que e o caminho que o app usa quando o MJPEG do WDA
  nao esta no ar. O MJPEG e o WDA ficam apontados para uma porta morta de
  proposito: a bancada nunca fala com o WDA de ninguem nem muda os ajustes dele.
- `sintetica`: um quadro fixo gerado em memoria, sem aparelho. Mede so a parte
  Python do laco (decodificar, comparar, codificar).
- `auto` (padrao): `ios` se houver simulador ligado, senao `sintetica`.

Nao usa o motor do app aberto nem o arquivo de log dele: o motor da bancada
sobe sem `configure_logging`. Resultado em JSON, mediana de `--repeticoes`.

    .venv/bin/python tools/bench_stream.py --segundos 60 --repeticoes 3
    .venv/bin/python tools/bench_stream.py --params '{"fps": 6, "max_width": 900}'
    .venv/bin/python tools/bench_stream.py --perfil leve
    .venv/bin/python tools/bench_stream.py --pausado
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import queue
import statistics
import subprocess
import sys
import threading
import time

REPO = pathlib.Path(__file__).resolve().parent.parent


# ------------------------------------------------------------------ motor


def _motor(engine_src: str, sintetica: bool) -> None:
    """Processo do motor da bancada: o servidor real com um metodo a mais."""
    import logging
    import resource

    sys.path.insert(0, engine_src)
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr)
    from mobaile.rpc.server import EngineServer

    server = EngineServer(out=sys.stdout)

    def rusage(_params):
        proprio = resource.getrusage(resource.RUSAGE_SELF)
        filhos = resource.getrusage(resource.RUSAGE_CHILDREN)
        return {
            "self_s": proprio.ru_utime + proprio.ru_stime,
            "children_s": filhos.ru_utime + filhos.ru_stime,
            "rss_mb": proprio.ru_maxrss / (1024 * 1024),
            "wall": time.monotonic(),
        }

    server.methods["bench.rusage"] = rusage
    if sintetica:
        import io
        import tempfile

        from PIL import Image

        # Tela do tamanho de um iPhone (1170x2532) com ruido, para o PNG custar
        # o que um print de verdade custa para decodificar.
        ruido = Image.effect_noise((1170, 2532), 24).convert("RGB")
        base = Image.blend(Image.new("RGB", ruido.size, (235, 238, 242)), ruido, 0.25)
        for y in range(0, 2532, 120):
            base.paste((30, 60, 120), (40, y, 1130, y + 60))
        import atexit
        import shutil

        atraso = float(os.environ.get("MOBAILE_BENCH_CAPTURA_MS") or 0) / 1000
        pasta = tempfile.mkdtemp(prefix="mobaile-bench-")
        atexit.register(shutil.rmtree, pasta, True)
        arquivos = {"png": os.path.join(pasta, "tela.png"), "jpeg": os.path.join(pasta, "tela.jpg")}
        base.save(arquivos["png"], "PNG")
        base.save(arquivos["jpeg"], "JPEG", quality=90)

        def captura(_udid="booted", fmt="png", **_kw):
            # Como o `simctl io screenshot -`: um processo filho escreve a
            # imagem no pipe e o motor decodifica. O custo do `simctl` em si
            # (CoreSimulator) fica de fora; ver o modo `ios`.
            if atraso:
                # Latencia de parede do `simctl` (~270 ms medidos), sem CPU.
                time.sleep(atraso)
            dados = subprocess.run(["/bin/cat", arquivos.get(fmt, arquivos["png"])], capture_output=True, timeout=6).stdout
            imagem = Image.open(io.BytesIO(dados)).convert("RGB")
            imagem.load()
            return imagem

        server.ios.take_screenshot = captura
        server.ios.list_booted_simulators = lambda: [("SINTETICO", "Sintetico")]
    server.serve_forever()


# ---------------------------------------------------------------- cliente


class Cliente:
    def __init__(self, python: str, engine_src: str, sintetica: bool, captura_ms: float = 0) -> None:
        env = dict(os.environ)
        env["PYTHONPATH"] = engine_src
        env["PYTHONUNBUFFERED"] = "1"
        # Porta morta: nada de MJPEG nem de WDA de outra pessoa.
        env["WDA_URL"] = "http://127.0.0.1:9"
        env["WDA_MJPEG_PORT"] = "9"
        env["MOBAILE_BENCH_CAPTURA_MS"] = str(captura_ms)
        cmd = [python, str(pathlib.Path(__file__).resolve()), "--_motor", "--engine-src", engine_src]
        if sintetica:
            cmd.append("--_sintetica")
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1, env=env,
        )
        self._id = 0
        self._respostas: dict[int, queue.Queue] = {}
        self._lock = threading.Lock()
        self.quadros = 0
        self.bytes_quadros = 0
        self.contando = False
        threading.Thread(target=self._ler, daemon=True).start()

    def _ler(self) -> None:
        assert self.proc.stdout is not None
        for linha in self.proc.stdout:
            try:
                msg = json.loads(linha)
            except json.JSONDecodeError:
                continue
            if "id" in msg and msg.get("id") is not None:
                with self._lock:
                    fila = self._respostas.get(msg["id"])
                if fila is not None:
                    fila.put(msg)
            elif msg.get("method") == "stream.frame" and self.contando:
                self.quadros += 1
                self.bytes_quadros += len(linha)

    def chamar(self, metodo: str, params: dict | None = None, prazo: float = 30.0) -> dict:
        with self._lock:
            self._id += 1
            ident = self._id
            fila: queue.Queue = queue.Queue()
            self._respostas[ident] = fila
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": ident, "method": metodo, "params": params or {}}) + "\n")
        self.proc.stdin.flush()
        msg = fila.get(timeout=prazo)
        if "error" in msg:
            raise RuntimeError(f"{metodo}: {msg['error']}")
        return msg["result"]

    def encerrar(self) -> None:
        try:
            self.chamar("engine.shutdown", prazo=10)
        except Exception:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def simulador_ligado() -> str | None:
    try:
        saida = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "booted", "-j"], capture_output=True, text=True, timeout=15,
        ).stdout
        for aparelhos in json.loads(saida).get("devices", {}).values():
            for aparelho in aparelhos:
                if aparelho.get("state") == "Booted":
                    return aparelho["udid"]
    except Exception:
        return None
    return None


def rodada(args, udid: str, sintetica: bool) -> dict:
    cliente = Cliente(args.python, args.engine_src, sintetica, args.captura_ms)
    try:
        cliente.chamar("session.select_device", {"platform": "ios", "device_id": udid})
        if args.perfil:
            cliente.chamar("perf.set_preference", {"preference": args.perfil})
        if args.vigia:
            cliente.chamar("devices.watch_start")
        inicio = cliente.chamar("stream.start", json.loads(args.params))
        if args.pausado:
            cliente.chamar("stream.pause")
        time.sleep(args.aquecimento)
        stats0 = cliente.chamar("stream.stats")
        uso0 = cliente.chamar("bench.rusage")
        cliente.contando = True
        time.sleep(args.segundos)
        cliente.contando = False
        uso1 = cliente.chamar("bench.rusage")
        stats1 = cliente.chamar("stream.stats")
        janela = uso1["wall"] - uso0["wall"]
        cpu_motor = uso1["self_s"] - uso0["self_s"]
        cpu_filhos = uso1["children_s"] - uso0["children_s"]
        return {
            "fps_pedido": inicio.get("fps"),
            "max_width": inicio.get("max_width"),
            "quality": inicio.get("quality"),
            "janela_s": round(janela, 2),
            "cpu_motor_pct": round(100 * cpu_motor / janela, 1),
            "cpu_filhos_pct": round(100 * cpu_filhos / janela, 1),
            "cpu_total_pct": round(100 * (cpu_motor + cpu_filhos) / janela, 1),
            "capturas_por_s": round((stats1.get("frames_captured", 0) - stats0.get("frames_captured", 0)) / janela, 2),
            "quadros_recebidos": cliente.quadros,
            "kb_quadros": round(cliente.bytes_quadros / 1024, 1),
            "rss_max_mb": round(uso1["rss_mb"], 1),
        }
    finally:
        cliente.encerrar()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--_motor", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--_sintetica", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--engine-src", default=str(REPO / "engine" / "src"))
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--fonte", choices=("auto", "ios", "sintetica"), default="auto")
    ap.add_argument("--segundos", type=float, default=60.0)
    ap.add_argument("--aquecimento", type=float, default=5.0)
    ap.add_argument("--repeticoes", type=int, default=3)
    ap.add_argument("--params", default="{}", help="params do stream.start, em JSON")
    ap.add_argument("--perfil", choices=("completo", "equilibrado", "leve"), help="perf.set_preference antes de ligar")
    ap.add_argument("--pausado", action="store_true", help="stream.pause logo depois de ligar (janela oculta)")
    ap.add_argument("--sem-vigia", dest="vigia", action="store_false", help="nao liga devices.watch_start")
    ap.add_argument("--captura-ms", type=float, default=0.0,
                    help="fonte sintetica: latencia de parede por captura (o simctl leva ~270 ms)")
    ap.add_argument("--rotulo", default="")
    args = ap.parse_args()

    if args._motor:
        _motor(args.engine_src, args._sintetica)
        return 0

    udid = simulador_ligado() if args.fonte in ("auto", "ios") else None
    if args.fonte == "ios" and not udid:
        print("nenhum simulador iOS ligado", file=sys.stderr)
        return 2
    sintetica = udid is None
    udid = udid or "SINTETICO"

    rodadas = [rodada(args, udid, sintetica) for _ in range(args.repeticoes)]
    chaves = ("cpu_motor_pct", "cpu_filhos_pct", "cpu_total_pct", "capturas_por_s", "quadros_recebidos", "kb_quadros", "rss_max_mb")
    resultado = {
        "rotulo": args.rotulo,
        "fonte": "sintetica" if sintetica else "ios_simctl",
        "segundos": args.segundos,
        "params": json.loads(args.params),
        "perfil": args.perfil,
        "pausado": args.pausado,
        "vigia": args.vigia,
        "captura_ms": args.captura_ms,
        "mediana": {chave: statistics.median(r[chave] for r in rodadas) for chave in chaves},
        "rodadas": rodadas,
    }
    print(json.dumps(resultado, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

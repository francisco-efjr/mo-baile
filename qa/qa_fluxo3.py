import sys

"""FLUXO 3 — so Android: espelho, hierarquia, toque, digitacao e proxy."""
import json
import pathlib
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from engine_client import Motor

falhas, passes = [], []
def check(nome, cond, detalhe=""):
    (passes if cond else falhas).append(nome)
    print(f"  [{'PASS' if cond else 'FALHA'}] {nome}" + (f"  -> {detalhe}" if detalhe and not cond else ""))

def chamadas_adb():
    linhas = []
    with open(str(pathlib.Path(__file__).resolve().parent / "calls.log"), encoding="utf-8") as f:
        for l in f:
            l = l.strip()
            if l:
                d = json.loads(l)
                if d["bin"] == "adb":
                    linhas.append(d["argv"])
    return linhas

print("=" * 78)
print("FLUXO 3 — SO ANDROID")
print("=" * 78)

open(str(pathlib.Path(__file__).resolve().parent / "calls.log"), "w").close()
SERIAL = "emulator-5554"

m = Motor(android=True, ios=False)
try:
    devs = m.ok("devices.list", {"platform": "android"})["devices"]
    check("aparelho aparece na lista", len(devs) == 1 and devs[0]["id"] == SERIAL, str(devs))
    check("modelo do aparelho consultado", devs and devs[0]["name"] == "Pixel 7 QA", str(devs))
    check("aparelho marcado como pronto", devs and devs[0]["ready"] is True)

    d = m.ok("diagnostics.check")["android"]
    print(f"\n  diagnostico Android ready={d['ready']}")
    for c in d["checks"]:
        print(f"    [{c['state']:<5}] {c['label']:<24} {c['detail'][:56]}")
    check("Android declarado pronto", d["ready"] is True)

    m.ok("session.select_device", {"platform": "android", "device_id": SERIAL})

    # --- espelho ------------------------------------------------------------
    frame = m.ok("screen.capture", {"max_width": 360})
    check("captura devolve PNG", frame["png_base64"].startswith("iVBOR"))
    check("origem 1080x2400 preservada", frame["source_width"] == 1080)
    tam = m.ok("screen.size")
    check("wm size lido do aparelho", (tam["width"], tam["height"]) == (1080, 2400), str(tam))

    # --- hierarquia ---------------------------------------------------------
    dump = m.ok("hierarchy.dump")
    check("uiautomator dump parseado", dump["count"] >= 3, f"count={dump['count']}")
    botao = next((e for e in dump["elements"] if "btn_continuar" in e["resource_id"]), None)
    check("botao do app localizado", botao is not None)
    check("bounds android convertidos", botao and botao["bounds"] == [100, 400, 980, 560], str(botao and botao["bounds"]))
    check("package capturado", botao and botao["package"] == "br.com.amobs", str(botao and botao.get("package")))

    argv = chamadas_adb()
    dumps = [a for a in argv if "uiautomator" in " ".join(a)]
    check("dump usa caminho privado, nao /sdcard", dumps and "/data/local/tmp/" in " ".join(dumps[0]), str(dumps[:1]))
    remocoes = [a for a in argv if a[-2:-1] == ["rm"] or "rm" in a]
    check("artefato do dump e removido do aparelho", len(remocoes) > 0, "nenhum rm encontrado")

    achado = m.ok("hierarchy.element_at", {"x": 540, "y": 480})["element"]
    check("element_at acha o botao", achado and "btn_continuar" in achado["resource_id"])

    # --- toque --------------------------------------------------------------
    antes = len(chamadas_adb())
    m.ok("input.tap", {"x": 540, "y": 480})
    novos = chamadas_adb()[antes:]
    tap = [a for a in novos if "tap" in " ".join(a)]
    check("tap enviado ao aparelho", len(tap) == 1, str(novos))
    check("coordenadas corretas no comando", tap and tap[0][-2:] == ["540", "480"], str(tap))

    # --- digitacao e escaping (correcao de seguranca) -----------------------
    antes = len(chamadas_adb())
    m.ok("input.text", {"text": "valor 1500"})
    cmd = [a for a in chamadas_adb()[antes:] if "input text" in " ".join(a)]
    check("digitacao enviada", len(cmd) == 1, str(chamadas_adb()[antes:]))
    if cmd:
        remoto = cmd[0][-1]
        check("espaco vira %s", "valor%s1500" in remoto, remoto)
        check("comando remoto vai como argumento unico", len(cmd[0]) == 4, str(cmd[0]))
        check("texto entre aspas simples", remoto == "input text 'valor%s1500'", remoto)

    antes = len(chamadas_adb())
    m.ok("input.text", {"text": "a; rm -rf /tmp/x && echo $(id)"})
    cmd = [a for a in chamadas_adb()[antes:] if "input text" in " ".join(a)]
    if cmd:
        remoto = cmd[0][-1]
        corpo = remoto[len("input text "):]
        check("payload de injecao fica inteiro dentro das aspas",
              corpo.startswith("'") and corpo.endswith("'"), remoto)
        check("nenhuma aspa solta escapa do quoting",
              "'" not in corpo[1:-1].replace("'\\''", ""), remoto)
        print(f"       comando remoto: {remoto}")

    e = m.erro("input.text", {"text": "linha1\nlinha2"})
    check("texto com quebra de linha e recusado", e["data"]["code"] == "invalid_input")

    e = m.erro("session.select_device", {"platform": "android", "device_id": 'x"; rm -rf /'})
    check("serial malicioso e recusado", e["data"]["code"] == "invalid_input")

    # --- gravacao -----------------------------------------------------------
    g = m.ok("codegen.record", {"x": 540, "y": 480, "strategy": "xpath"})
    check("gravacao com xpath funciona", "XPATH" in g["object_code"].upper(), g["object_code"][:70])
    check("passo registrado", m.ok("codegen.steps")["steps"][0]["platform"] == "android")

    # --- streaming ----------------------------------------------------------
    m.ok("stream.start", {"fps": 20, "max_width": 300})
    n = m.esperar_notificacao("stream.frame", timeout=10)
    check("quadro Android chega por notificacao", n["params"]["width"] == 300)
    time.sleep(1.0)
    st = m.ok("stream.stats")
    print(f"\n  stream: capturados={st['frames_captured']} emitidos={st['frames_emitted']} descartados={st['frames_skipped']}")
    check("tela parada descarta quadro", st["frames_skipped"] > 0, str(st))
    m.ok("stream.stop")

    # --- proxy no aparelho --------------------------------------------------
    antes = len(chamadas_adb())
    r = m.ok("proxy.start", {"configure_device": True})
    novos = chamadas_adb()[antes:]
    check("proxy sobe", r["running"] is True)
    check("adb reverse configurado", any("reverse" in " ".join(a) for a in novos), str(novos))
    check("proxy global apontado para loopback",
          any("127.0.0.1:8082" in " ".join(a) for a in novos), str(novos))
    check("proxy do aparelho configurado com sucesso", r["device_configured"] is True)

    antes = len(chamadas_adb())
    m.ok("proxy.stop")
    novos = chamadas_adb()[antes:]
    check("proxy do aparelho e desfeito no stop",
          any("http_proxy" in " ".join(a) and ":0" in " ".join(a) for a in novos), str(novos))
    check("reverse removido", any("--remove" in " ".join(a) for a in novos), str(novos))

    check("nenhum erro no stderr", not [l for l in m.stderr if "Traceback" in l],
          str([l for l in m.stderr if "Traceback" in l][:1]))
finally:
    m.encerrar()

print(f"\n  RESULTADO: {len(passes)} passaram, {len(falhas)} falharam")
if falhas: print("  FALHAS:", falhas)
sys.exit(1 if falhas else 0)

import sys

"""FLUXO 2 — so iOS: espelho, hierarquia, toque e gravacao."""
import json
import pathlib
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fake_wda
from engine_client import Motor

falhas, passes = [], []
def check(nome, cond, detalhe=""):
    (passes if cond else falhas).append(nome)
    print(f"  [{'PASS' if cond else 'FALHA'}] {nome}" + (f"  -> {detalhe}" if detalhe and not cond else ""))

print("=" * 78)
print("FLUXO 2 — SO iOS")
print("=" * 78)

servidor = fake_wda.start(8100)
open(str(pathlib.Path(__file__).resolve().parent / "calls.log"), "w").close()
UDID = "A1B2C3D4-1111-2222-3333-444455556666"

m = Motor(android=False, ios=True)
try:
    # --- deteccao -----------------------------------------------------------
    sims = m.ok("devices.list", {"platform": "ios"})["devices"]
    check("simulador ligado aparece na lista", len(sims) == 1 and sims[0]["id"] == UDID, str(sims))
    check("nome do simulador vem junto", sims and sims[0]["name"] == "iPhone 16 QA")

    d = m.ok("diagnostics.check")["ios"]
    estados = {c["label"]: c["state"] for c in d["checks"]}
    print(f"\n  diagnostico iOS ready={d['ready']}")
    for c in d["checks"]:
        print(f"    [{c['state']:<5}] {c['label']:<24} {c['detail'][:56]}")
    check("simulador ligado detectado", estados.get("Simulador ligado") == "ok")
    check("WDA detectado no ar", estados.get("WebDriverAgent") == "ok")
    check("iOS declarado pronto", d["ready"] is True)

    # --- sessao -------------------------------------------------------------
    s = m.ok("session.select_device", {"platform": "ios", "device_id": UDID})
    check("sessao aceita o simulador", s == {"platform": "ios", "device_id": UDID})

    # --- espelho ------------------------------------------------------------
    frame = m.ok("screen.capture", {"max_width": 400})
    check("captura devolve PNG em base64", frame["png_base64"].startswith("iVBOR"))
    check("captura reduz para o max_width pedido", frame["width"] == 400, str(frame["width"]))
    check("resolucao de origem preservada", frame["source_width"] == 1170, str(frame["source_width"]))

    tam = m.ok("screen.size")
    check("screen.size devolve a tela do simulador", (tam["width"], tam["height"]) == (1170, 2532), str(tam))

    # --- hierarquia ---------------------------------------------------------
    dump = m.ok("hierarchy.dump")
    check("hierarquia parseada do WDA", dump["count"] >= 3, f"count={dump['count']}")
    nomes = [e["display_name"] for e in dump["elements"]]
    check("elementos do app aparecem", "Continuar" in " ".join(nomes), str(nomes))
    botao = next((e for e in dump["elements"] if e["resource_id"] == "btn_continuar"), None)
    check("botao localizado com id", botao is not None)
    check("chip de tipo correto para botao", botao and botao["chip_type"] == "B", botao and botao["chip_type"])
    check("bounds convertidos de x/y/width/height",
          botao and botao["bounds"] == [24, 200, 366, 250], str(botao and botao["bounds"]))

    achado = m.ok("hierarchy.element_at", {"x": 195, "y": 225})["element"]
    check("element_at acha o botao no centro dele", achado and achado["resource_id"] == "btn_continuar",
          str(achado and achado.get("resource_id")))

    # --- interacao ----------------------------------------------------------
    fake_wda.CHAMADAS.clear()
    r = m.ok("input.tap", {"x": 195, "y": 225})
    check("input.tap responde ok", r["ok"] is True)
    taps = [c for c in fake_wda.CHAMADAS if "/wda/tap" in c[1]]
    check("toque chegou de verdade no WDA", len(taps) == 1, str(fake_wda.CHAMADAS))
    if taps:
        corpo = json.loads(taps[0][2])
        check("coordenada do toque preservada", corpo == {"x": 195, "y": 225}, str(corpo))

    # --- gravacao de passo --------------------------------------------------
    gravado = m.ok("codegen.record", {"x": 195, "y": 225, "strategy": "id"})
    check("passo gravado gera nome de variavel", "BOTAO" in gravado["var_name"], gravado["var_name"])
    check("gera linha de Page Object", "AppiumBy" in gravado["object_code"], gravado["object_code"][:60])
    check("gera bloco de acao", "def " in gravado["action_code"], gravado["action_code"][:60])
    passos = m.ok("codegen.steps")["steps"]
    check("passo aparece na lista", len(passos) == 1 and passos[0]["platform"] == "ios", str(passos))

    # --- streaming ----------------------------------------------------------
    m.ok("stream.start", {"fps": 20, "max_width": 300})
    n1 = m.esperar_notificacao("stream.frame", timeout=10)
    check("quadro chega como notificacao", "png_base64" in n1["params"])
    check("notificacao nao carrega id", "id" not in n1)
    check("quadro respeita max_width", n1["params"]["width"] == 300, str(n1["params"]["width"]))
    time.sleep(1.2)
    st = m.ok("stream.stats")
    print(f"\n  stream: capturados={st['frames_captured']} emitidos={st['frames_emitted']} "
          f"descartados={st['frames_skipped']} fps={st['effective_fps']}")
    check("stream esta rodando", st["running"] is True)
    check("capturou varios quadros", st["frames_captured"] >= 3, str(st["frames_captured"]))
    check("tela estatica faz o motor descartar quadro",
          st["frames_skipped"] > 0, f"skipped={st['frames_skipped']}")
    m.ok("stream.stop")
    check("stream para sem erro", m.ok("stream.stats") == {"running": False})

    check("nenhum erro no stderr do motor",
          not [l for l in m.stderr if " ERROR " in l or "Traceback" in l],
          str([l for l in m.stderr if " ERROR " in l][:2]))
finally:
    m.encerrar()
    servidor.shutdown()

print(f"\n  RESULTADO: {len(passes)} passaram, {len(falhas)} falharam")
if falhas: print("  FALHAS:", falhas)
sys.exit(1 if falhas else 0)

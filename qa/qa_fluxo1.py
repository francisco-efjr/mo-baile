import sys

"""FLUXO 1 — sem dispositivo nenhum."""
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from engine_client import Motor

falhas, passes = [], []
def check(nome, cond, detalhe=""):
    (passes if cond else falhas).append(nome)
    print(f"  [{'PASS' if cond else 'FALHA'}] {nome}" + (f"  -> {detalhe}" if detalhe and not cond else ""))

print("=" * 78)
print("FLUXO 1 — SEM DISPOSITIVO")
print("=" * 78)

m = Motor(android=False, ios=False)
try:
    info = m.ok("engine.info")
    check("motor sobe e responde engine.info", bool(info.get("version")))
    check("stdout so tem protocolo (log foi para stderr)",
          not any("LINHA FORA DO PROTOCOLO" in s for s in m.stderr))

    devs = m.ok("devices.list", {"platform": "android"})["devices"]
    check("nenhum Android listado", devs == [], f"veio {devs}")
    sims = m.ok("devices.list", {"platform": "ios"})["devices"]
    check("nenhum simulador listado", sims == [], f"veio {sims}")

    d = m.ok("diagnostics.check")
    ios, android = d["ios"], d["android"]
    print(f"\n  iOS      ready={ios['ready']}")
    for c in ios["checks"]:
        print(f"    [{c['state']:<5}] {c['label']:<24} {c['detail'][:60]}")
    print(f"  Android  ready={android['ready']}")
    for c in android["checks"]:
        print(f"    [{c['state']:<5}] {c['label']:<24} {c['detail'][:60]}\n" if c is android["checks"][-1] else
              f"    [{c['state']:<5}] {c['label']:<24} {c['detail'][:60]}")

    check("iOS nao se declara pronto", ios["ready"] is False)
    check("Android nao se declara pronto", android["ready"] is False)

    estados_android = {c["label"]: c["state"] for c in android["checks"]}
    check("NAO mente 'Dispositivo autorizado' com visto verde",
          estados_android.get("Dispositivo autorizado") != "ok",
          f"veio {estados_android.get('Dispositivo autorizado')}")
    check("ADB detectado como instalado (fake no PATH)",
          estados_android.get("ADB instalado") == "ok")
    check("emulador parado sugere acao de ligar",
          any(c["action"] == "boot_avd" for c in android["checks"]),
          str([c["action"] for c in android["checks"]]))

    estados_ios = {c["label"]: c["state"] for c in ios["checks"]}
    check("xcrun detectado", estados_ios.get("Ferramentas do Xcode") == "ok")
    check("simulador instalado detectado", estados_ios.get("Simulador instalado") == "ok")
    check("simulador desligado nao vira 'ok'", estados_ios.get("Simulador ligado") != "ok")
    check("simulador parado sugere acao de ligar",
          any(c["action"] == "boot_simulator" for c in ios["checks"]))

    # Operacoes que exigem alvo precisam falhar com mensagem util, nao travar.
    e = m.erro("hierarchy.dump")
    check("hierarchy.dump sem alvo devolve erro tipado", e["data"]["code"] == "invalid_input")
    e = m.erro("input.tap", {"x": 10, "y": 10})
    check("input.tap sem alvo devolve erro tipado", e["data"]["code"] == "invalid_input")
    check("mensagem de erro fala em dispositivo", "dispositivo" in e["message"].lower(), e["message"])

    st = m.ok("stream.stats")
    check("stream.stats sem stream nao explode", st == {"running": False})

    check("simulators.list funciona sem device", len(m.ok("simulators.list")["simulators"]) == 2)
    check("emulators.list funciona sem device", m.ok("emulators.list")["avds"] == ["Pixel_7_API_34", "Pixel_Tablet_API_34"])
finally:
    m.encerrar()

print(f"\n  RESULTADO: {len(passes)} passaram, {len(falhas)} falharam")
if falhas:
    print("  FALHAS:", falhas)
sys.exit(1 if falhas else 0)

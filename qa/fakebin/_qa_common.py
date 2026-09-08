"""Apoio dos binarios falsos: log de chamadas e telas sinteticas."""
import io
import json
import os
import pathlib
import sys
from pathlib import Path

LOG = Path(os.environ.get("QA_LOG", str(pathlib.Path(__file__).resolve().parent / "calls.log")))

def registrar(binario, argv):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"bin": binario, "argv": argv}, ensure_ascii=False) + "\n")

def tem_android():
    return os.environ.get("QA_ANDROID", "0") == "1"

def tem_ios():
    return os.environ.get("QA_IOS", "0") == "1"

def atraso_de_captura():
    """Simula o custo real de `screencap` / `simctl io`, que nao e instantaneo."""
    import time
    ms = float(os.environ.get("QA_CAPTURE_DELAY_MS", "0"))
    if ms:
        time.sleep(ms / 1000.0)


def png(w, h, cor=(20, 20, 34)):
    """PNG real, para o app decodificar de verdade com Pillow."""
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (w, h), cor)
    d = ImageDraw.Draw(img)
    # Um "botao" desenhado no mesmo lugar do XML da hierarquia.
    d.rectangle([100, 400, 980, 560], fill=(137, 180, 250))
    # Faixa que muda a cada chamada, para o detector de diferenca ter o que ver.
    # QA_ANIMADO=1: a tela muda a cada captura, forcando o pior caso em que
    # nenhum quadro e descartado e tudo sobe para a apresentacao.
    if os.environ.get("QA_ANIMADO") == "1":
        import time as _t
        fase = int((_t.time() * 1000) % 1000)
        d.rectangle([0, 0, w, h // 3], fill=(fase % 255, (fase * 3) % 255, 120))
    else:
        n = int(os.environ.get("QA_FRAME", "0"))
        d.rectangle([0, 0, w, 8], fill=((n * 40) % 255, 80, 120))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()

def emitir_binario(dados):
    sys.stdout.buffer.write(dados)
    sys.stdout.buffer.flush()

ANDROID_XML = """<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" class="android.widget.FrameLayout" package="br.com.amobs" bounds="[0,0][1080,2400]" clickable="false" text="" content-desc="" resource-id="">
    <node index="0" class="android.widget.TextView" package="br.com.amobs" bounds="[100,200][980,280]" clickable="false" text="Simulacao de credito" content-desc="" resource-id="br.com.amobs:id/titulo"/>
    <node index="1" class="android.widget.EditText" package="br.com.amobs" bounds="[100,300][980,380]" clickable="true" text="" content-desc="Valor desejado" resource-id="br.com.amobs:id/campo_valor"/>
    <node index="2" class="android.widget.Button" package="br.com.amobs" bounds="[100,400][980,560]" clickable="true" text="Continuar" content-desc="Continuar simulacao" resource-id="br.com.amobs:id/btn_continuar"/>
  </node>
</hierarchy>"""

IOS_XML = """<?xml version="1.0" encoding="UTF-8"?>
<XCUIElementTypeApplication name="AMobs" label="AMobs" x="0" y="0" width="390" height="844">
  <XCUIElementTypeWindow x="0" y="0" width="390" height="844">
    <XCUIElementTypeStaticText name="titulo" label="Simulacao de credito" value="Simulacao de credito" x="24" y="80" width="342" height="30"/>
    <XCUIElementTypeTextField name="campo_valor" label="Valor desejado" value="" x="24" y="130" width="342" height="44" accessible="true"/>
    <XCUIElementTypeButton name="btn_continuar" label="Continuar" x="24" y="200" width="342" height="50" accessible="true"/>
  </XCUIElementTypeWindow>
</XCUIElementTypeApplication>"""

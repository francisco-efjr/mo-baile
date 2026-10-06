"""Aparelho falso para os testes de execucao de fluxo.

Os falsos ficam so na fronteira: um `adb` executavel de verdade (o processo
filho do fluxo o chama por caminho absoluto) e um WebDriverAgent HTTP de
verdade numa porta efemera. Parser, processo filho, canal de eventos e
servidor JSON-RPC sao os reais.

O `adb` falso le o seu comportamento de arquivos ao lado dele, e nao de
variavel de ambiente: assim o teste muda a tela entre duas execucoes sem
reiniciar nada, como acontece num aparelho de verdade.
"""

from __future__ import annotations

import http.server
import json
import stat
import sys
import threading
from pathlib import Path

SERIAL = "emulator-5554"
UDID = "A1B2C3D4-1111-2222-3333-444455556666"


def xml_android(*, botao_bounds: str | None = "[100,400][980,560]", campo_focado: bool = False) -> str:
    """Tela com um campo e, opcionalmente, um botao em `botao_bounds`."""
    botao = (
        f'<node index="2" class="android.widget.Button" package="br.app" bounds="{botao_bounds}" '
        'clickable="true" text="Continuar" content-desc="" resource-id="br.app:id/btn_continuar" '
        'focused="false"/>'
        if botao_bounds else ""
    )
    return (
        "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
        '<hierarchy rotation="0">'
        '<node index="0" class="android.widget.FrameLayout" package="br.app" bounds="[0,0][1080,2400]" '
        'clickable="false" text="" content-desc="" resource-id="" focused="false">'
        '<node index="1" class="android.widget.EditText" package="br.app" bounds="[100,300][980,380]" '
        'clickable="true" text="" content-desc="Valor desejado" resource-id="br.app:id/campo_valor" '
        f'focused="{"true" if campo_focado else "false"}"/>'
        f"{botao}"
        "</node></hierarchy>"
    )


_ADB = r'''#!{python}
import json, sys, time
from pathlib import Path

AQUI = Path(__file__).resolve().parent
argv = sys.argv[1:]


def registrar(evento):
    with (AQUI / "adb_calls.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(evento, ensure_ascii=False) + "\n")


def ler(nome, padrao=""):
    caminho = AQUI / nome
    return caminho.read_text(encoding="utf-8") if caminho.exists() else padrao


registrar({"argv": argv})
a = argv[2:] if argv[:1] == ["-s"] else argv

if argv[:1] == ["devices"]:
    print("List of devices attached")
    print("{serial}\tdevice")
    sys.exit(0)
if a[:1] == ["get-state"]:
    print("device")
    sys.exit(0)
if a[:1] == ["shell"] and len(a) >= 2:
    comando = " ".join(a[1:])
    if "uiautomator dump" in comando or a[1:2] == ["cat"]:
        print(ler("hierarquia.xml"))
        sys.exit(0)
    if a[1:3] == ["dumpsys", "input_method"]:
        print("mInputShown=" + ("true" if (AQUI / "teclado_aberto").exists() else "false"))
        sys.exit(0)
    if a[1:3] == ["input", "tap"]:
        registrar({"toque_inicio": a[3:5]})
        time.sleep(float(ler("atraso_toque", "0") or 0))
        registrar({"toque_fim": a[3:5]})
        sys.exit(int(ler("falha_toque", "0") or 0))
    if comando.startswith("input text "):
        sys.exit(int(ler("falha_texto", "0") or 0))
sys.exit(0)
'''


class AdbFalso:
    def __init__(self, pasta: Path) -> None:
        self.pasta = pasta
        self.caminho = pasta / "adb"
        self.caminho.write_text(_ADB.replace("{python}", sys.executable).replace("{serial}", SERIAL),
                                encoding="utf-8")
        self.caminho.chmod(self.caminho.stat().st_mode | stat.S_IXUSR)
        self._log = pasta / "adb_calls.jsonl"
        self.tela(xml_android())

    def tela(self, xml: str) -> None:
        (self.pasta / "hierarquia.xml").write_text(xml, encoding="utf-8")

    def teclado(self, aberto: bool) -> None:
        marcador = self.pasta / "teclado_aberto"
        if aberto:
            marcador.write_text("1", encoding="utf-8")
        else:
            marcador.unlink(missing_ok=True)

    def atraso_toque(self, segundos: float) -> None:
        (self.pasta / "atraso_toque").write_text(str(segundos), encoding="utf-8")

    def falhar_texto(self, codigo: int = 1) -> None:
        (self.pasta / "falha_texto").write_text(str(codigo), encoding="utf-8")

    def limpar_registro(self) -> None:
        self._log.unlink(missing_ok=True)

    def eventos(self) -> list[dict]:
        if not self._log.exists():
            return []
        return [json.loads(linha) for linha in self._log.read_text(encoding="utf-8").splitlines() if linha]

    def chamadas(self) -> list[list[str]]:
        return [e["argv"] for e in self.eventos() if "argv" in e]

    def toques(self) -> list[tuple[int, int]]:
        return [(int(e["toque_fim"][0]), int(e["toque_fim"][1])) for e in self.eventos() if "toque_fim" in e]

    def textos(self) -> list[str]:
        """O comando remoto de cada digitacao, exatamente como chegou ao aparelho."""
        return [c[-1] for c in self.chamadas() if c and c[-1].startswith("input text ")]


def xcrun_falso(pasta: Path) -> Path:
    """`xcrun simctl list devices` com um simulador ligado, para a pre-condicao iOS."""
    caminho = pasta / "xcrun"
    caminho.write_text(
        f"#!{sys.executable}\n"
        "import sys\n"
        f"print('    iPhone 16 QA ({UDID}) (Booted)')\n"
        "sys.exit(0)\n",
        encoding="utf-8",
    )
    caminho.chmod(caminho.stat().st_mode | stat.S_IXUSR)
    return pasta


class WdaFalso:
    """WebDriverAgent minimo: sessao, busca de elemento, clique, digitacao e toque.

    `elementos` mapeia (estrategia, valor) -> (id, rect). `falha_digitacao`
    simula as duas formas de falha que o WDA real produz: "semantica" (HTTP 200
    com `value.error`) e "http" (status de erro).
    """

    def __init__(self) -> None:
        self.elementos: dict[tuple[str, str], tuple[str, dict]] = {}
        self.falha_digitacao: str | None = None
        self.chamadas: list[tuple[str, str, dict | None]] = []
        falso = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def _json(self, payload, status=200):
                corpo = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(corpo)))
                self.end_headers()
                self.wfile.write(corpo)

            def do_GET(self):
                falso.chamadas.append(("GET", self.path, None))
                if self.path == "/status":
                    self._json({"sessionId": "S1", "value": {"ready": True}})
                elif self.path.endswith("/rect"):
                    eid = self.path.split("/")[-2]
                    rect = next((r for i, r in falso.elementos.values() if i == eid), None)
                    self._json({"value": rect} if rect else {"value": {"error": "stale element reference"}},
                               200 if rect else 404)
                else:
                    self._json({"value": None})

            def do_POST(self):
                tamanho = int(self.headers.get("Content-Length", 0) or 0)
                corpo = json.loads(self.rfile.read(tamanho) or b"null") if tamanho else None
                falso.chamadas.append(("POST", self.path, corpo))
                if self.path == "/session":
                    self._json({"sessionId": "S1", "value": {"sessionId": "S1"}})
                elif self.path.endswith("/element"):
                    achado = falso.elementos.get((corpo.get("using"), corpo.get("value")))
                    if achado is None:
                        self._json({"value": {"error": "no such element", "message": "nao achei"}}, 404)
                    else:
                        eid = achado[0]
                        self._json({"value": {"ELEMENT": eid, "element-6066-11e4-a1fd-950276f4fb3a": eid}})
                elif self.path.endswith("/value") or self.path.endswith("/wda/keys"):
                    texto = "".join(corpo.get("value") or []) if isinstance(corpo, dict) else ""
                    if falso.falha_digitacao == "semantica":
                        # O WDA real devolve 200 com o erro dentro de `value`, e a
                        # mensagem pode citar o valor do campo: o motor nao pode repeti-la.
                        self._json({"value": {"error": "invalid element state",
                                              "message": f"Falhou ao digitar {texto}"}})
                    elif falso.falha_digitacao == "http":
                        self._json({"value": {"error": "unknown error", "message": f"erro {texto}"}}, 500)
                    else:
                        self._json({"value": None})
                else:
                    self._json({"value": None})

            def log_message(self, *_args):
                pass

        self._servidor = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self._servidor.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self._servidor.server_address[1]}"

    def fechar(self) -> None:
        self._servidor.shutdown()
        self._servidor.server_close()

    def posts(self, sufixo: str) -> list[dict | None]:
        return [corpo for metodo, rota, corpo in self.chamadas if metodo == "POST" and rota.endswith(sufixo)]

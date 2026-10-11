"""Parser do `CFNETWORK_DIAGNOSTICS` e filtro do filho `ios_device_log`."""

from __future__ import annotations

import itertools

from mobaile.adapters.ios_cfnetwork import BODY_UNAVAILABLE, PENDING_TIMEOUT_S, CFNetworkDiagParser
from mobaile.adapters.ios_device_log import _CFNetworkFilter

REQUEST = """CFNetwork Diagnostics [3:45] 10:20:30.123 {
  Protocol Enqueue: request POST https://api.exemplo.com/v1/login?x=1 HTTP/1.1
         Request:  <CFURLRequest 0x1700f0b80 [0x1b1a3abb8]> {url = https://api.exemplo.com/v1/login?x=1, cs = 0x0}
         Message: POST https://api.exemplo.com/v1/login?x=1 HTTP/1.1
          Accept: */*
    Content-Type: application/json
   Authorization: Bearer segredo123
} [3:45]"""

RESPONSE = """CFNetwork Diagnostics [3:46] 10:20:30.456 {
  Response Received: <CFURLRequest 0x1700f0b80 [0x1b1a3abb8]> {url = https://api.exemplo.com/v1/login?x=1, cs = 0x0}
         Response: <CFURLResponse 0x170226b40 [0x1b1a3abb8]> {url = https://api.exemplo.com/v1/login?x=1}
          { Status Code: 201, Headers {
    "Content-Type" =     (
        "application/json; charset=utf-8"
    );
    Server =     (
        nginx
    );
} }
} [3:46]"""

FAILURE = """CFNetwork Diagnostics [3:47] 10:20:31.000 {
  Did Fail: <CFURLRequest 0x1 [0x2]> {url = https://lento.exemplo.com/, cs = 0x0}
  Error: Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."
} [3:47]"""


def _parser():
    ids = itertools.count(1)
    raw: list[str] = []
    return CFNetworkDiagParser(lambda: next(ids), on_raw_block=raw.append), raw


def test_requisicao_e_resposta_viram_um_evento():
    parser, raw = _parser()
    assert parser.feed(10, REQUEST, now=100.0) == []
    [event] = parser.feed(10, RESPONSE, now=100.25)
    assert event.method == "POST"
    assert event.host == "api.exemplo.com"
    assert event.path == "/v1/login?x=1"
    assert event.status_code == 201
    assert event.status_text == "Created"
    assert event.request_headers["Content-Type"] == "application/json"
    assert event.request_headers["Authorization"] != "Bearer segredo123"
    assert event.response_headers["Content-Type"] == "application/json; charset=utf-8"
    assert event.response_headers["Server"] == "nginx"
    assert event.response_body == BODY_UNAVAILABLE
    assert round(event.duration_ms) == 250
    # O bloco bruto e guardado sem o token.
    assert len(raw) == 2 and "segredo123" not in raw[0]


def test_bloco_quebrado_em_varios_registros():
    parser, _ = _parser()
    for line in REQUEST.splitlines():
        parser.feed(7, line, now=1.0)
    events = []
    for line in RESPONSE.splitlines():
        events += parser.feed(7, line, now=2.0)
    assert [e.status_code for e in events] == [201]


def test_falha_de_rede_vira_evento_com_erro():
    parser, _ = _parser()
    parser.feed(
        1,
        REQUEST.replace("https://api.exemplo.com/v1/login?x=1", "https://lento.exemplo.com/").replace(
            "POST", "GET"
        ),
        now=1.0,
    )
    [event] = parser.feed(1, FAILURE, now=2.0)
    assert event.status_code == 0
    assert "NSURLErrorDomain -1001" in (event.error or "")


def test_resposta_sem_requisicao_e_requisicao_sem_resposta():
    parser, _ = _parser()
    [orphan] = parser.feed(1, RESPONSE, now=1.0)
    assert orphan.method == "?" and orphan.status_code == 201
    parser.feed(1, REQUEST, now=10.0)
    [expired] = parser.expire(10.0 + PENDING_TIMEOUT_S + 1)
    assert expired.status_code == 0 and expired.error


def test_texto_fora_de_bloco_e_ignorado():
    parser, raw = _parser()
    assert parser.feed(1, "GET https://x.com/ HTTP/1.1 qualquer log do app", now=1.0) == []
    assert raw == []


def test_filtro_do_filho_segue_o_bloco_por_pid():
    f = _CFNetworkFilter()
    assert f.keep(1, "CFNetwork Diagnostics [1:2] 10:00:00.000 {")
    assert f.keep(1, "  Message: GET https://x.com/ HTTP/1.1")
    assert not f.keep(2, "outro processo")
    assert f.keep(1, "} [1:2]")
    assert not f.keep(1, "depois do bloco")
    # Bloco inteiro num registro so nao deixa o pid aberto.
    assert f.keep(3, REQUEST)
    assert not f.keep(3, "linha solta")


# ------------------------------------------------- SEC-3: log bruto em disco

TOKEN_NA_URL = """CFNetwork Diagnostics [3:50] 10:20:40.000 {
  Protocol Enqueue: request GET https://api.exemplo.com/v1/conta?access_token=tok987&pagina=2 HTTP/1.1
         Request:  <CFURLRequest 0x1 [0x2]> {url = https://api.exemplo.com/v1/conta?access_token=tok987&pagina=2, cs = 0x0}
         Message: GET https://usuario:senha321@api.exemplo.com/v1/conta?access_token=tok987&pagina=2 HTTP/1.1
          Accept: */*
} [3:50]"""


def test_bloco_bruto_sai_com_a_url_redigida():
    parser, raw = _parser()
    parser.feed(10, TOKEN_NA_URL, now=100.0)
    [bloco] = raw
    assert "tok987" not in bloco
    assert "senha321" not in bloco
    # O que nao e sensivel continua la, para o diagnostico servir.
    assert "pagina=2" in bloco
    assert "api.exemplo.com/v1/conta" in bloco


def test_log_bruto_e_criado_so_para_o_dono(tmp_path, monkeypatch):
    import stat

    from mobaile.adapters import ios_cfnetwork

    caminho = tmp_path / "Logs" / "MoBaile" / "cfnetwork-diagnostics.log"
    monkeypatch.setattr(ios_cfnetwork, "RAW_LOG_PATH", caminho)
    captura = ios_cfnetwork.IOSDebugNetworkCapture(emit=lambda _e: None, next_id=lambda: 1)
    captura._save_raw("bloco")
    assert stat.S_IMODE(caminho.stat().st_mode) == 0o600
    assert stat.S_IMODE(caminho.parent.stat().st_mode) == 0o700
    assert caminho.read_text(encoding="utf-8") == "bloco\n\n"


def test_log_bruto_antigo_aberto_para_todos_fica_so_do_dono(tmp_path, monkeypatch):
    import stat

    from mobaile.adapters import ios_cfnetwork

    caminho = tmp_path / "cfnetwork-diagnostics.log"
    caminho.write_text("antigo\n", encoding="utf-8")
    caminho.chmod(0o644)
    monkeypatch.setattr(ios_cfnetwork, "RAW_LOG_PATH", caminho)
    captura = ios_cfnetwork.IOSDebugNetworkCapture(emit=lambda _e: None, next_id=lambda: 1)
    captura._save_raw("novo")
    assert stat.S_IMODE(caminho.stat().st_mode) == 0o600
    assert caminho.read_text(encoding="utf-8") == "antigo\nnovo\n\n"

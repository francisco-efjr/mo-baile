"""O harness usa ferramentas falsas mesmo com configuração local exportada."""

import os
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from qa.engine_client import Motor


def test_nao_herda_endpoints_e_adb_reais(monkeypatch):
    monkeypatch.setenv("ADB_PATH", "/sdk/adb-real")
    monkeypatch.setenv("WDA_URL", "http://device.example.com:8100")
    monkeypatch.setenv("APPIUM_URL", "http://device.example.com:4723")
    monkeypatch.setenv("PROXY_HOST", "0.0.0.0")
    monkeypatch.setenv("MOBAILE_REDACT", "0")
    monkeypatch.setenv("QA_ANIMADO", "1")
    monkeypatch.setenv("QA_CAPTURE_DELAY_MS", "700")
    with patch("qa.engine_client.subprocess.Popen", return_value=SimpleNamespace(stdout=[], stderr=[])) as popen:
        Motor()

    env = popen.call_args.kwargs["env"]
    assert Path(env["ADB_PATH"]) == Path(__file__).resolve().parents[1] / "fakebin" / "adb"
    assert env["WDA_URL"] == "http://127.0.0.1:0"
    assert env["APPIUM_URL"] == "http://127.0.0.1:0"
    assert env["PROXY_HOST"] == "127.0.0.1"
    assert env["MOBAILE_REDACT"] == "1"
    assert env["QA_ANIMADO"] == "0"
    assert env["QA_CAPTURE_DELAY_MS"] == "0"
    assert Path(env["PATH"].split(os.pathsep)[1]) == Path(sys.executable).parent


def test_aceita_endpoint_local_fornecido_pelo_cenario():
    with patch("qa.engine_client.subprocess.Popen", return_value=SimpleNamespace(stdout=[], stderr=[])) as popen:
        Motor(ios=True, extra_env={"WDA_URL": "http://127.0.0.1:34567"})

    env = popen.call_args.kwargs["env"]
    assert env["WDA_URL"] == "http://127.0.0.1:34567"
    assert env["QA_IOS"] == "1"

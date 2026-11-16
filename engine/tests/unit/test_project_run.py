"""Execução do `main` do dono (B1-3): resumo do behave, máscara, parada, vídeo.

Os processos aqui são scripts pequenos rodados pelo Python da suíte: o que se
confere é o comportamento do `ProjectRun`, não o behave (esse fica no teste de
integração, em `tests/contract/test_run_rpc.py`).
"""

from __future__ import annotations

import json
import os
import pathlib
import sys
import textwrap
import time

import pytest

from mobaile.domain.models import Platform
from mobaile.services import project_run
from mobaile.services.project_run import BehaveSummary, NoVideo, ProjectRun, RecorderVideo, ScrcpyVideo

RESUMO_OK = [
    "1 feature passed, 0 failed, 0 skipped",
    "2 scenarios passed, 0 failed, 0 skipped",
    "6 steps passed, 0 failed, 0 skipped, 0 undefined",
]
RESUMO_FALHA = [
    "0 features passed, 1 failed, 0 skipped",
    "0 scenarios passed, 1 failed, 0 skipped",
    "2 steps passed, 1 failed, 0 skipped, 0 undefined",
]


class TestResumoDoBehave:
    def test_soma_varias_chamadas_e_passa(self):
        resumo = BehaveSummary()
        for linha in [*RESUMO_OK, "Took 0m0.3s", *RESUMO_OK]:
            resumo.feed(linha)
        assert resumo.status() == "passed"
        contagem = resumo.counts()
        assert contagem["summaries"] == 2
        assert contagem["scenarios"]["passed"] == 4
        assert contagem["steps"]["passed"] == 12

    def test_uma_falha_em_qualquer_chamada_falha(self):
        resumo = BehaveSummary()
        for linha in [*RESUMO_OK, *RESUMO_FALHA, *RESUMO_OK]:
            resumo.feed(linha)
        assert resumo.status() == "failed"
        assert resumo.counts()["scenarios"] == {
            "passed": 4, "failed": 1, "skipped": 0, "undefined": 0, "errors": 0, "untested": 0,
        }

    def test_step_indefinido_falha(self):
        resumo = BehaveSummary()
        for linha in ["1 feature passed, 0 failed, 0 skipped", "1 scenario passed, 0 failed, 0 skipped",
                      "2 steps passed, 0 failed, 0 skipped, 1 undefined"]:
            resumo.feed(linha)
        assert resumo.status() == "failed"

    def test_formato_do_behave_1_3_com_error(self):
        resumo = BehaveSummary()
        for linha in ["1 feature passed, 0 failed, 1 error, 0 skipped",
                      "1 scenario passed, 0 failed, 1 error, 0 skipped",
                      "3 steps passed, 0 failed, 1 error, 0 skipped, 0 undefined"]:
            resumo.feed(linha)
        assert resumo.status() == "failed"
        assert resumo.counts()["scenarios"]["errors"] == 1

    def test_sem_resumo_e_indeterminado(self):
        resumo = BehaveSummary()
        resumo.feed("RuntimeError: nao abriu a sessao")
        assert resumo.status() == "indeterminate"
        assert resumo.counts() is None

    def test_texto_parecido_no_meio_da_linha_nao_conta(self):
        resumo = BehaveSummary()
        resumo.feed("print: o log diz 3 scenarios passed, 0 failed")
        assert not resumo.found


# ---------------------------------------------------------------- execução


def _script(tmp_path, corpo: str) -> pathlib.Path:
    arquivo = tmp_path / "main.py"
    arquivo.write_text(textwrap.dedent(corpo), encoding="utf-8")
    return arquivo


def _rodar(tmp_path, corpo, *, masks=(), expected_runs=0, video=None, esperar=True, env=None):
    entrada = _script(tmp_path, corpo)
    pasta = tmp_path / "execucao"
    pasta.mkdir()
    linhas: list[str] = []
    fim: list[dict] = []
    execucao = ProjectRun(
        run_id="r1", project={"id": "abc", "name": "exemplo", "root": str(tmp_path)},
        command=[sys.executable, str(entrada)], cwd=tmp_path,
        env={**os.environ, "PYTHONUNBUFFERED": "1", **(env or {})}, folder=pasta, masks=list(masks),
        video=video, on_line=lambda rid, linha: linhas.append(linha), on_finished=fim.append,
        expected_runs=expected_runs, device_id=None, platform="android", config_name="config_x",
    )
    execucao.start()
    if esperar:
        assert execucao.wait(30), "a execucao nao terminou"
    return execucao, linhas, fim, pasta


class TestExecucao:
    def test_console_ao_vivo_pasta_e_resumo(self, tmp_path):
        corpo = "print('ola')\n" + "".join(f"print({linha!r})\n" for linha in RESUMO_OK)
        execucao, linhas, fim, pasta = _rodar(tmp_path, corpo)
        assert "ola" in linhas
        assert linhas[0].startswith("[Mo baile] Rodando")
        [resultado] = fim
        assert resultado["status"] == "passed"
        assert resultado["exit_code"] == 0
        assert resultado["folder"] == str(pasta)
        assert resultado["counts"]["scenarios"]["passed"] == 2
        assert set(resultado) == {"run_id", "status", "counts", "exit_code", "folder", "video", "video_warning",
                                  "message", "duration_s"}
        assert "ola" in (pasta / "console.log").read_text(encoding="utf-8")
        resumo = json.loads((pasta / "resumo.json").read_text(encoding="utf-8"))
        assert resumo["status"] == "passed"
        assert resumo["config"] == "config_x"
        assert oct((pasta / "console.log").stat().st_mode & 0o777) == "0o600"
        assert not execucao.active

    def test_codigo_de_saida_nao_decide(self, tmp_path):
        """O main do dono engole a exceção: sai 0 com cenário falho, e pode sair 1 com tudo passando."""
        corpo = "".join(f"print({linha!r})\n" for linha in RESUMO_FALHA)
        _, _, fim, _ = _rodar(tmp_path, corpo)
        assert fim[0]["status"] == "failed"
        assert fim[0]["exit_code"] == 0
        (tmp_path / "execucao").rename(tmp_path / "execucao-1")
        corpo = "import sys\n" + "".join(f"print({linha!r})\n" for linha in RESUMO_OK) + "sys.exit(1)\n"
        _, _, fim, _ = _rodar(tmp_path, corpo)
        assert fim[0]["status"] == "passed"
        assert fim[0]["exit_code"] == 1

    def test_sem_resumo_e_indeterminado_com_a_ultima_linha_de_erro(self, tmp_path):
        corpo = "raise RuntimeError('Nao foi possivel abrir a sessao do Appium')\n"
        _, _, fim, _ = _rodar(tmp_path, corpo)
        assert fim[0]["status"] == "indeterminate"
        assert "Nao foi possivel abrir a sessao do Appium" in fim[0]["message"]
        assert fim[0]["counts"] is None

    def test_menos_resumos_que_execucoes_do_main_e_indeterminado(self, tmp_path):
        corpo = "".join(f"print({linha!r})\n" for linha in RESUMO_OK) + "print('NameError: test_suite_x')\n"
        _, _, fim, _ = _rodar(tmp_path, corpo, expected_runs=3)
        assert fim[0]["status"] == "indeterminate"
        assert "3 vezes" in fim[0]["message"]

    def test_mascara_nas_linhas_no_console_e_no_resumo(self, tmp_path):
        corpo = "print('config: {\"accessKey\": \"FAKE-KEY-0000\"}')\nraise SystemExit('chave FAKE-KEY-0000')\n"
        _, linhas, fim, pasta = _rodar(tmp_path, corpo, masks=["FAKE-KEY-0000"])
        tudo = "\n".join(linhas) + json.dumps(fim) + (pasta / "console.log").read_text(encoding="utf-8")
        tudo += (pasta / "resumo.json").read_text(encoding="utf-8")
        assert "FAKE-KEY-0000" not in tudo
        assert "***" in "\n".join(linhas)

    def test_cores_ansi_saem_e_linha_longa_e_cortada(self, tmp_path):
        corpo = "print('\\x1b[32mverde\\x1b[0m')\nprint('x' * 9000)\n"
        _, linhas, _, _ = _rodar(tmp_path, corpo)
        assert "verde" in linhas
        longa = next(linha for linha in linhas if linha.startswith("xxx"))
        assert len(longa) == project_run.MAX_LINE_CHARS + 1

    def test_parar_encerra_o_processo_e_os_netos(self, tmp_path):
        corpo = """
            import subprocess, sys, time
            neto = subprocess.Popen(["sleep", "60"])
            print(f"NETO={neto.pid}", flush=True)
            time.sleep(60)
        """
        execucao, linhas, fim, _ = _rodar(tmp_path, corpo, esperar=False)
        limite = time.monotonic() + 10
        while not any(linha.startswith("NETO=") for linha in linhas) and time.monotonic() < limite:
            time.sleep(0.05)
        neto = int(next(linha for linha in linhas if linha.startswith("NETO="))[5:])
        inicio = time.monotonic()
        assert execucao.stop() is True
        assert execucao.wait(15)
        assert time.monotonic() - inicio < 12
        assert fim[0]["status"] == "cancelled"
        limite = time.monotonic() + 5
        while time.monotonic() < limite:
            try:
                os.kill(neto, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            pytest.fail(f"o neto {neto} continuou vivo depois do run.stop")
        assert execucao.stop() is False

    def test_neto_que_segura_a_saida_nao_trava_o_fim(self, tmp_path, monkeypatch):
        monkeypatch.setattr(project_run, "DRAIN_AFTER_EXIT_S", 0.5)
        corpo = """
            import subprocess
            neto = subprocess.Popen(["sleep", "30"])
            print(f"NETO={neto.pid}", flush=True)
        """
        inicio = time.monotonic()
        _, linhas, fim, _ = _rodar(tmp_path, corpo)
        assert time.monotonic() - inicio < 10
        assert fim[0]["status"] == "indeterminate"
        assert any("seguravam a saída" in linha for linha in linhas)

    def test_parar_enquanto_o_video_sobe_nao_deixa_o_processo_rodar(self, tmp_path):
        """`run.stop` entre o `run.start` e o processo: a execução já conta como ativa e para."""
        caixa = {}

        class VideoQuePara:
            mode = "scrcpy"
            warning = None

            def start(self):
                assert caixa["execucao"].active
                assert caixa["execucao"].stop() is True

            def stop(self):
                return None

        entrada = _script(tmp_path, "import time\ntime.sleep(60)\n")
        pasta = tmp_path / "execucao"
        pasta.mkdir()
        fim = []
        execucao = ProjectRun(
            run_id="r", project={"id": "a", "name": "x"}, command=[sys.executable, str(entrada)], cwd=tmp_path,
            env=dict(os.environ), folder=pasta, masks=[], video=VideoQuePara(),
            on_line=lambda *_: None, on_finished=fim.append,
        )
        caixa["execucao"] = execucao
        inicio = time.monotonic()
        execucao.start()
        assert execucao.wait(15)
        assert time.monotonic() - inicio < 12
        assert fim[0]["status"] == "cancelled"

    def test_interpretador_que_nao_existe_vira_erro_na_hora(self, tmp_path):
        from mobaile.domain.errors import EngineError

        pasta = tmp_path / "execucao"
        pasta.mkdir()
        execucao = ProjectRun(
            run_id="r", project={"id": "a", "name": "x"}, command=[str(tmp_path / "nao-existe"), "main.py"],
            cwd=tmp_path, env=dict(os.environ), folder=pasta, masks=[], video=None,
            on_line=lambda *_: None, on_finished=lambda _: None,
        )
        with pytest.raises(EngineError):
            execucao.start()
        assert not execucao.active

    def test_video_e_parado_no_fim_e_aviso_vai_no_resultado(self, tmp_path):
        class VideoFalso:
            mode = "scrcpy"
            warning = None

            def __init__(self):
                self.eventos = []

            def start(self):
                self.eventos.append("start")

            def stop(self):
                self.eventos.append("stop")
                alvo = tmp_path / "execucao" / "video.mp4"
                alvo.write_bytes(b"mp4")
                return alvo

        video = VideoFalso()
        _, _, fim, pasta = _rodar(tmp_path, "print('x')\n", video=video)
        assert video.eventos == ["start", "stop"]
        assert fim[0]["video"] == str(pasta / "video.mp4")

        (tmp_path / "execucao").rename(tmp_path / "execucao-1")
        _, linhas, fim, _ = _rodar(tmp_path, "print('x')\n", video=NoVideo("Sem aparelho alvo."))
        assert fim[0]["video"] is None
        assert fim[0]["video_warning"] == "Sem aparelho alvo."
        assert "[Mo baile] Sem aparelho alvo." in linhas


# ---------------------------------------------------------------- vídeo e pasta


class TestEscolhaDoVideo:
    def _escolher(self, tmp_path, **kw):
        padrao = {"platform": Platform.ANDROID, "device_id": "emulator-5554", "folder": tmp_path,
                  "scrcpy_path": "/usr/local/bin/scrcpy", "recorder_factory": lambda pasta: object(),
                  "booted_simulators": lambda: [("SIM-1", "iPhone 16")]}
        padrao.update(kw)
        return project_run.make_video(**padrao)

    def test_android_com_scrcpy_grava_sem_janela_e_sem_audio(self, tmp_path):
        video = self._escolher(tmp_path)
        assert isinstance(video, ScrcpyVideo)
        assert video.command() == ["/usr/local/bin/scrcpy", "-s", "emulator-5554", "--no-playback", "--no-window",
                                   "--no-audio", f"--record={tmp_path / 'video.mp4'}"]

    def test_android_sem_scrcpy_cai_no_screenrecord_com_aviso(self, tmp_path):
        video = self._escolher(tmp_path, scrcpy_path=None)
        assert isinstance(video, RecorderVideo)
        assert video.mode == "screenrecord"
        assert "180 s" in video.warning

    def test_simulador_ios_usa_simctl_e_iphone_fisico_fica_sem_video(self, tmp_path):
        video = self._escolher(tmp_path, platform=Platform.IOS, device_id="SIM-1")
        assert isinstance(video, RecorderVideo)
        assert video.mode == "simctl"
        fisico = self._escolher(tmp_path, platform=Platform.IOS, device_id="00008110-001A2B3C4D5E")
        assert isinstance(fisico, NoVideo)
        assert "iPhone físico" in fisico.warning

    def test_sem_aparelho_fica_sem_video(self, tmp_path):
        assert isinstance(self._escolher(tmp_path, device_id=None), NoVideo)

    def test_recorder_video_move_o_arquivo_para_video_mp4(self, tmp_path):
        gravado = tmp_path / "mobaile-android-x.mp4"

        class Gravador:
            def start(self, platform, device_id):
                gravado.write_bytes(b"mp4")

            def stop(self):
                return {"path": str(gravado)}

        video = RecorderVideo(Gravador(), Platform.ANDROID, "emulator-5554", tmp_path / "video.mp4", "screenrecord")
        video.start()
        assert video.stop() == tmp_path / "video.mp4"
        assert (tmp_path / "video.mp4").read_bytes() == b"mp4"
        assert not gravado.exists()


class TestPasta:
    def test_raiz_vem_do_ambiente_e_o_padrao_e_documents(self, monkeypatch, tmp_path):
        monkeypatch.setenv("MOBAILE_RUNS_DIR", str(tmp_path))
        assert project_run.runs_dir() == tmp_path
        monkeypatch.delenv("MOBAILE_RUNS_DIR")
        assert project_run.runs_dir() == pathlib.Path.home() / "Documents" / "Mo baile" / "Execuções"

    def test_pasta_nova_por_execucao_mesmo_no_mesmo_segundo(self, tmp_path):
        primeira = project_run.new_run_folder(tmp_path, "projeto_exemplo_behave", 1757030000.0)
        segunda = project_run.new_run_folder(tmp_path, "projeto_exemplo_behave", 1757030000.0)
        assert primeira != segunda
        assert primeira.parent == segunda.parent == tmp_path / "projeto-exemplo-behave"
        assert segunda.name == primeira.name + "-2"

"""O gate de QA precisa recusar sucesso sem verificações executadas."""

import pytest

from qa import run_all


def configurar_fluxos(monkeypatch, tmp_path, scripts):
    fluxos = []
    for indice, codigo in enumerate(scripts, start=1):
        nome = f"fluxo{indice}.py"
        (tmp_path / nome).write_text(codigo, encoding="utf-8")
        fluxos.append((f"Fluxo {indice}", nome))
    monkeypatch.setattr(run_all, "AQUI", tmp_path)
    monkeypatch.setattr(run_all, "FLUXOS", fluxos)


@pytest.mark.parametrize("saida", [
    "nenhuma verificação executada",
    "RESULTADO: 0 passaram, 0 falharam",
    "RESULTADO: 3 passaram, 1 falharam",
    "RESULTADO: incompleto",
    "RESULTADO: 1 passaram, 0 falharam\nRESULTADO: 0 passaram, 2 falharam",
])
def test_rejeita_exit_zero_sem_evidencia_de_sucesso(monkeypatch, tmp_path, capsys, saida):
    configurar_fluxos(monkeypatch, tmp_path, [f"print({saida!r})"])

    assert run_all.main() == 1
    assert "[FALHA]" in capsys.readouterr().out


def test_aceita_verificacoes_executadas_sem_falhas(monkeypatch, tmp_path, capsys):
    configurar_fluxos(monkeypatch, tmp_path, ["print('RESULTADO: 19 passaram, 0 falharam')"])

    assert run_all.main() == 0
    assert "[OK  ]" in capsys.readouterr().out


def test_falha_preserva_diagnostico_de_stderr(monkeypatch, tmp_path, capsys):
    configurar_fluxos(monkeypatch, tmp_path, [
        "import sys\nprint('origem indisponível', file=sys.stderr)\nsys.exit(2)",
    ])

    assert run_all.main() == 1
    assert "origem indisponível" in capsys.readouterr().out


def test_fluxo_travado_falha_sem_impedir_fluxo_seguinte(monkeypatch, tmp_path, capsys):
    configurar_fluxos(monkeypatch, tmp_path, [
        "import time\nprint('aguardando WDA', flush=True)\ntime.sleep(60)",
        "print('RESULTADO: 1 passaram, 0 falharam')",
    ])
    monkeypatch.setattr(run_all, "TIMEOUT_FLUXO", 0.2, raising=False)

    assert run_all.main() == 1
    saida = capsys.readouterr().out
    assert "aguardando WDA" in saida
    assert "timeout" in saida.lower()
    assert "[OK  ] Fluxo 2" in saida


def test_exit_nao_zero_prevalece_sobre_resumo_verde(monkeypatch, tmp_path, capsys):
    configurar_fluxos(monkeypatch, tmp_path, [
        "import sys\nprint('RESULTADO: 1 passaram, 0 falharam')\nsys.exit(1)",
    ])

    assert run_all.main() == 1
    assert "[FALHA]" in capsys.readouterr().out

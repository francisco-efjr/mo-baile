"""Configuração comum das suítes do motor.

Os recentes da tela Início são gravados em disco a cada Page Object salvo,
auditoria ou flow exportado. Nos testes, isso vai para uma pasta temporária,
e nunca para `~/Library/Application Support/Mo baile` de quem roda a suíte.
"""

from __future__ import annotations

import os
import tempfile

import pytest


@pytest.fixture(autouse=True, scope="session")
def _pasta_de_dados_temporaria():
    anterior = os.environ.get("MOBAILE_DATA_DIR")
    with tempfile.TemporaryDirectory(prefix="mobaile-dados-") as pasta:
        os.environ["MOBAILE_DATA_DIR"] = pasta
        yield pasta
    if anterior is None:
        os.environ.pop("MOBAILE_DATA_DIR", None)
    else:
        os.environ["MOBAILE_DATA_DIR"] = anterior

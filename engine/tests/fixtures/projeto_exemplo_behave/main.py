"""Ponto de entrada do projeto de exemplo, no formato do `main` do dono.

Rodado como run configuration "Python" no PyCharm (`main.py`, sem argumentos).
A config ativa e a linha `init(...)` sem comentario; as outras ficam
comentadas para trocar de ambiente na mao.
"""

from configs import (  # noqa: F401 (as alternativas ficam comentadas no main)
    config_android_local_HLG,
    config_ios_local_HLG,
    config_kobiton_android_HLG,
    config_kobiton_ios_HLG,
)
from core.runner import executar, finish, init


def main_sem_args():
    init(config_android_local_HLG)
    # init(config_ios_local_HLG)
    # init(config_kobiton_android_HLG)
    # init(config_kobiton_ios_HLG)

    try:
        test_suite_time_01()
        test_suite_time_02()
        test_suite_time_03()
    except Exception as e:
        print(e)
    finally:
        finish()


# Definições de TestSuits
def test_suite_canais():
    executar(squad='canais', feature='canais/canais.feature')


def test_suite_time_01():
    executar(squad='time_01', feature='teste/teste.feature')


def test_suite_time_02():
    executar(squad='time_02', feature='login/login.feature')


def test_suite_time_03():
    executar(squad='time_03', feature='teste/teste.feature')


if __name__ == "__main__":
    main_sem_args()

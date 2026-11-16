"""`init`, `executar` e `finish` do projeto de exemplo.

Suposicao documentada (estudo, H2): `executar` chama o behave **no mesmo
processo**, por `behave.__main__.main([...])`. E o caso mais provavel no
projeto do dono e o que o Mo baile precisa entender: o resultado nao sai do
codigo de saida (o `main` engole a excecao com `print(e)`), e sim do resumo
que o behave imprime no fim de cada chamada.

Nada aqui fala com Appium: os steps so imprimem e dormem pouco. Duas
variaveis de ambiente deixam o teste escolher o desfecho:

- `EXEMPLO_FALHAR_INIT=1`: o `init` lanca antes de qualquer cenario;
- `EXEMPLO_CENARIO_FALHA=1`: um step do login falha;
- `EXEMPLO_IMPRIMIR_CONFIG=1`: o `init` imprime a config inteira, como um
  projeto descuidado faria (o Mo baile tem de mascarar os segredos);
- `EXEMPLO_DORMIR=<s>`: cada step dorme esse tempo (teste de parada).
"""

import os

from behave.__main__ import main as behave_main

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_config = {}


def init(config):
    if os.environ.get("EXEMPLO_FALHAR_INIT") == "1":
        raise RuntimeError("Nao foi possivel abrir a sessao do Appium (simulado pelo exemplo).")
    _config.clear()
    _config.update(config)
    if os.environ.get("EXEMPLO_IMPRIMIR_CONFIG") == "1":
        print(f"[init] config completa: {config}", flush=True)
    print(f"[init] plataforma={config.get('platformName')} aparelho={config.get('appium:deviceName')}", flush=True)


def executar(squad, feature):
    caminho = os.path.join(BASE, "features", feature)
    print(f"[executar] squad={squad} feature={feature}", flush=True)
    return behave_main(["--no-capture", "--no-color", caminho])


def finish():
    print("[finish] sessao encerrada", flush=True)

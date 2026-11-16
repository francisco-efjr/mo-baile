import os
import time

from behave import given, then, when


def _dormir():
    time.sleep(float(os.environ.get("EXEMPLO_DORMIR", "0.05")))


@given("que o app de exemplo esta aberto")
def passo_app_aberto(context):
    _dormir()
    print("app aberto", flush=True)


@when('eu toco em "{botao}"')
def passo_tocar(context, botao):
    _dormir()
    print(f"toquei em {botao}", flush=True)


@then('vejo a tela "{tela}"')
def passo_ver_tela(context, tela):
    _dormir()
    print(f"tela {tela} visivel", flush=True)


@then("o login responde conforme o ambiente")
def passo_login(context):
    _dormir()
    if os.environ.get("EXEMPLO_CENARIO_FALHA") == "1":
        raise AssertionError("A tela de login nao apareceu (falha simulada pelo exemplo).")
    print("login ok", flush=True)

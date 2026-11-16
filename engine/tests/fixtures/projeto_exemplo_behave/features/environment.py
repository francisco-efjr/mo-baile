import os


def before_scenario(context, scenario):
    print(f"[hook] antes de: {scenario.name}", flush=True)


def after_all(context):
    # `EXEMPLO_FALHAR_AFTER_ALL=1`: o encerramento falha depois de todos os
    # cenários passarem, como um `driver.quit()` que lança. O behave ainda
    # escreve "passed" no resumo, mas sai com falha (revisão CR-01).
    if os.environ.get("EXEMPLO_FALHAR_AFTER_ALL") == "1":
        raise RuntimeError("driver.quit falhou (simulado pelo exemplo)")

"""Mo baile Engine — núcleo headless de inspeção, automação e interceptação mobile.

Camadas (dependências apontam sempre para dentro):

    domain/     modelos e erros puros, sem I/O
    ports/      protocolos que o domínio espera das bordas
    adapters/   implementações concretas (adb, WDA, proxy, scrcpy, logcat)
    services/   casos de uso que compõem adapters
    security/   validação, escaping e redação de dados sensíveis
    rpc/        fronteira JSON-RPC consumida pelo front SwiftUI

Nada aqui importa Tkinter, SwiftUI ou qualquer camada de apresentação.
"""

import sys as _sys

__version__ = "3.10.0"

# Subido com `python3 -S` pelo app nativo: as bibliotecas entram sem os `.pth`
# (ver `_site`), antes de qualquer módulo do motor importar Pillow.
if _sys.flags.no_site:
    from mobaile._site import add_site_packages

    add_site_packages()

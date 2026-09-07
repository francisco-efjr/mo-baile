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

__version__ = "2.0.0"

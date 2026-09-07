"""Interface Tkinter do Mo baile (camada de transicao).

Esta e a UI que esta em producao hoje. A direcao do projeto e substitui-la pelo
front SwiftUI em `apps/MoBaile`, que conversa com o mesmo motor pela fronteira
JSON-RPC. Enquanto a substituicao nao termina, esta camada continua funcionando
e importando o motor por `mobaile.*`, exatamente como o front nativo fara.

Regra para mudancas aqui: logica nova vai para o motor, nao para o widget.
"""

__version__ = "2.0.0"

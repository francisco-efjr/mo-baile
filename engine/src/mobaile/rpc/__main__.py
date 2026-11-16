"""Ponto de entrada: `python3 -m mobaile.rpc`.

O front SwiftUI sobe este processo e conversa por stdin/stdout.
"""

from mobaile.rpc.server import serve

if __name__ == "__main__":
    serve()

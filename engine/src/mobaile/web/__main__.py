"""`python -m mobaile.web` (ou `mobaile-web`): Relatório e Analytics no navegador.

Roda em Windows, Linux e macOS com Python 3.10+ e as dependências do motor
(Pillow e requests). Não chama `configure_logging` do motor: ele usa
`O_NOFOLLOW` e `fchmod`, que não existem no Windows.
"""

from __future__ import annotations

import argparse
import logging
import signal
import sys
import webbrowser

from mobaile.web.server import LOOPBACK, WebServer


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="mobaile-web",
        description="Relatório e Analytics do Mo baile no navegador, só nesta máquina.",
    )
    parser.add_argument("--host", default="127.0.0.1",
                        help="127.0.0.1 (padrão), ::1 ou localhost. Outro endereço é recusado.")
    parser.add_argument("--port", type=int, default=0, help="Porta; 0 escolhe uma livre (padrão).")
    parser.add_argument("--no-browser", action="store_true", help="Não abre o navegador; só mostra o endereço.")
    args = parser.parse_args(argv)
    if args.host not in LOOPBACK:
        parser.error(f"--host {args.host!r} recusado: o servidor só escuta nesta máquina "
                     "(127.0.0.1, ::1 ou localhost).")
    if not 0 <= args.port <= 65535:
        parser.error("--port precisa estar entre 0 e 65535.")
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    try:
        server = WebServer(args.host, args.port)
    except OSError as exc:
        parser.exit(1, f"Não foi possível abrir a porta {args.port}: {exc.strerror or exc}\n")
    # SIGTERM vira saída normal, para o `finally` apagar a pasta da sessão.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    print("Mo baile no navegador. Produto em desenvolvimento: pode conter bugs.")
    print(f"Abra: {server.url}")
    print("O endereço leva a chave desta sessão: não compartilhe. Ctrl+C encerra.", flush=True)
    if not args.no_browser:
        webbrowser.open(server.url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nEncerrado.")
    finally:
        server.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

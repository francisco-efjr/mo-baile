#!/usr/bin/env python3
"""Roda os quatro fluxos de QA e resume o resultado.

    python3 qa/run_all.py

O harness sobe o motor de verdade como subprocesso e fala o mesmo JSON-RPC que
o front SwiftUI fala, com `adb`, `xcrun` e WebDriverAgent falsos no PATH. Ou
seja, o que passa aqui é o que a interface vai ver.
"""
import subprocess
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
FLUXOS = [
    ("1 · sem dispositivo", "qa_fluxo1.py"),
    ("2 · só iOS", "qa_fluxo2.py"),
    ("3 · só Android", "qa_fluxo3.py"),
    ("4 · HTTPS", "qa_fluxo4.py"),
]


def main() -> int:
    resumo, falhou = [], False
    for titulo, script in FLUXOS:
        proc = subprocess.run(
            [sys.executable, script], cwd=AQUI, capture_output=True, text=True, check=False
        )
        linha = next(
            (ln.strip() for ln in proc.stdout.splitlines() if "RESULTADO:" in ln),
            "sem resultado",
        )
        if proc.returncode != 0:
            falhou = True
            print(proc.stdout[-3000:])
        resumo.append((titulo, linha, proc.returncode == 0))

    print("\n" + "=" * 70)
    print("RESUMO DO QA")
    print("=" * 70)
    for titulo, linha, ok in resumo:
        print(f"  [{'OK  ' if ok else 'FALHA'}] {titulo:<24} {linha}")
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())

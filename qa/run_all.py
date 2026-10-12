#!/usr/bin/env python3
"""Roda os fluxos de QA e resume o resultado.

    python3 qa/run_all.py

O harness sobe o motor de verdade como subprocesso e fala o mesmo JSON-RPC que
o front SwiftUI fala, com `adb`, `xcrun` e WebDriverAgent falsos no PATH. Ou
seja, o que passa aqui é o que a interface vai ver.
"""
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
FLUXOS = [
    ("1 · sem dispositivo", "qa_fluxo1.py"),
    ("2 · só iOS", "qa_fluxo2.py"),
    ("3 · só Android", "qa_fluxo3.py"),
    ("4 · HTTPS", "qa_fluxo4.py"),
    ("5 · relatório", "qa_fluxo5.py"),
]
TIMEOUT_FLUXO = 120
RESULTADO = re.compile(r"^\s*RESULTADO: (\d+) passaram, (\d+) falharam\s*$", re.MULTILINE)


def _diagnostico(titulo, stdout, stderr):
    print(f"\nFalha em {titulo}")
    for canal, conteudo in (("stdout", stdout), ("stderr", stderr)):
        if conteudo:
            if isinstance(conteudo, bytes):
                conteudo = conteudo.decode("utf-8", errors="replace")
            print(f"  {canal}:\n{conteudo[-3000:]}")


def main() -> int:
    resumo, falhou = [], False
    for titulo, script in FLUXOS:
        try:
            with subprocess.Popen(
                [sys.executable, script], cwd=AQUI, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True,
                start_new_session=True,
            ) as proc:
                try:
                    stdout, stderr = proc.communicate(timeout=TIMEOUT_FLUXO)
                except subprocess.TimeoutExpired:
                    # O motor é subprocesso do fluxo: encerre o grupo inteiro
                    # para não deixar processos nem portas ocupadas após timeout.
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    stdout, stderr = proc.communicate()
                    falhou = True
                    _diagnostico(titulo, stdout, stderr)
                    resumo.append((titulo, f"timeout após {TIMEOUT_FLUXO}s", False))
                    continue
        except OSError as exc:
            falhou = True
            resumo.append((titulo, f"não executado: {exc}", False))
            continue

        resultados = list(RESULTADO.finditer(stdout))
        valido = len(resultados) == 1
        linha = resultados[0].group().strip() if valido else "resumo ausente ou inválido"
        ok = (
            proc.returncode == 0 and valido
            and int(resultados[0][1]) > 0 and int(resultados[0][2]) == 0
        )
        if not ok:
            falhou = True
            _diagnostico(titulo, stdout, stderr)
        resumo.append((titulo, linha, ok))

    print("\n" + "=" * 70)
    print("RESUMO DO QA")
    print("=" * 70)
    for titulo, linha, ok in resumo:
        print(f"  [{'OK  ' if ok else 'FALHA'}] {titulo:<24} {linha}")
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())

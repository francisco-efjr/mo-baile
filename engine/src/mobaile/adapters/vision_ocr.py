"""OCR local com o framework Vision do macOS: sem LLM, sem rede e sem custo.

Portado do `tag_audit` (importers/vision_ocr). O código Swift fica embutido
aqui; na primeira vez ele é compilado com ``swiftc`` e o binário fica num cache
privado do usuário (0700), reaproveitado depois. Compilar leva de 20 a 60
segundos, por isso ``report.import`` tem prazo longo e emite progresso. Sem
``swiftc``, cai para ``swift <script>``, que é mais lento mas funciona.

Saída por linha de texto: texto, caixa normalizada (x, y a partir do topo, w,
h; de 0 a 1) e confiança, já como `OcrLine` do domínio.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import platform
import shutil
import stat
import subprocess
from collections.abc import Sequence
from pathlib import Path

from mobaile.domain.errors import AdapterError, ToolNotFoundError
from mobaile.domain.report import OcrLine

logger = logging.getLogger(__name__)

SWIFT_SOURCE = r"""
import Foundation
import Vision
import AppKit

var out: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    var lines: [[String: Any]] = []
    var failure: String? = nil
    if let img = NSImage(contentsOf: URL(fileURLWithPath: path)),
       let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["pt-BR", "en-US"]
        req.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            for o in (req.results ?? []) {
                guard let c = o.topCandidates(1).first else { continue }
                let b = o.boundingBox
                lines.append(["t": c.string, "x": b.minX, "y": 1 - b.maxY, "w": b.width, "h": b.height,
                              "c": c.confidence])
            }
        } catch let e { failure = "\(e)" }
    } else { failure = "imagem ilegível" }
    var item: [String: Any] = ["file": path, "lines": lines]
    if let f = failure { item["error"] = f }
    out.append(item)
}
let data = try! JSONSerialization.data(withJSONObject: out, options: [])
FileHandle.standardOutput.write(data)
"""

INSTALL_HINT = "Instale as Command Line Tools do Xcode: xcode-select --install"
# Por lote de imagens. Um print de card leva menos de um segundo no Vision.
BATCH = 25
BATCH_TIMEOUT_S = 300
COMPILE_TIMEOUT_S = 240


def cache_dir() -> Path:
    """Pasta do binário compilado, privada do usuário (0700)."""
    base = Path.home() / "Library" / "Caches" / "Mo baile" / "ocr"
    base.mkdir(parents=True, exist_ok=True, mode=0o700)
    if stat.S_IMODE(base.stat().st_mode) != 0o700:
        base.chmod(0o700)
    return base


class VisionOCR:
    """Lê o texto de imagens com o Vision. Só existe no macOS."""

    def __init__(self, cache: Path | None = None) -> None:
        self._cache = cache
        self._command: list[str] | None = None

    @staticmethod
    def is_available() -> bool:
        return platform.system() == "Darwin" and bool(shutil.which("swiftc") or shutil.which("swift"))

    def _runner(self) -> list[str]:
        """Comando que roda o OCR, compilando o binário na primeira vez."""
        if self._command:
            return self._command
        if platform.system() != "Darwin":
            raise ToolNotFoundError("O OCR de prints usa o Vision e só funciona no macOS.")
        digest = hashlib.sha256(SWIFT_SOURCE.encode()).hexdigest()[:12]
        folder = self._cache or cache_dir()
        source = folder / f"vision_ocr_{digest}.swift"
        binary = folder / f"vision_ocr_{digest}"
        if binary.is_file() and os.access(binary, os.X_OK):
            self._command = [str(binary)]
            return self._command
        source.write_text(SWIFT_SOURCE, encoding="utf-8")
        source.chmod(0o600)
        swiftc = shutil.which("swiftc")
        if swiftc:
            logger.info("Compilando o leitor de OCR (Vision) em %s", binary)
            try:
                result = subprocess.run(  # binário do sistema, argumentos fixos
                    [swiftc, "-O", str(source), "-o", str(binary)],
                    capture_output=True, text=True, timeout=COMPILE_TIMEOUT_S, check=False,
                )
            except subprocess.TimeoutExpired as exc:
                raise AdapterError("A compilação do leitor de OCR passou do tempo.") from exc
            if result.returncode == 0:
                self._command = [str(binary)]
                return self._command
            logger.warning("swiftc falhou; usando o interpretador swift: %s", result.stderr.strip()[:300])
        swift = shutil.which("swift")
        if swift:
            self._command = [swift, str(source)]
            return self._command
        raise ToolNotFoundError("Swift não encontrado para rodar o OCR dos prints.", detail=INSTALL_HINT)

    def read(self, paths: Sequence[str | Path]) -> dict[str, list[OcrLine]]:
        """OCR em lotes. Devolve ``{caminho: linhas}``; imagem ilegível vira `AdapterError`."""
        command = self._runner()
        out: dict[str, list[OcrLine]] = {}
        names = [str(p) for p in paths]
        for start in range(0, len(names), BATCH):
            chunk = names[start:start + BATCH]
            try:
                result = subprocess.run(  # binário próprio, caminhos já validados
                    command + chunk, capture_output=True, text=True, timeout=BATCH_TIMEOUT_S, check=False,
                )
            except subprocess.TimeoutExpired as exc:
                raise AdapterError("O OCR dos prints passou do tempo.") from exc
            if result.returncode != 0:
                raise AdapterError("Falha no OCR dos prints.", detail=result.stderr.strip()[:500])
            try:
                items = json.loads(result.stdout)
            except json.JSONDecodeError as exc:
                raise AdapterError("O OCR devolveu uma saída que não é JSON.") from exc
            for item in items:
                if item.get("error"):
                    raise AdapterError(f"Não foi possível ler {Path(item['file']).name}: {item['error']}")
                out[item["file"]] = [
                    OcrLine(t=str(line["t"]), x=float(line["x"]), y=float(line["y"]), w=float(line["w"]),
                            h=float(line["h"]), c=float(line.get("c", 1.0)))
                    for line in item["lines"]
                ]
        return out

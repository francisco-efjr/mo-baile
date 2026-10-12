"""Aba Relatório: auditoria de tagueamento contra a spec do Figma.

O núcleo é o `tag_audit` (projeto bold-kepler), portado para as camadas do
motor. Ver `docs/adr/0003-relatorio-tagueamento.md`.

    rules        normalização, placeholders, filtro de ruído e expansão da spec
    firebase_log leitura do log (arquivo exportado, Logcat ou eventos da sessão)
    audit        casamento por variação e "fora da spec"
    card_reader  OCR dos cards do Figma para o rascunho da spec
    board        board Excalidraw
    documents    Markdown, TSV e HTML
    service      caso de uso chamado pelo RPC
"""

from mobaile.services.report.service import ReportService

__all__ = ["ReportService"]

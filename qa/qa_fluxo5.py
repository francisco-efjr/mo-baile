import sys

"""FLUXO 5 — aba Relatório: spec do Figma x log do Analytics, sem aparelho.

Sobe o motor de verdade e faz o que o app faz: abre a spec, audita um log
exportado, exporta os quatro arquivos e confere o conteúdo deles. Os dados são
sintéticos (os mesmos dos testes do motor). O HOME do motor aponta para uma
pasta temporária: nenhum caminho padrão pode escrever na pasta do usuário.
"""
import json
import pathlib
import tempfile

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(AQUI.parent / "engine" / "tests" / "unit"))
from engine_client import Motor
from relatorio_dados import AUSENTES, DIVERGENTES, OK, SPEC, TOTAL, gravar

falhas, passes = [], []
def check(nome, cond, detalhe=""):
    (passes if cond else falhas).append(nome)
    print(f"  [{'PASS' if cond else 'FALHA'}] {nome}" + (f"  -> {detalhe}" if detalhe and not cond else ""))

print("=" * 78)
print("FLUXO 5 — RELATÓRIO DE TAGUEAMENTO")
print("=" * 78)

tmp = tempfile.TemporaryDirectory()
pasta = pathlib.Path(tmp.name).resolve()
spec_path, log_path = gravar(pasta)
m = Motor(android=False, ios=False, extra_env={"HOME": str(pasta / "home")})
try:
    hello = m.ok("engine.hello", {"protocol_version": 2, "client": "qa"})
    metodos = hello["methods"]
    check("hello anuncia os quatro métodos de relatório",
          all(n in metodos for n in ("report.spec", "report.audit", "report.export", "report.import")))
    check("relatório roda na fila própria",
          {metodos[n]["lane"] for n in metodos if n.startswith("report.")} == {"report"})

    resumo = m.ok("report.spec", {"path": str(spec_path)})
    check("spec lida com cards e variações", (resumo["cards"], resumo["variants"]) == (3, TOTAL), str(resumo))
    check("fluxos na ordem da spec", [f["key"] for f in resumo["fluxos"]] == ["pessoal", "investimentos"])

    # Sessão sem escuta: recusar é melhor que um relatório todo "não disparado".
    e = m.erro("report.audit", {"spec_path": str(spec_path), "source": "session"})
    check("sessão sem eventos devolve invalid_input", e["data"]["code"] == "invalid_input", str(e))
    check("mensagem diz o que fazer", "Analytics" in e["message"], e["message"])

    rel = m.ok("report.audit", {"spec_path": str(spec_path), "source": "file", "log_path": str(log_path),
                                "progress_token": "qa-5"})
    s = rel["summary"]
    check("totais batem com o cenário",
          (s["total"], s["ok"], s["divergent"], s["missing"]) == (TOTAL, OK, DIVERGENTES, AUSENTES), str(s))
    check("conformidade calculada", s["compliance_rate"] == round(OK / TOTAL * 100, 1))
    check("duplicado e plataforma filtrados no log",
          rel["log_stats"] == {"total_lidos": 12, "da_plataforma": 11, "duplicados": 1, "uteis": 10},
          str(rel["log_stats"]))
    check("fora da spec e alertas", (s["extras"], s["alerts"]) == (3, 1))
    progresso = m.esperar_notificacao("$/progress", timeout=5)
    check("progresso chega com o token pedido", progresso["params"]["token"] == "qa-5")

    erro = next(r for r in rel["results"] if r["status"] == "error" and r["variation"] == "click:parcelas")
    check("divergência diz campo, obtido e esperado",
          erro["divergences"] == "component: obtido toggle, esperado button", erro["divergences"])
    check("bloco da variação igual ao do board", erro["block"].startswith("// CPAGI · "))

    destino = pasta / "exportado"
    exp = m.ok("report.export", {"directory": str(destino)}, timeout=60)
    nomes = sorted(f["name"] for f in exp["files"])
    check("quatro arquivos exportados", nomes == ["board_auditoria.excalidraw", "relatorio_auditoria.html",
                                                   "relatorio_auditoria.md", "relatorio_auditoria.tsv"], str(nomes))
    board = json.loads((destino / "board_auditoria.excalidraw").read_text(encoding="utf-8"))
    ids = [el["id"] for el in board["elements"]]
    check("board é Excalidraw v2 válido", board.get("type") == "excalidraw" and board.get("version") == 2)
    check("board sem id repetido", len(ids) == len(set(ids)))
    tsv = (destino / "relatorio_auditoria.tsv").read_text(encoding="utf-8").strip().split("\n")
    check("TSV com uma linha por variação e nove colunas",
          len(tsv) == TOTAL + 1 and all(len(linha.split("\t")) == 9 for linha in tsv))
    md = (destino / "relatorio_auditoria.md").read_text(encoding="utf-8")
    check("Markdown com a tabela e o quadro fora da spec", "| Seção |" in md and "Fora da spec" in md)

    # Entrada hostil: o nome do projeto vai para o HTML que abre no navegador.
    pasta_hostil = pasta / "hostil"
    pasta_hostil.mkdir()
    hostil, _ = gravar(pasta_hostil, spec={**SPEC, "projeto": "<script>alert(1)</script>"})
    m.ok("report.audit", {"spec_path": str(hostil), "source": "file", "log_path": str(log_path)})
    m.ok("report.export", {"directory": str(pasta / "hostil-saida")}, timeout=60)
    html = (pasta / "hostil-saida" / "relatorio_auditoria.html").read_text(encoding="utf-8")
    check("nome hostil não vira script no HTML", "<script>alert(1)" not in html and "&lt;script&gt;" in html)

    # Recusas: sempre tipadas, nunca "Erro interno no motor".
    quebrada = pasta / "quebrada.json"
    quebrada.write_text('{"projeto": "x", "cards": [', encoding="utf-8")
    e = m.erro("report.spec", {"path": str(quebrada)})
    check("spec que não é JSON aponta a linha", e["data"]["code"] == "invalid_input" and "linha" in e["message"],
          str(e))
    e = m.erro("report.spec", {"path": str(pasta / "nao-existe.json")})
    check("spec inexistente é invalid_input", e["data"]["code"] == "invalid_input")
    e = m.erro("report.spec", {"path": "spec\u0000.json"})
    check("byte nulo no caminho é recusado", e["data"]["code"] == "invalid_input")
    e = m.erro("report.audit", {"spec_path": str(spec_path), "source": "file", "log_path": str(pasta)})
    check("log que é pasta é recusado", e["data"]["code"] == "invalid_input")
    sem_prints = pasta / "sem-prints"
    sem_prints.mkdir()
    e = m.erro("report.import", {"prints_dir": str(sem_prints), "spec_path": str(pasta / "rascunho.json")})
    check("importação sem imagem é recusada antes do OCR", e["data"]["code"] == "invalid_input", str(e))
    check("nada foi gravado na pasta do usuário", not (pasta / "home" / "Documents").exists())

    check("motor seguiu respondendo", bool(m.ok("engine.info").get("version")))
finally:
    m.encerrar()
    tmp.cleanup()

print(f"\n  RESULTADO: {len(passes)} passaram, {len(falhas)} falharam")
if falhas:
    print("  FALHAS:", falhas)
sys.exit(1 if falhas else 0)

# Viabilidade multiplataforma: Analytics e Relatório fora do macOS

Data: 2026-11-16. Revisão somente leitura, feita pelo arquiteto da rodada. Nada foi executado em Windows. Tudo o que está marcado "Suposição" é inferência de leitura de código, sem teste.
Limite da revisão: mesmo modelo do autor do código; é uma segunda leitura, não validação externa. Versão do código lido: 3.23.0 (branch `melhoria/2026-11-16-liberacao-publica`).

## 0. Resposta curta

- O **Relatório** (ler spec, ler log, auditar, gerar HTML/Markdown/TSV/board) é Python puro e já roda em Linux hoje: a suíte dele roda no CI Ubuntu (`.github/workflows/ci.yml:24`). Em Windows a lógica de auditoria deve rodar igual (Suposição); o que falta é **uma porta de entrada** (hoje só há stdio com o app Swift) e três arestas de SO que não estão no caminho do Relatório.
- O **Analytics em tempo real** depende de `adb logcat` (Android) e é Android-only fora do Mac. O **parser** do logcat é Python puro e serve para um logcat salvo.
- O app Tkinter **não tem aba Relatório** nem o editor de spec (ver 1.4). A opção A custaria reconstruir o Relatório em Tk, contra o ADR 0005 (Tk congelado).
- Recomendação: **opção B em fases** (servidor web local `python -m mobaile.web`, mesmo motor, 127.0.0.1), com MVP de ~400 linhas só de Relatório + Analytics por arquivo/colagem. Depois, **opção C via Pyodide** (reuso do mesmo Python, sem port para JS) se o dono quiser "sem instalar nada". D só depois, e só se houver demanda de distribuição.

## 1. Mapa dos módulos

### 1.1 Relatório

| Camada | Onde | Papel |
|---|---|---|
| Swift, telas | `apps/MoBaile/Sources/MoBaile/Views/Report/` (ReportView 577, ReportSpecEditorView 477, ReportBug 297, ReportDetailPane 297, ReportToolbar 270, ReportCardEditor 178, ReportImportSheet 113, ReportCardInspector 96, ReportExportSheet 68) | interface; ~2 370 linhas |
| Swift, modelos/DTO | `Models/ReportModels.swift` (497), `Engine/EngineDTO+Report.swift` (402) | tipos do contrato |
| Swift, chamadas RPC | `Engine/EngineSession.swift:1592` (`report.spec`), `:1628` (`report.audit`), `:1661` (`report.export`), `:1688` (`report.import`), `:1719` (`report.checklist_export`), `:1744` `:1772` (`report.card`, `report.card_update`), `:1802` `:1832` (`report.cards`, `report.cards_update`) | cliente |
| RPC | `engine/src/mobaile/rpc/server.py:406-414` (tabela), handlers `:2431-2517` | `report.spec/audit/export/import/checklist_export/card/card_update/cards/cards_update` |
| Contrato | `rpc/contract.py` (lane `report`), `docs/PROTOCOLO_RPC.md` | fronteira |
| Serviço | `services/report/service.py` (682): `read_log :169`, `audit :174`, `report_payload :202`, `export :392`, `import_prints :431` | orquestra |
| Núcleo de regra | `services/report/audit.py` (272), `rules.py` (226), `firebase_log.py` (200), `domain/report.py` (292) | auditoria; ~990 linhas |
| Saídas | `documents.py` (89; Markdown, TSV), `html_report.py` (477; HTML interativo), `board.py` (369; Excalidraw), `checklist.py` (533), `card_reader.py` (506; OCR para spec) | |
| Assets embutidos | `services/report/html/` (`report.js` 381, `report.css` 228, `design_system.css` 696, `motion.min.js` 144 KB, `icons.json`, `icon.png`); `tools/sync_report_assets.py` copia do design system; empacotados por `pyproject.toml` `package-data` | HTML autocontido: CSP com hash dos scripts (`html_report.py:371`, `:377`) |

Fluxo do Relatório sem prints: `read_log` (`service.py:169`) → `items_from_text` (`firebase_log.py`) → `events_from_items` → `run_audit` (`audit.py`) → `report_payload` (JSON da aba) → `export` grava board, HTML, Markdown e TSV (`service.py:392-428`).

### 1.2 Analytics

| Camada | Onde |
|---|---|
| Swift | `Views/Analytics/AnalyticsInspectorView.swift` (165), `AnalyticsToolbar.swift` (148); estado em `App/AppState.swift` (`analyticsEvents`); exportar TSV/JSON em `App/Exporters.swift:81-109`; chamadas em `Engine/EngineSession.swift:1534` (`stop`), `:1542` (`start`), `:1555` (`ios_devices`), `:1574` (`clear`), notificação `analytics.event` em `:2421` |
| RPC | `rpc/server.py:385-389` (`analytics.start/stop/events/clear/ios_devices`), handlers `:1743-1800`; notificação `analytics.event` emitida em `:254` |
| Motor | `adapters/analytics_logcat.py` (648): `FirebaseAnalyticsListener`; `start :260` (Android: `adb logcat -v time -s FA FA-SVC FirebaseAnalytics FA-GMS`, `:322`; iOS simulador: `xcrun simctl spawn ... log stream`, `:309`; iPhone por cabo: filho `ios_device_log`, `:302`); parser `_parse_line :558`; iOS `IOSLogRecordAssembler :70` e `_parse_ios_record :494`; `setup_props :193` (setprop via adb) |
| Modelo | `domain/models.py` `AnalyticsEvent :229` (`to_dict :249`) |
| Teste | `engine/tests/unit/test_analytics_logcat.py` (já testa o parser sem aparelho) |

Ponto de reuso: o Relatório já lê logcat em texto sozinho (`firebase_log.py`, `ANDROID_LINE`) e a auditoria aceita `source: "file"` (`server.py:2455`). O que **não** existe é "carregar um logcat/JSON salvo na tabela de Analytics": a tabela só se alimenta da escuta ao vivo.

### 1.3 Matriz de dependências por SO

Legenda: OK = roda só com Python 3.10+; Android = precisa de `adb` e aparelho/emulador; Mac = só macOS.

| Item | Onde | macOS | Linux | Windows | Observação |
|---|---|---|---|---|---|
| Auditoria (spec + log) | `services/report/audit.py`, `rules.py`, `firebase_log.py`, `domain/report.py` | OK | OK (CI) | OK (Suposição) | só `re`, `json`, `dataclasses` |
| Exportar HTML/MD/TSV | `documents.py`, `html_report.py` | OK | OK (CI) | OK (Suposição) | lê assets via `Path` do pacote; `Path.home()/Documents/Mo baile` (`service.py:112`) vira `C:\Users\x\Documents\Mo baile`, aceitável |
| Board Excalidraw | `board.py:30` `from PIL import Image` | OK | OK | OK (Suposição) | Pillow é dependência obrigatória (`pyproject.toml`), há wheel para Windows |
| Editor de spec (`report.cards*`, `card*`) | `service.py:269-372` | OK | OK | OK (Suposição) | só JSON em disco |
| Importar prints (OCR) | `adapters/vision_ocr.py:34` (`import AppKit`, Vision via `swiftc`), cache em `~/Library/Caches` (`:73`), `platform.system()=="Darwin"` (`:89`) | OK | NÃO | NÃO | `ReportService(ocr=None)` recusa com mensagem clara (`service.py:442`); sem substituto portátil |
| Checklist HTML | `checklist.py` | OK | OK | OK (Suposição) | |
| Parser de logcat/iOS (texto) | `analytics_logcat.py:558`, `:494`, `:70` | OK | OK | OK (Suposição) | mas o módulo importa `adb` e `ios_device_log` no topo (`:32-33`) e instancia `ADBBridge()` no import (`:648`): inofensivo, só procura o adb |
| Escuta ao vivo Android | `adb logcat` (`analytics_logcat.py:322`) + `setup_props :193` | OK | OK | OK com adb (Suposição) | `adb.py:80-85` só procura `/opt/homebrew`, `/usr/local`, `~/Library/Android/sdk`; no Windows o adb precisa estar no PATH; `os.access(X_OK)` em `.exe` funciona |
| Escuta iOS simulador | `xcrun simctl` (`:309`) | OK | NÃO | NÃO | |
| Escuta iPhone por cabo | `ios_device_log` + `pymobiledevice3` (extra `ios-device`, `pyproject.toml`) | OK | Possível | Possível | pymobiledevice3 tem suporte a Linux/Windows; não testado aqui (Suposição); `ios_device_log.py` não foi lido por inteiro |
| Servidor RPC por stdio | `rpc/server.py:3004` `serve_forever`; `serve :3157` | OK | OK | quebra na subida | `serve()` chama `configure_logging` → `logs_dir()` → `os.open(..., O_DIRECTORY\|O_NOFOLLOW)` (`security/paths.py:64`) que não existem no Windows: `AttributeError` não tratado (o `except OSError` em `server.py:3114` não pega); também `server.py:3052-3056` (`O_NOFOLLOW`, `os.fchmod`) |
| Pasta privada de sessão | `security/paths.py:32` `os.getuid()`, `:103-143` `O_NOFOLLOW`, `fchmod`, `dir_fd` | OK | OK | quebra | só afeta quem usa `secure_runtime_dir`/escrita atômica (fluxos, captura); **o Relatório não passa por aí** (grep em `services/report/*.py`: nenhuma ocorrência) |
| Gravação de vídeo | `screen_recorder.py:178` `send_signal(SIGINT)` | OK | OK | quebra | fora do escopo |
| Execução (behave) | `services/project_run.py:376` `start_new_session`, `:476-492` `os.killpg` | OK | OK | quebra | fora do escopo |
| `EngineServer()` construído sem aparelho | `server.py:236-258` (ADBBridge, IOSBridge, ScrcpyManager, proxy, `VisionOCR()`) | OK | OK (CI) | provável (Suposição) | construtores só procuram binários; não confirmado em Windows |
| Pastas de dados | `services/home.py:79-81` (`~/Library/Application Support` no Mac, `~/.mobaile` nas demais), `paths.py:55-58` | OK | OK | OK (`~\.mobaile`) | |
| App Swift | `apps/MoBaile` | OK | NÃO | NÃO | |

Conclusão do mapa: **o caminho Relatório + Analytics-por-arquivo não toca nenhuma API exclusiva de macOS nem de POSIX**. Os defeitos de Windows listados em `docs/INSTALACAO.md:180-190` estão todos fora desse caminho, com uma exceção: o `serve()` stdio, que o servidor web não precisa usar.

### 1.4 Tkinter legado

`apps/tk-legacy/mobaile_tk/*.py` (5 646 linhas). `grep -i "report\|relat"` em `main_window.py` não acha aba Relatório; o Analytics aparece como alternância de visão (`:1328-1332`) e contador (`:775`). O ADR 0005 congela o Tk. `docs/INSTALACAO.md:187` já lista um defeito de Windows no Tk (`<Command-f>`, `main_window.py`), não verificado.

## 2. Opções

Estimativas de linhas são Suposição baseada em tamanho de módulos parecidos. Esforço: P (< 1 dia), M (2-4 dias), G (> 1 semana).

### A. Tkinter legado no Windows para Analytics/Relatório

- Esforço **G**. O Tk já tem Analytics ao vivo, mas **não tem Relatório**. Construir Relatório (resumo, filtros, cards, tabela, extras) em Tk: ~1 500 a 2 500 linhas novas de UI, contra o ADR 0005 ("Tk congelado, sem recurso novo", `docs/adr/0005-app-tk-congelado.md`). Teria de reverter ou emendar o ADR.
- Já tem defeito conhecido de montar a janela fora do macOS (`INSTALACAO.md:184`); aparência ruim em Windows; não herda o HTML interativo.
- Dependências novas: nenhuma. Risco: alto (retomar um front congelado). Fica de fora: tudo que o Tk não tem.
- Veredito: **não recomendado.**

### B. Interface web local servida pelo motor (`python -m mobaile.web`)

- Esforço **M** (MVP **P/M**, ~400 linhas; completo ~1 500).
- Dependências novas: **nenhuma** (stdlib `http.server`, `secrets`, `threading`); front em HTML/CSS/JS estático. Reaproveita `design_system.css`, `report.css`, `report.js` que já existem em `services/report/html/` e o HTML de relatório que o motor já gera. Pillow e requests já são dependências.
- Reuso: 100% da regra de negócio; o front web só renderiza. Duas telas pequenas (Relatório, Analytics) em vez de 3 585 linhas Swift, porque o HTML interativo já é um "visualizador" completo: o Relatório pode **embutir o HTML do motor num iframe sandbox** em vez de reescrever a aba.
- Transporte: `POST /rpc` (JSON-RPC por HTTP, mesmo envelope de `rpc/protocol.py`) e `GET /events` (SSE) para `analytics.event` e `$/progress`. SSE em vez de WebSocket: a stdlib não tem WebSocket e SSE basta para empurrar de servidor para cliente.
- Riscos: (1) superfície de rede local: exige token, checagem de Host/Origin e bind só em loopback (seção 5); (2) os handlers `report.*` aceitam **caminhos arbitrários** do disco (`validate_input_file` só confere existência, extensão e tamanho, `security/files.py:34-55`); exposto na web, um site malicioso poderia ler `.json/.log` ou escrever em qualquer pasta, então a camada web precisa de upload em pasta de sessão e confinamento de caminhos; (3) `EngineServer()` em Windows não foi verificado.
- Fica de fora: OCR (Mac), simulador/iPhone, espelho, Execução. Escuta ao vivo Android entra na fase 2 (precisa de adb).
- Também resolve Linux de graça, e o app nativo não muda.

### C. Web 100% estática (GitHub Pages) para o Relatório

Duas formas:

- **C1, port da lógica para JS.** Portar `audit.py` + `rules.py` + `firebase_log.py` + `domain/report.py` (~990 linhas Python, ~1 200-1 500 de JS) e a geração do HTML (`html_report.py` 477 + helpers de `board.py` `summary_lines/observation_lines/log_period`, ~200: outras ~700 linhas) = **~2 000-2 400 linhas de JS**, mais testes de paridade. Esforço **G**. Risco: duas fontes da verdade para a regra de auditoria; regex de Python (`re`) e JS diferem (flags, lookbehind, Unicode, `re.DOTALL`); toda mudança em `rules.py` passa a exigir duas edições. Contraria "motor é a fonte da verdade". **Não recomendado**, a menos que Pyodide seja inviável.
- **C2, Pyodide (Python no navegador).** Carregar o mesmo código (`domain/report.py`, `services/report/*`, `security/`, `ports/`, e o parser) no Pyodide; só substituir a camada de arquivos por upload em memória (`MEMFS`). Esforço **M** (~250-400 linhas de glue JS + ajustes de import). Sem port, sem duplicar regra: a página roda a mesma auditoria Python. Custos: primeira carga ~10 MB do Pyodide (Suposição; cacheável) + Pillow como pacote do Pyodide (`board.py:30` importa PIL no topo; ou tornar o import preguiçoso, ~5 linhas); `ReportService` usa `threading.Lock` (funciona no Pyodide, sem threads reais); os assets do HTML (`html/*`, 144 KB de Motion) precisam ir para o sistema de arquivos virtual. Hospedar o Pyodide: CDN jsDelivr (dependência de terceiro; o relatório gerado é autocontido, mas a página não seria) ou cópia própria no Pages. Risco: tempo de carga, fatia de usuários em navegador antigo, versão do Pyodide trazer Python diferente do motor (3.12/3.13).
- **Analytics em C?** O **tempo real não cabe** (precisa de adb/processo local). **Colar ou importar um logcat salvo cabe**: o parser (`_parse_line`, `_parse_ios_record`, `IOSLogRecordAssembler`) é Python puro, mas hoje mora dentro de `FirebaseAnalyticsListener`, que importa `adb`/`subprocess`/`ios_device_log`. Para entrar no Pyodide convém extrair `parse_logcat_text(text, platform)` para um módulo puro (ex. `domain/analytics_parse.py`, ~120 linhas movidas, não novas). A tabela com filtro/busca é ~150 linhas de JS.
- Fica de fora de C: tudo que depende de aparelho, OCR, editor de spec que grava no disco (o editor pode virar download do JSON), exportação para pasta (vira download/zip).
- Privacidade: o log do QA nunca sai do navegador; ponto forte para quem não instala nada. Mas **não pode** ter telemetria nem CDN de terceiros no caminho do dado.

### D. Empacotar para Windows (Electron, Tauri, PyInstaller)

- Esforço **G** e recorrente (assinatura de código, antivírus falso-positivo no PyInstaller, instalador, atualização). Não resolve o front (continua faltando UI): é só embalagem do **B** (um .exe que sobe o servidor e abre o navegador/webview). Tauri/Electron adicionam runtime de ~10-150 MB e uma segunda toolchain (Rust/Node) ao projeto.
- Sentido só como fase final: PyInstaller (ou o Python embutido do `instalar-windows.ps1`, já existente em `tools/setup/`) empacotando `python -m mobaile.web`. Sem teste em Windows real, qualquer pacote seria às cegas.
- Dependências novas: PyInstaller (build) ou Tauri/Electron. Risco: alto. Veredito: **depois do B validado por quem usa Windows.**

### Comparativo

| | A Tk | B web local | C1 JS | C2 Pyodide | D empacotar |
|---|---|---|---|---|---|
| Esforço | G | M (MVP P/M) | G | M | G |
| Linhas novas (est.) | 1 500-2 500 | ~400 MVP / ~1 500 completo | 2 000-2 400 | 250-400 + ~120 movidas | pouco código, muita infra |
| Regra duplicada | não | não | **sim** | não | não |
| Relatório | construir | sim | sim | sim | via B |
| Analytics ao vivo (Android) | já tem | fase 2 | não | não | via B |
| Analytics por arquivo | construir | sim | sim (port) / sim (Pyodide) | sim | via B |
| Exige instalar Python | sim | sim (3.10+) | não | não | não |
| Superfície de segurança | nenhuma | rede local (mitigável) | nenhuma | nenhuma | depende |
| Conflita com ADR | **0005** | não | não | não | não |

## 3. Recomendação em fases

**Fase 0 (pré-requisito barato, dentro do MVP):** extrair o parser de logcat para função pura e criar `analytics.import_text`.

**Fase 1, MVP (B mínimo, ~400 linhas de produção):** `python -m mobaile.web`, Relatório auditando spec + log enviados pela página, Analytics lendo um logcat/JSON salvo. Sem escuta ao vivo, sem OCR, sem editor de spec.

**Fase 2 (B completo):** SSE com `analytics.event` + escuta ao vivo Android (`analytics.start/stop`, precisa corrigir `adb.py:80-96` para `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`); editor de spec (`report.cards*`) na web; portabilidade de `security/paths.py` e `server.py:3052` (helper `open_private` que usa `O_NOFOLLOW` só quando existe e `os.chmod` quando não há `fchmod`); upload de prints (a spec pode apontar `prints_dir`, hoje inexistente na web); CI em `windows-latest` rodando só os testes do Relatório e do parser.

**Fase 3 (opcional, "sem instalar nada"):** C2 Pyodide em GitHub Pages reutilizando o front da fase 1 (a mesma `index.html`, trocando o transporte `fetch('/rpc')` por chamada ao Pyodide). Isso é barato justamente porque a fase 1 já isola o front atrás de uma interface `rpc(method, params)`. Só Relatório + Analytics por arquivo.

**Fase 4 (opcional):** empacotamento (D), com testador em Windows real.

Por que B antes de C2: B valida o contrato web e a UI com o motor real, em uma máquina onde dá para testar; C2 reaproveita a mesma UI. C1 fica descartada pelo custo de duplicação.

Decisão estrutural que merece ADR curto (ADR 0007, "front web local multiplataforma"): front web como terceiro front, limitado a Analytics e Relatório; servidor loopback + token; Tk continua congelado.

## 4. Esboço técnico do MVP (Fase 1)

Versão sugerida: **3.24.0** (recurso novo no motor; CHANGELOG, `make fixtures`, tag; regra em `AGENTS.md`). O pacote entra no bundle do app nativo (`engine/src`), então o fluxo `make update-native` vale para quem implementar.

### 4.1 Arquivos novos (estimativa de linhas de produção)

| Arquivo | Linhas | Conteúdo |
|---|---|---|
| `engine/src/mobaile/web/__init__.py` | 1 | |
| `engine/src/mobaile/web/__main__.py` | ~35 | `argparse` (`--port` padrão 0, `--no-browser`, `--host` aceita só loopback), `logging.basicConfig` (**não** chamar `configure_logging`, que quebra no Windows), sobe o servidor, imprime a URL com o token, `webbrowser.open` |
| `engine/src/mobaile/web/server.py` | ~170 | `ThreadingHTTPServer` com handler: roteamento, checagem de Host, Origin e token, limites de corpo, cabeçalhos de segurança, `POST /rpc`, `POST /upload`, `GET /download/<id>`, `GET /` e estáticos; `EngineServer(out=<sink>)` único e um `Lock` em volta de `handle_message` |
| `engine/src/mobaile/web/sandbox.py` | ~70 | pasta de sessão (`tempfile.mkdtemp`, `chmod 0700` quando existir), gravação de upload com nome gerado e limite (spec 5 MB = `MAX_SPEC_BYTES`, log 64 MB = `MAX_LOG_BYTES`, de `security/files.py`), **allowlist de métodos**, confinamento de caminhos nos parâmetros (`spec_path`, `log_path`, `directory`) à pasta da sessão, limpeza ao sair |
| `engine/src/mobaile/web/static/index.html` | ~50 | duas abas: Relatório e Analytics; `<meta>` de CSP |
| `engine/src/mobaile/web/static/app.js` | ~120 | cliente `rpc(method, params)` com o token em memória; upload; renderiza o resumo do `report.audit` (tiles + lista) e abre o HTML completo em iframe `sandbox`; tabela de Analytics com filtro por nome; botão "Baixar HTML/TSV" |
| `engine/src/mobaile/web/static/app.css` | ~40 | reusa tokens do `design_system.css` por cópia via `tools/sync_report_assets.py` (já existe para o HTML do relatório) |
| `engine/src/mobaile/adapters/analytics_logcat.py` (edição) | ~+40 / -0 | função pura `parse_logcat_text(text, platform) -> list[AnalyticsEvent]` usando `_parse_line`, o assembler iOS e `_parse_ios_record` (hoje instância; precisa de um `get_next_id`: instanciar listener sem adb ou mover para módulo puro) |
| `engine/src/mobaile/rpc/server.py` + `contract.py` (edição) | ~+25 | método `analytics.import_text` (`text`, `platform` opcional; recusa texto acima de `MAX_LOG_BYTES`), lane `fast`/`report`; entrada em `docs/PROTOCOLO_RPC.md` e fixtures |
| `engine/pyproject.toml` (edição) | ~+2 | `package-data` para `mobaile.web = ["static/*"]` e script `mobaile-web = "mobaile.web.__main__:main"` |
| `engine/tests/unit/test_web_*.py`, `test_analytics_import.py` | (teste, fora da conta) | ver seção 6 |

Total de produção: **~35 + 170 + 70 + 50 + 120 + 40 + 40 + 25 ≈ 550**, ~400 sem os estáticos de UI que são só marcação. Se precisar caber em ~400 de lógica, o corte natural é `app.css` (reusar o CSS do relatório) e a aba Analytics sem filtro. Estimativa: Suposição.

### 4.2 Rotas

| Rota | Método | Autenticação | O que faz |
|---|---|---|---|
| `/` e `/static/*` | GET | token na primeira carga (fragmento `#t=`), depois header | HTML/JS/CSS; `Cache-Control: no-store` |
| `/rpc` | POST `application/json` | header `X-Mobaile-Token` | corpo é o envelope JSON-RPC de `protocol.py`; só métodos da allowlist |
| `/upload?kind=spec\|log` | POST corpo bruto | header de token | grava na sessão, devolve `{"path": "<na sessão>", "bytes": n}` |
| `/download/<nome>` | GET | token em header ou `?t=` de uso único | HTML/MD/TSV gerados por `report.export` (diretório forçado para a sessão) |
| `/events` (fase 2) | GET SSE | token | `analytics.event`, `$/progress` |

### 4.3 Métodos RPC reutilizados (allowlist do MVP)

`engine.hello`, `report.spec`, `report.audit` (com `source: "file"`; **`source: "session"` fica fora**, depende da escuta), `report.export`, `report.cards`, `analytics.import_text` (novo). Fase 2 acrescenta `report.card*`, `report.cards_update`, `analytics.start/stop/clear/events`. Fora da allowlist e recusados com `-32601`: `workspace.*`, `run.*`, `proxy.*`, `flow.*`, `report.import` (OCR) e o resto, para a web nunca alcançar arquivo arbitrário nem processo.

Reaproveitar `EngineServer.handle_message` (`server.py:2829`) mantém o envelope, os erros tipados (`InvalidInputError` etc.) e o texto das mensagens iguais ao app nativo. Alternativa mais leve, se `EngineServer()` não subir em Windows: chamar `ReportService(ocr=None)` direto e escrever 3 handlers finos (~60 linhas), copiando o que `server.py:2435-2483` faz (menos `_remember`). Decidir ao testar em Windows; o MVP no Mac usa `handle_message`.

### 4.4 Segurança (obrigatório antes de qualquer código)

1. **Bind só em loopback.** Aceitar `127.0.0.1` ou `::1`; recusar `0.0.0.0` e nomes. Padrão `127.0.0.1`. Porta 0 (aleatória) por padrão.
2. **Token por sessão.** `secrets.token_urlsafe(32)`, comparado com `hmac.compare_digest`. Entregue ao navegador no fragmento da URL (`http://127.0.0.1:PORTA/#t=...`, o fragmento não vai ao servidor nem a logs), lido pelo JS e guardado em memória; toda requisição à API leva `X-Mobaile-Token`. Sem token: 401, sem corpo detalhado. Não gravar o token em disco nem em log (o `_RedactingFilter` do motor, `server.py:3070+`, não conhece este formato: **não logar a URL**, imprimir só no terminal).
3. **Contra DNS rebinding:** conferir `Host` exato (`127.0.0.1:PORTA`, `localhost:PORTA`, `[::1]:PORTA`); qualquer outro: 421. Token em header (não cookie) já derruba CSRF clássico, e a checagem de Host fecha a janela de rebinding.
4. **CSRF/CORS:** nenhum cabeçalho `Access-Control-Allow-*`. `POST` só com `Content-Type: application/json` (ou `application/octet-stream` no upload), que força *preflight* em chamada de outra origem; sem CORS, o preflight falha. Conferir `Origin` quando presente: igual à origem do servidor, senão 403. Recusar `GET` com efeito colateral.
5. **Confinamento de arquivo.** A web nunca passa caminho do cliente ao motor: o cliente envia o arquivo, recebe um caminho dentro da pasta de sessão, e `sandbox.py` verifica que cada `*_path`/`directory` do request resolve (com `resolve()`, mesma regra de `_dentro_de`, `server.py:201`) para dentro dela. `report.export` ganha `directory` forçado. Extensões e tamanhos continuam os de `security/files.py`.
6. **Limites:** corpo máximo por tipo (5 MB spec, 64 MB log, 1 MB `/rpc`); `Content-Length` obrigatório; sem *chunked*; timeout de socket; um `Lock` global (motor é single-user).
7. **Cabeçalhos:** `Content-Security-Policy: default-src 'self'; frame-src 'self'; ...` na página do app; o HTML do relatório já traz a própria CSP com hash (`html_report.py:371`), então vai num `<iframe sandbox="allow-scripts">` e é servido com `Content-Security-Policy: sandbox allow-scripts`; `X-Content-Type-Options: nosniff`; `Referrer-Policy: no-referrer`. Todo texto vindo de spec/log já passa por escape no HTML do motor (`documents.py` cabeçalho); a página do app deve usar `textContent`, nunca `innerHTML`, para eventos e parâmetros.
8. **Sem telemetria e sem CDN** no caminho do dado; fontes/ícones locais.
9. **Pasta de sessão** apagada ao sair (`atexit` + SIGINT); `Ctrl+C` encerra o servidor.
10. Aviso no README: o servidor é uma ferramenta local de um usuário, não para rede nem para Docker exposto.

### 4.5 Ajustes de portabilidade (fora do MVP, mas listados)

- `security/paths.py:32` `os.getuid()` → `getattr(os, "getuid", lambda: "user")()`; `:64-71`, `:103-143` `O_DIRECTORY`/`O_NOFOLLOW`/`fchmod`/`dir_fd` → ramo `os.name == "nt"` sem essas flags (no Windows, symlink exige privilégio, risco menor).
- `server.py:3052-3056` idem (`_open_private`).
- `adapters/adb.py:80-96` acrescentar `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` e `shutil.which("adb.exe")`.
- `screen_recorder.py:178`, `project_run.py:376,476-492`: fora do escopo de Analytics/Relatório.

## 5. Critério de aceite do MVP

Num Windows ou Linux com Python 3.10+, só com `pip install` do pacote do motor (Pillow e requests, sem adb, sem Xcode):

1. `python -m mobaile.web --no-browser` imprime `http://127.0.0.1:<PORTA>/#t=<token>` e abre a página (`GET /` responde 200 só com Host válido).
2. **Relatório:** enviar uma spec de exemplo e um log de exemplo (JSON do Mo baile ou logcat em texto); a página mostra o resumo (total, OK, divergentes, não disparadas, taxa de conformidade), exibe o HTML interativo do motor num iframe e baixa HTML, Markdown e TSV. Os números são **idênticos** aos de `report.audit` chamado direto (mesmo `summary` e `results`).
3. **Analytics:** colar/enviar um logcat de exemplo (e um trecho iOS); a tabela lista nome, hora, tag e parâmetros dos eventos, com a mesma contagem de `analytics.import_text`; "Baixar TSV/JSON" gera o mesmo conteúdo de `export_as_tsv/json` (`analytics_logcat.py:620,640`).
4. **Segurança** (todos automatizados): sem token = 401; token errado = 401; `Host: evil.example` = 421; `Origin: http://evil.example` = 403; método fora da allowlist = `-32601`; `spec_path: "/etc/hosts"` ou `"..\\..\\x"` = recusado; `--host 0.0.0.0` = erro; resposta sem nenhum `Access-Control-Allow-Origin`.
5. `make check` verde; novos testes rodando também em `ubuntu-latest`; docs (`PROTOCOLO_RPC.md` com `analytics.import_text`, README/INSTALACAO com a seção "No Windows e no Linux, Analytics e Relatório pelo navegador") e `CHANGELOG`/`VERSION` 3.24.0 atualizados.
6. Registrado no relatório da rodada que **não foi testado em Windows real**; quem tiver Windows roda a checklist 1-3 e anota o resultado (insumo da fase 2).

## 6. Plano de teste nesta máquina (macOS, sem Windows)

Pirâmide:

1. **Motor, sem rede (pytest, rápido).**
   - `test_analytics_import.py`: `parse_logcat_text` com as linhas que `test_analytics_logcat.py` já usa (casos A e B Android, registro iOS multilinha, estágios duplicados), conferindo igualdade com `_parse_line`. Teste de contrato de `analytics.import_text` via `EngineServer.handle_message` (padrão de `engine/tests/contract`); `make fixtures`.
   - Teste de **portabilidade por simulação**: rodar a auditoria com `platform.system`, `os.name` e `sys.platform` patcheados e `os.getuid` removido (`monkeypatch.delattr(os, "getuid", raising=False)`), provando que o caminho Relatório + parser não os usa. Isso não substitui Windows, mas pega regressão.
   - Teste de isolamento de import: subprocess `python -I -c "import mobaile.web.server"` com `sys.modules['AppKit']=None`, `Quartz=None`, para garantir que o servidor web não importa módulos exclusivos de macOS.
2. **Servidor real em 127.0.0.1 (pytest `integration`, marcador já existente).** Subir `mobaile.web` em thread com porta 0; usar `urllib.request`/`http.client` (stdlib): fluxo completo upload spec/log → `/rpc` `report.audit` → `report.export` → `/download`; e a bateria de segurança do item 4 do aceite (cabeçalhos `Host`/`Origin` forjados com `http.client`, que permite). Comparar o `summary` com `ReportService.audit` direto. Fixtures: `engine/tests/unit/relatorio_dados.py` (`gravar`, `SPEC`, `TOTAL`) já gera spec e log de exemplo; reutilizar movendo para `tests/` compartilhado ou importando.
3. **CI.** Adicionar job `windows-latest` limitado (`pytest tests/unit/test_report_*.py tests/unit/test_analytics_import.py tests/unit/test_web_*.py`), e rodar o mesmo no `ubuntu-latest`. Hoje o CI só roda Ubuntu e macOS (`INSTALACAO.md:189`); este job é a única prova real de Windows possível sem máquina física, e deve ser a primeira entrega da fase 2 se o dono não tiver Windows à mão.
4. **Visual.** Navegador embutido do Claude Code (`mcp__Claude_Browser__*`) apontado a `http://127.0.0.1:PORTA/#t=...`, ou capturas, só para checar layout e o iframe; não substitui os testes acima. Encerrar o servidor ao final.
5. **Windows real.** Manual, com a checklist do item 5.6, por quem tiver a máquina.

## 7. Riscos e pontos a verificar (Suposição, não executado)

| ID | Ponto | Por que importa |
|---|---|---|
| V1 | `EngineServer()` constrói em Windows (`ADBBridge`, `IOSBridge`, `ScrcpyManager`, `VisionOCR`) | decide entre `handle_message` e `ReportService` direto (4.3) |
| V2 | Pillow importa no Pyodide e `board.py` pode virar import preguiçoso | custo da fase 3 |
| V3 | `ios_device_log.py` e pymobiledevice3 em Windows/Linux | só afeta Analytics por cabo no iPhone |
| V4 | Acentos em caminho e CRLF em log no Windows | `read_text(encoding="utf-8")` já é explícito (`service.py:171`); logcat salvo no PowerShell pode vir em UTF-16 (`>` do PowerShell 5): tratar BOM/UTF-16 no upload (`errors="replace"` esconderia o problema, o log "não tem eventos") |
| V5 | Reuso de `report.js`/CSS na página do app vs iframe do HTML do motor | se o iframe bastar, o front do MVP fica ainda menor |
| V6 | `report.audit` guarda `_ultimo_relatorio` e `_remember` (`server.py:2467-2472`), que gravam em `data_dir()` (`~/.mobaile`) | efeito colateral em disco fora da sessão web; aceitável, mas anotar |

## 8. Limites desta revisão

- Somente leitura; nada executado em Windows, nem servidor web, nem Pyodide. Foi rodado apenas `python3` com `PYTHONPATH=engine/src` para importar módulos: o Relatório e o parser de Analytics **importam** com Pillow presente e dependem dele (`board.py:30`, `adb.py:19`, `ports/protocols.py:19`); sem Pillow, falham no import.
- Números de linhas de JS e do MVP são estimativas. `ios_device_log.py`, `scrcpy.py`, `proxy.py` e o resto do `server.py` fora das faixas citadas não foram lidos por inteiro.
- Pastas ignoradas pelo `.gitignore` (por exemplo `.claude/worktrees/`) e arquivos de segredo não foram abertos. `qa/cert.pem` e `qa/key.pem` existem em disco mas `git ls-files qa` não os lista (não versionados), então não há ação pendente.

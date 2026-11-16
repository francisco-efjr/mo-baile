# Contraprova: MVP web local (skeptic-architect)

Validador: `architecture-design:skeptic-architect`, só leitura, sobre `multiplataforma.md`.

**Veredito: aprovar com mudanças.**

## Decisões

- **Q1. `EngineServer` ou `ReportService` direto:** `ReportService(ocr=None)` direto, com handlers finos.
  - `EngineServer.__init__` (`rpc/server.py:218-336`) não toca em `getuid`, `O_NOFOLLOW` nem `fchmod`.
  - Mesmo assim, ele expõe a tabela inteira (`rpc/server.py:339-414`).
  - `report.audit`/`report.export` gravam recentes em `~/.mobaile` (`services/home.py:101`, `rpc/server.py:2467-2472`).
- **Q3. Método `analytics.import_text`:** não criar. O servidor web usa `items_from_text` + `events_from_items` (`firebase_log.py:131-139`) direto. Assim o contrato do app Swift não muda, e não é preciso rodar `make fixtures`. O iOS multilinha sai do MVP.

## Mudanças obrigatórias

1. **Neutralizar `prints_dir` e `print_name` da spec enviada.** Hoje uma spec de terceiros leria imagens arbitrárias do disco e as embutiria em base64 no HTML (`service.py:135-139`, `board.py:57,298`, `html_report.py:221,381`).
2. **Forçar `directory` do export para a pasta da sessão.** O padrão de hoje é `~/Documents/Mo baile/Relatórios`, e `prepare_output_dir` aceita qualquer caminho (`security/files.py:64-73`).
3. **Confinar todo `*_path` com `resolve()` + `is_relative_to(sessão)`.** Upload só com nome gerado. O `report.cards_update` fica para a fase 2.
4. **Forçar `source: "file"`** e recusar `platform` fora de `android|ios`.
5. **Allowlist com filtro antes do despacho** (`-32601` para o resto). `report.import` e `report.checklist_export` ficam fora.
6. **Segurança do servidor:**
   - checar `Host` antes de qualquer rota, inclusive `GET /`;
   - CSP `sandbox` mais iframe sandbox no HTML do relatório;
   - download por id opaco;
   - validar `Content-Length` antes de ler;
   - não registrar URL nem token;
   - detectar o BOM de UTF-16 no upload.
7. **A fase 0 do arquiteto** (parser puro mais RPC novo) sai do MVP.

**Tamanho:** cabe em cerca de 450 linhas de produção se cortar `app.css` (reusar o CSS do relatório), o iOS, o filtro da tabela, o `report.cards` e o `/events`.

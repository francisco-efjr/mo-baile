# ADR 0007 — Front web local para Relatório e Analytics fora do macOS

Data: 2026-11-16
Status: aceito

## Contexto

O app nativo é SwiftUI e só roda no macOS (ADR 0002). O dono quer que pessoas
sem Mac usem pelo menos o Relatório (auditoria de tagueamento) e o Analytics.
O motor Python já é a fonte da verdade e o caminho do Relatório é Python puro,
testado no CI em Ubuntu. O Tk legado não tem aba Relatório e está congelado
(ADR 0005). Um port da auditoria para JavaScript duplicaria cerca de 2.000
linhas de regra de negócio. Estudo em
[`docs/melhorias/2026-11-16-liberacao/revisao/multiplataforma.md`](../melhorias/2026-11-16-liberacao/revisao/multiplataforma.md)
e contraprova em
[`contraprova-multiplataforma.md`](../melhorias/2026-11-16-liberacao/revisao/contraprova-multiplataforma.md).

## Decisão

1. **`python -m mobaile.web`** (script `mobaile-web`) sobe um servidor HTTP da
   biblioteca padrão que serve uma página estática (HTML, JS e o CSS do
   relatório, sem CDN) e uma API pequena.
2. **`ReportService` direto, não `EngineServer`.** O servidor RPC expõe a
   tabela inteira e grava recentes em `~/.mobaile`. A web usa uma allowlist
   fechada (`report.spec`, `report.audit`, `report.export`) com o mesmo envelope
   de `rpc/protocol.py`. O Analytics lê um logcat salvo com o parser do
   Relatório (`items_from_text` e `events_from_items`).
3. **O contrato do app nativo não muda:** nenhum método RPC novo, nenhuma
   fixture.
4. **Fronteira de segurança**, aplicada antes de qualquer serviço:
   - bind só em loopback, com porta aleatória;
   - checagem de `Host` (421) e de `Origin` (403) em toda rota;
   - token por sessão no fragmento da URL, enviado em cabeçalho e comparado em
     tempo constante;
   - sem CORS;
   - upload com nome gerado numa pasta temporária da sessão, e todo caminho
     confinado a ela;
   - `prints_dir` da spec neutralizado: uma spec de terceiros não faz o motor
     ler imagem do disco;
   - export sempre numa pasta nova da sessão;
   - download por id opaco e HTML do relatório num iframe com CSP `sandbox` e
     bilhete de uso único;
   - sem log de acesso.

## Consequências

- Windows e Linux ganham Relatório e logcat salvo sem instalar nada além de
  Python e Pillow. Escuta ao vivo, iOS e OCR de prints seguem só no app.
- O servidor web não chama `configure_logging` do motor (usa `O_NOFOLLOW` e
  `fchmod`). A portabilidade é simulada nos testes; falta prova num Windows real.
- Próximas fases, se houver demanda: escuta Android ao vivo por SSE, editor de
  spec na web, job `windows-latest` no CI e, por último, empacotamento.

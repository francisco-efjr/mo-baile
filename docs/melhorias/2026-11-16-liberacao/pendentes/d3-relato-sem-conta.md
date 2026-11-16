# D3. Relato de bug por quem não tem conta no GitHub (decisão do dono)

## Como está nesta rodada

**Relatar um Problema** monta o relato e abre a issue pré-preenchida no GitHub
(formulário `bug-app.yml`). Os anexos ficam numa pasta revelada no Finder, e a
pessoa os arrasta para o GitHub. O app não guarda token nem envia nada sozinho.

O limite: a pessoa precisa de conta no GitHub. Ela é gratuita e o público é
técnico (QA, dev), então é aceitável para o beta.

## Opção recomendada para depois: serviço intermediário pequeno

Para "qualquer pessoa relata, e vira issue":

| Peça | Escolha sugerida | Custo |
|---|---|---|
| Serviço | Cloudflare Worker (ou função equivalente) com `POST /v1/reports` | camada gratuita |
| Credencial | token *fine-grained* do GitHub, só com **Issues: write** no `mo-baile`, guardado como secret do Worker. Nunca no app | — |
| Anexos | repositório **privado** `mo-baile-relatos` (Contents: write), em `anexos/<nº da issue>/`. Anexo de relato pode ter tela com dado pessoal: no privado, só você vê | — |
| Abuso | limite por IP (KV do Worker), teto de tamanho e de tipo, Turnstile opcional | gratuito |
| App | `MoBaileBugReportURL` no Info.plist, gravado pelo empacotamento. Sem ele, o app segue com o caminho atual. O contrato já está na especificação (`revisao/ux-ajuda-beta-bugs.md` §4.7) | ~150 linhas Swift + testes |

O que precisa de você: conta no Cloudflare (ou outro provedor), criar o token
no GitHub e o repositório privado de anexos, e aprovar a publicação do
serviço. Com isso, a próxima rodada implementa o Worker e o lado do app, e
testa ponta a ponta.

## Alternativas

- **Formulário externo** (Google Forms, Tally): sem código, mas o relato não
  vira issue sozinho.
- **E-mail:** expõe um endereço seu no app e não leva anexos pelo `mailto:`.
  Não recomendo.

## O que muda

<!-- Uma ou duas frases. Um assunto por PR. -->

## Por quê

<!-- Problema que resolve. Link da issue: "Fecha #123". -->

## Como testei

<!-- Comandos rodados e resultado. Com aparelho? Qual? -->

## Checklist

- [ ] `make check` passou (versão, lint, bandit, suítes Python, fluxos de QA)
- [ ] `make test-swift` passou
- [ ] Versão subida com `python3 tools/version.py bump ...` e seção nova no `CHANGELOG.md` (ver `docs/VERSIONAMENTO.md`)
- [ ] Contrato RPC mudou? `make fixtures` rodado, fixtures no commit e `docs/PROTOCOLO_RPC.md` atualizado
- [ ] Lógica nova está no motor (`engine/`), não na interface
- [ ] Interface mudou? Capturas clara e escura anexadas
- [ ] Sem segredo, token ou dado pessoal real no diff, nos testes e nas capturas
- [ ] Commits no formato Conventional Commits ([CONTRIBUTING.md](../CONTRIBUTING.md))

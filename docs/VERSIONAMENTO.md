# Versionamento

O Mo baile segue o [Versionamento Semântico](https://semver.org/lang/pt-BR/)
(`MAIOR.MENOR.CORREÇÃO`). **Todo push leva uma versão nova.** Não é sugestão: o
hook de `pre-push` recusa o push, e o CI recusa o PR, quando a versão não sobe.

## Onde a versão mora

- `VERSION`, na raiz, é a fonte única.
- Cópias mantidas por `tools/version.py`: `engine/pyproject.toml`,
  `engine/src/mobaile/__init__.py` (vai para o `engine.hello` e para o
  `Info.plist` do app), `apps/tk-legacy/pyproject.toml` e
  `apps/tk-legacy/mobaile_tk/__init__.py`.
- `CHANGELOG.md` tem uma seção `## [X.Y.Z]` para cada versão.
- Cada versão publicada ganha uma tag anotada `vX.Y.Z`.

## Qual número subir

| Mudou… | Sobe | Exemplo |
|---|---|---|
| Algo que quebra quem usa: protocolo RPC incompatível (`PROTOCOL_VERSION` sobe), formato de arquivo salvo, remoção de recurso | MAIOR | 2.1.0 → 3.0.0 |
| Recurso novo, compatível com o que já existe | MENOR | 2.1.0 → 2.2.0 |
| Correção, ajuste interno, documentação, teste | CORREÇÃO | 2.1.0 → 2.1.1 |

## A cada subida

```bash
python3 tools/version.py bump patch     # ou minor / major
# descreva a mudança na seção nova do CHANGELOG.md
make fixtures                           # a versão aparece nas fixtures do contrato
make check                              # e a suíte Swift, se mexeu no front
git commit -am "chore(release): X.Y.Z"
python3 tools/version.py tag            # tag anotada vX.Y.Z
git push --follow-tags
```

Para conferir sem subir nada: `python3 tools/version.py check`.

## O que é verificado

- **Hook `pre-push`** (`.githooks/pre-push`, ativado por `make hooks`): para cada
  branch enviada, as cópias batem com `VERSION`, o CHANGELOG tem a seção, e a
  versão é maior que a que o remoto já tem naquela branch (branch nova: maior
  que a tag mais alta). Tag `vX.Y.Z` só sobe se o commit dela tiver
  `VERSION` = `X.Y.Z`.
- **CI** (job "Versão"): em PR, a versão do PR é maior que a da branch de
  destino e está consistente.

`git push --no-verify` pula o hook. Fica para emergência, e o CI continua
barrando o PR.

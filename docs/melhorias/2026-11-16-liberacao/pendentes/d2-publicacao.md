# D2. Publicar a 3.24.0 (decisão do dono)

Nada desta rodada foi enviado. A ordem depende da D1.

## Se a D1 for "sim" (repositório recriado com histórico limpo)

Siga `d1-historico-limpo.md`. O passo 4 de lá já publica a `main` e a tag
`v3.24.0`, e a workflow de release gera o zip. Depois confira:

```bash
gh release view v3.24.0 --repo francisco-efjr/mo-baile
gh api repos/francisco-efjr/mo-baile/releases/latest --jq .tag_name
```

## Se a D1 for "não" (mantém o repositório e o histórico)

1. PR desta branch para a `main`. Ele leva também a 3.18.0–3.23.0, que nunca
   foram para a `main`:

   ```bash
   git push -u origin melhoria/2026-11-16-liberacao-publica
   gh pr create --base main --title "Liberação pública (3.24.0)" --body-file docs/melhorias/2026-11-16-liberacao/MELHORIAS.md
   ```

2. Merge manual depois do CI verde (o auto-merge está desligado no repositório).
3. Envie **só** a tag nova, num push separado. Mais de 3 tags num push não
   disparam a workflow:

   ```bash
   git push origin v3.24.0
   ```

4. Feche o PR #5 do dependabot ou suba a versão nele. Hoje ele falha no CI
   porque não sobe a `VERSION`.

## Nos dois casos

- Confira uma vez o relato pelo app: **Ajuda › Relatar um Problema…**, preencha
  e veja se a issue abre preenchida (o formulário `bug-app.yml` só existe no
  GitHub depois do push). Não precisa enviar.
- Crie as labels `origem-app` e `triagem`, se ainda não existirem.
- O aviso de versão só chega a quem instalar a 3.24.0 ou mais nova. Quem tem a
  3.21.0 precisa baixar a nova uma vez.

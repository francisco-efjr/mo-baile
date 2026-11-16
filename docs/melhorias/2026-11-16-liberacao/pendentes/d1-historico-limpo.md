# D1. Publicar com histórico limpo (decisão do dono)

A árvore atual foi neutralizada (LIB-1), mas o histórico do repositório público
ainda guarda versões antigas de arquivos, capturas, mensagens de commit e o
e-mail dos merges feitos pelo GitHub. Reescrever com `push --force` não basta:
o GitHub mantém `refs/pull/*` dos PRs e commits acessíveis por SHA até o
suporte limpar.

## Recomendação: arquivar o repositório atual e recriar com o mesmo nome

Mantém a URL `github.com/francisco-efjr/mo-baile`, que o README, o aviso de
atualização do app e o relato de bugs usam. Não apaga nada de forma
irreversível: o repositório antigo vira privado e guarda tudo.

Estado em 16/11/2026: 0 forks, 0 estrelas, 0 issues abertas, 1 PR aberto do
dependabot.

### Passo local (seguro, pode repetir)

Na branch já integrada (com LIB-1 e as demais melhorias):

```bash
bash docs/melhorias/2026-11-16-liberacao/pendentes/d1-historico-limpo.sh main ~/mo-baile-publico ~/mo-baile-historico.git .privado/replacements.txt
```

O script:
1. guarda o histórico completo em `~/mo-baile-historico.git` (espelho, backup);
2. cria `~/mo-baile-publico` com um único commit. O autor é o seu nome com o
   e-mail noreply do GitHub (`279321095+francisco-efjr@users.noreply.github.com`);
3. procura os termos reais de `.privado/replacements.txt` (pasta ignorada pelo
   git) e para se achar algum.

Confira a olho as imagens que ele lista. O relatório detalhado está em
`.privado/privacidade-relatorio-completo.md`.

### Passos no GitHub (só você)

1. **Antes:** em *Settings › Emails*, marque "Keep my email addresses private"
   e "Block command line pushes that expose my email". Nesta máquina:
   `git config --global user.email 279321095+francisco-efjr@users.noreply.github.com`.
2. **Arquivar o atual:** *Settings* do `mo-baile` › renomear para
   `mo-baile-historico` › *Change visibility* › **Private**.
3. **Criar o novo:** repositório público `mo-baile`, vazio, sem README.
   Criar com o nome antigo cancela o redirecionamento que o GitHub fez no
   passo 2.
4. **Enviar:**

   ```bash
   cd ~/mo-baile-publico
   git remote add origin https://github.com/francisco-efjr/mo-baile.git
   git push -u origin main
   git push origin vX.Y.Z      # uma tag só: dispara a workflow de release
   ```

5. **Reconfigurar:** proteção da `main`, issues ligadas, labels `bug`,
   `triagem` e `origem-app` (o formulário `bug-app.yml` usa as três),
   Dependabot e o secret de release, se houver.
6. **Opcional:** pedir ao suporte do GitHub que remova as visualizações em
   cache do repositório antigo. Cópias feitas por terceiros (arquivos da web)
   não dependem do GitHub.

### Depois

- Esta pasta de trabalho continua com o histórico antigo. Para seguir
  desenvolvendo, use `~/mo-baile-publico` como novo clone, ou troque o
  `origin` daqui e trabalhe só a partir da nova `main`.
- Os releases antigos somem com o repositório antigo. Quem tem a 3.21.0
  instalada não recebe o aviso de versão, porque o aviso nasce na versão
  desta rodada. Essas pessoas precisam baixar a nova uma vez.

## Alternativa: `git filter-repo` no mesmo repositório

Preserva a linha do tempo dos commits, com o texto reescrito. Exige instalar o
`git-filter-repo` (não está nesta máquina), recriar 32 tags e pedir ao suporte
do GitHub a remoção de `refs/pull/*`. O roteiro está no relatório detalhado em
`.privado/`. Não recomendo: mais passos, mais risco de deixar resto, e depende
do suporte.

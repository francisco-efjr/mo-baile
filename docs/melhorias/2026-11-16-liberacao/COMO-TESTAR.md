# Como testar: liberação pública (3.24.0)

Branch: `melhoria/2026-11-16-liberacao-publica`. Para voltar ao estado anterior:
`git switch melhoria/2026-11-12-execucao-projeto`. Para desfazer uma melhoria:
`git revert <commit>` (commits em `MELHORIAS.md`).

## Pré-requisitos

- Mac com Apple Silicon, macOS 14 ou mais novo, Xcode ou Command Line Tools
  com Swift 6.
- Python 3.10+ com Pillow e requests (o mesmo que o app usa).
- Para a parte web em Windows ou Linux: Python 3.10+ com Pillow.

## Portão de qualidade

```bash
make check
```

```bash
make test-swift
```

Esperado: tudo verde. Os números desta rodada estão em `MELHORIAS.md`.

Para reinstalar o app nativo (feche o Mo baile antes):

```bash
make update-native
```

Esperado: o `verify-native` termina em OK, inclusive a conferência nova "Ajuda
embutida igual a `docs/ajuda`".

## LIB-4. Aviso de versão nova

1. Prepare um release falso, só nesta máquina:

   ```bash
   mkdir -p /tmp/feed && printf '{"tag_name":"v99.0.0","html_url":"https://github.com/francisco-efjr/mo-baile/releases","draft":false,"prerelease":false,"assets":[]}' > /tmp/feed/latest.json && python3 -m http.server 8765 --bind 127.0.0.1 --directory /tmp/feed
   ```

2. Em outro terminal, aponte o app para ele (vale até apagar a chave) e abra o
   app:

   ```bash
   defaults write com.qa.mobaile mobaile.update.feedURL http://127.0.0.1:8765/latest.json && defaults delete com.qa.mobaile mobaile.update.lastCheck 2>/dev/null; open "/Applications/Mo baile (nativo).app"
   ```

3. **Esperado:** em poucos segundos, uma faixa "Versão 99.0.0 disponível" no
   topo da coluna central, com **Ver Novidades**, **Baixar** e o **×**
   (Lembrar Amanhã / Ignorar Esta Versão).
4. **Ignorar Esta Versão**, depois feche e abra o app: a faixa não volta.
5. **Mo baile › Buscar Atualizações…**: com o feed falso, a faixa volta (o
   menu ignora a escolha). Com o servidor parado: alerta "Não deu para buscar
   atualizações".
6. *Ajustes › Geral › Atualizações*: desligue e reabra o app. Nenhuma
   requisição chega ao servidor (o terminal dele não mostra `GET`).
7. Ao terminar: `defaults delete com.qa.mobaile mobaile.update.feedURL`.

Critério de aceite: aviso só para versão maior publicada (nunca draft ou
prerelease), escolha persistida, falha de rede silenciosa na abertura,
desligável. Cobertura: `UpdateCheckerTests` (11 testes).

## LIB-2. Ajuda por área

1. Abra o app em qualquer área e aperte **⌘?** (ou o botão **?** no fim da
   barra de ferramentas).
2. **Esperado:** a janela "Ajuda do Mo baile" abre no guia da área atual, com
   as seções O que é, Quando usar, Passo a passo, Exemplo prático, Recursos e
   Problemas comuns.
3. Troque de guia na lista. Use **Buscar na Ajuda** com "HAR": só sobra Rede
   HTTP. **Ir para Rede HTTP** traz a janela principal nessa área.
4. Em Primeiros passos, o link **Relatar um Problema** abre o guia do relato.
5. Os mesmos textos estão em `docs/ajuda/` para quem lê no GitHub.

Critério de aceite: um guia por área, no formato fixo, empacotado no app.
Cobertura: `HelpAndBugReportTests` (formato, atalhos, parser, empacotamento) e
a conferência do `verify-native`.

## LIB-3. Beta e Relatar um Problema

1. **Selo:** a barra de status mostra **Beta** à direita em toda área. A
   barra lateral tem **Relatar Problema** no rodapé.
2. **Aviso da primeira abertura:** aparece uma vez por versão maior. Para ver
   de novo:

   ```bash
   defaults delete com.qa.mobaile mobaile.avisoBetaMajor
   ```

3. **Sobre:** *Mo baile › Sobre o Mo baile* mostra a versão, o aviso de beta,
   o crédito e o commit.
4. **Relato:** **⇧⌘B**. Clique em **Abrir no GitHub…** sem preencher: aparecem
   os erros de Título e de O que aconteceu, e o foco vai ao primeiro. Preencha,
   arraste um `.png` e tente arrastar um `.sh` (recusado com mensagem). Marque
   "Versão do Mo baile e do macOS" e abra **Ver o que será enviado**: a prévia
   mostra exatamente o texto.
5. **Abrir no GitHub…**: o navegador abre `issues/new` com o formulário "Relato
   pelo app" preenchido (só depois que `bug-app.yml` estiver no GitHub). O
   Finder mostra `Documentos › Mo baile › Relatos › <data>` com `relato.md` e o
   anexo. A janela passa para "Falta só enviar no GitHub".
6. **Copiar Relato** copia o mesmo Markdown da prévia.

Critério de aceite: nada sai sem a pessoa clicar, dados do ambiente só se
marcados, anexos validados, aviso de privacidade sempre visível. Cobertura:
`HelpAndBugReportTests` (validação, prévia, URL com os ids do `bug-app.yml`,
corte de relato longo, anexos, pasta do relato, aviso por versão maior, Sobre).

**Não verificado nesta sessão:** o preenchimento real no GitHub. O formulário
novo ainda não está no repositório remoto, e o navegador desta sessão não tem
login. A documentação do GitHub confirma o preenchimento de campos de issue
form pela URL. Conferir uma vez depois do push.

## LIB-1. Árvore sem dado pessoal ou de empresa

```bash
git grep -n -I -E '/Users/[a-z]+\.[a-z]+|-MacBook[A-Za-z0-9-]*\.local|@gmail\.com'
```

Esperado: nenhuma linha. A busca completa, com a lista de termos reais, usa o
arquivo fora do git:

```bash
sed -e 's/==>.*$//' -e 's/^regex://' -e 's/^literal://' .privado/replacements.txt | grep -v '^#' | grep -v '^$' > /tmp/termos.txt && git grep -n -I -i -P -f /tmp/termos.txt
```

Esperado: nenhuma linha. Seu nome só aparece como crédito (LICENSE, README,
Sobre e autores do `pyproject`).

Capturas do catálogo que mostravam a saudação com nome ou a pasta do
repositório saíram (02c, 02d, 02e, 02g, 13 e as duas da Início em
`docs/design/home`). Para recapturar sem dado: `docs/design/telas/CHECKLIST.md`.

## LIB-5. Relatório e Analytics no navegador

```bash
PYTHONPATH=engine/src /usr/local/bin/python3 -m mobaile.web
```

1. O navegador abre em `http://127.0.0.1:<porta>/#t=<chave>`, com o aviso
   "Produto em desenvolvimento" no topo.
2. **Relatório:** escolha uma spec JSON e um log, e clique em **Auditar**. O
   resumo e o HTML aparecem; os botões baixam HTML, MD e TSV.
3. **Analytics:** escolha um logcat salvo (`adb logcat -d > log.txt`). A tabela
   mostra os eventos; os botões baixam TSV e JSON.
4. `Ctrl+C` encerra e apaga a pasta temporária da sessão.

Segurança conferida nesta sessão com o servidor no ar (`curl`): sem chave dá
401, `Host` forjado dá 421, `Origin` forjado dá 403, método fora da lista dá
`-32601`, não há cabeçalho de CORS e a porta escuta só em `127.0.0.1`. A suíte
(`engine/tests/unit/test_web_handlers.py`,
`engine/tests/integration/test_web_server.py`) cobre isso e a paridade com o
app.

**Não verificado:** um Windows de verdade. Windows (PowerShell), na pasta do
código:

```powershell
py -m pip install Pillow requests
$env:PYTHONPATH = "engine\src"; py -m mobaile.web
```

## LIB-6. Documentação pública

- README: aviso de beta no topo, requisito Apple Silicon, primeira abertura
  pelo caminho da Apple, seções Atualizações, Windows e Linux, Ajuda e relato
  de bugs.
- Notas do release (`release.yml`): mesmo aviso e mesmo caminho.
- `docs/SEGURANCA.md`: o que sai da máquina.

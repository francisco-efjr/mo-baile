---
area: analytics
titulo: Analytics
resumo: Capture eventos de Firebase Analytics em tempo real e busque por evento e parâmetro.
precisa: aparelho conectado; app com debug do Firebase
---

## O que é

Analytics escuta os eventos de Firebase Analytics que o app dispara e os mostra numa tabela, com seus parâmetros.

## Quando usar

- Para confirmar que um evento disparou na hora certa.
- Para conferir os parâmetros de um evento.
- Para gerar o log que o Relatório audita.

## Passo a passo

1. Abra **Analytics** (⌘3) com o aparelho conectado.
2. No iOS, escolha a **Origem**: Automático, Simulador ou iPhone por cabo.
3. Clique em **Iniciar Escuta** e navegue no app.
4. Busque na barra, por exemplo `evento:screen_view` ou `param:chave=valor`.
5. Clique em **Exportar JSON…** para salvar o log.

## Exemplo prático

Você precisa validar o `screen_view` ao abrir o carrinho do DemoApp. Clique em **Iniciar Escuta**, abra o carrinho no aparelho e busque `evento:screen_view`. Confira o nome da tela nos parâmetros. Quando estiver satisfeito, clique em **Exportar JSON…** e abra o arquivo em **Relatório** para comparar com a spec.

> Dica: fora do macOS, você ainda audita um log salvo no navegador com `python -m mobaile.web`. Veja `docs/INSTALACAO.md`.

## Recursos

- **Iniciar Escuta** / **Parar Escuta**: liga e desliga a captura de eventos.
- **Origem**: no iOS, escolhe Automático, Simulador ou iPhone por cabo. Pare a escuta antes de trocar.
- **Busca**: filtra por `evento:` e `param:` na barra de ferramentas.
- **Copiar TSV**: copia a tabela para colar no Google Planilhas.
- **Exportar JSON…**: salva o log como `log_obtido.json`.
- **Limpar**: esvazia a tabela para uma nova captura.

## Problemas comuns

- **Nenhum evento aparece.** Confirme que o app está com o debug do Firebase ligado e, no iOS, que a **Origem** está certa.
- **O iPhone por cabo não está disponível.** Instale o pymobiledevice3 pelo Ambiente.
- **Troquei a Origem e nada mudou.** Clique em **Parar Escuta** e inicie de novo.

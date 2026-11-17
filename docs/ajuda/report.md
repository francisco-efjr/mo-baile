---
area: report
titulo: Relatório
resumo: Audite um log de eventos contra a spec de tagueamento, parâmetro por parâmetro.
precisa: nada
---

## O que é

O Relatório compara os eventos de um log com a spec de tagueamento (os cards do Figma) e mostra o que bate e o que diverge.

> Dica: esta área não precisa de aparelho. Fora do macOS, use o Relatório e a leitura de logcat salvo no navegador com `python -m mobaile.web` (veja `docs/INSTALACAO.md`).

## Quando usar

- Para validar o tagueamento de uma tela antes de liberar.
- Para criar uma spec a partir dos prints do Figma.
- Para gerar um relatório e um bug prontos para o time.

## Passo a passo

1. Abra **Relatório** (⌘4) e clique em **Importar Prints do Figma…** ou **Abrir Spec…**.
2. Corrija o que a leitura dos prints errou em **Editar Spec**.
3. Em **Origem dos eventos**, escolha **Escolher Arquivo de Log…** ou os eventos capturados.
4. Escolha a **Plataforma auditada** e clique em **Auditar**.
5. Filtre por **Divergentes** e use **Copiar Bug** nos itens com problema.

## Exemplo prático

Você precisa auditar a tela de login do DemoApp contra os cards do Figma. Importe os prints, abra **Editar Spec** e ajuste o nome de um parâmetro que a leitura trocou. Escolha o `log_obtido.json` exportado do Analytics, confira a plataforma e clique em **Auditar**. Filtre por **Divergentes**, abra o item e compare Obtido x Esperado. Clique em **Copiar Bug** para colar o modelo no Jira ou no Azure.

## Recursos

- **Importar Prints do Figma…**: cria um rascunho da spec lendo os prints.
- **Abrir Spec…**: abre uma spec existente; **Reler Spec** atualiza após edição.
- **Editar Spec**: edita a spec em Quadro ou Tabela e salva.
- **Origem dos eventos**: usa eventos capturados ou um arquivo de log: `log_obtido.json`, logcat salvo ou o TSV de uma exploração do Google Analytics (GA4).
- **Auditar**: calcula a conformidade em % e classifica cada evento.
- **Filtros**: Todas, Pedem Ação, Divergentes, Não Disparadas, OK e Fora da Spec.
- **Copiar Bug**: copia o modelo de bug do time para o app auditado.
- **Exportar**: salva em HTML, Markdown, TSV e Excalidraw.

## Problemas comuns

- **Tudo aparece como Não Disparada.** Confira a **Plataforma auditada**: ela precisa ser a do log.
- **Com o TSV do Analytics, vários parâmetros aparecem como não exportado.** O export só traz as dimensões escolhidas na exploração (ex.: `firebase_screen`, `flow_name`, `flow_step`). Só elas são conferidas; para conferir mais, inclua as dimensões na exploração e exporte de novo.
- **Importar prints está indisponível.** Instale o Swift das Command Line Tools pelo Ambiente.
- **O OCR leu um parâmetro errado.** Corrija em **Editar Spec** e clique em **Auditar** de novo.

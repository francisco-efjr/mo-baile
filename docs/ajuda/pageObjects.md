---
area: pageObjects
titulo: Page Objects
resumo: Espelhe o aparelho, grave passos com cliques e transforme-os em código e flows.
precisa: aparelho conectado
---

## O que é

Page Objects espelha a tela do aparelho. Cada clique no espelho toca no aparelho e grava um passo, e os passos viram código.

## Quando usar

- Para criar um teste sem escrever o locator na mão.
- Para descobrir o ID ou o XPath de um elemento.
- Para exportar o roteiro como flow do Maestro.

## Passo a passo

1. Abra **Page Objects** (⌘1) e escolha o aparelho na barra de cima.
2. Escolha o seletor: **Auto**, **ID**, **XPath** ou **Coords**.
3. Clique no espelho para tocar e gravar. Os passos aparecem em Fluxo.
4. Confira o código no editor e salve com ⌘S.
5. Rode o roteiro com **Rodar Automação** (⌘R) ou clique em **Exportar Flow…** em **Estrutura…**.

## Exemplo prático

Você quer gravar "abrir o app e tocar em Entrar" no DemoApp. Deixe o seletor em **Auto** e clique no botão Entrar no espelho. O passo aparece em Fluxo e o código surge no arquivo de ações. Salve com ⌘S e rode com ⌘R para ver o aparelho repetir o toque. Para levar o roteiro ao Maestro, abra **Estrutura…** e clique em **Exportar Flow…**.

## Recursos

- **Espelho**: mostra a tela ao vivo; o clique toca no aparelho e grava o passo.
- **Hierarquia** e **Atributos**: mostram a árvore de elementos; **Copiar Tudo** copia os atributos.
- **Seletor**: define como o app escolhe o locator de cada passo.
- **Gravar do Aparelho**: grava os toques feitos direto no aparelho. No iOS, só no Simulator.
- **Gravar a Tela**: grava o vídeo da tela do aparelho.
- **Espelho 60 FPS**: espelho mais fluido no Android, com scrcpy.
- **Estrutura…**: resume o fluxo, copia o resumo e exporta o flow.
- **Correlação**: mostra o tráfego e os eventos do último passo.

## Problemas comuns

- **O iPhone físico não grava os toques.** Grave pelo clique no espelho. A escuta direta no iPhone por cabo não está disponível.
- **O espelho 60 FPS fica cinza.** Instale o scrcpy pelo Ambiente e tente de novo.
- **A hierarquia vem vazia.** Instale o driver UiAutomator2 no Ambiente (Android) ou confira o Appium (iOS).

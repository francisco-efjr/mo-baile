---
area: comecando
titulo: Começando
resumo: Prepare a máquina, conecte um aparelho e faça sua primeira gravação em poucos minutos.
precisa: nada
---

## O que é

O Mo baile espelha o aparelho, grava passos, mostra rede e analytics e audita tagueamento. Tudo roda nesta máquina.

> Atenção: o Mo baile é um produto em desenvolvimento e pode ter bugs. Se algo falhar, use [Relatar um Problema](mobaile://ajuda/relatar-problema).

## Quando usar

- Na primeira vez que abrir o app.
- Para saber qual área abrir para cada tarefa.

## Passo a passo

1. Abra **Ambiente** (⌘5) e instale o que estiver pendente com **Instalar no Terminal…**.
2. Conecte um aparelho (cabo, emulador ou simulador) e escolha-o na barra de cima.
3. Abra **Page Objects** (⌘1) e clique no espelho: cada clique toca no aparelho e grava um passo.
4. Abra **Rede HTTP** (⌘2) ou **Analytics** (⌘3) para ver o que o app envia.
5. Abra **Relatório** (⌘4) quando quiser auditar um log. Essa área não precisa de aparelho.

## Exemplo prático

Você quer gravar o login do DemoApp. Confirme no Ambiente que nada está pendente, conecte o celular e abra Page Objects. Clique no campo de e-mail, no de senha e em **Entrar**. Em poucos cliques você tem os passos no Fluxo, e o código aparece ao lado. É a sua primeira gravação.

## Recursos

- **Início** (⌘0): escolhe o aparelho e mostra pendências.
- **Page Objects** (⌘1): espelho, hierarquia e editor de código.
- **Rede HTTP** (⌘2): tráfego HTTP do aparelho, com exportação em HAR.
- **Analytics** (⌘3): eventos de Firebase Analytics em tempo real.
- **Relatório** (⌘4): audita eventos contra a spec.
- **Ambiente** (⌘5): mostra o que está instalado e instala o que falta.
- **Execução** (⌘6): roda o projeto de automação (behave) do seu time.

## Problemas comuns

- **O aparelho não aparece.** Abra o Ambiente e confira o `adb` (Android) ou o Xcode (iOS). Depois, atualize a lista no Início.
- **Uma área diz que falta algo.** Instale o item no Ambiente e clique em **Verificar de Novo**.
- **Não sei por onde começar.** Abra o Início (⌘0): ele mostra o próximo passo.

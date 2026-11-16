---
area: environment
titulo: Ambiente
resumo: Veja o que está instalado, o que cada área precisa e instale o que falta.
precisa: nada
---

## O que é

O Ambiente mostra o estado desta máquina: o que está instalado, o que falta e quais áreas funcionam por causa disso.

## Quando usar

- Na primeira vez que usar o app.
- Quando uma área diz que falta algo.
- Depois de instalar uma ferramenta, para confirmar que o app a enxerga.

## Passo a passo

1. Abra **Ambiente** (⌘5).
2. Leia o resumo por grupo e a lista de pendências.
3. Clique em **Instalar no Terminal…** na pendência. Se preferir, use **Copiar Comando**.
4. Termine a instalação no Terminal.
5. Volte ao app e clique em **Verificar de Novo**.

## Exemplo prático

No Android, nenhuma área funciona. Abra o Ambiente e leia a pendência: falta o `adb`. Clique em **Instalar no Terminal…** e acompanhe a instalação. Quando terminar, volte e clique em **Verificar de Novo**. A pendência some e a matriz "O que funciona em cada área" passa a mostrar Page Objects, Rede e Analytics como prontos para o Android.

## Recursos

- **Verificar de Novo**: refaz a checagem e mostra a hora da última.
- **Resumo por grupo**: mostra quantos itens de cada grupo estão em ordem.
- **Pendências**: lista o que falta, com a ação para resolver.
- **Instalar no Terminal…**: abre o Terminal com o comando de instalação.
- **Copiar Comando**: copia o comando para você rodar onde preferir.
- **O que funciona em cada área**: cruza as áreas com a plataforma.
- **Componentes**: lista cada ferramenta com a versão encontrada.

## Problemas comuns

- **Instalei e continua pendente.** Clique em **Verificar de Novo**. Se persistir, confira o Python do motor.
- **Não há opção de iOS.** O iOS exige um Mac com o Xcode completo instalado.
- **O Terminal pede senha.** É o instalador do sistema. Digite apenas no Terminal, nunca no app.

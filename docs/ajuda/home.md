---
area: home
titulo: Início
resumo: Escolha o aparelho, resolva pendências, retome o trabalho e leia as novidades.
precisa: nada
---

## O que é

O Início é a porta de entrada do app. Ele mostra o aparelho escolhido, o que falta instalar e o que você estava fazendo.

## Quando usar

- Ao abrir o app, para ver se está tudo pronto.
- Para pular direto a Page Objects, Rede HTTP ou Analytics com o aparelho certo.
- Para voltar ao que você fazia antes de fechar o app.

## Passo a passo

1. Abra **Início** (⌘0).
2. Confira o aparelho no cartão. Se houver pendência, clique em **Resolver…**.
3. Escolha uma ação do cartão: **Espelhar e Gravar**, **Ver Rede HTTP** ou **Escutar Analytics**.
4. Para retomar o trabalho, use **Continuar de onde parou**; **Ver Tudo** lista o histórico.
5. Para rodar um teste pronto, clique em **Rodar Flow…** e escolha um arquivo `.yaml` do Maestro.

## Exemplo prático

Você abre o app pela manhã e o Início mostra "Tudo pronto" com o seu Android escolhido. Em vez de procurar a área certa, clique em **Espelhar e Gravar**. O app abre Page Objects com o aparelho escolhido, e você continua o roteiro de ontem em **Continuar de onde parou**. 

## Recursos

- **Aparelho**: escolhe o aparelho ativo e aponta o que impede de usá-lo.
- **Espelhar e Gravar**: abre Page Objects com o aparelho escolhido.
- **Ver Rede HTTP**: abre o tráfego do aparelho escolhido.
- **Escutar Analytics**: abre Analytics para escutar os eventos.
- **Rodar Flow…**: executa um `.yaml` do Maestro, sem internet.
- **Continuar de onde parou**: reabre a última área e o contexto de trabalho.
- **Novidades**: mostra o que mudou na versão; dá para dispensar até a próxima.

## Problemas comuns

- **O aparelho não aparece.** Use Dispositivo › **Atualizar Lista de Aparelhos** (⇧⌘R). Se continuar, abra o Ambiente.
- **O Início fica em "Primeira vez".** Clique em **Preparar…** na sua plataforma e depois em **Verificar de Novo** no Ambiente.
- **O motor está parado.** Siga a instrução da própria tela: ela diz qual Python instalar.

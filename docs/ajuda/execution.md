---
area: execution
titulo: Execução
resumo: Rode o projeto de automação (behave) do seu time, com Doctor, console e vídeo.
precisa: projeto behave; aparelho ao rodar
---

## O que é

A Execução roda o `main` do projeto de automação do seu time, como a run configuration do PyCharm. Ela mostra o resultado no console e pode gravar vídeo.

> Atenção: rodar executa o código do projeto nesta máquina, com as suas permissões. Confie só em projetos que você conhece.

## Quando usar

- Para rodar a suíte do time sem abrir o PyCharm.
- Para checar o interpretador e o behave antes de rodar.
- Para gravar o vídeo de uma execução.

## Passo a passo

1. Abra **Execução** (⌘6) e clique em **Abrir Projeto…**.
2. Confira o interpretador e o resultado do **Doctor**; use **Confiar no Projeto e Verificar…** na primeira vez.
3. Escolha o **Aparelho** e, se quiser, marque **Gravar vídeo**.
4. Clique em **Rodar** e acompanhe o **Console**.
5. Ao terminar, use **Abrir Vídeo** ou **Abrir Pasta da Execução**.

## Exemplo prático

Você quer rodar o projeto behave do seu time no celular da bancada. Abra o projeto, confira o Doctor e escolha o aparelho. Marque **Gravar vídeo** e clique em **Rodar**. No Console, busque a falha com ⌘F e use **Ir para o Fim** para ver o resultado. Depois clique em **Abrir Vídeo** para ver o que aconteceu na tela.

## Recursos

- **Abrir Projeto…**: escolhe a pasta do projeto; os recentes ficam em Abertos antes.
- **Confiável** e **Esquecer**: mostram e retiram a confiança no projeto.
- **Aparelho**: escolhe o alvo; Automático usa o aparelho da config ou do app.
- **Gravar vídeo**: grava a tela durante a execução.
- **Rodar** / **Parar**: inicia e interrompe a execução.
- **Doctor**: confere o interpretador e o behave; **Verificar de Novo** refaz a checagem.
- **Console**: mostra a saída, com busca em ⌘F.
- **Abrir Pasta da Execução**: abre no Finder os arquivos da execução.

## Problemas comuns

- **O botão Rodar está bloqueado.** Passe o mouse no cadeado: ele explica o que falta.
- **O interpretador não tem behave.** Escolha outro Python e clique em **Usar**, ou **Voltar à Detecção**.
- **A config é de nuvem.** Configs de nuvem não rodam aqui; escolha uma config local.

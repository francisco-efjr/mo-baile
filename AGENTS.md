# Instruções para agentes

Vale para qualquer agente ou assistente que trabalhe neste repositório: Claude
Code, Antigravity, Cursor, Codex, subagentes e equipes de agentes. As regras de
arquitetura estão em [docs/ARQUITETURA.md](docs/ARQUITETURA.md) e
[docs/adr/](docs/adr/). O contrato entre motor e front está em
[docs/PROTOCOLO_RPC.md](docs/PROTOCOLO_RPC.md).

## Obrigatório: deixar o app nativo atualizado nesta máquina

O dono do projeto usa o **`/Applications/Mo baile (nativo).app`** no dia a dia. Esse
app carrega uma cópia do motor (`Contents/Resources/engine/src`) e a interface Swift
compilada no momento do empacotamento. Ele **não lê o código do repositório**: uma
mudança que não foi reempacotada simplesmente não existe para quem usa o app.

Por isso, **toda tarefa que altera algo que vai dentro do app só termina depois que
o app instalado estiver atualizado e verificado.** Isso vale para mudanças em
`engine/src/`, `apps/MoBaile/` ou `assets/`.

```bash
make update-native    # = make build-native + make verify-native
```

- `make build-native` roda `swift test`, compila em modo release e substitui
  **apenas** o `Mo baile (nativo).app`. Se um teste falhar, ele aborta. Nesse caso
  a tarefa não está pronta.
- `make verify-native` prova três coisas:
  - a versão instalada é igual a `VERSION`;
  - o motor embutido é idêntico a `engine/src`;
  - o Python que o app vai usar sobe esse motor e responde ao `engine.hello`.

  Um "OK" desse alvo é a evidência que vai no relatório final.

Cuidados:

1. **Feche o app antes.** O empacotamento apaga e recria o bundle, e o app aberto
   perde o motor que estava usando. Se `pgrep -f "Mo baile (nativo)"` encontrar o
   app rodando, peça ao dono para fechá-lo. Não encerre o processo por conta própria.
2. **Nunca substitua o `Mo baile.app`.** Esse é o app Tkinter. Nada de
   `APP_NAME="Mo baile"`, a menos que o dono peça explicitamente.
3. **Atualize depois de integrar.** Empacote a partir da branch onde o trabalho
   foi integrado, e não de um worktree temporário. Assim o app reflete o que foi
   entregue.
4. **Dependência nova do motor também vai para o Python do app.** Fora do
   repositório, o app usa o primeiro Python que encontrar entre
   `/opt/homebrew/bin/python3`, `/usr/local/bin/python3` e `/usr/bin/python3`. Se
   a dependência nova estiver só no `.venv`, o `verify-native` falha no handshake.
5. **Se não der para atualizar**, diga no relatório final exatamente o que
   impediu e qual comando o dono precisa rodar. Pode ser falta de permissão,
   teste falhando ou app aberto. Nunca dê a tarefa como concluída sem isso.

Mudanças só de documentação, ou de testes e ferramentas que não entram no bundle,
não exigem reempacotar. Mesmo assim, rode `make verify-native` se houver dúvida.

## Demais regras do projeto

- **Versionamento:** todo push leva versão nova em SemVer (`VERSION`,
  `CHANGELOG.md`, `make fixtures`, tag `vX.Y.Z`). O hook de `pre-push` e o CI
  barram. Detalhes em [docs/VERSIONAMENTO.md](docs/VERSIONAMENTO.md).
- **Portão de qualidade:** `make check` e `make test-swift` passando antes de
  qualquer commit. Contrato RPC mudou: rode `make fixtures` e atualize
  `docs/PROTOCOLO_RPC.md`.
- **Pendências em aberto:** antes de começar uma melhoria, confira
  [docs/RODADA_2026-10-05_PENDENCIAS.md](docs/RODADA_2026-10-05_PENDENCIAS.md).

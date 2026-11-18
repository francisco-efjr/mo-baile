# ADR 0008 — Atualização no lugar com assinatura própria

Data: 2026-11-18
Status: aceito

## Contexto

Desde a 3.24.0 o app avisa de versão nova (LIB-4): uma faixa com **Baixar**
que abre o zip no navegador. Atualizar exigia baixar, fechar o app, trocar o
bundle em Aplicativos e passar de novo pelo **Abrir Mesmo Assim**, porque o
zip baixado pelo navegador entra em quarentena e o app não é notarizado. O dono
quer que o colega receba uma notificação e atualize com um clique.

A revisão de distribuição de 16/11
([`distribuicao.md`](../melhorias/2026-11-16-liberacao/revisao/distribuicao.md))
comparou três caminhos: (a) só aviso, (b) atualização no lugar feita pelo
próprio app e (c) Sparkle. Ela recomendou (a) porque, sem Developer ID,
(b) dependeria do `.sha256` publicado no mesmo release (integridade, não
autenticidade, DIST-12). A Sparkle, com assinatura ad-hoc, pode não carregar o
framework, e o empacotamento monta o bundle à mão, sem `Frameworks/`.

## Decisão

1. **Atualização no lugar, sem dependência nova** (`UpdateInstaller.swift`). Em
   dois cliques: **Atualizar** baixa e confere, com o app em uso;
   **Reiniciar e Atualizar** troca e reabre. Assim a pessoa escolhe a hora de
   fechar e salva o que estiver aberto.
2. **Autenticidade por assinatura Ed25519 própria** (`UpdateSignature.swift`,
   CryptoKit). O workflow de release assina o zip com o secret
   `MOBAILE_UPDATE_SIGNING_KEY` e publica `<zip>.sig`. O app só instala se a
   assinatura bater com uma das chaves públicas embutidas. A lista aceita mais
   de uma chave, para permitir a troca. O passo do workflow confere a
   assinatura contra o próprio `UpdateSignature.swift`, o que impede publicar
   um release que o app recusaria.
3. **Validação do app novo antes da troca:** um único `.app` no zip, o mesmo
   `CFBundleIdentifier`, a versão igual à da tag e maior que a instalada, o
   executável presente e `codesign --verify --deep --strict` passando.
4. **Troca por rename no mesmo volume.** O zip é extraído numa pasta
   `itemReplacementDirectory` ao lado do app. O app em uso vira `anterior.app`
   nessa pasta e o novo entra no mesmo caminho. Se o segundo passo falhar, o
   anterior volta. Depois o app sai pelo `NSApp.terminate`, porque o
   encerramento ordenado desfaz o proxy do aparelho. O `terminate` vai pelo
   runloop (`perform(_:with:afterDelay:)`): chamado de dentro de uma tarefa do
   MainActor, o `.terminateLater` do `AppDelegate` esperava uma resposta que
   nunca chegava e o app travava. O teste de ponta a ponta pegou isso.
5. **Ajudante que reabre fora do grupo de processos do app.** Um `/bin/sh`
   sobe por `posix_spawn` com `POSIX_SPAWN_SETPGROUP` e
   `POSIX_SPAWN_CLOEXEC_DEFAULT`, sem herdar o pipe do motor. Ele espera o PID
   sair (até 60 s), roda `open` no app e apaga a pasta temporária.
6. **Quarentena:** o `URLSession` de um app sem sandbox não marca o arquivo
   baixado, e o app ainda roda `xattr -dr com.apple.quarantine` no app
   extraído. O Gatekeeper, portanto, não avalia a versão nova. Isso é
   proposital: a confiança vem da assinatura Ed25519, conferida antes. É o
   mesmo modelo da Sparkle sem Developer ID.
7. **Quando não dá, cai no caminho antigo:** app transladado (rodando de
   Downloads), pasta sem escrita, release sem `.sig` ou URL fora de HTTPS. Nesses
   casos o botão vira **Baixar**. HTTP só é aceito em loopback, para o teste
   local com `MOBAILE_UPDATE_URL`.
8. **Consulta a cada duas horas com o app aberto** (antes era uma por dia ao
   abrir). A notificação do macOS (`UpdateNotifier.swift`) sai uma vez por
   versão, com os botões Atualizar e Lembrar Amanhã. Sem permissão de
   notificação, fica só a faixa.

## Consequências

- Quem está na 3.25.0 ou antes atualiza para a 3.26.0 à mão, uma vez. As
  versões seguintes chegam pelo clique.
- **A chave privada é um segredo de distribuição.** Ela fica no secret do
  repositório e numa cópia do dono, fora do git (`.privado/`). Perder a chave
  obriga a publicar uma versão com chave nova, e quem já tem o app atualiza
  essa versão à mão. Vazar a chave permite a quem controlar o release distribuir
  código que o app instala. Nesse caso, trocar a chave pelo mesmo caminho.
- Sem Developer ID, a identidade do app muda a cada versão e o macOS pode pedir
  de novo as permissões do TCC (DIST-05).
- Uma dependência nova do motor não vai junto: o zip leva o motor, não o
  Python. Mudança assim continua exigindo o aviso nas notas da versão.
- No macOS 13 ou mais novo, a proteção "Gerenciamento de Apps" pode barrar a
  troca. O erro vira mensagem na faixa, que aponta o ajuste e oferece Baixar.
- Com Developer ID (PROP-5), a Sparkle volta a ser opção. A assinatura
  Ed25519 é a mesma ideia e não fecha essa porta.
- Teste local sem publicar: `docs/RELEASE.md`, seção "Testar a atualização sem
  publicar".

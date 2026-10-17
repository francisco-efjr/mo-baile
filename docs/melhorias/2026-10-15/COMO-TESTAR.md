# Como testar — Rodada 2 (3.6.0)

## Pré-requisitos

- macOS 14+, Swift 6.2 (Xcode 26), Python do `.venv`.
- Para o manual: um aparelho Android e um simulador iOS com WebDriverAgent
  (via Appium) no ar. Para o MJPEG, o WDA precisa servir na porta 9100 (padrão
  dele; o motor lê `WDA_MJPEG_PORT`).

## Automático

```bash
make check          # versão, ruff, bandit, pytest, fluxos de QA, fixtures
make test-swift     # suíte do front
```

Resultado esperado: tudo verde. Números desta máquina no `MELHORIAS.md`.

```bash
.venv/bin/python tools/bench_frame.py   # PNG × JPEG num quadro 900×2000
```

## Manual (aparelho real)

1. **F3 · digitação iOS.** No simulador, grave um toque num campo de texto e
   digite nele (a escuta passiva guarda o texto). Rode o fluxo. Esperado: o
   campo recebe o texto; o `flow.log` mostra "Digitando N caracteres" e nunca
   o valor. Apague o texto do passo (passo sem texto) e rode de novo:
   esperado, o passo falha com "sem texto gravado", sem tocar o campo como se
   fosse sucesso.
2. **F11 · espelho.** Android: ligue o espelho; o `engine.log`/stderr mostra
   quadros `jpeg`, e a barra de status mostra fps maior que antes na mesma
   tela. iOS com WDA no ar: `stream.start` responde `source: wda_mjpeg` (ver
   no log do motor "Espelho iOS pelo MJPEG"); desligue o WDA no meio: o
   espelho cai para o `simctl` sem travar. `STREAM_FORMAT=png` no ambiente
   volta ao PNG.
3. **F8 · diagnóstico.** Com o proxy desligado, clique em "Por que não vejo
   tráfego?": esperado "O proxy está desligado". Ligue o proxy e tire o cabo:
   esperado "O aparelho não está apontando para o proxy" com o comando adb.
   Com um app que faz pinning: esperado "conexões HTTPS recusadas". Sessão
   iOS com proxy: esperado "só configura Android".
4. **F12 · busca.** Na Rede, digite `status:4xx` e depois `metodo:POST
   tipo:json`; troque o escopo para Erros e Mídia. Em Analytics,
   `evento:screen param:ga_screen=home`. Arraste a largura de uma coluna,
   feche e reabra o app: esperado, a largura volta igual.
5. **F5 · correlação.** Com proxy e analytics ligados, grave um toque em
   "Entrar" num app com login. Na barra lateral, botão direito no passo →
   "Ver na Rede": esperado, só o POST de autenticação na tabela e o chip
   "Passo N · Entrar · 1 requisição · 1 evento". "Ver em Analytics": só o
   evento `login`. "Mostrar tudo" volta à lista completa. Troque de área com
   ⌘2/⌘3: o chip continua.

## Como desfazer

```bash
git switch melhoria/2026-10-14-rodada1-comportamento
# ou, por funcionalidade:
git revert <commit>
```

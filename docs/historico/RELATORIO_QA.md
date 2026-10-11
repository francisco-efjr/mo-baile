# Relatório de QA — quatro fluxos principais

Data: 07/09/2026
Método: execução automatizada de ponta a ponta, com `adb`, `xcrun` e
WebDriverAgent falsos no PATH e servidor HTTPS real com certificado próprio.

O harness sobe o motor de verdade como subprocesso e fala o mesmo JSON-RPC que
o front SwiftUI fala. Não é mock do motor: é o motor. O que passa aqui é o que
a interface vai ver.

Reproduzir: `make qa`

## Resultado

| Fluxo | Verificações | Resultado |
|---|---|---|
| 1 · sem dispositivo | 19 | todas passaram |
| 2 · só iOS | 31 | todas passaram |
| 3 · só Android | 35 | todas passaram |
| 4 · HTTPS | 34 | todas passaram |
| **Total** | **119** | **após corrigir 3 defeitos** |

---

## Defeitos encontrados e corrigidos

### DEFEITO 1 — recusa silenciosa na digitação

**Severidade: média. Fluxo 3.**

`input.text` com texto contendo caractere de controle devolvia `{"ok": false}`,
sem motivo nenhum. A validação existia no adapter, mas ele a engolia e
convertia em `False`, e a razão se perdia no caminho.

Do ponto de vista de quem usa: digitou, não aconteceu nada, nenhuma explicação.

**Correção.** A fronteira RPC valida a própria entrada, exatamente como já fazia
com coordenada. A recusa virou erro tipado com mensagem.

Regressão: `test_texto_invalido_vira_erro_tipado_e_nao_ok_falso`.

### DEFEITO 2 — cookie de sessão vazando da resposta

**Severidade: alta. Fluxo 4.**

Os headers da **requisição** eram redigidos, os da **resposta** não. `Set-Cookie`
está na lista de sensíveis desde o começo, mas nunca era aplicado ao caminho de
volta.

Na prática, o cookie de sessão que o servidor acabou de emitir aparecia inteiro
na tabela de tráfego e ia junto na exportação HAR. Um HAR compartilhado com o
time carregaria a sessão autenticada de quem gravou.

**Correção.** `redact_headers` aplicado também aos headers de resposta.

Regressão: `test_header_sensivel_da_resposta_tambem_e_redigido`, que também
confirma que header inocente continua visível.

### DEFEITO 3 — ferramenta sem permissão derruba a chamada

**Severidade: média. Achado por acidente durante o setup.**

Com o `adb` presente no PATH mas sem bit de execução, `devices.list` respondia
erro interno `-32603` com stack trace, em vez de erro tipado.

O cenário é real: acontece ao copiar o Android SDK entre máquinas, ou com
binário em quarentena pelo Gatekeeper. O usuário veria "erro interno no motor"
e não teria como saber que o problema era permissão de arquivo.

`_run_cmd` tratava `FileNotFoundError` e deixava `PermissionError` passar.

**Correção.** `PermissionError` e `OSError` viram `ToolNotFoundError` com a
mensagem dizendo qual binário e qual o problema. Mesma classe de falha coberta
no adapter iOS.

Regressão: `test_adb_sem_permissao_vira_erro_tipado` e
`test_listagem_degrada_sem_derrubar`.

---

## O que foi confirmado funcionando

### Fluxo 1 · sem dispositivo

O diagnóstico não mente. Com adb e xcrun presentes mas nenhum aparelho, ele
reporta ferramenta instalada, nenhum dispositivo, e sugere ligar simulador ou
emulador. Nenhuma plataforma se declara pronta.

Operações que exigem alvo falham com erro tipado e mensagem que fala em
dispositivo, em vez de travar ou estourar.

`simulators.list` e `emulators.list` funcionam sem device, que é o que permite a
tela de estado vazio oferecer "abrir simulador".

### Fluxo 2 · só iOS

Simulador detectado com nome, captura devolvendo PNG real com redimensionamento
correto e resolução de origem preservada, hierarquia do WebDriverAgent parseada
com bounds convertidos de `x/y/width/height` para retângulo, `element_at`
acertando o botão no centro dele.

O toque chega ao WDA de verdade: o servidor falso registrou um `POST
/wda/tap` com as coordenadas exatas. A gravação de passo gera nome de variável,
linha de Page Object e bloco de ação.

O streaming entrega quadro por notificação, sem `id`, respeitando o `max_width`.
Em tela parada: **8 quadros capturados, 1 emitido, 7 descartados**.

### Fluxo 3 · só Android

Aparelho detectado com modelo consultado. `wm size` lido do aparelho, hierarquia
do `uiautomator` parseada com package correto.

Duas confirmações de segurança que importam:

O dump usa `/data/local/tmp/`, não `/sdcard/`, e o artefato é removido do
aparelho depois. Confirmado no log de chamadas.

O escaping da digitação segura. O payload `a; rm -rf /tmp/x && echo $(id)`
chegou ao aparelho assim:

```
input text 'a;%srm%s-rf%s/tmp/x%s&&%secho%s$(id)'
```

Argumento único, tudo dentro de aspas simples, nenhuma aspa escapando do
quoting. Serial malicioso recusado na fronteira.

O proxy configura `adb reverse` e aponta o proxy global para `127.0.0.1:8082`.
No `proxy.stop`, desfaz as duas coisas. Isso é o que impede o aparelho de ficar
sem internet depois de fechar a ferramenta.

### Fluxo 4 · HTTPS

Túnel CONNECT com handshake TLS de verdade atravessando o proxy. O cliente
completou a negociação e recebeu a resposta do servidor de origem. O evento
ficou registrado como túnel, com host, porta e bytes transferidos.

Em HTTP claro, a redação funciona nos quatro lugares: `Authorization`, `Cookie`,
`Set-Cookie` (depois do defeito 2) e campos sensíveis no corpo. `token`, `cpf` e
`senha` viram `«redigido»`, e `parcelas`, `valor` e `User-Agent` continuam
visíveis. Redação que apaga tudo não serve para depurar.

Limites confirmados: corpo grande truncado com o tamanho real registrado,
binário virando resumo em vez de lixo UTF-8, `generate_204` respondido na hora
(sem isso o Android marca a rede como sem internet), destino inalcançável
devolvendo 502 sem vazar endereço interno, e `Content-Length` inválido não
derrubando o proxy.

---

## Limitação importante, e ela não é defeito

**O corpo do tráfego HTTPS não é inspecionável.** O método CONNECT abre um túnel
e o proxy conta bytes; ele não decifra TLS. O teste confirma isso de propósito:
a credencial enviada dentro do túnel não aparece em lugar nenhum do evento.

Para uma ferramenta cujo valor é inspecionar contrato de API, essa é a maior
lacuna funcional que resta. Inspecionar corpo de HTTPS exige CA própria
instalada no aparelho, com tudo que isso implica. O caminho está descrito em
`docs/research/estudo-http-toolkit.md`.

Hoje, para ver corpo de requisição do app, o tráfego precisa ser HTTP claro ou o
app precisa aceitar uma CA de depuração.

---

## O que este harness não cobre

Ele valida o motor e o contrato, que é o que as duas interfaces consomem. Não
substitui verificação com aparelho real para:

- comportamento visual das telas, em modo claro e escuro
- fluidez do espelho com latência real de USB
- precisão do toque repassado em telas de proporções diferentes
- compilação do WebDriverAgent pelo Appium na primeira execução
- navegação por teclado e leitura por VoiceOver

O roteiro manual dessas verificações está em `docs/QA.md`.

---

# Espelhamento: acompanha e sem travar?

Medição de 08/09/2026. Reproduzir: `python3 qa/perf_espelho.py` e
`qa/perf_tk.py`.

Os testes de fluxo usavam um `adb` que responde em 5 ms. Aparelho real leva de
300 a 800 ms por captura, então nada do que eles mostravam respondia a esta
pergunta. O harness ganhou atraso de captura configurável e um modo de tela
animada, que força o pior caso: nenhum quadro é descartado e tudo sobe para a
apresentação.

## O motor acompanha

| Captura | Capturados em 5 s | Emitidos | Descartados | p95 de comando |
|---|---|---|---|---|
| 0 ms | 29 | 1 | 28 | 15 ms |
| 150 ms | 17 | 1 | 16 | 15 ms |
| 350 ms | 10 | 1 | 9 | 15 ms |
| 700 ms | 5 | 1 | 4 | 15 ms |

A contagem de capturas cai proporcional à latência, como deveria. Em tela
parada, um quadro é emitido e o resto descartado.

O número que responde à pergunta é o último: **o tempo de resposta a comandos
fica em 15 ms mesmo com captura de 700 ms**. A captura roda em thread própria e
não bloqueia a fronteira.

## Pior caso: tela mudando sempre

| Captura | Quadros/s entregues | Payload | Banda | p95 de comando | Pior |
|---|---|---|---|---|---|
| 0 ms | 7,53 | 36 KB | 0,26 MB/s | 15 ms | 15 ms |
| 150 ms | 2,60 | 36 KB | 0,09 MB/s | 15 ms | 15 ms |
| 350 ms | 1,78 | 36 KB | 0,06 MB/s | 15 ms | 15 ms |

Com todo quadro subindo, o comando continua em 15 ms. A banda é modesta: 0,26
MB/s no pior caso, contra os 900 px de largura que o front pede.

## A interface Tk não trava

Medido rodando a janela real com display virtual e um relógio de 50 Hz agendado
com `after()`. Se a thread principal travar, a batida atrasa e aparece.

| Cenário | Quadros desenhados | Atraso médio | p95 | Pior | Batidas > 100 ms |
|---|---|---|---|---|---|
| tela parada | 4 | 0,3 ms | 0,4 ms | 8,8 ms | 0 |
| tela animada | 30 | 0,3 ms | 0,4 ms | 9,1 ms | 0 |
| animada + 150 ms | 28 | 0,3 ms | 0,4 ms | 5,7 ms | 0 |
| animada + 350 ms | 18 | 0,3 ms | 0,4 ms | 4,3 ms | 0 |

Zero batidas acima de 100 ms em qualquer cenário. A janela permanece fluida.

O motivo está no desenho: a captura roda em thread própria, o quadro entra numa
fila, e `_process_event_queue` **drena a fila inteira e desenha só o último**,
descartando os intermediários. É o padrão certo, e é o que impede o atraso de
acumular quando a captura é mais rápida que o desenho.

## DEFEITO 4 — ida e volta por quadro no front

**Severidade: média. Encontrado nesta medição.**

O front chamava `stream.stats` **a cada quadro recebido**, para atualizar fps e
latência na barra de status. Isso é uma requisição e uma resposta completas por
quadro, e enquanto ela não volta o laço de notificações do cliente fica parado,
empilhando os quadros seguintes. É exatamente o mecanismo de travar.

**Correção.** As métricas passaram a viajar dentro da própria notificação do
quadro. Custa três números num payload que já estava indo, e elimina a ida e
volta.

| | Quadros/s | Intervalo médio |
|---|---|---|
| com ida e volta | 3,50 | 283 ms |
| métrica embarcada | 3,64 | 268 ms |

O ganho medido aqui é de 4 a 17%, dependendo da carga. Vale registrar que este
harness roda tudo em memória, num pipe local: o ganho real no front é maior,
porque lá a espera acontecia na main actor, junto com a decodificação do PNG e
o redesenho da tela.

Regressão: o teste de contrato passou a exigir `fps`, `capture_ms` e `skipped`
dentro de `stream.frame`.

## O que esta medição não cobre

O front SwiftUI não foi medido, porque não há como executá-lo aqui. Dois pontos
merecem atenção quando ele for testado num Mac:

**Decodificação de PNG na main actor.** `NSImage(data:)` roda dentro do
tratamento da notificação, que é `@MainActor`. A 5 quadros por segundo com 900
px de largura isso é trabalho real na thread da interface. Se aparecer engasgo,
é o primeiro lugar a olhar.

**Ausência de descarte de quadro atrasado.** A interface Tk drena a fila e
desenha só o último. O front Swift processa todos os quadros que chegam. Se a
decodificação ficar atrás da chegada, ele desenha quadros velhos em vez de pular
para o atual.

# Arquitetura

## Em uma frase

O Mo baile é um motor Python headless com uma interface nativa por cima. Toda a
lógica de inspeção, automação e interceptação vive no motor. A interface só
desenha estado e traduz gesto em chamada.

## O problema que essa forma resolve

O projeto tinha duas implementações paralelas da mesma coisa.

Do lado Python, cerca de 8.200 linhas funcionando: espelho, hierarquia,
geração de Page Objects, proxy, analytics.

Do lado Swift, cerca de 4.600 linhas que reimplementavam os mesmos conceitos
sem estarem ligadas a nada. Nenhum serviço chegava a ser instanciado, as três
colunas da janela eram literalmente `Text("Mirror")`, `Text("Hierarchy")` e
`Text("Workspace")`, e o interceptador de rede respondia `200 OK` para toda
requisição sem encaminhar nada, o que deixaria o aparelho sem internet se
alguém ligasse o proxy.

Duas implementações da mesma regra divergem. A pergunta não era qual das duas
manter, e sim onde a regra deve morar. A resposta é: no motor, uma vez só.

## Camadas

```
┌──────────────────────────────────────────────────────────────┐
│  apps/MoBaile        front nativo SwiftUI (macOS 14+)        │
│  apps/tk-legacy      interface Tkinter (transição)           │
└───────────────────────────┬──────────────────────────────────┘
                            │  JSON-RPC 2.0 sobre stdin/stdout
┌───────────────────────────▼──────────────────────────────────┐
│  engine/src/mobaile/rpc         fronteira: valida e despacha │
├──────────────────────────────────────────────────────────────┤
│  services/    casos de uso: espelho, hierarquia, codegen     │
│  adapters/    adb, WebDriverAgent, proxy, scrcpy, logcat     │
│  security/    validação, escaping, redação                   │
│  ports/       protocolos que os serviços esperam das bordas  │
│  domain/      modelos e erros puros, sem I/O                 │
└──────────────────────────────────────────────────────────────┘
```

A dependência aponta sempre para dentro. O domínio não conhece adapter, o
adapter não conhece a fronteira RPC e nada no motor importa Tkinter ou SwiftUI.
Foi isso que tornou a suite executável em ambiente sem servidor gráfico, coisa
que antes não acontecia: o teste do proxy importava um widget e, com isso,
travava a coleta inteira.

## Por que JSON-RPC sobre stdio

O front sobe o motor como processo filho e conversa por stdin e stdout.

Sem porta TCP não existe superfície de rede, não existe autenticação para
inventar e não existe risco de outra máquina alcançar o motor.

O ciclo de vida também fica resolvido de graça. O motor morre junto com o
aplicativo, o que elimina a classe de bug em que um processo órfão continua
segurando o adb depois que a janela fechou.

O enquadramento é uma mensagem por linha. Requisição carrega `id` e espera
resposta. Quadro de espelho, evento HTTP e evento de analytics chegam como
notificação, sem `id`, empurrados pelo motor. A interface nunca faz polling.

O contrato completo está em [PROTOCOLO_RPC.md](PROTOCOLO_RPC.md).

## O contrato é verificado dos dois lados

As fixtures em `apps/MoBaile/Tests/MoBaileTests/Fixtures/engine_payloads.json`
não foram escritas à mão. Saem do próprio motor, pelos mesmos serializadores
que rodam em produção, via `make fixtures`.

A suite Swift decodifica esses payloads reais. Se alguém renomear um campo no
Python, a suite Swift quebra na hora, e o CI reprova o PR se as fixtures
estiverem desatualizadas. Sem isso, a divergência só apareceria como tela vazia
em tempo de execução.

## Onde cada coisa mora

| Pasta | Conteúdo |
|---|---|
| `engine/src/mobaile/domain` | Modelos e erros. Sem I/O, sem dependência de framework. |
| `engine/src/mobaile/ports` | Protocolos estruturais das bordas. Permitem testar serviço sem aparelho. |
| `engine/src/mobaile/adapters` | Conversa com adb, WebDriverAgent, scrcpy, logcat e sockets. |
| `engine/src/mobaile/services` | Casos de uso que compõem adapters. |
| `engine/src/mobaile/security` | Validação de entrada, escaping de shell, redação, XML seguro. |
| `engine/src/mobaile/rpc` | Fronteira. Única porta de entrada do motor. |
| `apps/MoBaile/Sources/MoBaile/Engine` | Cliente do motor, DTOs e o coordenador de sessão. |
| `apps/MoBaile/Sources/MoBaile/Views` | Telas. Falam com a sessão, nunca com o transporte. |
| `apps/tk-legacy` | Interface Tkinter atual, em transição. |

## A regra de disciplina

Lógica nova vai para o motor.

Se a mesma regra aparecer em Python e em Swift, uma das duas está errada e
ninguém vai descobrir qual até um cliente reclamar.

A exceção é comportamento genuinamente de interface: animação, atalho, layout,
projeção de coordenada na tela. Isso é do front, e a suite `ProjectionTests`
existe justamente porque essa conta estava errada.

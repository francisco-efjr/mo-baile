# QA

## Estado atual

| Suite | Onde | Testes | Precisa de |
|---|---|---|---|
| Motor | `engine/tests` | 91 | nada além de Python |
| Contrato RPC | `engine/tests/contract` | 22 (inclusos acima) | nada |
| Front nativo | `apps/MoBaile/Tests` | 4 arquivos | macOS com Swift |
| UI Tkinter | `apps/tk-legacy/tests` | 4 arquivos | sessão gráfica |

```bash
make check      # lint + bandit + suites Python
make coverage   # cobertura do motor
make test-swift # front nativo, só no macOS
```

## O ponto de partida

A suite não era coletada. Três arquivos de teste importavam Tkinter, direta ou
indiretamente, e o pytest abortava antes de rodar qualquer teste em qualquer
ambiente sem servidor gráfico, CI incluído.

O caso mais revelador: `test_network_interceptor.py` importava
`HTTPInspectorFrame` para testar o proxy. O teste do proxy dependia de um
widget.

## O que mudou

**Separação por camada.** Teste de motor em `engine/tests`, teste de widget em
`apps/tk-legacy/tests`. O motor roda sem servidor gráfico e sem aparelho, por
construção.

**Um teste que passava por acaso.** `test_http_request_interception` usava
`urllib` com `ProxyHandler` para atravessar o proxy. O `urllib` consulta
`no_proxy` e ignora proxy para `127.0.0.1` em qualquer ambiente que tenha essa
variável, o que é comum em container e em CI. A requisição ia direto ao
destino, nada era interceptado e o teste passava mesmo assim.

A versão nova monta a requisição no socket, com URI absoluta na linha de
requisição, exatamente como um aparelho faz. Ficou determinística e passou a
exercitar o parser real.

**Um teste que dependia da máquina.** `test_start_and_stop_mirror` só passava em
máquina com scrcpy instalado em `/opt/homebrew/bin/scrcpy`.

## Cobertura por camada

```
security/          91–94%   toda a validação e o escaping
config             96%
rpc/protocol      100%
streaming          91%
rpc/server         66%
proxy              71%
domain/models      78%
```

O número global do motor é 58%. A distribuição importa mais que o total: o que
está bem coberto é justamente validação de entrada, fronteira do contrato e
detecção de mudança de tela. O que puxa a média para baixo são adapters que só
executam com aparelho conectado, e para esses o teste de integração real vale
mais que mock.

## O que ainda não é coberto por teste automatizado

Isto precisa de aparelho e de olho humano:

1. Espelho ao vivo em aparelho físico Android e em simulador iOS.
2. Toque repassado caindo na coordenada certa, em pelo menos três proporções de
   tela diferentes. Aqui havia um erro real: a conversão usava 1080x1920 fixo.
3. Proxy com tráfego real do app, incluindo o comportamento em HTTPS, em que o
   túnel apenas conta bytes.
4. Captura de tagueamento com o Firebase ativo.
5. Fluxo gravado executando de ponta a ponta no aparelho.
6. Aparência clara, escura e a troca automática ao anoitecer.
7. Navegação completa por teclado e leitura por VoiceOver.

## Roteiro de verificação manual

Antes de liberar uma versão:

**Ambiente.** Abrir o aplicativo sem aparelho conectado. A tela vazia precisa
dizer o que falta, e não apenas "nenhum dispositivo".

**Conexão.** Conectar o aparelho. Ele deve aparecer na lista sem clique extra, e
os indicadores da barra inferior devem refletir o estado real.

**Inspeção.** Passar o cursor sobre um botão. A caixa de seleção precisa
coincidir com o botão, não ficar deslocada.

**Toque.** Trocar o modo do clique para "Repassar toque" e clicar em um botão.
O aparelho deve responder no lugar certo.

**Gravação.** Trocar para "Gravar passo", clicar em três elementos e conferir o
código gerado.

**Rede.** Ligar o proxy, navegar pelo app e conferir que o cabeçalho
`Authorization` aparece redigido. Depois desligar o proxy e confirmar que o
aparelho voltou a ter internet, que é o efeito colateral mais comum nesse tipo
de ferramenta.

**Encerramento.** Fechar o aplicativo com o proxy ligado e confirmar, de novo,
que o aparelho ficou com a rede funcionando.

## Convenções da suite

Nome de teste descreve o comportamento, não o método. `test_texto_gigante_e_recusado`
diz mais que `test_build_args_2`.

Todo teste que corrige uma falha encontrada carrega, em comentário, o que
falhava antes. É o que evita que alguém "simplifique" a correção meses depois.

Teste que precisa de aparelho leva a marca `requires_device` e fica fora do CI.

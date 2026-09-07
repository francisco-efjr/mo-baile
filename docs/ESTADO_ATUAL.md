# O que funciona e o que é fachada

Varredura de 07/09/2026. Critério: só entra em "funciona" o que foi executado
ou coberto por teste. O resto está separado entre "depende de aparelho" e
"fachada", que é código que aparenta funcionar e não faz nada.

---

## Funciona, com prova

| Área | Prova |
|---|---|
| Motor Python (`engine/`) | 106 testes passando, incluindo 22 de contrato RPC |
| Validação, escaping, redação | Cobertura de 91 a 94%, com teste de regressão por vulnerabilidade |
| Proxy de interceptação | 14 testes de integração com socket real, incluindo limites e redação |
| Detecção de mudança de tela | Testado: tela parada emite 1 quadro contra dezenas capturados |
| Detecção automática de dispositivo | 11 testes, incluindo aparelho que some e adb que quebra |
| Interface Python/Tk | Subida de ponta a ponta com display virtual nesta sessão, sem exceção |
| Front SwiftUI | Compila em debug e release na sua máquina, com a suite construída |

O `.build` da sua máquina confirma que os 12 arquivos novos do front compilaram
e que os serviços Swift duplicados saíram do binário.

---

## Funciona, mas só com aparelho conectado

Não dá para verificar em ambiente sem adb, sem Xcode e sem dispositivo. O
código está inteiro e é real, não fachada.

- Captura de tela e espelho, Android via `exec-out screencap` e iOS via `simctl`
- Dump e parsing de hierarquia, `uiautomator` e WebDriverAgent
- Toque repassado e digitação
- Escuta passiva de toques: `getevent` no Android e Quartz no macOS
- Captura de tagueamento via logcat e Unified Logging
- Espelho por scrcpy
- Execução de fluxo gravado, pela interface Python

---

## Fachada: aparenta funcionar e não faz nada

### Front SwiftUI: 19 controles inertes

| Tela | Controles sem ação |
|---|---|
| `DeviceDock` | Voltar, Home, Girar, Screenshot |
| `WorkspaceTabBar` | Estrutura · N, Split, ▶ Rodar |
| `DualEditorPane` | Copiar, Salvar, Limpar |
| `NetworkToolbar` | Configurar proxy, Exportar HAR |
| `AnalyticsToolbar` | Copiar TSV, Exportar JSON |
| `DiagnosticCard` | Iniciar WDA, adb devices |
| `FlowRunnerModal` | Abrir log, Interromper |
| `CorrelationCard` | Gerar asserção de contrato |

### `EmptyStateView`: diagnóstico falso

É a tela que aparece quando não há aparelho, ou seja, a que mais se vê quando
algo está errado. Os três indicadores de cada plataforma são literais no
código:

```swift
("Dispositivo conectado", .ok),      // sempre verde
("WDA instalado", .warn),            // sempre amarelo
("WDA executando", .error)           // sempre vermelho
```

E o rodapé diz `último scan 14:00:00`, um horário fixo.

O efeito prático é o pior possível: a tela mostra um visto verde em
"Dispositivo conectado" justamente quando não há dispositivo nenhum.

### `WorkspaceTabBar`: controles que são texto

As abas e o seletor de estratégia não são controles. São duas linhas de texto:

```swift
Text("Tabs: Page Objects | Rede HTTP | Analytics")
Text("Strategy: ID | XPath | Coords")
```

A troca de aba funciona por outro caminho, mas essa barra não participa dela.

### `SplashWindow`: roteiro fixo

As mensagens "iniciando ADB server", "conectando WebDriverAgent · 8100",
"iniciando Proxy MITM · 8082" e "pronto!" são uma lista literal com temporizador.
Nada disso está sendo iniciado enquanto o texto aparece.

### `HierarchyTreeView`: lista plana fingindo ser árvore

`buildTree()` devolve todos os nós com `children: nil` e simula o aninhamento
com `padding(.leading, depth * 18)`. Não há triângulo de expansão nem
recolhimento de ramo, que é metade da utilidade de um inspetor de hierarquia.

### Interface Python: asserção de contrato inventada

`_generate_contract_assertion` insere sempre o mesmo trecho, com endpoint,
status e payload fixos, ignorando o tráfego capturado:

```python
response = self.network_interceptor.wait_for_request('/v2/credito/simulacao', timeout=5.0)
assert response.status_code == 201
assert response.json()['status'] == 'PRE_APROVADO'
```

Pior que fixo: `wait_for_request` não existe em lugar nenhum do projeto. O
código gerado não roda.

### Métodos vazios na interface Python

`_launch_scrcpy_docked()` e `_on_window_configure()` têm corpo `pass`.

---

## Existe, mas não está ligado

**Execução de fluxo não está no contrato RPC.** `engine/src/mobaile/services/flows.py`
está implementado e testado, e só a interface Tk o usa. O front SwiftUI não tem
como rodar automação, porque não existe método `flow.*` no contrato.

**Campos de estado que ninguém alimenta.** Lidos por telas, nunca escritos:

| Campo | Quem lê | Efeito |
|---|---|---|
| `settleMs` | `StatusBar` | mostra sempre `settle 0 ms` |
| `runLog` | `TerminalView` | terminal sempre vazio |
| `currentRunStep` | `StepsList` | nenhum passo marca progresso |
| `tapForward` | nada mais | substituído por `interactionMode` |
| `passiveMode` | nada mais | escuta passiva não tem controle no front |

---

## Resumo honesto

O motor está sólido e testado. A interface Python é o produto que funciona
hoje. O front SwiftUI passou de casca vazia para um app que compila, conecta no
motor, lista dispositivo, espelha, inspeciona hierarquia, grava passo e mostra
tráfego real. O que falta nele é acabamento: dezenove botões, uma tela de
diagnóstico honesta, a árvore de verdade e a execução de fluxo no contrato.

Nenhum dado exibido nas telas de rede, hierarquia, analytics ou código é
inventado. Onde há invenção, ela está listada acima.

---

## Segunda passagem (07/09, tarde)

A primeira varredura olhou o front SwiftUI a fundo e passou por cima das 6.100
linhas da interface Tk e de alguns adapters. Esta passagem cobriu o que faltava.
Nada no código mudou entre as duas.

### Bug real: escuta passiva iOS usa tela fixa

`_start_passive_listeners` constrói o listener sem passar o tamanho lógico:

```python
self.ios_listener = IOSPassiveListener(on_tap_callback=self._on_passive_tap)
```

`IOSPassiveListener` então usa o padrão do construtor, `(390, 844)`, para
converter a posição do mouse em coordenada do simulador. O aplicativo já
descobre o tamanho real a partir do XML do WebDriverAgent e guarda em
`self.ios_logical_size`, mas esse valor nunca chega ao listener.

Efeito: em qualquer simulador que não seja um iPhone de 390x844, os toques
capturados em modo passivo são gravados na coordenada errada. Em iPad o desvio
é grande.

O mesmo vale para o primeiro toque antes do primeiro dump de hierarquia, que
usa o valor inicial 390x844 em `main_window.py`.

### Risco latente: I/O de rede no construtor

`IOSBridge.__init__` chama `_ensure_session()`, que faz `GET /status` com 2 s de
timeout e `POST /session` com 4 s. Medido:

| Cenário | Custo |
|---|---|
| WDA não está rodando em localhost (porta recusa) | instantâneo |
| Host engole pacotes (WDA_URL apontando para aparelho dormindo) | 6,01 s |

No uso normal não incomoda, porque a porta fechada recusa na hora. Mas o
aplicativo cria três instâncias (janela principal, inspetor HTTP e motor), então
no cenário ruim são 18 s de janela travada. I/O em construtor é o problema de
fundo; a sessão deveria ser criada sob demanda.

### Heurística frágil na captura de toque iOS

`title_bar_h = 28 if win_h > 300 else 0` é um chute fixo para a altura da barra
de título do Simulator. Se a Apple mudar a barra, ou o usuário usar zoom
diferente, o eixo Y sai deslocado.

### Sistema de design copiado três vezes

| Componente | Definido em |
|---|---|
| `FluidPillButton` | `main_window.py`, `http_viewer.py`, `dialogs.py` |
| `_draw_round_rect` | `main_window.py`, `http_viewer.py` |
| Paleta `THEME` | `main_window.py`, `http_viewer.py` |

São 438 cores hexadecimais espalhadas por três arquivos. Trocar uma cor do tema
exige mexer em três lugares, e nada garante que fiquem iguais.

### O que a segunda passagem confirmou como real

- `http_viewer.py` consome os eventos do proxy e do analytics de verdade, com
  polling a cada 120 ms, exportação HAR, TSV e JSON funcionando
- `dialogs.py` monta a estrutura e o executor a partir dos passos reais
- `scrcpy.build_command` monta o comando real, com todas as flags
- `ios_logical_size` é derivado do XML do WebDriverAgent, não é chute
- Nenhum controle morto na interface Tk: todos os botões têm comando ligado


---

## Terceira passagem (07/09, noite): abrir simulador

A pergunta era direta: clicar na tela e o simulador abrir. A resposta era que
isso não existia em lugar nenhum do projeto.

O `list_booted_simulators` só enxerga simuladores **já ligados**. Não havia
nenhuma chamada a `simctl boot`, nenhum `open -a Simulator`, e o `start_avd` do
Android existia mas não estava no contrato RPC. Clicar não tinha para onde ir.

### O que passou a existir

| Método RPC | O que faz |
|---|---|
| `diagnostics.check` | Estado medido de verdade, com detalhe e ação por checagem |
| `simulators.list` | Todos os simuladores instalados, não só os ligados |
| `simulators.boot` | `simctl boot` mais `open -a Simulator` |
| `simulators.shutdown` | Desliga |
| `emulators.list` / `emulators.boot` | Equivalente para AVD do Android |

Cobertura: 19 testes novos no motor e 7 no contrato.

### A tela de estado vazio deixou de mentir

Os três indicadores por plataforma agora vêm de `diagnostics.check`. O horário
do último scan é o horário real. Os dois botões funcionam: "Abrir simulador" e
"Abrir emulador", com menu para escolher qual quando há mais de um.

Cada checagem carrega o detalhe do que fazer. "Conectado mas em 'unauthorized'.
Aceite a depuração USB no aparelho" resolve mais que um X vermelho.

### WebDriverAgent pelo Appium

O time usa Appium, então o botão não compila o WDA por conta própria: ele pede
ao Appium, que já faz isso como parte do ciclo de vida do driver XCUITest.

`wda.start` sobe o servidor Appium se preciso, abre uma sessão XCUITest apontada
ao simulador ligado e espera a porta 8100 responder.

Dois detalhes decidem se isso funciona na prática, e ambos estão cobertos por
teste:

**Sessão sem `app` nem `bundleId`.** O driver aceita, sobe o WDA e deixa o
simulador na tela inicial. Não estamos testando um app, estamos pegando
emprestada a gestão de ciclo de vida do WDA.

**`newCommandTimeout: 0`.** Com o padrão de 60 s, o Appium encerraria a sessão
por inatividade e derrubaria o WDA junto. O indicador ficaria verde e voltaria a
vermelho sozinho, que é o tipo de sintoma que consome uma tarde.

Na primeira execução o Appium compila o WDA e isso leva minutos. O motor usa
timeout generoso e a interface avisa o motivo, em vez de parecer travada.

O encerramento derruba apenas o servidor Appium que o próprio motor iniciou. Um
Appium que já estava no ar é do usuário, e matá-lo quebraria a sessão dele.

### O botão da tela vazia faz o próximo passo necessário

O motor marca cada checagem que tem conserto com um identificador de ação, e a
interface obedece a isso em vez de reimplementar a decisão:

| Situação | Botão |
|---|---|
| Nenhum simulador ligado | Abrir simulador |
| Simulador ligado, WDA fora do ar | Iniciar WebDriverAgent |
| Tudo pronto | Ir para o simulador |

---

## Quarta passagem (07/09, noite): as fixtures não cobriam o que era novo

A leva de Swift da terceira passagem compila e a suite passa. O compilador não
tinha nada a dizer: build limpo do zero, zero erro, e nenhum dos warnings do
projeto está nos quatro arquivos novos.

O problema estava um nível abaixo. Os dez DTOs de ambiente (`Diagnostics`,
`PlatformDiagnostics`, `Check`, `SimulatorList`, `Simulator`, `BootResult`,
`AvdList`, `AvdBootResult`, `WDAStatus`, `WDAStartResult`) foram escritos,
compilados e ligados às telas **sem que nenhuma fixture os cobrisse**:
`tools/generate_fixtures.py` não chamava `diagnostics.check`, `simulators.*`,
`emulators.*` nem `wda.*`.

Compilar só provava que o Swift era válido, não que ele casava com o motor. Um
campo renomeado do lado Python passaria pelo CI e apareceria como cartão de
diagnóstico vazio em execução — exatamente a divergência silenciosa que as
fixtures existem para impedir.

Conferido à mão, subindo o motor de verdade: os dez DTOs estão corretos, campo
a campo. O contrato estava certo; o que faltava era a prova.

### Bug de ferramenta: `make fixtures` não era determinístico

Mais sério, porque atinge quem seguir a regra à risca. O gerador lia o ambiente
da máquina:

| Campo | Gerado sem adb (o que estava commitado) | Gerado num Mac com adb |
|---|---|---|
| `adb_path` | `"adb"` | `/opt/homebrew/bin/adb` |
| `adb_available` | `false` | `true` |
| `scrcpy_available` | `false` | `true` |

O portão do CI regenera as fixtures no Ubuntu e compara com o commitado. Ou
seja: rodar `make fixtures` num Mac e commitar, que é literalmente a regra
"mudou o contrato, rode make fixtures", **reprovava o próprio PR**.

`ambiente_fixo()` congela toda leitura de ambiente com um ambiente de
referência. A fixture voltou a ser função apenas do contrato, que é o que ela
deveria estar medindo. Verificado: saída idêntica com e sem `adb`, `scrcpy` e
`appium` no PATH, e idêntica entre o Python do sistema e o do venv.

### Cobertura nova

Fixtures de 14 para 21, suíte Swift de 36 para 45 testes (contrato: 13 → 22).

Um teste merece nota. O `DaemonState` do motor tem cinco valores (`ok`, `busy`,
`warn`, `error`, `off`) e o `switch` do Swift trata quatro: `off` cai no
`default`. Está seguro **porque** o default é `.off`. Se alguém "simplificar"
esse default para `.ok`, o visto verde falso em "Dispositivo conectado" volta
inteiro, agora por baixo, sem nenhuma linha literal para denunciar.

`testEstadoDesconhecidoNuncaViraVistoVerde` amarra isso. Verificado por mutação:
com o `default` em `.ok`, o teste falha nas duas asserções.

---

## Validação com aparelho de verdade (07/09, noite)

Primeira vez que os seis passos foram executados num Mac com Xcode, adb, um
simulador iOS e um emulador Android reais. Antes disso nada aqui tinha sido
verificado fora de teste unitário.

**Limite desta validação, dito na frente:** o shell usado não tem permissão de
Gravação de Tela nem de Acessibilidade no macOS, então a janela do app nativo
não pôde ser observada. Tudo abaixo foi verificado no motor — que é o mesmo
motor que o app embute — e, onde a afirmação era sobre a tela, está marcado
como pendente de conferência visual. Nada foi marcado como verificado sem ter
sido executado.

### O que passou

| Passo | Resultado |
|---|---|
| 1. Cartões refletem o ambiente | **Passou.** Acompanhados em quatro estados reais |
| 2. Abrir simulador | **Passou.** `simctl boot` mais janela do Simulator na frente |
| 3. Botão vira "Iniciar WebDriverAgent" | **Passou.** Ação do motor troca de `boot_simulator` para `start_wda` |
| 3. WDA sobe pelo Appium | **Passou.** No ar em 20 s, porta 8100 respondendo 200 |
| 4. Espelho, hierarquia, toque, gravação | **Passou.** Tudo com dado real do WDA |
| 5. Redação do `Authorization` | **Passou.** Token nunca chega ao cliente |
| 6. Aparelho continua com internet | **Passou.** Sem perda de pacote após o encerramento |

### Passo 1: o diagnóstico deixou de mentir, comprovado

Os cartões foram lidos em quatro ambientes diferentes, nesta ordem:

| Ambiente | iOS | Android |
|---|---|---|
| Nada ligado | `warn` Simulador ligado · `off` WDA | `warn` Nenhum aparelho conectado |
| Simulador ligado | `ok` iPhone 16 · `warn` WDA → ação `start_wda` | idem |
| WDA no ar | tudo `ok`, pronto=true | idem |
| Emulador online | tudo `ok` | tudo `ok`, pronto=true |

Com o ambiente vazio, "Dispositivo autorizado" saiu em **`warn`**, com o texto
"Nenhum aparelho conectado". O visto verde falso da versão anterior não existe
mais na origem.

### Passo 2: a janela vem para a frente

`simulators.boot` ligou o iPhone 16 em 1,5 s e o app em primeiro plano passou a
ser o Simulator, medido por `lsappinfo front` com o Mo baile fechado para não
disputar o foco.

### Passo 3: a troca de botão é dirigida pelo motor

Com o simulador ligado, a checagem do WDA passou a carregar `action:
"start_wda"`, e `EmptyStateView.tituloAcaoIOS` mapeia esse identificador para
"Iniciar WebDriverAgent". A decisão está no motor e a view obedece, que é a
regra da casa.

O WDA subiu em 20 s porque já estava compilado de uma execução anterior. A
primeira compilação de verdade não foi cronometrada aqui. O aviso existe no
código (`EngineSession.startWDA` escreve "Na primeira vez isso compila o WDA e
demora" e liga `isBooting`, que vira `isBusy` no cartão); **falta conferir na
tela** que ele aparece.

### Passo 4: dado real, não fachada

Simulador iPhone 16, tela real de 1179x2556. `hierarchy.dump` devolveu 147
elementos do WebDriverAgent, com `parent_idx` preenchido — que é justamente o
que a árvore de verdade da tarefa 3c precisa.

O toque foi repassado e teve efeito: tocar no ícone do Fitness abriu o app e a
hierarquia foi de 147 para 168 elementos. O `codegen.record` gerou entrada real
a partir do elemento sob o dedo, com `AppiumBy.ACCESSIBILITY_ID`.

O espelho ao vivo confirmou a detecção de mudança de tela em condição real: com
a tela parada, 23 quadros capturados e **1 emitido**, 22 descartados, proporção
de 95,7%.

### Passo 5: a credencial não vaza

Requisição com `Authorization: Bearer <token de 61 caracteres>` atravessou o
proxy. O evento capturado trouxe `Authorization: «redigido» (61 chars)`, e o
token não aparece em lugar nenhum do payload entregue ao cliente.

Confirmado de quebra que o proxy **encaminha de verdade**: a resposta foi o 404
real do servidor de destino, e não o `200 OK` inventado que a versão Swift
antiga devolvia.

Falta conferir na tela que a coluna da tabela mostra o valor redigido.

### Passo 6: o aparelho não fica sem internet

O passo mais importante, porque o modo de falha é silencioso e só aparece
depois que a pessoa fecha a ferramenta.

| Momento | `settings get global http_proxy` | `adb reverse` |
|---|---|---|
| Antes | `null` | vazio |
| Proxy ligado | `127.0.0.1:8082` | `tcp:8082 tcp:8082` |
| Depois de fechar o motor com o proxy ligado | `:0` | vazio |

E a prova que interessa, feita no aparelho: 3 pacotes para 8.8.8.8, 0% de
perda, mais resolução de DNS funcionando. O aparelho continua na rede.

### Achado novo: o WDA sobrevive ao encerramento

O motor derruba o servidor Appium que ele mesmo iniciou, como projetado. Mas o
`xcodebuild` que hospeda o `WebDriverAgentRunner` **não morre junto**: depois do
encerramento ele continua vivo e a porta 8100 segue respondendo 200.

Não quebra nenhum dos seis passos, e num segundo uso até acelera. Mas é
processo órfão segurando simulador e CPU depois que a janela fechou — a mesma
classe de bug que o ARQUITETURA.md diz que a fronteira por stdio resolve. Fica
registrado; consertar exige decidir se o WDA é do motor ou do usuário, como já
se decidiu para o Appium.

### O que continua pendente, e por quê

Precisa de olho humano na janela do app, porque falta permissão de tela:

1. Os cartões desenhados na tela batem com o que o motor mede
2. O aviso de compilação do WDA aparece em vez de o app parecer travado
3. O `Authorization` redigido aparece na coluna da tabela de rede
4. Clicar nos botões dispara as ações (o caminho de dados está provado; falta o clique)

Não testado: aparelho Android **físico** com desconexão a quente. A validação
usou emulador, que não cobre cabo removido nem o estado `unauthorized`.

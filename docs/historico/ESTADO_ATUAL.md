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

---

## Correção: a tela conectava com o espelho em branco (07/09, noite)

A validação anterior deu o espelho como funcionando. Estava certa sobre o
motor e errada sobre o aplicativo, e a diferença só apareceu quando alguém
olhou a janela.

**Por que a suíte não pegou:** nenhum dos 45 testes Swift instanciava o `body`
de uma View ou observava o que a sessão pede ao motor. `ThemeTests` importa
SwiftUI, mas só verifica tokens de cor. A cobertura terminava na fronteira RPC.

### Bug 1: selecionar dispositivo não pedia quadro

`select(deviceID:)` chamava `screen.size` e `hierarchy.dump`, e nenhuma
captura. Conectar enchia a árvore de acessibilidade e deixava a moldura preta
até alguém ligar o streaming ou clicar em "Forçar Captura".

Mesma falta em `device.changed`, o caminho de quando o aparelho é plugado com o
app já aberto.

### Bug 2: quadro do aparelho anterior sobrevivia à troca

`select` limpava hierarquia e seleção, mas não o quadro. Trocar de alvo deixava
na moldura a tela do aparelho antigo — pior que moldura vazia, porque parece
dado atual.

### Bug 3: rótulo quebrando no meio da palavra

Sem `lineLimit(1)`, o SwiftUI quebrava os rótulos quando a barra apertava:
"Streaming" virava "Streamin" / "g", "Forçar Captura" ia para duas linhas e
"Copiar" virava "Copi" / "ar". Corrigido em `CanvasSwitch`, `FluidPillButton` e
no cabeçalho do `DualEditorPane`.

### A costura que faltava para testar

`EngineSession` guardava um `EngineClient` concreto criado dentro do próprio
`connect()`. Não havia como observar as chamadas da sessão sem subir um
processo Python, e foi por isso que o espelho em branco atravessou 45 testes
verdes.

O protocolo `EngineCalling` abre essa costura. Em produção quem conforma é o
`EngineClient`; no teste, um duplo que responde com as fixtures reais do motor —
então o teste da sessão continua amarrado ao contrato de verdade.

Três testes novos, todos verificados por mutação: com a correção desfeita, os
três falham, e a lista de chamadas registrada mostra o problema direto
(`["session.select_device", "screen.size", "hierarchy.dump"]`, sem captura).

Suíte Swift: 45 para 48.

### O que continua fachada nessa tela, e é a tarefa 3

O que se vê de quebrado além dos três bugs acima já estava catalogado e não foi
tocado: a `WorkspaceTabBar` ainda é `Text("Tabs: Page Objects | Rede HTTP |
Analytics")` literal, a árvore de hierarquia ainda é lista plana com recuo
simulado, e os botões Copiar/Salvar/Limpar continuam com corpo vazio.

### Limite que permanece

Não existe teste de renderização. As correções 1 e 2 estão amarradas por teste;
a correção 3, de layout, foi verificada a olho e continua sem rede de proteção.
Enquanto não houver teste de snapshot, quebra de layout só aparece quando
alguém abre a janela.

---

## Layout e gravação (07/09, noite)

### Como passou a dar para enxergar a tela

O ambiente não tem permissão de Gravação de Tela, então a janela não podia ser
observada. `ImageRenderer` desenha uma View sem janela e sem permissão nenhuma,
e é isso que `LayoutSnapshotTests` faz: renderiza a barra e a janela em larguras
escolhidas e grava PNG. Roda só com `MOBAILE_SNAPSHOT_DIR` definido, para não
gerar arquivo em CI.

Limite conhecido: `ImageRenderer` não desenha controle com base em AppKit
(`Menu`, `Picker`), que sai como bloco amarelo. Serve para conferir a conta do
layout, não para validar pixel.

### Bug: o seletor de interação pintava por cima dos vizinhos

`interactionPicker` era um `Picker(.segmented)` — controle do AppKit — preso a
`.frame(width: 150)`. Os três rótulos ("Inspecionar", "Repassar toque", "Gravar
passo") precisam de mais que o dobro disso, e o AppKit não comprime texto para
caber: desenha para fora da moldura. O layout reservava 150 pontos e o controle
pintava por cima do interruptor "Streaming" à esquerda e do botão "Forçar
Captura" à direita.

Trocado pelo `SegmentedControl` da casa, SwiftUI puro, que se dimensiona pelo
conteúdo.

### Bug: a barra não cabia na largura mínima da janela

Somada, a barra pede cerca de 1380 pontos. O mínimo da janela era 1100, ou seja,
dava para arrastar a janela até um estado em que o título sumia à esquerda e o
grupo de painéis era cortado à direita.

Duas mudanças: a barra ganhou modo compacto abaixo de 1400 (esconde o subtítulo
e encolhe a largura reservada ao nome do aparelho) e o mínimo da janela subiu
para 1320. Conferido por snapshot nas duas larguras.

### Bug: clique fora de qualquer elemento recusava a gravação

`codegen.record` levantava "Nenhum elemento encontrado nessa coordenada" quando
o ponto não caía em nó nenhum. Área vazia, canvas de jogo e componente desenhado
à mão não aparecem na árvore de acessibilidade, e é justamente aí que o passo
por coordenada é a única saída. No front nativo isso virava clique que não faz
nada.

A interface Tk já sintetizava esse elemento por conta própria (`pos_x_y`), ou
seja, a regra existia num lugar só e o outro front falhava em silêncio — o caso
exato que a regra de disciplina do ARQUITETURA.md descreve. A síntese passou
para o motor, então as duas interfaces usam a mesma.

### Bug: toque repassado com streaming desligado deixava tudo parado

`tap(at:)` só chamava `input.tap`. Com o espelho ao vivo ligado, quem manda
reler é o `stream.settled`; desligado, ninguém manda.

O efeito ruim não é o visual. O passo gravado logo depois é resolvido contra a
árvore velha, então o toque navega a tela e a gravação aponta para o elemento
que não está mais lá.

### Cobertura

Motor 156 → 158, front 45 → 54 (4 são os snapshots, pulados sem a variável de
ambiente). Todas as correções verificadas por mutação: desfeita a correção, o
teste correspondente falha.

### Continua em aberto

Os três modos de clique são exclusivos, então gravar um fluxo obriga a alternar
entre "Gravar passo" e "Repassar toque" a cada passo. Na interface Tk gravação e
repasse são independentes: `auto_forward_tap` é caixa de seleção separada, e o
clique grava e navega de uma vez. É decisão de produto, não bug, e não foi
mexida.

---

## Gravação que não aparecia e emulador lido cedo demais (07/09, noite)

### Bug: ação no aparelho não virava código na tela

`AppState.actionsCode` e `AppState.locatorsCode` **nunca eram escritos por
ninguém**. Nasciam vazios e só apareciam em `clearSteps()`. Os dois editores da
coluna de workspace ficavam permanentemente em branco.

O dado sempre esteve lá: `codegen.record` já devolve `object_code` e
`action_code`. Faltava a sessão escrever. Clicar no elemento e não ver o Page
Object aparecer é o ciclo inteiro do produto falhando em silêncio.

A gravação agora acrescenta a cada passo, que é exatamente o que
`_record_element` da interface Tk faz — as duas precisam produzir o mesmo
arquivo.

### Bug: o alvo era dado como pronto antes de o Android subir

O `adb` responde `device` assim que o `adbd` sobe, o que num emulador acontece
bem antes da interface. `devices.list` repassava isso como `ready: true`, e a
interface então selecionava o alvo, lia `screen.size` e capturava a tela nesse
intervalo.

Observado na prática: `1080x1088` num aparelho de 1080x2400, e quadro rasgado
no espelho, com o rodapé ainda dizendo "Emulador iniciando…". Nada relia depois.

`list_devices_typed` agora rebaixa o estado para `booting` enquanto
`sys.boot_completed` não confirma. Falha de leitura conta como concluído: um
aparelho físico que não responde ao getprop no tempo esperado não pode sumir da
lista por isso. Estado que já não era `device` (`unauthorized`, `offline`) passa
intacto, porque tem diagnóstico próprio.

### Barra superior: não reproduzido

Relato de que a barra some da janela. Não foi possível reproduzir. A hipótese
inicial era o `GeometryReader` introduzido com o modo compacto, mas a mutação
desmentiu: com e sem ele, a barra desenha igual, empilhada e isolada.

O `GeometryReader` foi trocado por medição no `background` mesmo assim, porque é
estritamente mais seguro — envolver a barra a deixa sem altura intrínseca, ainda
que aqui isso não tenha se manifestado.

`ToolbarLayoutTests` passou a afirmar de verdade, lendo os pixels do desenho: a
faixa da barra tem de conter vários tons (controles presentes) e a faixa abaixo,
um só (a barra não invadiu o conteúdo). Diferente de `LayoutSnapshotTests`, que
só grava PNG para inspeção e não falha sozinho.

### Cobertura

Motor 158 → 170, front 54 → 59 (5 são snapshots, pulados sem a variável de
ambiente). Correções verificadas por mutação, uma a uma.

### Continua faltando para fechar o ciclo do produto

Gravar já aparece na tela. **Salvar em disco e reexecutar continuam ausentes**:
o botão "Salvar" tem corpo vazio e não existe `flow.*` no contrato, então os
passos seguem morrendo com o processo.

---

## O espelho rasgado era o transporte (07/09, noite)

Duas tentativas anteriores erraram o diagnóstico. A primeira culpou o tamanho
do aparelho lido cedo demais; a segunda, o `GeometryReader` da barra. Nenhuma
das duas era a causa do espelho rasgado, e a mutação desmentiu a segunda.

O que fechou a questão foi comparar os dois lados. O motor, chamado direto,
produz o PNG **perfeito**: 1080x2424, tela inteira, ícones legíveis. O mesmo
quadro chegava rasgado na janela. Logo, o defeito estava no transporte.

### A causa

```swift
stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
    let chunk = handle.availableData
    Task { await self?.ingest(chunk) }   // uma Task nova por pedaço
}
```

Cada pedaço do stdout virava uma `Task` independente, e **`Task` não garante
ordem de execução**. Resposta curta cabe num pedaço só e nunca deu problema —
por isso hierarquia, lista de dispositivos e diagnóstico sempre funcionaram.

Um quadro do espelho passa de 400 KB em base64 e atravessa o cano em vários
pedaços, que eram remontados embaralhados. O JSON continuava decodificando,
porque a troca caía dentro da string base64, e o PNG saía parcial: certo no
topo, uma faixa de lixo e o resto preto.

Corrigido com `AsyncStream`, que preserva a ordem do `yield`, mais um único
consumidor aplicando os pedaços em sequência.

### O modo de falhar era pior do que parecia

Reintroduzido o bug, o teste de integração **travou** em vez de falhar: com a
linha corrompida o JSON não decodifica, `route` descarta, e a continuação da
chamada nunca é resumida. No app isso é a janela congelada, não um erro na tela.

O teste ganhou prazo próprio para falhar limpo. Fica registrado que `call` não
tem prazo nenhum: qualquer linha malformada pendura a chamada para sempre. Não
foi mexido porque um prazo fixo quebraria `wda.start`, que legitimamente leva
minutos.

### Por que nenhum teste pegava

O erro não está na lógica de nenhuma função — `ingest` monta linha certo, e
`route` despacha certo. Está na concorrência entre o cano e o ator, que só
aparece com payload grande o bastante para chegar picotado.

`EngineClientStreamTests` sobe o motor de verdade, captura a 900 de largura
(o mesmo do espelho em produção) e confere que o PNG decodificado tem a altura
declarada e a proporção do aparelho. Precisa de aparelho, então roda só com
`MOBAILE_DEVICE_TESTS=1`.

### Cobertura

Front 59 → 61 (7 pulados: 5 snapshots e 2 de integração). Motor em 170.

### Segue sem causa: a barra superior

O relato de que a barra some da janela continua sem reprodução. Renderizada
isolada e empilhada, com e sem o `GeometryReader`, ela desenha correta e
completa. Não foi possível observar a janela real: falta permissão de tela.

---

## Barra reorganizada e gravação de vídeo (08/09)

Pedidos do usuário, com o que cada um implicou.

### Saiu o modo "Inspecionar"

Eram três modos de clique. O painel de atributos já é preenchido em qualquer
modo — `handleTap` guarda o elemento antes de decidir o que fazer com o clique —
então "Inspecionar" não fazia nada que os outros dois não fizessem, e obrigava a
trocar de modo à toa.

### "Gravar passo" passou a tocar no aparelho

Os modos eram exclusivos, então gravar um fluxo exigia alternar entre "Gravar
passo" e "Repassar toque" a cada clique: vinte passos viravam quarenta trocas de
modo. Um fluxo só avança navegando por ele.

A ordem importa e está coberta por teste: grava primeiro, resolvendo o elemento
contra a árvore da tela atual, e só depois toca, que é o que leva para a próxima.

### Saíram "Espelho" e "Streaming"

Dois nomes parecidos que faziam coisas diferentes — um escondia a coluna, o
outro ligava a captura. Dava para desligar "Espelho" com "Streaming" ligado e
ficar capturando sem ver.

A coluna agora é escondida pelos botões de painel, que já faziam isso, e o
espelho ao vivo começa sozinho ao selecionar um aparelho.

### "Forçar Captura" virou "Gravar a tela"

Gravação de vídeo de verdade, nova no motor: `adb shell screenrecord` no
Android, `xcrun simctl io recordVideo` no iOS. A escolha da ferramenta é do
motor; a interface só pede "grava".

Três métodos novos no contrato: `recording.start`, `recording.stop`,
`recording.status`. Vídeos vão para `~/Movies/Mo baile/`.

Dois detalhes que decidem se funciona:

**Encerramento por SIGINT.** Matar com SIGKILL deixaria o MP4 sem índice final e
o arquivo não abriria em lugar nenhum.

**Limite de 180 s no Android.** É o teto do `screenrecord`, que para sozinho ao
atingi-lo. A interface avisa no início, em vez de o vídeo terminar sem
explicação.

Verificado com aparelho físico (moto g55 5G): 5 s de gravação, MP4 h264 de
1080x2400 válido.

### Bug encontrado ao ligar isso: filho roubando o canal do protocolo

`recording.start` respondia e `recording.status` logo depois nunca respondia.

O `adb shell screenrecord` herdava o **stdin do motor** — que é o canal
JSON-RPC — e passava a consumir as linhas das chamadas seguintes.

Seis dos sete `subprocess.Popen` do motor tinham o mesmo defeito: scrcpy,
logcat, escuta de toques, emulador, execução de fluxo e a gravação nova. Só o
Appium isolava. No app o sintoma é janela travada, sem erro nenhum.

Todos passaram a receber `stdin=subprocess.DEVNULL`. Como o modo de falhar é
silencioso e difícil de ligar à causa, a regra virou guarda de código:
`test_todo_subprocesso_do_motor_isola_o_stdin` varre a fonte e reprova qualquer
`Popen` sem `stdin` explícito.

### Botões de painel trocados

Os três glifos abstratos em alvos de 26x22 saíram. Eram menores que o mínimo
confortável do HIG e não diziam qual coluna era qual — só se descobria clicando.

`PanelToggles` usa 32x28, ícone que nomeia a coluna (aparelho, lista, chaves) e
dica com o atalho. O `contentShape` faz a área toda receber o clique, e não só o
traço do ícone.

### O código agora aparece enquanto se clica

`$state.actionsCode` cria um `Binding` **sem ler** o valor, e o `@Observable` só
registra dependência no que o corpo lê. A coluna não redesenhava: o código só
aparecia se outra coisa forçasse o redesenho.

O cabeçalho passou a mostrar a contagem de linhas, que é útil por si só e é a
leitura que registra a dependência.

### Cobertura

Motor 170 → 180, front 61 → 66. Fixtures 21 → 24, conferidas como estáveis.

---

## Android, espelho e rodapé (08/09)

### Por que o Android não gerava código e o iOS gerava

`codegen.record` precisa de `current_xml`. No iOS ele vem do WebDriverAgent; no
Android, de `uiautomator dump`.

No Motorola g55 físico do time, `uiautomator dump` é **morto com SIGKILL**
(exit 137) e devolve vazio. Sem hierarquia não há elemento para resolver, e a
gravação de passo do Android ficava silenciosa enquanto a do iOS funcionava.

Medido também: a sessão UiAutomator2 do Appium falhava com
`IllegalStateException: UiAutomation not connected` — ou seja, o serviço do
próprio Android estava travado, e não a ferramenta. As duas rotas dependem do
mesmo UiAutomation.

**A causa raiz era a conexão USB.** No meio da investigação o aparelho sumiu do
`adb devices`. Depois de reconectar, `hierarchy.dump` passou a devolver 66
elementos e a gravação passou a gerar código normalmente:

```
BOTAO_0_OU_1 = (AppiumBy.ID, "uds_text_id")
def click_0_ou_1(self):
```

### O que mudou por causa disso

**Reserva pelo WebDriver.** `_android_hierarchy` tenta `uiautomator dump` e, se
vier vazio, abre sessão UiAutomator2 pelo Appium — o equivalente Android do WDA.
O caminho rápido continua primeiro porque abrir sessão custa dezenas de segundos
na primeira vez.

**Erro que diz o que fazer.** A mensagem era "Hierarquia de UI indisponivel para
o alvo atual", que deixava o usuário sem árvore, sem código e sem pista. Agora
o texto separa iOS de Android e, quando reconhece `UiAutomation not connected`,
diz que reiniciar o aparelho ou reconectar o cabo costuma resolver.

### O espelho reflete, mas devagar

Medido com o aparelho físico: abrir Ajustes gerou 5 quadros, voltar à home
gerou 2. Ou seja, ele reflete. O problema é o intervalo.

`last_capture_ms` estava em **1823 ms** por quadro, com fps efetivo de 1,22. A
sensação de travado vem daí, não de o espelho estar parado.

Causa: `screencap -p` faz o **aparelho** codificar o PNG. Medido no g55:

| Forma | Tempo | Tamanho |
|---|---|---|
| `screencap -p` | 2,14 s | 3,0 MB |
| `screencap` cru | 1,23 s | 10,4 MB |

A codificação no aparelho custa quase um segundo, e é desperdício puro: o
espelho reduz a imagem logo em seguida. A captura passou a usar o formato cru,
com o PNG como reserva para aparelho que não entregue o cru.

Resultado medido depois da mudança: **1227 ms** por quadro, contra 1823 ms.

**Limite honesto:** ~0,8 quadro por segundo continua longe de fluido. Chegar a
espelho fluido no Android exige `scrcpy` ou um fluxo H.264 decodificado no Mac,
que é trabalho de outra ordem e não foi feito.

### Rodapé sempre atualizado

`applyDaemonStatus` rodava **uma única vez**, na conexão, e só mexia em dois dos
quatro indicadores. Subir o WDA, ligar o proxy ou perder o adb não mudava nada
na tela: o painel que existe para dizer o que está de pé afirmava o que estava
de pé um minuto atrás.

`startWatchingDaemons` relê a cada 5 s e alimenta os quatro.

### Espelho responsivo

A moldura era 258x540 fixos. A coluna podia crescer sem o espelho crescer junto,
e qualquer aparelho fora de 19.5:9 aparecia na proporção errada — iPad desenhado
como iPhone.

Agora a proporção vem de `deviceSize`, medida pelo motor, e o tamanho é o maior
que cabe no espaço oferecido. Arredondamentos e notch acompanham a largura.

### Cobertura

Motor 180 → 196, front 66.

---

## Dock de quatro botões trocado por "Atualizar" (08/09)

`DeviceDock` trazia "Voltar", "Home", "Girar" e "Screenshot" — quatro botões com
corpo vazio desde sempre, listados como fachada desde a primeira varredura.
Removidos a pedido, junto com o arquivo.

No lugar, um botão só: **Atualizar**, que recaptura a tela e recarrega a
hierarquia (o antigo `captureNow`, também no ⌘K).

Ele tem razão de existir enquanto o espelho depender de `screencap`: a captura
passa de um segundo em aparelho físico, então o espelho ao vivo anda perto de um
quadro por segundo. Quando se quer o estado exato de agora, com a árvore
correspondente, pedir na hora é mais direto que esperar a próxima volta do ciclo.

O estado "Atualizando…" não é enfeite: captura mais dump passam de dois
segundos, e sem ele o clique parece não ter feito nada — o que leva a apertar
várias vezes e enfileirar capturas.

---

## O espelho congelava no primeiro quadro (08/09)

Sintoma relatado: com o aparelho conectado, o Mo baile mostrava a tela de
minutos atrás enquanto o scrcpy, lado a lado, mostrava a atual. Só clicando em
"Atualizar" a imagem vinha.

### Como foi isolado

Primeiro descartando o motor. Testado com o mesmo interpretador que o app usa
(Python 3.14 do framework, não o `.venv`), nas duas plataformas:

| | Android | iOS |
|---|---|---|
| `screen.capture` | 1,29 s, imagem conferida a olho | 0,27 s |
| `hierarchy.dump` | 45 elementos | 48 elementos |

Depois, olhando o processo do motor do próprio app: **zero processos de captura
em 6 s de amostragem**. Ou seja, `stream.start` nunca tinha sido pedido.

### A causa

Havia dois caminhos até um alvo ficar pronto, e eles divergiam:

- escolher no menu → `select(deviceID:)` → ligava o espelho
- o aparelho aparecer sozinho pelo detector → `device.changed` → **não ligava**

O segundo é o caminho comum de quem pluga o aparelho. Por ele chegava um único
quadro, vindo do `refreshFrame()`, e a moldura congelava nele para sempre.

Os dois caminhos passaram a usar a mesma rotina, `activateDevice()`: medida,
primeiro quadro, árvore e espelho ao vivo.

### Um segundo defeito que o teste revelou

No `device.changed`, `refreshDevices()` rodava **antes** da ativação. Um
`devices.list` que voltasse vazio por um instante zerava o alvo recém-anunciado,
e a ativação então não acontecia.

Isso não é hipotético: acontece com USB instável, que é exatamente o que esse
aparelho vinha apresentando. A releitura da lista passou para depois — o aviso é
autoridade sobre a chegada, a lista não é.

### Cobertura

Dois testes novos, um deles comparando os dois caminhos e exigindo que terminem
no mesmo estado, que é o que impede a divergência de voltar. Front 67 → 69.

Verificado depois da correção: o motor do app passou a disparar captura a cada
segundo, contra zero antes.

---

## Workspace deixou de ser fachada (08/09)

### Editor de código

Duas coisas trocadas de uma vez:

**Numeração de linha.** Era uma coluna que desenhava `Text("1")` fixo — qualquer
arquivo aparecia com uma linha, e o número nem acompanhava a rolagem. Virou
`LineNumberRuler`, régua do próprio `NSScrollView`, que rola junto e conta as
linhas do texto real.

**Coloração Python.** O editor mostrava tudo numa cor só. Como o produto inteiro
existe para produzir Python, ler o resultado sem distinguir palavra-chave de
string era trabalho a mais justamente no artefato final. `PythonHighlighter` é
um colorizador léxico: comentário, string, palavra-chave, número, nome de função
e classe, e as CONSTANTES em caixa alta, que são os locators gerados.

A posição do cursor é preservada na recoloração — sem isso, cada passo gravado
jogava o cursor para o início de quem estivesse editando.

### Copiar, Salvar e Limpar

Os três tinham corpo vazio.

- **Copiar** vai para a área de transferência do sistema, não pelo motor: a área
  de transferência é da máquina de quem usa, não do processo do motor.
- **Salvar** virou `codegen.save` no contrato, porque a convenção de nome e
  pasta é regra do produto e as duas interfaces precisam produzir o mesmo
  layout. Escreve `pages/<chave>.py` e `locators/<chave>.py` em
  `~/Documents/Mo baile/`. O conteúdo enviado é o **dos editores**, e não o que
  o motor tem guardado: os campos são editáveis, então o que está na tela é o
  que vale.
- **Limpar** zera passos e editores.

O nome do arquivo no cabeçalho passou a vir de `page_objects_key`, exposto agora
em `engine.info`. Antes era "feature.py" fixo, que não correspondia ao que o
Salvar escreve.

### Barra de abas

Era `Text("Tabs: Page Objects | Rede HTTP | Analytics")` e
`Text("Strategy: ID | XPath | Coords")` — texto literal que parecia controle. A
troca de aba acontecia por outro caminho e essa barra não participava dela.

Agora são dois `SegmentedControl`, com contagem por aba para não ser preciso
entrar na aba para saber se há o que ver nela.

- **Estrutura · N** abre o `StructureDialog`, que já existia pronto e não estava
  ligado: tabela ordenada dos passos gravados.
- **Split** alterna entre os dois editores lado a lado e só o de ações.
- **Rodar** executa o fluxo.

### Execução de fluxo no contrato

`services/flows.py` estava implementado e testado desde sempre, e só a interface
Tk o usava — o front nativo não tinha como rodar automação nenhuma.

Três métodos novos: `flow.run`, `flow.stop`, `flow.status`. O andamento sai como
notificação `flow.log`, linha a linha, do mesmo jeito que o espelho usa
`stream.frame`, e o fim como `flow.finished`.

Isso passou a alimentar `runLog`, `currentRunStep` e `runState` — os três campos
que as telas liam e ninguém escrevia.

`flow.stop` marca a intenção e avisa a interface, sem matar o processo no meio
de um toque.

### Contrato

37 → 41 métodos. Fixtures regeradas.

---

## Escolha de localizador, no modelo do Maestro Studio (08/09)

O Maestro Studio é baseado em snapshot: captura mais hierarquia, desenha os
limites dos elementos por cima e, ao clicar, **escolhe o seletor sozinho** a
partir dos atributos, mostrando o comando pronto. Não é vídeo ao vivo — recaptura
após cada ação.

Comparando com o que já existia aqui, o overlay de hover e a resolução do clique
já eram equivalentes. A diferença estava na escolha do seletor.

### O buraco

A estratégia era uma só para a sessão inteira e escolhida na mão: ID, XPath ou
Coords. Isso produz passo instável, porque o mesmo `resource-id` pode casar com
vários elementos da tela e o passo passa a depender de qual deles o Appium
encontre primeiro.

Medido no aparelho físico: na tela inicial, o id do elemento clicado casava com
**15 elementos**. A gente emitia esse id assim mesmo.

### O que passou a existir

`rank_locators` ordena os candidatos por robustez — identificador, rótulo de
acessibilidade, texto, caminho na árvore, coordenada — e **confere a unicidade
contra a tela inteira**, que já está carregada no momento da gravação. Candidato
ambíguo vai para o fim.

Cada candidato carrega o motivo, para a tela poder mostrar o que foi descartado
e por quê: sem isso o usuário não tem como discordar com fundamento.

`codegen.record` aceita `strategy: "auto"`, que passou a ser o padrão da
interface, e devolve a estratégia escolhida mais as alternativas avaliadas.

Verificado no aparelho: com o id casando 15 vezes, o motor rebaixou o id e
escolheu o XPath, que era único.

### Cobertura

Motor 196 → 201.

---

## A coluna do workspace sumia: era o NSRulerView (08/09)

Sintoma: a coluna direita aparecia vazia, sem barra de abas, sem cabeçalho dos
editores, só o rodapé lá embaixo.

### Como foi isolado

O ambiente ganhou acesso a `screencapture`, o que permitiu capturar a janela
real e bissectar sozinho, sem depender de descrição. A sequência:

1. Coluna inteira trocada por um retângulo vermelho → **apareceu**. Logo a
   coluna renderiza e está no lugar certo.
2. Barra de abas trocada por barra vermelha de 200pt → não apareceu, mas o
   detector de cor estava com limiar errado (o vermelho sai lavado na captura).
   Isso quase me levou a uma conclusão falsa; olhar a imagem, e não o limiar,
   corrigiu.
3. Coluna renderizada isolada em 440x950, a medida real → **correta**.
4. Só a régua de numeração desligada → **tudo apareceu**.

### A causa

`LineNumberRuler` era um `NSRulerView`, o caminho idiomático do AppKit. Ligar
`rulersVisible` no `NSScrollView` dentro do `HSplitView` da janela fazia o
scroll view pedir uma altura enorme. O `VStack` da coluna dava tudo a ele, e a
barra de abas e os cabeçalhos eram espremidos a zero.

O teste de renderização isolada **não pegava**: `ImageRenderer` não desenha view
do AppKit, então o `NSScrollView` nunca chegava a distorcer o layout ali. Era um
defeito que só existia na janela real.

### A correção

`CodeTextView` desenha os números na própria margem esquerda, dentro do
`draw(_:)`. Não mexe em métrica de layout nenhuma, e a numeração rola junto com
o texto de graça.

### Segundo defeito, encontrado no caminho

A barra de abas não cabia na coluna. Com as três colunas abertas ela fica em
440pt, e o conteúdo somado passa de 1000pt: as abas transbordavam para fora dos
dois lados.

Agora ela tem modo estreito, em duas linhas: abas em cima; seletor de estratégia
como menu e ações em ícone embaixo. Mesma solução que a barra superior já usava,
que eu não tinha aplicado aqui.

### Lição de processo

Snapshot isolado não substitui olhar a janela. Os dois defeitos acima passavam
por build, por 71 testes e por renderização isolada, e só apareciam em execução.

---

## Escuta passiva: gravar o que se faz no aparelho (08/09)

Objetivo: agir no aparelho ou simulador e ver o passo aparecer em Page Objects,
sem clicar no espelho.

### O que existe agora

`passive.start`, `passive.stop`, `passive.status` no contrato, mais as
notificações `passive.step`, `passive.text` e `passive.skipped`.

O botão "Gravar do aparelho" liga e desliga, e fica vermelho enquanto grava.

### Android: funciona, e a conversão importa

Lê `/dev/input` pelo `getevent`. Verificado no moto g55 sem root: leitura
permitida, touchscreen identificado como `event8` (`fts_ts`).

O detalhe que decide se presta: o digitizer tem resolução própria. Neste
aparelho vai a **4320x9600 para uma tela de 1080x2400** — fator 4. Sem a
conversão, todo passo sairia a quatro vezes a distância. Os limites são lidos do
próprio aparelho e conferidos.

A falha de leitura desses limites era engolida por `except Exception: pass`.
Era o pior lugar possível para silêncio: a escuta seguiria funcionando e
gravando tudo errado. Agora é log explícito.

### iOS: só simulador

Observa o clique do mouse sobre a janela do Simulator. **Em iPhone físico não há
como observar toque** — não existe API para isso, e nenhuma implementação muda
esse fato.

E um erro de espaço de coordenada que valia corrigir: `screen.size` no iOS mede
a **captura, em pixels**; o WDA trabalha em **pontos**. Medido no iPhone 16e:
1170x2532 contra 390x844, fator 3. A escuta usa a raiz da árvore do WDA, que é a
fonte certa. A interface Tk usava o padrão fixo 390x844 do construtor, que
acerta neste simulador por coincidência e erra em qualquer outro.

### Digitação: cada tecla é um toque

Digitar "joao" numa busca são quatro toques em coordenada de teclado. Sem
tratamento, viravam quatro passos de clique — lixo que não reexecuta.

Enquanto o teclado está na tela (`dumpsys input_method`, ~60 ms), os toques são
suprimidos. Quando ele fecha, o motor relê a tela, encontra o campo e guarda o
texto observado **no passo**, não no Page Object: o método gerado continua
recebendo `texto` como parâmetro, porque o objeto precisa servir para qualquer
valor; quem repete a execução é o passo.

### O que falta verificar

O caminho `getevent` → passo só pode ser confirmado com um toque físico de
verdade. `sendevent` exige root neste aparelho, então não deu para sintetizar.
Tudo antes disso está verificado: permissão, identificação do touchscreen,
limites do digitizer e a conversão.

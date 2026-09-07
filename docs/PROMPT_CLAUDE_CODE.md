# Prompt para o Claude Code local

Cole o bloco abaixo numa sessão do Claude Code aberta na raiz do projeto.

---

Você está no **Mo baile**, um inspetor de UI, espelho e gerador de Page Objects
para automação mobile (iOS e Android), em `~/Documents/antigravity/epic-fermi`.

Antes de mexer em qualquer coisa, leia `docs/ARQUITETURA.md`,
`docs/ESTADO_ATUAL.md` e `docs/PROTOCOLO_RPC.md`. Eles descrevem a arquitetura,
o que funciona, o que é fachada e o contrato entre as duas linguagens.

## Arquitetura em uma frase

Motor Python headless em `engine/` com fronteira JSON-RPC 2.0 sobre stdin/stdout,
front SwiftUI em `apps/MoBaile/` que consome esse contrato, e uma interface
Tkinter legada em `apps/tk-legacy/` que está em transição e ainda é o que roda
em produção.

**Regra inegociável: lógica nova vai para o motor, não para a view.** Se a mesma
regra aparecer em Python e em Swift, uma das duas está errada e ninguém vai
descobrir qual até um cliente reclamar. Exceção: comportamento genuinamente de
interface (animação, atalho, layout, projeção de coordenada na tela).

## Estado atual

- Motor: 156 testes passando, `ruff` limpo, `bandit` sem achado médio ou alto
- Contrato: 34 métodos RPC
- O front Swift compilou pela última vez em 07/09 00:57

## Tarefa 1, e é a mais importante

Uma leva recente de Swift **ainda não passou pelo compilador**. Rode:

```bash
cd apps/MoBaile && swift build && swift test
```

Corrija o que quebrar. Os arquivos não verificados são:

- `Sources/MoBaile/Engine/EngineDTO.swift` (structs novas: `Diagnostics`,
  `PlatformDiagnostics`, `Check`, `SimulatorList`, `Simulator`, `BootResult`,
  `AvdList`, `AvdBootResult`, `WDAStatus`, `WDAStartResult`)
- `Sources/MoBaile/Engine/EngineSession.swift` (`refreshEnvironment`,
  `bootSimulator`, `bootEmulator`, `startWDA` e as propriedades `diagnostics`,
  `simulators`, `avds`, `lastScan`, `isBooting`)
- `Sources/MoBaile/Views/EmptyState/DiagnosticCard.swift` (assinatura mudou por
  completo: antes recebia `items: [(String, DaemonState)]`, agora recebe
  `diagnostics`, `isBusy`, `action`, `actionTitle`, `actionEnabled`)
- `Sources/MoBaile/Views/EmptyState/EmptyStateView.swift` (reescrito)

Ponto de atenção provável: `EngineSession` é `@MainActor` e as views leem as
propriedades dela direto no `body`. Esse padrão já existe e já compilou em
`StatusBar` e `UnifiedToolbar`, então siga o que aqueles arquivos fazem em vez
de inventar isolamento novo.

Se aparecer erro de tipo nos DTOs, a verdade está nas fixtures reais do motor,
em `apps/MoBaile/Tests/MoBaileTests/Fixtures/engine_payloads.json`. Elas são
geradas pelo próprio motor com `make fixtures`, e `EngineContractTests` as
decodifica. Ajuste o Swift para casar com o JSON, nunca o contrário.

## Tarefa 2: validar com aparelho de verdade

Isso ninguém conseguiu fazer até agora, porque exige um Mac com Xcode, adb e
aparelho conectado. Verifique de ponta a ponta:

1. Abra o app e confira que os cartões de diagnóstico refletem o ambiente real.
   Desconecte o aparelho e veja se eles mudam. **Eles não podem mostrar visto
   verde em "Dispositivo conectado" quando não há dispositivo**, que era
   exatamente o bug da versão anterior.
2. Clique em "Abrir simulador". O simulador deve subir e a janela do Simulator
   vir para a frente.
3. Com o simulador de pé, o botão deve virar "Iniciar WebDriverAgent". Clique.
   Ele sobe o Appium e abre uma sessão XCUITest. Na primeira vez o Appium
   compila o WDA e demora minutos; confirme que a interface avisa isso em vez
   de parecer travada. Log em `~/Library/Logs/mobaile-appium.log`.
4. Com o WDA no ar, confira espelho, hierarquia, toque repassado e gravação de
   passo.
5. Ligue o proxy, navegue no app e confirme que o cabeçalho `Authorization`
   aparece redigido na tabela.
6. Feche o app com o proxy ligado e confirme que **o aparelho continua com
   internet**. O motor desfaz a configuração de proxy no encerramento; se isso
   falhar, o aparelho fica apontando para uma porta morta.

Anote em `docs/ESTADO_ATUAL.md` o que passou e o que não passou.

## Tarefa 3: acabamento

Nesta ordem.

**3a. Ligar os 17 controles inertes do Swift.** A lista completa está em
`docs/ESTADO_ATUAL.md`. A maioria já tem equivalente pronto no motor ou na
interface Python; é ligação, não implementação. Os casos:

- `DeviceDock`: Voltar, Home, Girar, Screenshot. Android tem `input keyevent`
  (4 = back, 3 = home) no `ADBBridge`; iOS tem equivalente no WDA. Exponha no
  contrato como `input.key` e `input.rotate` em vez de resolver na view.
- `DualEditorPane`: Copiar, Salvar, Limpar. Salvar deve escrever
  `pages/<chave>.py` e `locators/<chave>.py`.
- `NetworkToolbar`: Configurar proxy e Exportar HAR. O exportador HAR já existe
  em `apps/tk-legacy/mobaile_tk/http_viewer.py:_export_har`; **mova a lógica
  para o motor** e exponha como `proxy.export_har`, para as duas interfaces
  usarem a mesma.
- `AnalyticsToolbar`: Copiar TSV e Exportar JSON. Idem, já existe em
  `FirebaseAnalyticsListener.export_as_tsv` e `export_as_json`; falta expor no
  contrato.
- `WorkspaceTabBar`: além dos três botões, a barra inteira é texto literal
  (`Text("Tabs: Page Objects | Rede HTTP | Analytics")`). Troque por
  `SegmentedControl` de verdade, ligado a `appState.workspaceTab`, com os
  badges de contagem.
- `FlowRunnerModal`: Abrir log e Interromper. Dependem da tarefa 3b.

**3b. Execução de fluxo no contrato.** `engine/src/mobaile/services/flows.py`
está implementado e testado, mas só a interface Tk o usa. O front nativo não
tem como rodar automação. Exponha `flow.run`, `flow.stop` e uma notificação
`flow.log` (linha a linha, como o `stream.frame` faz). Depois ligue
`FlowRunnerModal` e `TerminalView`, e alimente `appState.runLog`,
`appState.currentRunStep` e `appState.runState`, que hoje são lidos pelas views
e nunca escritos por ninguém.

**3c. Árvore de hierarquia de verdade.** `HierarchyTreeView.buildTree()` devolve
todos os nós com `children: nil` e finge o aninhamento com
`padding(.leading, depth * 18)`. Não há expansão nem recolhimento, que é metade
da utilidade de um inspetor. Cada `UIElement` já traz `parentIdx`; monte a
árvore de verdade com isso e mantenha a busca funcionando (ao filtrar, preserve
os ancestrais dos nós que casam).

## Bugs conhecidos, se sobrar tempo

- `apps/tk-legacy/mobaile_tk/main_window.py:_start_passive_listeners` constrói
  `IOSPassiveListener` sem passar `ios_logical_size`. O listener então usa o
  padrão fixo `(390, 844)` para converter coordenada, mesmo o app já sabendo o
  tamanho real vindo do XML do WDA. Em qualquer simulador fora dessa proporção,
  os toques capturados em modo passivo são gravados na coordenada errada.
- `_generate_contract_assertion` no mesmo arquivo insere um trecho fixo com
  endpoint, status e payload inventados, ignorando o tráfego capturado. Pior:
  chama `wait_for_request`, método que não existe em lugar nenhum do projeto, ou
  seja, gera código que não roda. Ou implemente de verdade a partir do
  `proxy.events`, ou remova o botão.
- `FluidPillButton` está definido três vezes (`main_window.py`,
  `http_viewer.py`, `dialogs.py`), `_draw_round_rect` e a paleta `THEME` duas
  vezes, e há 438 cores hexadecimais espalhadas por três arquivos.

## Regras de trabalho

1. **Não instale nada por cima de `/Applications/Mo baile.app`.** Já aconteceu
   uma vez de a build Swift incompleta substituir o app em uso e derrubar o
   ambiente. Use `make build-native`, que instala como
   `Mo baile (nativo).app`. Promover para o nome principal só depois de a
   tarefa 2 passar inteira.
2. **Mudou o contrato? Rode `make fixtures` e faça commit do resultado.** O CI
   reprova o PR se as fixtures estiverem desatualizadas.
3. **`make check` antes de terminar** (lint, bandit e as suítes Python). Mais
   `swift test` no front.
4. Todo bug que você corrigir ganha teste de regressão, com um comentário
   dizendo o que falhava antes. É o que evita alguém "simplificar" a correção
   daqui a três meses.
5. Não engula exceção com `except Exception: pass`. Erro tipado e log.
6. Comentário explica **por que**, não o que o código já diz.

Comece pela tarefa 1 e me diga o que o compilador reclamou antes de seguir.

# Revisão de UX/UI e acessibilidade, fase 2 (papel `ux`), 26/10/2026

Escopo: app nativo Mo baile 3.11.0 (branch `melhoria/2026-10-26-rodada3`, HEAD `a74407c`) | Superfície: Operate | Plataforma: macOS 14+ (SwiftUI) | Status: rascunho (leitura de código, sem execução)

Rótulos: Verificado (li o trecho exato, ou calculei com a fórmula WCAG a partir dos valores do código) · Inferido (li código ou captura sem executar) · Suposição · Não verificável

Independência: avaliador da mesma família de modelos do gerador do código; é opinião de modelo, não validação com usuários. Nenhum VoiceOver, teclado ou tamanho de texto foi testado ao vivo.

Fluxo avaliado (heurística): "pessoa que escreve teste grava um passo no espelho, roda o fluxo e confere o resultado", com foco em quem usa só teclado ou VoiceOver, e em estados vazios, de erro e de espera. Material: código SwiftUI de hoje, catálogo de capturas `docs/design/telas/` (da 3.3, anterior à Início 2.0, ao Ambiente e à remoção dos modos de clique) e a especificação `docs/design/home/README.md`.

## Limites desta leitura (importante para quem decidir)

- Nesta sessão não existiam as ferramentas Grep e Glob, e Bash estava vetado pelo pedido. Achei os arquivos por tentativa de caminho em `apps/MoBaile/Sources/MoBaile/`. Resultado: li as telas e componentes listados abaixo, mas **não varri o repositório inteiro**. Listas do tipo "todos os pontos que fazem X" (chamadas de `Motion`, usos de `.disabled`, usos de `AccessibilityNotification`) são **mínimos conhecidos**, não exaustivos. O comando para completar cada uma está em "Não verificado".
- Arquivos lidos: `App/MoBaileApp.swift`, `App/CommandRegistry.swift`, `App/CommandPerformer.swift`, `Theme/DesignTokens.swift`, `Theme/ThemeManager.swift`, `Theme/PraiaLightTheme.swift`, `Theme/PraiaDarkTheme.swift`, `Theme/Palettes.swift` (até a linha 140), `Engine/EngineSession.swift` (inteiro), `Views/MainWindow/{ContentView,StatusBar,AppSidebar,EngineStatusBanner}.swift`, `Views/Mirror/{ScreenCanvas,MirrorColumn}.swift`, `Views/Workspace/DualEditorPane.swift`, `Views/Hierarchy/HierarchyTreeView.swift`, `Views/Network/HTTPInspectorView.swift`, `Views/Analytics/AnalyticsInspectorView.swift`, `Views/Report/ReportView.swift`, `Views/Automation/FlowRunnerSheet.swift`, `Views/CommandPalette/CommandPaletteView.swift`, `Views/Home/{HomeView,HomeDaily}.swift`, `Views/Environment/EnvironmentView.swift` (só o cabeçalho), `Views/Settings/SettingsView.swift`, `Views/DesignSystem/{Bars,Indicators}.swift`, `Tests/MoBaileTests/{AccessibilityTests,ToolbarLayoutTests}.swift`, mais os docs do backlog e quatro capturas (03, 04, 08b, 08d).
- Não localizei nem li: o arquivo da toolbar principal (`MainToolbar`), `NoDeviceView`, `AppState`, `CodeEditorView`, `StructureSheet`, `ReportDetailPane`, `ReportCardInspector`, o splash e as telas do Ambiente além do cabeçalho. Por isso D5 fica "não verificado" e a parte de `AppState` das propostas é inferida.

## Veredito

RETRABALHAR de forma pontual (nota ponderada 3,7 de 5; 0 P0, 4 P1, 4 P2). O app tem base de acessibilidade acima da média para um app de ferramenta (rótulos, papéis, `accessibilityValue`, paleta de comandos com motivo e anúncio, faixa do motor que anuncia e respeita Reduzir movimento, contraste do rótulo terciário já calculado). O que falta é consistência: três cantos onde a regra boa não chegou (movimento, motivo do desabilitado, anúncio), um caminho central (gravar passo) só por mouse, e dois sinais que mentem (indicador "Código sincronizado" e botões "Gravar Passo" que não gravam).

### Teste de tronco: PASS (6 de 6), Inferido

Só pelo que a Início mostra (`HomeDaily.swift`, `HomeView.swift`): produto (ícone e "Mo baile" no estado de motor parado), página (título da janela = seção), seções (barra lateral: Início, quatro áreas, Fluxo, Ambiente), opções neste nível (cartões de área com atalho), onde estou (título e subtítulo da janela, item selecionado), como busco (busca da toolbar por área e paleta ⇧⌘P). Não vi a Início 3.11 renderizada: a conclusão vem do código.

### Notas

| Critério | Nota | Evidência | Rótulo |
|---|---|---|---|
| Qualidade de design | 4 | Hierarquia clara nas telas (um cartão em destaque na Início: `HomeView.swift:120-173`; um botão padrão por cartão; área primária no Relatório). Defeito: dois botões "Gravar Passo" sem efeito (ver UX-1) | Inferido |
| Consistência com a marca (no lugar de originalidade) | 4 | Tokens usados em todo o código lido, sem hex cru em views, exceto `TerminalPalette` e dois literais de animação (`ScreenCanvas.swift:73,139`) | Inferido |
| Acabamento | 3 | Terminal com 2,63:1 e 2,86:1 (C1); desabilitado sem motivo em 13 pontos; erros e confirmações na linha de 11 pt da barra de status | Verificado (cálculo) |
| Funcionalidade | 3 | Tarefa principal completa com mouse; por teclado ou VoiceOver, gravar passo só pelo menu de contexto da árvore (`HierarchyTreeView.swift:134-138`) | Inferido |

Nota ponderada = (2x4 + 2x4 + 3 + 3) / 6 = 3,7. Quando oscilei entre duas notas, escolhi a menor.

### Matriz de estados (o ponto forte do app)

| Tela | Vazio | Carregando | Erro | Zero resultados | Observação |
|---|---|---|---|---|---|
| Rede | "O proxy está desligado" com ação (`HTTPInspectorView.swift:29-36`) | "Aguardando tráfego do aparelho…" (:266) | `InlineError` com "Tentar de Novo" (:18-27) | "Nenhuma requisição corresponde ao filtro ou ao escopo." (:267) | Bom |
| Analytics | "Nenhum evento capturado" (`AnalyticsInspectorView.swift:25-31`) | "Aguardando eventos…" (:88) | só barra de status | texto próprio (:88) | Ação some sem motivo quando `canStartAnalytics` é falso (UX-3) |
| Relatório | `ReportStartView` com duas ações (`ReportView.swift:72-107`) | `ReportBusyOverlay` com `.updatesFrequently` (:200-219) | `InlineError` + linha (:22-28) | "Nenhuma validação neste recorte." (:433) | Bom; o fim da operação não é anunciado (UX-2) |
| Hierarquia | "Conecte um aparelho…" | "Lendo a hierarquia…" | status | "Nenhum elemento encontrado" (`HierarchyTreeView.swift:36-42`) | Bom |
| Page Objects | "Nenhum passo gravado" (`DualEditorPane.swift:36-45`) | n/a | status | n/a | Ação "Gravar Passo" não grava (UX-1) |
| Fluxo (sheet) | "Pronto" | "Em execução" | "Falha" + linha FAIL no terminal | n/a | Causa só no log cru; sem resumo (H-04) |
| Início | "Nada por aqui ainda…" com ação (`HomeDaily.swift:551-561`) | "Conferindo o ambiente…" | motor parado com próximo passo (`HomeView.swift:62-116`) | n/a | Bom |

## Avaliação heurística (fluxo: gravar, rodar, conferir)

Usuário: quem escreve teste de app mobile, no Mac, frequência diária; subconjunto que usa teclado ou VoiceOver. Esta avaliação é opinião de modelo; recomendo validar os três achados mais graves (H-01, H-03, H-09) com usuários.

| ID | Heurística | Local | Evidência | Sev. | Frequência / impacto / persistência |
|---|---|---|---|---|---|
| H-01 | 7 flexibilidade e atalhos; WCAG 2.1.1 Teclado (A) | Espelho e árvore | `ScreenCanvas.swift:117-129`: só `onTapGesture`, `accessibilityElement(children: .ignore)`, sem `accessibilityAction`, e o valor diz "Clique: toca no aparelho e grava o passo". `CommandRegistry.swift:23-72`: nenhum comando grava passo. Único caminho sem mouse: menu de contexto da linha da árvore (`HierarchyTreeView.swift:134-138`) | 3 | todo uso do produto; sem contorno fácil; permanente |
| H-02 | 4 consistência; 1 visibilidade | Barra lateral `+` e estado vazio | `AppSidebar.swift:262-276` e `DualEditorPane.swift:41-45`: o botão "Gravar Passo" só escreve uma mensagem na barra de status | 2 | primeira vez de cada pessoa; baixo impacto, mas ensina errado |
| H-03 | 1 visibilidade do estado; WCAG 4.1.3 Mensagens de status (AA) | Barra de status | `StatusBar.swift:34-41`: erro e informação com a mesma cor, uma linha de 11 pt, `.updatesFrequently` (não anuncia); `EngineSession.swift:1749-1759` manda todo erro para essa linha; `:1683-1690` fim do fluxo idem; qualquer mensagem seguinte apaga a anterior (ex.: `:1639`) | 3 | todo erro e todo fim de operação; quem usa VoiceOver não ouve nada; persistência a cada uso |
| H-04 | 9 recuperar de erros | Sheet Executar fluxo | captura 08d: "Falha" + `NoSuchElementError: ... não ficou visível em 15 s` só no terminal; rodapé "4 aprovados · 1 falha"; sem frase de causa nem próximo passo. M4 segue aberto no front: `EngineSession.swift:1739` (regex `passo\s+(\d+)`) e `:1683-1690` (sem "cancelado") | 2 | falha de fluxo é comum; impacto médio | 
| H-05 | 10 ajuda e documentação | Início e áreas | Recursos descobertos só por acaso: App em Debug, busca com tokens, ⌘4, Importar Prints. `HomeDaily.swift` não tem dica por recurso; a única dica de uso é a frase do cartão do aparelho (`:338`). A4 segue aberto | 2 | primeira semana de uso; baixo impacto individual |
| H-06 | 1 e 10; WCAG 4.1.2 | 13 controles | desabilitados sem dizer por quê (lista na UX-3). Já existe `disabledReason` no registro, só a paleta o mostra | 2 | frequente; impacto baixo a médio; permanente |
| H-07 | 1 visibilidade (indicador honesto) | Rodapé do editor | `DualEditorPane.swift:131`: `StatusIndicator(status: .ok, label: "Código sincronizado")` fixo; a captura 03 mostra "nenhum passo" e "Código sincronizado" juntos. Após queda do motor, os passos do motor somem (PB3) e o texto do editor fica | 2 | toda abertura do editor | 
| H-08 | WCAG 1.4.3 Contraste mínimo (AA) | Terminal do fluxo | `TerminalPalette.dim` #585B70: 2,63:1 sobre `bgTerminal` claro #15182B e 2,86:1 sobre o escuro #0E0F18 (cálculo abaixo); usado nos horários, `FlowRunnerSheet.swift:139` | 2 | toda execução; leitura difícil de horário | 
| H-09 | WCAG 2.3.3 (AAA) e convenção Apple de Reduzir movimento | Animações | 6 chamadas a `Motion.smooth()` e `Motion.snappy()` sem o parâmetro e 2 literais ignoram a preferência do sistema (UX-4) | 2 | só quem ligou a preferência; vestibular; permanente |
| H-10 | 4 consistência; 2 linguagem do usuário | Textos | "Sem dispositivo"/"Nenhum dispositivo" (`ContentView.swift:117,126`) contra "Sem aparelho" (`AppSidebar.swift:294`, Início); "Configurar Proxy" (`HTTPInspectorView.swift:34,105`) contra "Iniciar Proxy" (`CommandRegistry.swift:385`); "Executar fluxo · fluxo" (`FlowRunnerSheet.swift:21`, captura 08b); "Video salvo" (`EngineSession.swift:1154`) e "nao aceitou a configuracao" (`:1303`) sem acento | 1 a 2 | todos os usuários; cosmético |
| H-11 | WCAG 4.1.2 Nome, função, valor (A) | Linhas da árvore | `HierarchyTreeView.swift:229,241`: o botão Expandir/Recolher fica dentro de `accessibilityElement(children: .combine)`; no SwiftUI o combine costuma descartar a ação do filho. Inferido: precisa ser ouvido no VoiceOver | 2 a 3 | todo uso de árvore por VoiceOver; depende da confirmação |

Trade-offs a validar (não são defeitos): (a) o clique no espelho tocar e gravar sempre (3.10.0) é escolha defensável e simplifica; o teste que decidiria é observar alguém gravando um fluxo de 20 passos e ver se erra clique; (b) menus do macOS não mostram motivo de item desabilitado, então o motivo precisa estar na paleta e no `.help` do controle.

Contraste calculado (fórmula WCAG, valores dos arquivos `Theme/*.swift`):

| Par | Razão | Passa 4,5:1 |
|---|---|---|
| `TerminalPalette.dim` #585B70 sobre #15182B (`bgTerminal` claro) | 2,63:1 | não |
| `TerminalPalette.dim` #585B70 sobre #0E0F18 (`bgTerminal` escuro) | 2,86:1 | não |
| `TerminalPalette.muted` #7F849C sobre os mesmos | 4,75:1 e 5,17:1 | sim |
| `syntaxComment` claro #7A8E98 sobre #FFFFFF | 3,41:1 | não |
| `syntaxGutter` claro #9AAAB4 sobre #FFFFFF | 2,39:1 | não |
| `syntaxGutter` escuro #585B70 sobre #18181E | 2,65:1 | não |
| `labelTertiary` claro (navy 62%) sobre #FFFFFF e sobre a sidebar #E6E7EE | 4,94:1 e 4,57:1 | sim |
| Branco sobre `accent` #C2456E | 4,81:1 | sim |

As três linhas de sintaxe são **Inferido** quanto ao uso (não li `CodeEditorView` para confirmar que o editor desenha comentário e número de linha com esses tokens sobre `bgContent`). As paletas alternativas herdam sintaxe e terminal da Praia (`Palettes.swift:125-127`), e o `PaletteCheck` conferido em código cobre rótulo terciário sobre os fundos de texto (`:98-111`), não esses pares: Inferido, não li `PaletteTests`.

## Propostas (até 5, maior ganho por risco)

Resumo: todas são só de front (nenhuma mexe no contrato RPC nem é regra de negócio) e cabem no corte. Soma estimada, sem testes e docs: 350 a 420 linhas. Ordem sugerida se o teto da rodada for apertado: UX-4, UX-3, UX-1, depois UX-2 e UX-5.

### UX-1 · Gravar passo sem mouse e botão "Gravar Passo" que grava (origem M18; achado novo H-02, H-11)

Problema: o passo só é gravado por clique no espelho (`ScreenCanvas.swift:117-129`, sem ação de acessibilidade, e o valor ainda manda "clicar") ou pelo menu de contexto de uma linha da árvore (`HierarchyTreeView.swift:134-138`). Não há comando no registro (`CommandRegistry.swift:23-72`), no menu nem na paleta. Dois botões "Gravar Passo" não gravam: `AppSidebar.swift:262-276` e a ação do estado vazio em `DualEditorPane.swift:41-45` só escrevem uma mensagem. A premissa do M18 mudou: desde a 3.10.0 gravar e tocar são a mesma coisa (CHANGELOG 3.10.0; comentário em `HierarchyTreeView.swift:132-133`), então "Gravar/Tocar no Selecionado" vira um comando só. O botão Expandir/Recolher da linha da árvore pode estar inalcançável pelo VoiceOver (`:229,241`, Inferido).
Evidência: Verificado (leitura dos trechos); o efeito no VoiceOver é Inferido.

Melhoria:
1. `CommandID.recordSelected` ("Gravar Passo no Elemento Escolhido", categoria Gravação, símbolo `record.circle`) em `CommandRegistry`, com `disabledReason` "Conecte um aparelho" sem aparelho e "Escolha um elemento na árvore ou no espelho" sem seleção (novo campo `hasSelectedElement` em `CommandContext`). Execução em `CommandPerformer`: vai para Page Objects e chama `session.record(at: elemento.center)`, o mesmo caminho do menu de contexto. Entra nos menus Dispositivo ou Automação por `item(...)` (já lê o registro). Atalho: a decidir; não usar Return puro (já foi descartado na revisão de 14/10: Return não deve tocar o aparelho) nem ↩ com ⌘ sem testar conflito com os campos de busca.
2. `ScreenCanvas`: `.accessibilityAction(named: "Gravar passo no elemento escolhido")` e trocar o texto do valor para algo que não prometa clique ("N elementos na tela. Use a ação Gravar Passo para tocar e gravar o elemento escolhido").
3. `HierarchyRow`: `.accessibilityAction(named: expanded ? "Recolher" : "Expandir", toggle)` para a linha combinada.
4. Os dois botões "Gravar Passo" passam a executar `recordSelected` quando há elemento escolhido; sem elemento, ficam desabilitados com o motivo (UX-3). Texto com objeto: "Gravar Passo em Continuar".

Ganho: quem usa teclado ou VoiceOver completa a tarefa principal; some um controle que ensina errado; reaproveita o registro (menu, paleta e botão leem a mesma regra).
Esforço: P a M (cerca de 120 linhas). Risco: baixo; a ação já existe em `session.record`. Atenção: o atalho novo precisa de `CommandShortcut.display` correto (a tecla Return hoje imprimiria `\r`).
Contrato RPC: não. Regra de negócio: não.
Critério de aceite: com um elemento escolhido na árvore, o comando aparece habilitado no menu e na paleta, e executá-lo acrescenta um passo e toca; sem elemento ou sem aparelho, a paleta mostra o motivo. O nó do espelho na árvore de acessibilidade expõe a ação nomeada. O botão `+` da barra lateral não escreve mais só uma mensagem.
Como verificar (vermelho antes, verde depois): `CommandRegistryTests`: `CommandRegistry.command(.recordSelected, in:)` é `nil` hoje (teste falha), depois habilitado/desabilitado conforme `hasSelectedElement`. `AccessibilityTests`: ampliar `AccessibilityInspector` para ler ações e conferir o nome da ação do espelho e da linha da árvore. Passada manual com VoiceOver para H-11 (confirma ou refuta a inferência do `.combine`).

### UX-2 · Erros e fim de operação visíveis e anunciados, e ortografia das mensagens (origem M21; achado novo H-03, H-10)

Problema: o canal de feedback de quase tudo é `appState.statusMessage`, desenhado em uma linha de 11 pt, na mesma cor para erro e para informação, com o trait `.updatesFrequently`, que não faz o VoiceOver falar (`StatusBar.swift:34-41`). `report(_:)` (`EngineSession.swift:1749-1759`) e o fim do fluxo (`:1683-1690`) só escrevem nessa linha, e a mensagem seguinte a apaga (ex.: "Dispositivo conectado", `:1639`). Os únicos anúncios que li são os da faixa do motor (`EngineStatusBanner.swift:101-107`) e da paleta (`CommandPaletteView.swift:266,281`); em `EngineSession` não há nenhum. O fim da gravação de tela (`:1144-1162`) também só escreve na linha. Duas mensagens estão sem acento: "Video salvo" (`:1154`) e "nao aceitou a configuracao automatica" (`:1303`).
Evidência: Verificado em `EngineSession.swift` (li o arquivo inteiro), `StatusBar.swift`, `FlowRunnerSheet.swift`. Não li `AppState`; outro ponto de anúncio fora desses arquivos é possível.

Melhoria:
1. Um único ponto `StatusAnnouncer.post(_:)` que envolve `AccessibilityNotification.Announcement(...)`, injetado na `EngineSession` (parâmetro com padrão real, para testar). Chamado só em três lugares, como o backlog pede para não virar ruído: fim do fluxo ("Fluxo concluído" ou "Fluxo falhou", mais a mensagem do motor limitada a cerca de 140 caracteres), erro em `report(_:)` ("Erro: …") e fim da gravação de tela ("Vídeo salvo").
2. Severidade na barra de status: `AppState.statusKind` (`info` ou `error`), definido como `error` por `report(_:)` e zerado na próxima mensagem comum; a `StatusBar` mostra ícone de erro e cor `destructive` quando `error`, e mantém o `.help` com o texto inteiro.
3. Corrigir as duas mensagens: "Vídeo salvo: …" e "Proxy no ar, mas o aparelho não aceitou a configuração automática."

Ganho: quem usa VoiceOver passa a saber que o fluxo terminou ou falhou; erro deixa de parecer informação; texto correto em pt-BR.
Esforço: P (cerca de 90 linhas). Risco: baixo a médio; anúncio demais incomoda, por isso só os três; a forma exata de `AppState.statusMessage` é Inferida.
Contrato RPC: não. Regra de negócio: não.
Critério de aceite: com `FakeEngine`, entregar `flow.finished` com `success: false` chama o anunciante uma vez com texto que começa por "Fluxo falhou"; `report(_:)` chama com "Erro:"; a barra de status marca o erro e a próxima mensagem comum o limpa. As mensagens saem com acento.
Como verificar (vermelho antes): teste em `EngineSession` com o anunciante injetado, hoje inexistente (falha na compilação do teste, que é o vermelho esperado); `StatusBarTests` de severidade; teste de string para as duas mensagens (se algum teste atual compara o texto sem acento, ajustar junto).

### UX-3 · Controle desabilitado sempre com o motivo, lendo do registro (origem M22; achados H-06)

Problema: o registro de comandos já sabe o motivo de cada desabilitado (`CommandRegistry.swift:248-257` e as condições nas linhas 392, 397, 429, 434, 438, 442, 446, 455, 459), mas só a paleta o mostra. As views repetem a condição em `.disabled(...)` sem explicar, e o próprio registro admite a duplicação (`:10-12`: "repete as condições `.disabled` que já existiam nas views"). Dois lugares com a mesma regra divergem com o tempo. Pontos conhecidos (13, mínimo): `HTTPInspectorView.swift:99,117,125`; `DualEditorPane.swift:100,195,202,207`; `AppSidebar.swift:273`; `MirrorColumn.swift:44`; `ReportView.swift:160`; `FlowRunnerSheet.swift:61,71`; `AnalyticsInspectorView.swift:29-30` (a ação do estado vazio some sem dizer por quê). Em `HTTPInspectorView.swift:125` ("Limpar Tráfego") nem há `.help`. Menus do macOS não mostram motivo de item desabilitado, então o motivo precisa estar no controle e na paleta.
Evidência: Verificado (leitura). Suposição: que `.help` apareça em `Button` desabilitado no macOS; precisa de uma conferência manual.

Melhoria: um modificador `.availability(_ id: CommandID)` (ou `.disabledReason(_ motivo: String?)`) que aplica `.disabled(motivo != nil)`, `.help(motivo ?? ajudaNormal)` e `.accessibilityHint(motivo ?? "")`. Os controles que já têm comando leem o motivo de `CommandRegistry.command(id, in: .current(...))`: Exportar HAR, Limpar Tráfego, Estrutura, Copiar, Salvar, Limpar Passos, Auditar, App em Debug, Iniciar Escuta. Os que não têm (Correlação, Abrir Log, Concluir enquanto roda) ganham três motivos novos em `Motivo`: "Conecte um aparelho", "Nenhuma saída para abrir ainda", "Espere o fluxo terminar ou interrompa". Remove as condições duplicadas das views.

Ganho: o motivo aparece no tooltip e é lido pelo VoiceOver; uma regra só por ação; menos código nas views.
Esforço: P (cerca de 110 linhas, 13 edições de uma linha). Risco: baixo; a única dúvida é o tooltip em controle desabilitado (Suposição), e o `.disabled` do menu não muda.
Contrato RPC: não. Regra de negócio: não.
Critério de aceite: para cada ponto da lista, o `.help` do controle desabilitado é o `disabledReason` do registro (ou um dos três motivos novos); habilitado, volta ao texto de ajuda de hoje; nenhuma view repete a condição.
Como verificar: teste puro do modificador (motivo `nil` e não `nil`); `AccessibilityTests` conferindo o hint de "Exportar HAR…" sem tráfego; conferência manual do tooltip em controle desabilitado no app real.

### UX-4 · Reduzir movimento num ponto só (origem M20; H-09)

Problema: `Motion.smooth()` e `Motion.snappy()` têm `reduceMotion: Bool = false` (`DesignTokens.swift:331-338`), e quem esquece de passar o valor anima mesmo com a preferência ligada. Chamadas sem o parâmetro: `CommandPerformer.swift:44,46,48,50`, `DualEditorPane.swift:110`, `HierarchyTreeView.swift:224`. Literais que nem usam `Motion`: `ScreenCanvas.swift:73` (`.easeOut(duration: 0.12)` na caixa de seleção) e `:139` (`.easeOut(duration: 0.3)` com `scaleEffect` de 0,6 a 1,6 no toque). O `CommandPerformer` não é `View`, então não lê `@Environment(\.accessibilityReduceMotion)`. Pontos corretos hoje, que servem de modelo: `EngineStatusBanner.swift:77,97,100` e `ProgressBar` (`Indicators.swift:123,136`). O catálogo do design system promete "Com Reduzir movimento, tudo vira crossfade" (`docs/CONTEXTO_DO_PROJETO.md`, seção Material e movimento).
Evidência: Verificado (6 chamadas e 2 literais, como o backlog dizia); pode haver mais chamadas que não li.

Melhoria: `Motion.systemReducesMotion` (lê `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) como valor padrão de `reduceMotion` em `smooth` e `snappy`; os dois literais de `ScreenCanvas` passam a usar `Motion` (com a preferência ligada, o toque vira só um piscar de opacidade, sem escala). A view que já tem o `@Environment` continua passando o valor. Com isso F4 (realce de linha nova) nasce correto.

Ganho: a preferência de sistema vale em todo o app, inclusive em código que não é `View`.
Esforço: P (cerca de 30 linhas). Risco: baixo; atenção com o modo estrito de concorrência do Swift 6 (R4) se a propriedade de teste for global mutável (usar `@MainActor` ou injeção).
Contrato RPC: não. Regra de negócio: não.
Critério de aceite: com a preferência ligada, `Motion.smooth()` e `Motion.snappy()` devolvem `.linear` curto sem argumento; o toque no espelho não escala.
Como verificar (vermelho antes): `MotionTests` com um provedor injetável que devolve `true`: hoje `Motion.smooth()` devolve a mola (teste falha), depois `.linear(duration: 0.18)` (`Animation` é `Equatable`).

### UX-5 · Contraste do terminal e indicador de código honesto (origem C1; achados H-07, H-08)

Problema: `TerminalPalette.dim` #585B70 dá 2,63:1 no claro e 2,86:1 no escuro sobre o fundo do terminal (cálculo acima), e é usado nos horários de cada linha (`FlowRunnerSheet.swift:139`); `muted` #7F849C passa (4,75:1 e 5,17:1). O indicador `StatusIndicator(status: .ok, label: "Código sincronizado")` é fixo (`DualEditorPane.swift:131`): aparece verde com "nenhum passo" (captura 03) e continua verde depois de uma queda do motor, quando os passos do motor somem e o texto do editor fica (PB3; `EngineSession.swift:517-549` não relê passos nem limpa o código, Inferido). Achado novo, Inferido quanto ao uso: comentário e número de linha do editor em 3,41:1, 2,39:1 e 2,65:1 (tabela acima), e as paletas alternativas herdam esses tokens sem conferência.
Evidência: Verificado para o terminal e o indicador; Inferido para a sintaxe.

Melhoria:
1. `dim` passa a ser pelo menos `muted` (ou um tom entre os dois com 4,5:1 nos dois fundos); a distinção do horário vem de tamanho ou peso, não de contraste baixo.
2. O rodapé do editor mostra o estado real: sem código, nada; texto do editor diferente do último gerado, "Editado à mão" em aviso (o `saveCode` já grava o que está na tela, `EngineSession.swift:1189-1203`); caso contrário "Gerado dos passos" em ok. Só texto e ícone; sem cor sozinha.
3. Para a sintaxe: levar `syntaxComment` e `syntaxGutter` a 4,5:1 nas duas aparências, ou registrar a decisão de que número de linha é decorativo; incluir o terminal e a sintaxe no `PaletteCheck`, para as nove paletas.

Ganho: leitura dos horários e comentários; um indicador que deixa de afirmar o que não verificou.
Esforço: P (cerca de 50 linhas, mais uma decisão de design nos tons de sintaxe). Risco: baixo; mudar tom de sintaxe mexe nas capturas do catálogo e nas paletas (`PaletteTests`).
Contrato RPC: não. Regra de negócio: não (a comparação "editado" é estado de interface).
Critério de aceite: razão calculada no teste, não estimada: `TerminalPalette.dim` sobre `bgTerminal` de cada tema (Praia e nove paletas) maior ou igual a 4,5; o rodapé não mostra "sincronizado" sem passo nem com texto editado.
Como verificar (vermelho antes): `PaletteTests` ou `TerminalContrastTests` com `PaletteMath` (já existe) sobre `TerminalPalette.dim`: hoje 2,63 e 2,86 (falha). Teste de view do rodapé nos três estados.

## Itens do backlog da minha área: situação hoje

| ID | Situação | Evidência |
|---|---|---|
| M20 | Aberto, confirmado | UX-4; 6 chamadas e 2 literais |
| M22 | Aberto, e maior do que o backlog dizia (13 pontos conhecidos, não 6) | UX-3 |
| C1 | Aberto, números confirmados (2,63:1 e 2,86:1), indicador ainda fixo | UX-5 |
| M18 | Aberto, premissa mudou: "Tocar" separado deixou de existir na 3.10.0 | UX-1 |
| M21 | Parcial: faixa do motor e paleta anunciam (`EngineStatusBanner.swift:101-107`, `CommandPaletteView.swift:266,281`); fim do fluxo, erro e gravação não | UX-2 |
| A4 | Aberto; sem dica por recurso na Início (`HomeDaily.swift`). Não entra no corte: TipKit é framework novo e desenho por recurso (Suposição: funciona no alvo SwiftPM; não testei) | H-05 |
| D5 | Não verificado: não localizei o arquivo da toolbar; o catálogo é de 3.3 e mudou desde então | Não verificado |
| F4 | Aberto: tabela de Rede sem realce de linha nova (`HTTPInspectorView.swift:194-243`). Baixo ganho; depende de UX-4 para nascer correto | Verificado |
| Contraste do rótulo terciário | Já resolvido: alfa calculado a 4,5:1 (`PraiaLightTheme.swift:18-19`, `PraiaDarkTheme.swift:18-19`; 4,94:1 e 4,57:1 no claro) | Verificado (cálculo) |
| D6 tokens de busca, D7 escopo da Rede | Já entregues na 3.6.0 (CHANGELOG, seção F12; `HTTPInspectorView.swift:173-192`, `ContentView.swift:365-390`) | Verificado |
| D8 colunas lembradas | Parcial: Rede e Analytics sim (`HTTPInspectorView.swift:160`, `AnalyticsInspectorView.swift:12`); Relatório não (`ReportView.swift:366` é `Table` sem `columnCustomization`) | Verificado |
| F3 estado restaurado | Parcial: largura de inspector e espelho e divisórias em `@SceneStorage` (`ContentView.swift:110`, `MirrorColumn` via `DetailColumn`); área e inspector aberto não conferi | Inferido |
| Rótulos, papéis, valores de VoiceOver (B5, 2.1.1) | Já feitos e testados (`AccessibilityTests.swift`); a paleta de comandos tem foco, modal, anúncio e `accessibilityAction` | Verificado |

## Decisões pendentes do humano

1. Atalho do comando de gravar (UX-1): ⌥⌘G, ⌥⌘R ou outro sem conflito; Return puro foi descartado.
2. Glossário (H-10): "aparelho" ou "dispositivo". Hoje a UI mistura, e dois testes travam "Sem dispositivo" e "Dispositivo" (`ToolbarLayoutTests.swift:74,110,116`); trocar exige ajustar os testes. Idem "Configurar Proxy" contra "Iniciar Proxy".
3. Tons de sintaxe (UX-5): decisão de design se número de linha é decorativo.
4. Se `AppState.statusKind` (UX-2) é aceitável ou se a barra de status deve virar um componente próprio com histórico.

## Polimento que não entrou nas cinco (P2, uma linha cada)

- "Executar fluxo · fluxo" e "Fluxo · fluxo" quando a chave padrão é "fluxo" (`FlowRunnerSheet.swift:21`, `AppSidebar.swift:58`): omitir o sufixo quando a chave é a padrão.
- "Dispositivo conectado" sem o nome (`EngineSession.swift:1639`): usar o nome do aparelho.
- "Ver Todas as Novidades…" abre o `CHANGELOG.md` cru no editor de texto (`HomeDaily.swift:674-676`).
- Alvos pequenos, Inferido e sem medição: dispensar novidades 18x18 pt (`HomeDaily.swift:654-660`), disclosure da árvore 12x16 pt (`HierarchyTreeView.swift:225`), `BarIconButton` com mínimo 24x22 pt (`Bars.swift:115`).
- Item "Mostrar Splash" no menu Janela (`MoBaileApp.swift:154`) é recurso de desenvolvimento no menu do usuário.

## Não verificado (e como verificar)

- VoiceOver, Controle Total por Teclado, Texto Maior, Aumentar contraste ao vivo: passada manual no app instalado, com o roteiro: gravar passo por teclado, rodar fluxo com falha, ouvir o fim, abrir a árvore e expandir um nó (H-11).
- Listas completas (mínimos conhecidos aqui): `grep -rn "Motion\.\(smooth\|snappy\)()" apps/MoBaile/Sources`; `grep -rn "withAnimation\|\.animation(" apps/MoBaile/Sources`; `grep -rn "\.disabled(" apps/MoBaile/Sources`; `grep -rn "AccessibilityNotification" apps/MoBaile/Sources`; `grep -rn "statusMessage =" apps/MoBaile/Sources | wc -l` (o backlog diz 65).
- `.help` em controle desabilitado: criar uma view mínima e passar o mouse; ou ler o tooltip pela árvore de acessibilidade.
- Início 3.11 e Ambiente renderizadas: o catálogo `docs/design/telas/` ainda é da 3.3 (as capturas `02c`, `02e`, `02f` e `02g` existem, mas não abri); regenerar com `WindowSnapshotTests/testCatalogoDeTelas` e conferir contraste de Início e Ambiente.
- Contraste da sintaxe com o uso real no `CodeEditorView`, e dos tokens de terminal e sintaxe nas nove paletas: estender o `PaletteCheck`.
- D5 (menu » da toolbar): precisa de captura atual.
- Reflow e janela estreita (980x600): coberto por `WindowSnapshotTests.testTelasPequenas`, que não executei.

## Limites da avaliação

Avaliação de modelo, sobre código e capturas antigas; nenhuma execução. Severidade 0 a 4 é minha, por frequência, impacto e persistência, sem dado de uso. Nenhuma afirmação de conformidade com WCAG, LBI ou NBR 17060: os critérios citados são referência de revisão, e o item 2.3.3 é nível AAA (citado pela convenção da Apple, não como requisito AA). Verificação automática é piso; axe ou `performAccessibilityAudit` sem violações não provariam acessibilidade.

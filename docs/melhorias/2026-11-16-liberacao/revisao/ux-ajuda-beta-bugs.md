# Spec: Ajuda por módulo, aviso Beta e Relatar um Problema

Status: rascunho · Plataforma: macOS 14+ (SwiftUI, Liquid Glass no 26) · Sistema: design system do Mo baile (`Glass.swift`, ADR 0006, `docs/design/design-system/readme.md`) · Direção: sistema existente · Rótulos: Verificado (li no código) · Inferido · Suposição
Brief: pessoa que baixa o app pela primeira vez (QA/dev mobile) precisa aprender cada área, saber que o produto está em desenvolvimento e relatar bug sem sair do app · Superfície: Operate
Versão sugerida: 3.24.0 (recurso novo, sem redesenho; não é major pela regra de `semver-ui-drastica-major`)

## 0. Resumo das decisões

| # | Decisão | Por quê |
|---|---|---|
| D1 | Ajuda em **janela própria** (`Window` id `ajuda`), não em sheet, abrindo no capítulo da área atual por ⌘? e por um botão `?` na toolbar | A pessoa precisa ler e operar o app ao mesmo tempo; sheet é modal e bloqueia a janela. |
| D2 | Conteúdo em **Markdown por área**, em `apps/MoBaile/AppResources/Ajuda/<rawValue da WorkspaceTab>.md`, copiado para `Contents/Resources/ajuda/` no empacotamento | O app não usa `Bundle.module` (Verificado: `Resources/` do pacote está vazio, só `.gitkeep`; o script copia recursos à mão em `tools/package_macos_app.sh:134-178`). Mesmo padrão do `CHANGELOG.md` (`HomeDaily.swift:684-690`). |
| D3 | Renderizador próprio e pequeno de um subconjunto de Markdown (blocos por linha + `AttributedString(markdown:)` só no inline) | `Text` do SwiftUI não desenha títulos nem listas do Markdown completo. Sem dependência nova. |
| D4 | Teste que cruza `WorkspaceTab.allCases` com os arquivos, e atalhos citados com o `CommandRegistry` | Documento que diverge do app é pior que nenhum. |
| D5 | Selo **Beta** persistente na **barra de status** (visível mesmo no Modo Zen) e no rodapé da barra lateral; aviso na primeira abertura **por versão maior**; linha no Sobre | A barra lateral some no Modo Zen (`AppState.swift:254-255`); a barra de status não. |
| D6 | Relatar problema em **janela própria não modal** (`Window` id `relato`), **não** como nova `WorkspaceTab` | Não é área de trabalho: uma `WorkspaceTab` nova mexe em ⌘-dígito, matriz de áreas, subtítulo, grade do Início, paleta e testes. E precisa ficar aberta enquanto a pessoa volta ao app para conferir o que aconteceu. Acesso por item fixo no rodapé da barra lateral (parece aba), menu Ajuda, paleta, selo e Sobre. |
| D7 | Dois caminhos de envio: (a) navegador com issue pré-preenchida (sempre existe); (b) serviço intermediário (só se configurado) | (a) não precisa de token nem infraestrutura. (b) melhora anexos e evita login, mas exige serviço. |
| D8 | Dados automáticos **todos desligados por padrão**, com prévia exata do que vai | Consentimento explícito pedido pelo dono. |
| D9 | Nome do recurso: **"Relatar um Problema"**, nunca "Copiar Bug" | "Copiar Bug" já existe no Relatório e significa outra coisa (bug do app auditado do usuário: `ReportDetailPane.swift:56`, `ReportView.swift:439`). Confundir os dois é o risco de copy mais provável. |

## 1. Inventário dos módulos (lido do código das telas)

Fonte da ordem, nome e atalho: `WorkspaceTab` em `Models/Enums.swift:55-90`. O atalho é a posição no enum (`shortcutDigit`, linha 87); o registro publica `⌘<dígito>` (`CommandRegistry.swift:284-291`). Sidebar: Início acima das seções (`AppSidebar.swift:25-31`), seção Workspace com Page Objects, Rede HTTP, Analytics, Relatório, Execução (`:33-56`, `WorkspaceTab.workspaceAreas` `Enums.swift:82`), Ambiente fixo no rodapé (`:214-268`).

| Nome exibido | Atalho | Precisa de aparelho? | Uma linha |
|---|---|---|---|
| Início | ⌘0 | não | Escolher o aparelho, ver o que falta instalar, continuar de onde parou, ler as novidades. |
| Page Objects | ⌘1 | sim | Espelho do aparelho, hierarquia e editor: cada clique no espelho toca no aparelho e grava um passo; os passos viram código. |
| Rede HTTP | ⌘2 | sim | Tabela do tráfego HTTP do aparelho, por proxy ou lendo o app em debug, com detalhe de request e response e exportação HAR. |
| Analytics | ⌘3 | sim | Captura em tempo real dos eventos de Firebase Analytics do aparelho, com busca por evento e parâmetro. |
| Relatório | ⌘4 | não | Audita um log de eventos contra a spec de tagueamento (cards do Figma), parâmetro por parâmetro. |
| Ambiente | ⌘5 | não | O que está instalado nesta máquina, o que cada área precisa e o botão para instalar o que falta. |
| Execução | ⌘6 | não (o aparelho só importa ao rodar) | Roda o `main` do projeto de automação (behave) do dono, como a run configuration do PyCharm, com Doctor, console e vídeo. |

`needsDevice`: `Enums.swift:77`. Quando falta aparelho, a coluna central mostra `NoDeviceView` (`DiagnosticCard.swift:249-300`).

### 1.1 Início (`HomeView.swift:13-60`)
- Três estados: motor parado (`HomeEngineContent`, `:62`), primeira vez (`HomeFirstRunContent`, `HomeFirstRun.swift:7`), uso diário (`HomeDailyContent`, `HomeDaily.swift:8`). O motor decide (`home.summary`).
- Primeira vez: "Boas-vindas ao Mo baile" (`HomeFirstRun.swift:23`), cartão por plataforma com **Preparar iOS…/Android…** que abre o instalador no Terminal (`:211-213`), **Abrir Relatório…** para explorar sem instalar nada (`:80`), link para o Ambiente (`:92`).
- Diário: alvos e aparelhos (`HomeDaily.swift:129-250`, **Resolver…** `:213`, **Instalar Emulador ou Simulador…** `:169`); card do aparelho com **Espelhar e Gravar** (`:384`), **Ver Rede HTTP** (`:386`), **Escutar Analytics** (`:387`), **Rodar Flow…** de um `.yaml` do Maestro, sem internet (`:388-389`); grade de Áreas (`:454-515`); **Continuar de onde parou** + **Ver Tudo** (`:524-575`); **Novidades da versão** com dispensar até a próxima versão (`:640-680`, chave `mobaile.novidadesDispensadas`, `:14`).
- Pré-requisito: só o Python do motor; sem ele a tela diz o que fazer (`HomeView.swift:62`).

### 1.2 Page Objects (`DualEditorPane.swift:15`, coluna: `WorkspaceColumn.swift:24`)
- **Espelho** (`MirrorColumn.swift:8-59`): tela do aparelho ao vivo, fps, chip **Correlação** do último passo com tráfego e eventos (`:41`). Clique no espelho toca no aparelho **e** grava o passo (`UnifiedToolbar.swift:9-12`; `HomeDaily.swift:338`).
- **Inspector**: Hierarquia (árvore de acessibilidade) e Atributos (`AttributesPanel.swift:8-110`, **Copiar Tudo** `:81`). Menu da árvore: Copiar Locator, Copiar XPath, Copiar Atributos, Gravar como Passo (`HierarchyTreeView.swift:122-137`). ⌥⌘I mostra/oculta (`CommandRegistry.swift:295-304`).
- **Editor**: seletor **Auto | ID | XPath | Coords** (`DualEditorPane.swift:248-258`, `Enums.swift:14-30`), arquivo (ações / locators) (`:263`), **Estrutura…** (`:275`), árvore **Projeto** (`ProjectTreeView.swift:113-153`: Atualizar, Revelar no Finder). ⌘S salva (`CommandRegistry.swift:470-477`).
- **Barra de ferramentas** (`UnifiedToolbar.swift:17-70`): aparelho (`:103`), **Gravar do Aparelho** (escuta passiva; no iOS só no Simulator, `:168-205`), **Gravar a Tela** (`:209`), **Espelho 60 FPS** (só Android com scrcpy, `:230-251`), **Rodar Automação** ⌘R (`:256-289`).
- **Fluxo** na barra lateral: passos gravados, com menu Mostrar no Código, Ver na Rede, Ver em Analytics, Copiar Locator/Seletor, Limpar Passos… (`AppSidebar.swift:58-71`, `:146-176`). Texto digitado aparece mascarado (`:195-200`).
- **Estrutura do fluxo** (sheet): Copiar Resumo, **Exportar Flow…** (Maestro, em Documentos › Mo baile › flows), Rodar… (`StructureSheet.swift:5-77`). **Executar fluxo**: Interromper ⌘., Abrir Log, Concluir (`FlowRunnerSheet.swift:9-69`).
- Pré-requisitos (`services/setup.py:190-370`): aparelho conectado; Android: `adb` (sem ele nada funciona, `:195-198`); iOS: Xcode completo, Appium com driver XCUITest (toque, hierarquia e Page Objects no iOS), WebDriverAgent; opcionais: scrcpy, driver UiAutomator2, pyobjc-Quartz (escuta passiva no Simulator).

### 1.3 Rede HTTP (`HTTPInspectorView.swift:8-135`)
- Vazio: "O proxy está desligado" com **Configurar Proxy** (`:33-45`).
- Barra: estado do proxy e porta (`:84`); **Ler Tráfego do App em Debug** (sem proxy nem certificado: CFNetwork no iPhone, OkHttp no Android; `DebugNetCopy`, `:387`); **Configurar/Parar Proxy** (`:104-113`); **Exportar HAR…** ⇧⌘E (`:115-119`); **Limpar Tráfego** (`:121`); **Por que não vejo tráfego?** abre um diagnóstico em popover (`:128-139`, `TrafficDiagnosisView.swift:19`).
- Escopo: Todos · API · Mídia · Erros · Lentas (>1 s) (`HTTPInspectorView.swift:176`, `SearchQuery.swift:160-182`). Busca na toolbar: `status:4xx metodo:POST tipo:json` (`ContentView.swift:366-370`).
- Detalhe Request/Response lado a lado (`:50-55`, `RequestDetailView.swift:68`); menu: Copiar URL, Copiar como cURL, Exportar HAR… (`:246-255`).
- Pré-requisito: aparelho conectado; proxy exige configurar o aparelho (Inferido do texto de `:78-85`).

### 1.4 Analytics (`AnalyticsToolbar.swift`, `AnalyticsInspectorView.swift`)
- Estado da escuta (`:42`), **Iniciar/Parar Escuta** (`:49-57`), no iOS **Origem**: Automático, Simulador ou iPhone por cabo (`:86-101`, trocar exige parar a escuta, `:110`), **Copiar TSV** para Google Planilhas (`:60`), **Exportar JSON…** como `log_obtido.json` (`:68`), **Limpar** (`:75`).
- Tabela de eventos com contagem de parâmetros (`AnalyticsInspectorView.swift:67`). Busca: `evento:screen_view param:chave=valor` (`ContentView.swift:376-380`).
- Pré-requisitos: aparelho conectado e `canStartAnalytics`; iPhone por cabo exige pymobiledevice3 (`setup.py:337-343`).

### 1.5 Relatório (`ReportView.swift`, `ReportToolbar.swift`)
- Vazio: **Importar Prints do Figma…** (gera rascunho da spec por OCR local, `ReportImportSheet.swift`) e **Abrir Spec…** (`ReportView.swift:97-111`).
- Barra: menu da spec (Abrir Spec…, Importar Prints do Figma…, Exportar Checklist…, Reler Spec, Editar Spec, Abrir em Editor Externo, Mostrar no Finder, `ReportToolbar.swift:71-95`); **Origem dos eventos**: Eventos Capturados ou Escolher Arquivo de Log… (`:103-126`); **Plataforma auditada** (`:167`); **Checklist** (`:30-37`); **Auditar** (`:41-47`); **Copiar** TSV/Markdown (`:53-62`); **Exportar** para Documentos › Mo baile › Relatórios: board Excalidraw, HTML, Markdown e TSV (`:183-205`; **Dados do relatório** opcional, `ReportExportSheet.swift:24`).
- Resultado: conformidade em %, filtro Todas · Pedem Ação · Divergentes · Não Disparadas · OK · Fora da Spec (`ReportView.swift:325-331`), detalhe com Obtido x Esperado e print do card (`ReportDetailPane.swift`), **Copiar Bug** (modelo do time para Jira/Azure, `:56`; menu `ReportView.swift:439-440`).
- **Editar Spec**: Quadro ou Tabela, Salvar (`ReportSpecEditorView.swift:65-96`).
- Pré-requisitos: nenhum aparelho. Importar prints precisa de Swift das Command Line Tools (`setup.py:355-367`).

### 1.6 Ambiente (`EnvironmentView.swift:11-110`)
- Cabeçalho com **Verificar de Novo** e hora da checagem (`:99-110`); resumo por grupo (`:182`); pendências com **Instalar no Terminal…** e **Copiar Comando** (`:231-291`); matriz "O que funciona em cada área" por plataforma (`:314-370`); lista de componentes com versão (`HomeComponentGroup`, `HomeView.swift:286`).
- Rodapé da barra lateral mostra a contagem amarela de pendências ou ⌘5 (`AppSidebar.swift:237-249`).
- Componentes (`setup.py`): Python 3.10+ (Pillow, requests), adb, Emulador Android, scrcpy, UiAutomator2, driver USB (Windows), Xcode, Appium + XCUITest, pymobiledevice3, escuta passiva, Swift (leitura de prints).

### 1.7 Execução (`ExecutionView.swift:12`)
- Sem projeto: "Nenhum projeto aberto" + **Abrir Projeto…** + "Abertos antes" (`:108-160`).
- Cabeçalho: projeto, **Confiável**, Recentes, **Abrir Projeto…**, **Esquecer** (`:180-260`).
- Barra de execução: **Aparelho** alvo (Automático = udid da config ativa, senão o aparelho do app, `:300-321`), **Gravar vídeo** (`:324`), **Rodar**/**Parar** (`:340-370`), bloqueio explicado com cadeado.
- Coluna Projeto (lê o `main` sem executar): entrada, interpretador (candidatos com versão do behave, **Usar**, **Voltar à Detecção**), configs (nuvem não roda), suítes, problemas (`ExecutionProjectColumn.swift:89-460`). **Doctor** (**Verificar de Novo**, **Confiar no Projeto e Verificar…**, `ExecutionDoctorPanel.swift:5-96`) e **Console** com busca ⌘F e **Ir para o Fim** (`ExecutionConsoleView.swift:12-41`).
- Resultado: **Abrir Pasta da Execução**, **Abrir Vídeo**, dispensar (`ExecutionView.swift:412-480`). Confirmação antes do primeiro run: "executa o código do projeto nesta máquina, com as suas permissões" (`:528-575`).
- Pré-requisitos: projeto behave com `main.py`/`run.py`/`__main__.py` (`ExecutionProjectColumn.swift:108`), Python do projeto com behave, hub local (config de nuvem não roda).

### 1.8 Transversais
- Barra de ferramentas única, trocando de itens por área: `UnifiedToolbar.swift:17-70` (ordem: título, aparelho, gravações, Rodar, Buscar, Espelho, Inspector).
- Paleta de comandos ⇧⌘P (`CommandPaletteView.swift`); registro único em `CommandRegistry.swift` (menu e paleta leem dele, `MoBaileApp.swift:62-65`).
- Ajustes ⌘, com abas Geral, Desempenho, Paletas, Conexões (`SettingsView.swift:4-24`).
- Barra de status de 22 pt (`StatusBar.swift:9-58`): serviços, mensagem, `PerfBadge`, métricas.
- Menus: Arquivo, Editar, Visualizar, Dispositivo, Automação, Janela (`MoBaileApp.swift:80-160`). **Não há menu Ajuda próprio nem Sobre próprio**: o sistema põe o Help padrão e o Sobre padrão (`AppDelegate.swift:84` só renomeia o item).

## 2. Ajuda dentro do app

### 2.1 Onde fica
1. **Janela "Ajuda do Mo baile"**: `Window("Ajuda do Mo baile", id: "ajuda")` em `MoBaileApp.swift`, ao lado do `Settings` (`:44-51`), com o mesmo `.environment(appState/session/themeManager)`, `.preferredColorScheme` e `.tint`. Tamanho padrão 760x560, mínimo 560x420. Instância única; reabrir traz à frente.
2. **Barra de ferramentas**: novo `ToolbarItem(placement: .primaryAction)` `HelpToolbarButton` depois de `InspectorToggleButton` (`UnifiedToolbar.swift:66-68`). `Label("Ajuda desta Área", systemImage: "questionmark.circle")`; `.help("Ajuda desta Área (⌘?)")`. Vale para todas as áreas (a toolbar é uma só), então abre no capítulo de `appState.workspaceTab`. Em janela estreita o macOS manda para o menu `»` (`UnifiedToolbar.swift:11`): aceitável.
3. **Menu Ajuda** (`CommandGroup(replacing: .help)` em `MoBaileCommands`, depois do bloco Janela, `MoBaileApp.swift:156-160`): **Ajuda do Mo baile** ⌘? (abre no capítulo da área atual), **Todos os Tópicos** (abre em Primeiros passos), divisor, **Relatar um Problema…**, **Novidades da Versão** (abre o CHANGELOG, `HomeDaily.swift:684`). Atalho: `KeyEquivalent("?")` com `.command` (Suposição: confirmar que o macOS entrega como ⇧⌘/ sem conflito).
4. **Paleta**: três `CommandID` novos no `CommandRegistry` (`help.open`, `help.topics`, `help.reportBug`) e `CommandCategory.help = "Ajuda"` (`CommandRegistry.swift:79-90`). O menu lê do registro via `item(_:_:)` (`MoBaileApp.swift:164-175`), como os outros.
5. **Início**: link "Guia do Mo baile" no `HomeHeader` (`HomeDaily.swift:60`) e no estado de primeira vez, abrindo Primeiros passos.
6. Como `CommandPerformer` não tem `openWindow`, `AppState` ganha `windowRequest: AppWindowID?` (`.help(topic)`, `.bugReport`) e o `ContentView` observa com `onChange` e chama `@Environment(\.openWindow)`, no mesmo molde de `commandPalettePresented` (`ContentView.swift:70`).

### 2.2 Estrutura da janela
- Coluna esquerda (`List(selection:)`, 190-220 pt): grupos **Começar** (Primeiros passos), **Áreas** (as 7, com o `symbolName` e `categoryColor` da barra lateral: `AppSidebar.swift:315-340`), **Suporte** (Atalhos do Teclado, Relatar um Problema).
- Coluna direita: `ScrollView` com largura máxima de leitura 640 pt, margem `DesignMetrics.Spacing.windowMargin`. Cabeçalho: título (`DSFont.title1`), resumo (`labelSecondary`), faixa "Precisa de:" com chips, botão **Ir para <Área>** (muda `workspaceTab` e traz a janela principal à frente).
- Campo **Buscar na Ajuda** (`.searchable` na janela): filtra título e texto; sem resultado mostra `EmptyState` ("Nada encontrado" + "Limpar Busca"). P2.
- Superfície: janela comum, fundo `theme.bgContent`, cartões com `dsCard()` (`Content.swift:107`), blocos de código com `CodeBlock` (`Content.swift:112`). **Sem vidro próprio**: a janela e a barra lateral já recebem o do sistema (regra de `Glass.swift:11-15`).
- Tópico **Atalhos do Teclado** é gerado em código a partir do `CommandRegistry.commands(in:)` (não é Markdown): nunca diverge.

### 2.3 Formato dos arquivos
Pasta de origem: `apps/MoBaile/AppResources/Ajuda/`. Nomes:

| Arquivo | Tópico |
|---|---|
| `comecando.md` | Primeiros passos |
| `home.md`, `pageObjects.md`, `network.md`, `analytics.md`, `report.md`, `environment.md`, `execution.md` | uma por `WorkspaceTab` (nome = `rawValue`, `Enums.swift:58`) |
| `relatar-problema.md` | Relatar um Problema |

Escolher `rawValue` como nome de arquivo é o que torna a sincronia testável: nova área sem arquivo quebra o teste.

Cabeçalho (front matter) simples, lido à mão (não é YAML completo: chave `: ` valor, uma por linha):

```
---
area: network
titulo: Rede HTTP
resumo: Veja o tráfego HTTP do aparelho, filtre e exporte em HAR.
precisa: aparelho conectado; proxy ou app em debug
---
```

Seções, nesta ordem, com estes títulos exatos (`##`):
1. `## O que é` — 1 a 2 frases.
2. `## Quando usar` — 2 a 4 itens de lista, cada um um cenário real.
3. `## Passo a passo` — lista numerada de 3 a 6 passos; ação e rótulo do botão em `**negrito**`, igual ao da tela.
4. `## Exemplo prático` — um cenário completo em 4 a 8 linhas ("Você quer descobrir por que o login falha no Android…").
5. `## Recursos` — 4 a 8 itens `**Nome**: o que faz, em até 18 palavras.` (os "textos curtos de cada feature").
6. `## Problemas comuns` — 3 a 5 itens `**Sintoma.** O que fazer.`

Tamanho alvo: 250 a 400 palavras por área (cabe em uma tela e meia), teto de 450; `comecando.md` até 350. Resumo até 110 caracteres.

Subconjunto de Markdown aceito (o parser rejeita o resto no teste): `##`, parágrafo, `- `, `1. `, bloco ``` (código), `> ` (nota; prefixos `Dica:` e `Atenção:` viram ícone + cor `success`/`warning`, sempre com a palavra), inline `**negrito**`, `*itálico*`, `` `código` ``, e links `[texto](mobaile://ajuda/<tópico>)` para outro capítulo ou `https://…` (abre no navegador; só esquemas `https` e `mobaile`). Sem imagens, tabelas nem HTML (cada um é problema de acessibilidade e de manutenção).

### 2.4 Renderização (sem dependência)
- `HelpDocument.parse(_:) -> HelpDocument` (front matter + `[HelpBlock]`): `enum HelpBlock { heading, paragraph, bullets([String]), steps([String]), code(String), note(kind, String) }`. Inline: `try AttributedString(markdown: texto, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`; `code` ganha `DSFont.mono`. Falha de parse inline mostra o texto cru (nunca some).
- `HelpLibrary` localiza a pasta: `Bundle.main.resourceURL/ajuda` e, rodando do código, `EngineLocator.repositoryRoot()/apps/MoBaile/AppResources/Ajuda` (molde de `HomeDaily.changelog`, `HomeDaily.swift:684-690`). Arquivo ausente: o tópico mostra `EmptyState` ("Esta ajuda não veio no app. Reinstale ou abra o Relato de Problema") e o teste falha antes do release.
- `.environment(\.openURL, OpenURLAction { … })` trata `mobaile://ajuda/...` trocando o tópico.
- Empacotamento: `tools/package_macos_app.sh` copia `AppResources/Ajuda` para `$CONTENTS/Resources/ajuda` (junto do `cp` do CHANGELOG, `:171`); `tools/verify_native_app.sh` ganha a conferência "a pasta `ajuda` embutida é idêntica à do repositório" (mesmo estilo da conferência do motor).

### 2.5 Briefs de conteúdo (base dos textos; o redator não inventa além disto)

**comecando** — O Mo baile espelha o aparelho, grava passos, mostra rede e analytics e audita tagueamento, tudo nesta máquina. Passos: 1) abrir **Ambiente** (⌘5) e instalar o que falta; 2) conectar um aparelho (cabo, emulador ou simulador) e escolhê-lo na barra de cima; 3) ir a **Page Objects** (⌘1) e clicar no espelho; 4) abrir **Rede HTTP** ou **Analytics**; 5) **Relatório** funciona sem aparelho. Nota Atenção: produto em desenvolvimento, pode ter bugs, link para Relatar um Problema. Exemplo: primeira gravação de login em 5 cliques.

**home** — Recursos: Aparelho (escolher e resolver pendência), Espelhar e Gravar, Ver Rede HTTP, Escutar Analytics, Rodar Flow… (`.yaml` do Maestro, sem internet), Continuar de onde parou, Novidades. Exemplo: abrir o app pela manhã, ver "Tudo pronto" e entrar em Page Objects. Problemas: aparelho não aparece (Atualizar Lista de Aparelhos ⇧⌘R; Ambiente), "Primeira vez" não sai (Preparar… e Verificar de Novo).

**pageObjects** — Exemplo: gravar "abrir app e tocar em Entrar", escolher seletor **Auto**, ver o código em **Arquivo**, ⌘S para salvar, ⌘R para rodar, **Exportar Flow…** para o Maestro. Recursos: Espelho, Hierarquia e Atributos, Seletor (Auto/ID/XPath/Coords), Gravar do Aparelho, Gravar a Tela, Espelho 60 FPS (Android), Estrutura…, Correlação. Problemas: iPhone físico não grava toques pelo cabo (usar clique no espelho, `UnifiedToolbar.swift:199`), 60 FPS cinza (instalar scrcpy), hierarquia vazia (UiAutomator2 no Ambiente).

**network** — Exemplo: "o login retorna erro": ligar proxy ou **Ler Tráfego do App em Debug**, filtrar `status:4xx`, abrir a requisição, **Copiar como cURL**, **Exportar HAR…**. Problemas: tabela vazia (**Por que não vejo tráfego?**), app com certificate pinning (usar leitura em debug), proxy não inicia (porta em uso, Ajustes › Conexões).

**analytics** — Exemplo: validar `screen_view` ao abrir o carrinho: **Iniciar Escuta**, navegar no app, buscar `evento:screen_view`, **Exportar JSON…** e levar ao **Relatório**. Problemas: nenhum evento (conferir debug do Firebase no app, origem no iOS), iPhone por cabo indisponível (pymobiledevice3).

**report** — Exemplo: auditar o log de uma tela contra os cards do Figma: **Importar Prints do Figma…**, corrigir o que o OCR leu em **Editar Spec**, **Escolher Arquivo de Log…**, **Auditar**, filtrar **Divergentes**, **Copiar Bug** (do app auditado, não do Mo baile). Nota Dica: não precisa de aparelho. Problemas: tudo "Não Disparada" (plataforma errada), importar prints indisponível (Swift das Command Line Tools).

**environment** — Exemplo: Android "nenhuma área funciona": ler pendência `adb`, **Instalar no Terminal…**, **Verificar de Novo**. Recursos: resumo por grupo, pendências, matriz por área, versões. Problemas: instalou e continua pendente (Verificar de Novo; Python do motor), iOS exige Mac com Xcode completo.

**execution** — Exemplo: rodar o projeto behave do PyCharm: **Abrir Projeto…**, conferir interpretador e Doctor, escolher **Aparelho**, **Rodar**, ler o Console, **Abrir Vídeo**. Nota Atenção: rodar executa o código do projeto com as suas permissões. Problemas: botão bloqueado (ler o cadeado), sem behave no interpretador (**Usar** outro Python), config de nuvem não roda.

**relatar-problema** — O que o relato inclui, o que nunca incluir (dados pessoais), os dois caminhos, como anexar.

### 2.6 Manter em sincronia
- Teste de arquivo por área (critério AC-AJ-01 a 05 abaixo) e checagem de **rótulos em negrito do "Passo a passo"** contra os literais das fontes Swift (AC-AJ-06).
- Regra de PR: mudança em área (`Views/<Área>`) pede revisão do `.md` correspondente; incluir no `CONTRIBUTING.md` e no template de PR (`.github/PULL_REQUEST_TEMPLATE.md`).
- AGENTS.md: mudança em `AppResources/Ajuda` entra no app (reempacotar com `make update-native`).

## 3. Aviso de produto em desenvolvimento

### 3.1 Selo "Beta" persistente
Componente novo `BetaBadge` (um arquivo, `Views/MainWindow/BetaBadge.swift`), duas variações de tamanho do mesmo componente.

| Onde | Encaixe | Forma |
|---|---|---|
| Barra de status, à direita, depois de `PerfBadge` | `StatusBar.swift:44` (antes do bloco `if appState.isDeviceConnected`) | cápsula mono 11 pt, sempre visível, inclusive no Modo Zen e com a barra lateral fechada |
| Rodapé da barra lateral, linha própria | `AppSidebar.swift:80-85` dentro do `VStack` do `mbBottomBar`, acima de `SidebarEnvironmentItem` | linha "Relatar Problema" com a cápsula Beta à direita; extrair o corpo de `SidebarEnvironmentItem` (`:214-268`) para um `SidebarFooterRow` reaproveitado |
| Ajustes › Geral | rodapé do `Form` (`SettingsView.swift:33`) | texto "Mo baile 3.23.0 (beta)" + link Relatar um Problema… |
| Sobre | seção 3.3 | crédito |

Papel visual (sem vidro próprio, de propósito: barra de status e barra lateral já são superfícies do sistema, e a regra do projeto proíbe vidro sobre vidro, `Glass.swift:11-15`; não cria `GlassRole`):
- Preenchimento `theme.warningTint`, borda de 1 pt `theme.warning`, texto "Beta" em `theme.labelPrimary` (não em `warning`: garante contraste 4,5:1 em todas as paletas; o `warning` claro `#8A6100` tem cerca de 5,5:1 sobre branco, Inferido por cálculo, mas as paletas e o escuro não foram medidos).
- Raio `Capsule`, altura mínima 16 pt, padding horizontal 6 pt (mesma medida da contagem do Ambiente, `AppSidebar.swift:238-244`).
- Significado nunca só por cor: a palavra "Beta" é o conteúdo.
- **Reduzir transparência / Aumentar contraste**: como o selo não usa vidro nem material, não muda; em alto contraste a borda passa para `theme.controlBorder`. **Perfil leve** (`mbPerfLight`) não o afeta.
- Interação: clique abre a janela Relatar um Problema; `.help("Versão beta, em desenvolvimento. Pode ter bugs. Clique para relatar um problema.")`.
- VoiceOver: `accessibilityLabel("Versão beta")`, `accessibilityValue("em desenvolvimento, pode ter bugs")`, `accessibilityHint("Abre o relato de problema")`, trait `.isButton`. Na linha da barra lateral: label "Relatar Problema", value "Beta".

### 3.2 Aviso na primeira abertura (uma vez por versão maior)
- Gatilho: primeira vez que a janela principal aparece depois do splash (`SplashController`, `MoBaileApp.swift:34`) em que `UserDefaults["mobaile.avisoBetaMajor"]` difere da versão maior atual (`CFBundleShortVersionString` → primeiro componente; "dev" quando rodando do código, valor `"dev"`; `EngineSession.swift:105` já lê a versão desse jeito).
- Forma: `.alert` do SwiftUI no `ContentView` (`.alert` já é usado ali, `:81`), que herda o vidro do sistema. Não é sheet própria, não usa `mbGlass`.
- Texto e botões: seção 5.1. O botão padrão é **Entendi** (grava a versão maior); **Relatar um Problema…** grava e abre a janela.
- Não aparece: durante os testes (`AppState.atLaunch` recebe `skipBetaNotice`), quando outro alert está ativo (`pendingClear`), nem sobre o Início em primeira vez se isso empilhar duas camadas: espera o `Início` ter aparecido (`jaVisto`, `HomeView.swift:29`).
- Subir de 3.x para 4.0.0 mostra de novo; 3.23 → 3.24 não.

### 3.3 Sobre
- Substituir o item padrão: `CommandGroup(replacing: .appInfo)` com `Button("Sobre o Mo baile")` chamando `NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString])` (`MoBaileApp.swift`, junto dos outros grupos). O renome por `item.title.contains("About")` do `AppDelegate.swift:84` fica redundante e pode sair.
- Versão e commit: o painel padrão já mostra `CFBundleShortVersionString`; o commit está em `MoBaileGitCommit` (Info.plist, `package_macos_app.sh:200`): incluir no crédito.
- Crédito: seção 5.1.

### 3.4 Atalho para relatar bug
Presente em: selo (clique), linha do rodapé da barra lateral, menu Ajuda **Relatar um Problema…** (`⇧⌘B`: livre no registro atual, Verificado por leitura de `CommandRegistry.swift`; confirmar no macOS), paleta (`help.reportBug`, sinônimos "bug, erro, problema, defeito, feedback"), alert da primeira abertura, Sobre, Ajustes › Geral, Ajuda › capítulo Relatar um Problema, e **erro de motor** (`EngineStatusBanner`: botão secundário "Relatar Problema" quando o motor cai; P1).

## 4. Tela Relatar um Problema

### 4.1 Encaixe na navegação
- **Janela própria, não modal**: `Window("Relatar um Problema", id: "relato")` ao lado de `Ajuda` e `Settings`; 520x640 padrão, mínimo 480x520, instância única.
- **Não é `WorkspaceTab`** (D6). Se o dono insistir em "aba" de verdade: custo = novo case no enum (muda `shortcutDigit` das seguintes? não, só adiciona ⌘7), `symbolName`/`categoryColor`/`keywords`/`needsDevice` (`AppSidebar.swift:316-339`, `CommandRegistry.swift:581-591`), `windowSubtitle` (`ContentView.swift:114-145`), `DetailColumn` (`:211-228`), `WorkspacePane`, `HomeAreaGrid`, e os testes que iteram `allCases`. Não recomendado.
- Estado em `BugReportState` (`@Observable`, dono: `AppState`, injetado na janela), sobrevive a fechar e reabrir a janela durante a sessão; fechar com rascunho sujo pergunta (padrão de `ReportSpecEditorView.swift:47-50`).

### 4.2 Layout (de cima para baixo)
1. Título da janela "Relatar um Problema"; intro (`DSFont.callout`, `labelSecondary`): texto 5.2.
2. **Aviso de privacidade** sempre visível, em `dsCard()` com ícone `eye` e borda `warning` (não some, não é colapsável): texto 5.2.
3. Formulário (`Form`/`VStack`, margem 20 pt, grade de 4 pt):
   - **Título** `TextField` (obrigatório, 1 a 120 caracteres, contador `n/120` quando >100).
   - **Área** `Picker` (Início, Page Objects, Rede HTTP, Analytics, Relatório, Ambiente, Execução, Ajuda, "Outra ou não sei"); valor inicial = área ativa quando a janela abriu.
   - **O que você fez** `TextEditor` (altura 3 linhas, expansível), **O que você esperava** `TextEditor`, **O que aconteceu** `TextEditor` (obrigatório). É a "descrição com modelo": três campos rotulados, e o corpo da issue sai montado em Markdown (4.5). Placeholder como texto cinza que some ao digitar e **não** como conteúdo pré-preenchido (rótulo visível + placeholder, nunca só placeholder).
   - **Anexos**: zona de soltar + botão **Adicionar Arquivo…** (`NSOpenPanel`, `allowedContentTypes`), lista com nome, tamanho, ícone e **Remover**; `.dropDestination(for: URL.self)`; ao arrastar por cima, borda `theme.selection` 2 pt e texto "Solte para anexar" (movimento só de cor, nada que dependa de Reduzir movimento).
   - **Informações para ajudar a reproduzir** (opcional): 4 `Toggle` (padrão desligado) + disclosure **Ver o que será enviado** com a prévia em `CodeBlock` (editável só no trecho do log).
4. Rodapé fixo (`mbBottomBar`-like, sem vidro próprio): estado/progresso à esquerda; **Cancelar**, **Copiar Relato**, **Abrir no GitHub…** (secundário se há serviço), **Enviar Relato** (primário, `mbProminentGlassButton`, `Glass.swift:83`; é a única cápsula tingida da janela, como o Rodar na toolbar).

### 4.3 Anexos: limites
- Até 5 arquivos, 10 MB cada, 25 MB no total (Suposição alinhada ao que o GitHub aceita em issue: confirmar antes do release).
- Tipos aceitos: png, jpg, jpeg, gif, mp4, mov, txt, log, json, pdf, zip. Recusa por extensão **e** por tipo real (UTType) e recusa executáveis e pacotes (`.app`, `.sh`, `.command`, `.pkg`, `.dmg`, `.exe`), arquivos duplicados, links simbólicos e diretórios.
- Cada recusa vira `InlineError` perto da lista (textos 5.3). O app nunca lê o conteúdo do anexo; só nome, tamanho e tipo.
- Aviso sob a lista: "Capturas e vídeos podem mostrar dados pessoais. Confira antes de anexar."

### 4.4 Dados automáticos (consentimento explícito)
| Toggle (padrão desligado) | O que entra | Origem |
|---|---|---|
| Versão do Mo baile e do macOS | `Mo baile 3.23.0 (commit abc1234)`, `macOS 26.1` | `Bundle.main` (`CFBundleShortVersionString`, `MoBaileGitCommit`), `ProcessInfo.operatingSystemVersion` |
| Modelo do Mac | `Mac14,2`, `Apple Silicon` | `sysctlbyname("hw.model")` e arquitetura |
| Aparelho e plataforma em uso | `Android, Pixel 7` | `appState.platform`, `appState.selectedDeviceName` |
| Últimas linhas do log do motor | até 200 linhas, até 24 KB | arquivo de log informado no `engine.hello` (`EngineClient.useLogPath`, `EngineClient.swift:273-280`) |

- O log passa por redução antes da prévia: `/Users/<nome>` vira `/Users/~`, e saem trechos que parecem `Bearer …`, `token=…`, `senha=…`, `password=…`, e-mail e CPF. A prévia mostra o resultado e a pessoa pode apagar linhas. Aviso fixo na prévia: "A limpeza automática não pega tudo. Leia antes de enviar." (o log do motor pode ter URLs, nomes de pacote e identificadores de aparelho).
- Sem log (motor parado ou sem arquivo): o toggle fica desabilitado com o motivo (5.3).
- "Ver o que será enviado" mostra exatamente o Markdown final, o mesmo que vai ao GitHub ou ao serviço. É também o que **Copiar Relato** copia.

### 4.5 Corpo gerado (Markdown)
```
### O que aconteceu
<texto>

### O que eu fiz
<texto ou "Não informado">

### O que eu esperava
<texto ou "Não informado">

### Área
Rede HTTP

### Informações do ambiente        (só se marcado)
- Mo baile 3.23.0 (commit abc1234)
- macOS 26.1, Mac14,2

### Log do motor                   (só se marcado)
<details><summary>Últimas 200 linhas</summary>

```text
…
```
</details>

_Enviado pelo Mo baile (relato pelo app)._
```

### 4.6 Caminho (a): navegador com issue pré-preenchida
- URL: `https://github.com/francisco-efjr/mo-baile/issues/new?template=bug-app.yml&title=<…>&<id>=<…>`. Em issue form do GitHub, parâmetros com o `id` do campo preenchem o campo (Inferido da documentação do GitHub; **testar uma vez com a conta do dono** antes do release).
- **Template novo `.github/ISSUE_TEMPLATE/bug-app.yml`** ("Relato pelo app"), com ids `resumo`/`aconteceu`/`fez`/`esperava`/`area`/`ambiente`/`log`, `labels: ["bug", "triagem", "origem-app"]` e título `[bug] `. O `bug.yml` existente (`.github/ISSUE_TEMPLATE/bug.yml`) exige versão, macOS, plataforma, passos, esperado e obtido como obrigatórios: não serve para relato rápido, e mudar os ids dele quebraria o fluxo manual. Rótulos vêm do template, porque o parâmetro `labels=` só vale para quem tem permissão de triagem (Inferido).
- Limite de URL: 7.500 caracteres depois de codificar (Suposição: GitHub recusa URLs perto de 8 KB; não verificado). Ordem de corte: (1) log sai da URL; (2) cada campo de texto é cortado com `… (texto completo no relato copiado)`. Quando algo é cortado, o app **copia o Markdown completo** para a área de transferência e avisa (5.3).
- Anexos: o GitHub não aceita arquivo por link. O app cria `Documentos › Mo baile › Relatos › <aaaa-mm-dd hh-mm>/` com `relato.md` e cópias dos anexos, abre o navegador e **revela a pasta no Finder** (`Exporters.revealInFinder`, `Exporters.swift:160`). A pessoa arrasta os arquivos para o campo de descrição no GitHub. A janela entra em "Falta só enviar no GitHub" (4.8).
- Sem rede/sem navegador: erro com cópia do relato e o endereço `github.com/francisco-efjr/mo-baile/issues/new`.

### 4.7 Caminho (b): serviço intermediário (quando existir)
- Configuração: `MoBaileBugReportURL` no Info.plist (https), gravada pelo empacotamento a partir da variável `MOBAILE_BUG_REPORT_URL`; vazio ou ausente = caminho (b) **inexistente** (o botão **Enviar Relato** vira **Abrir no GitHub…**). Em desenvolvimento, `MOBAILE_BUG_URL` no ambiente. **Nunca** token do GitHub dentro do app.
- Contrato (para quem construir o serviço): `POST {url}/v1/reports`, `multipart/form-data`: parte `report` (JSON `{schema:1, title, body_markdown, area, app_version}`) e partes `file` (anexos); cabeçalho `Idempotency-Key: <uuid do rascunho>`. Respostas: `201 {issue_url, number}`; `400/413/415/429` com `{error: "mensagem curta em pt-BR"}` e, no 429, `Retry-After`. Prazo de 30 s, sem repetição automática (a pessoa repete; a chave de idempotência evita issue duplicada).
- O serviço cria a issue com os rótulos de 4.6, valida tamanho e tipo de novo, limita taxa por IP e hospeda os anexos (a API REST do GitHub não tem upload de anexo de issue, Inferido): decisão de infraestrutura pendente (seção 9).
- Falha do serviço **sempre** oferece o caminho (a) com o rascunho intacto.

### 4.8 Estados
| Estado | Aparência | Comportamento | Texto |
|---|---|---|---|
| Rascunho vazio | campos vazios, **Enviar Relato** habilitado (não usar `disabled`: tira o botão da ordem de foco do VoiceOver) | ao clicar, valida | placeholders 5.2 |
| Rascunho inválido | `InlineError` sob o campo; foco vai ao primeiro erro; erro anunciado | corrige e segue | 5.3 |
| Rascunho válido | igual | pronto | n/a |
| Enviando (b) | `ProgressView` + texto no rodapé, botões `aria-disabled` equivalente (ignoram clique, continuam focáveis), **Cancelar** vira **Interromper** | `Task` cancelável, anuncia "Enviando relato…" e "Enviando anexo 2 de 3…" | 5.3 |
| Enviado (b) | ícone `checkmark.circle.fill` (`success`) + texto + link; `appState.statusMessage` | **Abrir no GitHub**, **Copiar Link**, **Fechar**; rascunho é apagado | 5.3 |
| Aguardando no GitHub (a) | ícone `safari`, texto, pasta dos anexos | **Mostrar Pasta no Finder**, **Abrir de Novo**, **Copiar Relato**, **Concluir** | 5.3 |
| Falhou | `InlineError` (`destructive`), rascunho e anexos intactos | **Tentar de Novo** + **Abrir no GitHub…** | 5.3 |
| Sem log / motor parado | toggle do log desabilitado com motivo | resto funciona | 5.3 |
| Texto longo / 47 caracteres no título / 0 anexos / 5 anexos / nome de arquivo longo | título e nomes com `truncationMode(.middle)` e `.help` com o nome inteiro | n/a | n/a |

### 4.9 Teclado e acessibilidade
- Ordem de Tab: Título, Área, Fez, Esperava, Aconteceu, Adicionar Arquivo…, itens da lista (**Remover <nome>**), 4 toggles, Ver o que será enviado, Cancelar, Copiar Relato, Abrir no GitHub…, Enviar Relato. ⌘↩ envia; ⌘W fecha (com confirmação se sujo); Esc não fecha com rascunho sujo.
- `accessibilityLabel` com o rótulo visível em cada campo (critério 2.5.3), obrigatórios com "obrigatório" no valor; erro ligado ao campo (`accessibilityLabel` do campo inclui o erro enquanto existir; foco e `AccessibilityNotification.Announcement` ao validar).
- Zona de soltar tem equivalente por teclado (**Adicionar Arquivo…**); arrastar não é o único caminho.
- Estados de envio anunciados via `AccessibilityNotification.Announcement`.
- Texto mínimo 11 pt (`DSFont.subheadline`), corpo 13 pt (`DSFont.body`); contraste de texto 4,5:1 e de componentes 3:1 medidos nas paletas existentes (teste AC-BE-04/AC-BR-12).
- **Reduzir transparência** e perfil leve: a janela não usa vidro próprio, só o botão primário (`mbProminentGlassButton`), que já cai para cápsula opaca (`Glass.swift:182-200`). **Reduzir movimento**: sem animação própria além da transição de estado (`Motion.crossfade`).

## 5. Textos finais (UX writing, prontos para colar)

Tom: direto, curto, cordial, "você", botão em verbo no infinitivo com maiúsculas (`readme.md`, CONTENT FUNDAMENTALS), sem emoji, sem código de erro. Guia de voz lido: `docs/design/design-system/readme.md` (não há guia de voz separado).

### 5.1 Beta
| Elemento | Texto |
|---|---|
| Selo (valor visível) | `Beta` |
| Tooltip do selo | Versão beta, em desenvolvimento. Pode ter bugs. Clique para relatar um problema. |
| VoiceOver do selo | rótulo: Versão beta · valor: em desenvolvimento, pode ter bugs · dica: Abre o relato de problema |
| Linha do rodapé da barra lateral | `Relatar Problema` (tooltip: Conte um bug ou um erro. O relato vai para o GitHub.) |
| Alert da primeira abertura, título | O Mo baile está em desenvolvimento |
| Alert, mensagem | Esta é uma versão beta. Ela já faz bastante coisa, mas ainda tem bugs e algumas telas vão mudar. Se algo falhar, relate o problema: leva um minuto e ajuda a corrigir mais rápido. |
| Alert, botões | **Entendi** (padrão) · Relatar um Problema… |
| Sobre (crédito) | Versão beta, em desenvolvimento. Pode conter bugs e mudar sem aviso.↵Encontrou um problema? Use Ajuda › Relatar um Problema…↵Projeto: github.com/francisco-efjr/mo-baile |
| Ajustes › Geral | Mo baile 3.23.0 (beta) · Relatar um Problema… |
| Mensagem na barra de status ao abrir o app (opcional, 5 s) | Versão beta: se algo falhar, use Ajuda › Relatar um Problema… |

### 5.2 Relatar um Problema: rótulos, placeholders, ajuda
| Elemento | Texto |
|---|---|
| Título da janela | Relatar um Problema |
| Introdução | Conte o que aconteceu. O relato vira uma issue no GitHub e entra na fila de correção. |
| Aviso de privacidade, título | Este relato será público |
| Aviso de privacidade, corpo | Qualquer pessoa pode ler o que você enviar, inclusive os anexos. Não inclua senhas, tokens, CPF, e-mails, dados de clientes nem tráfego de produção. Troque por valores fictícios ou cubra a informação antes de anexar. |
| Campo Título | rótulo `Título` · placeholder `Resumo em uma frase. Ex.: A Rede HTTP fica vazia no Android` · ajuda `Diga o que falha e onde.` |
| Campo Área | rótulo `Em que parte aconteceu?` · última opção `Outra ou não sei` |
| Campo Passos | rótulo `O que você fez` · placeholder `1. Conectei o aparelho↵2. Abri a Rede HTTP↵3. Cliquei em Configurar Proxy` |
| Campo Esperado | rótulo `O que você esperava` · placeholder `Ex.: A tabela mostrar as requisições do app.` |
| Campo Obtido (obrigatório) | rótulo `O que aconteceu` · placeholder `Ex.: A tabela ficou vazia e a barra mostrou Proxy inativo.` |
| Seção Anexos | título `Anexos (opcional)` · zona `Arraste capturas, vídeos ou logs aqui` · botão `Adicionar Arquivo…` · legenda `Até 5 arquivos, 10 MB cada, 25 MB no total. Aceitamos png, jpg, gif, mp4, mov, txt, log, json, pdf e zip.` · aviso `Capturas e vídeos podem mostrar dados pessoais. Confira antes de anexar.` · ao arrastar `Solte para anexar` |
| Seção Informações | título `Informações para ajudar a reproduzir (opcional)` · legenda `Nada é incluído sem a sua permissão. Marque o que quiser compartilhar e confira em Ver o que será enviado.` |
| Toggles | `Versão do Mo baile e do macOS` · `Modelo do Mac` · `Aparelho e plataforma em uso` · `Últimas linhas do log do motor` |
| Aviso da prévia do log | A limpeza automática não pega tudo. Leia antes de enviar. |
| Disclosure | `Ver o que será enviado` |
| Botões | `Cancelar` · `Copiar Relato` · `Abrir no GitHub…` · **`Enviar Relato`** (primário) · `Interromper` (durante o envio) |
| Confirmação ao fechar sujo | título `Descartar este relato?` · mensagem `O texto e os anexos escolhidos serão perdidos.` · botões `Descartar` (destrutivo) · `Continuar Editando` (padrão) |
| Menu Ajuda e paleta | `Relatar um Problema…` · sinônimos: bug, erro, problema, defeito, feedback |

### 5.3 Mensagens
Validação:
- Título vazio: `Informe um título. Uma frase curta já ajuda.`
- Obtido vazio: `Conte o que aconteceu. Uma ou duas frases bastam.`
- Título longo: `O título tem {n} caracteres. O limite é 120. Encurte e deixe os detalhes na descrição.`

Anexos:
- Arquivo grande: `“{nome}” tem {tamanho}. O limite é 10 MB por arquivo. Corte o vídeo ou use uma captura de tela.`
- Total: `Os anexos passam de 25 MB juntos. Remova algum ou envie menos arquivos.`
- Tipo: `“{nome}” não é um tipo aceito. Use png, jpg, gif, mp4, mov, txt, log, json, pdf ou zip.`
- Executável: `“{nome}” é um programa ou instalador, e não pode ser anexado. Anexe uma captura ou um log.`
- Quantidade: `O máximo é 5 anexos. Remova um para adicionar outro.`
- Duplicado: `“{nome}” já está na lista.`
- Ilegível: `Não consegui ler “{nome}”. Confira se o arquivo ainda existe e tente de novo.`

Dados:
- Sem log: `O motor não informou um arquivo de log. Você ainda pode enviar sem ele.` (motor parado: `O motor está parado, então não há log para incluir.`)

Envio (b):
- Enviando: `Enviando relato…` · `Enviando anexo {i} de {n}…`
- Sucesso: título `Relato enviado. Obrigado!` · corpo `Ele virou a issue #{n}. Você pode acompanhar a correção no GitHub.` · botões `Abrir no GitHub` · `Copiar Link` · `Fechar` · barra de status `Relato enviado: issue #{n}`
- Sem conexão: `Não foi possível enviar o relato. Não consegui falar com o serviço de relatos. Seu texto continua aqui. Tente de novo ou use Abrir no GitHub….`
- Serviço fora (5xx/prazo): `Não foi possível enviar o relato. O serviço não respondeu. Seu texto continua aqui. Tente de novo em instantes ou use Abrir no GitHub….`
- Muitos envios (429): `Muitos relatos em pouco tempo. Espere um minuto e tente de novo, ou use Abrir no GitHub….`
- Anexos grandes para o serviço (413): `O serviço recusou os anexos por tamanho. Reduza os arquivos ou anexe direto no GitHub.`
- Recusa genérica (400/415): usa o `error` do serviço; sem ele: `O serviço recusou o relato. Confira os anexos ou use Abrir no GitHub….`

Envio (a):
- Aguardando: título `Falta só enviar no GitHub` · corpo `Abri a página com o texto preenchido. Revise e clique no botão verde para criar a issue.` · com anexos: `Seus {n} anexos estão na pasta do relato. Arraste os arquivos da janela do Finder para o campo de descrição no GitHub, depois envie.` · botões `Mostrar Pasta no Finder` · `Abrir de Novo` · `Copiar Relato` · `Concluir`
- Relato longo: `O relato é longo demais para ir no link. Copiei o texto completo: cole no campo de descrição no GitHub.`
- Navegador falhou: `Não consegui abrir o navegador. Use Copiar Relato e abra github.com/francisco-efjr/mo-baile/issues/new.`
- Cópia: barra de status `Relato copiado`

## 6. Pontos exatos de encaixe no código

| Mudança | Arquivo e referência | Tipo |
|---|---|---|
| Janelas Ajuda e Relato | `MoBaileApp.swift:44` (ao lado de `Settings`) | novas `Window` |
| Grupos Sobre e Ajuda | `MoBaileApp.swift:76-161` (`MoBaileCommands.body`, depois de Janela `:156-160`) | `CommandGroup(replacing: .appInfo)` e `.help` |
| Novos comandos | `CommandRegistry.swift:23-77` (ids), `:79-90` (`CommandCategory.help`), lista `:277-` (bloco "Ajuda"), `CommandPerformer.swift` (executar) | registro único |
| Pedido de janela | `AppState.swift` (`windowRequest`, `betaNoticePending`, `bugReport`) + `ContentView.swift:63-70` (`onChange` + `openWindow`) | estado |
| Botão `?` | `UnifiedToolbar.swift:66-68` (depois de `InspectorToggleButton`) | `ToolbarItem` |
| Selo na barra de status | `StatusBar.swift:44` (depois de `PerfBadge()`) | `BetaBadge` |
| Linha no rodapé da barra lateral | `AppSidebar.swift:80-85` e `:214-268` (extrair `SidebarFooterRow`) | view |
| Alert da primeira abertura | `ContentView.swift:81-93` (junto do `.alert` existente) | `.alert` |
| Rodapé dos Ajustes | `SettingsView.swift:33-130` (`GeneralSettings`) | texto + botão |
| Link no Início | `HomeDaily.swift:60` (`HomeHeader`), `HomeFirstRun.swift:7` | botão |
| Renome do Sobre | `AppDelegate.swift:84` | remover ramo "About" |
| Template do GitHub | `.github/ISSUE_TEMPLATE/bug-app.yml` (novo); `config.yml` sem mudança | arquivo |
| Empacotamento | `tools/package_macos_app.sh:171` (copiar `Ajuda`), `:181-` (Info.plist: `MoBaileBugReportURL` opcional), `tools/verify_native_app.sh` (conferir `ajuda` e plist) | script |
| Arquivos novos de código | `Views/Help/{HelpWindow,HelpReader}.swift`, `App/{HelpLibrary,HelpDocument}.swift`, `Views/MainWindow/BetaBadge.swift`, `App/BetaNotice.swift`, `Views/BugReport/BugReportWindow.swift`, `App/{BugReportState,BugReportBuilder,BugReportAttachments,LogExcerpt,BugReportSender}.swift` | novos |
| Conteúdo | `apps/MoBaile/AppResources/Ajuda/*.md` (9 arquivos) | novos |
| Testes | `Tests/MoBaileTests/{HelpLibraryTests,BetaNoticeTests,BugReportTests}.swift`; estender `ToolbarLayoutTests`, `ContrastTests`, `GlassTests` | novos e estendidos |

Arquitetura (ADR 0001, "lógica nova vai para o motor"): tudo aqui é apresentação e exportação do front (como `Exporters`, `ReportBug.copy`): não há regra de negócio nova nem chamada de motor nova, então **não muda `docs/PROTOCOLO_RPC.md` nem `make fixtures`**. O log vem do arquivo cujo caminho o motor já informa no `engine.hello`. Registrar a decisão em `docs/ARQUITETURA.md` ao implementar.

Obrigatório do projeto (AGENTS.md): é mudança de `apps/MoBaile/` e de arquivos que entram no bundle, então a tarefa só termina com `make update-native` e o "OK" do `verify-native`; versão nova SemVer (3.24.0), `CHANGELOG.md`, tag; `make check` e `make test-swift` antes do commit.

## 7. Componentes e tokens do design system a reutilizar

- Superfície e layout: `dsCard()` (`Content.swift:107`), `EmptyState` (`:5`), `InlineError` (`:57`), `CodeBlock` (`:112`), `AccessoryBar` (`Bars.swift:8`), `PlainTextButtonStyle` (`Bars.swift:155`), `StatusIndicator` (`Indicators.swift:8`).
- Vidro: só `mbProminentGlassButton` para **Enviar Relato** (`Glass.swift:83`); nenhum `mbGlass` novo, nenhum `GlassRole` novo; `.alert`/`.sheet`/`Window` com vidro do sistema.
- Cores: `warningTint`, `warning`, `labelPrimary`, `labelSecondary`, `destructive`, `success`, `selection`, `controlBorder` (`DesignTokens.swift:51-72`).
- Tipografia: `DSFont.title1/headline/body/callout/subheadline/mono` (escala do readme). Espaço: `DesignMetrics.Spacing`, `windowMargin`. Movimento: `Motion.crossfade`, `Motion.smooth`.
- Atalhos e comandos: `CommandRegistry`/`CommandShortcut` (`CommandRegistry.swift:93-124`).
- Persistência: `@AppStorage`/`UserDefaults` com prefixo `mobaile.` (`mobaile.avisoBetaMajor`, como `mobaile.novidadesDispensadas`).
- Tokens propostos: nenhum novo de cor. Métrica nova `DesignMetrics.Widths.helpReading = 640` (primitivo) e `Widths.helpSidebar = 200`.

## 8. Adições intencionais e substituições a validar
- Adições: Window Ajuda; Window Relato; menu Ajuda e Sobre próprios; `BetaBadge`; template `bug-app.yml`; pasta `Documentos › Mo baile › Relatos`.
- Substituições a validar: ⌘? como atalho de Ajuda; ⇧⌘B para Relatar; selo na barra de status em vez de na toolbar (a toolbar está cheia e cede itens ao `»`).

## 9. Critérios de aceite (verificáveis por teste Swift)

Ajuda
- AC-AJ-01 Para todo `WorkspaceTab.allCases` existe `<rawValue>.md` em `apps/MoBaile/AppResources/Ajuda` (teste lê pelo caminho do repositório) e `comecando.md` e `relatar-problema.md`.
- AC-AJ-02 Front matter válido: `area == rawValue`, `titulo == displayName`, `resumo` não vazio e até 110 caracteres, `precisa` presente.
- AC-AJ-03 As seis seções existem, com os títulos exatos e na ordem de 2.3; "Passo a passo" tem 3 a 6 itens numerados; "Exemplo prático" não vazio.
- AC-AJ-04 Palavras por documento de área entre 120 e 450 (`comecando` até 350).
- AC-AJ-05 Todo `⌘…` citado no texto existe: dígitos batem com `WorkspaceTab.shortcutDigit` do nome citado, e os demais existem em `CommandRegistry.commands(in:)`.
- AC-AJ-06 Todo `**rótulo**` do "Passo a passo" aparece como literal de string em `Sources/MoBaile` (varredura de fontes) ou está numa lista de exceções com motivo.
- AC-AJ-07 Todo link `mobaile://ajuda/<tópico>` resolve; só esquemas `https` e `mobaile`.
- AC-AJ-08 O parser reconhece só os blocos do subconjunto (rejeita tabela, imagem, HTML) e nenhum `**` ou `` ` `` sobra literal no texto renderizado.
- AC-AJ-09 `HelpLibrary.topic(for:)` devolve tópico para todas as áreas; `HelpState.open(area:)` seleciona o tópico.
- AC-AJ-10 `package_macos_app.sh` contém a cópia de `Ajuda` e `verify_native_app.sh` a confere (teste lê os scripts).
- AC-AJ-11 `CommandRegistry` tem `help.open`, `help.topics`, `help.reportBug`, categoria Ajuda; `ToolbarLayoutTests` acha o item "Ajuda desta Área".
- AC-AJ-12 O tópico Atalhos é gerado do registro: contém todo comando com atalho.

Beta
- AC-BE-01 `BetaNotice.shouldShow(stored: nil/"2"/"3", current: "3")` → `true/true/false`; "dev" só mostra uma vez.
- AC-BE-02 Versão maior de `"3.23.0"` é `"3"`; entrada inválida cai em `"dev"`.
- AC-BE-03 `StatusBar` renderizada expõe um elemento com rótulo "Versão beta" e hint "Abre o relato de problema" (`AccessibilityInspector`); a linha da barra lateral expõe "Relatar Problema".
- AC-BE-04 Contraste de `labelPrimary` sobre `warningTint` composto sobre `bgContentAlt` e sobre o fundo da barra lateral ≥ 4,5:1 em Praia clara, escura, alto contraste e em todas as paletas (estende `ContrastTests`).
- AC-BE-05 `BetaBadge.swift` não referencia `mbGlass`, `glassEffect` nem `GlassRole` (estende a varredura de `GlassTests`); logo não depende de Reduzir transparência.
- AC-BE-06 O texto do Sobre contém "beta" e "bugs"; o alert tem os dois botões e o padrão é "Entendi".
- AC-BE-07 `AppState.atLaunch` com `skipBetaNotice` nunca apresenta o alert nos testes; com valor guardado igual à versão maior, não apresenta.

Relatar um Problema
- AC-BR-01 `BugReportDraft.validate()`: título vazio ou só espaços e "O que aconteceu" vazio geram os erros de 5.3; título com 121 caracteres gera erro.
- AC-BR-02 Todos os toggles de dados nascem desligados e o corpo gerado não contém ambiente, modelo, aparelho nem log; ligando um, entra só ele.
- AC-BR-03 `BugReportBuilder.body(...)` casa com o fixture de 4.5 (com e sem dados).
- AC-BR-04 `BugReportBuilder.issueURL(...)`: começa com `https://github.com/francisco-efjr/mo-baile/issues/new?template=bug-app.yml`, tem no máximo 7.500 caracteres, codifica acento, quebra de linha, `#`, `&` e `+`; com log grande o log sai da URL e `needsClipboardFallback == true`.
- AC-BR-05 Os parâmetros que o builder usa são exatamente os `id` do `bug-app.yml` (teste lê o YAML) e o `labels` do template tem `bug`, `triagem`, `origem-app`.
- AC-BR-06 `BugReportAttachments.validate`: recusa 6º arquivo, >10 MB, total >25 MB, extensão fora da lista, executáveis, duplicado, diretório e link simbólico, com a mensagem exata de 5.3.
- AC-BR-07 `LogExcerpt.redact`: `/Users/maria/x` vira `/Users/~/x`; `Bearer abc123`, `token=abc`, `senha=abc`, e-mail e CPF saem; no máximo 200 linhas e 24 KB; sem arquivo de log o toggle fica desabilitado com o motivo.
- AC-BR-08 Máquina de estados com `BugReportSending` falso: rascunho → enviando → enviado (guarda `issue_url`, apaga o rascunho); → falhou (mantém texto e anexos, oferece caminho (a)).
- AC-BR-09 Sem `MoBaileBugReportURL`, o primário é "Abrir no GitHub…" e não existe `Enviar Relato`; com URL, o primário é "Enviar Relato" e o caminho (a) é secundário.
- AC-BR-10 A `Idempotency-Key` é a mesma entre tentativas do mesmo rascunho e muda em rascunho novo.
- AC-BR-11 O caminho (a) com anexos cria a pasta `Relatos/<data>` com `relato.md` e as cópias, e chama revelar no Finder (via protocolo injetado, sem abrir o Finder nos testes).
- AC-BR-12 O aviso "Este relato será público" aparece em todos os estados do rascunho (renderização com `ImageRenderer`/`NSHostingView`); campos expõem rótulo visível como nome acessível; erro de campo é anunciado.
- AC-BR-13 Fechar com rascunho sujo pede confirmação; limpo fecha direto.

Verificação manual (não automatizável): VoiceOver percorre Ajuda e Relato; abrir uma issue real pelo caminho (a) e conferir o preenchimento dos campos, rótulos e o limite de URL; arrastar um anexo no GitHub; Aumentar contraste e Reduzir transparência ligados.

## 10. Decisões pendentes do humano

| # | Decisão | Opções (impacto) |
|---|---|---|
| P1 | Relato como janela ou como aba da barra lateral | Janela + item no rodapé (recomendado; 0 impacto nas áreas). Área real (`WorkspaceTab`, +7 pontos de código, ⌘7). |
| P2 | Serviço intermediário | Sem serviço em 3.24.0 (só caminho (a); zero infraestrutura). Com serviço (b): precisa hospedar anexos, guardar token e limitar taxa; o contrato de 4.7 vale. |
| P3 | Rótulos exatos da issue | `bug` + `triagem` + `origem-app` (proposto, reaproveita `bug.yml`). Se "precisa de fix" tem que ser rótulo literal, criar `precisa-de-fix` no repositório. |
| P4 | Padrão dos dados automáticos | Todos desligados (proposto, consentimento explícito). Versão do app e do macOS ligada por padrão ajuda a triagem, mas contraria o pedido literal. |
| P5 | Limites de anexo | 5 arquivos, 10 MB, 25 MB (Suposição). Confirmar no GitHub antes do release. |
| P6 | Atalhos ⌘? e ⇧⌘B | Confirmar sem conflito com o sistema. |
| P7 | Reler o aviso Beta | Uma vez por versão maior (proposto). Alternativa: toda atualização menor (mais ruído). |
| P8 | Quem escreve os 9 `.md` | Brief da seção 2.5 + este formato; revisão do dono; um teste impede release sem eles. |
| P9 | Idioma | Só pt-BR (app inteiro está em pt-BR). Inglês fica fora desta entrega. |

## 11. Verificado / Inferido / Não verificado

- **Verificado (li no código)**: nomes, atalhos e ordem das áreas; botões e rótulos citados com `arquivo:linha`; a toolbar única; o menu sem Help próprio; o fato de `Bundle.module` não ser usado e de os recursos serem copiados à mão; o molde do CHANGELOG embutido; a barra de status e o `PerfBadge`; os papéis de vidro e a regra de vidro sobre vidro; `bug.yml` e `config.yml` existentes; o remoto `github.com/francisco-efjr/mo-baile`; o caminho do log do motor vindo do `engine.hello`.
- **Inferido**: prefill por `id` em issue form do GitHub; `labels=` na URL só vale para quem tem triagem; GitHub sem upload de anexo pela API REST; limite de URL perto de 8 KB; contraste do `warning` claro de cerca de 5,5:1 (cálculo manual); a pré-condição do proxy.
- **Não verificado**: nada foi compilado, rodado nem renderizado; VoiceOver não foi ouvido; contraste nas paletas escuras e de alto contraste; atalhos ⌘? e ⇧⌘B no macOS; comportamento real da URL pré-preenchida no GitHub; limites de anexo do GitHub; conteúdo do `CommandPerformer.swift`, de `NoDeviceView` além das primeiras linhas e dos arquivos `Page Objects`/`AnalyticsInspectorView` além dos trechos citados.

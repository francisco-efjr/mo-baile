# Changelog

Todas as mudanças relevantes do Mo baile ficam aqui, da mais nova para a mais
antiga. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e a numeração segue o [Versionamento Semântico](https://semver.org/lang/pt-BR/).
A regra de quando e como subir a versão está em [docs/VERSIONAMENTO.md](docs/VERSIONAMENTO.md).

## [3.8.0] - 2026-10-23

### Adicionado

- **Relatório HTML interativo com a identidade do Mo baile.** O
  `relatorio.html` do Exportar agora é a aba Relatório fora do app: toolbar
  de vidro com o ícone, barra lateral com as seções da spec, anel de
  conformidade, filtro igual ao do app (Todas, Pedem Ação, Divergentes, Não
  Disparadas, OK, Fora da Spec), busca, cards com o print ampliável e a
  tabela Parâmetro · Obtido · Esperado por fluxo, o "Bloco" com Copiar,
  visão em tabela ordenável e "Fora da spec" em tabelas. Segue o claro e o
  escuro do sistema (com seletor), Aumentar contraste, Reduzir movimento e
  Reduzir transparência. Rodapé em letras miúdas: "Gerado pelo Mo baile".
- O design system inteiro vai embutido no HTML (tokens, vidro, molas e
  componentes `.mb-*`), copiado de `docs/design/design-system` por
  `tools/sync_report_assets.py`; um teste falha se a cópia ficar para trás.
- Animações com Motion 13.5.1 (MIT, embutido, sem internet) nas molas do
  design system. Toda animação termina em até 1,5 s, e sem JavaScript ou na
  impressão o conteúdo aparece inteiro.

### Segurança

- O HTML exportado tem política de conteúdo: nenhuma requisição de rede e só
  os três scripts embutidos rodam, autorizados pelo hash. Texto da spec e do
  log continua sempre escapado.

## [3.7.0] - 2026-10-22

### Adicionado

- **Copiar Bug no Relatório.** Numa validação divergente ou não disparada, o
  botão "Copiar Bug" do painel Validação (ou o menu de contexto da linha)
  copia o bug no modelo do time: Resultado Obtido com obtido × esperado de
  cada parâmetro que diverge (ou o esperado, no não disparado), passos para
  reproduzir com fluxo, tela e ação, anexos e a tag `automacao`. Usuário,
  base e versão ficam em branco para preencher. Vão junto duas imagens: o
  painel Validação desenhado em claro e o print do card do Figma. O clipboard
  leva RTFD, HTML com as imagens embutidas e texto puro, e cada destino usa o
  que entende. "Copiar Imagens do Bug" põe só as duas imagens lado a lado.
- **Editar o card da spec no app.** O botão "Editar" do inspector abre um
  formulário com seção, título, evento, parâmetros, variações e observação.
  Salvar (⌘S) grava no `.json` da spec e audita de novo, mantendo a linha
  escolhida. Só esses campos mudam: o print, `por_fluxo`,
  `params_por_fluxo`, observação por fluxo e chaves desconhecidas ficam como
  estavam. A spec inteira é validada antes, e o arquivo é trocado de uma vez.
- Métodos `report.card` e `report.card_update`, e o campo `expected` em cada
  resultado de `report.audit` (o que a variação espera, com o fluxo
  aplicado). Tudo aditivo: `PROTOCOL_VERSION` continua 2.

## [3.6.2] - 2026-10-22

### Corrigido

- **A janela principal não aparece mais atrás do splash.** A cena `Window`
  abria a janela junto com o app, e o splash de abertura ficava por cima com a
  tela inteira já desenhada no fundo. A janela continua sendo criada na
  abertura (é ela que sobe o motor), mas nasce transparente e aparece com o
  mesmo esmaecer da saída do splash. Janela › Mostrar Splash não esconde nada.
  Coberto em `SplashTimingTests`.

## [3.6.1] - 2026-10-22

Layout em monitores pequenos. A janela declarava 980 × 600 pt de mínimo, mas
pedia de verdade 1.743 pt de largura no Relatório com uma auditoria aberta
(mais que a tela de um MacBook Air), 1.337 a 1.357 pt nas outras áreas e 838 pt
de altura com uma spec aberta. Num monitor menor, o conteúdo era cortado nas
bordas.

### Corrigido

- **Inspector próprio.** O `.inspector` aninhado na `NavigationSplitView`
  media as colunas pela largura ideal e contava a barra lateral em dobro. O
  inspector virou um painel da área, com divisória arrastável e a largura
  guardada por janela; o botão de mostrar e ocultar foi para o fim da toolbar.
- **Tabela e detalhe sem `VSplitView`** em Rede, Analytics e Relatório: o
  NSSplitView aninhado somava largura à janela e não repassava o mínimo do
  conteúdo. Agora é uma divisória própria (`VerticalSplit`), também arrastável.
- **Request | Response e Validação | Bloco viram abas** quando a coluna fica
  estreita (`AdaptivePair`). Lado a lado, Rede pedia 564 pt para um workspace
  que declarava 360, e o excesso empurrava o espelho para baixo da barra
  lateral e o inspector para fora da janela.
- **Espelho e inspector cedem até o mínimo** antes de a área transbordar
  (`layoutPriority`); com folga, voltam à largura arrastada.
- **Resumo do Relatório quebra linha** no estreito: a origem sobe para a linha
  da conformidade e as contagens descem para a seguinte.

Mínimos medidos com barra lateral e inspector abertos: Page Objects 1.090 ×
565, Rede e Analytics 1.070 × 552, Relatório 949 × 548 (com auditoria) e 909 ×
361 (vazio). `ToolbarLayoutTests` passa a medir as áreas com conteúdo, com teto
de 1.100 × 600, e confere que o conteúdo do workspace e do inspector cabe no
mínimo declarado. `WindowSnapshotTests.testTelasPequenas` fotografa todas as
áreas em 980 × 600 e 1.280 × 720.

## [3.6.0] - 2026-10-15

Rodada 2 do orquestrador: cinco funcionalidades escolhidas na mesa de
propostas (F3, F11, F8, F12, F5), com o contrato escrito antes do código em
[docs/melhorias/2026-10-15/CONTRATO.md](docs/melhorias/2026-10-15/CONTRATO.md).
`PROTOCOL_VERSION` continua 2: tudo é aditivo e está em
[docs/PROTOCOLO_RPC.md](docs/PROTOCOLO_RPC.md).

### Adicionado

- **Digitação no iOS dentro do fluxo (F3).** O passo de digitação toca no
  campo e envia o texto por `/wda/keys`; antes virava só um toque e era dado
  como sucesso. Sem texto gravado, falha, como no Android. O texto nunca vai
  para o `flow.log`.
- **Espelho em JPEG e MJPEG do WebDriverAgent (F11).** `stream.frame` sai com
  `format` (`jpeg` por padrão) e `image_base64`; `png_base64` continua quando
  o formato é PNG. `stream.start` aceita `format` e `quality`. No iOS, com o
  MJPEG do WDA no ar (`WDA_MJPEG_PORT`, padrão 9100), o JPEG é repassado sem
  reencodar. Medido em `tools/bench_frame.py` (900×2000, mediana de 20): PNG
  20,7 ms e 1,97 MB; JPEG 2,2 ms e 86 KB.
- **"Por que não vejo tráfego?" (F8).** Método `proxy.diagnose` e botão na
  Rede, na paleta e no menu Editar: o motor olha o proxy, o aparelho e o
  histórico e diz a causa provável com o passo de correção (proxy parado,
  aparelho sem proxy, app que ignora o proxy, só túneis HTTPS, pinning,
  sessão iOS, App em Debug sem eventos).
- **Busca com tokens, escopo e colunas lembradas (F12).** `status:4xx`,
  `metodo:POST`, `host:`, `tipo:json` na Rede; `evento:`, `param:chave=valor`,
  `origem:` em Analytics, com sugestões no campo de busca. Escopo Todos · API ·
  Mídia · Erros · Lentas acima da tabela de Rede. Largura, ordem e
  visibilidade das colunas de Rede e Analytics sobrevivem ao reabrir.
- **Linha do tempo correlacionada (F5).** Cada passo gravado ganha
  `recorded_at`; `session.correlate` devolve as requisições e os eventos de
  analytics na janela do passo (1 s antes, 4 s depois ou até o passo
  seguinte). Selecionar um passo na barra lateral, ou "Ver na Rede" / "Ver em
  Analytics" no menu dele, filtra as duas tabelas pela janela, com o chip
  "Passo N · elemento · requisições · eventos" e "Mostrar tudo". A atribuição
  é por tempo (`probable`), não causal.

### Alterado

- `screen.capture` continua em PNG: é a captura do OCR e do Relatório.
- Os quadros do espelho deixam de ser comparáveis byte a byte entre versões
  da libjpeg; a fixture `notif_stream.frame` é gerada em PNG e conferida por
  pixel.

### Limites

- Nada desta rodada foi exercitado com aparelho real: WDA, adb, simctl e o
  MJPEG foram falsos nos testes. O roteiro manual está em
  `docs/melhorias/2026-10-15/COMO-TESTAR.md`.
- A correlação não corrige relógio do aparelho porque não precisa: todos os
  carimbos são do Mac na recepção; a latência do `logcat` (sub-segundo) é o
  único desvio.

## [3.5.2] - 2026-10-14

Correções de comportamento da auditoria orquestrada de 14/10: o que o motor
deixava para trás quando algo falhava, e o que ele entregava errado. O esquema
do contrato RPC não muda (`PROTOCOL_VERSION` 2, fixtures iguais); três
comportamentos observáveis mudam e estão anotados em `docs/PROTOCOLO_RPC.md`
(`device.changed`, `devices.watch_start`, `passive.start` no iOS). O relatório
completo, com a revisão independente e a auditoria, está em
`docs/melhorias/2026-10-14/`.

### Corrigido

- **Aparelho escolhido não volta ao primeiro (M1).** Com emulador e aparelho
  físico conectados, escolher o segundo era desfeito na varredura seguinte e
  ainda religava o espelho. O vigia passa a saber qual é o alvo da sessão.
- **Escuta passiva e analytics não morrem em silêncio (M5).** Um `dumpsys`
  lento, um toque que falha, o Python do app sem Quartz e o `logcat` que morre
  com o cabo deixavam a tela dizendo "Gravando"/"Ligado" sem ouvir nada.
- **O proxy do aparelho volta ao que era (M2).** `http_proxy` e
  `captive_portal_mode` anteriores são restaurados, e um desmonte que não se
  confirma (cabo solto) é retentado uma vez quando o aparelho reaparece (mesmo
  com a sessão em iOS) e ao encerrar. `global_http_proxy_*` não é guardado.
- **Seletor "único" é único de verdade (M7).** O candidato por texto gravava o
  xpath do `resource-id`, que casava com todos os elementos de mesmo id; o
  xpath contava `matches` fixo em 1. Um botão com "campo" no rótulo não vira
  mais passo de digitação.
- **Sessão WDA/Appium caduca é reaberta (M6).** O id em cache nunca expirava, e
  todo toque falhava até reiniciar o motor.
- **cURL e código gerado escapam o que vem do tráfego (M12).** Método, URL e
  nome de header entravam sem escape no cURL copiado, e o caminho da requisição
  no literal Python da asserção de contrato.

### Alterado

- O candidato `xpath` do ranking de localizadores conta os elementos que ele
  realmente casa. Sem texto nem id único, o modo automático passa a escolher
  coordenada com mais frequência, que é o que o ranking já devia dizer.
- O desmonte do proxy (`teardown_reverse_proxy`) devolve `False` quando o
  aparelho não confirma.
- `IOSPassiveListener.start` levanta `AdapterError` sem Quartz, em vez de
  responder `listening: true`. O app Tkinter legado mostra o motivo e desmarca
  o modo passivo, em vez de quebrar.
- A classificação de passo de digitação vale pela classe do elemento
  (EditText, TextField, SearchView, AutoCompleteTextView), pelo prefixo `CAMPO`
  do nome, ou por `campo` no id de um componente sem tipo conhecido.

## [3.5.1] - 2026-10-12

CI do GitHub de volta ao verde. As falhas já existiam desde a 3.3, só
apareciam no GitHub e travaram o Release da 3.5.0.

### Corrigido

- Front nativo e Release rodam no `macos-26` (Xcode 26). O `macos-14` traz
  Swift 5.10 e não compila o código em Swift 6.2.
- A conferência das fixtures compara os PNGs pelos pixels, não pelos bytes.
  A compressão muda com a versão do Pillow e do zlib e acusava fixture
  desatualizada sem ela estar.
- O teste de `scrcpy.start` sem aparelho não depende mais de o `scrcpy` estar
  instalado na máquina.

## [3.5.0] - 2026-10-11

### Adicionado

- 

## [3.5.0] - 2026-10-11

Fluidez, correções da auditoria orquestrada de 11/10 e preparação para open
source. Detalhes da paleta em [docs/design/FLUIDEZ_3.5.md](docs/design/FLUIDEZ_3.5.md).

### Adicionado

- **Paleta de comandos (⇧⌘P):** qualquer ação do app pelo teclado, com busca
  aproximada sem acento, sinônimos, atalho visível, recentes no topo e motivo
  quando a ação não está disponível. Menus e paleta leem o mesmo registro.
- **Faixa "Motor parado"** com o botão Reiniciar Motor e anúncio ao VoiceOver.
- **Próximo passo** em destaque no estado sem aparelho.
- Licença MIT, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, templates de issue e
  PR, Dependabot e workflow de release que publica o app zipado com SHA-256
  ([docs/RELEASE.md](docs/RELEASE.md)).

### Mudado

- O app escolhe o primeiro Python 3.10+ com as dependências do motor e, sem
  nenhum, diz o que instalar. O `verify-native` segue a mesma regra.
- Empacotamento em staging com troca atômica, recusa com o app aberto e grava
  o commit no Info.plist; o `verify-native` confere commit e assinatura.
- `make check` falha com fixtures do contrato desatualizadas.
- Contraste do texto terciário ≥ 4,5:1 em todos os temas; barra de status com
  nomes por extenso e 11 pt; textos do diagnóstico com acento e plural.
- Chave padrão do Page Object passa a `minha_tela_objs`.
- App Tk congelado ([ADR 0005](docs/adr/0005-app-tk-congelado.md)); docs
  históricos em `docs/historico/`.
- Componentes novos da 3.5 (paleta, faixa do motor, cartão de próximo passo)
  seguem o contrato de componente: `#Preview`, variantes em enum, tokens,
  Reduzir movimento e doc com Acessibilidade em
  [docs/design/componentes/](docs/design/componentes/README.md).
- Dados de exemplo neutros: app de teste "DemoApp" (`com.example.demoapp`),
  `cadastro_demo` e UDID sintético nos testes.

### Corrigido

- Código gerado: valor vindo da tela entra só como string (antes, um texto com
  aspas podia virar código no Page Object).
- `analytics.stop` desliga o debug do Firebase no aparelho; fila de eventos
  com limite.
- Proxy desfeito no aparelho em que foi ligado, inclusive ao trocar de aparelho.
- `codegen.save` só grava dentro da pasta de trabalho.
- Log bruto do iPhone com URL redigida e arquivos só com o dono.
- Cursor da divisória não fica preso; buscar na hierarquia não age com o
  inspector fora da janela.
- Paleta: teclas só agem na janela dela e sem modal; foco preso na paleta e
  devolvido ao fechar; linhas executam pelo VoiceOver.
- Reiniciar Motor duas vezes não deixa motor órfão; a escolha do Python roda
  fora da thread principal, não guarda falha em cache e mata a sonda que trava.

### Removido

- `web_app.py`, que executava `main.py` recebido por upload sem autenticação.

## [3.4.0] - 2026-10-09

P1 de interface da [revisão de produto](docs/MELHORIAS_2026-10-09.md): D3 e D4.

### Mudado

- **Inspector contextual (D3):** sem aparelho, em Page Objects, Rede e
  Analytics, o inspector sai da janela em vez de repetir o "Conecte um
  aparelho" do estado vazio, e volta ao conectar. A escolha manual é mantida:
  quem fechou o inspector continua com ele fechado. No Relatório ele fica,
  porque mostra o card do Figma. O botão e o ⌥⌘I ficam desabilitados enquanto
  o inspector está fora da janela.
- **Barra de status por plataforma (D4):** no iOS a barra mostra WDA, proxy
  e FA; no Android, ADB, proxy e FA. O serviço da outra plataforma vai para o
  tooltip.

## [3.3.1] - 2026-10-09

Os P0 de interface da [revisão de produto](docs/MELHORIAS_2026-10-09.md):
D1, D2 e Q4.

### Corrigido

- **A janela cabe num MacBook (D1):** com barra lateral e inspector abertos, a
  largura mínima caiu de 1.885 para 1.357 pt em Page Objects, de 1.865 para
  1.337 em Rede e Analytics, e ficou em 1.176 no Relatório. Antes, numa
  janela menor que isso, o conteúdo era desenhado na largura mínima e cortado
  nas bordas, e a barra lateral e o inspector sumiam. O `HSplitView` entre
  espelho e workspace virou um `HStack` com divisória arrastável própria, e a
  largura do espelho fica guardada por janela. O espelho cede até o mínimo antes
  de a janela crescer.
- **Rodar visível (D2):** desabilitado ou com a janela inativa, o botão usa o
  estilo padrão. A cápsula tingida sem tom deixava o play branco sobre fundo
  claro.

### Testes

- `ToolbarLayoutTests.testJanelaCabeNumMacBookEmTodasAsAreas` (Q4) mede a
  largura mínima nas quatro áreas com barra lateral e inspector. O teto é
  1.440 pt, a tela do MacBook Air de 13".

## [3.3.0] - 2026-10-09

Rodada de melhorias de 09/10: três pedidas, os defeitos que o catálogo de telas
novo mostrou e a revisão de produto em
[docs/MELHORIAS_2026-10-09.md](docs/MELHORIAS_2026-10-09.md).

### Adicionado

- **App em Debug no Android:** tráfego HTTPS do app em debug sem proxy nem
  certificado, lido do logcat (log do `HttpLoggingInterceptor` do OkHttp).
  Funciona com o debugger do Android Studio conectado. É a mesma ação do
  "iPhone em Debug" ([ADR 0004](docs/adr/0004-https-sem-proxy-android.md)).
- Catálogo de telas da 3.x em `docs/design/telas/`: 29 telas e estados em
  claro e escuro, PDF e folha de contato, gerados por
  `WindowSnapshotTests.testCatalogoDeTelas` e `tools/catalogo_telas.py`. O
  catálogo da 2.x foi para `docs/design/telas/arquivo-2.x/`.

### Mudado

- **Busca em tudo:** a busca da toolbar procura em qualquer dado capturado. Na
  Rede: URL, query, headers (nome e valor), corpos e erro. No Analytics: nome,
  parâmetros (chave e valor), origem e log bruto. No Relatório: evento,
  variação, divergência e parâmetros do disparo. Cada palavra precisa
  aparecer em algum campo, sem diferenciar maiúsculas nem acentos.
- **Splash que espera o app:** fica até o motor responder e a primeira
  varredura de aparelhos e do ambiente terminar, com a fase escrita na tela
  ("Iniciando o motor…", "Procurando aparelhos e simuladores…"), mínimo de
  2,5 s e teto de 12 s. Se o motor falhar, sai para o erro aparecer na janela.
- A barra de status cede espaço em largura estreita (só ícones dos serviços,
  métricas curtas) em vez de impor 690 pt à janela.
- `netlog.start` escolhe a fonte pela plataforma da sessão e devolve `source`.

### Corrigido

- O corpo JSON da Rede mostrava `28.399999999999999` no lugar de `28.4` e
  reordenava as chaves. Agora a indentação é feita sobre o texto original.
- O popover de Correlação mostrava `AutomationStep(stepNum: …)`. Agora mostra a
  frase do passo e o locator.
- "1 aprovados" no rodapé da execução.
- O passo por coordenada aparecia como "click position" (valor interno). Agora
  é "toque em x, y".

## [3.2.0] - 2026-10-08

Aba **Relatório**: a auditoria de tagueamento do `tag_audit` (projeto
bold-kepler) agora roda dentro do Mo baile, no motor. Decisões em
[ADR 0003](docs/adr/0003-relatorio-tagueamento.md); anatomia da tela em
[docs/design/relatorio.md](docs/design/relatorio.md).

### Adicionado

- Relatório na barra lateral (⌘4), sem precisar de aparelho: abre a
  spec-modelo dos cards do Figma, audita os eventos que a escuta de Analytics
  capturou nesta sessão ou um log exportado (`log_obtido.json`, Logcat em
  texto) e mostra a conformidade, uma linha por variação (card × fluxo ×
  variação) e, para cada uma, o parâmetro obtido e o esperado, o bloco com ✓/✗
  e o disparo avaliado. O inspector mostra o card do Figma da linha.
- Recortes: Pedem Ação, Divergentes, Não Disparadas, OK e Fora da Spec
  (eventos dos fluxos que nenhum card cobre, e alertas de `app_exception` e
  `error_view`). A busca da toolbar (⌘F) filtra a tabela.
- Exportar grava o board Excalidraw, o HTML, o Markdown e o TSV em
  Documentos › Mo baile › Relatórios, ou na pasta escolhida. Copiar põe o TSV
  (Google Planilhas) ou o Markdown (PR, Jira) na área de transferência.
- Importar Prints do Figma: o OCR do macOS (Vision, local) lê os cards e grava
  o rascunho da spec, sem sobrescrever spec existente, com a lista do que
  conferir em cada card.
- Arquivo › Abrir Spec de Tagueamento… (⌘O), Importar Prints do Figma… e
  Exportar Relatório….
- Contrato: `report.spec`, `report.audit`, `report.export` e `report.import`,
  numa fila própria (`report`), com progresso. O relatório não espera nem
  segura o aparelho.
- Fluxo 5 do harness de QA (relatório de ponta a ponta, 26 verificações).

### Mudado

- Em relação ao `tag_audit`: regex inválida na spec é recusada ao abrir (antes
  quebrava a auditoria no meio); o board sai determinístico (ids por contador,
  não `uuid4`); spec, log e pastas passam por validação de caminho e de
  tamanho antes de abrir. As regras de casamento são as mesmas: Markdown, TSV e
  HTML saem idênticos aos do `tag_audit` para os mesmos arquivos.

### Fora desta versão

- O pipeline antigo `run` do `tag_audit`, a sincronização com o WebKit do
  *Francis' DrawCred* e a saída com código 2 para CI (ver ADR 0003).

## [3.1.0] - 2026-10-08

### Adicionado

- Ajustes › Paletas: galeria com nove paletas alternativas inspiradas em
  designers de interiores (`docs/design/paletas/`). São quatro claras (Sálvia
  & Palha, Azulejo/Sig Bergamin, Hampshire/Dorothy Draper, Veludo
  Rosé/India Mahdavi), quatro escuras (Terracota/Kelly Wearstler,
  Costes/Jacques Garcia, Geométrico/David Hicks, Mármore/Joseph Dirand) e uma
  extra (Jardim Digital/Antoni Tudisco). Cada cartão mostra uma mini-janela de
  prévia nas cores da paleta, as 11 amostras e as oito checagens de contraste
  (WCAG e distância OKLab entre o destaque e as cores de estado). "Usar
  Paleta" aplica o tema na hora, e a escolha é guardada.
- Cada paleta tem variação de Aumentar contraste. O que ela não declara
  (sintaxe, chips, GET/POST, terminal) vem da Praia da mesma aparência.

### Mudado

- Uma paleta clara ou escura define a aparência do app. Em Ajustes › Geral, a
  Aparência fica desabilitada e oferece "Voltar para a Praia". A Praia
  continua sendo o padrão e segue Sistema, Claro ou Escuro.
- Com uma paleta alternativa, a barra lateral usa a cor de barra lateral da
  paleta no lugar do material do sistema.

## [3.0.0] - 2026-10-08

Redesenho do front nativo com o design system "Mo baile · macOS 27 / Liquid
Glass" ([`docs/design/design-system/`](docs/design/design-system/)). A
versão MAIOR sobe porque a interface muda de estrutura: quem usa precisa
reaprender onde as coisas estão. O motor e o protocolo RPC não mudaram.
Decisões em [ADR 0002](docs/adr/0002-redesenho-liquid-glass.md).

### Mudado

- Janela em três colunas no padrão do macOS: barra lateral (Page Objects, Rede
  HTTP, Analytics e os passos do fluxo), espelho com workspace, e inspector
  recolhível (⌥⌘I) com hierarquia e atributos.
- As duas barras empilhadas viraram uma toolbar unificada (Liquid Glass no
  macOS 26): título e subtítulo da seção, pop-up de aparelho agrupado por iOS e
  Android (absorveu o seletor de plataforma), Repassar toque | Gravar passo,
  gravação, Rodar (a única cápsula tingida), busca e inspector. Com pouco
  espaço, o macOS manda os itens para o menu ».
- Estrutura do fluxo e Executar fluxo viraram sheets. Interromper é destrutivo
  e nunca é o botão padrão; Concluir fica desabilitado até o fim.
- O cartão de Correlação virou um popover, aberto pelo botão sob o espelho em
  Rede e Analytics.
- Rede e Analytics usam a tabela do sistema, que ordena pelo cabeçalho e
  redimensiona as colunas. O filtro foi para a busca da toolbar (⌘F).
- Cores do design system nas aparências Clara e Escura, com variantes de
  Aumentar contraste. O destaque é o flamingo escurecido `#C2456E`, também na
  seleção nativa (`AccentColor` compilado no empacotamento).
- Indicadores de status com ícone, cor e texto (antes, só um ponto colorido).
- Painéis abrem e fecham com mola; trocar de área é um crossfade de 180 ms.
- Botões com verbo e maiúscula em cada palavra principal ("Abrir Simulador",
  "Verificar de Novo", "Exportar HAR…").
- Largura mínima da janela: de 1320 pt para o mínimo das colunas abertas.

### Adicionado

- Janela de Ajustes (⌘,): aparência (Sistema, Claro, Escuro, guardada entre
  aberturas), seletor padrão e "Iniciar o espelho automaticamente"; a aba
  Conexões mostra os endereços do motor.
- Passos do fluxo na barra lateral. Escolher um passo destaca o código dele
  nos editores; menu de contexto com Copiar Locator e Copiar Seletor.
- Inspector: árvore expandida, com ← e → para recolher e expandir, menu de
  contexto (Copiar Locator, Copiar XPath, Copiar Atributos, Gravar como Passo)
  e o elemento escolhido destacado também no espelho.
- Menus Arquivo, Editar, Visualizar, Dispositivo, Automação e Janela com todas
  as ações da toolbar e atalhos (⌘1/⌘2/⌘3, ⌥1/⌥2, ⌃⌘Z Modo Zen, ⌘R, ⌘K,
  ⇧⌘E, ⌘S).
- Splash de abertura (1,5 s) com o mascote; reabre em Janela › Mostrar Splash.
- Rede: Copiar como cURL no menu de contexto e erro em linha quando o proxy
  não sobe, com "Tentar de Novo".
- Rede no iOS: "iPhone em Debug" lê pelo cabo as requisições do app em debug,
  sem proxy nem certificado (`netlog.start` / `netlog.stop`, a partir do log
  `CFNETWORK_DIAGNOSTICS=3`). Rede e Analytics mostram o mais novo no topo.

### Corrigido

- "Copiar tudo" dos atributos não fazia nada; agora copia.
- O atributo "enabled" mostrava `clickable`; passou a se chamar `clickable`.
- A execução de fluxo contava como aprovados todos os passos gravados e
  mostrava "tempo 0.0 s" fixo; agora conta os aprovados de fato e mede o tempo
  pelo log do runner.
- Sem tráfego capturado, "Gerar Asserção de Contrato" inseria um endpoint fixo
  com status 200; agora o botão fica desabilitado, e sem status a asserção não
  inventa um.
- O texto digitado nos passos de digitação aparece mascarado na barra lateral e
  na execução.
- O campo de busca da hierarquia não ganha mais foco sozinho ao abrir a janela.
- O editor recolore o código ao trocar de aparência.

### Removido

- `ScreenCatalogTests`, que fotografava as telas da 2.x; a janela 3.0 é
  fotografada por `WindowSnapshotTests` (com `MOBAILE_SNAPSHOT_DIR`).
- Componentes próprios substituídos por controles do sistema: `FluidPillButton`,
  `SegmentedControl`, `ActivityBadge`, `CanvasSwitch`, `UnderlineTabBar`,
  `CollapsedRail` e `PanelToggles`.

## [2.1.2] - 2026-10-06

### Adicionado

- `AGENTS.md` (importado pelo `CLAUDE.md`): todo agente que mexe em
  `engine/src/`, `apps/MoBaile/` ou `assets/` só conclui a tarefa com o
  "Mo baile (nativo).app" desta máquina reempacotado e verificado.
- `make verify-native` (`tools/verify_native_app.sh`): confere se a versão
  instalada é igual a `VERSION`, se o motor embutido é idêntico a
  `engine/src` e se o `engine.hello` responde pelo Python que o app usa.
  `make update-native` empacota e verifica.

## [2.1.1] - 2026-10-06

### Corrigido

- Execução de fluxo: o texto digitado não aparece mais no `flow.log`, nas
  notificações nem no stdout do motor; o log registra só o tamanho e o campo.
  Passo de digitação sem texto falha com motivo, em vez de digitar os textos
  inventados "Texto de Exemplo" ou "Texto de Teste".
- Proxy: redação de credenciais em corpo, URL, Location/Referer e erros;
  encaminhamento em blocos com teto de captura; recusas tipadas (400/413/501/502)
  sem chamar a origem; `Proxy-Authorization` não chega à origem.
- `flow.stop` cooperativo entre passos; falha de ADB reprova o passo.
- Front Swift preserva passos, edições e evidências quando o RPC falha e
  descarta respostas antigas de hierarquia pela geração.
- Gate de QA exige resumo válido, usa ferramentas falsas e portas efêmeras;
  testes Tkinter distinguem skip de erro.

### Acessibilidade

- Rótulos, estados e papéis para VoiceOver na toolbar, controles segmentados,
  abas, tabelas HTTP e de analytics, editores, espelho e estado vazio, com
  testes que leem a árvore de acessibilidade real do macOS.

### Documentação

- Revisão de QA de 05/10 (`docs/QA_2026-10-05.md`), relatório de pontos de
  melhoria (`docs/research/pontos-de-melhoria-2026-10-05.md`) e pendências da
  rodada de melhorias, com análise item a item e o trabalho parcial preservado
  (`docs/RODADA_2026-10-05_PENDENCIAS.md`).

## [2.1.0] - 2026-10-01

### Adicionado

- Tagueamento iOS no simulador: a aba Analytics lê o log do Firebase
  (`-FIRDebugEnabled`) pelo `log stream` do simulador, remontando a mensagem de
  várias linhas e mostrando um evento só por disparo, mesmo com o SDK logando
  cada evento em mais de um estágio.
- Tagueamento iOS em iPhone físico por cabo, via `pymobiledevice3` (dependência
  opcional `engine[ios-device]`). Seletor de origem na aba Analytics
  (Automático, Simulador ou o iPhone) e método `analytics.ios_devices`.
- Protocolo JSON-RPC v2 (etapa 1, "motor que não trava"): `engine.hello` com
  aperto de mão versionado, seis filas de despacho declaradas em
  `rpc/contract.py`, `$/cancelRequest` e `$/progress`.
- Cliente Swift com prazo por método vindo do motor, quadros sem acúmulo e
  reinício automático do motor quando ele cai.
- Estudo de mercado e plano de evolução em `docs/research/estudo-mercado/`.
- Versionamento: arquivo `VERSION`, este CHANGELOG, `tools/version.py`, hook de
  `pre-push` e verificação no CI.

### Corrigido

- Parar e reiniciar a escuta de analytics duplicava cada evento na interface.
- Estado da sessão protegido por lock e época; o desmonte do motor sobrevive a
  SIGTERM.

### Desempenho

- Import do motor de ~250 ms para ~60 ms, com dependências pesadas carregadas
  só quando usadas.

## [2.0.0] - 2026-09-08

Linha de base: primeira versão declarada, antes do versionamento formal. Motor
headless em Python com fronteira JSON-RPC, interface Tkinter e front nativo
SwiftUI em construção.

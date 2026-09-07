# Handoff: Mo baile — Interface Desktop (Mobile Element Recorder)

## Visão geral
Proposta de redesenho completo da interface desktop do **Mo baile** (inspetor de UI mobile,
espelhamento ao vivo, interceptador de rede e gerador de Page Objects para iOS/Android).
O pacote cobre 4 estados de tela em 1440×900, seguindo a linguagem visual do macOS
(Apple HIG / Xcode / Instruments): toolbar unificada, segmented controls pill, painéis
redimensionáveis, tipografia de sistema e barra de status de daemons.

## Sobre os arquivos de design
`Mo baile Desktop.dc.html` é **referência de design feita em HTML** — um protótipo que mostra
aparência, hierarquia e comportamento pretendidos. Não é código de produção para copiar.
A tarefa é **recriar essas telas no ambiente já existente do projeto**: Python 3.9+ com
Tkinter/Ttk, usando os módulos e widgets atuais (`recorder/ui.py`, `recorder/http_viewer.py`,
`recorder/automation_dialogs.py`, `FluidPillButton`, etc.). Onde o Tkinter não suporta um
efeito (sombra, blur, cantos arredondados), aproxime com Canvas/frames aninhados e cores
sólidas — a prioridade é hierarquia, espaçamento e paleta, não o efeito exato.

## Fidelidade
**Hi-fi.** Cores, tamanhos, pesos e espaçamentos são finais e devem ser reproduzidos.
Conteúdo textual do protótipo (nomes de arquivos, logs, endpoints) é exemplo ilustrativo.

## Estrutura geral da janela (todas as telas)
- Janela 1440×900 (mínimo 1100×720), fundo `#1E1E2E`.
- **Toolbar unificada única**, 52 px — substitui as duas barras atuais (top_bar + config_bar).
  Ordem: traffic lights nativos · título "Mo baile" + subtítulo "Element Recorder" ·
  segmented control `iOS | Android` · dropdown de dispositivo com dot de status ·
  toggles `Espelho`, `Streaming`, `Tap forward` · à direita: `Modo Passivo`, `Zen`,
  botão primário `Forçar Captura`.
- **Workspace em 3 colunas** com splitters: espelho 384 px · hierarquia 296 px · resto
  para código/rede.
- **Barra de status** 26 px, fundo `#11111B`: WDA 8100, ADB server, Proxy MITM 8082,
  FA listener (dots coloridos), coordenadas do mouse, FPS, settle, latência.

## Telas

### 1a — Conectado & Inspecionando (estado padrão)
- **Coluna 1 (384 px, fundo `#181825`)**: header `ESPELHO · TEMPO REAL` (10 px, letter-spacing
  .09em, `#6C7086`) + badge de FPS em verde. Espelho renderizado dentro de moldura de
  dispositivo: 264×552, `border-radius: 40px`, `border 1px #313244`, anel externo
  `box-shadow: 0 0 0 7px #11111B`, padding 7 px, tela interna `#151520` com raio 33 px e
  notch pill 78×20 (`#11111B`). Overlay do elemento sob o cursor: borda `2px #89B4FA`,
  raio 14 px, halo `0 0 0 4px rgba(137,180,250,.14)`, etiqueta acima com id + hit target
  (`btn_continuar · 44pt`). Indicador de clique: círculo 26 px, borda branca 2 px
  (animar como ripple 300 ms ease-out). Dock inferior: `‹ Voltar`, `Home`, `Girar`,
  `Screenshot` — pills 8 px de raio, fundo `#11111B`, borda `#313244`.
- **Coluna 2 (296 px)**: campo de busca (`Buscar texto, ID ou XPath`, atalho ⌘F à direita) +
  **árvore de acessibilidade** com disclosure triangles, indentação de 18 px por nível e
  chip 15×15 por tipo de nó (`W` window, `V` view/container `#A6ADC8`, `T` texto `#F9E2AF`,
  `I` input `#A6E3A1`, `B` botão `#89B4FA`). Nó selecionado: fundo
  `rgba(137,180,250,.16)`, borda `rgba(137,180,250,.35)`, raio 7 px.
  Rodapé fixo `ATRIBUTOS`: grid 82px/1fr, mono 10,5 px, chave em `#6C7086`, ação
  `Copiar tudo` em `#89B4FA`.
- **Coluna 3**: barra de 40 px com segmented control `Page Objects | Rede HTTP [12] |
  Analytics [4]` (badges numéricos de atividade), segundo segmented de estratégia
  `ID | XPath | Coords`, e à direita `Estrutura · 7 passos`, `Lado a lado` e botão
  `▶ Rodar Automação` (`#A6E3A1`, texto `#11111B`).
  Abaixo, dois editores lado a lado: `pages/onboarding_credito.py` (título `#89B4FA`) e
  `locators/onboarding_credito.py` (título `#94E2D5`), cada um com gutter de 34 px
  (`#45475A` sobre `#181825`), corpo mono 11,5 px / line-height 1.85.
  Rodapé de 38 px com detalhes do passo gerado + `código sincronizado` em verde.
- **Syntax highlighting**: keyword `#CBA6F7`, função `#89B4FA`, classe/tipo `#F9E2AF`,
  string `#A6E3A1`, número `#FAB387`, comentário `#6C7086`, texto `#CDD6F4`.

### 1b — Estado vazio (nenhum dispositivo)
Toolbar com dropdown vermelho `Nenhum dispositivo`, toggles em 40 % de opacidade e botão
primário desabilitado (`#26263a` / `#585B70`). Centro: placeholder de dispositivo 150×300,
borda tracejada `1.5px #45475A`, preenchimento com listras diagonais (repeating-linear-gradient
8/16 px) e rótulo mono `sem sinal`; título 19 px/640 "Conecte um dispositivo para começar";
subtítulo 12,5 px `#7F849C`. Dois cards de diagnóstico (grid 1fr 1fr, gap 14 px, raio 12 px,
fundo `#181825`): **iOS · WebDriverAgent** (dot `#0A84FF`) e **Android · ADB** (dot `#34C759`),
cada um com checklist `✓ #A6E3A1` / `! #F9E2AF` / `✕ #F38BA8` e ação (`Iniciar WDA` primário,
`adb devices` secundário). Linha mono no fim: `procurando dispositivos… · último scan hh:mm:ss`
(polling de 1,5 s do `device_watcher`).

### 1c — Aba Rede HTTP (proxy MITM)
Coluna 1 vira **espelho compacto** (186×390) e ganha bloco `CORRELAÇÃO`: mostra qual toque
disparou quantas requisições e eventos de analytics, com ação `Gerar asserção de contrato`.
Coluna direita: barra com o segmented (aba Rede ativa), campo `Filtrar host, path ou status`,
`Exportar HAR`, `Limpar tráfego` (`#F38BA8`); status do proxy no canto da toolbar.
**Tabela** (altura 296 px) com colunas `64px 62px 1fr 300px 84px 76px` =
MÉTODO · STATUS · HOST · PATH · TAMANHO · TEMPO; header mono 9,5 px em `#6C7086` sobre
`#181825`; linhas 11 px, separador `#26263a`; método GET `#89B4FA`, POST/PUT `#F9E2AF`,
CONNECT `#94E2D5`; status 2xx `#A6E3A1`, 3xx `#F9E2AF`, 4xx/5xx `#F38BA8`; linha selecionada
com fundo `rgba(137,180,250,.14)`. **Painel inferior** dividido: Request e Response, cada um
com abas `Headers | Body` (aba ativa com underline `1.5px #89B4FA`) e JSON destacado
(chave `#89B4FA`, string `#A6E3A1`, número `#FAB387`).

### 1d — Flow Runner (diálogo de execução)
Shell da app ao fundo dessaturado + overlay `rgba(17,17,27,.62)`. Modal 860 px de largura,
raio 14 px, borda `#45475A`, sombra `0 32px 80px rgba(0,0,0,.6)`:
- Header 44 px: título `Executar fluxo · onboarding_credito`, badge `EM EXECUÇÃO`
  (`rgba(166,227,161,.14)` / `#A6E3A1`), pré-condições à direita (`WDA 8100 ✓ · Proxy 8082 ✓`).
- Barra de progresso 5 px (`#313244` / preenchimento `#A6E3A1`) + `passo 4 / 7`.
- Esquerda (334 px): lista ordenada de passos — concluído (`✓` verde, fundo `#181825`),
  em execução (`◐` azul, fundo/borda azul translúcidos), pendente (borda `#26263a`,
  texto `#7F849C`); valores de input editáveis à direita de cada linha.
- Direita: terminal `#0B0B12`, raio 10 px, header mono `.flow_runner.py` / `stdout · streaming`,
  log com prefixos coloridos `INFO #89B4FA`, `PASS #A6E3A1`, `RUN #89B4FA`, `HTTP/FA #F9E2AF`,
  timestamp `#585B70`.
- Footer 52 px: resumo (`3 aprovados · 0 falhas · tempo 7,4 s`) + `Abrir log`,
  `Interromper` (`#F38BA8`), `Concluir` (desabilitado até o fim).

## Interações & comportamento
- Hover no espelho: bounding box do elemento sob o cursor (fade 120 ms).
- Clique no espelho: ripple 300 ms + geração de código; se `Tap forward` ativo, envia o toque
  ao aparelho (WDA `/session/.../wda/tap` ou `adb shell input tap`).
- Modo passivo: toque físico (Quartz/getevent) seleciona o nó na árvore e adiciona o passo.
- Frame-diff settle: quando o diff cai abaixo do limiar, dispara dump da hierarquia e mostra
  `tela estável` no log/status.
- Abas Rede/Analytics: badge numérico incrementa em tempo real; toque selecionado destaca
  as requisições correlacionadas.
- Modo Zen: colapsa toolbar e colunas laterais, mantendo espelho + código.
- Splitters arrastáveis; larguras mínimas: espelho 340 px, hierarquia 260 px, código 520 px.

## Estado necessário
`platform` (ios|android) · `selected_device` · `stream_active` · `mirror_visible` ·
`tap_forward` · `passive_mode` · `locator_strategy` (id|xpath|coords) · `locator_key` ·
`hierarchy_tree` + `selected_node` · `steps[]` (ordenáveis, com valores de input) ·
`http_requests[]` + `selected_request` · `analytics_events[]` · `daemon_status`
(wda, adb, proxy, fa) · `fps`, `settle_ms`, `latency_ms` · `run_state`
(idle|running|passed|failed) + `run_log[]` · `theme`.

## Design tokens
Fundos: base `#1E1E2E` · mantle `#181825` · crust `#11111B` · tela do device `#151520` ·
placeholder `#1f1f30`.
Bordas: `#313244` (padrão) · `#26263a` (sutil) · `#45475A` (modal/controle).
Texto: `#CDD6F4` primário · `#A6ADC8` secundário · `#7F849C` terciário · `#6C7086` label ·
`#585B70`/`#45475A` desabilitado.
Acentos: `#89B4FA` brand · `#A6E3A1` sucesso · `#F9E2AF` alerta · `#F38BA8` erro ·
`#94E2D5` teal (locators) · `#CBA6F7` keyword · `#FAB387` número ·
`#0A84FF` iOS · `#34C759` Android.
Traffic lights: `#FF5F57`, `#FEBC2E`, `#28C840`.
Raios: 6 (item de segmented) · 7–8 (controles/pills) · 9–12 (cards) · 14 (modal) ·
30–40 (moldura de device).
Alturas: toolbar 52 · header de painel 34 · barra de abas 40 · header de editor 30 ·
rodapé de detalhes 38 · status bar 26.
Tipografia: UI `SF Pro Text / -apple-system` — 10 px labels (600, letter-spacing .08–.09em),
11–11,5 px corpo, 12,5–13 px títulos, 19 px título de empty state;
código/dados `SF Mono / Menlo` — 10–11,5 px, line-height 1.75–1.85.
Toggle: trilha 34×20 raio 10 (`#89B4FA` on / `#313244` off), knob 16 px.

## Assets
Nenhuma imagem externa. Todos os elementos são formas/cores; imagens do app mobile aparecem
como placeholders listrados (`repeating-linear-gradient`). O vídeo de splash existente
(`splash_app.mp4`) permanece inalterado.

## Especificação em JSON
`mo_baile_ui_spec.json` é a fonte canônica para implementação automatizada: temas claro/escuro
(tema segue o ambiente do sistema), tokens, tipografia, métricas, componentes, telas, interações,
modelo de estado e mapeamento para os módulos `recorder/*.py`. Em caso de divergência entre o
README e o JSON, vale o JSON.

## Toggles de painel
A toolbar tem, no canto direito, três botões minimalistas (glifo retângulo + barra) que ocultam
qualquer painel: espelho (⌥1), hierarquia (⌥2), workspace (⌥3). Painel colapsado vira trilho
vertical de 30 px com rótulo e chevron. Apenas toolbar e barra de status são fixas.
⌥⌘F restaura o layout. Ver `components.panel_toggle_group` no JSON.

## Arquivos
- `Mo baile Desktop.dc.html` — as 4 telas (ids `1a`, `1b`, `1c`, `1d`) em stack vertical.
  Abre direto no navegador. Turno 2 (2a/2b) = paleta clara “Praia”; turno 1 (1a–1d) = paleta escura.
- `mo_baile_ui_spec.json` — especificação estruturada completa.

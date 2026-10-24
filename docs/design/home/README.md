# Tela Início 2.0 e tela Ambiente: especificação para implementação

Estado: **implementada na 3.11.0** (24/10/2026), a partir da proposta do mesmo
dia sobre a 3.10.0. Maquete no Claude Design (canvas "Mo baile · nova tela
Início"); as fontes das três telas estão em [`maquete/`](maquete/) como
`.dc.html` (HTML com estilos inline, servem de referência de layout, cor e
texto; não rodam fora do editor). Capturas do app em
`docs/design/telas/02c-*`, `02e-*`, `02f-*` e `02g-*`. A maquete anterior da
Início (3.10.0) continua em `home-maquete.html`.

### Decisões tomadas na implementação

- **Ambiente** é seção da janela, fixa no rodapé da barra lateral, com
  **⌘5**. O `⌘,` continua abrindo os Ajustes (já era dele).
- **Atalhos**: ⌘0 Início, ⌘1–⌘4 áreas (já existiam), ⌘5 Ambiente. Na barra
  lateral o atalho aparece enquanto a área não tem contagem.
- **Recentes**: últimos 20 itens, até 30 dias, em
  `~/Library/Application Support/Mo baile/recentes.json`. A Início mostra 5;
  "Ver Tudo" mostra todos. O motor **não** confere se o arquivo existe ao
  montar a tela (os caminhos costumam estar em ~/Documents e isso faria o
  macOS pedir acesso à pasta a cada abertura): quem tenta reabrir um item que
  sumiu tira o item da lista (`home.forget_recent`). Entram Page Object
  salvo, flow do Maestro exportado ou rodado de arquivo, e auditoria (com o
  export atualizando o subtítulo). "Fluxo gravado" sem arquivo não entra.
- **Novidades**: somem ao dispensar (×) e voltam na versão seguinte. O
  CHANGELOG vai embutido em `Contents/Resources`.
- **Barra inferior da sidebar**: mantida como estava (`+` e o aparelho).
- **"Rodar Flow…"** abre um `.yaml` do Maestro e roda pelo runner do motor,
  no painel de execução de sempre.

## 1. Problema e objetivo

Hoje a Início é, na prática, um diagnóstico de instalação: próximo passo,
status por área e a lista inteira do ambiente. Quem já tem a máquina pronta
abre o app e vê configuração.

Objetivo:

- **Início** vira uma tela de boas-vindas útil no dia a dia: escolher ou usar o
  aparelho, entrar numa área, continuar o trabalho recente.
- **Ambiente** vira uma tela à parte com tudo o que hoje está na Início
  (diagnóstico, pendências, comandos de instalação).
- Pendência de ambiente só aparece na Início **onde ela atrapalha** (por
  exemplo, no aparelho iOS que não consegue tocar sem o Appium), sempre com
  link para o Ambiente.
- Máquina zerada ganha uma Início de **primeira vez** em três passos.

Sem função nova de produto: é reorganização de tela. O que for regra (o que
está pronto, o que bloqueia o quê, qual estado da Início mostrar) vem do
motor, conforme a regra de ouro do [ARQUITETURA.md](../../ARQUITETURA.md).

## 2. Navegação

| Elemento | Hoje | Proposta |
|---|---|---|
| Barra lateral, topo | Início (com badge de pendências) | Início, **sem badge** |
| Barra lateral, Workspace | Page Objects, Rede HTTP, Analytics, Relatório | Igual, com atalho visível à direita (`⌘1`…`⌘4`) |
| Barra lateral, rodapé | — | Item fixo **Ambiente** (ícone `slider.horizontal.3`), com badge amarelo do número de pendências obrigatórias; some quando é zero |
| Barra inferior da sidebar | `+` e "Sem aparelho" | "Mo baile 3.10.0" à esquerda, dica `⌘, Ambiente` à direita (ou manter o que existe; decidir no PR) |
| Atalho | — | `⌘,` abre o Ambiente. **Proposta, não existe hoje.** Alternativa nativa: transformar o Ambiente na cena `Settings` do SwiftUI; a maquete supõe seção da janela principal |
| Atalhos de área | — | `⌘1`…`⌘4`. **Proposta, não existe hoje.** Conferir conflito com atalhos atuais |

Título da janela segue o nome da seção ("Início", "Ambiente").

## 3. Tela Início: dois estados

O motor decide qual estado mostrar (ver §6):

- `first_run`: motor pronto, mas nenhuma plataforma utilizável → tela
  **Primeira vez** (§3.2).
- `daily`: pelo menos uma plataforma utilizável → tela **Uso diário** (§3.1).

### 3.1 Uso diário (`maquete/Main.dc.html`)

Coluna central, `max-width` 1080, margem 32 (tela) e 36 no topo, `gap` 28
entre blocos. De cima para baixo:

1. **Cabeçalho**
   - Ícone do app 52×52, raio 12 (o asset real do ícone; na maquete é um
     placeholder azul).
   - Large Title 26 bold: saudação por hora + primeiro nome do usuário do macOS
     (`Bom dia` até 11:59, `Boa tarde` até 17:59, `Boa noite` depois). Sem nome
     disponível: só "Bom dia". Isso é apresentação, pode ficar no front.
   - Title 3 15, cor secundária: "O que vamos testar hoje?"
   - À direita, cápsula de status do ambiente: ponto (verde se tudo pronto,
     amarelo se há pendência) + texto mono/curto `Ambiente: 11 de 12 prontos`
     ou `Ambiente pronto` + seta. Clique abre o Ambiente.

2. **Bloco do aparelho** (muda com a conexão)
   - **Sem aparelho**: dois cartões lado a lado (2:1, quebram em tela estreita).
     - Cartão "Escolha um aparelho para começar": lista os alvos que o motor
       encontrou (simuladores e emuladores desligados, aparelhos físicos
       pareados). Cada linha: ícone 34×34 tingido pela plataforma (iOS
       `#0A84FF`, Android `#34C759` a 16%), nome, linha secundária
       (`Simulador iOS · desligado`), botão `Iniciar Simulador` /
       `Iniciar Emulador`. O botão padrão (preenchido com o destaque) vai no
       primeiro alvo **sem bloqueio**; os outros são secundários.
     - Linha de aviso (cor de aviso, ícone triângulo) quando o alvo tem
       limitação: `Só espelho: para tocar e gravar falta o Appium. Resolver…`
       (link para o Ambiente, rolando até a pendência).
     - Última linha, tracejada: instrução de cabo. "Aparelho físico: conecte
       pelo cabo. No iPhone, toque em Confiar; no Android, ligue a depuração
       USB. Ele aparece aqui sozinho."
     - Cartão lateral "Sem aparelho à mão?": explica que o Relatório funciona
       sem aparelho, link `Abrir Relatório…`.
     - Lista vazia (nenhum alvo encontrado): o cartão mostra só a linha do cabo
       e um link para o Ambiente instalar emulador/simulador.
   - **Com aparelho conectado**: um cartão só.
     - Miniatura do aparelho à esquerda (último quadro do espelho, se houver;
       senão a tela azul-piscina).
     - Nome em Title 2 17, chip da plataforma, status mono
       (`emulador · conectado`).
     - Frase: "Tudo pronto. Um clique no espelho toca no aparelho e grava o
       passo." (ou o aviso de limitação, se houver).
     - Ações em cápsula: `Espelhar e Gravar` (padrão), `Ver Rede HTTP`,
       `Escutar Analytics`, `Rodar Flow…`. Cada uma navega para a área já
       com o aparelho selecionado.
     - Coluna à direita, mono 11: status vivos com ponto verde/amarelo
       (`espelho a 60 quadros`, `proxy 8082 ouvindo`, `logcat conectado`).
       Vêm de notificação do motor, sem polling.

3. **Áreas**: título "Áreas" (Headline 13) + 4 cartões em linha (quebram).
   Cada um: ícone na cor da categoria, atalho mono à direita, nome em
   Headline, uma frase. **Sem** status de instalação (isso foi para o
   Ambiente).
   - Page Objects: "Cada toque vira locator e método Appium em Python."
   - Rede HTTP: "Tráfego do aparelho, com credenciais redigidas."
   - Analytics: "Eventos do Firebase em tempo real."
   - Relatório: "Eventos contra a spec do Figma. Sem aparelho."

4. **Linha inferior** (2:1, quebra)
   - **Continuar de onde parou**: lista agrupada, até 5 itens, link
     `Ver Tudo` no título. Cada linha: ícone do tipo, nome (mono para arquivos),
     linha secundária com contexto, data relativa mono à direita (`hoje 9:40`,
     `ontem`, dia da semana, depois data). Tipos: fluxo gravado, flow do
     Maestro, relatório, Page Object. Clique reabre o item na área certa.
     Estado vazio: "Nada por aqui ainda. Grave um passo ou abra um
     Relatório." com uma ação.
   - **Novidades da 3.10.0**: até 4 tópicos curtos da versão instalada + link
     `Ver Todas as Novidades…` (abre o CHANGELOG embutido). Some depois de
     dispensado ou depois de N aberturas; decidir no PR.

5. Rodapé central, legenda 12: "Tudo roda nesta máquina, sem internet."

Barra de status inferior: igual à atual (`wda 8100`, `proxy 8082`,
`analytics`, `motor 3.10.0 conectado`).

### 3.2 Primeira vez (`maquete/PrimeiraVez.dc.html`)

Coluna central estreita (`max-width` 760), conteúdo centralizado.

1. Ícone 88×88 (raio 20), Large Title "Boas-vindas ao Mo baile", frase:
   "Espelho, Page Objects, rede, analytics e relatório de tagueamento num
   lugar só. Vamos deixar esta máquina pronta em três passos."
2. Cartão com lista numerada de 3 passos:
   1. **Motor pronto**: check verde + `Python 3.14.0 encontrado, com Pillow e
      requests.` Se o motor não sobe, esta tela não aparece (vale o erro
      atual de motor).
   2. **Para qual plataforma você testa?** "Instalamos só o que ela precisa.
      Dá para adicionar a outra depois." Dois cartões selecionáveis (Android,
      iOS), cada um com o chip do que já foi achado (`adb encontrado`,
      `Xcode encontrado`), o que falta em uma frase e o botão
      `Preparar Android…` / `Preparar iOS…`, que roda o mesmo instalador do
      Ambiente (`instalar-mac.sh <alvo>` no Terminal). O cartão sugerido pelo
      motor (o que está mais perto de pronto) vem marcado com a borda de
      destaque.
   3. **Conectar um aparelho**: desabilitado até o passo 2 concluir.
3. Faixa tracejada "Quer explorar antes?" → `Abrir Relatório…`.
4. Legenda: "Tudo roda nesta máquina, sem internet. Os detalhes de cada
   componente ficam em Ambiente."

Quando o motor passa a reportar `daily`, a Início troca para o uso diário com
crossfade de 180 ms.

## 4. Tela Ambiente (`maquete/Ambiente.dc.html`)

É o conteúdo da Início atual reorganizado. `max-width` 860.

1. Cabeçalho: Title 1 22 "Ambiente", frase "O que está instalado nesta
   máquina e o que cada área precisa." À direita, `Verificar de Novo` e
   `verificado às 9:40` (mono 11).
2. **Resumo**: 4 cartões pequenos — Motor, Android, iOS, Extras opcionais —
   com `pronto` (verde), `só espelho` (aviso, borda amarela a 35%) ou
   `3 de 3`.
3. **Pendências**: um cartão por pendência obrigatória (hoje: "Instalar
   Appium com o driver XCUITest"), borda do destaque, rótulo
   `Falta 1 item`, explicação que diz o efeito ("…e no iOS os Page Objects
   ficam só no espelho."), comando em bloco mono, `Instalar no Terminal…` e
   `Copiar Comando`. Âncora para o link "Resolver…" da Início.
4. **O que funciona em cada área**: tabela Área × iOS × Android (substitui as
   linhas de status dos cartões de área da Início atual). Valores e cores vêm
   do motor.
5. **Grupos de componentes**: Motor, iOS, Android, Extras opcionais. Grupo com
   pendência vem antes. Cada linha: ícone de estado, nome, chip `Opcional`,
   detalhe mono truncado (caminho/versão). Linha pendente tem link
   `Resolver` que rola até o cartão do item 3.
6. Legenda: "Depois de instalado, tudo roda nesta máquina, sem internet."

## 5. Visual

Seguir o design system existente (`docs/design/design-system/` e
`apps/MoBaile/Sources/MoBaile/Theme/`). **Não copiar os hex da maquete**: ela
foi desenhada no Praia escuro; usar os tokens para funcionar em claro,
escuro, alto contraste e nas 9 paletas.

| Na maquete | Token |
|---|---|
| fundo `#1C1C1F`, sidebar `#222226` | fundo da janela / sidebar |
| cartão `#26262B` + borda 0,5 px `rgba(255,255,255,.07)` | `--bg-group`, borda interna 0,5 px, sem sombra |
| texto secundário `rgba(235,235,245,.62)` | rótulo secundário |
| `#C2456E` (botão padrão, seleção) / `#F389A9` (link no escuro) | destaque / texto de destaque |
| `#8FD685` / `#F5C451` | sucesso / aviso |
| `#0A84FF` / `#34C759` | iOS / Android |

- Raios: cartão 12, linha interna 10, campo/código 7, chip 4, botões em
  cápsula (28 de altura; 32 no cartão do aparelho conectado).
- Tipo: Large Title 26, Title 1 22, Title 2 17, Title 3 15, Body/Headline 13,
  legenda 11–12. SF Mono para nomes de arquivo, status, comandos, datas.
- Ícones SF Symbols: `house`, `chevron.left.forwardslash.chevron.right`,
  `globe`, `chart.line.uptrend.xyaxis`, `checklist`, `slider.horizontal.3`,
  `iphone`, `cable.connector`, `exclamationmark.triangle`,
  `checkmark.circle`, `play`, `record.circle`, `doc`, `terminal`,
  `doc.on.doc`, `arrow.clockwise`, `arrow.right`.
- Sem vidro no conteúdo (só toolbar/menus). Hover `--fill-secondary`,
  desabilitado 42%, foco com anel de 3 px.
- Layout responsivo: blocos lado a lado usam `ViewThatFits` ou layout com
  quebra; em janela estreita empilham (ver ajustes da 3.6 para monitor
  pequeno).

## 6. Motor (RPC)

Regra de ouro: quem decide estado, pendência e impacto é o motor. O front só
desenha. Antes de criar método, **conferir `engine/src/mobaile/rpc/contract.py`**
e reaproveitar o que já existe (diagnóstico do `services/setup`, listagem de
`services/devices`, notificações de aparelho).

Proposta aditiva (`PROTOCOL_VERSION` continua 2):

- **`home.summary`** (requisição) → objeto com:
  - `state`: `"first_run" | "daily"`.
  - `environment`: `{ready: int, total: int, pending: [{id, title, blocks: [{area, platform, effect}]}]}`
    — contagem conta só itens obrigatórios; `blocks` alimenta as linhas de
    aviso da Início e a tabela do Ambiente.
  - `targets`: `[{id, name, platform, kind: "simulator"|"emulator"|"physical", running: bool, connected: bool, capabilities: {mirror, tap, record}, blocked_by: [pending_id]}]`.
  - `suggested_platform` (para a Primeira vez).
  - `recent`: `[{kind: "flow"|"maestro"|"report"|"page_object", title, subtitle, path, at}]`, até 5. **Novo**: hoje o motor não guarda histórico; precisa de um índice local (sem nuvem) em `~/Library/Application Support/Mo baile/`.
  - `whats_new`: `{version, items: [str]}` lido do CHANGELOG embutido.
- **`environment.matrix`** (ou campo no diagnóstico atual): linhas Área ×
  plataforma com `status` (`ready|partial|missing|not_needed`) e texto.
- Notificação **`home.changed`** quando aparelho conecta/desconecta, alvo
  liga/desliga ou o diagnóstico muda. A interface não faz polling.

Depois de mexer no contrato: `make fixtures` e atualizar
[`PROTOCOLO_RPC.md`](../../PROTOCOLO_RPC.md).

## 7. Front (SwiftUI)

Sugestão de quebra (ajustar aos nomes reais em `Views/`):

- `HomeView` → escolhe `HomeDailyView` ou `HomeFirstRunView` por
  `summary.state`.
- `HomeHeader`, `EnvironmentStatusPill`, `DeviceHeroCard` (estados sem/com
  aparelho), `TargetRow`, `AreaGrid`/`AreaCard`, `RecentList`/`RecentRow`,
  `WhatsNewCard`.
- `EnvironmentView` com `EnvironmentSummary`, `PendingCard`,
  `AreaMatrixTable`, `ComponentGroup`/`ComponentRow` — reaproveitar as views
  de diagnóstico da Início atual.
- Novo item de navegação `.environment` fixo no rodapé da sidebar, com badge.
- Componentes novos ganham versão no design system web
  (`docs/design/design-system/components/`) e captura em
  `docs/design/telas/` (claro e escuro).

## 8. Critérios de aceite

- [ ] Abrir o app numa máquina pronta mostra a Início sem nenhuma lista de
      instalação.
- [ ] Tudo o que estava na Início antiga está no Ambiente, sem perda de
      informação nem de ação (Instalar no Terminal, Copiar Comando, Verificar
      de Novo).
- [ ] O badge de pendências aparece no item Ambiente, não no Início.
- [ ] Pendência que limita um alvo aparece na linha daquele alvo com
      "Resolver…" levando ao cartão certo no Ambiente.
- [ ] Máquina sem plataforma pronta abre a Primeira vez; ao concluir, troca
      sozinha para o uso diário.
- [ ] Conectar/desconectar aparelho troca o bloco do aparelho sem recarregar
      (via notificação).
- [ ] Continuar de onde parou reabre o item na área certa; estado vazio tem
      uma frase e uma ação.
- [ ] Claro, escuro, aumentar contraste, reduzir transparência, reduzir
      movimento e as 9 paletas conferidos; `PaletteCheck` passa.
- [ ] VoiceOver lê ícones de estado ("pronto", "pendente") e botões só com
      ícone têm rótulo.
- [ ] Janela estreita empilha os blocos sem corte.
- [ ] `make check`, `make test-swift` e fixtures em dia; versão nova (minor,
      3.11.0) com CHANGELOG; `make update-native` + `verify-native` com o
      app encerrado por ⌘Q pelo dono.

## 9. Em aberto

- Ambiente como seção da janela (maquete) ou como cena `Settings` (`⌘,`
  nativo).
- Atalhos `⌘1`…`⌘4` e `⌘,`: confirmar que não conflitam.
- Regra para esconder "Novidades".
- Onde guardar o índice de recentes e quanto histórico manter.
- Windows (`apps/tk-legacy`) está congelado (ADR 0005): **fora do escopo**.

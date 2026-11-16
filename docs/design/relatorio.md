# Relatório — anatomia da tela

Área nova do front nativo (3.2.0), desenhada com os componentes do design
system "Mo baile · macOS 27 / Liquid Glass" ([`design-system/`](design-system/)).
O protótipo do design system não tem esta tela; o que segue é como ela foi
montada com as peças que já existiam, para a próxima revisão de design partir
daqui. Decisões de produto e de arquitetura em
[ADR 0003](../adr/0003-relatorio-tagueamento.md).

## Onde fica

- Barra lateral, seção Workspace, quarto item: **Relatório**, ícone
  `checklist` na cor da categoria do Analytics (`cat2`, verde), porque é a
  auditoria dele. A contagem é o que pede ação (divergentes + não disparadas).
- ⌘4 no menu Visualizar; ⌘O abre a spec de qualquer área.
- Funciona **sem aparelho**: a área ocupa a coluna central inteira, sem
  espelho. O título da janela é "Relatório" e o subtítulo diz o projeto, as
  validações e a conformidade.

## Estrutura

```
┌ Toolbar (a do app) ─────────────────────────────── busca: filtrar tabela ┐
├ Barra acessória 36 pt ───────────────────────────────────────────────────┤
│ [doc] Projeto · spec.json ▾  [antena] Eventos Capturados (N) ▾  [iphone] │
│ Android ▾                         [Auditar] [Exportar ▾] [Copiar ▾]      │
├ Resumo ──────────────────────────────────────────────────────────────────┤
│ 42,9% conforme  ✓ 3 OK  ✕ 2 divergentes  ! 2 não disparadas  …  origem   │
│ ███████████░░░░░░░░░░░ (ProgressBar, success)                            │
│ [Todas 7 | Pedem Ação 4 | Divergentes 2 | Não Disparadas 2 | OK 3 | …]   │
├ Tabela do sistema ───────────────────────────────────────────────────────┤
│ Status · Seção · Fluxo · Evento · Variação · Divergências · Horário · N  │
├ Detalhe (VSplitView) ────────────────────────────────────────────────────┤
│ Validação [status]       [Copiar] │ Bloco | Disparo            [Copiar]  │
│ ✓ screen_name  obtido  esperado   │ // PDE · evento [ERRO]             │
│ ✕ component    toggle  button     │ { "component": "toggle",  ✗ ... }    │
└──────────────────────────────────────────────────────────────────────────┘
Inspector: "Card do Figma" — seção, card, evento, fluxo, variação e o print.
```

## Componentes usados

| Parte | Componente | Observação |
|---|---|---|
| Barra | `AccessoryBar`, `Menu` `.borderlessButton`, `Button` | `ViewThatFits`: em largura estreita os rótulos viram ícone e o nome da spec encurta |
| Exportar | `Menu` com `primaryAction` | clique exporta para a pasta padrão; a seta oferece "Exportar Para…", abrir o HTML, o board e o Finder |
| Status | `StatusIndicator` | ícone, cor e texto, nunca só cor: OK (`ok`), Divergente (`error`), Não disparado (`warn`), Fora da spec (`off`) |
| Conformidade | `DSFont.title1` + `ProgressBar` (`success`) | número com algarismos tabulares |
| Filtro | `Picker` segmentado `.small` | cai para menu quando não cabe |
| Tabela | `Table` do sistema | ordena pelo cabeçalho; evento em mono no destaque, como em Analytics |
| Detalhe | `DetailHeader`, `CodeBlock`, `KeyValueGrid`, `InlineError` | o bloco é o mesmo texto do board Excalidraw e do HTML |
| Spec aberta sem auditoria | `dsCard` com `Grid` | o botão padrão (↩) é Auditar |
| Sem spec | estado vazio com duas ações | "Importar Prints do Figma…" e "Abrir Spec…" (padrão) |
| Operação longa | sobreposição com `ProgressView` + `dsCard` | mostra a mensagem do `$/progress` do motor; sem vidro, porque é conteúdo |
| Importação | `.sheet` 560×520 | lista de dúvidas por card; "Usar Esta Spec" só habilita se o rascunho valida |

## HTML exportado

Desde a 3.8.0 o `relatorio.html` do Exportar é a própria aba Relatório fora do
app, num arquivo único que abre em qualquer navegador e sem internet
(`engine/src/mobaile/services/report/html_report.py`).

- **Identidade**: toolbar de vidro com o ícone do app, barra lateral com as
  seções da spec (ponto com o pior status de cada uma), conteúdo liso, e o
  rodapé em letras miúdas "Gerado pelo Mo baile X.Y.Z · data".
- **Design system inteiro embutido**: `html/design_system.css` é a
  concatenação de `docs/design/design-system/styles.css` (tokens das quatro
  aparências, vidro, molas e as classes `.mb-*`), gerada por
  `tools/sync_report_assets.py`; os glifos vêm do `Icon.jsx`. O teste
  `test_report_html.py` falha se o design system mudar e a cópia não.
- **Aparência**: segue o sistema (claro, escuro, Aumentar contraste, Reduzir
  movimento e Reduzir transparência) e tem o seletor Automático/Claro/Escuro
  na toolbar, lembrado no navegador.
- **Período do log** (3.9.0): ao lado da plataforma, em destaque, a data e
  a hora do primeiro ao último evento do log auditado, com a duração ("Log
  08/10 10:00:00 até 10:06:00 · 6 min"). O logcat traz dia e mês; o log do
  iOS, o ano também; sem data, fica só a hora. O Markdown leva a mesma linha.
- **Resumo**: anel de conformidade com OK, divergentes e não disparadas; os
  quadros de contagem também filtram.
- **Filtro e busca**: o mesmo segmentado do app (Todas, Pedem Ação,
  Divergentes, Não Disparadas, OK, Fora da Spec) e busca em evento,
  parâmetro, valor e divergência. Atalhos: `/` busca, `1`–`6` filtram, `t`
  troca cards e tabela, `b` expande os blocos.
- **Cards**: print do card (clique amplia num popover de vidro) e uma coluna
  por fluxo; cada validação tem a tabela Parâmetro · Obtido · Esperado do
  painel Validação, e o "Bloco" (o mesmo texto do board) com Copiar.
- **Tabela**: as colunas da tabela do app, ordenáveis; a linha leva ao card.
- **Movimento**: Motion 13.5.1 (MIT, embutido) com as molas do design system
  (snappy 0,35 s/0,15 e smooth 0,5 s/0). Toda animação termina em até 1,5 s
  mesmo sem quadros, e com Reduzir movimento tudo vira esmaecer. Sem
  JavaScript, ou na impressão, o conteúdo aparece inteiro.
- **Segurança**: texto da spec e do log sempre escapado; a política de
  conteúdo bloqueia rede e só autoriza os três scripts embutidos pelo hash.

Atualizar o Motion: baixar o pacote `motion` do npm, conferir o `integrity`
com `npm view motion@X dist.integrity`, copiar `dist/motion.js` para
`html/motion.min.js` e trocar `MOTION_VERSION`.

## Editor de spec (3.21.0)

"Editar Spec" troca o conteúdo da área (resumo, tabela e detalhe) pelo editor
da spec; a barra acessória e o inspector continuam. Entradas: menu da spec,
cartão da spec aberta sem auditoria e "Abrir no Editor" da revisão da
importação (`ReportSpecEditorView.swift`).

- **Cabeçalho**: "Editar Spec", a linha projeto · arquivo · N cards · N
  alterados, o segmentado Quadro | Tabela, Fechar (Esc, pergunta antes de
  descartar) e Salvar (⌘S, botão de destaque).
- **Quadro**: seções na ordem da spec; em cada uma, grade adaptável de
  quadros de 300 a 420 pt. O quadro segue a caixa de classe da UML: nome
  (card N, título, evento em mono, seção) sobre fundo `bgContentAlt`, depois
  os compartimentos Parâmetros, Variações e Observação separados por linha.
  O ícone de foto abre o print num popover. "Alterado" usa o
  `StatusIndicator` de aviso; card com problema ganha borda `destructive` e a
  lista do que corrigir no rodapé.
- **Tabela**: `Table` do sistema com Card, Evento, Onde (Parâmetro ou
  Variação N), Parâmetro e Valor; as duas últimas são campos. Acrescentar e
  remover linhas é no Quadro.
- **Validação**: o que não precisa do arquivo é conferido a cada tecla
  (`ReportCardDraft.problems`); o resto vem do motor em `spec_error`, em
  linha no topo, com o card citado em destaque.
- **Gravação**: `report.cards_update` com os cards diferentes do disco. Se a
  spec é a da aba, o resumo é atualizado e a auditoria roda de novo; se a aba
  não tinha spec, a gravada passa a ser a dela.

Fora do editor por enquanto: criar, remover e reordenar cards, e editar
`params_por_fluxo` e a observação por fluxo (ficam no JSON).

## Checklist da importação (3.18.0)

A importação dos prints grava, ao lado do rascunho, `<spec>.checklist.md`:
uma seção por seção da spec, um bloco por card (título, print, parâmetros
esperados) e a lista "Conferir" com um item ⚠ por dúvida do OCR e um item por
disparo (fluxo x variação, os mesmos da auditoria). O Markdown é a fonte.

Com uma spec aberta, o botão "Checklist" da barra (e "Exportar Checklist…" no
menu Arquivo) exporta direto, sem log nem auditoria: usa o `.checklist.md` ao
lado da spec ou gera um da spec. Sem spec, o menu pede o `.md`. Também há o botão
Checklist na revisão da importação. A exportação grava `checklist_<nome>_<dd-mm-aaaa>.html` ao lado do `.md` e abre
no navegador. A página usa a mesma casca do relatório exportado
(`design_system.css` + `report.css`, mais `html/checklist.css` e
`html/checklist.js`): toolbar de vidro, barra lateral com o progresso de cada
seção, anel de concluído, tiles que filtram, filtro Todos / Pendentes / Feitos /
Revisar OCR (teclas 1–4), busca (/), tema, impressão e "Copiar Markdown" (c),
que devolve o arquivo com `[x]` no que foi marcado na página. As marcações da
página ficam no navegador, por conteúdo do Markdown.

## Texto

- Botões no infinitivo com maiúscula nas palavras principais: "Auditar",
  "Exportar Para…", "Abrir Spec…", "Importar Prints do Figma…",
  "Usar Esta Spec", "Exportar Checklist…".
- Status em palavra: "OK", "Divergente", "Não disparado". O TSV e o Markdown
  continuam com "ERRO" e "NÃO DISPARADO", que é o formato que o time já cola
  em planilha e em PR.
- Erros dizem o que fazer: "Nenhum evento capturado nesta sessão. Inicie a
  escuta em Analytics ou escolha um arquivo de log."

## Acessibilidade

- A primeira célula de cada linha lê a variação inteira: status, evento,
  variação, fluxo e divergência.
- Cada parâmetro do detalhe é anunciado como
  "component: diverge, obtido toggle, esperado button".
- Menus da barra têm nome próprio ("Spec de tagueamento", "Origem dos
  eventos", "Plataforma auditada") e valor.
- Cobertura em `ReportAccessibilityTests`.

## Pontos para a próxima revisão de design

- Uma cor de categoria própria para o Relatório (`cat4`) pediria o token nas
  quatro aparências e nas nove paletas.
- O print do card no inspector usa a largura do inspector; um modo "board"
  (print ao lado das colunas por fluxo, como no Excalidraw) seria o próximo
  passo visual.
- Capturas de referência: `WindowSnapshotTests` (`12-relatorio-claro` a
  `15-relatorio-vazio-claro`), geradas com `MOBAILE_SNAPSHOT_DIR`.

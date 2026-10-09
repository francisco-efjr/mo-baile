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
│ ✓ screen_name  obtido  esperado   │ // CPAGI · evento [ERRO]             │
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

## Texto

- Botões no infinitivo com maiúscula nas palavras principais: "Auditar",
  "Exportar Para…", "Abrir Spec…", "Importar Prints do Figma…",
  "Usar Esta Spec".
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

# Spec: aba Page Objects no modelo do PyCharm

Status: rascunho para o dono · Plataforma: desktop (macOS 14+) · Sistema: design system do Mo baile (`Views/DesignSystem/`, `Theme/DesignTokens.swift`) · Direção: sistema existente, com o editor no esquema "PyCharm" (D-1) · Rótulos: Verificado · Inferido · Suposição

Brief: quem escreve Page Object em Python lê, cola e edita o código gerado como faria no PyCharm, sem perder espelho nem hierarquia · Superfície: Operate

Base: `docs/research/pycharm-page-objects.md` (gap analysis, P0/P1, teste T1–T4). Decisões do orquestrador D-1 a D-5 valem aqui sem repetição.

## Reutiliza

- `AccessoryBar`, `BarIconButton`, `EmptyState`, `StatusIndicator` (`Views/DesignSystem/Bars.swift`, `Content.swift`, `Indicators.swift`).
- Tokens `bgContent`, `separator`, `labelPrimary/Secondary/Tertiary`, `selectionContent`, `DesignMetrics.Heights.editorHeader` e `.codeFooter`, `DSFont.callout`, `DSFont.mono`.
- Padrão de árvore achatada com `List(selection:)` e `onKeyPress` de `Views/Hierarchy/HierarchyTreeView.swift`.
- Contraste por `PaletteMath.contrast` (`Theme/Palettes.swift`).

Adições intencionais (o sistema não tinha):
- **Esquema do editor "PyCharm"** (`EditorScheme`), separado do tema do app: só o editor usa. O resto da janela continua na paleta escolhida (R1 da pesquisa).
- **Faixa de tool windows** de 32 pt à esquerda da área (componente novo `ToolWindowStripe`, só nesta aba).
- **Painel Projeto** (`ProjectTreeView`).

## Layout

```text
┌ barra lateral ┬ espelho ┬──────────────── área Page Objects ───────────────────┬ inspector ┐
│ Início        │         │ barra acessória: Seletor · arquivo · Estrutura · Lado │ Hierarquia│
│ Page Objects  │         ├──┬───────────────┬────────────────────────────────────┤ (como hoje│
│ Rede …        │         │▣ │ Projeto  ⊕◎⇵⋯–│ pages/x.py │ locators/x.py │ a.py ×│ ⌥⌘I)      │
│ Fluxo · passos│         │☰ │ Mo baile ~/Do…│ 1 │ def tocar(self):               │           │
│               │         │  │ ▾ pages       │ 2 │     self.click(...)            │           │
│               │         │  │   x.py        │   │                                │           │
│               │         │  │ ▸ locators    │   │                                │           │
│               │         ├──┴───────────────┴───┴────────────────────────────────┤           │
│               │         │ passo 3 · tap   12:5  LF  UTF-8  4 spaces  Python 3.13  ● não salvo│
└───────────────┴─────────┴────────────────────────────────────────────────────────┴───────────┘
```

- **Faixa** (esquerda, 32 pt, fundo `bgContent`, separador à direita): botão "Projeto" (alterna o painel) e botão "Hierarquia" (alterna o inspector existente, a mesma ação do ⌥⌘I). Botão ligado usa o estado `isOn` do `BarIconButton`.
- **Painel Projeto** (largura 220 pt padrão, 160–360 pt, `@SceneStorage("larguraProjeto")`): árvore servida pelo motor. Escondido, a faixa continua.
- **Editor** ao centro: abas `pages/<chave>.py`, `locators/<chave>.py` (fixas, como hoje) e uma aba por arquivo aberto da árvore, com ×. "Lado a lado" continua mostrando pages e locators juntos.
- **Espelho e hierarquia** ficam onde estão (D-5). Vidro não entra em editor, árvore nem faixa (ADR 0006).

## Editor ("leitor de texto")

| Item | Valor | Rótulo |
| --- | --- | --- |
| Fonte | JetBrains Mono 13, altura de linha 1,2, sem ligaduras; SF Mono 13 se o registro falhar | D-1 |
| Esquema | "PyCharm": Islands Dark no escuro (tabela 2.5 da pesquisa); IntelliJ Light no claro | Escuro Verificado; claro Inferido (valores de memória do esquema IntelliJ Light, conferir com `expUI_lightScheme.xml`) |
| Número de linha | `#4B5059` do PyCharm dá 2,15:1 sobre `#191A1C`; ajuste mínimo para `#61666E` (3,01:1). Linha atual `#A1A3AB` (6,92:1) | Calculado |
| Soft wrap | desligado, rolagem horizontal | Verificado (PyCharm) |
| Entrada | literal: nenhuma substituição do sistema, CR e CRLF viram `\n` ao colar e ao receber | Verificado (PyCharm) |
| Caracteres especiais | etiqueta com a abreviação (NBSP, ZWSP, LRM…), texto intacto | Verificado (PyCharm) |
| Linha atual | fundo `#1F2024` (escuro) | Verificado |
| Tab | 4 espaços | Inferido |
| Ao salvar | UTF-8 sem BOM, `\n`, sem remover espaço no fim nem forçar quebra final (D-3) | D-3 |

## Estados

| Estado | Aparência | Comportamento | Texto |
| --- | --- | --- | --- |
| Sem passo e sem código | `EmptyState` + dicas | Botão "Gravar Passo" se houver aparelho | "Nenhum passo gravado" e as dicas abaixo |
| Editor com código, sem salvar | rodapé com ponto `warning` | ⌘S grava | "não salvo" |
| Salvo | rodapé com ponto `ok` | — | "salvo às 14:32", caminho no tooltip |
| Árvore carregando | `EmptyState(loading:)` compacto | — | "Lendo a pasta…" |
| Árvore vazia (pasta não existe) | `EmptyState` compacto | — | "A pasta ~/Documents/Mo baile ainda não existe. Salve um Page Object (⌘S) para criá-la." |
| Árvore com erro | `InlineError` | "Tentar de novo" | mensagem do motor |
| Motor desconectado | árvore em branco com aviso | — | "Motor não conectado" |
| Arquivo aberto não UTF-8 | aba com cadeado, editor só leitura | gravação recusada | "somente leitura: não é UTF-8" |

Dicas do editor vazio (só atalhos que existem no Mo baile, D-2):
- "Paleta de Comandos ⇧⌘P"
- "Iniciar Espelho ⌘E"
- "Salvar Page Object ⌘S"
- "Mostrar Projeto: botão na faixa à esquerda"

## Rodapé (status do editor)

`passo N · ação · estratégia` à esquerda (como hoje). À direita, como na status bar do PyCharm: `linha:coluna`, `LF`, `UTF-8`, `4 spaces`, `Python 3.x.y` (de `setup.check`, tooltip com o caminho), estado salvo. Coluna: grafemas, com tab expandido até a próxima parada de 4 (Inferido do PyCharm; conferir no oráculo com L3 e L6).

## Árvore Projeto

- Raiz: "Mo baile" em `labelPrimary` + caminho abreviado (`~/Documents/Mo baile`) em `labelTertiary`, como na referência.
- Conteúdo (D-4): `pages/`, `locators/`, `flows/`. Pastas primeiro, ordem alfabética. Até 2.000 nós; arquivo maior que 1 MB não abre.
- Cabeçalho (`PaneHeader`): "Projeto" + Localizar Arquivo Aberto (alvo), Expandir Tudo, Recolher Tudo, Atualizar, Ocultar (–).
- Teclado: ↑↓ movem, ← recolhe, → expande, ↩ abre o arquivo, digitar letras abre a busca rápida (speed search) no topo do painel; ↑↓ passam entre os nós que casam, ⎋ fecha a busca.
- Abrir: clique duplo ou ↩. O arquivo `pages/<chave>.py` da sessão atual leva à aba pages, não abre uma cópia.

## Atalhos (D-2)

Nenhum atalho existente muda. Novos só onde o registro está livre:

| Ação PyCharm | PyCharm | Mo baile | Motivo |
| --- | --- | --- | --- |
| Project tool window | ⌘1 | paleta: "Mostrar Projeto"/"Ocultar Projeto" | ⌘1 é Page Objects |
| Recent Files | ⌘E | — | ⌘E é Espelho |
| Expandir/Recolher tudo na árvore | ⌘+ / ⌘- | ⌘+ / ⌘- com foco na árvore | livres no contexto da árvore |
| Speed search | digitar | digitar | — |

## Teclado e acessibilidade

- Faixa: cada botão com `accessibilityLabel` ("Projeto", "Hierarquia") e `accessibilityValue` "ligado/desligado".
- Árvore: `accessibilityLabel("Árvore do projeto")`; cada linha diz "pasta pages, expandida" ou "arquivo feature.py"; o campo da busca rápida tem rótulo "Busca rápida na árvore".
- Editor: o VoiceOver lê o texto real (as etiquetas são só desenho).
- Rodapé: um elemento por item, rótulo falado ("Linha 12, coluna 5", "Separador de linha LF", "Codificação UTF-8", "Recuo de 4 espaços", "Interpretador Python 3.13.1", "Não salvo").
- Contraste calculado (tabela no relatório do dev): texto 9,37:1, comentário 4,27:1 (abaixo de 4,5, igual ao PyCharm; risco registrado), número de linha ajustado 3,01:1.
- Aumentar contraste: número de linha e etiqueta usam `#A1A3AB`.

## Critérios de aceite (observáveis)

- T1 colado no editor vira exatamente L1–L9 unidas por `\n`; o cabeçalho diz "9 linhas"; salvar grava os bytes da seção 5.3 da pesquisa.
- NBSP e ZWSP aparecem como etiqueta; copiar devolve U+00A0 e U+200B.
- Digitar `def` recolore na hora; gravar um passo com o cursor no meio do texto não move o cursor; ⌘Z desfaz a última edição manual.
- Rodapé muda de "não salvo" para "salvo às hh:mm" depois do ⌘S.
- A árvore lista `pages/`, `locators/` e `flows/` e abre um arquivo no editor; caminho fora da pasta ou por link simbólico é recusado pelo motor.

## Decisões pendentes do dono

1. Esquema "PyCharm" como padrão também no claro (valores Inferidos) ou só no escuro.
2. ⌘1 de novo em Page Objects alternar a árvore (muda o comportamento de um atalho existente).
3. Ajuste do número de linha `#4B5059` → `#61666E` (fica 3:1, diverge do PyCharm em 22 pontos de luminância).

## Verificado / Inferido / Não verificado

- Verificado: valores do PyCharm marcados assim na pesquisa; código atual lido.
- Inferido: esquema claro, contagem de coluna, recuo de L9 no oráculo.
- Não verificado: comparação com o PyCharm real (oráculo da seção 5.1), VoiceOver real.

# Dev: aba Page Objects no modelo do PyCharm (PO-1 a PO-5)

Status: implementado na branch `melhoria/2026-11-03-pycharm-dev`, sem push e sem reempacotar o app (o orquestrador integra e roda `make update-native`). Data: 2026-11-04.

Base: `docs/research/pycharm-page-objects.md` e `revisao/spec-page-objects.md`. Decisões D-1 a D-5 do orquestrador aplicadas como escritas; desvios estão em "Decisões pendentes".

## O que mudou, por ID

### PO-1 (P0-1, P0-2, P0-3, P0-5): caracteres idênticos ao PyCharm

- `CodeTextView.configurarEntradaLiteral()` desliga tudo: `enabledTextCheckingTypes = 0`, aspas, travessão, correção, substituição de texto, ortografia contínua, gramática, links, dados, completar, `smartInsertDeleteEnabled`, `inlinePredictionType = .no` e `writingToolsBehavior = .none` (macOS 15+).
- Colar, soltar e Serviços passam por `readSelection(from:type:)`. CR e CRLF viram LF e nada mais muda. O texto que chega do estado também é normalizado.
- Tab insere espaços até a próxima parada de 4 colunas (4 no começo da linha).
- O editor tem histórico de desfazer próprio, e ⌘Z/⇧⌘Z do menu chegam a ele. Antes iam para o histórico da janela.
- Sem soft wrap: rolagem horizontal, container infinito e uma linha visual por linha lógica.
- `EditorText` conta linhas por bytes. "1 linha" com CRLF não acontece mais.
- Motor: `codegen.save` grava com `newline="\n"` e normaliza CR/CRLF (`_texto_com_lf`). Grava UTF-8 sem BOM, sem normalização Unicode, sem tirar espaço do fim e sem forçar quebra final (D-3).

### PO-2 (P0-4): caracteres especiais visíveis

- `CaracteresEspeciais` traz a lista de `SpecialCharacterFragment.java` (C0 menos tab/LF/CR, DEL, C1, NBSP, SHY, CGJ, U+2000–200A, ZWSP, ZWNJ, ZWJ, LRM, RLM, LSEP, PSEP, bidi, NNBSP, MMSP, WJ, ZWNBSP) e as duas exceções:
  - espaço antes de marca combinante não vira etiqueta;
  - ZWJ e ZWNJ vizinhos de caractere não ASCII também não.
- `CodeLayoutManager` marca o glifo como controle. Isso dá largura à etiqueta e faz LSEP/PSEP pararem de quebrar linha. A etiqueta é a abreviação num retângulo de 1 pt.
- O texto não muda: a cópia e o valor do VoiceOver continuam com o caractere original (testado).

### PO-3 (P0-6, P0-7, P0-8): fonte, esquema, linha atual, realce

- **Fonte.** JetBrains Mono Regular, Bold, Italic e BoldItalic foram copiadas da instalação local do PyCharm para `assets/fonts/`, junto com `OFL.txt` (SIL OFL 1.1 com o aviso de copyright da JetBrains). README › Licença cita a fonte, e `package_macos_app.sh` copia a pasta para `Contents/Resources/fonts`.
- **Registro.** `EditorFont` registra as fontes com `CTFontManagerRegisterFontsForURL(.process)` e cai para SF Mono se falhar. Padrões: 13 pt, altura de linha fixa em round(altura natural × 1,2), linha de base centralizada, `.ligature: 0`. O gutter usa a mesma família 1 pt menor, alinhado à linha de base do texto.
- **Esquema.** `EditorScheme.pycharm` é o padrão:
  - escuro: Islands Dark, com os valores da tabela 2.5 da pesquisa;
  - claro: IntelliJ Light, com valores **Inferidos** (ver pendências).
  - Em Ajustes › Geral › "Cores do editor" dá para voltar à paleta do app.
- **Contraste** (WCAG, calculado):

  | Par (escuro) | Contraste |
  |---|---|
  | texto `#BCBEC4` sobre `#191A1C` | 9,37:1 |
  | comentário `#7A7E85` | 4,27:1 |
  | docstring `#5F826B` | 4,06:1 |
  | `self` `#94558D` | 3,27:1 |
  | argumento nomeado `#AA4926` | 3,06:1 |
  | número de linha do PyCharm `#4B5059` | 2,15:1 |
  | número de linha ajustado `#61666E` | 3,01:1 |
  | número da linha atual `#A1A3AB` | 6,92:1 |
  | etiqueta `#6F737A` | 3,66:1 |

  - O número de linha passou de `#4B5059` para `#61666E` (D-1). É o mínimo para 3:1 na mesma matiz.
  - Com Aumentar contraste, número de linha e etiqueta usam `#A1A3AB`.
  - No claro, o número de linha `#AEB3C2` dá 2,09:1 e foi para `#9094A4` (3,02:1).
- **Linha atual.** A linha do cursor é realçada (`#1F2024`) só sem seleção, e o número dela fica mais claro.
- **Realce.** `PythonHighlighter` recolore só o parágrafo editado. Se houver aspas triplas, recolore tudo.
  - Lê string e comentário numa passada, então `#` dentro de string continua string.
  - Dá cor própria a `self`, decorador, builtin e argumento nomeado. CAIXA_ALTA fica sem cor, como no PyCharm.
  - O passo gravado entra no fim (`IDEEditorContainerView.carregar`) sem mover o cursor nem entrar no ⌘Z. Uma troca inteira (Limpar) zera o histórico.
  - Um bug real apareceu nos testes: a `String` de `NSTextView.string` é viva. O tamanho agora é lido antes de mutar.

### PO-4 (P0-9): rodapé do editor

- O rodapé mostra `linha:coluna` (grafemas, tab até a parada), o separador (`LF`, ou o do arquivo aberto), a codificação, `4 espaços` e o Python do motor (`setup.check`, com o caminho no tooltip).
- O estado salvo é "não salvo" (aviso) ou "salvo às hh:mm" (ok, com o caminho no detalhe). Ele vem de `AppState.codigoSalvo`, que `saveCode` preenche.
- Sai o "Código sincronizado" fixo. Na coluna estreita ficam só a posição e o estado.
- Cada item tem rótulo falado próprio ("Linha 1, coluna 1", "Separador de linha LF"…).

### PO-5 (P1-1/P1-2 + layout)

- **Motor:** `workspace.tree`, `workspace.read` e `workspace.write` (`services/workspace.py`, fila rápida).
  - Mostra só `pages/`, `locators/` e `flows/` (D-4).
  - Travas SEC-5: caminho relativo sem `..`, nenhum link simbólico em nenhum nível, extensões de texto, até 1 MB.
  - A leitura devolve o texto em LF, com separador, BOM e somente leitura (não UTF-8) a parte. A gravação devolve tudo como era (T4).
  - `PROTOCOLO_RPC.md` ganhou uma seção nova, e `make fixtures` foi rodado.
- **Front, layout (D-5):** faixa de tool windows de 32 pt (Projeto; Hierarquia alterna o inspector existente), painel Projeto, editor ao centro. O espelho e o inspector ficam onde estão. Sem vidro.
- **Árvore:**
  - raiz com nome e caminho;
  - Localizar Arquivo Aberto, Expandir e Recolher Tudo (também ⌘+ e ⌘- com foco na árvore), ⋮ (Atualizar, Revelar no Finder) e Ocultar;
  - speed search: digitar abre o campo e realça; ↑↓ passam entre os que casam; ⎋ fecha;
  - ↩ ou duplo clique abre; ← e → recolhem e expandem.
- **Arquivos abertos:**
  - Abrem em abas com ×. `pages/<chave>.py` e `locators/<chave>.py` da sessão levam ao editor do Page Object.
  - Salvar grava pelo motor. Arquivo não UTF-8 mostra cadeado e não é editável.
- **Painel:**
  - A largura fica em `@SceneStorage("larguraProjeto")`, entre 160 e 360 pt.
  - Com menos de 640 pt na área, o painel some. A faixa avisa "sem espaço".
- **Editor vazio:** dicas com os atalhos REAIS, lidos do registro de comandos: ⇧⌘P, ⌘E, ⌘S, e "Mostrar ou Ocultar Projeto" pela paleta.
- **Atalhos (D-2):** nenhum mudou. Na paleta entrou "Mostrar/Ocultar Projeto" sem atalho, porque o ⌘1 do PyCharm já é Page Objects.

## Como validar no app (depois do `make update-native`)

1. Abra o Mo baile (nativo) › Page Objects e grave um passo, ou cole código num editor.
2. Monte o T1 no pasteboard (uma linha de shell, sem quebra no fim):
   ```bash
   printf 's = "reta" + '"'"'simples'"'"'\r\n# -- ... --- fim\r\na\tb\r\nx\xc2\xa0y\r\nz\xe2\x80\x8bw\r\n\xf0\x9f\x98\x80 \xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x92\xbb\r\nc\xc3\xa9 ce\xcc\x81\r\ndef f():\r\n    return 1' | pbcopy
   ```
3. Clique no editor `pages`, apague tudo (⌘A, ⌫) e cole com ⌘V.
   - O cabeçalho diz "9 linhas".
   - A linha 4 mostra `x[NBSP]y` e a linha 5 `z[ZWSP]w`.
   - O emoji 👩‍💻 aparece inteiro e `é` aparece igual nas duas formas.
4. Selecione a linha 4, copie com ⌘C e rode `pbpaste | xxd`: aparece `c2 a0`, não a etiqueta.
5. Digite `x = "a" -- ...` numa linha nova. Nada vira aspa curva nem travessão, e não aparece sublinhado vermelho. Tab no começo da linha insere 4 espaços.
6. Repita o passo 3 no editor `locators` e salve com ⌘S. O rodapé passa de "não salvo" para "salvo às hh:mm".
7. Rode `xxd ~/Documents/Mo\ baile/pages/<chave>.py`. O resultado tem que bater com a seção 5.3 da pesquisa: oito `0a`, nenhum `0d`, sem `ef bb bf`, sem `0a` final.
8. Rode `diff` com o `xxd` do PyCharm (oráculo da seção 5.1).
9. Confira o rodapé: `linha:coluna` muda ao mover o cursor, e `Python 3.x.y` aparece à direita.
10. Faixa à esquerda › Projeto: a árvore mostra `pages`, `locators` e `flows`. Digite "feat": `feature.py` é selecionado. ↩ abre.
11. Abra um arquivo de `flows/` e confira que ele abre numa aba nova.
12. Grave um arquivo com CRLF em `flows/`, abra pela árvore, edite e salve. Rode `xxd`: os `0d 0a` continuam (T4).
13. Ajustes › Geral › Cores do editor › Paleta do app: o editor volta às cores do tema.

## Testes (antes × depois)

| Suíte | Antes (056367d) | Depois (0309c0c) |
|---|---|---|
| `make test-swift` | 408 testes, 27 pulados, 0 falhas | 450 testes, 28 pulados, 0 falhas |
| `make check`, pytest do motor | 793 passaram (859 subtestes) | 811 passaram (874 subtestes) |
| `make check`, UI legada, QA (5 cenários), lint, segurança, fixtures | verdes | verdes |

- Testes novos em Swift:
  - `EditorCaracteresTests`: T1, T2, T3, desfazer, sem soft wrap, linha e coluna;
  - `CaracteresEspeciaisTests`: conjunto, exceções, largura, emoji, LSEP, cópia, VoiceOver;
  - `EditorEsquemaTests`: fonte, ligadura, altura, hexadecimais da tabela 2.5, contraste, realce ao digitar, 50 passos sem mover o cursor nem desfazer a pessoa;
  - `EditorStatusTests`;
  - `ProjectTreeTests`: contrato das fixtures, expandir e recolher, localizar, speed search, dicas e paleta;
  - um teste novo em `AccessibilityTests`: rótulos do rodapé.
- Testes novos em pytest:
  - `test_codegen_save_bytes.py`: bytes da seção 5.3, CRLF, BOM, NFD, U+2028; primeiro como caracterização (o CRLF falhava);
  - `test_workspace_rpc.py`: árvore, T4, BOM, Latin-1, travas de caminho e de link simbólico.
- O snapshot novo `16-page-objects-projeto-escuro` só roda com `MOBAILE_SNAPSHOT_DIR`.
- Nenhum snapshot existente mudou de propósito; `LayoutSnapshotTests`, `ToolbarLayoutTests` e `AccessibilityTests` passam.

## Riscos

- **Tamanho.** Foram cerca de 1.760 linhas de produção somadas (com comentários e 141 do motor), contra o teto de referência de ~600. O PO-5 é o maior (árvore, abas e RPC).
- **Bytes previstos.** Os bytes da seção 5.3 são previsão (R6). O oráculo PyCharm (passo 8) ainda não rodou.
- **Contraste do esquema.** Comentário (4,27:1), docstring, `self` e argumento nomeado ficam abaixo de 4,5:1, igual ao PyCharm.
- **Esquema claro.** Os valores do IntelliJ Light vieram de memória. Não li `expUI_lightScheme.xml`, porque o brief só autorizou ler as fontes em `/Applications`.
- **Realce com aspas triplas.** Com `"""` no arquivo, cada tecla recolore o texto inteiro. Arquivo grande com docstring pode pesar; não foi medido no Instruments.
- **Painel Projeto em 1280 pt.** Com espelho e inspector abertos, o painel não aparece: a área fica abaixo de 640 pt. A faixa avisa "sem espaço".
- **Integração.** `EngineSession.swift`, `AppState.swift`, `CommandRegistry.swift`, `server.py` e `contract.py` também são tocados pela trilha de desempenho. As mudanças daqui são aditivas e localizadas.
- **VoiceOver real** e o caminho de arrastar e soltar no editor não foram testados à mão.

## Decisões pendentes do dono

1. Esquema PyCharm como padrão também no claro (valores Inferidos) ou só no escuro.
2. Ajuste do número de linha `#4B5059` → `#61666E`.
3. ⌘S com uma aba de arquivo à frente: hoje continua "Salvar Page Object" (D-2), e o arquivo da aba se salva pelo botão do cabeçalho. Tornar o ⌘S contextual?
4. ⌘1 de novo em Page Objects alternar a árvore, como no PyCharm.
5. Versão: o editor muda de forma visível. Minor ou major?

O que ficou para depois está em `../pendentes/page-objects-proximos-passos.md`.

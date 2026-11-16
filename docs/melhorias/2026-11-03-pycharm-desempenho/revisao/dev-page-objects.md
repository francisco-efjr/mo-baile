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
- **Realce com aspas triplas.** Resolvido em parte pelo R-06 (ver "Correções da revisão"). Uma tecla que põe ou tira aspas num arquivo com `"""` ainda recolore até o fim do arquivo: cerca de 0,2 s em 1 MB.
- **Painel Projeto em 1280 pt.** Com espelho e inspector abertos, o painel não aparece: a área fica abaixo de 640 pt. A faixa avisa "sem espaço".
- **Integração.** `EngineSession.swift`, `AppState.swift`, `CommandRegistry.swift`, `server.py` e `contract.py` também são tocados pela trilha de desempenho. As mudanças daqui são aditivas e localizadas.
- **VoiceOver real** e o caminho de arrastar e soltar no editor não foram testados à mão.

## Decisões pendentes do dono

1. Esquema PyCharm como padrão também no claro (valores Inferidos) ou só no escuro.
2. Ajuste do número de linha `#4B5059` → `#61666E`.
3. ~~⌘S contextual~~: feito no R-05, a pedido do orquestrador. O atalho continua ⌘S e só o alvo muda conforme a aba.
4. ⌘1 de novo em Page Objects alternar a árvore, como no PyCharm.
5. Versão: o editor muda de forma visível. Minor ou major?

O que ficou para depois está em `../pendentes/page-objects-proximos-passos.md`.

## Correções da revisão (2026-11-04)

Revisão independente da branch com os achados R-01 a R-14 (relatório entregue ao orquestrador). Cada correção tem teste quando dá para testar sem janela.

### Commits

| Hash | IDs | O que mudou |
|---|---|---|
| `366d78a` | R-04 (motor), R-09, R-10, R-11, R-14 | **R-04:** `workspace.read` passa a devolver `mtime_ns`. `workspace.write` com `expected_mtime_ns` recusa com o erro tipado novo `file_changed` (`FileChangedError`) se o arquivo mudou ou sumiu.<br>**R-09:** o limite de 1 MB conta bytes codificados. `st_size` é conferido antes de ler, e a leitura é limitada.<br>**R-10:** `OSError` vira `invalid_input` com o motivo do sistema. Uma pasta sem leitura vem com `error` e não derruba a árvore.<br>**R-11:** `security.paths.write_file_atomic` grava com a pasta aberta em `O_NOFOLLOW`, um temporário `O_EXCL\|O_NOFOLLOW`, `fsync` e `os.replace`. Recusa link simbólico e arquivo sem permissão de escrita, e mantém o modo do arquivo. A leitura também usa `O_NOFOLLOW`.<br>**R-14:** o corte por profundidade marca `truncated`.<br>`PROTOCOLO_RPC.md` e as fixtures foram atualizados. |
| `dbb9bdf` | R-12 | Dentro de um `.app`, a fonte só é procurada em `Resources/fonts`; o caminho do repositório vale só fora do bundle. `verify_native_app.sh` agora falha se faltar `Resources/fonts/JetBrainsMono-Regular.ttf` ou `OFL.txt`. Só a checagem foi feita: o alvo não rodou.<br>Entrou também a dúvida da revisão sobre o ⌘+: na árvore, ⌘= e ⇧⌘+ expandem tudo. |
| `a0d2794` | R-06 | Realce gravado em ordem, um trecho por cor. Docstring marcada com um atributo próprio, para recolorir só ela. Layout não contíguo. Gutter só com o que está visível. Contador de linhas incremental. A linha atual redesenha só a antiga e a nova. Cópia nativa da string por `CFStringGetBytes`. |
| `f979d07` | R-01, R-02, R-03, R-04 (front), R-05, R-06, R-07, R-08, R-13 | **R-01:** as abas ficam em `AppState.arquivosAbertos` e `arquivoAtivo`.<br>**R-02:** o × numa aba suja pergunta "Salvar / Descartar Alterações / Cancelar", e a aba suja mostra "•" antes do nome.<br>**R-03:** cada aba tem o próprio editor; todos ficam vivos e só o da frente aparece.<br>**R-04:** um conflito abre o aviso "Recarregar do Disco / Sobrescrever / Cancelar".<br>**R-05:** ⌘S com uma aba de arquivo à frente salva essa aba ("Salvar <arquivo>"); com o Page Object da sessão, continua o `codegen.save`.<br>**R-06:** o rodapé lê o cursor num objeto próprio (`CursorDoEditor`); o `updateNSView` ganhou um caminho rápido e não reatribui mais a fonte.<br>**R-07:** atualização por id depois do `await`.<br>**R-08:** abrir confere de novo antes de criar a aba.<br>**R-13:** `NSCursor.pop()` no `onDisappear`. |

O último commit junta vários IDs porque as mudanças dividem os mesmos arquivos (`DualEditorPane`, `ArquivoAbertoPane`, `CodeEditorView`). Separar exigiria `git add -p`, que não está disponível aqui. `make check` e `make test-swift` rodaram verdes na árvore final antes dos commits `dbb9bdf`, `a0d2794` e `f979d07`, mas não em cada um isoladamente.

### R-06: medição (Medido)

- **Bench:** `EditorBenchTests` roda com `MOBAILE_BENCH=1` e imprime `BENCH`.
- **Cenário:**
  - `CodeEditorView` de verdade numa `NSWindow` de 900 × 700, com um pai que guarda o texto e mostra a posição do cursor;
  - arquivo `.py` sintético de 1.000.159 bytes, com docstring no topo;
  - 15 teclas no meio do arquivo, 15 movimentos de cursor e 5 aspas;
  - cada medida inclui uma volta do run loop e o `displayIfNeeded`.
- **Máquina:** o Mac do dono, numa execução (`swift test`, build debug).

| Métrica (mediana) | Antes (`67eb1ab`) | Depois (`f979d07`) |
|---|---|---|
| Carga inicial | 5.356 ms | 736 ms |
| Tecla comum | 7.075 ms (máx. 7.171) | 12,1 ms (máx. 29,9) |
| Movimento do cursor | 97,2 ms (máx. 101,5) | 1,7 ms (máx. 8,2) |
| Tecla de aspa (recolore até o fim) | 6.930 ms | 194 ms |

- **Antes:** o bench foi adaptado à API antiga (`onCursor` com o pai lendo a posição no próprio `body`, como o `PageObjectsView` da `0309c0c`). A versão rodada não foi commitada.
- **Custo restante da tecla:** cerca de 2,5 ms da cópia da string e o resto do `insertText` e do SwiftUI.
- **Aspa em arquivo com docstring:** passa de 16 ms porque recolore até o fim, no thread principal.

### Testes, antes × depois das correções

| Suíte | Antes (`67eb1ab`) | Depois (`f979d07`) |
|---|---|---|
| `make test-swift` | 450 testes, 28 pulados, 0 falhas | 461 testes, 29 pulados (o bench), 0 falhas |
| pytest do motor | 811 | 820 |
| QA, UI legada, lint, segurança, fixtures | verdes | verdes |

Testes novos:
- `ArquivosAbertosTests`: R-01, R-04, R-05, R-07, R-08, a docstring incremental e o contador de linhas;
- `TestRevisao` em `test_workspace_rpc.py`: R-04, R-09, R-10, R-11 (inclui o link simbólico plantado contra `write_file_atomic`) e R-14;
- `EditorEsquemaTests.testDentroDoAppSoProcuraNosRecursos`: R-12.

### O que não foi corrigido, e por quê

- **R-02 e R-03 sem teste automatizado.** O diálogo e a troca de editor por aba são UI de SwiftUI. Os testes cobrem a lógica por trás: `sujo`, `fecharArquivo` e as abas no `AppState`. Validar à mão: abrir dois arquivos, editar os dois, alternar e conferir o ⌘Z de cada um; fechar uma aba suja.
- **Desfazer depois de trocar de área.** O texto das abas sobrevive (R-01). Já o histórico de ⌘Z e a posição de rolagem se perdem quando a aba Page Objects é recriada, porque moram no `NSTextView`. Guardar isso fora da view seria uma mudança maior.
- **Aspa num arquivo grande com docstring (cerca de 0,2 s).** Ficou porque recolorir em segundo plano, por blocos visíveis, é uma mudança de arquitetura do realce.
- **Dúvida da revisão sobre `breakUndoCoalescing`.** Aplicado de forma preventiva antes de zerar o histórico na recriação do texto. O comportamento interno do AppKit não foi verificado.
- **Estado "Lendo a pasta…" no recarregamento.** O desvio menor da revisão (o recarregamento pelo `PageObjectsView` não liga `carregando`) ficou como está: a árvore antiga continua visível até chegar a nova.

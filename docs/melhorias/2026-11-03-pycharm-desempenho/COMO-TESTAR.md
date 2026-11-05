# Como testar a 3.17.1 (3.17.0 + correções da revisão de desempenho)

## Pré-requisitos

- macOS 26 com Xcode/Swift instalado.
- Python 3 com o `.venv` do projeto (`make setup`).
- Para o espelho: um simulador iOS ligado ou um aparelho Android pelo `adb`.
- Branch `melhoria/2026-11-03-pycharm-desempenho`.

## Testes automatizados

```bash
make check        # lint, segurança, motor (896), UI Tk, QA (5 cenários), fixtures
make test-swift   # 479 testes, 29 pulados, 0 falhas
```

Bancada do espelho, sem o app aberto:

```bash
.venv/bin/python tools/bench_stream.py               # fonte sintética
.venv/bin/python tools/bench_stream.py --fonte ios   # simulador ligado
```

Bench do editor (opcional):

```bash
MOBAILE_BENCH=1 make test-swift
```

## App instalado

O app precisa estar fechado.

```bash
make update-native
```

O resultado esperado é o "OK" do `verify-native`. Ele agora confere também
se a JetBrains Mono e o `OFL.txt` estão no bundle.

## Passos manuais

### Page Objects (PO-1 a PO-5)

O roteiro completo, com o texto T1 e o `xxd`, está em
`revisao/dev-page-objects.md`, na seção "Como validar no app".

1. Copie o T1 para a área de transferência com o `printf … | pbcopy` do
   roteiro. Na aba Page Objects, cole-o no editor `pages`. O resultado
   esperado:
   - o editor mostra 9 linhas;
   - o NBSP e o ZWSP aparecem marcados;
   - o emoji 👩‍💻 aparece inteiro.
2. Salve com ⌘S e confira o arquivo gravado:

   ```bash
   xxd ~/Documents/Mo\ baile/pages/<chave>.py
   ```

   O resultado esperado:
   - oito `0a`;
   - nenhum `0d`;
   - nenhum BOM;
   - nenhum `0a` no final.
3. Digite `"a" -- ...`. Nada pode virar aspa curva nem travessão.
4. Confira o rodapé. Ele mostra:
   - `linha:coluna`;
   - `LF`, `UTF-8` e `4 espaços`;
   - o Python do motor;
   - "salvo às hh:mm".
5. Abra a faixa à esquerda › Projeto. A árvore mostra `pages`, `locators` e
   `flows`. Para testar:
   - digitar filtra;
   - ↩ abre o arquivo numa aba.
6. Teste a aba de arquivo:
   1. Edite um arquivo.
   2. Troque para a aba Rede e volte. A edição continua lá.
   3. Clique no ×. Aparece Salvar / Descartar / Cancelar.
7. Teste o conflito:
   1. Abra um arquivo de `flows/` no Mo baile e no PyCharm.
   2. Salve no PyCharm.
   3. Salve no Mo baile. Aparece Recarregar / Sobrescrever.

### Desempenho (PERF-1 a PERF-5)

O roteiro está em `revisao/dev-desempenho.md`, na seção "Como validar no
app".

1. Ligue o espelho e cubra a janela por mais de 1 s. No Monitor de
   Atividade, o `simctl` ou o `screencap` para. Ao voltar, a tela atual
   aparece em menos de 0,5 s. Durante um flow, o espelho não pausa.
2. Com a tela do aparelho parada, as capturas ficam mais espaçadas depois de
   uns 2 s. Um toque mostra a mudança no tempo normal.
3. Ative o modo leve manualmente: ⇧⌘P › "Ativar Modo Leve". O resultado
   esperado:
   - o badge `leve` aparece;
   - o vidro fica sólido;
   - os painéis abrem sem animação de mola.
4. Ligue a Economia de Energia do macOS. O badge muda para `equilibrado`,
   com o motivo. Desligue: ele volta ao Completo em cerca de 60 s.
5. Abra Ajustes › Desempenho. A escolha continua lá depois de fechar e abrir
   o app.

### Nome do relatório (REL-1)

Na aba Relatório, audite e exporte. O HTML sai como
`relatorio_<projeto-da-spec>_<ios|android>_<dd-mm-aaaa>.html`, por exemplo
`relatorio_limite-de-conta_android_04-11-2026.html`. O `.md` e o `.tsv`
continuam com o nome `relatorio_auditoria.*`.

## O que rodou nesta sessão

**Verificado:**
- `make check` e `make test-swift`, com os números acima;
- as bancadas do espelho e do editor;
- o `make update-native`, se o "OK" estiver registrado no relatório final.

**Não verificado** (precisa do app aberto ou de outro hardware):
- dormir e acordar o Mac;
- troca de Space;
- Android real;
- o caminho real do `simctl --type=jpeg`;
- a CPU do app Swift;
- VoiceOver à mão;
- M1 de 8 GB e Intel.

## Como desfazer

```bash
git switch melhoria/2026-10-28-automacao-sync
```

Para reinstalar a 3.16.0, rode `make update-native` a partir dessa branch.

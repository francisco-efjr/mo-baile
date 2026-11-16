# Como testar o Liquid Glass (3.13.0)

## Pré-requisitos

- macOS 26 para ver o vidro. No macOS 14 e 15 o app roda com o recuo.
- Xcode 26 ou Command Line Tools com Swift 6.2 (SDK macOS 26.2).
- O `.venv` do projeto (`make setup`).
- Sem variáveis secretas.

## Comandos

```bash
make check          # esperado: 725 passed / 839 subtests; Tk 20; harness 11; QA 19/31/35/34/26; fixtures em dia
make test-swift     # esperado: 404 testes, 27 pulados, 0 falhas
```

Só os testes do vidro:

```bash
cd apps/MoBaile && swift test --filter GlassTests
```

Capturas (com a tela desbloqueada; as janelas piscam):

```bash
cd apps/MoBaile && MOBAILE_SNAPSHOT_DIR=/tmp/telas MOBAILE_CENA=11 swift test --filter WindowSnapshotTests/testCatalogoDeTelas
```

Com o app de testes inativo, o macOS tira o tom do vidro. O `catalogo.json`
lista essas imagens em `capturadasComAppInativo`.

Recuo do macOS 14 e 15 num Mac com 26 (aproximação, só no vidro do app):

```bash
cd apps/MoBaile && MOBAILE_SEM_VIDRO=1 swift run MoBaile
```

App instalado (feche com ⌘Q antes; fechar a janela não basta):

```bash
make update-native
```

## Passos manuais (no app instalado, macOS 26)

1. **Paleta de comandos.** ⇧⌘P abre um painel de vidro que deixa ver a janela
   por trás, sem borda nem sombra desenhadas pelo app. Esc fecha. Com Ajustes
   do Sistema › Acessibilidade › Tela › Reduzir movimento, o painel só aparece,
   sem se formar.
2. **Rodar.** Grave um passo com um aparelho conectado. O Rodar é uma cápsula
   de vidro tingida com o destaque, separada do grupo de botões da toolbar.
   Ao trocar para a janela de outro app, o Rodar fica neutro. Em Ajustes ›
   Paletas › Costes, o rótulo do Rodar é escuro sobre o dourado.
3. **Título.** "Início", "Page Objects" etc., na toolbar, aparecem sem cápsula
   em volta.
4. **Cápsula do Ambiente** (Início, canto superior direito). É vidro com tom
   leve, reage ao ponteiro e leva ao Ambiente.
5. **Rodapé da barra lateral.** Com muitos passos gravados, a lista rola por
   baixo do Ambiente com o desfoque do sistema, sem cortar seco.
6. **Splash** (Janela › Mostrar Splash). O trilho da barra de progresso é vidro
   transparente sobre o céu.
7. **Reduzir transparência** (Acessibilidade › Tela). A paleta de comandos e a
   cápsula ficam opacas, com borda.
8. **Aumentar contraste**, na Praia escura. O rótulo do Rodar e o texto do item
   escolhido na barra lateral passam a ser marinho sobre o rosa.

Critério de aceite: todos os itens acima, sem texto ilegível em nenhuma das 9
paletas.

## O que foi executado nesta sessão

- **Verificado:**
  - `make check` e `make test-swift`, com os números acima;
  - catálogo completo regenerado em `docs/design/telas`, com o app de testes
    inativo;
  - `make update-native`, com o resultado no relatório final da sessão.
- **Não verificado:**
  - macOS 14 e 15 reais;
  - a transição `materialize` gravada em vídeo;
  - VoiceOver na paleta de vidro;
  - o tom do vidro nas capturas (o app de testes não ficou ativo).

## Como desfazer

Nada foi commitado. Para descartar só a rodada, use
`git restore --source=HEAD -- <arquivos>` e apague os arquivos novos
(`Glass.swift`, `GlassTests.swift`, `docs/adr/0006-*`,
`docs/research/liquid-glass-macos26.md`, esta pasta e as cenas novas do
catálogo). Para reinstalar a 3.12.0, faça o checkout dela e rode
`make update-native`.

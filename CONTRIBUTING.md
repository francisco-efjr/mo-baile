# Como contribuir

Obrigado pelo interesse no Mo baile. Este guia cobre o que você precisa para
abrir um PR que passe na primeira revisão.

Ao participar, você concorda com o [Código de Conduta](CODE_OF_CONDUCT.md).
Vulnerabilidades **não** vão em issue pública: siga o [SECURITY.md](SECURITY.md).

## Antes de começar

- Procure uma issue existente. Para mudança grande (recurso novo, troca de
  contrato, redesenho), abra uma issue antes e combine o caminho.
- Leia [docs/ARQUITETURA.md](docs/ARQUITETURA.md). A regra central: **lógica nova
  vai para o motor Python (`engine/`), não para a interface.** O front SwiftUI
  desenha estado e traduz gesto em chamada JSON-RPC.
- O app Tk em `apps/tk-legacy/` está congelado: só correção de defeito, nada de
  recurso novo ([ADR 0005](docs/adr/0005-app-tk-congelado.md)).
- Confira as pendências em aberto em
  [docs/RODADA_2026-10-05_PENDENCIAS.md](docs/RODADA_2026-10-05_PENDENCIAS.md).

## Preparar o ambiente

Requisitos: macOS 14 ou superior, Python 3.10 ou superior e as Command Line
Tools do Xcode (`xcode-select --install`) para o front nativo.

```bash
git clone https://github.com/francisco-efjr/mo-baile.git
cd mo-baile
make setup        # cria .venv, instala motor e app Tk em modo editável e liga os hooks
source .venv/bin/activate
```

`make setup` também roda `make hooks`, que ativa o hook de `pre-push` do
versionamento. Se você clonou de outro jeito, rode `make hooks` uma vez.

## Rodar sem aparelho

Quase tudo dá para desenvolver e testar sem iPhone, Android, Xcode ou Android
SDK:

| Comando | O que exercita |
|---|---|
| `make test-engine` | Suíte do motor. Não precisa de aparelho nem de servidor gráfico. |
| `make qa` | Fluxos de ponta a ponta com `adb`, `xcrun` e WebDriverAgent falsos (`qa/fakebin/`, `qa/fake_wda.py`). Veja [qa/README.md](qa/README.md). |
| `make test-swift` | Suíte do front nativo, com fixtures geradas pelo motor. |
| `make run-engine` | Sobe o motor em modo JSON-RPC para depurar o contrato à mão. |

A aba **Relatório** (auditoria de tagueamento) funciona com um log exportado,
sem aparelho conectado.

Para testar com aparelho de verdade: Android precisa do `adb` (Android SDK
Platform Tools); iOS precisa do Xcode e de um WebDriverAgent em execução
(normalmente via Appium, `APPIUM_URL` no `.env`). Copie `.env.example` para
`.env` para ajustar.

## Portão de qualidade

Antes de **cada commit**:

```bash
make check        # versão, lint (ruff), bandit, suítes Python e fluxos de QA
make test-swift   # suíte do front nativo
```

Os dois precisam passar. O CI roda o mesmo e mais a matriz de Python.

Mudou o contrato RPC (campo, método, evento)? Rode `make fixtures`, faça o
commit das fixtures regeradas e atualize [docs/PROTOCOLO_RPC.md](docs/PROTOCOLO_RPC.md).
O CI reprova o PR com fixtures desatualizadas.

## Versionamento obrigatório

**Todo push leva uma versão nova** em SemVer. O hook de `pre-push` e o CI
barram o que não subir. Resumo:

```bash
python3 tools/version.py bump patch   # ou minor / major
# descreva a mudança na seção nova do CHANGELOG.md
make fixtures
```

Qual número subir, e por quê, está em [docs/VERSIONAMENTO.md](docs/VERSIONAMENTO.md).
Em PR de contribuidor externo, o mantenedor pode fazer o bump na hora do merge;
avise no PR se preferir assim.

## Mensagens de commit

Usamos [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/),
em português, no imperativo ou descritivo curto:

```
tipo(escopo): resumo em minúsculas

Corpo opcional explicando o porquê, não o como.
```

Tipos usados no histórico: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`,
`build`, `ci`, `chore` (inclusive `chore(release): X.Y.Z`). Escopos comuns:
`motor`, `janela`, `rede`, `relatorio`, `ui`, `a11y`, `qa`, `oss`.

Mudança incompatível: `feat!:` ou rodapé `BREAKING CHANGE:` (sobe MAIOR).

## Fluxo de PR

1. Faça um fork e crie uma branch a partir de `main` (`fix/espelho-trava`,
   `feat/rede-filtro`).
2. Um assunto por PR. PR pequeno é revisado de verdade.
3. Rode o portão (`make check` e `make test-swift`) e suba a versão.
4. Abra o PR preenchendo o template: o que mudou, por quê, como testou.
5. O CI precisa ficar verde. O dono do código ([CODEOWNERS](.github/CODEOWNERS))
   revisa.
6. Interface mudou? Anexe captura de tela clara e escura.

Dependência nova no motor precisa ser justificada no PR: ela vai para o Python
de quem usa o app, fora de qualquer ambiente virtual.

## Licença das contribuições

Ao enviar um PR, você concorda que sua contribuição é licenciada sob a
[licença MIT](LICENSE) do projeto.

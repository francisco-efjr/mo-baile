# Mo baile

Inspetor de UI, espelho ao vivo, interceptador de rede e gerador de Page
Objects para automação mobile em iOS e Android.

Feito para quem escreve teste automatizado e cansou de esperar dez segundos por
uma captura estática no Appium Inspector.

## O que ele faz

**Espelho ao vivo.** Streaming contínuo da tela do aparelho ou simulador, com
detecção de mudança: quadro idêntico não é redesenhado.

**Inspeção de hierarquia.** Árvore de acessibilidade normalizada entre Android
e iOS, com busca e painel de atributos.

**Toque repassado.** Clique no espelho vira toque no aparelho, na coordenada
certa.

**Geração de código.** Cada elemento inspecionado vira Page Object e ação
Appium, em três estratégias de localizador.

**Inspeção de rede.** Proxy local que registra o tráfego HTTP do aparelho, com
credenciais redigidas.

**Captura de tagueamento.** Eventos de Firebase Analytics em tempo real, via
logcat no Android e Unified Logging no iOS.

## Estrutura

```
engine/          motor Python headless, com fronteira JSON-RPC
apps/MoBaile/    front nativo SwiftUI (macOS 14+)
apps/tk-legacy/  interface Tkinter, em transição
docs/            arquitetura, contrato, segurança, QA
tools/           empacotamento e geração de fixtures
```

Toda a lógica vive no motor. A interface desenha estado e traduz gesto em
chamada. O porquê está em [docs/ARQUITETURA.md](docs/ARQUITETURA.md) e a
decisão está registrada em
[docs/adr/0001-motor-python-front-swift.md](docs/adr/0001-motor-python-front-swift.md).

## Começando

Requisitos: Python 3.10 ou superior; macOS com Xcode Command Line Tools para o
front nativo; Android SDK Platform Tools para Android; WebDriverAgent em
execução para iOS.

```bash
make setup        # ambiente virtual, motor e UI em modo editável
make check        # lint, varredura de segurança e suites
make run          # interface Python a partir do código-fonte
make install-app  # instala /Applications/Mo baile.app
```

O front nativo ainda não está terminado. Ele compila e abre, mas até `swift test`
passar na sua máquina, ele mostra o estado vazio e não reconhece dispositivo:

```bash
cd apps/MoBaile && swift build && swift test
make build-native   # instala como "Mo baile (nativo).app", app separado
```

O app separado é proposital. Instalar a build nativa por cima do app em uso já
derrubou o ambiente uma vez, e agora exige confirmação explícita.

## Configuração

Copie `.env.example` para `.env`. Todos os valores têm padrão seguro. Fora da
faixa válida, o motor avisa no log e usa o padrão, em vez de derrubar a
aplicação no import.

O ponto que merece atenção é `PROXY_HOST`. Mantenha em `127.0.0.1`. O alcance
ao aparelho vem do `adb reverse`, e escutar em `0.0.0.0` transforma a máquina
em proxy aberto para quem estiver na mesma rede.

## Comandos

| Comando | O que faz |
|---|---|
| `make setup` | Prepara o ambiente |
| `make check` | Portão antes do commit: lint, bandit e suites |
| `make test` | Suites Python |
| `make test-swift` | Suite do front nativo, no macOS |
| `make coverage` | Cobertura do motor |
| `make fixtures` | Regera as fixtures do contrato usadas pela suite Swift |
| `make run` | Interface Python a partir do código-fonte |
| `make run-engine` | Motor em modo JSON-RPC, útil para depurar o contrato |
| `make install-app` | Instala `/Applications/Mo baile.app` com a interface Python |
| `make build-native` | Empacota o front SwiftUI como app separado, após os testes passarem |

## Documentação

| Documento | Conteúdo |
|---|---|
| [ARQUITETURA.md](docs/ARQUITETURA.md) | Camadas, dependências e a regra de disciplina |
| [PROTOCOLO_RPC.md](docs/PROTOCOLO_RPC.md) | Contrato completo entre motor e front |
| [SEGURANCA.md](docs/SEGURANCA.md) | Auditoria, correções e pendências |
| [QA.md](docs/QA.md) | Estado da suite e roteiro de verificação manual |
| [ESTADO_ATUAL.md](docs/ESTADO_ATUAL.md) | O que funciona, o que depende de aparelho e o que é fachada |
| [design/](docs/design/) | Especificação visual e handoff |
| [research/](docs/research/) | Estudo do HTTP Toolkit e notas do interceptador |

## Contribuindo

Lógica nova vai para o motor, não para o widget.

Se a mesma regra aparecer em Python e em Swift, uma das duas está errada, e
ninguém vai descobrir qual até um cliente reclamar.

Mudou o contrato? Rode `make fixtures` e faça o commit do resultado. O CI
reprova o PR se as fixtures estiverem desatualizadas.

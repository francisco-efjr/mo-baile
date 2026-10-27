# Maestro como modelo de automação para o Mo baile, sempre local

Estudo de 23/10/2026. Pergunta: o que o Mo baile deve copiar do Maestro
(mobile.dev) para gravar e reproduzir testes, sem que nenhum dado saia da
máquina?

**Fontes:**
- Código do Maestro 2.11.0, em `~/Downloads/Maestro-main.zip`, baixado em 09/10/2026.
- Documentação oficial em docs.maestro.dev.
- O CLI 2.4.0 que vem dentro do Maestro Studio 0.9.1 instalado. Foi rodado só pelo lançador offline descrito na seção 3.
- Um emulador Android local (AVD Pixel_9, en-US, 1080x2424).

Afirmação sem fonte está marcada como **não verificado**.

## Resumo executivo

- **Adotar o modelo, não o binário.** O que dá estabilidade ao Maestro é a semântica, não o Kotlin:
  - flow declarativo em YAML;
  - seletor por texto ou id como regex;
  - procura do elemento com prazo (17 s, ou 7 s se `optional`);
  - espera até a hierarquia "assentar" depois de cada ação.

  O Mo baile já tem a árvore, os adapters e a gravação. Faltava esse modelo.
- **Protótipo entregue no motor.** `engine/src/mobaile/services/maestro_flow.py` lê o subconjunto do YAML do Maestro, roda com as mesmas esperas sobre adb e WDA, e exporta os passos gravados como flow.
  - O mesmo arquivo de exemplo passou **no runner do Mo baile e no Maestro**, no mesmo emulador.
  - Três métodos RPC novos: `flow.maestro_check`, `flow.maestro_export` e `flow.maestro_run`.
  - 37 testes novos. `make check` passa.
- **O Maestro não é offline por padrão, e as variáveis de ambiente não bastam.** O CLI chama a API da mobile.dev em quatro situações:
  - checagem de versão;
  - relatório de erro;
  - relatório de "profundidade de tela";
  - analytics (PostHog).

  Só a analytics tem opção para desligar de verdade. `MAESTRO_DISABLE_UPDATE_CHECK=true` **não impede** a consulta de versão; só esconde o aviso. Isso foi provado com uma armadilha local na seção 3.

  No MCP, `cheat_sheet` e `query_docs` chamam a internet com endereço fixo no código. O lançador `tools/maestro_offline/maestro-offline.sh` fecha tudo em três camadas. Com ele, a auditoria viu apenas conexões em `127.0.0.1`.
- **O gargalo do nosso runner é a leitura da árvore.** O mesmo flow de 13 comandos levou **21 s no Maestro e 69–70 s no Mo baile**.
  - Cada `uiautomator dump` custa **2,0 s** (média de 5 leituras, 31 KB).
  - A espera por tela assentada exige duas leituras iguais.
  - O Maestro lê a árvore por um servidor de instrumentação próprio, que fica de pé no aparelho.

  Esse é o próximo passo de maior retorno (seção 6).

## 1. O Maestro: o que é e como funciona

**O que é.** Framework de teste de UI para Android, iOS e web. Licença Apache 2.0. A versão mais recente é a 2.11.0, de 29/09/2026 ([CHANGELOG](https://github.com/mobile-dev-inc/maestro/blob/main/CHANGELOG.md), [LICENSE](https://github.com/mobile-dev-inc/maestro/blob/main/LICENSE)). O modelo de negócio é o Maestro Cloud, que roda os flows em aparelhos da mobile.dev, e o Maestro Studio, um app desktop Electron.

**Como fala com o aparelho.** Não usa Appium nem WebDriverAgent ([como o Maestro funciona](https://docs.maestro.dev/get-started/how-maestro-works)):

- **Android.** Um APK de instrumentação sobe um servidor gRPC (Netty), na porta 7001 do aparelho, sobre UiAutomator.
  - RPCs: `viewHierarchy`, `tap`, `inputText`, `isWindowUpdating`, `launchApp` e outros ([maestro_android.proto](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-proto/src/main/proto/maestro_android.proto)).
  - Desde a 2.5.0 conecta por socket do adb, sem `adb forward`.
- **iOS.** Um runner XCUITest com servidor HTTP em `127.0.0.1:22087` ([XCTestHTTPServer.swift](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-ios-xctest-runner/maestro-driver-iosUITests/Routes/XCTestHTTPServer.swift)).
  - Desde a 2.11.0, iPhone físico deixou de ser suportado.
- Nos dois casos, o driver fica de pé entre um comando e outro. Ler a árvore é uma chamada local barata, não um processo novo.

**Flow.** É um arquivo YAML com dois documentos: o cabeçalho (`appId`, `name`, `tags`, `env`, `onFlowStart`, `onFlowComplete`) e, depois de `---`, a lista de comandos ([YamlConfig.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-orchestra/src/main/java/maestro/orchestra/yaml/YamlConfig.kt)). Os comandos que importam aqui:

- `launchApp`, `tapOn`, `inputText`, `assertVisible` e `assertNotVisible`;
- `scroll`, `scrollUntilVisible` e `swipe`;
- `back`, `pressKey`, `eraseText` e `hideKeyboard`;
- `extendedWaitUntil` e `waitForAnimationToEnd`;
- `runFlow`, que aceita `when` com `visible`, `notVisible` ou `platform`;
- `retry`, com `maxRetries` de 0 a 3;
- `${VAR}` para variáveis, e JavaScript (GraalJS) em `runScript` e `${expr}`.

**Seletores.** Estão em [YamlElementSelector.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-orchestra/src/main/java/maestro/orchestra/yaml/YamlElementSelector.kt) e `Orchestra.buildFilter`:

- `text` e `id` são **regex de casamento inteiro**, sem distinguir maiúscula de minúscula. Regex inválida vira texto literal (`toRegexSafe`).
- `text` também casa com `hintText` e `accessibilityText`. `id` casa com ou sem o prefixo `pacote:id/`.
- Dos elementos que casam, fica **o mais fundo** (`deepestMatchingElement`). Depois entram os filtros relativos:
  - `below`, `above`, `leftOf` e `rightOf`, ordenados por distância;
  - `childOf`, `containsChild` e `containsDescendants`.
- Sem `index`, **clicável vem primeiro** (`clickableFirst`). Com `index`, a ordem é por posição, e índice negativo conta do fim.
- `point` aceita pixels ou porcentagem. Há também `enabled`, `checked`, `focused` e `selected`.

**Esperas automáticas.** Ver [Maestro.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-client/src/main/java/maestro/Maestro.kt), [ScreenshotUtils.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-client/src/main/java/maestro/utils/ScreenshotUtils.kt) e [Orchestra.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-orchestra/src/main/java/maestro/orchestra/Orchestra.kt):

- **Procurar elemento.** Lê a árvore em laço até o seletor casar, por até 17 s (`lookupTimeoutMs`), ou 7 s com `optional` (`optionalLookupTimeoutMs`).
- **Depois de cada ação.** `waitForAppToSettle` lê a árvore até duas leituras seguidas serem iguais, no máximo 10 vezes. A raiz também não pode ter `is-loading=true`.
  - No Android, antes disso, pergunta ao driver se a janela ainda está atualizando (`isWindowUpdating`).
- **`retryTapIfNoChange`.** Se a árvore não mudou depois do toque, compara capturas de tela, com limiar de 0,5%, e toca de novo.

**MCP (`maestro mcp`).** Servidor stdio dentro do próprio CLI ([McpServer.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/mcp/McpServer.kt), [README](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/mcp/README.md)):

- **2.11.0:**
  - locais: `list_devices`, `inspect_screen` (hierarquia em JSON compacto), `take_screenshot`, `run` (YAML inline, `files` ou `dir`), `cheat_sheet` e `open_maestro_viewer`;
  - de nuvem: `list_cloud_devices`, `run_on_cloud`, `get_cloud_run_status` e `describe_cloud_run`.
- **2.4.0, a que vem no Studio:**
  - ações por comando: `list_devices`, `start_device`, `launch_app`, `take_screenshot`, `tap_on`, `input_text`, `back` e `stop_app`;
  - flows: `run_flow`, `run_flow_files` e `check_flow_syntax`;
  - consulta: `inspect_view_hierarchy`, `cheat_sheet` e `query_docs`.
  - Lista obtida com `tools/list` pelo lançador offline.
- O agente segue o ciclo listar aparelho, inspecionar a tela, rodar YAML pequeno e juntar num flow. A instrução embutida diz para usar `cheat_sheet` antes de escrever comandos desconhecidos.

## 2. O que o Mo baile já tinha

| Peça | Onde | Como funciona hoje |
|---|---|---|
| Gravação | `services/codegen.py`, `rpc/server.py` (`codegen.record`, escuta passiva) | Cada toque vira `AutomationStep` com nome, classe e localizador escolhido por `rank_locators`: id > accessibility > texto > xpath > posição, com conferência de unicidade na tela. É **melhor** que o Maestro Studio nessa parte. |
| Page Object | `codegen.py` | Gera Python/Appium com `wait_to_be_visible` e 2 tentativas de clique. Esse é o produto entregue a quem automatiza. |
| Reprodução | `services/flows.py` (`.flow_runner.py`) | Gera um script Python que **toca na coordenada gravada**, com `sleep` fixo de 0,8 s e 1 s entre passos. Não procura o elemento, não espera a tela e não tem asserção. Quebra com qualquer mudança de layout ou de tempo. |
| Árvore | `services/hierarchy.py`, `adb.get_ui_hierarchy`, `ios_wda.get_ui_hierarchy` | `uiautomator dump` + `cat` (cerca de 2 s), com Appium como segunda tentativa no Android 14+; `/source` do WDA no iOS. |
| Entrada | `adapters/adb.py`, `adapters/ios_wda.py` | Toque, texto (com escape para o shell do aparelho) e tecla. Não havia deslize, abrir/parar app nem limpar dados. |
| Appium | `adapters/appium.py` | Sobe o servidor e cuida de sessão UiAutomator2/WDA, para leitura da árvore. |

## 3. Rede: o que o Maestro manda para fora e como fechar

### 3.1 O que sai, pelo código

| Chamada | Para onde | Quando | Desliga? |
|---|---|---|---|
| Analytics (PostHog) | `us.i.posthog.com` | Cada comando, teste e workspace. Leva UUID, versões de SO, Java, Xcode e Flutter, e a linha de comando sanitizada. Depois do login, também e-mail e organização ([Analytics.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/analytics/Analytics.kt)). | Sim: `MAESTRO_CLI_NO_ANALYTICS` com qualquer valor. Na primeira execução, grava `enabled: false` em `analytics.json`. |
| Versão nova | `api.copilot.mobile.dev/v2/maestro/version` | **Toda** execução: `Updates.fetchUpdatesAsync()` em `App.kt` ([Updates.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/update/Updates.kt)). | **Não.** `MAESTRO_DISABLE_UPDATE_CHECK=true` só impede ler a resposta e mostrar o aviso. |
| Relatório de erro | `api.copilot.mobile.dev/maestro/error` | Exceção não tratada no CLI. Manda a exceção e a linha de comando, com o valor de `-e` em hash ([ErrorReporter.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/util/ErrorReporter.kt)). | **Não há opção.** |
| Profundidade de tela | `api.copilot.mobile.dev/maestro/screen` | Fim de cada sessão com aparelho ([ScreenReporter.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/util/ScreenReporter.kt), `MaestroSessionManager`). | **Não há opção.** |
| `cheat_sheet` / `query_docs` (MCP) | `api.copilot.mobile.dev/v2/bot/...`, com endereço fixo no código | Quando o agente chama a ferramenta ([CheatSheetTool.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/mcp/tools/CheatSheetTool.kt)). | Não; a variável de API não afeta essa chamada. |
| Nuvem e IA | `api.copilot.mobile.dev` | `maestro cloud` / `login`, as ferramentas MCP de nuvem, `assertWithAI`, `extractTextWithAI`, `--analyze`. | Basta não usar. Exigem `maestro login` ou `MAESTRO_CLOUD_API_KEY`. |
| Relatório HTML | `cdn.tailwindcss.com`, `cdn.jsdelivr.net` | Ao **abrir** o HTML de `--format html` no navegador ([HtmlTestSuiteReporter.kt](https://github.com/mobile-dev-inc/maestro/blob/main/maestro-cli/src/main/java/maestro/cli/report/HtmlTestSuiteReporter.kt)). | Usar `--format junit`. |
| Maestro Studio (app) | GitHub `mobile-dev-inc/maestro-studio` | O `app-update.yml` do bundle configura atualização automática (electron-updater). | **Não auditado.** Não usar com dado sensível sem firewall. |

Nesta máquina existe `~/.mobiledev/authtoken`, de um login antigo no Studio. O
CLI lê esse arquivo para identificar o usuário na analytics e para as
ferramentas de nuvem. O lançador não apaga o arquivo; ele impede o envio.

### 3.2 O lançador offline

`tools/maestro_offline/maestro-offline.sh` recebe os argumentos do `maestro` e
falha fechado:

1. **Variáveis de ambiente:**
   - `MAESTRO_CLI_NO_ANALYTICS=1`;
   - `MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true`;
   - `MAESTRO_DISABLE_UPDATE_CHECK=true`;
   - `XDG_STATE_HOME` apontando para uma pasta própria, para não misturar estado com o Studio;
   - `MAESTRO_CLOUD_API_KEY` e `MAESTRO_CLI_AI_KEY` removidas.
2. **API redirecionada.** `MAESTRO_API_URL` e `MAESTRO_CLOUD_API_URL` apontam para `127.0.0.1:9`, onde nada escuta. Isso cobre o que não tem opção de desligar: versão, erro e profundidade de tela.
3. **`sandbox-exec`** com `deny network-outbound`, liberando apenas `localhost` e socket unix. Cobre o que tem endereço fixo no código (`cheat_sheet`, `query_docs`) e o que ainda não se conhece.
   - Sem `sandbox-exec`, o script recusa rodar.
   - A JVM precisa de `-Djava.net.preferIPv4Stack=true`. Sem isso, ela conecta em `::ffff:127.0.0.1`, que o filtro `localhost` do sandbox não reconhece, e o Maestro nem acha o servidor do adb. O script já passa a opção.
4. **Comandos recusados** antes de rodar: `cloud`, `login`, `logout`, `record`, `--analyze`, `--api-key` e `--api-url`.

O script acha o Maestro nesta ordem: `MAESTRO_BIN`, `maestro` no PATH ou o
CLI de dentro do Maestro Studio (`studio-server.jar` + JVM 17 embutida). Nesta
máquina, não há CLI instalado à parte: o lançador usa o do Studio, sem baixar
nada.

### 3.3 Prova de que nada saiu

`python3 tools/maestro_offline/auditar.py --flow <flow> --device <id>` faz o
seguinte:

- sobe uma armadilha HTTP em `127.0.0.1`, para onde vai a API da mobile.dev;
- abre o `maestro mcp`, lista as ferramentas e chama `list_devices`, `cheat_sheet`, `query_docs` e o flow;
- registra o `lsof` do processo a cada 200 ms.

Resultado em 23/10/2026, CLI 2.4.0, emulador Pixel_9:

| Verificação | Resultado |
|---|---|
| Pontas remotas vistas no `lsof` (MCP e `maestro test`) | só `127.0.0.1`; nenhuma conexão não local (129 amostras no `test`) |
| Armadilha (API da mobile.dev) | `GET /v2/maestro/version`, **com** `MAESTRO_DISABLE_UPDATE_CHECK=true`: a consulta sai mesmo assim |
| `cheat_sheet` | `Failed to get cheat sheet: Operation not permitted` (barrado pelo sandbox) |
| `query_docs` | `Failed to query docs: Operation not permitted` |
| `analytics.json` criado | `"enabled": false` |
| Flow de exemplo pelo `run_flow` do MCP | `success: true`, 14 comandos |

Observação: a resposta do `run_flow` devolve ao agente variáveis de ambiente
do processo. Na execução apareceram as `MAESTRO_*` do lançador. Segredo não
deve ir em variável de ambiente de quem roda o MCP.

## 4. Comparação

| Aspecto | Maestro | Mo baile antes | Mo baile com o protótipo |
|---|---|---|---|
| Formato do teste | YAML declarativo | Page Object Python (entregável) + script de coordenadas (reprodução) | YAML do Maestro como formato de reprodução; Page Object segue como entregável |
| Localizar elemento | Regex de texto/id, mais fundo, relativos, clicável primeiro | Ranking com unicidade na gravação; coordenada na reprodução | Mesma seleção do Maestro na reprodução; ranking da gravação vira o seletor exportado |
| Espera | Procura até 17/7 s; tela assentada após cada ação | `sleep` fixo | Igual ao Maestro (leituras da árvore) |
| Asserção | `assertVisible`, `assertNotVisible`, `extendedWaitUntil` | Nenhuma | As três |
| Composição | `runFlow` (com `when`), `retry`, hooks | Nenhuma | `runFlow` (arquivo ou bloco, `when`), `retry`, `onFlowStart`/`onFlowComplete` |
| Dado sensível | `inputText` literal no YAML ou `${VAR}` | Texto fica só em memória e nunca vai a log | Exportação sempre com `${VAR}`; valor só no `env`; log mascara |
| Leitura da árvore | Servidor de instrumentação próprio, rápido | `uiautomator dump`, cerca de 2 s | Igual a antes: **é o gargalo** |
| Rede | Analytics, versão, erro e tela por padrão | Nenhuma | Nenhuma (o runner não abre socket) |
| Agente / MCP | `maestro mcp` | — | Agente `maestro-automacao` sobre o MCP offline + RPC `flow.maestro_*` |
| iOS físico | Não (2.11.0) | WDA, se disponível | WDA, se disponível |

**Medição no mesmo flow** (`tools/maestro_offline/exemplos/configuracoes_android.yaml`, 13 comandos, emulador Pixel_9):

| Runner | Resultado | Tempo |
|---|---|---|
| Maestro 2.4.0 (`maestro test`, offline) | passou | 21 s |
| Maestro 2.4.0 (MCP `run_flow`, offline) | passou | não medido à parte |
| Mo baile (`rodar_flow.py`) | passou | 69–70 s |
| `uiautomator dump` sozinho | — | 2,0 s por leitura (5 leituras) |

## 5. Recomendação e o que já foi feito

**Adotar o formato e a semântica do Maestro como o formato de reprodução do
Mo baile.** Manter o Page Object Python como entregável. Não embutir o Maestro
no app: seriam JVM e drivers de terceiros, mais a telemetria acima, que precisa
ser contida. Usar o Maestro apenas como referência e como segunda opinião, via
lançador offline.

Entregue nesta rodada:

- **`engine/src/mobaile/services/maestro_flow.py`**, módulo sem I/O próprio:
  - `parse_flow`/`load_flow`: lê o subconjunto e **recusa com motivo** o que não suporta, sem ignorar nada em silêncio:
    - JavaScript, IA/nuvem, web;
    - propriedade desconhecida;
    - variável sem valor.
  - `select_elements`: a receita de seleção do `buildFilter`.
  - `FlowRunner`: as esperas do Maestro, com relógio injetável; cancelamento entre passos; log com texto digitado mascarado.
  - `export_steps`: passos gravados viram YAML.
    - O localizador do ranking vira `id` ou `text`, com o texto escapado como regex literal.
    - Coordenada fica como último recurso.
    - Texto digitado vira `${VARIAVEL}`.
- **`engine/src/mobaile/adapters/flow_devices.py`**, que implementa o `FlowDevice` (novo protocolo em `ports`):
  - Android: adb com `monkey`, `am force-stop`, `pm clear`, `input swipe`, e `appId` validado contra injeção no shell.
  - iOS: WDA para toque, texto, tecla e deslize; `simctl` para abrir e parar.
- **RPC:** `flow.maestro_check`, `flow.maestro_export` (com `save`, em `~/Documents/Mo baile/flows/`) e `flow.maestro_run`.
  - O `run` divide trava, `flow.stop`, `flow.log` e `flow.finished` com o `flow.run` atual. A interface não precisa de nada novo para acompanhar.
  - Documentado em `docs/PROTOCOLO_RPC.md`.
- **PyYAML** como extra opcional `maestro` (e em `dev`). Sem ele, só esses métodos recusam, com a instrução de instalação; o motor sobe igual. O Python que o app usa (`/usr/local/bin/python3`) já tem o PyYAML 6.0.3.
- **Testes:** `test_maestro_flow.py` (33) e `test_maestro_flow_rpc.py` (4, com servidor real e `adb` falso).
- **Ferramentas:**
  - `tools/maestro_offline/maestro-offline.sh` (lançador);
  - `auditar.py` (prova de rede);
  - `rodar_flow.py` (roda um YAML pelo motor, sem o app);
  - `exemplos/configuracoes_android.yaml`.
- **Agente** `.claude/agents/maestro-automacao.md`:
  - sobe o MCP offline pelo campo `mcpServers`;
  - não tem busca web;
  - tem `cheat_sheet`, `query_docs` e as ferramentas de nuvem bloqueadas;
  - leva uma referência local da sintaxe e a regra de validar o flow nos dois runners.

O que ficou de fora do protótipo, de propósito:

- **Interface.** O app ainda não tem botão para exportar ou rodar flow YAML. Os métodos estão no motor e no contrato.
- **Reprodução atual.** `flow.run` segue o script de coordenadas. Trocar a reprodução padrão pelo runner novo muda o comportamento visível e merece decisão e teste de interface.
- **Comandos não suportados:**
  - `longPressOn`, `doubleTapOn`, `copyTextFrom`;
  - `takeScreenshot`, `setLocation`, `openLink`, `addMedia`;
  - `startRecording`, `assertScreenshot`;
  - os seletores `enabled`, `checked`, `focused` e `selected`, porque o `UIElement` não guarda esses atributos.
- **Limitações do iOS.** `clearState` (o simctl não limpa dados de app instalado). `back` e `hideKeyboard` também não existem como tecla de sistema no iOS.

## 6. Próximos passos

| # | Ideia | Problema que resolve | Esforço | Risco | Pronto quando |
|---|---|---|---|---|---|
| 1 | Leitor de árvore persistente no Android: reaproveitar a sessão UiAutomator2 do Appium (`/source`), que já está no motor, ou um servidor de instrumentação próprio, como o do Maestro | Hoje são 2 s por leitura e cerca de 4 s por ação; flow 3x mais lento que o Maestro | M | Médio (APK no aparelho) | O flow de exemplo roda em menos de 30 s |
| 2 | Botões "Exportar flow" e "Rodar flow YAML" na aba de gravação | Usar o runner novo sem terminal | M | Baixo | Exportar → editar → rodar pelo app |
| 3 | Trocar `flow.run` pelo runner declarativo, gerando o YAML dos passos em memória | Reprodução por coordenada quebra com layout e tempo | P | Médio (muda o comportamento) | Os testes de `flow.run` passam com o runner novo |
| 4 | Guardar `enabled`/`checked`/`focused`/`selected` e `hint` no `UIElement` | Seletores de estado e paridade com o `text` do Maestro | P | Baixo | Seletores de estado aceitos |
| 5 | Comparar árvore normalizada (sem relógio nem barra de status) na espera | Tela com relógio nunca "assenta" | P | Baixo | Teste com relógio na status bar |
| 6 | `inspect_screen` compacto do Maestro (chaves curtas, padrões omitidos) num MCP do próprio Mo baile | Dar a árvore a agentes sem estourar contexto | M | Baixo | MCP do motor com `list_devices`, `inspect`, `run_flow` |

## Fontes

- Código do Maestro 2.11.0 (zip de 09/10/2026). Mesmos caminhos em [github.com/mobile-dev-inc/maestro](https://github.com/mobile-dev-inc/maestro):
  - `maestro-cli/src/main/java/maestro/cli/{App.kt, analytics/, update/Updates.kt, util/ErrorReporter.kt, util/ScreenReporter.kt, util/EnvUtils.kt, mcp/}`;
  - `maestro-orchestra/src/main/java/maestro/orchestra/Orchestra.kt`;
  - `maestro-client/src/main/java/maestro/{Maestro.kt, Filters.kt, utils/ScreenshotUtils.kt}`.
- Documentação: [MCP](https://docs.maestro.dev/getting-started/maestro-mcp), [variáveis de ambiente](https://docs.maestro.dev/maestro-cli/environment-variables), [seletores](https://docs.maestro.dev/api-reference/selectors), [condições](https://docs.maestro.dev/maestro-flows/flow-control-and-logic/conditions), [retry](https://docs.maestro.dev/api-reference/commands/retry), [como funciona](https://docs.maestro.dev/get-started/how-maestro-works).
- Execuções locais de 23/10/2026: `tools/maestro_offline/auditar.py` e `maestro-offline.sh test` sobre o Maestro Studio 0.9.1 (CLI 2.4.0), e `rodar_flow.py`, todos no AVD Pixel_9.

# Pontos de melhoria do Mo baile · 05/10/2026

Base: branch `etapa-1/motor-que-nao-trava`, versão 2.1.0, commit `4436082`.
Método: leitura do código e da documentação, reprodução em memória (sem aparelho,
sem escrita no repositório), cobertura do motor medida nesta análise e fontes
primárias com data de acesso. Ficam de fora, por estarem em execução em paralelo,
os itens de `docs/PROMPT_MELHORIAS_DEV_UX_QA.md` e do segundo prompt (logs sem
texto digitado, digitação iOS via WDA, persistência de sessão, execução por
localizador com espera, limites de memória do RPC, eventos estruturados de fluxo,
distribuição Swift+Python). Eles só aparecem abaixo quando há algo a acrescentar.

## Resumo executivo

A etapa 1 deixou o motor robusto, mas a etapa 0 ("chão firme") não fechou: 0.5
(exportação no motor), 0.6 (guardas de arquitetura), 0.7 (ADR de licença) e 0.8
(`ESTADO_ATUAL.md`) seguem abertos, e reapareceu a mesma classe de defeito
corrigida no analytics em 2.1.0 (o callback do proxy duplica a cada `proxy.start`,
reproduzido). Fora dos prompts em andamento, os riscos maiores são três: o motor
não registra nem desfaz o que muda no aparelho (proxy, debug do Firebase), então o
aparelho pode ficar sem internet; o app instalado por padrão (Tk) passa por fora
do contrato RPC e não recebe as correções da etapa 1; e no app Swift o log do
motor vai para um stderr que, aberto pelo Finder, não vai a lugar nenhum. No
fluxo gravar, gerar e executar há três verdades (passos do motor, editor, arquivo
salvo), e o arquivo salvo não é um módulo Python importável.

## Tabela priorizada

Esforço na escala do plano: P até 3 dias, M 1 a 2 semanas, G mais de 2 semanas.
Etapa conforme `docs/research/estudo-mercado/00-sintese-e-plano.md`.

| # | Prio | Ponto | Evidência no código | Referência de mercado | Impacto | Esf. | Etapa |
|---|---|---|---|---|---|---|---|
| 1 | P0 | Callback do proxy registrado a cada `proxy.start`: religar a captura multiplica cada linha da aba Rede e do HAR | `engine/src/mobaile/rpc/server.py:868`; `adapters/proxy.py:535-536` (append sem deduplicar; `stop` não limpa). Reproduzido: 3 `proxy.start` geram 3 `proxy.event` por requisição | Interna: mesmo defeito corrigido no analytics (CHANGELOG 2.1.0) | Dado duplicado na tela e na exportação | P | 0 (0.3) |
| 2 | P0 | Mudanças no aparelho não são registradas nem desfeitas no aparelho certo | `server.py:420-438` e `:876-881` (desfaz no aparelho atual, não no configurado); `:1519-1523` (idem no encerramento); `adapters/adb.py:379` e `:410` (`captive_portal_mode` apagado, não restaurado); `adb.py:417` (`is_proxy_configured` sem uso); `analytics_logcat.py:190-205` e `:311-336` (`stop` não faz `.none.` nem restaura `log.tag.*`) | [Proxyman Helper](https://docs.proxyman.com/basic-features/proxy-setting-tool) reverte o proxy em queda e restaura o anterior; [Firebase](https://firebase.google.com/docs/analytics/debugview): debug persiste até desligar e entra no export do BigQuery por padrão | Aparelho sem internet após trocar de aparelho ou desplugar; dado de teste no BigQuery do cliente | M | 0 (0.2, 0.3) |
| 3 | P0 | Dois produtos divergentes: o app instalado por padrão (Tk) importa adapters direto e ignora o contrato | `Makefile:74-75`; `apps/tk-legacy/mobaile_tk/main_window.py:13-21` e `:737` (estratégia `position`) contra `AppState.swift:24` (`auto`); `http_viewer.py:1307,1341` (porta 8082 fixa); HAR em dois fronts com versão "2.0" fixa (`http_viewer.py:1149`, `HARExporter.swift:74`) | - | Correções da etapa 1 (filas, cancelamento, época) não chegam a quem usa o app instalado; código gerado muda conforme o front | M | 0 (0.1, 0.5) |
| 4 | P0 | Log do motor invisível no app Swift e sem pacote de diagnóstico | `EngineClient.swift:158-167` (stderr do motor vai para o stderr do app); `server.py:1596-1602` (`basicConfig` só em stderr); nenhum `Logger`/`os_log` em `apps/MoBaile/Sources`; sem `faulthandler` no motor; queda na subida vira "encerrou inesperadamente (código N)" (`EngineError.swift`) | [Apple DTS](https://developer.apple.com/forums/thread/786673): "stderr goes nowhere" por padrão, use o log do sistema; [Android Studio](https://developer.android.com/studio/report-bugs): Help > Collect Logs and Diagnostic Data | Todo relato do time vira "travou", sem evidência; bloqueia distribuir | P-M | 1 (resíduo), 5.1 |
| 5 | P1 | Gravar, gerar e executar sem fonte única de verdade | Rodar usa os passos do motor (`server.py:1271`), Salvar grava o texto do editor (`:1022-1051`); sem apagar ou reordenar passo (`contract.py:123-126`, só gravar, listar, zerar e salvar); mesmo elemento gravado duas vezes vira `BOTAO_X` e `BOTAO_X_1` com o mesmo seletor (`codegen.py:122-127`); passo sem texto digita "Texto de Exemplo" (`flows.py:140`); arquivo salvo dá `IndentationError` (`codegen.py:236`, conferido com `ast.parse`) | [Playwright codegen](https://playwright.dev/docs/codegen): o gerador escreve o próprio teste que será executado | Teste passa no Mo baile e falha no repositório; um clique errado obriga regravar tudo | M | 3 (3.3, 3.4) |
| 6 | P1 | Diagnóstico de ambiente incompleto e sem exportação | `services/diagnostics.py:73-195` não confere Python e dependências do motor, drivers do Appium, iPhone físico, porta do proxy ocupada, scrcpy nem permissões do macOS; `adapters/appium.py:87-88` só procura o binário | [`appium driver doctor --json`](https://appium.io/docs/en/3.1/reference/cli/extensions/); [driver XCUITest](https://appium.github.io/appium-xcuitest-driver/latest/getting-started/device-setup/): Developer Mode e assinatura do WDA | Primeiro uso falha tarde, no `wda.start`, minutos depois | M | 0, 5.1 |
| 7 | P1 | Configuração documentada sem efeito | `README.md:70` manda copiar `.env`, mas nada carrega `.env` (`config.py:59-77` lê só `os.getenv`); `extraEnvironment` nunca é preenchido fora de teste (`EngineClient.swift:112`); padrões de um projeto específico: `onboarding_credito_objs` e `position` (`config.py:63-64`) | - | Pessoa muda a configuração e nada acontece; código gerado com nome de outro time | P | 0 |
| 8 | P1 | Privacidade fora da redação HTTP | Appium sobe em nível debug, anexando sem rotação em `~/Library/Logs/mobaile-appium.log` (`adapters/appium.py:125-137`); texto visível vira nome de variável e XPath (`codegen.py:95-127`, `:207-224`), levando nome, saldo ou CPF para o repositório de testes | Appium [`--log-filters`](https://appium.io/docs/en/latest/guides/log-filters/) e [`--log-level`](https://appium.io/docs/en/latest/reference/cli/server/) | Dado de cliente em log e em código versionado | P-M | 3 |
| 9 | P1 | Tempo até o espelho ao vivo | `EngineSession.swift:603-608` espera o dump de hierarquia (1 a 10 s no Android, segundo o plano) antes de `stream.start`, que está na fila `fast` (`contract.py:105`); nenhuma métrica de tempo até o primeiro quadro nem de toque até quadro | [VS Code](https://github.com/microsoft/vscode/wiki/Performance-Issues): "Startup Performance" e Process Explorer embutidos | Sensação de travamento ao conectar | P | 2 |
| 10 | P1 | `server.py` (1619 linhas) acumula regra de negócio | Escuta passiva (`:1053-1260`), escolha de backend de hierarquia (`:663-727`), fluxo (`:1264-1345`), codegen (`:954-1051`): cerca de 450 linhas de regra dentro da fronteira; 14 desvios por plataforma; `ports/` nunca importado (0% de cobertura); atributo criado fora do `__init__` (`:700`, `:717`) | Desenho LSP/DAP de servidor fino sobre serviços (estudo 03) | Cada recurso novo aumenta o arquivo e o risco; iPhone físico exige mexer em 14 pontos | M | 2 (antes de 2.5), 0.6 |
| 11 | P1 | Pirâmide de testes com buracos de integração | Motor testado só em Ubuntu (`.github/workflows/ci.yml:42`) e o produto só roda em macOS; Python 3.14 do `.venv` fora da matriz; cliente Swift nunca falou com o motor real no CI (fixtures; o harness usa um terceiro cliente, `qa/engine_client.py`); código gerado nunca executado contra WDA ou Appium falso; `pip_audit` não reprova (`ci.yml:79-80`); sem piso de cobertura (70%; `input_events` 38%, `ios_wda` 39%, `adb` 47%) | - | Regressão de macOS e de integração Swift-motor só aparece à mão | M | 0.6, contínuo |
| 12 | P1 | 14 `except Exception: pass` no motor, nos módulos menos cobertos | `adapters/input_events.py:115,206,212,235,277,324,362`; `ios_wda.py:41,52,85,99,118`; `scrcpy.py:141`; `docs/SEGURANCA.md:135` afirma "corrigido em todo o motor" | Ruff [`S110`](https://docs.astral.sh/ruff/rules/try-except-pass/) | Passo gravado errado sem aviso (escuta iOS, WDA) | P | 0.6 |
| 13 | P2 | Documentação que contradiz o código | `docs/ESTADO_ATUAL.md:3` parado em 07-08/09; `docs/PROMPT_MELHORIAS_DEV_UX_QA.md:25` afirma desligar o debug do Firebase; `docs/adr/` só tem o 0001 | - | Decisão tomada sobre premissa falsa | P | 0 (0.7, 0.8) |
| 14 | P2 | Distribuição: identidade, runtime e licença | Mesmo `CFBundleIdentifier` `com.qa.mobaile` nos dois instaladores (`tools/install_tk_app.sh:65`, `tools/package_macos_app.sh:82`); `requires-python >=3.10` (`engine/pyproject.toml:10`) e `ruff.toml:3`; `pymobiledevice3` opcional (`ios_device_log.py`) | [Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier): bundle ID identifica um app só; [Python 3.10 EOL 2026-10-01](https://devguide.python.org/versions/); [pymobiledevice3 é GPL-3.0](https://github.com/doronz88/pymobiledevice3) | Preferências e permissões cruzadas entre os dois apps; runtime sem correção de segurança; risco de licença ao embarcar | P-M | 0.7, 5.1 |
| 15 | P2 | Codegen com um alvo e um estilo da casa | Só Python com `self.locators['<chave>']` (`codegen.py:236-265`) | Appium Inspector gera 9 alvos por módulos em [`client-frameworks/`](https://github.com/appium/appium-inspector/tree/main/app/common/renderer/lib/client-frameworks) | Times Java, JS ou Robot descartam o que é gerado | M | 3 (3.4) |
| 16 | P2 | `EngineSession.swift` (1277 linhas) coordena mais de dez áreas | Um tipo para espelho, rede, analytics, fluxo, ambiente; 41 DTOs escritos à mão para 49 métodos e 11 notificações (`EngineDTO.swift`); consulta `engine.info` e `wda.status` a cada 5 s (`EngineSession.swift:408-419`) apesar de `docs/ARQUITETURA.md:64` dizer que a interface nunca faz polling | - | Mudança num domínio arrisca os outros; deriva de contrato | M | 2-3 (sobra do 1.3) |
| 17 | P2 | iPhone físico não é alvo de sessão | `server.py:440-449` lista só simulador ligado; capabilities sem `xcodeOrgId` nem `updatedWDABundleId` (`adapters/appium.py:170-186`) | [driver XCUITest](https://appium.github.io/appium-xcuitest-driver/latest/getting-started/device-setup/) | O público (banco, fintech) testa em aparelho real | G | 5 |

## Detalhamento: proposta e critério de pronto

Fato está na tabela. Daqui para baixo é recomendação.

1. **Proxy.** Registrar o callback uma vez no `__init__`, como já é feito no
   analytics (`server.py:203`). Pronto quando: teste de contrato com
   start, stop e start mostra uma notificação por requisição. Risco baixo.
2. **Diário do aparelho.** O motor grava em disco, antes de mudar, o valor
   anterior de cada propriedade tocada (`http_proxy`, `captive_portal_mode`,
   `debug.firebase.analytics.app`, `log.tag.*`), por serial. Desfaz no aparelho
   do diário em `proxy.stop`, na troca de aparelho, no encerramento e, se sobrar
   entrada, na próxima subida (usando `is_proxy_configured`). Pronto quando: teste
   com aparelho falso cobre trocar de aparelho com proxy ligado, matar o motor com
   SIGKILL e religar; `getprop debug.firebase.analytics.app` volta a `.none.`.
   Risco médio: o diário vira estado persistido e precisa de versão. Se o
   `adb reverse` sobrevive à desconexão não foi verificado.
3. **Um produto.** Congelar o Tk (só correção de segurança), publicar checklist
   de paridade e trocar o alvo de `make install-app` para o Swift quando ele
   fechar. Não portar o Tk para RPC (ver "O que não fazer"). Pronto quando:
   `/Applications/Mo baile.app` é o front Swift e o README diz a data de remoção
   do Tk. Risco: perder recurso que só existe no Tk; o checklist mitiga.
4. **Log local.** Motor: `RotatingFileHandler` em `~/Library/Logs/Mo baile/`
   (5 x 1 MB), `faulthandler` no mesmo diretório, id da requisição, fila, espera
   e duração em cada linha de método lento. Front: `os.Logger` com subsistema
   próprio e as últimas 50 linhas de stderr do motor anexadas à mensagem de
   queda. Menu "Exportar diagnóstico": zip com versões (app, motor, protocolo,
   Python, adb, Xcode, Appium e drivers), `diagnostics.check`, `stream.stats` e
   logs já redigidos. Nada sai da máquina. Pronto quando: motor com `import PIL`
   quebrado mostra a causa na janela, e o zip abre sem conter corpo HTTP nem XML.
5. **Fonte única.** O passo do motor é a verdade; o editor vira visão gerada
   dele, com edição por passo (renomear, apagar, mover, trocar localizador)
   exposta no contrato; elemento já declarado reaproveita o localizador; passo
   de digitação sem texto falha com motivo em vez de digitar "Texto de Exemplo";
   Salvar grava módulo completo (imports, classe, teste em ordem). Complementa o
   item de execução por localizador do segundo prompt. Pronto quando: todo
   arquivo salvo passa em `ast.parse` e roda contra o WDA falso do harness.
6. **Doutor.** Novas checagens com ação sugerida: Python e dependências do motor,
   `appium driver list --installed --json` e `appium driver doctor`, Developer
   Mode e assinatura do WDA para iPhone, porta 8082 livre, scrcpy, permissões do
   macOS. Botão "Copiar relatório". Pronto quando: cada checagem tem teste com
   ferramenta falsa e o card diz o comando que resolve.
7. **Configuração.** Ler `.env` no motor (parser próprio de poucas linhas, sem
   dependência nova) ou tirar a instrução do README; tela de Preferências no
   Swift que passa os valores em `extraEnvironment`; padrões neutros
   (`page_objects`, `auto`). Pronto quando: mudar `PROXY_PORT` pela tela muda a
   porta sem terminal.
8. **Privacidade.** Subir o Appium com `--log-level info` e `--log-filters`
   cobrindo `text`, `value` e os padrões de `security/redaction.py`, com rotação.
   No codegen, rebaixar localizador por texto que case com CPF, cartão, e-mail
   ou valor monetário e avisar no motivo do ranqueamento. Pronto quando: teste
   com texto "CPF 123.456.789-09" não gera nome nem XPath com o número.
9. **Espelho primeiro.** Em `activateDevice`, ligar o espelho logo após o
   tamanho e buscar a árvore em paralelo. Instrumentar tempo até o primeiro
   quadro e toque até quadro, expostos em `stream.stats` e no pacote do item 4.
   Pronto quando: o tempo até o primeiro quadro não depende do dump.
10. **Afinar o `server.py`.** Extrair, nesta ordem, `services/passive.py`,
    `services/hierarchy_source.py` e `services/session.py`; criar um alvo por
    plataforma que implemente `ports/` e substitua os 14 desvios. Sem
    reescrita de uma vez: os testes de despacho concorrente seguram o contrato.
    Pronto quando: `server.py` só valida, despacha e serializa (meta abaixo de
    700 linhas) e o import-linter do item 0.6 reprova regra na fronteira.
11. **Pirâmide.** Rodar a suíte do motor também em `macos-14` (uma versão de
    Python) e incluir 3.14 na matriz; teste de integração Swift que sobe o motor
    real com o `qa/fakebin` no PATH; executar o código gerado contra
    `qa/fake_wda.py`; `pip_audit` bloqueante com lista de exceções datada; piso
    de cobertura no valor atual (70%) para impedir queda.
12. **Exceções.** Ligar `S110` e `BLE001` no ruff para `engine/src` e trocar os
    14 pontos por log em `debug` com `exc_info`. Pronto quando: `make lint`
    reprova `except Exception: pass` novo.
13. **Documentos.** Reescrever `ESTADO_ATUAL.md` a partir do código (item 0.8),
    corrigir `SEGURANCA.md` §9 e o prompt, e escrever o ADR 0002 já com o
    ponto de licença do item 14.
14. **Distribuição.** Bundle ID distinto para o Tk (por exemplo
    `com.qa.mobaile.legacy`) enquanto os dois coexistirem; subir o mínimo para
    Python 3.12, o que também elimina a restrição que levou o plano a rodar o
    mitmproxy como processo filho; decidir no ADR 0002 se `pymobiledevice3`
    pode ser embarcado (implicação jurídica não verificada).
15. **Alvos de código.** Renderizar o mesmo passo por modelos (pytest, Java
    JUnit, WebdriverIO, Maestro YAML), com o estilo da casa como modelo
    configurável e não como regra do motor. Depende do item 5.
16. **Sessão Swift.** Separar em controladores por domínio sobre o mesmo
    cliente; gerar os DTOs a partir de `rpc/contract.py` (sobra do item 1.3);
    trocar o polling de 5 s por notificação de estado do motor.
17. **iPhone físico.** Depois do item 10: alvo iOS físico com capabilities de
    assinatura vindas das Preferências e checagem no doutor (item 6).

## Quick wins (menos de meio dia cada)

1. Item 1: mover o `add_event_callback` do proxy para o `__init__` e escrever o
   teste de start, stop e start.
2. Item 2, parte mínima: `setprop debug.firebase.analytics.app .none.` e
   restauração de `log.tag.FA`, `FA-SVC` e `FirebaseAnalytics` em `stop()`, com
   teste que confere a chamada no `calls.log` do adb falso.
3. Item 9: reordenar `activateDevice` (espelho antes, árvore em paralelo).
4. Item 4, parte mínima: `RotatingFileHandler` e `faulthandler` em `serve()`, e
   as últimas linhas do stderr do motor guardadas no `EngineClient` e anexadas
   ao erro de queda.
5. Item 12: ligar `S110` no ruff para `engine/src` e corrigir os 14 pontos.

## O que NÃO fazer agora

- **Portar o Tk para o contrato RPC.** São cerca de 5,6 mil linhas com data
  para sair. Congelar e aposentar custa menos e acaba com a divergência.
- **Sistema de plugins de terceiros.** O contrato v2 tem uma semana; abrir API
  agora congela o que ainda vai mudar nas etapas 2 a 4. O Flipper, que apostou
  em plugins com SDK no app, deixou de ser suportado no React Native 0.74
  ([blog](https://reactnative.dev/blog/2024/04/22/release-0.74)).
- **Telemetria remota antes do log local.** O estudo 03 propõe Sentry; sem o
  item 4 e sem política no ADR, ela só exporta o problema de privacidade.
- **Distribuir por Homebrew cask sem notarização.** O Homebrew 5.0 depreciou
  `--no-quarantine` e desliga em setembro de 2026 os casks do repositório
  oficial que falham no Gatekeeper ([brew.sh](https://brew.sh/2025/11/12/homebrew-5.0.0/)).
- **Servidor MCP antes da etapa 3.** O `mobile-mcp` (Apache-2.0, cerca de 8,7
  mil estrelas) já entrega toque, árvore e captura
  ([GitHub](https://github.com/mobile-next/mobile-mcp)). O valor do Mo baile
  para agentes é a correlação da etapa 4; expor hoje um executor sem fonte
  única (item 5) multiplica instabilidade.
- **Reescrever `server.py` de uma vez.** Extrair por serviço, com os testes de
  despacho concorrente como rede de proteção (item 10).
- **Trocar o proxy global do Android por VPN no aparelho agora.** É o caminho do
  HTTP Toolkit ([docs](https://httptoolkit.com/docs/guides/android/)) e elimina
  a classe do item 2, mas exige app Android próprio. Primeiro o diário do item 2.

## Medição feita nesta análise

Cobertura do motor em 05/10/2026, `pytest --cov` com o Python 3.14 do `.venv`,
saída gravada fora do repositório: 70% no total. Menores: `ios_device_log` 28%,
`input_events` 38%, `ios_wda` 39%, `adb` 47%, `hierarchy` 62%, `ports` 0%.
Reproduções em memória: duplicação do callback do proxy (item 1), seletor
duplicado para o mesmo elemento e `IndentationError` nos arquivos salvos
(item 5).

## Fontes (acesso em 05/10/2026)

- Proxyman, Proxy Helper Tool: https://docs.proxyman.com/basic-features/proxy-setting-tool
- Firebase, DebugView: https://firebase.google.com/docs/analytics/debugview
- Apple Developer Forums, stderr de app GUI (DTS): https://developer.apple.com/forums/thread/786673
- Android Studio, relatar bug e coletar diagnóstico: https://developer.android.com/studio/report-bugs
- Appium 3.1, CLI de extensões (`doctor`): https://appium.io/docs/en/3.1/reference/cli/extensions/
- Appium, argumentos do servidor: https://appium.io/docs/en/latest/reference/cli/server/
- Appium, filtros de log: https://appium.io/docs/en/latest/guides/log-filters/
- Driver XCUITest, aparelho real: https://appium.github.io/appium-xcuitest-driver/latest/getting-started/device-setup/
- Appium Inspector, gravador: https://appium.github.io/appium-inspector/latest/session-inspector/recorder/
- Appium Inspector, alvos de código: https://github.com/appium/appium-inspector/tree/main/app/common/renderer/lib/client-frameworks
- Playwright, codegen: https://playwright.dev/docs/codegen
- VS Code, diagnóstico de desempenho: https://github.com/microsoft/vscode/wiki/Performance-Issues
- Apple, `CFBundleIdentifier`: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier
- Python, estado das versões: https://devguide.python.org/versions/
- pymobiledevice3, licença: https://github.com/doronz88/pymobiledevice3
- Ruff, regra S110: https://docs.astral.sh/ruff/rules/try-except-pass/
- Homebrew 5.0.0: https://brew.sh/2025/11/12/homebrew-5.0.0/
- React Native 0.74 (Flipper): https://reactnative.dev/blog/2024/04/22/release-0.74
- mobile-mcp: https://github.com/mobile-next/mobile-mcp
- HTTP Toolkit, Android: https://httptoolkit.com/docs/guides/android/

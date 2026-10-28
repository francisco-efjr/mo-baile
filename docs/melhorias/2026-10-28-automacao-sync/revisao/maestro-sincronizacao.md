# Como o Maestro sincroniza com o aparelho (pesquisa 28/10/2026)

## Fonte e método

- **Versão analisada: CLI 2.11.0, não 2.4.0.** O Maestro Studio instalado é o 0.9.8 (Info.plist,
  12/10/2026). O `studio-server.jar` traz `version.properties` com `version=2.11.0` (build de
  09/10/2026). É esse jar que `tools/maestro_offline/maestro-offline.sh` roda
  (`-cp studio-server.jar maestro.cli.AppKt`). O doc `docs/research/maestro-modelo-de-automacao.md`
  e as instruções do agente ainda falam em "Studio 0.9.1 / CLI 2.4.0" e listam ferramentas MCP da
  2.4.0. Os dois estão desatualizados.
- Host: `javap -c -p -constants` do JBR do Android Studio sobre as classes extraídas do jar
  (`maestro/Maestro`, `maestro/orchestra/Orchestra`, `maestro/drivers/AndroidDriver`,
  `maestro/utils/ScreenshotUtils$Companion`, `maestro/utils/MaestroTimer`, `maestro/cli/mcp/*`).
- Aparelho: `dexdump -d` (build-tools 36.0.0) sobre o `maestro-server.apk` embutido no jar
  (instrumentação `dev.mobile.maestro.test`; o servidor gRPC fica em `classes5.dex`,
  `dev.mobile.maestro.Service` e `MaestroDriverService`).
- Não executei o `maestro`. As saídas desmontadas estão em `javap/` e em `dex/server/*.txt`.
- Medidas: só no `emulator-5554`, só leitura (screencap, dumpsys, uiautomator dump para /dev/tty).
  Não usei o ZY22L3CH3X.

## 1. `Maestro.tap(element, initialHierarchy, retryIfNoChange, waitUntilVisible, longPress, appId, tapRepeat, waitToSettleTimeoutMs)`

Verificado em `Maestro.tap-HgV9Ck0`:

1. **Assenta antes de tocar.** `waitForAppToSettle(initialHierarchy, appId, waitToSettleTimeoutMs)`.
   `initialHierarchy` é a hierarquia em que o `findElement` achou o alvo. O `Orchestra.tapOnElement`
   passa `config.appId`.
2. **Re-localiza o alvo na tela assentada.**
   - Caso normal: `ViewHierarchy.refreshElement(settled, element.treeNode)` e depois
     `toUiElementOrNull`. Se não achar, usa o elemento original. Log: "Tap aimed via settled
     hierarchy".
   - Se o settle devolveu `null` (não estabilizou) e o campo `recentScroll` está ligado (houve
     scroll/swipe antes): `refreshElementUntilStable`. Ele lê a hierarquia a cada 100 ms por até
     3 s (`ldc 3000000000L` em nanoTime, `delay(100)`) até os *bounds* do elemento saírem iguais em
     duas leituras seguidas. Logs: "Element is still moving (a -> b). Waiting for its position to
     settle." e "Element position did not stabilise within 3000ms. Tapping last known position".
   - Settle `null` sem scroll recente: usa a hierarquia de antes ("trusted pre-wait hierarchy").
3. **Toca no centro dos bounds re-localizados** com `performTap`. Ele escolhe por capacidade do
   driver:
   - `AndroidDriver.capabilities()` devolve `[FAST_HIERARCHY]`, então o Android usa
     `hierarchyBasedTap`;
   - o `IOSDriver` devolve `emptyList()`, então o iOS usa `screenshotBasedTap`.
4. **`hierarchyBasedTap`, depois do toque.**
   - `hierarchyBefore` é `initialHierarchy` ou uma leitura nova.
   - Repete `getNumberOfRetries(retryIfNoChange)` vezes, ou seja, 2 com `retryIfNoChange` e 1 sem.
     Em cada volta: toca, roda `waitForAppToSettle(null, null, waitToSettleTimeoutMs)` e, se a
     hierarquia mudou, loga "Something has changed in the UI judging by view hierarchy. Proceed.".
   - **Depois do toque não passa `appId`**: no Android o settle é só o de hierarquia (item 2), sem
     o `isWindowUpdating`.
5. **`screenshotBasedTap` (iOS).** Captura tela antes e depois e compara com
   `romankh3 ImageComparison.getDifferencePercent()`. Diferença acima de 0.005 (0,5%) conta como
   "mudou".
6. **`waitUntilVisible`.** Se a hierarquia ficou igual e o elemento não está visível, roda
   `waitUntilVisible` (10 voltas, `delay(1000)`) e toca de novo.
7. **Defaults (Verificado).**
   - `retryTapIfNoChange` e `waitUntilVisible` do YAML viram `false` quando ausentes
     (`YamlFluentCommand`, `ifnull` seguido de `iconst_0`).
   - `TapOnElementCommand.MAX_TIMEOUT_WAIT_TO_SETTLE_MS = 30000`.
   - `DEFAULT_REPEAT_DELAY = 100`.
8. **Toque por coordenada também espera.** `Orchestra.tapOnPoint`/`tapOnPointV2Command` chamam
   `Maestro.tap(x, y, ...)` e depois `performTap(..., initialHierarchy=null)`. O
   `hierarchyBasedTap` lê a hierarquia antes, toca e assenta depois. O que não existe é settle
   antes do toque, porque não há elemento.

## 2. Settle: hierarquia, screenshot ou os dois

- **`ScreenshotUtils.waitForAppToSettle(initial, driver, timeoutMs)` compara só a hierarquia.**
  - **Sem timeout:** `anterior = initial ?: leitura`. Faz 10 voltas (`bipush 10`). Em cada uma:
    lê, sai se `ViewHierarchy.equals(anterior, nova)` e se o atributo da raiz `is-loading` não é
    `true`; senão dorme 200 ms (`MaestroTimer.sleep(WAIT_TO_SETTLE, 200)`). Se esgotar, devolve
    `null`.
  - **Com `waitToSettleTimeoutMs`:** mesmo critério em laço **sem sleep**
    (`currentTimeMillis < deadline`, goto 37) até o prazo.
  - O primeiro par compara `initial` (a tela em que o alvo foi achado) com a leitura nova. Com
    `initial` dado, basta uma leitura igual a ele.
  - `is-loading` só aparece nessa classe. Nenhum driver mobile o preenche (Inferido: é da web).
- **`AndroidDriver.waitForAppToSettle(initial, appId, timeout)`.**
  - Com `appId`: `waitForWindowToSettle`. É um laço de **750 ms fixos** (`sipush 750`) chamando o
    gRPC `isWindowUpdating(appId)`. No aparelho isso é `UiDevice.waitForWindowUpdate(appId, 500)`,
    que bloqueia até 500 ms esperando evento de janela do pacote.
    - Se houve evento: roda o settle de hierarquia acima e continua o laço até os 750 ms.
    - Se não houve: dorme 50 ms.
    - No fim, se nada assentou, roda o settle de hierarquia default.
  - **Custo mínimo de ~750 ms por toque em elemento.**
  - Sem `appId`: vai direto ao settle de hierarquia.
- **Screenshot só em `waitForAnimationToEnd` e no toque do iOS.**
  - `Maestro.waitForAnimationToEnd(timeout)`: default 15000 ms (`ldc2_w 15000`). Chama
    `ScreenshotUtils.waitUntilScreenIsStatic(timeout, 0.005, driver)`.
  - Esse método tira duas capturas seguidas e passa quando a diferença é ≤ 0,5%. O laço é
    `MaestroTimer.retryUntilTrue` com `delay=null`, ou seja, **sem sleep** entre pares.

## 3. Lookup (`findElementWithTimeout` / `Orchestra.findElement`)

- `MaestroTimer.withTimeoutSuspend(timeout) { viewHierarchy(); filter(aggregate()).firstOrNull() }`.
  Usa só `yield()`, **sem sleep** (Verificado em `MaestroTimer.withTimeoutSuspend`). O ritmo é o
  custo de cada dump no aparelho, que já inclui o `waitForIdle(500)` (item 4).
- O prazo é `timeout ?: adjustedToLatestInteraction(optional ? 7000 : 17000)`.
  `adjustedToLatestInteraction(t) = max(0, t - (now - timeMsOfLastInteraction))`, ou seja, **o
  prazo conta a partir da última interação, não do início da busca** (Verificado em
  `Orchestra.adjustedToLatestInteraction` e no construtor, `ldc2_w 17000 / 7000`).
- `assertVisible` passa pelo mesmo `findElement` e não assenta antes.

## 4. Servidor Android (`dev.mobile.maestro`, gRPC na porta 7001)

- `MaestroDriverService.grpcServer`: `Configurator.setActionAcknowledgmentTimeout(0)`,
  `setWaitForIdleTimeout(0)` e `setWaitForSelectorTimeout(0)`. Isso desliga as esperas implícitas
  do UiAutomator.
- `Service.viewHierarchy` chama `refreshAccessibilityCache()` antes de cada dump:
  - `uiDevice.waitForIdle(500)` (`const-wide/16 500`);
  - `uiAutomation.setServiceInfo(null)`, que força o cache de acessibilidade a ser refeito.
  Depois vem `ViewHierarchy.dump`, que pega `UiDevice.getWindowRoots` por reflexão (todas as
  janelas) e inclui o nó de toast do `ToastAccessibilityListener`.
- `Service.isWindowUpdating` = `uiDevice.waitForWindowUpdate(appId, 500)`. É o único sinal de
  evento de acessibilidade usado na sincronização.
- **`setCompressedLayoutHierarchy`: não usado.** Só aparece dentro da própria biblioteca
  uiautomator (`UiDevice.setCompressedLayoutHeirarchy`) e não tem chamada no código
  `dev.mobile.maestro`.
- **Animações: não desliga.** Nenhuma chamada a `settings put` nem `*_animation_scale` no código do
  Maestro (host ou servidor). As strings `animator_duration_scale` etc. no dex são da biblioteca
  Espresso (`PerformExceptionHandler.getAnimatorDurationScale`, só leitura). No emulador as três
  escalas estão em 1.0.

## 5. `inputText`

- Host (`Maestro.inputText`): `driver.inputText(text)` e depois `waitForAppToSettle()` default
  (hierarquia). **Não confere foco nem teclado antes** (`isKeyboardVisible` não é chamado).
- Aparelho (`Service.inputText`): para cada caractere, `setText(c)` (um `pressKeyCode` por
  caractere) e `Thread.sleep(75)`. Texto não-ASCII vai por `inputUnicodeText` no host.

## 6. `launchApp`

- `Orchestra.launchAppCommand`, em ordem: `clearKeychain`, `clearAppState`, `setPermissions`
  (`all=allow` por default) e `Maestro.launchApp(appId, args, stopApp)`.
- `Maestro.launchApp` faz `driver.stopApp` e depois `driver.launchApp`.
- No aparelho: `getLaunchIntentForPackage` e `startActivity`, **sem espera nenhuma**
  (nem de activity em foco, nem de hierarquia do pacote).
- A espera fica para o `findElement` do comando seguinte (17 s contados da última interação).

## 7. MCP do 2.11.0 (`McpServerKt.runMaestroMcpServer`)

- Ferramentas registradas:
  - locais: `list_devices`, `take_screenshot`, `run`, `inspect_screen`;
  - rede: `cheat_sheet`;
  - visor local: `open_maestro_viewer`;
  - nuvem: `list_cloud_devices`, `run_on_cloud`, `get_cloud_run_status`, `describe_cloud_run`.
  - Não existem mais `tap_on`, `input_text`, `run_flow` nem `inspect_view_hierarchy`.
- `run` monta um `Orchestra` via `McpViewerOrchestra.create(maestro)`, com os defaults
  17000/7000 (máscara de default), e chama `Orchestra.runFlow`. **Cada comando do `run` tem as
  mesmas esperas do CLI.**
- `inspect_screen` faz **uma** leitura `Maestro.viewHierarchy()`, sem settle. Mesmo assim, no
  Android ela passa pelo `waitForIdle(500)` do servidor.

## 8. Tela intermediária estável (spinner, splash, carregamento)

- Não há tratamento específico.
  - Mobile: nada procura `ProgressBar`, `progress`, `loading` ou `busy`. O único gancho é a raiz
    `is-loading`, que nenhum driver mobile preenche.
  - O que protege o Maestro é estrutural:
    - (a) o toque em elemento só acontece depois que o `findElement` acha o alvo, e o alvo não
      existe na tela de carregamento;
    - (b) o toque é re-mirado na hierarquia assentada;
    - (c) cada dump espera 500 ms de ócio de acessibilidade no aparelho;
    - (d) a janela de 750 ms do `waitForWindowUpdate`.
- Na sequência do log (48005 → 6693 → 11887 ×3 → 46010) o Maestro **também** daria a tela 11887
  como assentada: duas leituras iguais, ou uma igual à `initial`. Um spinner indeterminado anima
  por desenho e não muda a árvore (Inferido: não gera `TYPE_WINDOW_CONTENT_CHANGED`, então o
  `waitForWindowUpdate` também não o pega).

## Medidas no emulator-5554 (rodadas de verdade, Settings em foco, 1080x2424)

| leitura | tempos (ms) | observação |
|---|---|---|
| `exec-out screencap -p` | 1773, 549, 676, 716, 687 | 204541 bytes |
| `exec-out screencap` (raw) | 1643, 1652, 1600 | 10471696 bytes |
| `shell "dumpsys window \| grep mCurrentFocus"` | 119, 100, 102, 105, 116 | `mCurrentFocus=Window{… com.android.settings/…Settings}` |
| `dumpsys activity activities \| grep -m1 mResumedActivity` | 120, 159, 117 | |
| `exec-out uiautomator dump /dev/tty` | 3317, 2520, 2174 | 30708 bytes |
| `dumpsys gfxinfo com.android.settings` | 211, 144, 153 | |
| `dumpsys SurfaceFlinger --latency <layer>` | 75, 64, 70 | só devolveu o período (16666666); sem linhas de quadro nesta imagem |

- `gfxinfo ... framestats` traz "Total frames rendered" por janela (375) e o `FrameCompleted` dos
  últimos 90 quadros.
- Em duas leituras com 2 s de intervalo e a tela parada, o total (375) e o último `FrameCompleted`
  (36189869099712) não mudaram. É um sinal plausível de "está desenhando", que pega spinner e
  animação que a árvore não mostra.
- Não medi o lado "animando": exigiria tocar no emulador.

## O que o Mo baile deveria copiar

1. **Assentar antes do toque e re-mirar.**
   - Antes de tocar, assentar comparando a leitura nova com a tela em que o alvo foi achado.
   - Re-achar o alvo nessa tela assentada (mesmo seletor) e tocar nos bounds novos.
   - Depois de scroll/swipe, exigir bounds iguais em duas leituras (100 ms, até 3 s).
2. **Contar o prazo de busca a partir da última interação** (`max(0, 17 s - desde_ultima_acao)`).
   Isso deixa o lookup tolerante a telas lentas sem somar prazos.
3. **Sinal de ócio do aparelho em toda leitura.**
   - O Maestro faz `waitForIdle(500)` no aparelho antes de cada dump.
   - No Appium/UiAutomator2 o equivalente é o setting `waitForIdleTimeout` (Inferido; não conferi
     o servidor do Appium). Hoje o Mo baile não sabe se o `/source` esperou.
   - Para o atalho "uma leitura basta", exigir uma segunda leitura igual quando o leitor não
     garante ócio.
4. **Sinal de janela atualizando.** Usar o equivalente ao `waitForWindowUpdate(pkg, 500)`: via
   Appium, o próprio settle repetido; via adb, `gfxinfo framestats` ou o contador de quadros. Uma
   leitura "igual" só deveria valer se nenhum quadro novo foi desenhado entre elas.
5. **Toque por `point`.** No Mo baile o `_r_tapOn` já assenta depois. Falta ler a tela antes, como
   o Maestro, para comparar e permitir `retryIfNoChange`.
6. **`launchApp` e `inputText`.**
   - O Maestro não espera. Fazer melhor que ele sai barato: depois de abrir, esperar
     `mCurrentFocus` do pacote (~100-160 ms por consulta medida).
   - Antes de digitar, conferir se há nó `focused=true` editável.

## Onde o Maestro também falharia

- Tela de carregamento estável por ≥ 2 leituras (o caso 11887 ×3). O settle do Maestro termina
  nela. Ele só não erra quando o próximo passo procura um elemento que não está nela.
- Asserção cujo seletor casa na tela intermediária ou anterior (o caso "Languages.*").
  `assertVisible` passa sem settle.
- `assertNotVisible` e `when: notVisible` avaliados durante o carregamento: falso positivo.
- Toque por coordenada logo depois de uma transição: ele toca sobre o que estiver na tela.
- `inputText` antes de o campo ter foco ou de o teclado subir. Não há checagem.
- Spinner indeterminado ou animação que só desenha: árvore igual, sem evento de janela. Só o
  `waitForAnimationToEnd` (screenshot, 0,5%) pegaria, e só se o flow o pedir.

# Como testar: automação no tempo do aparelho (3.16.0)

Branch `melhoria/2026-10-28-automacao-sync`. Só macOS. Python do `.venv` do projeto, Android SDK em `~/Library/Android/sdk`, Swift 6 para o front.

## Suíte

```bash
make check
```

Resultado esperado: motor com 793 aprovados; QA com 19, 31, 35, 34 e 26.

```bash
make test-swift
```

Resultado esperado: 408 testes, 27 pulados, 0 falhas.

Só os testes desta rodada:

```bash
cd engine && ../.venv/bin/python -m pytest tests/unit/test_maestro_flow.py -k Sincronia -v
```

## Medição no emulador

**Feche o app Mo baile antes.** Com ele aberto, o inspetor lê o mesmo emulador e pode abrir uma sessão do Appium nele. A instrumentação do UiAutomator2 ocupa o UiAutomation, e o dump falha, tanto no runner antigo quanto no novo. Para conferir se ela ficou no emulador:

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell dumpsys activity processes | grep ActiveInstrumentation
```

Se aparecer `io.appium.uiautomator2.server`, libere o emulador:

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell am force-stop io.appium.uiautomator2.server
```

Rode o flow de exemplo e veja a linha `sincronia:` de cada passo:

```bash
.venv/bin/python tools/maestro_offline/rodar_flow.py tools/maestro_offline/exemplos/configuracoes_android.yaml --device emulator-5554
```

Resultado esperado: `✔ Flow executado com sucesso.` e nenhuma linha "seguiu sem prontidao" na tela de Bateria.

## No moto g55 (aceite da proposta)

1. Abra o app, conecte o g55 e rode a gravação que falhava (Rodar Automação, ⌘R) 10 vezes seguidas.
2. No log de cada execução, veja:
   - `sincronia: … · indicador de carregamento sumiu…` quando houver spinner;
   - `a classe gravada apareceu sob o ponto…` nos passos por coordenada;
   - `aviso: sob o ponto …` quando a tela nunca chegou.
3. Se alguma execução falhar, a última linha do log diz onde ficaram as telas (`Telas lidas no flow guardadas em …/flow-rastro/<data>`). O `resumo.txt` lista cada tela com o tamanho e o segundo em que chegou: é ali que aparece a tela de 11887 B. **Os XMLs contêm o que estava na tela do app.** Não os anexe em lugar público.
4. Critério de aceite: 10 de 10 execuções passando, e nenhuma linha "tocando o ponto mesmo assim" num passo que deveria ter esperado.

## Para cada melhoria

| ID | Passo manual | Esperado |
|---|---|---|
| SYNC-1 | Rode qualquer flow | Uma linha `sincronia:` por passo, também no passo que falha |
| SYNC-1 | Rode um flow com um `assertVisible` que não existe | Pasta nova em `~/Library/Logs/Mo baile/flow-rastro/`, com arquivos `-rw-------` |
| SYNC-2 | Toque num botão que entra deslizando (bottom sheet) | O toque cai no botão parado. O log diz "o alvo andou; mirei de novo" |
| SYNC-3 | Grave um toque por posição e rode com a tela demorando a abrir | O toque só sai quando a tela gravada chega |
| SYNC-4 | Tela com spinner depois de um toque | O passo seguinte espera o spinner sumir, por até 5 s |
| SYNC-5 | Passo de digitação logo depois de abrir a busca | Digita depois do foco. Sem foco em 3 s, aparece um aviso e ele digita assim mesmo |
| SYNC-6 | `retry` com um passo que falha | Cada tentativa espera o prazo inteiro |

Para desligar o rastro: `MOBAILE_FLOW_TRACE=nunca`. Para gravá-lo sempre: `MOBAILE_FLOW_TRACE=sempre`.

## O que foi executado nesta sessão

- **Verificado:**
  - `make check` e `make test-swift` verdes;
  - os testes vermelhos antes da correção;
  - mutação de cada mudança;
  - 12 execuções do flow de exemplo no `emulator-5554`. Só as 6 primeiras valem: depois disso, o app aberto passou a disputar o UiAutomation.
- **Não verificado:**
  - o moto g55 (não usei o aparelho físico);
  - o XML real da tela de 11887 B;
  - o iOS.

## Como desfazer

```bash
git switch melhoria/2026-10-27-automacao
```

Ou reverta o commit da rodada com `git revert <commit>`.

# Como testar: Fase 2 da automação (3.17.0)

Branch `melhoria/2026-11-04-automacao-fase2`. Só macOS. Python do `.venv` do checkout principal, Android SDK em `~/Library/Android/sdk` e Swift 6.

## Suíte

```bash
cd engine && ../.venv/bin/python -m pytest
```

Resultado esperado: 818 aprovados. Rode no checkout principal, ou troque `../.venv` pelo caminho absoluto se estiver no worktree.

```bash
make test-swift
```

Resultado esperado: 409 testes, 27 pulados, 0 falhas.

## SYNC-9: abrir o app do zero

1. Ajustes (⌘,) › Geral › Ao rodar automação: ligue "Abrir o app do zero antes do primeiro passo".
2. Com o app gravado em qualquer tela (ou fechado), rode a automação (⌘R).
3. **Esperado:**
   - o log começa com `▶ [onFlowStart] abrir <pacote> do zero`, seguido de "o app abriu em X s" quando o launcher ainda estava em foco;
   - o passo 1 roda na tela inicial do app;
   - a contagem de passos não inclui a abertura do app.

## SYNC-8: âncora

1. Grave dois ou três passos num app Android (Gravar Passo).
2. Rode a automação.
3. **Esperado:** antes de cada passo gravado aparece `▶ [  runFlow] esperar a tela do passo N`. Se a tela demorar, o passo espera.
4. Exporte o flow (Exportar Flow do Maestro…). **Esperado:** um `extendedWaitUntil` com `optional: true` antes do passo cuja âncora é um id. Nenhuma âncora por texto aparece no arquivo.
5. Se a tela mudou desde a gravação, aparece "a ancora do passo nao apareceu; seguindo". Na segunda vez, aparece também "as proximas ancoras deste flow nao serao esperadas".

## SYNC-12: comparar com o Maestro real

Feche o app antes, porque o inspetor disputa o emulador. Depois:

```bash
bash tools/maestro_offline/maestro-offline.sh --device emulator-5554 test tools/maestro_offline/exemplos/configuracoes_android.yaml
```

Pare o driver em seguida, para ele não ficar segurando o UiAutomation:

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell am force-stop dev.mobile.maestro
```

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell am force-stop dev.mobile.maestro.test
```

## O que foi executado nesta sessão

- **Verificado:**
  - pytest do motor (818) e `swift test` (409);
  - mutação de cada mudança;
  - 3 + 3 execuções do flow de exemplo no `emulator-5554` (motor 3.17 e Maestro 2.11.0 real), todas passando.
- **Não verificado:**
  - o moto g55;
  - o iOS;
  - o app instalado (ver o relatório final da sessão).

## Como desfazer

```bash
git switch melhoria/2026-10-28-automacao-sync
```

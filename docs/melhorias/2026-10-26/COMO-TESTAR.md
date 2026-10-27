# Como testar a Rodada 3 (3.12.0)

## Pré-requisitos

- macOS 14 ou mais novo, Xcode Command Line Tools com Swift 6.2.
- O `.venv` do projeto (`make setup`) e Python 3.10 ou mais novo.
- Para testar o Appium e o fluxo: um aparelho Android ou um simulador iOS.
  O Appium 3.x fica em `/opt/homebrew/bin/appium`.
- Sem variáveis secretas. Os testes usam `MOBAILE_LOG_DIR` e
  `MOBAILE_DATA_DIR` temporários.

## Comandos

```bash
git switch melhoria/2026-10-26-rodada3
make check          # esperado: 725 passed / 839 subtests; Tk 20; harness 11; QA 19/31/35/34/26
make test-swift     # esperado: 393 testes, 27 pulados, 0 falhas
```

```bash
make update-native  # com o app fechado (⌘Q): testa, empacota, instala e verifica
```

Só os testes novos:

```bash
cd engine && ../.venv/bin/python -m pytest tests/unit/test_appium.py tests/unit/test_security.py tests/unit/test_ios_cfnetwork.py tests/unit/test_flow_execucao.py tests/unit/test_maestro_flow_rpc.py tests/unit/test_engine_log.py tests/unit/test_analytics_logcat.py -q
```

```bash
cd apps/MoBaile && swift test --filter 'EngineClientTransportTests|FlowRunTests|EngineContractTests|EngineLogLinesTests|ListasComTetoTests'
```

## Passos manuais por melhoria

### MEL-2 · Assinatura que não quebra

1. Feche o app com ⌘Q e rode `make update-native`. Esperado: OK.
2. Abra o app, espere o motor subir e feche com ⌘Q.
3. Rode `codesign --verify --deep --strict "/Applications/Mo baile (nativo).app"`.
   Esperado: nenhuma mensagem. Antes aparecia "a sealed resource is missing or
   invalid".
4. Rode `find "/Applications/Mo baile (nativo).app" -name __pycache__`.
   Esperado: nada.

### MEL-1 · Appium só no loopback

1. Conecte um iPhone ou simulador e abra a hierarquia, para o motor subir o
   Appium.
2. Rode `lsof -nP -iTCP:4723 -sTCP:LISTEN`. Esperado: `127.0.0.1:4723`, e não
   `*:4723`.
3. Confira o log: `ls -l ~/Library/Logs/Mo\ baile/appium.log`. Esperado:
   `-rw-------`.
4. Com o WDA de pé, rode `lsof -nP -iTCP:8100 -sTCP:LISTEN`. Se aparecer
   `*:8100`, o WDA continua aberto para a rede (pendência registrada).

### MEL-3 · Andamento e Parar

1. Grave 3 ou mais passos e use **Rodar Automação**. Esperado: a barra e o
   destaque avançam passo a passo.
2. Rode de novo e clique em **Parar** no meio. Esperado: o badge mostra
   "Pronto", o log mostra a linha `STOP` e nada de "FAIL".
3. **Rodar Flow…** com um `.yaml` do Maestro de 3 comandos (um deles
   `runFlow`). Esperado: o contador mostra `1/3`, `2/3` e `3/3`, sem contar os
   subpassos.

### MEL-4 · Texto sensível

1. Num app de teste, ligue **iPhone em Debug** com uma requisição que receba
   `Set-Cookie`.
2. Abra `~/Library/Logs/Mo baile/cfnetwork-diagnostics.log`. Esperado: o
   valor do cookie aparece mascarado.
3. Grave um passo de digitação com um texto sentinela e rode. Busque o texto
   em `~/Library/Logs/Mo baile/` e em `$TMPDIR`. Esperado: não aparece.

### MEL-5 · Log do motor

1. Abra o app pelo Finder e use-o um pouco.
2. `ls -l ~/Library/Logs/Mo\ baile/`. Esperado: `engine.log` e
   `engine-faults.log` com `-rw-------`, e a pasta com `drwx------`.
3. No Console.app, filtre por `subsystem:com.qa.mobaile category:engine`.
   Esperado: "subiu", com o pid e o caminho do log.

### MEL-6 · Analytics e listas

1. Ligue o Analytics num aparelho com muitos eventos por alguns minutos.
   Esperado: a tabela para em 1000 eventos, descartando os mais antigos, e a
   escuta segue viva.
2. Rode um fluxo longo. Esperado: o log continua rolando até o fim, mesmo
   passando de 5000 linhas.

## O que foi executado nesta sessão (Verificado)

- `make check` e `make test-swift` completos, antes da rodada e depois de cada
  commit, com os números acima.
- Default `0.0.0.0` do Appium 3.2.2, lido no schema instalado.
- Selo quebrado e as 8 pastas `__pycache__` no app instalado antes da rodada.
- MEL-2 de ponta a ponta num bundle falso assinado, no scratchpad.
- O motor real com `MOBAILE_LOG_DIR` no scratchpad: `log_path` no hello e
  arquivos 0600.

## O que não foi executado

- Os passos manuais com aparelho real e simulador: MEL-1, MEL-3, MEL-4 e MEL-6.
- O WDA na porta 8100, uma queda nativa real do motor (faulthandler) e o
  Console.app.
- `make update-native`: depende de o app estar fechado. Veja o relatório final
  da sessão.

## Como desfazer

```bash
git switch melhoria/2026-10-15-rodada2-funcionalidades
```

Para desfazer uma melhoria específica: `git revert <commit>`. Os hashes estão
em `MELHORIAS.md`. Para voltar o app instalado à 3.11.0: troque de branch e rode
`make update-native`.

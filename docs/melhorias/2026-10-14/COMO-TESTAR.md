# Como testar — Rodada 1 (3.5.2)

## Pré-requisitos

- macOS 14+, Swift 6.2 (Xcode 26), Python do `.venv` do repositório.
- Para os testes manuais: um aparelho Android e/ou um simulador iOS.

## Automático

```bash
make check          # versão, ruff, bandit, pytest, fluxos de QA, fixtures
make test-swift     # suíte do front (298 testes; 26 pulam sem sessão gráfica)
```

Resultado esperado: tudo verde. Último resultado nesta máquina: 511 testes do
motor, 5 fluxos de QA, `swift test` com 0 falhas.

## Manual (aparelho real)

1. **M1:** conecte um emulador e um aparelho físico. Escolha o segundo no menu
   de aparelhos e espere alguns segundos. Esperado: ele continua selecionado e o
   espelho não recarrega sozinho.
2. **M2:** com um proxy próprio no aparelho (`adb shell settings put global
   http_proxy corp.exemplo:3128`), ligue e desligue a captura de rede.
   Esperado: `adb shell settings get global http_proxy` devolve
   `corp.exemplo:3128` de novo. Desligar com o cabo solto e plugar de novo
   também restaura.
3. **M5:** ligue a escuta passiva e deixe o aparelho ocupado. Esperado: um toque
   que não vira passo aparece como ignorado, e a escuta continua. No iOS sem
   `pyobjc-framework-Quartz`, o motor responde um erro que diz o que falta.
4. **M7:** numa tela com vários botões de mesmo `resource-id` e textos
   diferentes, grave um. Esperado: o objeto gerado usa `@text=…`, e não o
   `resource-id`.
5. **M6:** reinicie o WebDriverAgent com o app aberto e toque no espelho.
   Esperado: o toque funciona sem reiniciar o motor.
6. **M12:** capture uma requisição com `'` na URL e use "Copiar como cURL".
   Esperado: o texto colado no terminal não executa nada.

## Como desfazer

```bash
git switch melhoria/2026-10-11-opensource-fluidez     # a branch de origem
# ou, por melhoria:
git revert <commit>
```

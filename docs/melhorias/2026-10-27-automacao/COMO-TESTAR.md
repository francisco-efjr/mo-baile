# Como testar: rodada de automação mobile (3.15.0)

Branch `melhoria/2026-10-27-automacao`. Tudo roda local, sem rede.

## Pré-requisitos

- macOS com Xcode e o `swift` do projeto (`make test-swift`).
- Python do motor: `.venv` do repositório (`make check`); PyYAML instalado (extra `maestro`) para rodar flows YAML.
- Android SDK com `adb` e `emulator`. A medição usou o AVD `Pixel_9` (Android, 1080x2424, inglês).
- Opcional, para o caminho mais rápido: Appium 3.x com o driver `uiautomator2` (`appium driver list --installed`).

## Testes automatizados

```bash
make check        # motor (763 testes), ruff, bandit, contrato e as 5 suítes de QA
make test-swift   # front (408 testes, 27 pulados)
```

Resultado esperado: os dois terminam com código 0.

## Subir o emulador (se não houver um aberto)

```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_9 -no-snapshot-save -no-audio -no-boot-anim &
adb wait-for-device && adb -s emulator-5554 shell getprop sys.boot_completed   # espera "1"
```

Para fechar: `adb -s emulator-5554 emu kill`.

Com mais de um aparelho conectado, use sempre `-s emulator-5554` (ou `--device`): a rodada nunca tocou o aparelho físico.

## AUT-1. Leitura rápida da árvore

1. Volte à tela inicial: `adb -s emulator-5554 shell input keyevent 3`.
2. Rode o flow de exemplo e cronometre:

   ```bash
   time .venv/bin/python tools/maestro_offline/rodar_flow.py --device emulator-5554 tools/maestro_offline/exemplos/configuracoes_android.yaml
   ```

3. **Esperado:** "Flow executado com sucesso." em cerca de 30 s (medido: 29,3 a 34,2 s, conforme a rolagem precise de um ou dois deslizes; antes, 70 s).
4. Pelo app: Início › "Rodar Flow…" com o mesmo arquivo. O rodapé do painel de execução mostra o tempo. Com uma sessão UiAutomator2 do Appium já aberta para o aparelho, o mesmo flow cai para 21 a 23 s.

**Critério de aceite:** o flow passa, em menos da metade do tempo de antes (70 s). Abaixo de 30 s com uma sessão do Appium aberta. Ver em MELHORIAS.md por que a correção R-03 custou de 2 a 4 s.

## AUT-2. Reprodução pelo localizador

1. No app, conecte o emulador e abra o app Configurações nele.
2. Grave um toque em **Battery** pelo espelho (estratégia automática).
3. Role a lista um pouco para cima no emulador, para "Battery" mudar de lugar.
4. Rode a automação (⌘R).
5. **Esperado:** a tela de bateria abre. O log do painel mostra `tocar em Battery` e `tapOn texto ~ 'Battery'`.
6. Contraprova, com o comportamento antigo: rode o app com `MOBAILE_FLOW_RUNNER=coordinates` e repita. O toque cai na posição gravada e a tela de bateria **não** abre.
7. Toque gravado em área vazia (sem elemento): o passo aparece como `(coordenada gravada: sem localizador estável)` e toca o ponto.

**Critério de aceite:** o passo segue o elemento quando o layout muda; o texto digitado não aparece no log, no `flow.finished` nem em arquivo.

## AUT-3. Exportar Flow do Maestro

1. Grave dois ou três passos, incluindo um de digitação.
2. Abra a paleta (⇧⌘P) e busque "maestro", ou use Automação › Exportar Flow do Maestro…, ou o botão "Exportar Flow…" na Estrutura do Fluxo.
3. **Esperado:** o Finder abre em `~/Documents/Mo baile/flows/` com o arquivo selecionado; o status diz `Flow salvo em flows/<nome>.yaml · pede <VARIAVEL> em env`.
4. Abra o YAML: o texto digitado não está lá, só `${VARIAVEL}`.
5. Exporte de novo: nasce `<nome>_2.yaml`, sem sobrescrever o primeiro.
6. Sem passos gravados, o comando aparece desabilitado com "Grave ao menos um passo".

O flow exportado começa com `launchApp`, e o `flow.run` não abre o app antes. Para rodar o exportado, passe os valores das variáveis (`rodar_flow.py -e NOME=valor`), porque o "Rodar Flow…" do Início ainda não pede `env`.

## O que foi executado nesta sessão (Verificado)

- `make check` e `make test-swift` verdes depois de cada melhoria.
- AUT-1: flow de exemplo no Pixel_9. Antes da revisão: `rodar_flow.py` 28,1 / 27,9 / 25,3 s e servidor 25,4 / 25,5 / 27,9 s. Depois da revisão: `rodar_flow.py` 34,2 / 29,4 / 29,3 s e servidor 29,5 / 34,0 / 34,0 s. Com sessão do Appium aberta: 21,0 e 23,0 s.
- AUT-2: gravar "Battery", deslocar a lista e rodar `flow.run` pelo servidor: localizador abriu a tela de bateria (4,4 s); coordenadas não abriu.

## Não verificado

- iOS: o runner por localizador ficou fora do iOS nesta rodada (o `flow.run` do iOS segue no script de coordenadas).
- O aparelho físico (Motorola) não foi usado: a rodada só tocou o emulador.
- AUT-3 clicado no app instalado: coberto por testes de sessão e paleta, não por clique na interface.

## Como desfazer

```bash
git switch main                 # volta para a 3.14.2
git revert <commit>             # desfaz uma melhoria só (ver MELHORIAS.md)
MOBAILE_FLOW_RUNNER=coordinates # volta a reprodução antiga sem mexer no código
```

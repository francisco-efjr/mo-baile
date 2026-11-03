# Revisão do arquiteto mobile: AUT-1, AUT-2 e AUT-3

Papel: `mobile-apps:mobile-architect` (brain-of-agent), somente leitura, sobre a
branch `melhoria/2026-10-27-automacao` (= `main` 3.14.2, `469fd5d`). Rótulos:
**[Verificado]** lido no código; **[Inferido]** dedução; **[Suposição]** hipótese
a medir. A nota do orquestrador, no fim, traz as medições feitas no emulador.

## 1. Arquitetura existente

- Camadas `rpc → services → adapters`, portas em `ports/` (`docs/ARQUITETURA.md`). [Verificado]
- `FlowRunner` (`engine/src/mobaile/services/maestro_flow.py:668-953`) só conhece a porta `FlowDevice` (`ports/protocols.py:59-86`, `@runtime_checkable`); relógio e `sleep` injetáveis (`maestro_flow.py:675-697`). [Verificado]
- `AndroidFlowDevice` recebe o leitor do servidor (`adapters/flow_devices.py:44-49`), montado em `flow_maestro_run` (`rpc/server.py:1990-1993`) e apontado para `_android_hierarchy` (`server.py:872-913`), que memoriza por aparelho o backend que funcionou (`server.py:287`, `883-902`). [Verificado]
- Cada dump são 2 processos adb (`adapters/adb.py:255-258` e `rm -f` em `281-285`), sempre no mesmo arquivo remoto (`adb.py:44`). [Verificado]
- `_assentar` só termina com duas leituras iguais, até 10 tentativas com 200 ms entre elas (`maestro_flow.py:45-46`, `799-812`). `_procurar` relê a árvore em toda chamada (`maestro_flow.py:785-797`). [Verificado]
- `flow.run` gera um script de coordenadas com esperas fixas de 0,8 e 1,0 s (`services/flows.py:384`, `414`), grava os passos com `input_text` em disco (`flows.py:139-157`, `182`) e roda em subprocesso (`flows.py:445-555`). [Verificado]
- `flows.py` é usado pelo motor (`server.py:1857-1878`) e pelo Tk congelado (`apps/tk-legacy/mobaile_tk/dialogs.py:17-19`, `635`, `665`; ADR 0005). [Verificado]
- O front decodifica `FlowRun {running, steps, script}` com `script` obrigatório (`EngineDTO.swift:378-382`, `EngineSession.swift:1218-1230`); ninguém chama `flow.maestro_export`. [Verificado]
- Decisão de 05/10: "não haverá fallback automático. Coordenada só vale quando a estratégia gravada é `position`" (`docs/RODADA_2026-10-05_PENDENCIAS.md:87`). [Verificado]

## AUT-1. Leitor de árvore rápido no Android

**Problema.** O flow de exemplo faz de 26 a 33 leituras de ~2 s [Inferido pela
ordem dos comandos]: cada `tapOn` faz uma busca e duas leituras de espera
(`maestro_flow.py:829-838`, `785-797`, `799-812`); `back`, `launchApp` e `swipe`
fazem duas (`852-855`, `912-920`, `884-893`); `assertVisible`, uma (`857-863`). A
busca logo depois da espera relê a mesma tela (`maestro_flow.py:790`, `806-808`).
O `uiautomator dump` já espera a tela ociosa antes de despejar (`waitForIdle` do
AOSP [Inferido]), o que torna a segunda leitura da espera redundante. `_procurar`
engole árvore ausente (`hierarchy() or ""`, `maestro_flow.py:790`) e falha como
"elemento não encontrado". [Verificado]

**Opção (a), Appium como leitor padrão: não recomendada.** A primeira sessão pode
levar dezenas de segundos e instala APK no aparelho; `disableWindowAnimation` e
`newCommandTimeout: 0` mexem no aparelho e mantêm a instrumentação viva, o que
muda o backend de hierarquia do app inteiro (`appium.py:51`, `53`, `266-268`;
`server.py:883-902`). Dependência opcional, sem garantia em outras máquinas.
Já é reaproveitado quando há sessão aberta (`server.py:883-893`).

**Opção (b), sem dependência nova: recomendada.**
- **b1.** `_assentar` guarda a árvore; o primeiro ciclo de `_procurar` a reusa. O
  cache cai a cada ação no aparelho, quando a busca não casa e após 2 s. Em
  `assertNotVisible`, cai depois da primeira checagem.
- **b2.** Atributo opcional `reads_wait_for_idle` (fora do `Protocol`, lido com
  `getattr`): `True` quando o backend da última leitura foi o adb. Com ele e sem
  prazo explícito, `_assentar` faz uma leitura. WDA e Appium seguem com duas.
- **b3 (opcional).** `exec-out uiautomator dump /dev/tty` com reserva no caminho atual.
- **b4 (opcional).** Comparar a árvore normalizada, sem `com.android.systemui`.
- **b5.** Distinguir "não leu árvore nenhuma" de "leu e não casou".

Estimativa com b1 e b2: 19 a 26 s [Inferido]. A política de backend fica no
servidor (`_android_hierarchy`); o runner só conhece a capacidade da porta.
Arquivos: `maestro_flow.py` (~40), `flow_devices.py` (~12), `protocols.py`
(docstring), `server.py:1993` (~2). Contrato RPC não muda.

**Aceite.** Unitário com contador de leituras (no máximo 12 no flow equivalente com
`reads_wait_for_idle`; duas leituras iguais sem ele; `assertNotVisible` relê e passa
quando o elemento some). Emulador: mediana de 3 execuções do flow de exemplo
abaixo de 30 s.

## AUT-2. Reprodução por localizador como padrão

**Problema.** O replay toca a coordenada gravada com espera fixa (`flows.py:256-283`,
`285-361`, `384`, `414`) e quebra sem aviso quando o layout muda (PB4, A3). O
texto digitado vai para disco, num arquivo 0600 apagado no fim (`flows.py:139-157`,
`182`, `430-442`). Exportar e reimportar exigiria PyYAML e trocaria o texto por
`${VAR}` (`maestro_flow.py:1072-1079`, `185-192`, `241`). Um passo `position` tem
`locator_value` em XPath (`codegen.py:233-237`, `247-262`) e `selector_from_step`
ignora `strategy` (`maestro_flow.py:1010-1036`), o que contraria a decisão de 05/10.
XPath sem atributo cai em `point` sem aviso (`maestro_flow.py:1035-1036`). Um `id`
repetido toca o primeiro clicável (`maestro_flow.py:646-651`). [Verificado]

**Desenho.**
1. `maestro_flow.flow_from_steps(passos) -> Flow`, puro, sem YAML. `POSITION` vira
   `point`; localizador sem equivalente é recusado antes de começar, citando o
   opt-out. `Selector.near` (interno) desempata pelo ponto tocado. Cada passo
   gravado vira um item de topo (`recordedStep`), para `flow.step` continuar um
   por passo. O texto real vai para `Flow.secrets` e é mascarado no log; nunca toca
   o disco. Digitação sem texto falha.
2. `flow_run` monta o `Flow` antes da trava, mantém `verify_preconditions`, extrai
   `_flow_device(sessao)` e roda pelo `FlowThread`.
3. Opt-out `runner: "coordinates"` e `MOBAILE_FLOW_RUNNER` (padrão `_env_choice` de
   `config.py`), para aparelhos sem árvore nenhuma.
4. `flows.py` fica (Tk, pré-condições, opt-out).
5. Front: `FlowRun.script` vira opcional; o cabeçalho fixo `.flow_runner.py`
   (`FlowRunnerSheet.swift:125`) muda.

Contrato: aditivo (`runner?` na entrada, `runner` e `script?` na saída). Arquivos:
`maestro_flow.py` (~70), `server.py` (~40), `config.py` (~4), front (~6), protocolo.

**Riscos.** Sem o AUT-1, o replay fica mais lento que hoje. Dentro do flow, um dump
que falha faria `_android_hierarchy` abrir o Appium (`server.py:901-913`): no flow,
só reaproveitar sessão aberta. Passos `//tag` passam a ser recusados.

**Aceite.** Testes de privacidade e "sem texto" (`test_flow_execucao.py:91-200`)
passam com o runner novo; `flow.step` de 1 a N; nenhum `flow_runner_*.py` criado;
`flow.run` sem PyYAML; `position` toca a coordenada; opt-out mantém os testes atuais.

## AUT-3. "Exportar flow…" no app

**Problema.** `flow.maestro_export` (`server.py:1948-1977`) não tem chamada no front.
Exportar não precisa de PyYAML (`maestro_flow.py:1045-1080`). [Verificado]

**Desenho.** Comando `automation.exportFlow` no registro (`CommandRegistry.swift`),
na paleta, no menu Automação, em Arquivo › Exportar e no rodapé da Estrutura do
fluxo (`StructureSheet.swift:55-73`). Chama `flow.maestro_export {save: true, name:
pageObjectsKey}`, revela no Finder (`Exporters.revealInFinder`) e diz no status as
variáveis que o flow pede. Desabilitado sem passos ou com o motor parado. Sem
"Rodar agora" (⌘R já cobre e variáveis sem `env` falhariam). Pasta fixa agora;
"Exportar Para…" depois. Contrato não muda.

**Aceite.** Motivos de desabilitado corretos; arquivo novo em
`~/Documents/Mo baile/flows/`, revelado no Finder, sem o texto digitado e listado
em Início › Continuar.

## Alternativas descartadas

1. Appium como leitor padrão: reavaliar como opt-in se b1+b2 passar de 30 s.
2. Servidor de instrumentação próprio (APK): passa do teto da rodada.
3. `flow.run` exportando YAML e relendo: exige PyYAML e não preserva um `flow.step`
   por passo gravado.

## Ordem

AUT-1 → AUT-2 (depende do AUT-1 para não ficar mais lento) → AUT-3 (depende da
correção de `position` do AUT-2). Estimativa: 250 a 320 linhas de produção.

## Decisões pendentes propostas

1. Espera de uma leitura com o `uiautomator dump`: sim.
2. Appium como leitor por opt-in: não nesta rodada.
3. Flow abrir sessão do Appium no meio da execução: não, só reaproveitar.
4. Localizador sem equivalente: recusar antes de começar.
5. `launchApp` antes do `flow.run`: não.
6. Opt-out `coordinates` no front: não agora.
7. "Rodar agora" no AUT-3: não.
8. Pasta fixa ou painel: pasta fixa e revelar no Finder.

---

## Nota do orquestrador: medições no emulador Pixel_9 (27/10/2026)

Medido nesta sessão, no `emulator-5554` (Android, 1080x2424):

| Medição | Resultado |
|---|---|
| `uiautomator dump` + `cat` | 2,02 / 2,00 / 1,99 s |
| `exec-out uiautomator dump /dev/tty` | 1,99 / 2,00 / 1,99 s (funciona, mas não ganha tempo: b3 descartado) |
| `uiautomator dump --compressed` | 1,99 / 2,00 s |
| Sessão UiAutomator2 do Appium (`AppiumBridge.ensure_android_session`), APK já instalado | 4,2 s |
| `/source` pela sessão do Appium | 0,15 / 0,31 / 0,06 / 0,03 / 0,03 / 0,03 s |
| Flow de exemplo (`rodar_flow.py`), linha de base | 70 s, passou |

As inferências do arquiteto sobre o Appium foram conservadoras: com o servidor já
instalado no aparelho, o `/source` custa de 0,03 a 0,3 s e a sessão abre em 4,2 s.
Isso reforça a alternativa 1 como opt-in, se b1+b2 não bastarem.

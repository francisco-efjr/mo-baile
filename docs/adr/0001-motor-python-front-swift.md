# ADR 0001 — Motor em Python, front em SwiftUI

Data: 2026-09-05
Status: aceito

## Contexto

O repositório tinha duas implementações paralelas do mesmo produto.

`recorder/`, em Python com Tkinter, com cerca de 8.200 linhas em funcionamento
e usadas no dia a dia.

`MoBaile/`, em Swift com SwiftUI, com cerca de 4.600 linhas que reimplementavam
os mesmos conceitos sem estarem ligadas a nada. O levantamento mostrou que
nenhum dos serviços era instanciado em lugar algum, que as telas de espelho,
hierarquia e workspace existiam prontas mas não eram referenciadas pela janela,
e que o interceptador de rede respondia `200 OK` a toda requisição sem
encaminhá-la, com o método de registro de evento vazio e um comentário pedindo
desculpas.

Na prática, o aplicativo nativo abria no estado vazio e não fazia nada.

## Decisão

O Python vira o motor headless do produto, com fronteira JSON-RPC 2.0 sobre
stdin e stdout. O SwiftUI vira a única interface, consumindo esse contrato.

A interface Tkinter permanece funcionando em `apps/tk-legacy` durante a
transição, importando o mesmo motor.

Os serviços Swift que duplicavam o motor foram removidos: `ADBBridge`,
`IOSBridge`, `NetworkInterceptor`, `PassiveListener`, `ScrcpyManager`,
`DeviceWatcher`, `CodeGenerator`, `ElementParser` e `StreamEngine`, somando
1.074 linhas, mais os três arquivos de teste correspondentes e o `Settings`,
cuja responsabilidade passou para o motor.

## Alternativas consideradas

**Consolidar tudo em Python.** Entrega mais rápida e menos risco imediato, mas
o Tkinter não alcança o padrão de aplicativo Mac que o próprio documento de
design do projeto especifica: barra unificada, painéis redimensionáveis,
tipografia do sistema, aparência clara e escura acompanhando o sistema.

**Terminar o app nativo em Swift, com a lógica em Swift.** Deixa o produto com
uma linguagem só, mas joga fora 8.200 linhas testadas e recria, em código novo
e sem cobertura, integrações delicadas com adb, WebDriverAgent e logcat.

**Manter as duas bases.** Foi o que já estava acontecendo. Duas implementações
da mesma regra divergem, e ninguém descobre qual está certa até um cliente
reclamar.

## Consequências

Positivas. Uma implementação por regra. A lógica fica na linguagem em que ela
já funciona e onde a suite de testes roda em segundos, sem aparelho e sem
servidor gráfico. O front fica livre para ser genuinamente nativo. O contrato é
verificado nos dois lados por fixtures geradas pelo próprio motor.

Negativas. O aplicativo depende de um Python 3.10 ou superior presente na
máquina, e o empacotamento precisa embutir o motor no bundle. A serialização
de quadro em base64 tem custo, aceitável na cadência atual do espelho e com
caminho de melhoria já identificado, que é um socket dedicado para os quadros.

## Como isso é verificado

`engine/tests/contract/test_rpc_contract.py` é a especificação executável da
fronteira do lado Python.

`apps/MoBaile/Tests/MoBaileTests/EngineContractTests.swift` decodifica payloads
reais do motor do lado Swift.

O CI reprova o PR se as fixtures estiverem desatualizadas.

# Automação no tempo do aparelho, Fase 2 (3.17.0)

04/11/2026. A rodada é a continuação de [2026-10-28-automacao-sync](../2026-10-28-automacao-sync/MELHORIAS.md). O dono pediu "Seguir para a Fase 2" sem esperar o aceite no moto g55.

A branch é `melhoria/2026-11-04-automacao-fase2`, num worktree próprio (`.claude/worktrees/automacao-fase2`), criado a partir da `melhoria/2026-10-28-automacao-sync` (3.16.0). O checkout principal estava com outra sessão trabalhando na `melhoria/2026-11-03-pycharm-desempenho`.

## O que a avaliação do dono pedia na Fase 2

| ID | Avaliação | Nesta rodada |
|---|---|---|
| SYNC-9 Flow gravado começa numa tela conhecida | Fazer | Feito |
| SYNC-8 Âncora de um elemento por passo | Ajustar (D5: campo aditivo na Fase 2) | Feito, com o ajuste do cético: um elemento só, sem Jaccard |
| SYNC-12 Rodar no Maestro real para comparar | Fazer | Feito (medição, sem código) |
| SYNC-7 Contador de quadros | Ajustar ("só se a Fase 1 não bastar") | **Adiado.** Ainda não há resultado do g55 que mostre que a Fase 1 não basta |

## Linha de base × depois

| Verificação | Antes (3.16.0) | Depois (3.17.0) |
|---|---|---|
| Motor, pytest | 793 aprovados | 818 aprovados |
| Swift, `swift test` | 408 testes, 27 pulados, 0 falhas | 409 testes, 27 pulados, 0 falhas |
| Mutação (SYNC-8 espera e filtros, SYNC-9 espera, R2-01, R2-03, R2-04) | — | todas pegas |
| Flow de exemplo no `emulator-5554`, motor | 30,0 a 30,2 s (3.16.0) | 30,2 a 30,7 s, 3 de 3 passaram. "o app abriu em 0,4 s" no `launchApp` |
| Mesmo flow no **Maestro 2.11.0 real**, pelo `maestro-offline.sh` (SYNC-12) | — | 24,9 a 29,3 s, 3 de 3 passaram, os 13 comandos `COMPLETED`. Depois, nenhuma instrumentação ficou no emulador (driver parado com `am force-stop`) |

**SYNC-12, leitura:** os dois runners passam o mesmo flow. O Maestro fica de 1 a 5 s à frente: cada leitura dele vem do servidor no aparelho, enquanto a nossa usa o `uiautomator dump`, de cerca de 2,1 s por ação, segundo a linha `sincronia:`. É o mesmo gargalo medido na 3.15.0.

## Melhorias

| ID | Mudança | Como foi provado | Commit |
|---|---|---|---|
| SYNC-9 | O `launchApp` espera o app em primeiro plano, com o `foreground_app` lendo o `mCurrentFocus`, até 10 s. O `flow.run` ganha `launch_app`, que põe stop e launch do pacote da maior parte dos passos em `onFlowStart`, sem contar passo. Toggle nos Ajustes › Geral | Testes de unidade, de servidor (o aparelho falso mostra o launcher na primeira consulta depois do `monkey`) e Swift | `3026cfd`, `d0ec34d` |
| SYNC-8 | `choose_anchor` na gravação. `AutomationStep.anchor`, que entra no `codegen.steps`. `assertVisible` opcional de 5 s antes do passo, com disjuntor depois de 2 âncoras perdidas. `extendedWaitUntil` no YAML, só para a âncora por id | Replay da tela intermediária em que o seletor já aparece: sem âncora toca a intermediária, com âncora toca a real. Filtros, YAML e privacidade cobertos por teste | `830a3f5`, `d0ec34d` |

Diff de produção: cerca de 260 linhas (motor e Swift), sem contar testes e documentação.

## Revisão

O `code-quality-refactoring:code-reviewer` apontou 11 achados, R2-01 a R2-11, todos corrigidos com teste. O detalhe está em [revisao/revisor-de-codigo.md](revisao/revisor-de-codigo.md).

O achado alto foi o R2-01: uma âncora por texto levava dado pessoal (e-mail, resultado de busca) para o YAML exportado. Agora o YAML só leva âncora por id.

## Decisões do orquestrador (para o dono revisar)

- **D-1. A âncora por texto fica só na reprodução, nunca no YAML.** Por causa disso, um app em Compose sem resource-id exporta o flow sem âncora.
- **D-2. A âncora é escolhida perto do alvo, e não no título da toolbar.** O título costuma aparecer já na tela intermediária, enquanto o conteúdo perto do alvo chega junto com ele.
- **D-3. O `launch_app` faz parada e abertura, como o `launchApp` do Maestro.** Ele não limpa dados (`clearState`).
- **D-4. SYNC-7 adiado.** Ele só entra se o rastro de uma falha no g55 mostrar uma tela intermediária sem indicador e sem âncora que resolva.

## Limites conhecidos

- Ainda não medido no moto g55, nem a Fase 1.
- Âncora dentro de uma lista que rola pode não estar na tela na reprodução. O disjuntor limita o custo a 10 s por flow.
- O iOS segue no runner de coordenadas no `flow.run` (SYNC-11, adiado). Lá, a âncora só vale pelo `flow.maestro_run`.

## Próximos passos

1. Aceite no g55: a gravação que falhava, 10 de 10, com "Abrir o app do zero" ligado.
2. Com o rastro de uma falha, decidir sobre o SYNC-7.
3. SYNC-11: medir o `/source` do WDA e levar o iOS para o runner de localizador.
4. Ler o `scrollable` na árvore e excluir da âncora o candidato que está dentro de uma lista rolável.

# Revisão de código: Fase 1 (SYNC-1 a SYNC-6)

Papel: `code-quality-refactoring:code-reviewer` (brain-of-agent), somente leitura, 28/10/2026.
Alvo: `git diff` não commitado em `melhoria/2026-10-28-automacao-sync` (5 arquivos, +640/−27).
Veredito: aprovar com ressalvas. R-01 e R-02 devem ser corrigidos antes do commit.

O revisor leu o código, rodou `pytest tests/unit/test_maestro_flow.py` e fez duas simulações em memória com o relógio falso dos testes.

## Resumo
O diff cumpre a proposta. Os laços novos terminam e chamam `_checar`. O cache `_assentada` não fica inconsistente de um jeito que importe, e mexer em `_antes` no laço do indicador não quebra o atalho do dump.

Os problemas reais são três:
- o `_restante` zera o prazo do `retry` e do `onFlowComplete`;
- um indicador permanente custa de 5 a 9 s em cada espera;
- o rastro guarda as primeiras telas, e não as últimas.

## Achados e o que foi feito

| ID | Sev | Problema | Correção aplicada | Teste |
|---|---|---|---|---|
| R-01 | alta | `_restante` nunca reinicia: as tentativas 2 e 3 do `retry`, a limpeza do `onFlowComplete` e o passo depois de um opcional que falhou ficavam com 0 s | O prazo recomeça a cada tentativa do `retry`, antes do `onFlowComplete` e depois de um opcional que falhou | `test_retry_e_on_flow_complete_tem_o_prazo_inteiro` (mutação pega) |
| R-02 | média | Um indicador que nunca some cobra a espera em todo passo: 3 toques custaram 21 s | Um indicador que estoura o limite entra em `_indicadores_vencidos` (classe, id e bounds) e não é mais esperado nesse flow | `test_indicador_vencido_nao_cobra_a_espera_de_novo` (mutação pega) |
| R-03 | média | Com prazo declarado, o laço do indicador passava do prazo: um timeout de 2 s levou 5,2 s | Um limite único para a espera inteira, `min(prazo, 5 s)` para o indicador | `test_prazo_declarado_vale_para_a_espera_inteira` |
| R-04 | média | O rastro parava nas 60 primeiras telas | `deque(maxlen=60)`: guarda as últimas | `test_rastro_guarda_as_ultimas_telas` |
| R-05 | média | A máscara não cobria o valor escapado no XML (`&amp;`, `&quot;`) | `_mascarar` também troca a forma escapada | `test_flow_thread_grava_o_rastro_mascarado_conforme_o_modo` (mutação pega) |
| R-06 | baixa | `flow-rastro` como symlink levaria a gravação e a poda para outro lugar | Recusa symlink e pasta de outro dono | `test_rastro_recusa_pasta_que_e_symlink` |
| R-07 | baixa | No dump, uma leitura a mais (~2 s) por toque achado fora do cache | No dump, a leitura avulsa diferente da tela de antes e sem indicador já conta como parada, pela mesma regra do atalho do `_assentar` | Contagens de `LeituraRapidaTest` voltaram às da 3.15.1 |
| R-08 | baixa | A linha `sincronia:` não saía no passo que falhou | `finally` em volta do passo | — |
| R-09 | baixa | Faltavam testes de `_guardar_rastro`, de `_restante` com retry e de foco antes da digitação | Testes acrescentados; o de foco agora registra a tela no momento do `type_text` | Mutações: SYNC-2, 3, 4, 5, 6, R-01, R-02 e R-05 pegas |

## Dúvidas levantadas
- **Se o prazo do Maestro conta da última ação.** O especialista em Maestro verificou isso no bytecode: `Orchestra.adjustedToLatestInteraction`, em `revisao/maestro-sincronizacao.md`. Mantido.
- **iOS sem `visible="false"`:** um ActivityIndicator escondido, mas dentro da tela, poderia acionar o R-02. Não verificável sem simulador. O R-02 limita o custo a uma espera por flow.
- **Rastro ligado por padrão quando o flow falha:** decisão do dono. Ver MELHORIAS.md.

## Limites
Independência parcial: o revisor é o mesmo modelo que escreveu o código. Não foram verificados o moto g55, o WDA nem o Swift.

# Auditoria de testes: AUT-1, AUT-2 e AUT-3

Papel: `qa-testing:test-auditor` (brain-of-agent), somente leitura, sobre os
testes novos ou alterados em `469fd5d..4ec1355`. O auditor não rodou a suíte. O
orquestrador aplicou os ajustes e conferiu cada um **por mutação da produção**:
mudou o código de propósito e viu o teste certo falhar (commit `05b0134`).

## Resultado

- 39 testes novos ou alterados. Nenhum removido, e 8 pediam ajuste porque a asserção não pegava a regressão que o nome prometia.
- Dos 8 ajustes obrigatórios do cético, os itens 3, 4, 6 e 7 tinham furos de cobertura.

## Ajustes aplicados

| Teste | Problema | Ajuste |
|---|---|---|
| `test_assert_not_visible_nunca_usa_a_arvore_guardada` | Passava mesmo usando o cache, porque o TTL de 2 s vencia e o assert relia | Afirma que não esperou o TTL (`relogio.t < 1,0`) |
| `test_salvar_nunca_sobrescreve_e_fica_em_flows` | O código antigo (`exists()` + `write_text`) também passava | Simula a corrida com `Path.exists` mentindo e confere que o primeiro arquivo ficou intacto |
| `test_texto_digitado_escapado…` | Só afirmava falha, por qualquer motivo | Exige a falha no passo 2 e o `***` na mensagem |
| `test_android_roda_pelo_localizador…` | `FlowThread` mockado inteiro, sem provar a fiação do `backend` | Lê pelo aparelho passado à thread e afirma `reads_wait_for_idle` |
| `test_um_item_de_topo…` | Asserção redundante sobre `summary()` | Removida |

## Lacunas cobertas

| Lacuna | Teste novo |
|---|---|
| G1. `runFlow when` sem cache | `test_condicao_de_run_flow_nunca_usa_a_arvore_guardada` |
| G3. Epoch trocado; o inspetor aproveita a leitura do flow | `test_arvore_lida_depois_de_trocar_o_alvo_nao_vira_a_atual`, `test_inspetor_aproveita_a_leitura_do_flow…` |
| G4. Parar entre a trava e o `start()` | `test_parar_entre_a_trava_e_o_start_nao_inicia_o_runner` |
| G6. Pré-checagem do Appium pelo RPC; backend `appium` sem sessão | `test_aparelho_sem_sessao_do_appium_recusa…`, `test_backend_appium_sem_sessao_nao_le_nem_abre_nada` |
| G7c. `launchApp` com duas leituras | `test_launch_app_segue_com_duas_leituras_mesmo_com_dump` |
| G8. Completude da lista de ações do proxy | `test_toda_acao_do_aparelho_descarta_a_arvore_guardada` (compara com os métodos de `FlowDevice`) |

## Mutações conferidas (cada uma pega pelo teste da linha)

| Mutação | Teste que falhou |
|---|---|
| `assertNotVisible` com cache | `test_assert_not_visible_nunca_usa_a_arvore_guardada` |
| `when visible` com cache | `test_condicao_de_run_flow_nunca_usa_a_arvore_guardada` |
| `launchApp` com uma leitura | `test_launch_app_segue_com_duas_leituras_mesmo_com_dump` |
| Ação sem invalidar o cache | `test_toda_acao_do_aparelho_descarta_a_arvore_guardada` |
| Sem a guarda "tela diferente da de antes" | `test_leitura_unica_igual_a_tela_de_antes_nao_conta_como_assentada` |
| Segredo sem a forma escapada | `test_texto_digitado_escapado_num_seletor_seguinte_tambem_e_mascarado` |
| Sem a guarda de cancelamento no ramo por localizador | `test_parar_entre_a_trava_e_o_start_nao_inicia_o_runner` |
| `_store_hierarchy` sem epoch | `test_arvore_lida_depois_de_trocar_o_alvo_nao_vira_a_atual` |
| `flow.run` sem `backend=` | `test_android_roda_pelo_localizador_por_padrao…` |
| Gravar com `"w"` em vez de `"x"` | `test_salvar_nunca_sobrescreve_e_fica_em_flows` |
| Leitor relendo pelo dump com backend `appium` | `test_backend_appium_sem_sessao_nao_le_nem_abre_nada` |
| Sem a pré-checagem no `flow.run` | `test_aparelho_sem_sessao_do_appium_recusa_antes_de_ocupar_o_aparelho` |
| Cache que não casa sem reler | `test_arvore_guardada_que_nao_casa_e_relida_antes_de_rolar` |
| Máscara na coordenada | `test_mascara_do_yaml_nao_mexe_na_coordenada` |
| Sem aviso de ambiguidade | `test_varios_elementos_casando_viram_aviso_no_log` |
| `assertNotVisible` sem retentar | `test_assert_not_visible_sem_arvore_tenta_ate_o_prazo` |

## Não aplicado (próximos passos)

- G5: invalidação no `retry` num cenário em que nada mais invalida. É raro, porque o `_procurar` que falha já descarta o cache.
- G7a, b, d, e, f: os ramos "`None` não assenta", "capacidade lida depois da leitura", "tela que nunca assenta", TTL e "leitura nova diferente derruba o cache".
- G9: sentinela com `(`, rótulo com o valor digitado e o E2E do servidor com sentinela com caractere de regex.
- G11: o falso de arquivo remoto compartilhado no teste da trava e o caso de dois aparelhos.
- G12: os E2E do `test_flow_execucao.py` parametrizados pelos dois runners.
- G13: os ramos Swift sem variáveis, sem `path` e com erro.
- G14: o `MOBAILE_FLOW_RUNNER` no `Settings.from_env`.

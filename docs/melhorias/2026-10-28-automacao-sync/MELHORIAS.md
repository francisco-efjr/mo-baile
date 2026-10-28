# Automação no tempo do aparelho (3.16.0)

28/10/2026. Rodada orquestrada pelo `ORCHESTRATOR.md` do brain-of-agent. O dono avaliou a [PROPOSTA.html](PROPOSTA.html) e escolheu "Implementar a Fase 1 e medir". A branch é `melhoria/2026-10-28-automacao-sync`, criada a partir da `melhoria/2026-10-27-automacao` na 3.15.1 (`b8aeffb`).

## Resumo

O runner de flow aceitava como pronta uma tela intermediária que ficava parada. No moto g55, ela tinha 11887 B e aparecia em três leituras iguais, até 2 s. O passo seguinte agia nela. Agora:
- o passo gravado por coordenada confere a classe sob o ponto;
- a tela com indicador de carregamento não conta como pronta;
- o alvo achado no meio da transição é procurado de novo na tela parada;
- a digitação espera o foco;
- cada passo diz no log quanto esperou e por quê.

Quando um flow falha, as últimas telas lidas ficam guardadas para diagnóstico.

## Especialistas e validação

| Papel | Especialista | O que fez | Relatório |
|---|---|---|---|
| Pesquisa | `maestro-automacao` (agente do projeto) | Leu o bytecode do Maestro CLI 2.11.0 e do servidor Android e mediu sinais no emulador | [revisao/maestro-sincronizacao.md](revisao/maestro-sincronizacao.md) |
| Contraprova | `architecture-design:skeptic-architect` | Confirmou ou ajustou C1–C9, descartou 6 ideias e propôs o SYNC-3 | [revisao/cetico.md](revisao/cetico.md) |
| Implementação | orquestrador | Testes vermelhos primeiro (replay da sequência real), depois o código | — |
| Revisão de código | `code-quality-refactoring:code-reviewer` | 9 achados (R-01 a R-09), todos corrigidos com teste | [revisao/revisor-de-codigo.md](revisao/revisor-de-codigo.md) |

## Linha de base × depois

| Verificação | Antes (3.15.1) | Depois (3.16.0) |
|---|---|---|
| `make check`, motor | 768 aprovados | 793 aprovados |
| `make check`, QA (sem dispositivo / iOS / Android / HTTPS / relatório) | 19 / 31 / 35 / 34 / 26 | 19 / 31 / 35 / 34 / 26 |
| `make test-swift` | 408 testes, 27 pulados, 0 falhas | 408 testes, 27 pulados, 0 falhas |
| Replay da sequência do g55, aparelho falso | toca o ponto na tela de transição (dump) ou na intermediária (Appium) | toca na tela real, nos dois caminhos |
| Mutação de cada mudança (SYNC-2, 3, 4, 5, 6, R-01, R-02, R-05) | — | todas pegas pelos testes |
| Flow de exemplo no emulador, rodadas 1–6 (o app aberto também lia o emulador) | 5 de 6 passaram (uma vez o toque em "Network & internet" não abriu a tela); 46 a 69 s | 6 de 6 passaram; 39 a 64 s |
| Flow de exemplo no emulador, rodadas 7–12 | — | **Não vale como medida.** O app aberto passou a ler o emulador pelo Appium, a instrumentação do UiAutomator2 ocupou o UiAutomation e o dump falhou nos dois runners. A medição limpa fica para depois de fechar o app (ver COMO-TESTAR) |
| **Flow de exemplo no emulador, medição limpa** (app fechado, emulador sem instrumentação, dump em 2,0 s), 3 rodadas intercaladas | 30,1 / 30,0 / 30,1 s, 3 de 3 passaram | 30,2 / 30,1 / 30,1 s, 3 de 3 passaram, nenhum aviso nem "seguiu sem prontidao" |

**Achado da medição:** a tela de Bateria tem uma `ProgressBar` horizontal permanente (id `progress`, o nível da bateria). A primeira versão do SYNC-4 esperava 5 s nela a cada visita. Corrigido: classe e id "progress" só contam com formato de spinner. Teste: `test_barra_de_progresso_horizontal_nao_conta`.

## Melhorias

| ID | Problema (arquivo:linha na 3.15.1) | Mudança | Antes → depois | Como foi provado |
|---|---|---|---|---|
| SYNC-1 | Ninguém sabia o que o runner esperou | Linha `sincronia:` por passo (inclusive no que falha). Rastro das últimas 60 telas, gravado em `logs/flow-rastro/` quando o flow falha (`MOBAILE_FLOW_TRACE`) | sem diagnóstico → tempo, leituras e motivo por passo; XML da tela que enganou | `test_log_de_sincronia…`, `test_rastro_*`, `test_flow_thread_grava_o_rastro…` |
| SYNC-2 | O toque usava a caixa da leitura da busca (`maestro_flow.py:896-922`) | O alvo achado numa leitura avulsa é procurado de novo na tela parada, e, se andou, o runner espera a caixa parar. Alvo desabilitado espera até 2 s. No dump, a leitura avulsa diferente da anterior já conta como parada (R-07) | toca onde o botão estava → onde está | `test_alvo_achado_deslizando…`, `test_alvo_desabilitado…` |
| SYNC-3 | Coordenada tocada às cegas (`maestro_flow.py:897-899`) | `Step.expect_class` vindo da gravação: o runner só toca quando `element_at` sob o ponto tem a classe gravada; no prazo, toca e avisa | toca a tela intermediária → espera a real | `test_replay_do_g55…` (dump e Appium) |
| SYNC-4 | Spinner deixa a árvore parada (`maestro_flow.py:873-894`) | Tela com indicador visível não conta como assentada, por até 5 s. Indicador que estoura o limite não é mais esperado no flow (R-02). Prazo declarado vale para a espera inteira (R-03) | tela de carregamento "pronta" → espera o indicador sumir | `test_indicador_*`, `test_barra_de_progresso…`, `test_id_de_carregamento…` |
| SYNC-5 | Digitação sem foco (`maestro_flow.py:924-929`) | Espera um nó com `focused=true` (Android, até 3 s). Depois, avisa sem mostrar o valor se o campo não ficou com o texto (ignora senha) | letras perdidas em silêncio → espera e aviso | `test_digitacao_*`, `test_campo_que_nao_mostra…` |
| SYNC-6 | Espera que desiste calada e prazo contado do lugar errado (`maestro_flow.py:887-894`) | O log diz quando a tela não parou. O prazo conta da última ação e recomeça no `retry`, no `onFlowComplete` e depois de um opcional (R-01). O `scrollUntilVisible` tolera uma leitura vazia | — | `test_tela_que_nao_para…`, `test_prazo_da_busca…`, `test_retry_e_on_flow_complete…`, `test_scroll_until_visible_tolera…` |

Diff de produção: cerca de 420 linhas, dentro do teto de cerca de 600, sem contar testes e documentação. O contrato RPC não mudou: as fixtures só trocaram a versão. Os campos novos do `UIElement` (`enabled`, `focused`, `password`) ficam fora do `to_dict`.

**Um commit para as seis.** As mudanças se cruzam no `_assentar` e no `_alvo`, e separá-las em commits que compilam sozinhos daria mais risco que ganho.

## Descartadas na contraprova

Janela de tempo maior, comparação de screenshots, repetir o toque por padrão, perfil por aparelho, assinatura com Jaccard e pré-aquecer o UiAutomator2. Os motivos estão na PROPOSTA.html.

## Decisões tomadas pelo orquestrador (para o dono revisar)

- **D-1. O rastro fica ligado por padrão quando o flow falha.** Ele grava telas do app em teste no disco local, na pasta dos logs (0700, arquivos 0600, valores de `${VAR}` mascarados). Para desligar: `MOBAILE_FLOW_TRACE=nunca`. Limite: um valor que o app reformata ao exibir (CPF digitado "12345678900" aparece como "123.456.789-00") não é mascarado.
- **D-2. No caminho do dump, a leitura avulsa conta como tela parada se for diferente da anterior e não tiver indicador.** É a mesma regra do atalho de 3.15.0. Evita 2 s a mais por toque, mas o SYNC-2 só confere a caixa no caminho do Appium.
- **D-3. A conferência de classe do SYNC-3 usa o prazo da busca, de 17 s.** Uma lista que recicla a linha com outra classe gera espera e aviso, nunca falha.

## Limites conhecidos

- Uma tela intermediária **sem** indicador, cujo seletor também casa, continua passando para passos por id ou texto. O Maestro tem o mesmo comportamento. A âncora por passo (SYNC-8, Fase 2) cobre esse caso.
- Pelo dump, um quadro de transição sem indicador é aceito numa leitura só. Para os passos gravados, o SYNC-3 o pega.
- iOS: `flow.run` continua no script de coordenadas (SYNC-11, adiado). O `flow.maestro_run` no iOS ganha o SYNC-2 e o SYNC-4, mas não o SYNC-5.
- **No emulador, a sincronização nova não custou tempo** (30 s nos dois runners). **Ainda não medido no moto g55 nem com o XML real da tela de 11887 B.** As perguntas bloqueantes do cético (qual app, qual passo e qual sintoma) seguem sem resposta. O rastro do primeiro flow que falhar responde à terceira.

## Próximos passos

1. O flow que falhava no g55 rodado 10 vezes (aceite da PROPOSTA). A medição limpa no emulador está feita: sem custo de tempo.
2. Ler o rastro da próxima falha no g55 e ajustar a lista de indicadores, se for preciso.
3. Fase 2: SYNC-9 (aprovado), SYNC-8 (âncora, campo aditivo), SYNC-7 (contador de quadros, só se a Fase 1 não bastar), SYNC-12 (comparar com o Maestro real no emulador).

# Revisão de código: AUT-1, AUT-2 e AUT-3

Papel: `code-quality-refactoring:code-reviewer` (brain-of-agent), somente leitura,
sobre `469fd5d..4ec1355`, contra [arquiteto-mobile.md](arquiteto-mobile.md) e os
"Ajustes obrigatórios" de [cetico.md](cetico.md). Veredito: **aprovar com
ressalvas**. Os 8 ajustes estavam implementados. Na coluna Desfecho, o que o
orquestrador fez com cada achado (commit `05b0134`).

| ID | Sev | Achado (arquivo:linha na revisão) | Cenário | Desfecho |
|---|---|---|---|---|
| R-01 | Importante | `_preparar_leitura_do_flow` chamava `ensure_android_session` (até 300 s, `appium.py:53`) dentro de `flow.run`/`flow.maestro_run`, com prazo de 30 s e sem progresso (`contract.py:147,154`) | Motorola com sessão caída: o front estoura o prazo, e o motor abre a sessão e começa a tocar depois do erro | **Corrigido**: virou `_conferir_leitura_do_flow`, que recusa antes da trava e manda atualizar a hierarquia no inspetor, que abre a sessão com progresso. Contrato sem mudança |
| R-02 | Importante | O leitor nunca abre o Appium e o preparo só age com backend `appium` já memorizado (`server.py:932, 954-957`) | Android 14 físico recém-conectado: o flow falhava em 17 s com mensagem genérica | **Corrigido**: dump morto (137) no leitor do flow gera erro com o que fazer |
| R-03 | Importante | Com prazo 0, um "não achei" na árvore guardada voltava sem leitura nova (`maestro_flow.py:856-861`) | `scrollUntilVisible` logo depois de um toque rolava pela tela de antes de a lista carregar | **Corrigido**: árvore guardada que não casa é sempre relida (`continue`) |
| R-04 | Importante | A máscara do YAML também era aplicada ao `point` (`maestro_flow.py:1164`) | "100" digitado e passo em `540,1004` viravam `540,***4`, ponto inválido | **Corrigido** |
| R-05 | Importante | Passo gravado com estratégia fixa (ID/XPath) pode não ser único; o runner toca o primeiro sem aviso (`maestro_flow.py:853-855`) | Lista com o mesmo `resource-id` por linha: o runner antigo tocava a 3ª linha pela coordenada; o novo toca a 1ª | **Parcial**: entra o aviso no log. O desempate pela coordenada gravada ficou como decisão pendente |
| R-06 | Sugestão | O caminho por localizador não acordaria a tela | Tela apagada: só a tela de bloqueio | **Não procede** para o `flow.run`: ele continua chamando `flows.verify_preconditions`, que manda `keyevent 224` e `wm dismiss-keyguard` (`flows.py:70-82`) |
| R-07 | Sugestão | `dump_killed` lido fora da trava do dump (`server.py:904`, `adb.py:267`) | Dump do flow entre os dois troca a flag do mesmo aparelho | **Adiado**: impacto baixo, a leitura seguinte corrige |
| R-08 | Sugestão | Sem teste da guarda de cancelamento entre a trava e o `start()` no ramo por localizador | — | **Corrigido**: `test_parar_entre_a_trava_e_o_start_nao_inicia_o_runner` |

## Dúvidas levantadas

- `assertNotVisible` com uma leitura vazia falhava na hora. **Corrigido**: tenta até o prazo.
- O primeiro passo por coordenada aceita a leitura única sem comparar com a tela anterior (`_antes` vazio). Mantido: não há tela anterior para comparar.
- `flow.finished` pode chegar antes da resposta do `flow.run`, e o status "Executando…" sobrescreveria a mensagem final. Já acontecia no script. Fica nos próximos passos.
- `get_page_source` tem prazo de 30 s na thread do flow, então uma sessão travada atrasa o Parar. Fica nos próximos passos.

## Requisitos do cético sem implementação

- Avisar que o YAML exportado começa com `launchApp`: ficou no `COMO-TESTAR.md`, não no status.
- "Com mais de um candidato, o log avisa" (2e): implementado na correção do R-05.

## Checado sem nada a reportar

O proxy `__getattr__` cobre os 7 métodos de ação, e a property é avaliada a cada
acesso. `_flow_running` é solto em toda exceção. `flow.finished` sempre sai.
`_store_hierarchy` usa o epoch. `setdefault` da trava fica sob guarda. A máscara
cobre o literal, a regex e o `repr`, com `repr=False`. O `open("x")` fica sem
TOCTOU. O contrato é aditivo. O Tk e o iOS não são afetados.

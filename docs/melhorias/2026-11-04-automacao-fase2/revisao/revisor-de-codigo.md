# Revisão de código: Fase 2 (SYNC-9 `3026cfd`, SYNC-8 `830a3f5`)

Papel: `code-quality-refactoring:code-reviewer` (brain-of-agent), somente leitura, 04/11/2026. O arquivo do papel não estava no clone, então o revisor seguiu o formato da revisão da Fase 1.

Veredito: aprovar com ressalvas. Os testes dos dois módulos passaram (101). O revisor também fez simulações em memória com `choose_anchor` e `export_steps`.

## Achados e o que foi feito

| ID | Sev | Problema | Correção aplicada | Teste |
|---|---|---|---|---|
| R2-01 | alta | Âncora por texto ia para o YAML exportado sem máscara: um e-mail na tela ou "Resultados para <o que foi digitado>" | Só a âncora por id vai para o YAML, e só se a máscara não a mudar. A âncora por texto fica só na reprodução, em memória. Âncora que **contém** um texto digitado fica de fora, e texto com `@` não vira âncora | `test_ancora_por_texto_nao_vai_para_o_yaml`, `test_ancora_que_contem_texto_digitado…`, `test_nunca_email…` (mutação pega) |
| R2-02 | média | No iOS o `name` sem identifier é o rótulo ("R$ 59,90"), e tecla do teclado podia virar âncora | No iOS, id igual ao rótulo passa pela regra do texto. `XCUIElementTypeKey`, `Keyboard` e `XCUIElementTypeTextView` ficam de fora | `test_nunca_email_nem_tecla_nem_rotulo_do_ios_com_numero` |
| R2-03 | média | Âncora dinâmica custava 5 s em todo passo | Disjuntor: depois de 2 âncoras que não aparecem, as outras daquele flow não são esperadas, com um aviso só | `test_falha_da_ancora…_o_disjuntor…` (mutação pega) |
| R2-04 | média | Pedido de permissão por cima do app fazia o `launchApp` esperar 10 s | O permissioncontroller e o packageinstaller em foco contam como app aberto | `test_launch_app_com_pedido_de_permissao…` (mutação pega) |
| R2-05 | baixa | `get_current_package` ignora pacote terminado em "launcher" | `foreground_app` próprio, que lê o `mCurrentFocus` sem esse filtro e aceita a splash do Android 12+ | Teste de servidor com o foco mudando depois do `monkey` |
| R2-06 | baixa | O pacote do `launch_app` vinha do primeiro passo, que pode ser o launcher | Usa o pacote da maior parte dos passos | `test_abrir_app_usa_o_pacote_da_maior_parte…` |
| R2-07 | baixa | "o app abriu em X s" sumia no onFlowStart | A linha vai direto para o log | Teste de servidor `…antes_dos_passos` |
| R2-08 | baixa | `launch_app` era ignorado em silêncio no runner de coordenadas | Uma linha no `flow.log` | `test_launch_app_no_runner_de_coordenadas_avisa…` |
| R2-09 | baixa | A falha da âncora repetia o texto dela no log | Falha da âncora vira "a ancora do passo nao apareceu" | Mesmo teste do disjuntor (sem "Ana" no log) |
| R2-10 | baixa | Testes que não provavam a espera pelo foco nem a ausência de falha da âncora | O aparelho falso mostra o launcher na primeira consulta depois do `monkey`. Testes de cancelamento, de pacote e de âncora presente | — |
| R2-11 | baixa | A árvore era analisada duas vezes por toque | O `parse_xml` é reaproveitado | — |

## Não resolvido nesta rodada
- Excluir candidato à âncora dentro de um container rolável (parte do R2-03). O `UIElement` não lê `scrollable`. O disjuntor limita o custo.
- **Splash do Android 12+:** pode dar "em foco" antes de a janela ser desenhada. Não foi medido no g55. As duas leituras iguais do `_assentar` vêm depois.

## Limites
O revisor é o mesmo modelo que escreveu o código.

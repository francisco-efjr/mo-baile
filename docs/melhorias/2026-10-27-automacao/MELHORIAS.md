# Rodada de automação mobile (3.15.0)

27/10/2026. O orquestrador seguiu o `ORCHESTRATOR.md` do brain-of-agent com uma
lista fechada de três melhorias, pedida pelo dono. Branch
`melhoria/2026-10-27-automacao`, a partir da `main` 3.14.2 (`469fd5d`).

## Resumo

A automação ficou mais rápida e mais confiável no Android:

- **Leitura da árvore.** O flow de exemplo caiu de 70 s para 29–34 s pelo `uiautomator dump`, e para 21–23 s quando há uma sessão do Appium aberta, o mesmo tempo do Maestro.
- **Reprodução.** Os passos gravados passam a ser reproduzidos pelo localizador, e o toque segue o elemento quando o layout muda.
- **Exportação.** O app ganhou "Exportar Flow do Maestro…".

## Especialistas e validação

| Papel | Especialista | O que fez | Relatório |
|---|---|---|---|
| Arquitetura | `mobile-apps:mobile-architect` | Desenho dos três itens, com `arquivo:linha` | [revisao/arquiteto-mobile.md](revisao/arquiteto-mobile.md) |
| Contraprova | `architecture-design:skeptic-architect` | Achou 3 furos e 1 vazamento; 8 ajustes obrigatórios | [revisao/cetico.md](revisao/cetico.md) |
| Implementação | orquestrador | Um commit por melhoria, com teste | — |
| Revisão de código | `code-quality-refactoring:code-reviewer` | 5 achados importantes, 3 sugestões | [revisao/revisor-de-codigo.md](revisao/revisor-de-codigo.md) |
| Testes | `qa-testing:test-auditor` | 8 testes fracos e as lacunas | [revisao/auditor-de-testes.md](revisao/auditor-de-testes.md) |

## Linha de base × depois

| Verificação | Antes (3.14.2) | Depois |
|---|---|---|
| `make check`, motor | 726 aprovados | 763 aprovados |
| `make check`, suítes de QA (sem dispositivo / iOS / Android / HTTPS / relatório) | 19 / 31 / 35 / 34 / 26 | 19 / 31 / 35 / 34 / 26 |
| `make test-swift` | 404 testes, 27 pulados, 0 falhas | 408 testes, 27 pulados, 0 falhas |
| Flow de exemplo, `rodar_flow.py`, Pixel_9 | 70 s | 29,3 / 29,4 / 34,2 s |
| Flow de exemplo pelo servidor (`flow.maestro_run`) | — | 29,5 / 34,0 / 34,0 s; 21,0 / 23,0 s com sessão do Appium aberta |
| Leitura da árvore | 2,0 s (`uiautomator dump`) | 2,0 s pelo dump; 0,03–0,3 s pela sessão do Appium |
| `flow.run` depois de a lista se deslocar | toca a posição antiga e diz "sucesso" | toca "Battery" na posição nova e abre a tela de bateria |

**A meta de menos de 30 s foi atingida antes da revisão e perdida depois:**

- **Antes da revisão:** mediana de 27,9 s pelo `rodar_flow.py` e de 25,5 s pelo servidor.
- **Depois da revisão:** a correção do R-03 faz o `scrollUntilVisible` reler a tela antes de decidir que o item não está lá. Isso custa uma leitura de 2 s por volta da rolagem, e o tempo depende de a rolagem precisar de um ou dois deslizes.
- **Escolha:** fiquei com a correção, porque ela evita rolar pela tela velha.
- **Como voltar a menos de 30 s:** com uma sessão do Appium aberta.

## Melhorias

| ID | Problema (arquivo:linha) | Mudança | Antes → depois | Como foi provado | Commit |
|---|---|---|---|---|---|
| AUT-1 | Cada leitura custa 2 s e o runner fazia de 26 a 33 por flow (`maestro_flow.py:785-812`) | Árvore assentada reaproveitada até a próxima ação, por um proxy que invalida antes de cada ação. Uma leitura basta com o `uiautomator dump`, se a tela mudou. Leitura pela sessão do Appium quando ela já está aberta. Trava de dump por aparelho. A leitura do flow vira a árvore atual do inspetor. O Appium só é memorizado no SIGKILL | 70 s → 29–34 s (21–23 s com Appium) | Testes de contagem de leituras, mutação e medição no emulador | `f36a560` |
| AUT-2 | `flow.run` tocava a coordenada com espera fixa (`flows.py:256-283`, `384`, `414`) | `flow_from_steps` mais `FlowThread` no Android. Passo sem localizador estável toca o ponto e avisa no log. O toque em área vazia grava `position`. Texto digitado só em memória, com máscara literal e regex. Opt-out `runner: "coordinates"` / `MOBAILE_FLOW_RUNNER`. iOS no script | posição gravada → elemento atual | Testes de privacidade e de `flow.step` pelo runner novo, mutação e aceite no emulador | `7a47e86` |
| AUT-3 | `flow.maestro_export` sem chamada no front (`server.py:1948`) | Comando "Exportar Flow do Maestro…" na paleta, nos menus Automação e Arquivo e na Estrutura. Revela no Finder e diz as variáveis. Gravação com `open("x")` | terminal → um clique | Testes de paleta, de sessão e de RPC com HOME temporário | `4ec1355` |
| Revisão | Achados R-01 a R-05 e a auditoria de testes | Ver os relatórios em `revisao/` | — | Mutação | `05b0134` |

Diff de produção: cerca de 380 linhas, dentro do teto de cerca de 600, sem contar testes e documentação.

## Descartadas na contraprova

- **Recusar `//tag` antes de começar:** quebrava gravações reais (ícone sem descrição, WebView, toque em área vazia).
- **Desempate `near` pelo ponto gravado:** não tem equivalente no YAML. Foi adiado.
- **Dump direto para o stdout (b3):** medido, leva o mesmo tempo.
- **Comparar a árvore normalizada (b4):** sem segunda leitura a comparar com o dump.
- **Appium como leitor padrão:** mexe no aparelho e muda o backend do app inteiro. Fica só o reaproveitamento da sessão aberta.
- **Abrir a sessão do Appium dentro do `flow.run`:** até 300 s num pedido de 30 s. O app agora recusa e manda usar o inspetor.

## Decisões tomadas pelo orquestrador (para o dono revisar)

- **D-1.** Passo sem identidade estável (`position`, xpath só com a classe, toque em área vazia) toca a coordenada gravada, com aviso no log. Isso estende a decisão de 05/10 ("coordenada só quando a estratégia é `position`"). Não é reserva depois de falha: o mapeamento é feito antes de começar.
- **D-2.** O localizador como padrão vale só no Android. O iOS segue no script de coordenadas até o `/source` do WDA ser medido.
- **D-3.** Aparelho que só lê pelo Appium e está sem sessão é recusado com instrução, em vez de o app abrir a sessão dentro do pedido.

## Decisões pendentes

1. **Seletor fixo ambíguo (R-05).** Com a estratégia ID ou XPath fixada nos Ajustes e o mesmo `resource-id` em várias linhas, o runner novo toca a primeira linha e avisa no log. O antigo tocava a linha gravada. Opções:
   - desempatar pelo elemento que contém a coordenada gravada, que é o `near` adiado;
   - gravar se o localizador era único e usar a coordenada quando não era.

   Recomendação: a segunda.
2. **Seletor igual ao texto digitado no YAML.** Exemplo: buscar "pizza" e tocar na sugestão "pizza". O seletor sai `"***"` e o flow exportado não casa. Opção: trocar pela mesma `${VAR}` do `inputText`. Recomendação: fazer.

## Próximos passos

- Lacunas de teste restantes: G5, G7, G9, G11, G12, G13 e G14 (ver [revisao/auditor-de-testes.md](revisao/auditor-de-testes.md)).
- Medir o `/source` do WDA no simulador e decidir o localizador como padrão no iOS.
- `flow.finished` pode chegar antes da resposta do `flow.run` e ser sobrescrito pelo status "Executando…".
- `get_page_source` com prazo de 30 s atrasa o Parar quando a sessão trava.
- `dump_killed` lido fora da trava (R-07).
- "Rodar Flow…" do Início pedir os valores de `env` do flow exportado.

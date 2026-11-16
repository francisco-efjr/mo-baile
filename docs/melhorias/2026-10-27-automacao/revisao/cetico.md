# Contraprova cética: AUT-1, AUT-2 e AUT-3

Papel: `architecture-design:skeptic-architect` (brain-of-agent), somente leitura,
sobre `melhoria/2026-10-27-automacao` (`469fd5d`), contra
[arquiteto-mobile.md](arquiteto-mobile.md) e as medições do orquestrador.

**Resumo.** O desenho se sustenta na direção, mas tinha três furos que quebram
casos reais: o toque em área vazia (passo sintético `pos_x_y`), a leitura
concorrente da hierarquia com o espelho ligado e o Appium aberto dentro do flow
(Motorola e cancelamento). Havia também um vazamento de texto digitado que a
máscara não pegava. O `near` era escopo a mais, e recusar `//tag` quebrava
gravações que funcionam hoje.

## Citações do arquiteto, conferidas

- `_assentar` devolve `anterior` mesmo sem assentar (`maestro_flow.py:812`). Isso importa para o cache.
- O arquivo remoto do dump é o mesmo dentro do processo (`adb.py:44`, `mobaile_dump_{pid}.xml`), o que permite a corrida do item 1c.
- O `waitForIdle(1000, 10000)` do `DumpCommand` está documentado em `docs/research/estudo-mercado/01-inspecao-automacao-mobile.md:627`, `:760`.
- O Appium também é aberto no ramo do backend memorizado (`server.py:889`), não só em `901-913`.

## 1. AUT-1

**b2, uma leitura de espera com o dump: Ajustar.** `server.py:1807-1813` já dorme
0,35 s antes do dump pós-toque ("Aguarda o início da transição visual"). Uma tela
que espera rede sem emitir evento de acessibilidade sai "ociosa" com a tela velha;
com o mesmo rótulo nas duas telas (assistente com "Próximo"), b1+b2 tocaria a tela
antiga. Ajuste: a leitura única só conta se diferir da árvore de antes da ação;
`None` nunca assenta; a capacidade é avaliada depois da leitura; `launchApp` fica
com duas leituras.

**b1, cache: Ajustar.** `stopApp` e `clearState` não assentam (`maestro_flow.py:922-928`);
toque que estoura prazo pode ter sido entregue; `assertNotVisible`,
`extendedWaitUntil notVisible` e `runFlow when` decidem com a árvore e não podem
usar cache (`:867-872`, `:935-939`); `retry` precisa invalidar. Ajuste: cache num
proxy do aparelho que invalida antes de toda chamada que não é leitura; só guarda
árvore assentada; TTL contado do fim da leitura.

**1c, achado novo: corrida com o espelho. Obrigatório.** Com o espelho ligado, o
front pede `hierarchy.dump` a cada `stream.settled` (`EngineSession.swift:1720-1723`,
`:1009-1017`, `:970-978`), sem guarda de flow rodando. O cache do motor dura 1,2 s
(`server.py:857-859`). Os dois dumps usam o mesmo arquivo remoto e o `rm -f` de um
apaga o do outro (`adb.py:281-285`); sai `None`, o servidor memoriza `appium` e abre
sessão até no emulador (`server.py:901-907`). Ajuste: trava de dump por aparelho e
leitura do flow alimentando `_store_hierarchy`. Aceite medido também pelo servidor,
não só pelo `rodar_flow.py`.

**b3: Descartar** (mesmo tempo, medido). **b4: não construir.** **b5: Mantido**, com
a distinção nascendo no adapter (137 vs outras falhas, `adb.py:264-278`).

**Extra quase grátis:** se já existe sessão UiAutomator2 aberta para o aparelho, o
flow lê por ela (0,03–0,3 s medidos), sem abrir nada.

## 2. AUT-2

**2a, privacidade: Ajustar.** A gravação lê o campo depois da digitação
(`server.py:1741-1760`, `codegen.py:84-95`); um passo posterior pode ganhar
localizador de texto com o valor, escapado como regex (`maestro_flow.py:1000-1002`),
impresso por `Selector.describe` (`:101`) na mensagem de falha (`:821`). `_mascarar`
só troca o literal e o `repr` (`:700-705`): `123\.456\.789-00` passa. O teste atual
usa `SENTINELA-7f3a`, sem caractere de regex. Ajuste: `Flow.secrets` inclui a forma
escapada; teste com sentinela com `.` e `(`; `repr=False` nos campos sensíveis.

**2b, `flow.step`: Mantido, simplificado.** Usar `Step("runFlow", steps=..., label=...)`
sem `when` (`maestro_flow.py:930-942`) em vez de comando novo.

**2c, cancelamento: Ajustar.** Fora da thread do RPC, `_check_cancelled` e
`_progress` não fazem nada (`server.py:370-392`); abrir o Appium dentro do flow trava
o Parar por dezenas de segundos. Copiar a guarda de `server.py:2016-2020`. Digitação
sem texto continua falha **no passo** (`test_flow_execucao.py:107-118`).

**2d, contrato: Mantido.** O Tk usa `flows.py` direto e não é afetado.

**2e, `near`: adiar.** Em modo `auto` o localizador gravado é único na tela da
gravação (`codegen.py:230-243`); `near` não teria equivalente no YAML. Com mais de
um candidato, o log avisa.

**2f, recusar `//tag`: Descartar como desenhado.** `//tag` é legítimo para ícone sem
`content-desc`, WebView ou View custom (`codegen.py:296-330`). E o toque em área
vazia gera um elemento sintético `text="pos_x_y"` (`server.py:1546-1567`) cujo xpath
vence `position` no ranking (`codegen.py:303`); viraria `{"text": "pos_900_1600"}` e
falharia em 17 s. Ajuste: o elemento sintético só tem candidato `position`; no
runner, `POSITION`, `//tag` sem atributo e `pos_x_y` viram `point`, com linha de log.

**2g, Appium no flow e o Motorola: Ajustar.** Pré-checagem da sessão no `flow_run`,
na thread do RPC, quando o backend memorizado é `appium`; dentro do flow, nunca abrir
sessão nem gravar o backend; memorizar `appium` só no 137.

**2h, iOS: Ajustar.** O `/source` do WDA mede de 1,2 a 21 s
(`01-inspecao-automacao-mobile.md:123-128`). Padrão por localizador só no Android
nesta rodada.

## 3. AUT-3: Mantido, com ajustes

- TOCTOU entre `exists()` e `write_text` (`server.py:1968-1974`): `open(..., "x")`.
- O comentário `# passo N: {element_name}` e os seletores de texto do YAML podem
  carregar o valor digitado (`maestro_flow.py:1069-1070`): mascarar.
- O YAML exportado começa com `launchApp` (`maestro_flow.py:1065`) e o `flow.run`
  não abre o app: avisar.
- "Rodar Flow…" do Início não passa `env` (`HomeDaily.swift:423-432`): o status diz
  que flow com variáveis precisa de `env`.

## Pré-mortem (12 meses)

| Causa | Sinal | Reverter |
|---|---|---|
| Toque na tela velha com b1+b2 | passo N+1 "ok" com a tela antiga no espelho | baixo: desligar o cache |
| Corrida de dump troca o emulador para Appium | "abrindo sessao do Appium" com emulador | médio |
| Gravação de área vazia ou `//tag` para de rodar | "elemento nao encontrado: texto ~ 'pos_…'" | baixo, com o mapeamento para `point` |

## Ajustes obrigatórios (todos adotados pelo orquestrador)

1. Elemento sintético só com `position`; `POSITION`, `//tag` sem atributo e `pos_x_y` viram `point` com log; não recusar `//tag`.
2. Máscara do texto escapado no runner e no YAML exportado, com teste de sentinela com `.`/`(`.
3. Trava de dump por aparelho e leitura do flow alimentando `_store_hierarchy`.
4. Appium no flow: nunca abrir nem memorizar dentro da thread do flow; pré-checagem na thread do RPC; memorizar `appium` só no 137.
5. b2 com guarda (diferente da árvore de antes; `None` não assenta; `launchApp` com duas leituras).
6. b1 por proxy, sem uso em checagem negativa nem em `when`, só árvore assentada, TTL do fim da leitura.
7. Guarda de cancelamento entre a trava e o `start()`; digitação sem texto falha no passo.
8. Padrão por localizador só no Android; sem `near`; `runFlow` com `label`.

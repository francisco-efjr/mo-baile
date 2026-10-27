# Desempenho e qualidade das validações (23/10/2026)

Revisão da auditoria de tagueamento (aba Relatório) e da validação de entrada do
RPC, com medição antes e depois. O resultado da auditoria não mudou: a
impressão digital (SHA-256) do payload de `report.audit` e dos quatro arquivos
do export é a mesma antes e depois, nos três cenários.

## Como medir

```bash
.venv/bin/python tools/bench_report.py                                   # médio
.venv/bin/python tools/bench_report.py --eventos 50000 --cards 200 --fluxos 6
# outra cópia do motor, para comparar com uma versão antiga:
git archive v3.9.0 engine/src | tar -x -C /tmp/antes
MOBAILE_ENGINE_SRC=/tmp/antes/engine/src .venv/bin/python tools/bench_report.py
```

O cenário é sintético e determinístico (semente fixa): spec com cards de quatro
tipos (`screen_view`, interação com variações `[numero]` e `[sim|nao]`,
`add_to_cart` com `items` e `params_por_fluxo`, evento com `re:` e `[data]`) e
log Android + iOS com acertos, divergências, disparos antigos, `screen_name`
errado na tela certa, fora da spec, alertas, ruído do SDK e duplicados. Um card
em cada 13 nunca dispara. Prints PNG de 360×780 por card.

## Números

Mediana de 3 execuções (o "antes" do máximo é 1 execução), Apple M4 Pro,
Python 3.14, em milissegundos.

| Cenário | Log | Eventos | Variações |
|---|---|---|---|
| médio | 6,8 MB | 20.847 | 480 (80 cards, 4 fluxos) |
| grande | 17,2 MB | 52.066 | 1.800 (200 cards, 6 fluxos) |
| máximo | 62,0 MB | 187.501 | 1.800 (200 cards, 6 fluxos) |

| Etapa | médio antes | médio depois | grande antes | grande depois | máximo antes | máximo depois |
|---|---:|---:|---:|---:|---:|---:|
| normalizar o log | 216 | 138 | 562 | 356 | 2.146 | 1.483 |
| auditar as variações | 382 | 46 | 4.294 | 130 | 37.042 | 523 |
| fora da spec e alertas | 409 | 20 | 4.709 | 102 | 38.337 | 407 |
| **`report.audit` inteiro** | **1.051** | **209** | **10.259** | **582** | **78.410** | **2.251** |
| board | 27 | 22 | 87 | 72 | 92 | 70 |
| HTML | 28 | 22 | 100 | 85 | 106 | 81 |
| **`report.export` inteiro** | **56** | **46** | **201** | **170** | **202** | **180** |

O caso que importa é o máximo: um log perto do limite de 64 MB levava 78 s,
acima dos 60 s de timeout de `report.audit` no contrato. A pessoa via a
auditoria expirar sem resultado. Agora leva 2,3 s.

## O que mudou

### Auditoria (`services/report/audit.py`)

- **Índice de eventos.** `_candidates` varria o log inteiro para cada variação
  (O(eventos × variações)). O `EventIndex` agrupa por nome do evento e, sob
  demanda, pelo valor exato de `flow_name`, `detail`, tela (`screen_name` ou
  `ga_screen`) e `ga_screen`. Cada variação começa pelo recorte literal mais
  estreito e só confere placeholders nele. A ordem do log é preservada.
- **Candidatos uma vez só.** `find_extras` recalculava os candidatos de todas
  as variações para saber o que já estava atribuído. Agora `run_audit` calcula
  uma vez e passa adiante.
- **`_covered` removido.** Era uma segunda varredura de todas as variações por
  evento. Ela nunca mudava o resultado: um evento que casa com evento, fluxo,
  tela e `detail` de uma variação está entre os candidatos dela, e já tinha
  saído por "atribuído". O teste de paridade compara com a versão antiga, que
  ainda tem `_covered`.
- **Fluxos e telas da spec lembrados.** `in_flows` e `in_screens` comparavam
  cada evento com a lista de fluxos da spec, uma entrada por variação e com
  repetição. Agora a lista é deduplicada e a resposta é lembrada por valor do
  log, que se repete muito.
- **Disparos anteriores conferidos uma vez.** `audit_variant` rodava
  `check_params` duas vezes em cada disparo anterior.

### Regras (`services/report/rules.py`)

- `value_matches` montava a regex de `[a|b]`, `[numero]` e similares a cada
  comparação. Agora o valor da spec é compilado uma vez (`_compiled`, com
  `lru_cache`), e `literal_value` diz se ele é texto exato, o que permite a
  busca no índice.
- Os 15 padrões de ruído do SDK viraram uma regex só. As regex de sufixo
  `(_xx)` e de espaço em volta de `:` são pré-compiladas e só rodam quando o
  texto tem `)` ou `:`.

### Log (`services/report/firebase_log.py`)

- `_split_top_level` montava o texto caractere a caractere. Agora usa
  `split` quando não há `[]{}` e, quando há, visita só os separadores. A
  equivalência foi conferida por fuzz com 200 mil textos.
- A ordenação por horário usa uma lista de chaves em vez de um dicionário.

### Export e payload

- O print é lido do disco uma vez e aberto pelo Pillow a partir dos mesmos
  bytes (`board.read_image`).
- O payload consulta o disco uma vez por card, e não uma por variação, para
  saber se o print existe.
- As regex do realce do bloco no HTML são pré-compiladas.

### Validação de entrada do RPC (`security/numbers.py`, `rpc/server.py`)

- `validate_number` e `validate_integer` conferem o tipo, se o valor é finito e
  a faixa, e dizem o nome do parâmetro no erro. Valem para `limit`,
  `poll_interval`, `max_width`, `fps`, `quality`, `max_size`, `step_num`,
  `before_s` e `after_s`. As faixas estão em
  [PROTOCOLO_RPC.md](PROTOCOLO_RPC.md), em "Convenções".
- Problemas que existiam antes:
  - `limit: -5` devolvia o histórico a partir do 5º item, porque a fatia
    negativa ficava do lado errado;
  - `limit: "abc"` virava "Erro interno no motor";
  - `poll_interval` negativo ou `Infinity` passava;
  - `NaN` e `Infinity` são JSON válido para o Python. Numa coordenada, eles
    estouravam no `int()` como erro interno.

  Agora todos esses casos voltam como `invalid_input`.
- O comentário em `security/paths.py` citava `O_EXCL`; a flag usada é
  `O_NOFOLLOW`.

## Testes

- `test_report_desempenho.py` tem três partes:
  - **Paridade.** O oráculo é a varredura antiga, escrita do jeito direto. Os
    candidatos de cada variação, "fora da spec" e alertas são comparados com
    ela em cenários sorteados de 3 mil eventos.
  - **Peças novas.** `literal_value`, `_split_top_level` e valor vazio no
    índice.
  - **Guarda de tempo.** 20 mil eventos e 1.800 variações levavam 2,5 s antes e
    levam 0,07 s depois; o teste falha acima de 1 s.
- `test_parametros_rpc.py`: `limit`, `poll_interval` e `session.correlate`
  com texto, `NaN`, `Infinity`, valor negativo e fração viram `invalid_input`.
- `test_security.py`: os validadores novos, e coordenada com `NaN` ou
  `Infinity`.

## Ficou de fora (anotado, sem correção)

- **Regex da spec (`re:`) sem limite de tempo.** Uma regex catastrófica
  escrita na spec pode travar a auditoria. A spec é da própria pessoa, então o
  risco é baixo. Corrigir pede o módulo `regex` (com timeout) ou um teste de
  padrões perigosos.
- **Deduplicação com `json.dumps` por evento.** Custa cerca de 8% da
  normalização. Uma chave sem JSON mudaria a equivalência em casos de borda
  (`1` × `1.0` × `true`), então ficou como está.
- **Print lido duas vezes no export**, uma pelo board e outra pelo HTML. São
  ~20 ms no cenário grande.
- **Normalização do log ainda domina o tempo** no log de 62 MB (1,5 s de
  2,3 s): o Bundle do Android é interpretado em Python puro.

## Sugestão para o CHANGELOG

```markdown
### Corrigido

- **Auditoria de log grande não expira mais.** Um log de Analytics perto do
  limite de 64 MB levava 78 s e estourava o timeout de 60 s do
  `report.audit`. Agora leva cerca de 2 s; um log de 17 MB caiu de 10 s para
  0,6 s. O resultado é o mesmo, conferido contra a versão anterior. Medição
  em docs/DESEMPENHO_RELATORIO.md (`tools/bench_report.py`).
- **Parâmetro numérico inválido no RPC vira `invalid_input`.** `limit`
  negativo devolvia o histórico errado. Texto, `NaN` e `Infinity` em `limit`,
  `poll_interval`, `fps`, `max_width`, `quality`, `max_size`, `step_num`,
  `before_s`, `after_s` e nas coordenadas viravam erro interno ou passavam
  adiante. As faixas estão em PROTOCOLO_RPC.md.
```

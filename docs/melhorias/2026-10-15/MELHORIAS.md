# Melhorias de 15/10/2026 — Rodada 2 (versão 3.6.0)

Cinco funcionalidades escolhidas pelo dono na mesa de propostas
(`docs/melhorias/2026-10-14/revisao/propostas-priorizadas.md`), implementadas
no modo melhoria do orquestrador com o contrato escrito antes
([`CONTRATO.md`](CONTRATO.md)). `PROTOCOL_VERSION` continua 2.

## Linha de base × depois

| Verificação | Antes (3.5.2, `40f9887`) | Depois (3.6.0) |
|---|---|---|
| Motor (`pytest`) | 528 passam, 238 subtests | 566 passam, 240 subtests |
| UI Tkinter | 20 | 20 |
| Fluxos de QA com aparelho falso | 19 / 31 / 35 / 34 / 26 | 19 / 31 / 35 / 34 / 26 |
| `swift test` | 298, 0 falhas, 26 pulados | 322, 0 falhas, 26 pulados |
| `ruff`, `bandit`, `fixtures-check` | ok | ok |

`make check` e `swift test` rodaram antes de cada um dos cinco commits; os
números acima são do último portão. Os 26 pulos do Swift são os testes que
dependem de sessão gráfica (pendência M17).

## Funcionalidades

| ID | O quê | Contrato | Prova | Commit |
|---|---|---|---|---|
| F3 | Digitação no iOS no fluxo (`execute_ios_step` honra `input` via `/wda/keys`) | sem mudança | `test_flow_execucao.py::TestDigitacaoIOS` (runner real, WDA falso) | `34f2aad` |
| F11 | Espelho em JPEG (`format`, `image_base64`), MJPEG do WDA no iOS, `tools/bench_frame.py` | `stream.frame`, `stream.start` | `test_frame_encoding.py`, `test_mjpeg.py` (servidor multipart falso), `FrameFormatTests` | `16691a1` |
| F8 | `proxy.diagnose` e "Por que não vejo tráfego?" | método novo | `test_proxy_diagnose.py`, `TrafficDiagnosisTests` | `9796eeb` |
| F12 | Tokens na busca, escopo da Rede, colunas lembradas | só front | `SearchTokenTests` (17 com os antigos) | `c05265f` |
| F5 | `recorded_at` no passo e `session.correlate`; chip de correlação | `codegen.*`, método novo | `test_correlacao.py`, `CorrelationTests` | `4175384` |

Benchmark do F11 (`tools/bench_frame.py`, 900×2000, mediana de 20 iterações):
PNG compress 1 = 20,7 ms e 1 970 335 bytes; JPEG 80 = 2,2 ms e 86 504 bytes
(90% menos tempo, 96% menos bytes). É encode no Mac, não fps no aparelho: o
critério "10 fps sustentados no simulador" do plano depende do MJPEG real e
**não foi medido**.

## Decisões e premissas registradas

- **F5 não depende de F1 (flow.step):** a correlação é feita na gravação, pela
  hora do passo, e não na execução. Todos os carimbos (proxy, analytics,
  netlog, passo) são `time.time()` do Mac na recepção; não há relógio do
  aparelho a corrigir. `probable` é sempre `true`: atribuição por tempo.
- **Sugestões de token** usam `searchSuggestions`/`searchCompletion` em vez de
  `.searchable(text:tokens:)`: o resultado é o mesmo para quem usa (sugestão
  que completa o campo), sem um segundo estado de tokens a sincronizar com o
  texto livre.
- **F11 fixture em PNG:** o JPEG varia de bytes entre versões da libjpeg, e a
  conferência das fixtures é por pixel.

## Revisão independente (REV-1 a REV-11) e o que mudou

Um revisor Opus leu o diff dos cinco commits contra o contrato. Tudo o que
ele apontou foi corrigido no commit seguinte, com teste onde cabia:

| REV | Sev. | O que era | Correção |
|---|---|---|---|
| 1 | Alta | `param:=42` na busca de Analytics derrubava o app (`partes[0]` em array vazio) | `omittingEmptySubsequences: false` + guarda; `param:chave=` vale como "chave existe" |
| 2 | Média | `tls_pinning_suspected` acusava pinning, mas o proxy repassa o TLS sem abrir (ADR 0004): túnel com erro é rede do Mac | código `tunnels_failing`, texto honesto, contrato e PROTOCOLO corrigidos |
| 3 | Média | túnel aberto (HTTP/2, keep-alive) não está no histórico e virava "nenhuma conexão" | `active_tunnels` no proxy; `no_connections` exige zero túneis ativos |
| 4 | Média | timeout de 2 s de conexão valia também na leitura do MJPEG: uma pausa do WDA matava o fluxo | timeout só para conectar; socket da resposta sem prazo; `shutdown` no stop |
| 5 | Média | "repassa sem reencodar" só vale se o quadro cabe no `max_width`; o WDA manda nativo | o motor pede `mjpegScalingFactor` ao WDA antes de ler; PROTOCOLO diz isso |
| 6 | Média | iteração sobre o `deque` do analytics sem lock | `history_events()` sob o lock |
| 7 | Baixa | troca de `_mjpeg` sem lock e leitor descartado sem `stop()` | troca atômica sob `_state_lock`; `stop()` do leitor; espelho para antes do leitor |
| 8 | Baixa | "Limpar tráfego" não zerava a correlação; vazio na janela dizia "Aguardando tráfego" | limpar zera; mensagem própria "nenhuma requisição na janela deste passo" |
| 9 | Baixa | no Relatório um token virava filtro ignorado e mostrava tudo | `matchesLiteral`: token vale como texto |
| 10 | Baixa | sem aparelho na sessão a mensagem dizia "o aparelho aponta para o proxy" | `no_connections` exige `device_configured is True`; texto do `proxy_not_on_device` honesto |
| 11 | Baixa | `patch("...codegen.time.time")` congelava `time.time` no processo | `SimpleNamespace` no módulo |

Desvios do contrato, registrados: o `CorrelationCard` no inspector do passo
não foi feito (o chip e os menus "Ver na Rede/Analytics" cobrem o uso); o
Relatório ficou sem `TableColumnCustomization` (só Rede e Analytics); o botão
"Por que não vejo tráfego?" está na barra, na paleta e no menu, não no estado
vazio; a fixture de `stream.frame` é PNG (justificado acima).

## O que não foi verificado

- Nenhum item rodou com aparelho real, WDA real, simctl real nem MJPEG real:
  o roteiro está em [`COMO-TESTAR.md`](COMO-TESTAR.md).
- `TableColumnCustomization` com `@SceneStorage` não tem teste automático: foi
  verificado só por compilação; o roteiro manual cobre.
- Os 26 testes do Swift que dependem de sessão gráfica continuam pulando.

## Próximos passos (fora desta rodada)

- F1/F2 (flow.step e replay por localizador), F4, F6, F7, F9, F10: ver
  `docs/melhorias/2026-10-14/revisao/propostas-priorizadas.md` e a mesa.
- Rodada 2 e 3 da auditoria (fixtures reais, log do motor, CI contando skips).

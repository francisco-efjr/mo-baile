# agent-device x Mo baile: análise comparativa e melhorias validadas

- **Data:** 2026-10-10
- **Mo baile analisado:** branch `etapa-1/motor-que-nao-trava`, commit `8fe6cdc`, `VERSION` 3.4.0.
- **agent-device analisado:** SHA `87dbd708fd9dd606c1f2fdca6f0697e8e0e43bd2`, a partir de [01-pesquisa-tecnica.md](01-pesquisa-tecnica.md) e do clone somente leitura em `/private/tmp/claude-502/agent-device-src/repo`. Nada do agent-device foi executado.
- **Escopo:** comparação técnica com foco em persistência de dados e propostas adaptadas à arquitetura do Mo baile. Nenhum código foi alterado.

## Convenções

- **Fato (Mo baile)** vem com `arquivo:linha` do repositório, relativo à raiz (`engine/src/mobaile/...`, `apps/MoBaile/Sources/MoBaile/...`).
- **Fato (agent-device)** cita a seção da pesquisa (`pesquisa §4.4`) ou o arquivo do clone (`clone: caminho:linha`).
- **Verificado** marca o que conferi executando o código do próprio Mo baile, sem tocar no repositório: foi um script no scratchpad que importa o módulo e alimenta o parser.
- **Inferência** é dedução a partir do código, sem execução.
- **Recomendação** fica separada, nas seções 4 a 7. Nas seções 2 e 3, o que não é fato está marcado como "leitura".
- **Esforço**, na mesma escala de [`pontos-de-melhoria-2026-10-05.md`](../pontos-de-melhoria-2026-10-05.md): P até 3 dias, M de 1 a 2 semanas, G acima de 2 semanas.

---

## 1. Resumo executivo

O agent-device trata o disco como evidência e recuperação, nunca como estado vivo. Toda escrita é atômica, privada (0600/0700) e versionada, e o que muda fora do processo deixa um registro para ser desfeito depois de uma queda (pesquisa §4.1, §4.7, §4.11). O Mo baile já acerta o princípio: o estado mora em memória e o motor morre com o app (`docs/ARQUITETURA.md:55-60`). O que falta é a outra metade. Quase nada do que o motor grava é atômico ou versionado, e o que ele muda no aparelho ou deixa rodando não sobrevive a uma queda. Também confirmei um vazamento real de segredo em disco.

As 5 melhorias de maior retorno:

1. **Fechar o vazamento do log bruto do CFNetwork** (P, patch). Query strings com token e `Set-Cookie` vão em claro para `~/Library/Logs/MoBaile/cfnetwork-diagnostics.log` (verificado; `adapters/ios_cfnetwork.py:314-323`, `:425-431`).
2. **Uma primitiva de escrita segura e segredo fora do disco** (P, patch). Seria um módulo `security/storage.py`, com temporário + `fsync` + `os.replace`, 0600/0700 e recusa de symlink nos diretórios do motor. A mesma entrega faz o runner de fluxo receber os passos pelo stdin, e não mais gravados em claro num `.py` que sobra no disco após uma queda (`services/flows.py:146,176,481-485`).
3. **Log do motor em arquivo com rotação e `diagnostic_id` no erro** (P, minor). Hoje o log vai para o stderr do app e some quando o app é aberto pelo Finder (`Engine/EngineClient.swift:158-166`). Junto entram rotação, permissão 0600 e nível de log no Appium (`adapters/appium.py:125-139`).
4. **Registro durável do que o motor muda no aparelho e dos processos que ele cria** (M, minor). Proxy global, `captive_portal_mode`, debug do Firebase, vídeo em `/sdcard` e Appium órfão ficam para trás numa queda (`adapters/adb.py:362-411`, `adapters/analytics_logcat.py:184-207`, `adapters/appium.py:154-166`). É o padrão de descritor durável + `owned-processes.json` do agent-device, em versão simplificada.
5. **Sessão de gravação persistida, versionada e sem senha** (M, minor). Integra o `session_store.py` que já existe na branch wip (PB3) e soma a parametrização `${VAR}` do `--record-as` (ADR 0017 do agent-device).

Logo atrás vem a **geração da hierarquia**, uma versão simplificada do "ref frame". Ela impede que um passo seja gravado contra uma árvore diferente da que a pessoa via. É P-M e minor.

O Mo baile está à frente em captura HTTP com redação (inclusive CPF e CNPJ), em analytics com auditoria de tagueamento e em geração de Page Objects. Nenhuma ideia exige abrir porta TCP.

---

## 2. Mapa lado a lado

Uma linha por tema: o que o agent-device faz, o que o Mo baile faz e a leitura (quem está melhor e se o padrão cabe no Mo baile).

**Processos e transporte**

- **agent-device:** CLI e MCP são clientes finos de um daemon Node por diretório de estado. O transporte é TCP loopback NDJSON, ou HTTP JSON-RPC com token. Os helpers nativos são persistentes (pesquisa §2.1, §2.2).
- **Mo baile:** o front sobe o motor como processo filho e fala JSON-RPC 2.0 por stdio, sem porta TCP (`docs/ARQUITETURA.md:44-66`, `EngineClient.swift:117-122`). Há filas seriais por domínio (`rpc/contract.py:43-50`, `rpc/server.py:125-176`).
- **Leitura:** decisões diferentes e coerentes com o público de cada um. O daemon serve a vários agentes; o Mo baile serve a uma janela. O modelo do Mo baile fica.

**Ciclo de vida**

- **agent-device:** o daemon sai sozinho depois de 5 min ocioso. Na subida, recupera órfãos a partir de descritores duráveis (pesquisa §2.1, §4.7).
- **Mo baile:** o motor morre com o app. O encerramento é ordenado (`server.py:1630-1665`) e o SIGTERM vira pedido de parada (`server.py:1729-1742`). O front reinicia o motor numa queda e devolve aparelho e espelho (`EngineSession.swift:279-413`).
- **Leitura:** o Mo baile é bom no caminho feliz. A queda (SIGKILL ou crash) deixa órfãos e mudanças no aparelho sem registro (seção 3.3).

**Hierarquia no Android**

- **agent-device:** APK de instrumentação persistente com `UiAutomation.getWindows()`, sem nunca usar `uiautomator dump`. O p50 cai de 227 ms para 5,8 ms (pesquisa §3.1, §5).
- **Mo baile:** `uiautomator dump` para `/data/local/tmp/mobaile_dump_<pid>.xml` + `cat`, com a sessão UiAutomator2 do Appium como reserva (`adapters/adb.py:245-281`, `server.py:681-722`). Há cache de 1,2 s (`server.py:664-679`).
- **Leitura:** o agent-device é muito mais rápido. Adotar o mesmo é G e intrusivo (seção 5).

**Hierarquia no iOS**

- **agent-device:** no simulador, uma ponte AX compilada localmente; no aparelho físico, XCTest via runner HTTP (pesquisa §3.1).
- **Mo baile:** `GET /source` do WDA, via Appium (`adapters/ios_wda.py:89-93`).
- **Leitura:** fora do escopo de persistência.

**Refs de elementos e invalidação**

- **agent-device:** `@eN` cunhadas por posição. Um ref frame com geração (`@e12~s3`) expira antes de qualquer efeito no aparelho, e a primeira geração da sessão começa num número aleatório (pesquisa §3.2; `clone: src/daemon/session-snapshot.ts:77`).
- **Mo baile:** não há refs. O front manda coordenadas e o motor resolve contra `current_xml` (`server.py:1019-1031`, `:747-755`). A época só protege a troca de aparelho (`server.py:362-375`). Uma leitura assíncrona substitui a árvore sem avisar o front (`server.py:1308-1323`).
- **Leitura:** a ideia de geração cabe e custa pouco (M6).

**Ações e espera**

- **agent-device:** informa despacho, não chegada. Tem `--settle` com diff, `wait` por seletor e erros tipados com evidência (pesquisa §3.3).
- **Mo baile:** `input.tap`/`input.text` (`server.py:757-776`); a digitação no iOS não está exposta (`:769`). A notificação `stream.settled` sai do espelho (`server.py:821`). O runner espera tempos fixos (`flows.py:339,368`).
- **Leitura:** o agent-device está à frente. No Mo baile isso é PB4/A3.

**Gravação e replay de fluxo**

- **agent-device:** formato `.ad` em texto com cadeia de seletores e `# agent-device:target-v1 {...}`. O replay verifica a identidade antes de agir e diverge com sugestões. A publicação é atômica e exclusiva (pesquisa §4.8).
- **Mo baile:** os passos vivem em memória (`services/codegen.py:34`). `flow.run` gera um script Python temporário que toca **só por coordenada** (`flows.py:241-316`). Não há formato de fluxo salvo (PB3).
- **Leitura:** a maior distância entre os dois. Adapto o conceito de identidade, não o formato (M5b, M9).

**Codegen**

- **agent-device:** não gera Page Object. Exporta `.ad` → Maestro YAML (pesquisa §4.8).
- **Mo baile:** Page Object Python com ranking de localizadores no modo `auto` (`server.py:1034-1041`). `codegen.save` grava `pages/` e `locators/` (`server.py:1087-1114`).
- **Leitura:** o Mo baile atende melhor o seu público, que é QA escrevendo teste Appium.

**Logs**

- **agent-device:** `daemon.log`, `events.ndjson` v1 redigido com rotação de 5 MiB + 1, `requests/<id>.ndjson` em caso de erro, `app.log` com rotação e regex de redação, e erros com `diagnosticId` + `logPath` (pesquisa §4.4-§4.6).
- **Mo baile:**
  - o motor escreve no stderr (`server.py:1721-1726`), e o front repassa ao próprio stderr (`EngineClient.swift:158-166`);
  - o Appium anexa sem rotação (`appium.py:125-139`);
  - o log bruto do CFNetwork tem 5 MB + 1 (`ios_cfnetwork.py:55-56,425-431`);
  - o erro interno manda 3 quadros de traceback ao front (`server.py:1529-1534`).
- **Leitura:** o agent-device está muito à frente. Cabe sem conflito de arquitetura (M3).

**Rede**

- **agent-device:** sem proxy nem interceptação TLS. `network dump` interpreta HTTP presente no `app.log`, com limite de 4.000 linhas e 200 entradas (pesquisa §4.3).
- **Mo baile:**
  - proxy próprio em loopback, com túnel CONNECT sem MITM, teto de corpo de 256 KB e histórico de 2.000 (`adapters/proxy.py:1-21,48-56,202-277`);
  - HTTPS de app em debug via CFNetwork (iOS) e OkHttp no logcat (Android) (ADR 0004);
  - redação na entrada (`security/redaction.py`).
- **Leitura:** o Mo baile está à frente.

**Analytics**

- **agent-device:** não tem.
- **Mo baile:** Firebase via logcat e `os_log`, histórico de 5.000 (`adapters/analytics_logcat.py:43,160`), mais a aba Relatório (`services/report/`).
- **Leitura:** o Mo baile está à frente.

**Desempenho**

- **agent-device:** snapshot quente de 86-96 ms no iOS Simulator e 5,8 ms no helper Android (pesquisa §5). Tem orçamento de bytes de saída testado.
- **Mo baile:** o espelho manda PNG em base64 dentro do JSON, a 3,5 fps e com 900 px de largura (`server.py:79-82,378-391`, `config.py:66`). O dump do Android leva de 1 a 10 s, segundo `pontos-de-melhoria-2026-10-05.md` (item 9).
- **Leitura:** o agent-device está à frente. Fora do foco deste documento (F1 em `docs/MELHORIAS_2026-10-09.md`).

**Segurança e redação**

- **agent-device:** redação central por chave e padrão, com strings cortadas em 400 caracteres; 0600/0700; recusa de symlink; identidade de processo por pid + start time (pesquisa §4.11, §4.14).
- **Mo baile:**
  - redação HTTP mais rica, com headers, JSON, form e URL, incluindo `cpf`/`cnpj`/`cvv` (`security/redaction.py:22-60`);
  - `MOBAILE_REDACT=0` desliga tudo de uma vez (`:76-78`);
  - o diretório de runtime tem 0700 e os arquivos 0600, com `O_NOFOLLOW` (`security/paths.py:21-42`);
  - o cache do OCR tem 0700 (`adapters/vision_ocr.py:71-77`).
- **Leitura:** empate em conceito. O Mo baile tem lacunas pontuais (seção 3.4).

**Testes**

- **agent-device:** 1.815 arquivos de teste TS e 129 Swift, com Stryker, fuzz, contratos golden entre linguagens e teste de economia de saída (pesquisa §7).
- **Mo baile:** suítes `unit`, `contract` e `integration` no motor. As fixtures do contrato saem do próprio motor e são decodificadas pelo Swift (`docs/ARQUITETURA.md:67-76`).
- **Leitura:** o padrão de contrato entre linguagens é equivalente. O agent-device tem muito mais profundidade.

**Empacotamento**

- **agent-device:** pacote npm com APKs pré-compilados; runner XCUITest compilado localmente e cacheado por manifesto de conteúdo (pesquisa §6, §4.10).
- **Mo baile:** o `.app` carrega uma cópia do motor e usa o Python do sistema (`AGENTS.md`, item 4). O binário de OCR fica em cache pelo hash da fonte (`vision_ocr.py:97-104`).
- **Leitura:** o cache de OCR do Mo baile já segue a ideia de "chave por conteúdo". O resto é o item A1 de `docs/MELHORIAS_2026-10-09.md`.

---

## 3. Persistência de dados (foco principal)

### 3.1 Inventário: o que o Mo baile coleta e onde guarda

Os campos de cada ficha:

- **Onde e formato:** caminho e tipo de arquivo.
- **Atomicidade e permissão:** como o arquivo é escrito e com que modo.
- **Retenção:** quanto fica guardado e quem apaga.
- **Esquema:** se o formato tem campo de versão.
- **Depois de uma queda:** o que sobra ou se perde quando o motor morre sem `shutdown()`, por SIGKILL, crash ou Mac reiniciado.

**1. Hierarquia (XML e elementos)**

- **Onde e formato:** só em memória, em `current_xml` (`server.py:227,373`) e na lista de elementos do front. No aparelho, um XML temporário que é apagado depois da leitura (`adb.py:42-44,245-281`).
- **Atomicidade e permissão:** não se aplica.
- **Retenção:** a última árvore.
- **Esquema:** não se aplica.
- **Depois de uma queda:** perde-se, mas um novo dump recupera.

**2. Screenshot e quadro do espelho**

- **Onde e formato:** PNG em base64, inline na resposta e na notificação (`server.py:378-391,636-646,814`). Não achei gravação em disco no motor.
- **Atomicidade, permissão, retenção e esquema:** não se aplicam.
- **Depois de uma queda:** não se aplica.

**3. Gravação de tela**

- **Onde e formato:** MP4 em `~/Movies/Mo baile/mobaile-<plat>-<ts>.mp4` (`adapters/screen_recorder.py:54,81-83`). No Android, um intermediário em `/sdcard/mobaile-<ts>.mp4` que só é puxado no `stop` (`:92,151-152,187-200`). No iOS, o `simctl` escreve direto no destino com `--force` (`:87-90`).
- **Atomicidade e permissão:** escrita pela ferramenta externa, com o umask padrão.
- **Retenção:** sem limite. É conteúdo da pessoa.
- **Esquema:** não se aplica.
- **Depois de uma queda:**
  - no Android, o MP4 fica no `/sdcard` e ninguém registra que ele existe;
  - no iOS, o MP4 fica sem índice: o próprio código avisa que só o `stop` fecha o arquivo (`server.py:1649-1652`);
  - o processo `simctl` ou `adb shell screenrecord` pode seguir órfão (inferência: `Popen` sem `start_new_session`, sem registro).

**4. Passos gravados**

- **Onde e formato:** `CodeGenerator.steps` em memória (`services/codegen.py:34`), com cópia em `state.steps` no front.
- **Atomicidade, permissão e retenção:** não se aplicam.
- **Esquema:** nenhum.
- **Depois de uma queda:** perdem-se no motor. O front continua mostrando a lista antiga, porque o snapshot de restauração não inclui passos (`EngineSession.swift:265-272,381-413`), e `flow.run` responde "Nenhum passo gravado" (`server.py:1336-1338`). É o PB3.

**5. Script do runner de fluxo**

- **Onde e formato:** `$TMPDIR/mobaile-runtime-<uid>/flow_runner_<uuid>.py`, com os passos embutidos como JSON, **inclusive `input_text` em claro** (`flows.py:146,151,176,391-393`).
- **Atomicidade e permissão:** escrita direta, sem tmp + rename. Arquivo 0600 com `O_NOFOLLOW` em diretório 0700 (`security/paths.py:21-42`). O comentário em `:35` fala em `O_EXCL`, mas a flag não é usada (`:36`).
- **Retenção:** apagado no `finally` da execução (`flows.py:481-485`).
- **Esquema:** não se aplica.
- **Depois de uma queda:** o arquivo fica, com o texto digitado dentro. Nada limpa na subida.

**6. Page Objects**

- **Onde e formato:** `.py` em `~/Documents/Mo baile/{pages,locators}/<chave>.py`, ou na pasta que a pessoa escolher (`server.py:1095-1111`).
- **Atomicidade e permissão:** `write_text` direto, não atômico, que **sobrescreve sem aviso**. Umask padrão.
- **Retenção:** é conteúdo da pessoa.
- **Esquema:** não se aplica, porque é código.
- **Depois de uma queda:** uma queda no meio da escrita deixa o `.py` truncado (inferência: `write_text` trunca antes de escrever).

**7. Relatório de tagueamento exportado**

- **Onde e formato:** board Excalidraw, HTML, Markdown e TSV em `~/Documents/Mo baile/Relatórios/<projeto>-<plat>-<AAAAMMDD-HHMMSS>/`, ou na pasta escolhida (`services/report/service.py:239-273`).
- **Atomicidade e permissão:** `write_text` direto, sobrescrevendo na pasta escolhida. Umask padrão.
- **Retenção:** sem limite. É conteúdo da pessoa.
- **Esquema:** o board segue o formato do Excalidraw (`board.py:281`). Não há carimbo da versão do Mo baile nem do gerador.
- **Depois de uma queda:** o último relatório vivia só em memória (`service.py:96,170-171`). Com `source=session`, os eventos também (`server.py:1439-1445`), e a auditoria não pode ser refeita.

**8. Rascunho de spec (OCR)**

- **Onde e formato:** JSON + `.revisao.md` em `~/Documents/Mo baile/Specs/` (`service.py:311-318`).
- **Atomicidade e permissão:** `unique_path` testa a existência e depois escreve (`security/files.py:76-84`): é um TOCTOU, sem escrita atômica. Umask padrão.
- **Retenção:** é conteúdo da pessoa.
- **Esquema:** só há `versao_especificacao`, que é a versão do conteúdo e não do esquema (`domain/report.py:87`).
- **Depois de uma queda:** pode sobrar arquivo parcial (inferência).

**9. Tráfego HTTP**

- **Onde e formato:**
  - em memória: `deque(maxlen=2000)` (`proxy.py:54,503`) e uma `event_queue` de 4.000 sem consumidor no RPC (`:502,538-543`);
  - no front, um teto de 1.000 (`EngineSession.swift:1420-1430`);
  - em disco, só pelo HAR exportado pelo Swift (`App/Exporters.swift:19-29`).
- **Atomicidade e permissão:** o HAR sai por `data.write(to:)` sem `.atomic` (`Exporters.swift:161-172`).
- **Retenção:** 2.000 eventos no motor e 1.000 no front. O descarte é silencioso.
- **Esquema:** HAR 1.2. O `creator.version` tem "2.0" fixo (`Models/HARExporter.swift:71-74`).
- **Depois de uma queda:** tudo se perde no motor. O front guarda até 1.000.

**10. Log bruto do CFNetwork (iOS)**

- **Onde e formato:** texto em `~/Library/Logs/MoBaile/cfnetwork-diagnostics.log` (`ios_cfnetwork.py:55`).
- **Atomicidade e permissão:** append com o umask padrão, sem `O_NOFOLLOW`. A rotação é um `replace` para `.log.1` (`:425-431`).
- **Retenção:** 5 MB + 1 geração (`:56,428-429`).
- **Esquema:** nenhum.
- **Depois de uma queda:** fica. **Vaza segredo**, ver a seção 3.4.

**11. Eventos de analytics**

- **Onde e formato:**
  - em memória: `deque(maxlen=5000)` (`analytics_logcat.py:43,160`) e uma `event_queue` **sem limite e sem consumidor** no motor RPC (`:159,401`);
  - no front, um teto de 1.000;
  - em disco, só pelo JSON exportado pelo Swift (`Exporters.swift:69-90`).
- **Atomicidade e permissão:** o export não é atômico.
- **Retenção:** 5.000 no motor e 1.000 no front, com descarte silencioso. A fila sem limite cresce sem teto.
- **Esquema:** nenhum.
- **Depois de uma queda:** perdem-se no motor. A auditoria com `source=session` fica impossível.

**12. Log do motor**

- **Onde e formato:** texto no stderr (`server.py:1721-1726`) → stderr do app (`EngineClient.swift:158-166`).
- **Atomicidade, permissão e retenção:** não se aplicam, porque não vai para arquivo.
- **Esquema:** não se aplica.
- **Depois de uma queda:** some quando o app é aberto pelo Finder (P0 4 de `pontos-de-melhoria-2026-10-05.md`). Não há `faulthandler`: um grep por `faulthandler` não devolve nada no repositório.

**13. Log do Appium**

- **Onde e formato:** texto em `~/Library/Logs/mobaile-appium.log` (`appium.py:125-128`).
- **Atomicidade e permissão:** append com umask padrão. O Appium sobe sem `--log-level`, no nível padrão (`:134-140`).
- **Retenção:** sem limite.
- **Esquema:** não se aplica.
- **Depois de uma queda:** fica e cresce.

**14. Log de execução aberto no editor**

- **Onde e formato:** `mobaile-flow-run.log` no temporário do front (`Exporters.swift:148-157`).
- **Atomicidade e permissão:** escrita com `atomically: true`.
- **Retenção:** um arquivo, sobrescrito a cada vez.
- **Esquema:** não se aplica.
- **Depois de uma queda:** não se aplica. O conteúdo já vem mascarado do motor (`flows.py:258-259,416-419`).

**15. Configurações**

- **Onde e formato:**
  - o motor lê só variáveis de ambiente (`config.py:58-77`);
  - o front usa `UserDefaults` (`App/AppState.swift:269-270`, `Models/Enums.swift:37`, `Views/Settings/SettingsView.swift:24`, `Theme/ThemeManager.swift:24-31`) e `@SceneStorage` (`Views/MainWindow/ContentView.swift:230-231`).
- **Atomicidade e permissão:** a cargo do sistema.
- **Retenção:** não se aplica.
- **Esquema:** nenhum, o que é aceitável para preferências.
- **Depois de uma queda:** sobrevivem.

**16. Estado de sessão**

- **Onde e formato:** plataforma, aparelho e época em memória (`server.py:223-238`). O front guarda um snapshot para reinício (`EngineSession.swift:265-316`).
- **Atomicidade, permissão, retenção e esquema:** não se aplicam.
- **Depois de uma queda:** o front devolve aparelho e espelho. **Não** há registro do que foi mudado no aparelho.

**17. Mudanças feitas no aparelho**

O registro mora no próprio aparelho:

- `http_proxy`, `captive_portal_mode` e `adb reverse` (`adb.py:362-411`);
- `log.tag.*`, `logcat -G 8M` e `debug.firebase.analytics.app` (`analytics_logcat.py:184-207`).

Nenhum registro no Mac. `analytics.stop` não desfaz nada disso (`:311-335`), e o `captive_portal_mode` anterior é apagado, não restaurado (`adb.py:410`). Depois de uma queda, **o aparelho pode ficar sem internet** e com debug do Firebase ligado, o que manda dado de teste ao BigQuery (P0 2 do pesquisador em 05/10).

**18. Cache do OCR**

- **Onde e formato:** binário + `.swift` em `~/Library/Caches/Mo baile/ocr/`, com chave `sha256(fonte)[:12]` (`vision_ocr.py:71-104`).
- **Atomicidade e permissão:** a fonte é gravada com `write_text` e depois `chmod 0600`, num diretório 0700.
- **Retenção:** binários de versões antigas nunca são apagados.
- **Esquema:** a chave é o hash da fonte.
- **Depois de uma queda:** fica. O binário é reaproveitado só por existir e ser executável (`:101`).

**19. Processos filhos**

- **Onde e formato:** só em memória (`_process`/`_proc` em cada adapter). O Appium sobe com `start_new_session=True` (`appium.py:134-140`).
- **Atomicidade, permissão, retenção e esquema:** não se aplicam.
- **Depois de uma queda:** o Appium continua no ar. O motor seguinte o trata como "do usuário" e nunca o derruba (`appium.py:115-116,154-166`). Isso é inferência, sustentada pelo código.

Fora do inventário, também é fato que `flows.generate_hidden_runner_script(output_path=...)` grava sem `O_NOFOLLOW` (`flows.py:384-389`) e não tem chamador no motor nem no Tk: o grep por `output_path` só acha a definição.

### 3.2 Comparação item a item com o modelo do agent-device

**a) Estado vivo só em memória, disco só para evidência**

- **agent-device:** o `SessionStore` é um `Map` em memória. O diário "is an observability spine, **not** a source of truth". A reanexação "does not rehydrate `SessionState`" (pesquisa §4.1; `clone: docs/adr/0018-unified-event-journal.md:43`, `docs/adr/0019-request-bound-platform-runtime.md:484`).
- **Mo baile:** já é só memória (itens 1, 4, 9, 11 e 16 da seção 3.1). Mas **não deixa evidência nenhuma**: não há diário, não há registro de recurso e o log some.
- **Leitura:** o princípio é o mesmo; falta a metade "evidência". A sessão persistida (PB3) parece contrariar o agent-device, mas não contraria. Ela é um documento que a pessoa restaura explicitamente (`session.restore`, motor "desarmado"), o equivalente ao `.ad` publicado, e não uma reidratação automática de estado.

**b) NDJSON versionado com rotação e `.window.json`**

- **agent-device:** `events.ndjson` v1, redigido, com rotação de 5 MiB + 1. Um sidecar com digest da primeira linha dá cursores absolutos estáveis, e a escrita passa por uma fila serial por caminho (pesquisa §4.4; `clone: packages/session-journal/src/session-event-log-window.ts:33-37`, `session-event-log.ts:24,68-91`).
- **Mo baile:** não há diário. A única rotação é a do log bruto do CFNetwork (`ios_cfnetwork.py:428-429`), sem versão nem permissão.
- **Leitura:**
  - **adotar** NDJSON v1 com rotação simples para o log do motor (M3) e, se o dono quiser, para a captura (M8);
  - **descartar o `.window.json`:** ele existe porque agentes leem o diário paginado por cursor. No Mo baile o front recebe tudo por notificação e não pagina o disco.

**c) Escrita atômica com tmp + rename + fsync**

- **agent-device:** `publishFileSync`, com temporário irmão + `rename` ou `link` exclusivo, e `publishDurableFileSync`, com `wx` 0600 + `fsync` + `rename` + `fsync` do diretório (pesquisa §4.11; `clone: packages/host-kit/src/internal/atomic-file.ts:18-82`).
- **Mo baile:** nada é atômico na branch atual. Usam `write_text` direto: `server.py:1110`, `service.py:269,316,318`, `ios_cfnetwork.py:430` e `vision_ocr.py:104`. O padrão completo, com `mkstemp`, `fsync`, `os.replace` e `fsync` do diretório, **já existe** no `session_store.py` da branch wip `worktree-agent-ad7d472dd0b5a7130`, ainda não integrado.
- **Leitura:** adotar como primitiva única em `security/` (M2) e fazer o `session_store` usá-la.

**d) Permissões 0600/0700 e recusa de symlink**

- **agent-device:** 0600 em registros, claims, token e descritores; 0700 em diretórios; `lstat` recusa symlink no diário e no `app.log` (pesquisa §4.11, §4.14).
- **Mo baile:**
  - certo no diretório de runtime e no OCR (`paths.py:21-42`, `vision_ocr.py:71-77`);
  - errado nos logs, com umask padrão: `ios_cfnetwork.py:427-431` e `appium.py:127-128`;
  - `secure_runtime_dir` usa `stat` (segue symlink) e não confere o dono (`paths.py:23-28`). No macOS, `tempfile.gettempdir()` é o `$TMPDIR` do usuário, então o risco é baixo (inferência).
- **Leitura:** adotar nos diretórios **do motor**: `Application Support`, `Logs`, runtime e cache. Nos diretórios **da pessoa** (`~/Documents/Mo baile` ou pasta escolhida), recusar symlink quebraria quem liga `pages/` ao repositório de testes; ali vale escrever atômico no caminho resolvido.

**e) Descritores de recurso para recuperar após crash**

- **agent-device:** envelope `{envelopeVersion:1, resourceKind, sessionId, device, owner, fence, lifecycle, descriptor:{version, body}}`. Na subida, a recuperação é cercada (fenced), e descritor inválido é **mantido como evidência**. Também há `owned-processes.json` v1 com pid + start time (pesquisa §4.7; `clone: packages/contracts/src/durable-resource-envelope.ts:14-29`, `packages/host-kit/src/internal/owned-process-record.ts:62-74`).
- **Mo baile:** nada. Há três classes de órfão:
  - mudanças no aparelho (item 17 da seção 3.1);
  - processos (item 19);
  - MP4 no `/sdcard` (item 3).
- **Leitura:** adaptar numa forma bem menor: um registro por aparelho e um de processos, sem reanexar captura viva (M4). Reanexar `logcat` ou proxy depois de uma queda não compensa: o front já religa o que pode, e o que mexe no aparelho exige consentimento (`EngineSession.swift:375-380`).

**f) Posse de aparelho entre processos**

- **agent-device:** `~/.agent-device/device-claims/<sha256(deviceKey)>.json`, `schemaVersion: 2`, com pid + start time + token, sob lock de diretório (pesquisa §4.10; `clone: src/daemon/device/device-claim-store.ts:13-34`, `device-claim-record.ts:27-37`).
- **Mo baile:** nada. O código já admite duas instâncias, porque o nome do dump leva o pid "para evitar corrida entre duas instâncias" (`adb.py:42-44`). O app Tk e o nativo podem mexer no `http_proxy` do mesmo aparelho.
- **Leitura:** adiar a posse exclusiva até existir A9 (várias janelas, cada uma com o seu motor). O registro do M4 já carrega o pid e o start time do motor, o que basta para **avisar** que outro motor vivo mexeu no aparelho.

**g) Formato `.ad` com identidade do alvo**

- **agent-device:** texto, uma linha por comando, com cabeçalho `context platform=… device=…`. Cada ação vem precedida de `target-v1` (id, role+label, ancestrais, irmão, região de rolagem). O replay diverge em vez de escolher em silêncio (pesquisa §4.8; `clone: src/daemon/session-script-writer.ts:296,380-385`).
- **Mo baile:** o entregável é o Page Object Python. Os passos guardam `strategy` e `locator_value` (`domain/models.py:126-155`), mas o runner só usa `coords` (`flows.py:241-316`).
- **Leitura:**
  - **não** criar uma segunda linguagem de script: o público quer `.py` para o Appium;
  - **adotar a identidade do alvo** dentro do documento de sessão v1 (M5b) e usá-la no replay por localizador (M9).

**h) Redação de segredos e `--record-as`**

- **agent-device:** redação central por chave, `Bearer` e query de URL. O diário omite o que foi digitado. `fill … --record-as PASSWORD` envia o literal ao app e grava `${PASSWORD}`; sem a flag, o valor vai literal para o `.ad` (pesquisa §4.8, §4.14; `clone: docs/adr/0017-parameterized-recorded-inputs.md:21-44`, `src/daemon/session-state.ts:262`).
- **Mo baile:**
  - redação HTTP mais completa que a do agent-device (`redaction.py:22-153`);
  - o PB1 tirou o texto digitado do `flow.log` (`flows.py:258-259`, `RODADA_2026-10-05_PENDENCIAS.md`).
  - Lacunas:
    - o log bruto do CFNetwork (3.4);
    - `input_text` em claro no script temporário (item 5 da seção 3.1);
    - `passive.text` leva o texto lido do campo ao front (`server.py:1261-1264`);
    - parâmetros de analytics sem redação nenhuma (`analytics_logcat.py` só importa `validate_device_id` da camada de segurança, `:36`);
    - `MOBAILE_REDACT=0` desliga tudo, inclusive o que vai para disco (`redaction.py:76-78`).
- **Leitura:**
  - adotar `sensitive` (já na wip) mais a parametrização `${VAR}` (M5b);
  - tirar o segredo do disco do runner (M2/M5a);
  - a redação de analytics é uma pergunta ao dono (seção 6), porque a auditoria compara valores.

**i) Devolver só o caminho para artefatos pesados**

- **agent-device:** screenshot, vídeo, perf e logs voltam como caminho + metadados, nunca inline (pesquisa §4.9, §4.13).
- **Mo baile:**
  - **já faz** para gravação (`screen_recorder.py:165-170`), export do relatório (`service.py:273`) e Page Object (`server.py:1114`);
  - quadro e screenshot vão inline por desenho, porque o front os desenha na hora;
  - o JSON de analytics é montado no Swift a partir da lista limitada a 1.000.
- **Leitura:** o Mo baile já está bem. A exceção útil é mover o export de analytics para o motor, devolvendo o caminho (M7). O motivo é a consistência: a auditoria lê até 5.000 eventos e o export, até 1.000. Economia de bytes não é a questão.

### 3.3 Recuperação após queda: cenário por cenário

Considera-se SIGKILL ou crash do motor, sem passar por `shutdown()`.

**Proxy ligado no Android**

- **Hoje:** o front reinicia o motor e chama `proxy.stop` **se o mesmo aparelho continuar selecionado** (`EngineSession.swift:383-396`).
- **Falha:** se o app fechou, se a pessoa trocou de aparelho ou se o cabo saiu, `http_proxy` fica apontando para uma porta morta, e o aparelho fica sem internet.
- **Com o padrão do agent-device:** o registro por serial, gravado **antes** de mudar, é desfeito na próxima subida ou ao reconectar aquele serial, com cerca: só desfaz se o valor atual for o que o Mo baile pôs.

**Escuta de analytics no Android**

- **Hoje:** nada é desfeito, nem mesmo no `stop` normal (`analytics_logcat.py:311-335`).
- **Falha:** `debug.firebase.analytics.app` fica ligado e o buffer do logcat fica em 8 MB.
- **Com o padrão do agent-device:** o mesmo registro, com `previous` lido por `getprop` antes do `setprop`.

**Gravação Android**

- **Hoje:** o MP4 fica em `/sdcard/mobaile-<ts>.mp4` (`screen_recorder.py:92`).
- **Falha:** o arquivo ocupa espaço no aparelho e o vídeo se perde.
- **Com o padrão do agent-device:** uma entrada `remote_file` no registro. Na subida, o motor oferece "puxar o vídeo da sessão anterior" ou apagar. É o análogo simplificado do "stop-and-collect" (pesquisa §4.7).

**Gravação iOS**

- **Hoje:** o `simctl recordVideo` pode ficar órfão (inferência).
- **Falha:** o MP4 fica sem índice e o processo segue rodando.
- **Com o padrão do agent-device:** `owned-processes.json` com pid + start time + argv; na subida, um SIGINT no órfão fecha o MP4.

**Appium iniciado pelo motor**

- **Hoje:** sobrevive (`start_new_session=True`), e o motor seguinte acha que é do usuário (`appium.py:115-116,154-166`).
- **Falha:** a porta 4723 fica ocupada indefinidamente, e o log cresce sem rotação.
- **Com o padrão do agent-device:** `owned-processes.json`. Um processo nosso e vivo é retomado como nosso, e o motor o derruba ao fechar.

**Passos gravados**

- **Hoje:** perdem-se no motor; o front mostra a lista antiga (`EngineSession.swift:265-272`).
- **Falha:** rodar ou salvar usa uma lista diferente da que está na tela.
- **Com o padrão do agent-device:** sessão v1 em disco, com restauração explícita (M5b).

**Execução de fluxo em andamento**

- **Hoje:** o script com o texto digitado fica no `$TMPDIR` (`flows.py:481-485` não roda).
- **Falha:** a senha fica em disco até o sistema limpar o `$TMPDIR`.
- **Com o padrão do agent-device:** passos pelo stdin, mais limpeza de `flow_runner_*.py` órfãos na subida (M5a).

**Captura de analytics para auditoria**

- **Hoje:** perde-se no motor (`server.py:1439-1445`).
- **Falha:** é preciso refazer o roteiro de teste.
- **Com o padrão do agent-device:** diário NDJSON opt-in, lido por `report.audit source=file` (M8).

### 3.4 Lacunas e riscos reais

1. **Vazamento de segredo em disco (verificado).** `_mask_block` (`ios_cfnetwork.py:314-323`) só mascara linhas no formato `Nome: valor` (`_HEADER_LINE`, `:70`). A linha `Message: GET https://…?token=…` e o `{url = …}` estão na lista de exceções `_NOT_HEADERS` (`:74-80`). Os headers de resposta vêm no formato de dicionário `"Set-Cookie" = ( "…" );`, que o regex não reconhece.
   - **Como verifiquei:** alimentei o `CFNetworkDiagParser` real com uma amostra.
     - `access_token=SEGREDOQUERY` e `session=SEGREDOCOOKIE` aparecem no bloco bruto.
     - `Authorization: Bearer` sai redigido.
     - O `NetworkEvent` sai correto nos dois casos: URL e `Set-Cookie` redigidos.
   - **Por que passou:** o teste existente só confere o `Authorization` da requisição (`engine/tests/unit/test_ios_cfnetwork.py:58-60`).
   - **Agravante:** o arquivo nasce com o umask padrão, e o diretório `~/Library/Logs/MoBaile` também.
2. **Segredo em arquivo temporário que sobrevive à queda.** `input_text` vai em claro para o script do runner (`flows.py:146,176`) e só é apagado no `finally` (`:481-485`). O caminho do script volta ao front em `flow.run` (`server.py:1391`).
3. **Escrita não atômica que sobrescreve trabalho.**
   - `codegen.save` trunca e reescreve `pages/<chave>.py` e `locators/<chave>.py` sem aviso (`server.py:1105-1111`). Uma queda ou disco cheio no meio deixa o Page Object da pessoa truncado (inferência).
   - O export do relatório tem o mesmo problema (`service.py:265-270`).
4. **Crescimento sem limite.**
   - `analytics.event_queue` não tem limite nem consumidor no motor RPC (`analytics_logcat.py:159,401`); a PB5 já apontou isso.
   - `mobaile-appium.log` não tem rotação (`appium.py:125-128`).
   - O cache de OCR acumula binários de versões antigas (`vision_ocr.py:97-104`).
   - Os exports da pessoa não têm limite, e devem continuar sem, porque são dela.
5. **Ausência de versão de esquema.** Nenhum arquivo próprio do Mo baile tem campo de versão: spec gerada pelo OCR, relatório exportado, log bruto. Pela política, mudar "formato de arquivo salvo" de forma incompatível sobe a MAIOR (`docs/VERSIONAMENTO.md`, tabela "Qual número subir"). Sem versão no arquivo, não há como detectar nem migrar. O HAR traz `creator.version` "2.0" fixo, com o app em 3.4.0 (`HARExporter.swift:74`).
6. **Mudança no aparelho sem registro.** É o item 17 da seção 3.1. Era P0 em 05/10 e continua aberto: o grep por `debug.firebase.analytics.app` só acha o `setprop`, nunca a volta para `.none.`.
7. **Processos órfãos.** É o item 19 da seção 3.1. Isso contradiz em parte `docs/ARQUITETURA.md:58-60`, que diz que o stdio "elimina a classe de bug em que um processo órfão continua segurando o adb". A frase vale para o motor, não para os filhos que ele cria.
8. **Descarte silencioso.** O histórico do motor (2.000/5.000) e o do front (1.000) descartam o mais antigo sem avisar. O comentário em `server.py:1431-1432` diz que a auditoria da sessão usa "o mesmo conteúdo que 'Exportar JSON' gravaria". Isso deixa de ser verdade depois de 1.000 eventos.
9. **Diagnóstico inexistente em disco.** O erro interno manda o traceback ao front (`server.py:1529-1534`), mas não há arquivo nem identificador para casar o relato do QA com o log.

---

## 4. Melhorias validadas

Ordem por retorno sobre esforço. A versão segue `docs/VERSIONAMENTO.md`:

- **patch:** correção ou ajuste interno.
- **minor:** recurso novo compatível, inclusive campo ou método novo no contrato com `PROTOCOL_VERSION` em 2.
- **major:** protocolo incompatível, formato salvo incompatível ou remoção.

O vínculo com pendências usa os códigos de [`RODADA_2026-10-05_PENDENCIAS.md`](../../RODADA_2026-10-05_PENDENCIAS.md) (PBn, An, Bn, Cn), de [`MELHORIAS_2026-10-09.md`](../../MELHORIAS_2026-10-09.md) (Dn, Fn, An, Rn, Qn) e do relatório do pesquisador de 05/10 ("P0 n").

### M1. Redigir de verdade o log bruto do CFNetwork

| | |
|---|---|
| **Problema** | O log bruto em disco guarda query de URL e headers de resposta sem redação. Verificado; ver a seção 3.4, item 1. |
| **Padrão do agent-device** | Redação única na fronteira do que vai para disco (ADR 0018, pesquisa §4.14); `app.log` com `AGENT_DEVICE_APP_LOG_REDACT_PATTERNS` aplicado **na escrita** e recusa de symlink (pesquisa §4.6; `clone: src/daemon/app-log-files.ts:20-43`). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P. Risco baixo, porque só muda o que vai para o arquivo bruto. Impacto alto: é credencial de cliente em disco. |
| **Como testar** | Regressão em `engine/tests/unit/test_ios_cfnetwork.py` com `Set-Cookie` no formato de dicionário, `?access_token=` em `Message:` e em `{url = …}`. Ela **falha hoje** (reproduzido na seção 3.4) e passa depois. O teste também confere `stat.S_IMODE == 0o600` do arquivo com `HOME` temporário. Encaixa no Q3 (fuzz dos parsers): uma propriedade Hypothesis "nenhum valor de header sensível sobrevive no bloco bruto". |
| **Versão** | patch |
| **Pendências** | Q3 de `MELHORIAS_2026-10-09.md`; "privacidade fora da redação HTTP" (item 8 de 05/10). |

Proposta, em `adapters/ios_cfnetwork.py`:

1. Em `_mask_block` (`:314-323`):
   - aplicar `redact_url` a toda URL do bloco, com regex `https?://\S+`, inclusive nas linhas de `_NOT_HEADERS`;
   - redigir os pares `"Nome" = ( "valor" );` quando `Nome` é sensível, inclusive na forma multilinha que `_headers_from_dict` já sabe juntar (`:281-311`).
2. Gravar pela primitiva de M2: diretório 0700 e arquivo 0600 com `O_APPEND|O_NOFOLLOW`.
3. A redação do arquivo bruto **não** obedece a `MOBAILE_REDACT=0`, que fica só para a tela. Isso é pergunta ao dono (seção 6).

O contrato não muda.

### M2. Primitiva única de escrita segura (`security/storage.py`)

| | |
|---|---|
| **Problema** | Escrita não atômica que trunca o trabalho da pessoa (seção 3.4, item 3). Permissões frouxas nos logs (seção 3.2 d). TOCTOU no `unique_path` (`security/files.py:76-84`). O padrão correto só existe numa branch não integrada. |
| **Padrão do agent-device** | `publishFileSync`/`publishDurableFileSync` (`clone: packages/host-kit/src/internal/atomic-file.ts:18-82`): temporário irmão criado com `wx` 0600, `fsync`, `rename` ou `link` exclusivo ("first writer wins") e `fsync` do diretório. Recusa destino que é symlink (`:137-158`). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P. Risco baixo a médio: `os.replace` troca o inode, e quem tinha um hard link para o `.py` deixa de vê-lo atualizado (raro). Impacto médio a alto: deixa de existir Page Object truncado, e é a base de M1, M3, M4 e M5. |
| **Como testar** | Testes unitários da primitiva: queda simulada entre a escrita e o `replace` (monkeypatch de `os.replace` levantando erro) mantém o arquivo anterior intacto e não deixa `.tmp`; destino symlink recusado em diretório do motor e seguido em diretório da pessoa; modo 0600/0700; `exclusive=True` com o destino já existente dá erro. Um teste de contrato de `codegen.save` cobre os mesmos casos. |
| **Versão** | patch. Sem mudança de contrato. Sobrescrever continua sendo o comportamento do `codegen.save`. |
| **Pendências** | Habilita PB3 (a `_write_atomic` da wip passa a usar a primitiva) e A2 (lixeira em disco). |

Proposta: o módulo novo `engine/src/mobaile/security/storage.py`, só com biblioteca padrão. Nenhuma dependência nova, o que importa para o Python do app (`AGENTS.md`, item 4). Ele expõe:

- **`ensure_private_dir(path)`:** `mkdir(0o700)`, `lstat` recusando symlink, dono igual a `os.getuid()` e `chmod` corretivo.
- **`write_atomic(path, data, *, mode=0o600, exclusive=False, owned=True)`:**
  - cria um temporário no mesmo diretório com `mkstemp`;
  - grava e faz `fsync`;
  - publica com `os.replace`, ou com `os.link` + `unlink` quando `exclusive`;
  - faz `fsync` do diretório, em best-effort.
  - Com `owned=True` (diretório do motor), recusa destino symlink. Com `owned=False` (diretório da pessoa), escreve no caminho resolvido.
- **`PrivateRotatingLog(path, max_bytes=5 MiB, keep=1)`:** append com `O_APPEND|O_NOFOLLOW|O_CREAT` em 0600 e rotação por `os.replace` para `.1`.

Onde aplicar:

- `codegen_save`, com `owned=False` (`server.py:1105-1111`);
- `ReportService.export`, com `owned=False` (`service.py:265-270`);
- `import_prints`, com `exclusive=True` em vez de `unique_path` + `write_text` (`service.py:314-318`);
- o fonte do OCR (`vision_ocr.py:104`);
- o log bruto do CFNetwork (M1).

Também entram duas correções pontuais:

- `secure_runtime_dir` (`security/paths.py:21-29`) passa a usar `ensure_private_dir`, e o comentário sobre `O_EXCL` (`:35`) é corrigido.
- O ramo morto `output_path` de `flows.py:384-389` é removido.

### M3. Log do motor em arquivo, `faulthandler` e `diagnostic_id`

| | |
|---|---|
| **Problema** | O log do motor some no app aberto pelo Finder (`EngineClient.swift:158-166`). Não há `faulthandler`. O erro interno leva um traceback ao front e nenhum identificador (`server.py:1529-1534`). O log do Appium não tem rotação nem nível de log (`appium.py:125-139`). |
| **Padrão do agent-device** | `daemon.log` do ciclo de vida. Diagnóstico por requisição gravado **sempre em erro**, com `diagnosticId` e `logPath` devolvidos no erro. Strings redigidas e cortadas: 400 caracteres, e 8.192 para stderr (pesquisa §4.5; `clone: packages/kernel/src/redaction.ts:2-9,71-78`). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P. Risco baixo. Impacto alto: todo relato "travou" passa a ter evidência, e isso destrava a distribuição (A1). |
| **Como testar** | Teste unitário: um método que levanta exceção gera uma resposta com `data.diagnostic_id` e uma linha no `engine.log` com o mesmo id e o traceback; o arquivo é 0600; a rotação acontece ao passar o teto (com `max_bytes` pequeno); uma URL com token num `logger.info` sai redigida. Teste de contrato e `make fixtures` para o campo novo. Manual: abrir o app pelo Finder, provocar erro e achar o id em `engine.log`. |
| **Versão** | minor: campo novo e opcional em `error.data`, sem mudar `PROTOCOL_VERSION`. Exige atualizar `docs/PROTOCOLO_RPC.md` (seção "Erros") e `make fixtures`. |
| **Pendências** | P0 4 de 05/10 ("log do motor invisível"); A7 de `MELHORIAS_2026-10-09.md` (log unificado), que fica complementar: o `os.Logger` no front continua valendo. |

Proposta:

- **Arquivo do motor:** `serve()` (`server.py:1720-1727`) ganha um handler `PrivateRotatingLog` (M2) em `~/Library/Logs/Mo baile/engine.log`, com 5 MiB + 1 geração, além do stderr.
- **Filtro de redação:** um filtro de `logging` aplica `redact_url` a toda URL das mensagens.
- **Falhas fatais:** `faulthandler.enable(file=…)` num `engine-fault.log`, também 0600.
- **Identificador do erro:** em `_execute` (`server.py:1529-1534`), o erro interno ganha um `diagnostic_id` (base36 do tempo + 4 bytes hex, como o agent-device). O traceback completo vai para o log, e `data` passa a levar `{exception, diagnostic_id, log_path}`. O traceback inline pode continuar por compatibilidade, cortado em 8 KiB.
- **Appium:** passa a subir com `--log-level info` (ou `--log-filters`) e grava em `~/Library/Logs/Mo baile/appium.log`, com rotação na subida e modo 0600.

### M4. Registro durável de mudanças no aparelho e de processos do motor

| | |
|---|---|
| **Problema** | Seção 3.3, itens "proxy", "analytics", "gravação" e "Appium"; seção 3.4, itens 6 e 7. |
| **Padrão do agent-device** | Ver a lista abaixo da tabela. |
| **Proposta** | Ver as listas abaixo da tabela. |
| **Esforço, risco e impacto** | M. Risco médio, por três motivos: o registro vira estado persistido e precisa de versão; restaurar o valor errado pode quebrar a configuração de outra ferramenta, e por isso existe a cerca; e "start time" no macOS exige um `ps` por processo, só na subida. Impacto alto: aparelho sem internet e dado de teste no BigQuery do cliente. |
| **Como testar** | Ver a lista abaixo da tabela. |
| **Versão** | minor: métodos e notificação novos, aditivos. O formato do registro nasce versionado; mudar de forma incompatível depois será major, mas é um arquivo interno, e o motor pode tratar versão desconhecida como "manter e avisar", sem migrar. |
| **Pendências** | P0 2 de 05/10 ("Diário do aparelho"), quick win "desligar o debug do Firebase no stop" e C3 (desconexão abrupta). |

Padrões do agent-device que resolvem o problema:

- **Descritor durável** gravado antes do efeito, com `envelopeVersion`, dono e cerca. Na subida, a recuperação só acontece pelo dono exato, e o que é ilegível é mantido como evidência (pesquisa §4.7; `clone: packages/contracts/src/durable-resource-envelope.ts:14-29`).
- **`owned-processes.json`** v1 com pid + start time, gravado com `fsync` + `rename` (`clone: packages/host-kit/src/internal/owned-process-record.ts:62-74`).
- **Identidade de processo** por pid + start time, porque o pid sozinho não basta (pesquisa §4.11).

Proposta, camada `services` + `security`, valendo também para o Tk porque mora abaixo do RPC:

1. **Registro de mudanças no aparelho.** Um arquivo por aparelho em `~/Library/Application Support/Mo baile/state/devices/<sha256(serial)[:16]>.json`:

   ```json
   {
     "schema": "mobaile.device-ledger",
     "version": 1,
     "device_id": "…",
     "platform": "android",
     "owner": {"pid": 0, "start_time": "…", "engine_version": "3.5.0"},
     "entries": [
       {"kind": "setting", "namespace": "global", "key": "http_proxy", "previous": null, "applied": "127.0.0.1:8082", "at": "…"},
       {"kind": "reverse", "spec": "tcp:8082"},
       {"kind": "setprop", "key": "debug.firebase.analytics.app", "previous": ".none.", "applied": "com.app"},
       {"kind": "logcat_buffer", "previous": "256K", "applied": "8M"},
       {"kind": "remote_file", "path": "/sdcard/mobaile-….mp4", "purpose": "screen_recording"}
     ]
   }
   ```

   - A entrada é gravada pela primitiva de M2 **antes** do comando no aparelho, com o `previous` lido por `settings get` ou `getprop`.
   - A entrada é removida depois da reversão confirmada.

2. **Serviço `services/device_state.py`.** Ele recebe as chamadas de `adb.setup_reverse_proxy`/`teardown_reverse_proxy` (`adb.py:362-411`) e de `FirebaseAnalyticsListener.setup_props` (`analytics_logcat.py:184-207`). A porta nova vai em `ports/protocols.py`.
   - A reversão restaura o `previous` em vez de apagar (`adb.py:410`).
   - **A cerca:** só reverte se o valor atual ainda for o `applied`. Se outra ferramenta mudou o valor, mantém e avisa.
   - `analytics.stop` passa a reverter o que `setup_props` fez.

3. **Processos do motor.** O arquivo `…/state/owned-processes.json` (`{version: 1, processes: [{pid, start_time, argv0, role, device_id}]}`) é escrito quando o motor sobe Appium, `screenrecord`, `simctl recordVideo`, scrcpy ou `logcat`. Na subida:
   - um processo vivo com o mesmo start time e o mesmo `argv0` é órfão nosso: SIGINT para gravação (fecha o MP4), SIGTERM para o resto;
   - o Appium órfão pode ser **adotado**, passando a ser derrubado no `shutdown`.

4. **Contrato, aditivo.**
   - Uma notificação `device.pending_restore {device_id, entries:[{kind,key}], owner_alive}` é emitida depois do `engine.hello`, quando sobra registro de um motor morto.
   - O método `device.restore_pending {device_id}` desfaz e devolve o que foi e o que não foi revertido.
   - Se a reversão é automática ou se pergunta antes, quem decide é o dono (seção 6).

Como testar:

- **Aparelho falso:** já existe `engine/tests/unit/aparelho_falso.py`. Os cenários são:
  - ligar o proxy e matar o "motor" (descartar o objeto sem `shutdown`);
  - um motor novo encontra o registro e reverte;
  - a cerca não reverte valor alterado por terceiro;
  - `analytics.stop` volta `debug.firebase.analytics.app` para o valor anterior.
- **Processos:** um `sleep` filho registrado e o motor descartado. Na subida, ele é encerrado; já um processo com o mesmo pid e start time diferente não é tocado.
- **Integração manual:** com SIGKILL no motor e aparelho real.

### M5. Segredo fora do disco no runner (M5a) e sessão persistida v1 (M5b)

**M5a. Passos pelo stdin e limpeza de órfãos**

| | |
|---|---|
| **Problema** | `input_text` em claro no `.py` temporário, que sobrevive a uma queda (seção 3.4, item 2). |
| **Padrão do agent-device** | A issue #3260 propõe passar o valor do `fill` por stdin para tirá-lo do argv (pesquisa §4.14). Também: "never rebuilt from disk", e temporários com `cleanup` (pesquisa §4.9). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P. Risco baixo. Impacto alto em privacidade. |
| **Como testar** | Estender `engine/tests/unit/test_flow_execucao.py`, que já tem adb falso e sentinela: a sentinela digitada não aparece em nenhum arquivo sob o diretório de runtime durante a execução. Um teste de subida cria um `flow_runner_*.py` antigo e confere que ele foi removido. |
| **Versão** | patch |
| **Pendências** | PB1 (resíduo) e PB6 (o runner continua sendo o mesmo processo). |

Proposta:

- O script gerado (`flows.py:153-378`) deixa de embutir `STEPS` e passa a ler `json.load(sys.stdin)`. `FlowExecution.run` abre o filho com `stdin=PIPE` (hoje `DEVNULL`, `:442`), escreve os passos e fecha. Isso continua sem herdar o stdin do motor, que é o motivo do comentário em `:441`.
- Na subida do motor, `flow_runner_*.py` com mais de 1 h no diretório de runtime são apagados.
- **Limite residual, que precisa ser dito:** o `adb shell input text '<texto>'` continua passando o texto no argv do processo `adb` do host (`flows.py:260-263`). Isso é inerente ao adb.

**M5b. Sessão persistida v1 com texto sensível parametrizado e identidade do alvo**

| | |
|---|---|
| **Problema** | PB3: os passos morrem com o motor e o front mostra uma lista que o motor não tem (seção 3.3). PB1: o texto digitado em campo sensível precisa sair do disco e da tela. |
| **Padrão do agent-device** | Ver a lista abaixo da tabela. |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | M. A maior parte já existe, mas sem teste nem revisão. Risco médio: é formato salvo novo, que passa a ter compromisso de compatibilidade. Impacto alto: é o "salvar e reexecutar" que `docs/ESTADO_ATUAL.md:659` registrava como ausente. |
| **Como testar** | Os testes da wip (`tests/unit/test_session_store.py`, citados no cabeçalho do módulo) mais: documento com `version: 2` vira `session_incompatible` e o arquivo fica intacto; passo `sensitive` nunca grava texto; `${VAR}` sem variável no replay falha antes de qualquer toque; ciclo de reinício do motor em teste de contrato (`codegen.record`, motor novo, `session.restore`, `codegen.steps` iguais). Swift: o front chama `session.restore` em `recover` (`EngineSession.swift:381-413`). |
| **Versão** | minor: métodos `session.*`, capability `session_store` e campos novos em `AutomationStep`. Registrar em `docs/VERSIONAMENTO.md` que `mobaile.session` v1 incompatível é major. |
| **Pendências** | PB3 (as branches `worktree-agent-ad7d472dd0b5a7130` e `worktree-agent-aacc1948ad44fa5a9`), PB1 (máscara na `StepsList` e no `passive.text`), A6 (sessão como documento) e base de M9. |

Padrões do agent-device que resolvem o problema:

- **`.ad` publicado:** atômico, exclusivo e com cabeçalho `context platform=… device=…` (pesquisa §4.8).
- **`--record-as VAR`:** o literal vai ao app e `${VAR}` vai ao disco; o replay resolve a variável e falha alto se ela faltar (`clone: docs/adr/0017-parameterized-recorded-inputs.md:21-44,81`).
- **Descritor ilegível mantido como evidência,** nunca "migrado no chute" (pesquisa §4.7).

Proposta:

- Integrar, depois de revisar, `services/session_store.py` da branch wip. O desenho já cobre:
  - escrita atômica 0600/0700;
  - documento `mobaile.session` v1;
  - motor "desarmado";
  - backup do arquivo alheio;
  - `sensitive`, que zera `input_text`.
- A `_write_atomic` própria da wip passa a usar M2.
- Três acréscimos vindos do agent-device:
  1. **`record_as`.** Um passo de digitação pode ser marcado "salvar como variável" com um nome (`SENHA`). O documento grava `"input_text": "${SENHA}"`, e o runner (M5a) resolve por `MOBAILE_VAR_SENHA` ou por um valor que o front pede na hora de rodar. O front pode guardar o valor no Keychain, mas isso é pergunta ao dono. Na escuta passiva, o front mostra `${SENHA}` em vez do texto lido (`passive.text`, `server.py:1264`).
  2. **Identidade do alvo** por passo: `{resource_id, text, content_desc, class_name, ancestry: [classe/id de até 2 ancestrais], bounds}`. Os `bounds` ficam só como diagnóstico. Os dados já estão no `UIElement` (`domain/models.py:62-122`, com `parent_idx`).
  3. **Cabeçalho do alvo** no documento: `{platform, device_id, device_name, screen: [w, h]}`. Ele vale como evidência e serve para avisar "gravado em outro aparelho".

### M6. Geração da hierarquia (ref frame simplificado)

| | |
|---|---|
| **Problema** | Ver a lista abaixo da tabela. |
| **Padrão do agent-device** | Cada substituição da árvore incrementa `snapshotGeneration`, que começa num número aleatório para não colidir com uma vida anterior. Ref com geração diferente é rejeitada com razão tipada (`ref_generation_mismatch`), e leitura velha só ganha aviso (pesquisa §3.2; `clone: src/daemon/session-snapshot.ts:77`, `docs/adr/0014-session-ref-frame-lifetime.md:30-33,173`). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P a M. Risco baixo, porque o parâmetro é opcional. Impacto médio: o defeito é silencioso, e o passo gravado errado só aparece ao rodar. |
| **Como testar** | Teste de contrato: `hierarchy.dump` (g1), depois `_store_hierarchy` simulando o prefetch (g2), depois `codegen.record {generation: g1}` → `hierarchy_stale`; com `g2` grava; sem `generation`, comportamento atual. As fixtures mudam. |
| **Versão** | minor (aditivo). Tornar `generation` obrigatório no futuro seria major. |
| **Pendências** | B3 (teclado na árvore usa o mesmo estado) e A1 (unicidade de seletor, calculada sobre a árvore). |

O problema:

- `codegen.record` e `hierarchy.element_at` resolvem coordenadas contra `current_xml` (`server.py:747-755,1019-1031`).
- Essa árvore pode ter sido trocada por `_async_prefetch_hierarchy` (`:1308-1323`) ou por outro dump depois que o front desenhou a árvore que a pessoa via.
- A época só muda na troca de aparelho (`:362-375,447-452`).

Resultado: um passo pode ser resolvido contra uma árvore diferente da que estava na tela. É inferência a partir do código; não reproduzi em aparelho.

Proposta, em `rpc/server.py` (e no módulo de handlers, quando R1 acontecer):

- **Contador:** `_hierarchy_generation` com semente `secrets.randbelow(900_000) + 100_000`, incrementado em `_store_hierarchy`.
- **Na leitura:** `hierarchy.dump` devolve `generation`.
- **Na gravação:**
  - `codegen.record` e `hierarchy.element_at` aceitam `generation` opcional;
  - se a geração difere, respondem erro `data.code = "hierarchy_stale"` com `current_generation`, e o front relê e repete;
  - sem o parâmetro, o comportamento atual se mantém, com compatibilidade para o Tk.
- **Escuta passiva:** ela grava contra "a árvore de antes do toque", por desenho (`server.py:1270-1272`), e o passo passa a guardar a `generation` usada, como evidência.

### M7. Limites com sinal de descarte e export de analytics no motor

| | |
|---|---|
| **Problema** | Fila de analytics sem limite e sem consumidor; descarte silencioso; export (≤1.000) e auditoria (≤5.000) divergentes (seção 3.4, itens 4 e 8). |
| **Padrão do agent-device** | Cursor anterior à janela falha com `EVENT_LOG_CURSOR_EXPIRED` e `earliestCursor`: a perda é dita, não escondida (pesquisa §4.4; `clone: packages/session-journal/src/session-event-log-window.ts:40-41,236`). Artefato volta como caminho (pesquisa §4.9). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P. Risco baixo. Impacto médio: corrige um vazamento de memória e uma auditoria inconsistente. |
| **Como testar** | Um teste unitário emite 6.000 eventos e confere `evicted = 1000` e `capacity = 5000`; a memória da fila fica estável. Teste de contrato de `analytics.export` com `HOME` temporário: o arquivo tem 0600 e o mesmo conteúdo que `history_snapshot()`. |
| **Versão** | patch para a fila; minor para `evicted`/`capacity` e `analytics.export`. |
| **Pendências** | PB5 (vazamentos de `event_queue` primeiro) e o item 0.5 de 05/10 ("exportação no motor"). |

Proposta:

- **A fila:** remover `analytics.event_queue` do motor ou dar-lhe `maxsize` (`analytics_logcat.py:159,401`). O Tk tem fila própria (`apps/tk-legacy/mobaile_tk/main_window.py:731`).
- **O contrato:** `proxy.events` e `analytics.events` ganham `{evicted, capacity}`, como já está desenhado no apêndice A §3 da rodada de 05/10.
- **O export:** um método novo `analytics.export {path?}` grava o JSON pelo motor (M2) e devolve `{path, count, evicted}`. `Exporters.exportAnalyticsJSON` (`Exporters.swift:69-90`) passa a usá-lo.
- **O comentário:** corrigir `server.py:1431-1432`.

### M8. Diário de captura NDJSON (opt-in), lido pela auditoria

| | |
|---|---|
| **Problema** | Uma queda do motor perde a captura de analytics de um roteiro inteiro. A auditoria com `source=session` fica impossível (seção 3.3). |
| **Padrão do agent-device** | `events.ndjson` v1, redigido, com rotação de 5 MiB + 1 e fila serial por caminho. É evidência, não fonte de verdade (pesquisa §4.4; ADR 0018). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | M. Risco médio: é **mais dado sensível em disco**. Por isso é opt-in e pede decisão do dono. Impacto médio. |
| **Como testar** | Escrever 3 eventos, simular queda (sem `close`) e ler com `report.audit {source:"file", log_path:…ndjson}`: o resultado é igual ao da auditoria em memória. A rotação respeita o teto. A redação de URL vale nos eventos de rede. A limpeza remove as sessões além do limite. |
| **Versão** | minor |
| **Pendências** | A6 (sessão como documento), que pode empacotar esses NDJSON, e A2 (desfazer), cuja lixeira pode ser o próprio diário. |

Proposta:

- **Onde:** `~/Library/Application Support/Mo baile/captures/<AAAAMMDD-HHMMSS>-<id>/analytics.ndjson` (e `network.ndjson`, se o dono quiser).
- **Formato:** linhas `{"v":1,"ts":…,"kind":"analytics.event","event":{…}}`.
- **Escrita:** por `PrivateRotatingLog` (M2), numa thread única com fila limitada, sem `fsync` por linha. O agent-device também não faz `fsync` no diário.
- **Leitura:** `items_from_text` (`services/report/firebase_log.py:126-131`) aprende a ler NDJSON.
- **Retenção:** as últimas 10 capturas ou 7 dias, com limpeza na subida. Aqui o Mo baile deve ir além do agent-device, que não apaga sessões (pesquisa §4.12).
- **O que não fazer:** a memória continua sendo a verdade. O diário nunca recarrega o histórico sozinho; o front oferece "Auditar a captura anterior".

### M9. Replay por localizador com verificação de identidade

| | |
|---|---|
| **Problema** | O runner toca só por coordenada e com esperas fixas (`flows.py:241-316,339,368`). Um passo pode tocar o elemento errado em silêncio quando o layout muda (PB4/A3). |
| **Padrão do agent-device** | Antes de agir, o replay verifica `target-v1`. Se não consegue isolar o elemento, diverge com `kind` (`selector-miss`, `identity-mismatch`, `identity-unverifiable`), tela nova e até 5 sugestões ranqueadas. O `--update` não reescreve o script, só sugere (pesquisa §4.8; ADR 0012). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | G. Risco médio: muda o executor, e o iOS depende do PB2 (digitação via WDA). Impacto alto: é o que torna o fluxo gravado confiável. |
| **Como testar** | Aparelho falso com duas árvores: a mesma tela com o botão deslocado resolve pelo localizador e toca no centro novo; o botão removido diverge com `selector-miss` e sugestões; dois candidatos dão `identity-unverifiable`; passo `position` toca a coordenada. Teste de contrato de `flow.step`. |
| **Versão** | minor |
| **Pendências** | PB4, A3, PB2, PB6 (`flow.step`), B2 e C4. |

Proposta, decidida contra a regra já fixada em 05/10 ("não haverá fallback automático para coordenada"):

- Para cada passo, o runner relê a hierarquia e procura o elemento pelo `strategy`/`locator_value` gravado.
- Antes de agir, confere a identidade de M5b: classe + id/texto + ancestrais.
- Coordenada só vale quando a estratégia gravada é `position`.
- Divergência vira `flow.step {status: "failed", reason: "selector_miss" | "identity_mismatch" | "identity_unverifiable", suggestions: [...]}`, com o contrato do apêndice A §1 de 05/10 acrescido de `reason`.
- A espera fixa dá lugar a "esperar a tela assentar": reaproveitar a lógica de `stream.settled` (`services/streaming.py`) ou um polling curto de hierarquia com teto.

### M10. Retenção e limpeza do que é do motor

| | |
|---|---|
| **Problema** | Binários de OCR antigos acumulam (`vision_ocr.py:97-104`), scripts órfãos sobram (M5a), o log do Appium cresce (M3) e o MP4 no `/sdcard` é esquecido (M4). Nada é limpo na subida. |
| **Padrão do agent-device** | Cache do runner com as "3 chaves recentes ou usadas no último dia". Temporários com `cleanup`. Downloads expiram em 15 min (pesquisa §4.12). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P. Risco baixo. Impacto médio a baixo. |
| **Como testar** | Testes unitários da limpeza com diretórios temporários e relógio injetado. |
| **Versão** | patch |
| **Pendências** | Nenhuma explícita. Complementa M3, M4 e M5a. |

Proposta: uma rotina `services/housekeeping.py`, chamada na subida, fora do caminho crítico, numa thread da fila `environment`. Ela:

- mantém só o binário de OCR do digest atual e do anterior;
- remove `flow_runner_*.py` com mais de 1 h;
- aplica a retenção de M8.

Arquivos da pessoa (`~/Movies/Mo baile`, `~/Documents/Mo baile`) **nunca** são apagados. No máximo, o diagnóstico mostra o tamanho.

### M11. Versão de esquema e carimbo do gerador nos formatos próprios

| | |
|---|---|
| **Problema** | Seção 3.4, item 5. |
| **Padrão do agent-device** | Todo JSON próprio tem `version`/`schemaVersion`/`envelopeVersion`. Versão desconhecida é recusada com razão tipada e o arquivo fica como evidência (pesquisa resumo §6; §4.7). |
| **Proposta** | Ver a lista abaixo da tabela. |
| **Esforço, risco e impacto** | P. Risco baixo: `SpecTemplate.from_dict` lê só as chaves que conhece (`domain/report.py:93-113`), então um campo novo deve ser ignorado. É inferência; confirmar com teste. Impacto médio a baixo agora, e alto na primeira mudança de formato. |
| **Como testar** | Fixtures de relatório atualizadas (`make fixtures`); spec com versão maior é recusada com mensagem clara. |
| **Versão** | patch (campo novo em arquivo exportado, compatível) |
| **Pendências** | Nenhuma explícita. Ver ADR 0003 (paridade com o `tag_audit`): o campo novo não pode quebrar o `tag_audit` original, que lê a mesma spec. |

Proposta:

- **Rascunho de spec:** o rascunho gerado por `import_prints` (`service.py:316`) ganha `"schema": "mobaile.spec", "schema_version": 1, "gerado_por": "Mo baile <versão>"`. O leitor (`domain/report.py`) aceita a ausência, por compatibilidade, e recusa versão maior que a suportada.
- **Relatórios exportados:** o Markdown e o HTML ganham uma linha "Gerado por Mo baile X.Y.Z em <data>".
- **HAR:** `creator.version` passa a usar a versão real do app (`HARExporter.swift:74`).

### Prioridade final

| # | Melhoria | Esforço | Impacto | Versão | Arquivos principais |
|---|---|---|---|---|---|
| 1 | M1 log bruto CFNetwork | P | Alto | patch | `adapters/ios_cfnetwork.py`, `tests/unit/test_ios_cfnetwork.py` |
| 2 | M2 primitiva de escrita | P | Médio-alto | patch | `security/storage.py` (novo), `security/paths.py`, `rpc/server.py:1087-1114`, `services/report/service.py` |
| 3 | M5a passos pelo stdin | P | Alto | patch | `services/flows.py` |
| 4 | M3 log do motor + `diagnostic_id` | P | Alto | minor | `rpc/server.py:1529-1534,1720-1743`, `adapters/appium.py`, `docs/PROTOCOLO_RPC.md` |
| 5 | M7 limites e export no motor | P | Médio | patch/minor | `adapters/analytics_logcat.py`, `adapters/proxy.py`, `rpc/server.py`, `rpc/contract.py`, `App/Exporters.swift` |
| 6 | M4 registro de aparelho e processos | M | Alto | minor | `services/device_state.py` (novo), `adapters/adb.py`, `adapters/analytics_logcat.py`, `adapters/appium.py`, `adapters/screen_recorder.py`, `ports/protocols.py`, `Engine/EngineSession.swift` |
| 7 | M5b sessão v1 + `${VAR}` + identidade | M | Alto | minor | `services/session_store.py` (wip), `domain/models.py`, `services/codegen.py`, `rpc/server.py`, `Engine/EngineSession.swift` |
| 8 | M6 geração da hierarquia | P-M | Médio | minor | `rpc/server.py`, `Engine/EngineSession.swift` |
| 9 | M10 retenção | P | Médio-baixo | patch | `services/housekeeping.py` (novo), `adapters/vision_ocr.py` |
| 10 | M11 versão de esquema | P | Médio-baixo | patch | `services/report/service.py`, `domain/report.py`, `Models/HARExporter.swift` |
| 11 | M8 diário NDJSON opt-in | M | Médio | minor | `services/capture_journal.py` (novo), `services/report/firebase_log.py` |
| 12 | M9 replay com identidade | G | Alto | minor | `services/flows.py`, `rpc/server.py`, `rpc/contract.py`, front de execução |

---

## 5. Ideias descartadas ou adiadas

**Daemon de longa duração com TCP loopback ou HTTP + token — descartada.**
Contraria a ADR 0001 e `docs/ARQUITETURA.md:55-60`: sem TCP não há superfície de rede nem autenticação a inventar, e o motor morre com o app. O agent-device precisa de daemon porque atende vários clientes efêmeros (CLI, MCP, Node); o Mo baile atende uma janela. O ganho que o daemon traz, sobreviver à janela, viraria problema no Mo baile: proxy e escuta ligados sem ninguém olhando.

**Canal separado para quadros do espelho — fora deste estudo.**
Já está previsto (ADR 0001, `:62`; F1). Se acontecer, deve respeitar o "sem TCP", com pipe anônimo herdado ou `IOSurface`.

**Sidecar `.window.json` com cursores absolutos — descartada.**
Serve a leitores paginados por cursor, que são agentes. O front do Mo baile recebe tudo por notificação. A rotação simples, 5 MiB + 1, basta (M3, M8).

**Envelope genérico de recurso durável com cerca e reanexação de captura viva — descartada como desenho genérico.**
Adotada só a parte simples (M4): registrar para desfazer e para colher órfãos. Reanexar `logcat`, proxy ou gravação a um motor novo exigiria a mesma maquinaria de ADR 0019, para um caso que o front já resolve religando, com consentimento.

**Posse exclusiva de aparelho entre processos (device claims) — adiada.**
Só vira necessidade com A9 (uma janela por aparelho, cada uma com o seu motor) ou se o Tk continuar coexistindo. Até lá, M4 registra o dono (pid + start time) e permite avisar.

**Formato `.ad` (ou outra DSL de fluxo) — descartada como formato; o conceito foi adotado.**
O entregável do público é Page Object Python para Appium. Uma segunda linguagem duplicaria a regra (`docs/ARQUITETURA.md`, "A regra de disciplina"). A identidade do alvo e a parametrização `${VAR}` entram no JSON de sessão (M5b).

**Exportar para Maestro YAML — adiada.**
Não foi pedida pelo público atual (Appium). Pode entrar como mais um alvo do codegen (item 15 de 05/10), não como formato de persistência.

**Economia de saída (`digest/default/full`, baseline de bytes) — descartada.**
Otimiza tokens de LLM. O consumidor do Mo baile é uma interface local. Fica só a ideia de orçamento medido para o quadro do espelho, que já aparece em Q5.

**Devolver screenshot e quadro só por caminho — descartada.**
O front desenha na hora. Gravar em disco a 3,5 fps só somaria I/O. O Mo baile já devolve caminho onde faz sentido (gravação, export, Page Object).

**Helper Android persistente com APK de instrumentação (UiAutomation) — adiada, merece estudo próprio.**
É o maior ganho de desempenho visto no agent-device (227 → 5,8 ms, pesquisa §5) e ataca a dor central do público, que é a espera por captura. Mas é G e exige APK assinado, instalação no aparelho do cliente (MDM de banco, diálogo de OEM, pesquisa §8) e manutenção em Kotlin. Fora do foco de persistência.

**Servidor MCP por stdio — adiada.**
É compatível com o "sem TCP", mas muda o produto de inspetor para ferramenta de agente. Decisão de produto, não de arquitetura.

**Redigir os parâmetros de analytics por chave — não recomendada sem decisão.**
A auditoria compara valores com a spec (`services/report/rules.py`), e PII em evento de analytics é justamente um achado de QA. Ver a pergunta 4 na seção 6.

---

## 6. Riscos de adoção e perguntas em aberto

### Riscos

1. **Mais dado em disco é mais superfície de vazamento.** M3, M4, M5b e M8 passam a gravar o que hoje morre com o processo. Mitigação: cada arquivo novo nasce com um teste de redação que falha se a sentinela aparecer, e com modo 0600 conferido.
2. **Compromisso de compatibilidade.** `mobaile.session` v1 e `mobaile.device-ledger` v1 viram formatos salvos. Mudança incompatível sobe a MAIOR (`docs/VERSIONAMENTO.md`). Mitigação: leitor defensivo (versão desconhecida = erro tipado, arquivo intacto, como a wip já faz) e campos opcionais.
3. **Reverter a configuração de outra ferramenta.** Charles ou Proxyman podem ter mudado o `http_proxy` depois do Mo baile. Mitigação: a cerca de M4 (só reverte se o valor atual for o `applied`).
4. **Symlink do usuário.** Recusar symlink em `~/Documents/Mo baile` quebraria quem liga `pages/` ao repositório de testes. Mitigação: a política `owned=False` de M2.
5. **iCloud Drive em `~/Documents`.** O `fsync` pode ficar lento, e a sincronização pode ver o `.tmp` (inferência). Mitigação: temporário com prefixo `.` e no mesmo diretório; não fazer `fsync` de diretório em volumes que não suportam.
6. **Divergência com o Tk.** Se M4 morar na camada RPC, o app Tk (P0 3 de 05/10) continua deixando o aparelho sem rede. Mitigação: M4 em `services`/`adapters`.
7. **Branch wip não revisada.** O `session_store.py` tem 514 linhas sem teste rodado nem revisão (`RODADA_2026-10-05_PENDENCIAS.md`). Integrar exige revisão independente e a regressão "falha antes, passa depois".
8. **App instalado.** Tudo em `engine/src` exige `make update-native` + `verify-native` (`AGENTS.md`). Nenhuma proposta traz dependência nova: tudo é stdlib (`tempfile`, `os`, `logging.handlers`, `faulthandler`, `secrets`, `hashlib`), o que evita o modo de falha do item 4 do `AGENTS.md`.

### Perguntas para o dono

1. **Reversão no aparelho (M4):** automática na subida, com aviso depois, ou só com confirmação? A recomendação é automática quando a cerca confirma, e pergunta quando não confirma.
2. **Diário de captura (M8):** ligado por padrão, opt-in ou nunca? Com que retenção (sugestão: 10 capturas ou 7 dias)? Inclui tráfego HTTP redigido, ou só analytics?
3. **`MOBAILE_REDACT=0`:** deve continuar desligando a redação do que vai para disco (log bruto, diário, log do motor), ou só a da tela? A recomendação é só a da tela.
4. **Analytics com PII:** os parâmetros de analytics devem ser redigidos por chave (`email`, `cpf`) na tela e em disco? Ou o Mo baile deve **apontar** PII como divergência na auditoria, sem redigir?
5. **Valor das variáveis `${VAR}` (M5b):** variável de ambiente, Keychain do macOS (no front) ou pedido na hora de rodar?
6. **Local dos arquivos:** pode unificar `~/Library/Logs/MoBaile/` e `~/Library/Logs/mobaile-appium.log` em `~/Library/Logs/Mo baile/`? Quem tem script olhando o caminho antigo quebra.
7. **`session.json` × `.mobaile`:** a sessão autosalva (PB3) e o documento "Arquivo › Salvar Sessão" (A6) devem ser um formato só?
8. **Tk:** as correções de persistência devem chegar ao Tk, ou ele sai antes?

---

## 7. Roteiro proposto

### Fase 1: patch 3.4.x, cerca de 1 semana

Fecha vazamento e risco de perda sem tocar no contrato.

- **M1:** log bruto do CFNetwork redigido, com regressão que falha hoje.
- **M2:** `security/storage.py`, aplicado a `codegen.save`, export e import de relatório, OCR e log bruto.
- **M5a:** passos pelo stdin e limpeza de scripts órfãos.
- **M7 (parte patch):** fila de analytics limitada ou removida.
- **M10 e M11:** retenção do que é do motor e versão de esquema nos formatos próprios.
- **Critério de pronto:** `make check` e `make test-swift` verdes; nenhuma sentinela de segredo em arquivo sob `HOME` temporário em toda a suíte; `make update-native` com OK do `verify-native`.

### Fase 2: minor 3.5.0, 2 a 3 semanas

Recuperação após queda e sessão.

- **M3:** `engine.log`, `faulthandler`, `diagnostic_id`; Appium com nível e rotação.
- **M4:** registro do aparelho e processos possuídos, com `device.pending_restore` e `device.restore_pending`.
- **M5b:** sessão v1 integrada da wip, com `sensitive`, `${VAR}` e identidade do alvo; front restaura em `recover`.
- **M7 (parte minor):** `evicted`/`capacity` e `analytics.export`.
- **M6:** geração da hierarquia.
- **Critério de pronto:** o teste de SIGKILL com aparelho falso deixa o aparelho como estava; um motor reiniciado devolve os mesmos passos; `docs/PROTOCOLO_RPC.md` e `make fixtures` atualizados; `make update-native` OK.

### Fase 3: minor 3.6.0+, G

Fluxo confiável e captura recuperável.

- **M9:** replay por localizador com verificação de identidade e `flow.step` com motivo (depende de PB2 e PB6).
- **M8:** diário de captura, se o dono aprovar na pergunta 2, já preparando A6 (sessão como documento).
- **Critério de pronto:** um fluxo gravado num layout roda em outro com o botão deslocado; um botão removido produz divergência com sugestões, sem toque em coordenada.

# Distribuição pública do Mo baile: revisão

Data: 2026-11-16 · Status: RASCUNHO · Método: leitura estática do repositório, `git`, `gh api` (só GET) e documentação oficial. Nada foi assinado, notarizado, publicado, instalado ou empacotado.
Stack: app SwiftUI (SPM) + motor Python externo · Canal: GitHub Releases (zip) · CI: `.github/workflows/release.yml`.

## Veredito

**Pergunta 1 (qualquer pessoa baixa e usa?): hoje, não sem ajuda.** Um Mac com Apple Silicon e macOS 14+ abre o app depois de "Abrir Mesmo Assim"; o motor só sobe depois que a pessoa instala um Python 3.10+ com Pillow pelo Início (que por sua vez pode instalar o Homebrew). Mac Intel não roda o app (DIST-02).

**Pergunta 2 (avisa atualização?): não existe nada hoje.** Nenhuma checagem de versão remota no Swift, no motor, em `tools/` ou na arquitetura (busca por `releases/latest`, `api.github`, `appcast`, `Sparkle`, `SUFeed`, `checkForUpdate`: sem ocorrência). Recomendação: opção (a), checagem pela API de releases com aviso discreto (DIST-08, PROP-1).

## Achados

| ID | Sev. | Rótulo | Evidência | Impacto | Recomendação |
|---|---|---|---|---|---|
| DIST-01 | alta (atrito, não bloqueia) | Verificado | `release.yml:166-170`, `README.md:175`, `INSTALACAO.md:141` | As notas de todo release e o README mandam "clique direito > Abrir". A página oficial da Apple só descreve **Privacidade e Segurança > Abrir Mesmo Assim** (https://support.apple.com/en-us/102445, lida em 2026-11-16) e não menciona clique direito. Que o clique direito não funciona mais no macOS 15+ é relato amplo, **não confirmado nessa fonte**: Não verificável, reconferir num Mac com macOS 15/26. Quem seguir só o texto pode achar que o app está quebrado. | Reescrever o aviso de primeira abertura com o caminho oficial como principal (Tentar abrir > Ajustes do Sistema > Privacidade e Segurança > Abrir Mesmo Assim > Abrir). Manter `xattr -dr com.apple.quarantine` como alternativa. Atualizar nas notas (`release.yml`), README (pt e en) e INSTALACAO. |
| DIST-02 | **alta (bloqueador para Intel)** | Inferido | `package_macos_app.sh:102` (`swift build -c release`, sem `--arch`), `release.yml:30` (`macos-26`), `Package.swift:7` | O binário sai só na arquitetura do runner (arm64 provável; runner não confirmado em fonte oficial). Mac Intel não abre o app, e nenhum documento diz isso. `lipo -archs` no zip publicado confirmaria. | Decisão: (i) declarar "só Apple Silicon" em README, notas e `LSRequiredArchitecture`/documentação; ou (ii) build universal com `swift build -c release --arch arm64 --arch x86_64` (esforço P; confirmar que `swift test` e o runner suportam). Escolher e registrar. |
| DIST-03 | alta (bloqueador de 1ª execução) | Verificado | `EngineLocator.swift:16-18,59-86`, `INSTALACAO.md:74-75` | O app não leva Python. Num Mac zerado só existe `/usr/bin/python3` 3.9 (recusado pela sonda). O motor para com a mensagem "O motor precisa do Python 3.10…". É atrito resolvível pelo app, não impede de vez. | Manter; ver DIST-04. |
| DIST-04 | média | Verificado | `HomeModel.swift:5-41`, `instalar-mac.sh:50-65,73-88` | O Início resolve o Python com "Instalar no Terminal…": script que instala o Homebrew (pede senha de administrador, baixa de `raw.githubusercontent.com`, dispara as Command Line Tools) e depois `brew install python@3.12`. Funciona, mas leva minutos, exige internet e confiança num script remoto, e a pessoa precisa clicar em Reiniciar Motor. Sem o Terminal/conta admin, para. | Aceitar para o público técnico (QA). Para público amplo, avaliar embutir um Python (decisão G, fora desta rodada). Pôr no README, antes do download, a frase "precisa de Python 3.10+; o app instala para você". |
| DIST-05 | média | Verificado | `release.yml:80-86`, `RELEASE.md:79-83` | Assinatura ad-hoc: o macOS trata cada build como identidade nova, então permissões do TCC (Documentos, rede local) se perdem a cada atualização, e a pessoa vê os prompts de novo. A identidade "Mo baile Local" resolve só na máquina do dono. | Documentar o efeito nas notas ("após atualizar, o macOS pode pedir permissões de novo"). Só Developer ID resolve de vez (DIST-11). |
| DIST-06 | **alta** | Verificado | `git merge-base --is-ancestor v3.21.0 origin/main` falha; `gh release list` | O release "Latest" (3.21.0) vem da tag `v3.21.0` (63f4653), que **não está na main** (só na branch `melhoria/2026-11-03-pycharm-desempenho`). O campo `target_commitish: main` do release engana. Quem clonar a main não encontra o código do app baixado. Pelo GitHub (https://docs.github.com/en/rest/releases/releases#get-the-latest-release, lida em 2026-11-16) "latest" é o mais recente não rascunho e não prerelease, ordenado por `created_at`, que é a data do commit. | Integrar na main antes de publicar mais releases; depois publicar sempre a partir da main. Ver PROP-2. |
| DIST-07 | alta | Verificado | `git rev-list --count origin/main..HEAD` = 15; tags `v3.18.0, v3.19.0, v3.20.0, v3.22.0, v3.23.0` só locais; `origin/main` na 3.17.3 | A main está atrás; cinco tags sem push. Pelo que o dono relatou, o GitHub não dispara workflow quando mais de 3 tags sobem juntas (não conferi na fonte: Não verificável; reconferir em docs.github.com, evento `push`). Subir as cinco de uma vez provavelmente não gera release nenhum, sem aviso. | Subir **uma tag por vez**, só a 3.23.0 (ou a última), esperar o Release. Não é preciso publicar 3.18–3.22 (o CHANGELOG já cobre); ver DIST-09. |
| DIST-08 | **alta (lacuna de produto)** | Verificado | busca citada acima | Sem checagem de versão: quem instalou a 3.21.0 nunca saberá da 3.23.0. | PROP-1. |
| DIST-09 | média | Verificado | `release.yml:136-171` | Notas saem da seção do CHANGELOG. Se uma versão intermediária não tiver release, a seção da nova não resume o que mudou desde a anterior publicada (3.21.0 para 3.23.0 pula 3.22.0). | Ao publicar a 3.23.0, acrescentar às notas "Inclui também 3.22.0" (ou gerar notas acumuladas desde o último release). |
| DIST-10 | baixa | Verificado | `RELEASE.md:19` (`macos-latest`) vs `release.yml:30` (`macos-26`) | Documento fora do workflow. | Corrigir o doc. |
| DIST-11 | decisão | Verificado | `release.yml:56-80,100-130`, `RELEASE.md:66-96` | Developer ID e notarização estão prontos e comentados no workflow. Pela Apple, notarizar exige conta no Apple Developer Program, certificado Developer ID Application, Hardened Runtime e timestamp seguro (https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution, lida em 2026-11-16; a ferramenta devolveu só o resumo, então a sintaxe de `notarytool`/`stapler` segue Não verificável: conferir com `xcrun notarytool --help`). Preço da conta: Não verificável, reconferir em developer.apple.com/programs. | Decisão do dono (PROP-5). |
| DIST-12 | média | Verificado | `release.yml:60-62` (zip + `.sha256` no mesmo release) | O `.sha256` ao lado do zip dá integridade, não autenticidade: quem controla o release controla os dois. Serve para detectar download corrompido. Para atualização automática isso importa (DIST-13). | Para PROP-1 basta (o app só abre a página). Para instalar no lugar (PROP-3) precisa de assinatura própria (EdDSA). |
| DIST-13 | info | Inferido | https://developer.apple.com/documentation/bundleresources/information-property-list/lsfilequarantineenabled (lida em 2026-11-16) | Pela Apple, `LSFileQuarantineEnabled` controla se os arquivos que o app cria entram em quarentena, com padrão falso (o `Info.plist` gerado em `package_macos_app.sh:178-215` não define a chave). Logo, um zip baixado por `URLSession` do próprio app, sem sandbox, provavelmente **não** leva `com.apple.quarantine` e o Gatekeeper não avaliaria o app novo. Ou seja, a atualização in-app contorna o aviso, mas também a verificação do macOS. Relatos em fóruns da Apple dizem que o comportamento varia: **testar num Mac**. | Se fizer PROP-3, verificar com `xattr -l` e decidir de propósito. |
| DIST-14 | info | Verificado | `Package.swift:7`, `package_macos_app.sh:208-209` | Versão mínima macOS 14.0 declarada no pacote e no `LSMinimumSystemVersion`. O CI usa macos-26 e Swift 6.2 (`ci.yml:120`); o binário compilado com SDK novo pode ainda declarar mínimo 14: conferir com `otool -l` no zip. | Conferir em máquina com macOS 14 (Não verificável aqui). |
| DIST-15 | info | Verificado | `gh api repos/francisco-efjr/mo-baile` (`visibility: public`), limite de 5000/h só com token; sem token o limite é menor e não está na página lida (Não verificável) | O repositório é público, então a API de releases não precisa de token. Uma checagem por abertura (ou a cada 24 h) fica folgada. | Guardar a hora da última checagem e usar `If-None-Match`/ETag se quiser economizar. |

## Pergunta 1: caminho de quem tem um Mac zerado

1. **Achar o download.** README aponta para `releases/latest` (`README.md:62-63`). Hoje leva à 3.21.0 (DIST-06). Atrito baixo.
2. **Baixar e descompactar.** O navegador põe quarentena no zip. Safari descompacta sozinho; outros navegadores pedem duplo clique. Atrito baixo.
3. **Mac Intel?** Bloqueador (DIST-02, a confirmar com `lipo`).
4. **macOS < 14.** Bloqueador por declaração (`LSMinimumSystemVersion` 14.0). O README informa (`README.md:45`).
5. **Gatekeeper.** Ad-hoc e não notarizado: bloqueia na primeira abertura. Caminho oficial: Abrir Mesmo Assim (DIST-01). Atrito alto para leigo, aceitável para QA. macOS 15 e 26: Não verificável aqui; testar num Mac limpo.
6. **Primeira janela.** Motor não sobe sem Python 3.10+ com Pillow e requests (DIST-03). O Início mostra "Próximo passo: instalar o Python" e roda `instalar-mac.sh python` no Terminal (`HomeModel.swift`, `SetupInstaller.swift`). Pode instalar o Homebrew e as Command Line Tools pelo caminho (DIST-04).
7. **Recursos opcionais.** `adb`, Xcode, Appium: o Início mede e oferece instalar; Xcode vem da App Store (`instalar-mac.sh:18`).
8. **Primeiras permissões do TCC** (Documentos, rede local): aparecem; reaparecem a cada versão (DIST-05).

**Bloqueadores:** Intel (a decidir, DIST-02); macOS abaixo de 14; ausência de internet na primeira instalação do Python.
**Atrito:** aviso do Gatekeeper com instrução desatualizada, Homebrew e Python, TCC repetido, 3.21.0 como "Latest" fora da main.

## Pergunta 2: desenho da atualização

Ponto de entrada no Swift hoje: `EngineSession` já lê `CFBundleShortVersionString` (`EngineSession.swift:105`); `AppState` guarda preferências em `UserDefaults` (`AppState.swift:408`); há `SettingsView.swift` (`GeneralSettings`), `MoBaileApp.swift` (`MoBaileCommands`) e a tela Início (`HomeView.swift`).

| | (a) Checagem + aviso | (b) Atualização no lugar | (c) Sparkle 2 |
|---|---|---|---|
| Esforço | P (1 a 2 dias com testes) | M/G | G |
| Dependência nova | nenhuma (`URLSession`, `Foundation`) | nenhuma, mas ~script auxiliar | Sparkle (SPM), chave EdDSA, appcast no GitHub Pages |
| Assinatura ad-hoc | sem impacto: só abre a página do release | o bundle novo é ad-hoc: TCC perdido; quarentena provavelmente ausente (DIST-13) | A Sparkle diz que ad-hoc com Library Validation pode impedir de carregar o framework e que isso não ocorre com Developer ID (https://sparkle-project.org/documentation/, lida em 2026-11-16) |
| Risco | baixo (pior caso: aviso falso ou silêncio) | alto: troca do próprio bundle com o app rodando e o motor lendo `Resources/engine`; rollback; integridade só pelo `.sha256` do mesmo release (DIST-12) | médio/alto: `package_macos_app.sh` monta o bundle à mão, sem `Frameworks/` nem rpath; precisa de ajuste no script, assinatura de dentro para fora e hospedagem do appcast |

**Recomendação: (a) agora**, com desenho que não fecha a porta para (c) quando houver Developer ID (DIST-11). (b) não compensa: reimplementa o que a Sparkle resolve, com a segurança mais fraca.

## Esboço técnico de PROP-1 (recomendada)

Arquivos novos (Swift, sem mexer no motor; o motor não precisa mudar):

- `apps/MoBaile/Sources/MoBaile/App/UpdateChecker.swift`
  - `struct ReleaseInfo: Decodable, Equatable { tag_name, html_url, body, prerelease, draft, published_at, assets[{name, browser_download_url}] }` (com `CodingKeys` para camelCase).
  - `struct AppVersion: Comparable { init?(_ s: String) }`: aceita `v3.23.0` e `3.23.0`, compara por número (nunca por texto; 3.9.0 < 3.10.0). Falha em formato inválido (nil, sem aviso).
  - `protocol ReleaseFetching { func latest() async throws -> ReleaseInfo }` e `struct GitHubReleaseFetcher` com `URLSession`, timeout de 10 s, cabeçalhos `Accept: application/vnd.github+json` e `User-Agent: MoBaile/<versão>`, **sem token**.
  - URL base injetável: `MOBAILE_UPDATE_URL` (variável de ambiente) com prioridade, depois `UserDefaults` `mobaile.updateFeedURL`, depois o padrão `https://api.github.com/repos/francisco-efjr/mo-baile/releases/latest`. Permite testar com um JSON local servido em `127.0.0.1` sem publicar nada.
  - `enum UpdateDecision { case none, available(ReleaseInfo), ignored }` e função pura `decide(current:, remote:, ignoredTag:, snoozeUntil:, now:)`.
- `@MainActor @Observable final class UpdateState` (junto de `AppState`/`PerfState`): `status`, `checkNow()`, `ignore(tag)`, `snooze(hours: 24)`, `lastCheck`. Chaves em `UserDefaults`: `mobaile.update.ignoredTag`, `mobaile.update.snoozeUntil`, `mobaile.update.lastCheck`, `mobaile.update.autoCheck` (liga/desliga, padrão ligado).
- Disparo: ao abrir o app, no máximo uma vez a cada 24 h (usa `lastCheck`), em segundo plano, sem bloquear o motor. Erro de rede é silencioso (o app é offline-first: `HomeCopy.note` afirma "sem internet"; deixar a checagem **desligável** e dizer na Início/Ajustes que é a única chamada de rede do app, para não contradizer a promessa).
- Interface:
  - Faixa discreta no topo da tela Início (`HomeView.swift`, perto de `HomeNextStepCard`) com "Versão 3.23.0 disponível" e botões **Ver novidades** (abre `html_url` no navegador), **Baixar** (abre o `browser_download_url` do zip), **Lembrar depois** (snooze 24 h), **Ignorar esta versão**. Sem alerta modal, sem som.
  - Item de menu "Buscar Atualizações…" em `MoBaileCommands` (`MoBaileApp.swift`, grupo do app) que ignora snooze e ignorado e mostra "Você está na versão mais recente" quando for o caso.
  - Opção "Buscar atualizações ao abrir" em `GeneralSettings` (`SettingsView.swift`).
- Regras: ignora `draft` e `prerelease`; ignora versão remota menor ou igual à instalada (o dono, com 3.23.0 local e 3.21.0 como Latest, não vê aviso); build de desenvolvimento sem versão (`"dev"`) não checa.
- Testes (`apps/MoBaile/Tests/MoBaileTests/UpdateCheckerTests.swift`): comparação (`3.9.0 < 3.10.0`, `v` opcional, lixo vira nil), `decide` (igual, mais velha, mais nova, ignorada, snooze, prerelease), decodificação de um JSON real do `releases/latest` como fixture, e fetcher falso. Teste de integração opcional com `URLProtocol` customizado.

**Como testar sem publicar release:**
1. `python3 -m http.server 8765 --bind 127.0.0.1` numa pasta com um `latest.json` copiado de `gh api repos/francisco-efjr/mo-baile/releases/latest` com `tag_name` trocado para `v99.0.0`.
2. Abrir o app com `MOBAILE_UPDATE_URL=http://127.0.0.1:8765/latest.json`. (O `Info.plist` gerado não declara exceção de ATS; `127.0.0.1` em http é permitido pelo sistema em loopback, **Não verificável aqui**: confirmar, senão usar `NSAllowsLocalNetworking` só neste teste.)
3. Variar `tag_name` (menor, igual, maior), `prerelease`, JSON inválido e servidor parado.

**Critério de aceite (testável):**
- Com o feed apontando para uma versão maior, a faixa aparece na Início em até 5 s após abrir, com os quatro botões; "Ver novidades" abre `html_url`.
- Com versão igual ou menor, `draft` ou `prerelease`: nenhuma faixa.
- "Ignorar esta versão" persiste após reabrir; uma versão ainda mais nova volta a avisar.
- "Lembrar depois" some por 24 h (testar injetando o relógio).
- Servidor parado, JSON inválido ou sem rede: nenhuma faixa nem alerta, motor sobe normalmente, nenhum erro no console além de log.
- Com "Buscar atualizações ao abrir" desligado, nenhuma requisição sai (conferir com o proxy local do Mo baile ou `nettop`).
- `3.9.0` instalado e `3.10.0` remoto: avisa.
- `make check`, `make test-swift` e `make update-native` passam.

## Propostas

**PROP-1: aviso de nova versão (opção a)**. Problema: DIST-08. Melhoria: o esboço acima. Ganho: quem instalou fica sabendo, sem dependência nova nem mudança de assinatura. Esforço: P. Risco: baixo (chamada de rede num app que se diz offline: mitigar com opção e texto claro). Critério e verificação: acima. Antes de entrar, subir minor (SemVer, `VERSIONAMENTO.md`) e `make fixtures` não é necessário (sem mudança de RPC).

**PROP-2: ordem de liberação limpa.** Problema: DIST-06, DIST-07, DIST-09. Melhoria: (1) integrar a branch na main por PR; (2) subir **só** a tag mais nova, em um push separado (`git push origin v3.23.0`); (3) esperar o workflow; (4) conferir `gh release view v3.23.0` e `gh api .../releases/latest` (tag, ativos, notas); (5) tags antigas (3.18–3.22) ficam locais ou sobem uma a uma sem release, só se o dono quiser. Ganho: Latest correto, código na main. Esforço: P. Risco: baixo-médio (publicar é ação do dono). Critério: `releases/latest` devolve `v3.23.0`, e `git merge-base --is-ancestor v3.23.0 origin/main` passa. Verificar: `gh release list`, `git branch -r --contains v3.23.0`.

**PROP-3: instruções de primeira abertura e requisitos honestos.** Problema: DIST-01, DIST-02, DIST-03, DIST-04, DIST-05. Melhoria: reescrever o bloco de instalação (notas em `release.yml`, README pt/en, INSTALACAO) com: Apple Silicon (ou universal, após decisão), macOS 14+, caminho "Abrir Mesmo Assim", Python 3.10+ instalado pelo Início, aviso do TCC. Corrigir `RELEASE.md:19`. Esforço: P. Risco: baixo. Critério: um Mac limpo (ou conta de usuário nova com macOS 15/26) segue só o texto e abre o app sem consultar mais nada. Verificar: roteiro em máquina limpa, por quem não conhece o projeto.

**PROP-4: build universal (ou declaração só arm64).** Problema: DIST-02. Melhoria: `--arch arm64 --arch x86_64` em `package_macos_app.sh` e conferência com `lipo -archs` no `verify`, ou declarar arm64 only. Esforço: P (declarar) a M (universal, com Intel para testar). Risco: baixo-médio (sem Mac Intel para validar o binário x86_64). Critério: `lipo -archs` lista as arquiteturas prometidas; o README bate com isso.

**PROP-5: Developer ID e notarização (decisão de custo).** Problema: DIST-05, DIST-11. Melhoria: ligar os passos já comentados do workflow, depois de conferir a sintaxe no runner (`security help`, `xcrun notarytool --help`, `xcrun stapler --help`). Ganho: some o aviso do Gatekeeper, as permissões do TCC passam a persistir entre versões, e Sparkle (opção c) fica viável. Esforço: M. Risco: médio (segredos no CI). Critério: `spctl -a -vv` aceita o app do zip publicado em Mac limpo sem "Abrir Mesmo Assim". Verificar: o log do passo de notarização e abertura em máquina limpa. Ficha de ação externa abaixo.

## Fichas de ação externa (o usuário executa)

| Ação | Conta | Artefato | Destino | Comando | Reversibilidade | Quem | Confirmado pelo usuário em |
|---|---|---|---|---|---|---|---|
| Integrar a branch na main | GitHub | `melhoria/2026-11-16-liberacao-publica` | PR para `main` | a conferir (`gh pr create`) | reversível por revert | dono | |
| Subir uma tag e disparar o release | GitHub | `v3.23.0` | `origin` | `git push origin v3.23.0` | release público: apagável, mas já pode ter sido baixado | dono | |
| Entrar no Apple Developer Program | Apple | conta paga | developer.apple.com/programs | a conferir | custo recorrente | dono | |
| Criar secrets do CI | GitHub | 7 secrets em `RELEASE.md:70-80` | Settings > Secrets | a conferir | reversível | dono | |

## Itens conformes

- Workflow com `permissions: {}` no topo e `contents: write` só no job que publica; ações fixadas por SHA (`release.yml:20-35`).
- Tag conferida contra `VERSION` (`release.yml:44-52`); testes do motor e QA antes de empacotar.
- Zip por `ditto` com `.sha256`; notas vindas do CHANGELOG; falha se a seção não existir (`release.yml:136-160`).
- Segredo de assinatura previsto só por secret do CI, sem valores no repositório (nenhum segredo literal encontrado em `release.yml`, `package_macos_app.sh`, `RELEASE.md`).
- Troca atômica do bundle e recusa a rodar com o app aberto (`package_macos_app.sh`).

## Fatos voláteis

| Fato | Fonte | Lida em | Reconferir |
|---|---|---|---|
| Abrir app não notarizado: Privacidade e Segurança > Abrir Mesmo Assim; clique direito não citado | https://support.apple.com/en-us/102445 | 2026-11-16 | no macOS 15 e 26 reais |
| `releases/latest`: mais recente não rascunho/prerelease, por `created_at` (data do commit) | https://docs.github.com/en/rest/releases/releases#get-the-latest-release | 2026-11-16 | docs.github.com |
| Notarizar exige conta, Developer ID, Hardened Runtime, timestamp | https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution | 2026-11-16 (resumo parcial) | página completa |
| Sparkle 2: SPM, `SUFeedURL`, `SUPublicEDKey`, `generate_keys`; ad-hoc pode impedir o carregamento com Library Validation | https://sparkle-project.org/documentation/ | 2026-11-16 | sparkle-project.org |
| `LSFileQuarantineEnabled`: padrão falso para arquivos criados pelo app | https://developer.apple.com/documentation/bundleresources/information-property-list/lsfilequarantineenabled | 2026-11-16 (via resultado de busca) | teste real com `xattr -l` |

## Não verificável aqui

- Funcionamento do clique direito > Abrir no macOS 15/26 e o fluxo do Gatekeeper em máquina limpa.
- Arquitetura real do zip publicado (`lipo -archs`) e o mínimo de macOS no Mach-O.
- Regra do GitHub de não disparar workflows com mais de 3 tags no mesmo push (dado pelo dono).
- Limite sem token da API do GitHub (a página lida não traz o número).
- Preço do Apple Developer Program.
- Se o zip baixado por `URLSession` fica sem quarentena (DIST-13).

## Decisões pendentes do dono

1. Suportar Intel (build universal) ou declarar só Apple Silicon. Assumido: declarar arm64 até confirmar o `lipo`.
2. Entrar no Apple Developer Program (custo recorrente e conta Apple), para Developer ID e notarização. Assumido: não agora.
3. Aceitar uma chamada de rede opcional no app (checagem de versão, desligável). Assumido: sim, ligada por padrão com opção.
4. Sparkle (dependência nova, chave EdDSA, appcast no GitHub Pages) só depois de Developer ID. Assumido: adiar.
5. Publicar 3.18–3.22 como releases ou só a 3.23.0. Assumido: só a 3.23.0, com nota acumulada.
6. Embutir um Python no app para dispensar Homebrew (esforço G). Assumido: fora desta rodada.

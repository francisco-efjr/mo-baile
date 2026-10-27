# Mo baile: contexto do projeto

Resumo para quem chega agora (pessoa ou agente). Estado de 24/10/2026, versão
**3.11.0**. Detalhes nos documentos linkados; em caso de conflito, vale o
documento específico e o código.

## O que é

App nativo de macOS para quem escreve **teste automatizado de apps mobile**
(iOS e Android). Junta num lugar só o que hoje fica espalhado entre Appium
Inspector, proxy, logcat e planilha:

- **Espelho ao vivo** da tela do aparelho ou simulador. Um clique no espelho
  toca no aparelho e grava o passo (desde a 3.10.0 não há mais modos).
- **Hierarquia de acessibilidade** igual para iOS e Android, com busca e
  atributos.
- **Page Objects**: cada passo gravado vira locator + método em
  Python/Appium, em três estratégias (posição, XPath, id).
- **Rede HTTP**: proxy local com credenciais redigidas. HTTPS sem proxy, com o
  app em debug: `CFNETWORK_DIAGNOSTICS` pelo cabo no iPhone e log do OkHttp
  pelo logcat no Android ([ADR 0004](adr/0004-https-sem-proxy-android.md)).
- **Analytics**: eventos do Firebase em tempo real (logcat e Unified Logging).
- **Relatório de tagueamento**: audita os eventos contra a spec dos cards do
  Figma, parâmetro por parâmetro. Exporta board Excalidraw, HTML interativo,
  Markdown e TSV. Funciona sem aparelho.
- **Início**: boas-vindas do dia a dia (aparelho, áreas, recentes, novidades)
  e, numa máquina zerada, a primeira vez em três passos.
- **Ambiente** (⌘5): o que está instalado e o que falta, com o instalador.
- **Flows no formato do Maestro**, rodando local pelo runner do motor.

Repositório: `github.com/francisco-efjr/mo-baile` (MIT). Dono: Francisco Edson
Ferreira Junior. Documentação e conversa em português do Brasil.

## Arquitetura

```
apps/MoBaile      front SwiftUI (macOS 14+): desenha estado, traduz gesto em chamada
apps/tk-legacy    interface Tkinter, CONGELADA (ADR 0005); caminho no Windows
        │  JSON-RPC 2.0, uma mensagem por linha, stdin/stdout (sem porta TCP)
engine/src/mobaile
  rpc/        fronteira: valida e despacha (contract.py tem os 65 métodos)
  services/   casos de uso: streaming, hierarchy, codegen, flows, devices,
              diagnostics, setup, home, maestro_flow, report/
  adapters/   adb, WDA, Appium, scrcpy, proxy, logcat, OkHttp, CFNetwork, OCR
  security/   validação, escaping de shell, redação, XML seguro, números
  ports/      protocolos das bordas (testar sem aparelho)
  domain/     modelos e erros puros, sem I/O
```

- **Regra de ouro:** lógica nova vai para o motor. A mesma regra em Python e em
  Swift é defeito ([ARQUITETURA.md](ARQUITETURA.md),
  [ADR 0001](adr/0001-motor-python-front-swift.md)). No front ficam só
  animação, atalho, layout e projeção de coordenada.
- O app sobe o motor como processo filho e ele morre junto. Requisição tem
  `id`. Quadro do espelho, evento HTTP e evento de analytics chegam como
  notificação, e a interface nunca faz polling.
- `PROTOCOL_VERSION = 2`; métodos novos são aditivos. Contrato em
  [PROTOCOLO_RPC.md](PROTOCOLO_RPC.md).
- As fixtures do contrato (`apps/MoBaile/Tests/MoBaileTests/Fixtures/engine_payloads.json`)
  são geradas pelo próprio motor (`make fixtures`). A suíte Swift decodifica
  payloads reais, e o CI barra fixture desatualizada.
- Tamanho: cerca de 14,8 mil linhas de Python no motor e 16,9 mil de Swift no
  front.

### Como o app acha o motor e o Python

- O motor vai copiado dentro do bundle: `Contents/Resources/engine/src`. O app
  **não lê o repositório**.
- Ordem do Python: `MOBAILE_PYTHON`, Python do Mo baile em
  `~/Library/Application Support/Mo baile/python`, `/opt/homebrew/bin/python3`,
  `/usr/local/bin/python3` e `/usr/bin/python3`. Cada candidato passa por uma
  sonda (3.10+, Pillow, requests).
- Desde a 3.10.0, motor e sonda sobem com **`python3 -S`**:
  `mobaile/_site.py` acrescenta só o site-packages, sem seguir `.pth`. Um
  `.pth` editável apontando para `~/Documents` fazia o macOS pedir acesso à
  pasta Documentos a cada subida.

## Design system

"**Mo baile · macOS 27 / Liquid Glass**", em
[`docs/design/design-system/`](design/design-system/) (feito no Claude Design;
decisão em [ADR 0002](adr/0002-redesenho-liquid-glass.md)). Ele redesenha o
app no padrão de app nativo do macOS, sem inventar funções. A estrutura segue
o HIG: barra lateral, depois espelho + workspace, depois inspector, com toolbar
unificada.

### Marca

- O ícone é um flamingo + alien numa piscina, em ilustração cartoon com
  contorno marinho e cores chapadas. Não há logotipo tipográfico; onde precisar
  do nome, "Mo baile" em SF Pro.
- O mascote e o fundo da piscina aparecem só no ícone e no splash.
- Cores literais do ícone: piscina `#9BDCF3`, flamingo `#F389A9`, alien
  `#7EC674`, marinho `#141543` e grafite `#51545F`.

### Cor

- **A interface é neutra**, levemente tingida de marinho: os rótulos são
  `rgba(20,21,67,…)` com opacidade.
- O **destaque é o flamingo escurecido `#C2456E`**, porque o `#F389A9` do
  ícone tem só 2,2:1 com branco. Vale para seleção, botão padrão, links,
  controle ativo e a única cápsula tingida (Rodar). Texto de destaque:
  `#B23A63` no claro, `#F389A9` no escuro.
- Semânticas:
  - sucesso: o verde do alien (`#3E7A45` claro, `#8FD685` escuro);
  - aviso: `#8A6100` / `#F5C451`;
  - destrutivo: `#D70015` / `#FF6961`.
- Plataformas: iOS `#0A84FF`, Android `#34C759`.
- Categorias da barra lateral: `cat-1` flamingo, `cat-2` verde (Analytics e
  Relatório), `cat-3` azul.
- A piscina azul fica só no papel de parede, na tela do aparelho e no splash.
- **Aparências como tokens:** Claro, Escuro e Aumentar contraste (nas duas).
  Reduzir transparência deixa todo vidro sólido. Na janela inativa, a seleção
  colorida fica cinza.
- **9 paletas alternativas** no app (`Theme/Palettes.swift`, 3.1.0): Sálvia &
  Palha, Azulejo, Hampshire, Veludo Rosé, Terracota, Costes, Geométrico,
  Mármore e Jardim Digital, além da padrão "Praia". O contraste é conferido em
  código (`PaletteCheck`).

### Tipo, espaço e forma

- **Fonte:** SF Pro do sistema, na escala do macOS: Body 13, Headline 13 bold,
  Title 3 15, Title 2 17, Title 1 22, Large Title 26, auxiliares de 10 a 12.
  SF Mono para código, logs, hosts e atributos. Números com `tabular-nums`. A
  hierarquia vem de peso e cor.
- **Espaço:** grade de 4 pt. Margem de 20 nas janelas, 16 dentro de caixas.
  Toolbar 52, barra acessória 36, barra de status 22, barra inferior da
  sidebar 32.
- **Raios concêntricos:** janela 16 → item de sidebar 8; menu 10 → item 6;
  aparelho 40 → tela 33. Cartão 12, campo 7, chip 4, controles em cápsula.
- **Profundidade:** sombras suaves (`--shadow-*`), separador de 1 px, nada de
  borda grossa nem gradiente forte. Cartão: `--bg-group`, borda interna de
  0,5 px, sem sombra.

### Material e movimento

- **Liquid Glass só na camada de navegação:** cápsulas da toolbar, menus,
  popovers e alertas. Na web: `blur(18px) saturate(1.6)`, fundo a 62%, realce
  de 0,5 px no topo. Conteúdo nunca é vidro, e nunca há vidro sobre vidro:
  dentro da cápsula, separa-se com `--fill-*`.
- **Molas no estilo WWDC23:**
  - *smooth* (0,5 s, bounce 0) é a padrão, para painéis e sheets;
  - *snappy* (0,35 s, bounce 0,15) vai em clique, segmentado e switch;
  - *bouncy* só na manipulação direta.
- Trocar de seção é um crossfade de 180 ms. Menus abrem na hora e somem em
  150 ms. O popover vai de 95% a 100% de escala.
- Com Reduzir movimento, tudo vira crossfade.
- Estados: hover com `--fill-secondary`, pressionado com brightness .9, sem
  ripple, desabilitado com 42% de opacidade, foco com anel de 3 px em
  `--focus-ring`.

### Ícones e texto

- O app usa SF Symbols. Na web, Lucide (`lucide-static@0.460.0`, ISC) com
  traço 1,6, e os glifos estão em `components/indicators/Icon.jsx`. Botão só
  com ícone tem tooltip e `aria-label`. **Sem emoji.**
- **Voz:** pt-BR direto, curto e cordial, tratando por "você".
  - Botão: verbo no infinitivo com maiúscula nas palavras principais
    ("Rodar Automação", "Exportar HAR…"), com reticências quando abre painel.
  - Título de janela: o nome da seção, nunca o do app.
  - Erro: diz o que houve e o que fazer, sem código.
  - Estado vazio: uma frase e uma ação.
  - Termo técnico fica como está, em mono.
  - Status em minúsculas e mono.

### Onde o design system vive

| Lugar | O quê |
|---|---|
| `docs/design/design-system/` | Fonte: `tokens/*.css` (colors, typography, spacing, shape, materials, motion, fonts), `components/` (React + `mb.css`), `guidelines/` (20 cartões), `ui_kits/macos-app/` (protótipo), `assets/` (ícone, mascote, splash) |
| `apps/MoBaile/Sources/MoBaile/Theme/` | Tradução em Swift: `DesignTokens.swift`, `PraiaLightTheme`/`PraiaDarkTheme`, `Palettes.swift` e `ThemeManager` (lê contraste e acessibilidade do sistema) |
| `apps/MoBaile/Sources/MoBaile/Views/DesignSystem/` | Componentes SwiftUI do sistema |
| `engine/src/mobaile/services/report/html/` | Cópia embutida no HTML do Relatório (`design_system.css` e `icons.json`), gerada por `tools/sync_report_assets.py`. Um teste falha se a cópia ficar para trás |
| `docs/design/telas/` | Catálogo de capturas de cada tela, em claro e escuro |
| `docs/design/relatorio.md`, `docs/design/home/` | Anatomia do Relatório; especificação e maquetes da Início e do Ambiente |

## Fluxo de trabalho (obrigatório)

Regras completas em [AGENTS.md](../AGENTS.md):

1. **Portão:** `make check` (versão, lint, bandit, suítes Python, QA e
   fixtures) e `make test-swift` passando antes de qualquer commit. Se o
   contrato RPC mudou, rodar `make fixtures` e atualizar `PROTOCOLO_RPC.md`.
2. **Versão:** todo push leva SemVer novo
   ([VERSIONAMENTO.md](VERSIONAMENTO.md)):
   `python3 tools/version.py bump minor`, depois CHANGELOG, `make fixtures`,
   commit `chore(release): X.Y.Z` e tag com `python3 tools/version.py tag`.
   O hook de pre-push e o CI barram. Redesenho drástico de interface sobe
   major.
3. **App instalado sempre atualizado:** o dono usa
   `/Applications/Mo baile (nativo).app`. Toda mudança em `engine/src/`,
   `apps/MoBaile/` ou `assets/` termina com `make update-native` e o OK do
   `verify-native`.
   - O app precisa estar **encerrado com ⌘Q** (fechar a janela não basta).
     Nunca encerre o processo por conta própria; peça ao dono.
   - Nunca substitua o `Mo baile.app` (Tk).
   - Dependência nova do motor precisa estar também no Python do app.
4. **Assinatura:** hoje é ad-hoc, que muda a cada build, e o macOS esquece as
   permissões. `bash tools/create_local_signing_identity.sh` (o dono roda uma
   vez) cria a identidade "Mo baile Local", que o empacotamento passa a usar.
5. Commit e push só quando o dono pedir. Mensagens em português, no padrão
   `feat(area): …` / `fix(area): …` / `chore(release): X.Y.Z`.

## Comandos

```bash
make setup           # .venv com motor e ferramentas, hooks do git
make check           # portão Python
make test-swift      # suíte do front
make fixtures        # regera as fixtures do contrato
make update-native   # testa, empacota, instala e verifica o app nativo
make run-engine      # sobe o motor em JSON-RPC (depurar contrato)
python3 -m mobaile.services.setup   # o que falta instalar (PYTHONPATH=engine/src)
```

## Histórico recente

| Versão | O que trouxe |
|---|---|
| 3.0.0 | Redesenho Liquid Glass (ADR 0002); 3.1.0 paletas alternativas |
| 3.2.0 | Aba Relatório: núcleo do `tag_audit` portado (ADR 0003) |
| 3.3–3.6 | Busca em tudo, App em Debug Android (ADR 0004), splash, fluidez, layout em monitor pequeno |
| 3.7.0 | Copiar Bug da validação e editar o card da spec no app |
| 3.8.0 | HTML do Relatório interativo com a identidade do app (design system embutido, Motion 13.5.1, rodapé "Gerado pelo Mo baile") |
| 3.9.0 | Período do log (primeiro → último evento) em destaque no cabeçalho do relatório |
| 3.10.0 | Tela Início e instalação em máquina zerada (Mac e Windows); flows do Maestro offline; auditoria até 35 vezes mais rápida; toolbar só com o aparelho; fim do pedido de acesso a Documentos |
| 3.11.0 | Início 2.0 (dia a dia e primeira vez) e tela Ambiente (⌘5) separada; recentes locais; `home.summary` ([spec](design/home/README.md)) |

A branch de trabalho é `melhoria/2026-10-15-rodada2-funcionalidades`, com as
tags v3.8.0, v3.9.0 e v3.10.0 locais e ainda sem push.

## Decisões que não mudam sem conversa

- Motor Python headless + front SwiftUI, conversando por stdio
  ([ADR 0001](adr/0001-motor-python-front-swift.md)).
- Liquid Glass com controles nativos ([ADR 0002](adr/0002-redesenho-liquid-glass.md)).
- Relatório com o `tag_audit` como núcleo, Markdown/TSV/board no formato
  portado ([ADR 0003](adr/0003-relatorio-tagueamento.md)).
- HTTPS no Android pelo log do OkHttp, não por MITM
  ([ADR 0004](adr/0004-https-sem-proxy-android.md)).
- App Tk congelado; o produto é o app nativo
  ([ADR 0005](adr/0005-app-tk-congelado.md)).
- **Tudo roda local.** Integridade dos dados: nada de nuvem, telemetria ou
  login. O Maestro só por `tools/maestro_offline/maestro-offline.sh`, e o HTML
  exportado bloqueia rede por política de conteúdo.

## Onde procurar mais

- Índice da documentação: [docs/README.md](README.md)
- Instalação por recurso, Mac e Windows: [INSTALACAO.md](INSTALACAO.md)
- Segurança: [SEGURANCA.md](SEGURANCA.md) · QA: [QA.md](QA.md) · Release: [RELEASE.md](RELEASE.md)
- Desempenho do relatório: [DESEMPENHO_RELATORIO.md](DESEMPENHO_RELATORIO.md)
- Maestro: [research/maestro-modelo-de-automacao.md](research/maestro-modelo-de-automacao.md)
- Pendências antigas: [RODADA_2026-10-05_PENDENCIAS.md](RODADA_2026-10-05_PENDENCIAS.md)

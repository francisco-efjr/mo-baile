# Estudo de mercado · Frente 4 de 4

## Qualidade de software, geração de teste e posicionamento de mercado

Data: 29/09/2026. Autor: consultor-pesquisador (agente).
Escopo: geração de código e localizadores, auto-cura e flakiness, relatórios,
acessibilidade mobile, qualidade de código e arquitetura, tendências de IA e
mercado de ferramentas de QA mobile. No fim, confronto com o código do Mo baile
e recomendações.

**Como ler.** Cada ficha separa o que a ferramenta é (fato, com fonte) do que
isso significa para o Mo baile (opinião, em seção marcada). Fonte primária é
documentação oficial, repositório, changelog ou artigo acadêmico. Página de
fornecedor sobre si mesmo e agregador de preços (G2, Capterra, blogs de
comparação) contam como **indício** e estão marcados assim. Onde não houve
fonte, está escrito "não verificado". Todos os acessos foram feitos em
29/09/2026; preço muda com frequência e deve ser reconferido antes de qualquer
decisão comercial.

---

## 1. Resumo executivo

1. **O mercado já convergiu em como escolher um localizador.** Playwright,
   Appium e Maestro dizem a mesma coisa com palavras diferentes: preferir o que
   o usuário e a acessibilidade enxergam (papel, rótulo, id de acessibilidade),
   exigir que o seletor case com **exatamente um** elemento, e deixar XPath e
   coordenada como último recurso. O Playwright faz disso regra de execução
   (strict mode). O Mo baile tem a intenção certa em `rank_locators`, mas a
   implementação tem um defeito que entrega seletor ambíguo marcado como único
   (reproduzido na seção 11).

2. **Flakiness é, antes de tudo, espera.** No maior estudo acadêmico sobre
   teste de UI instável (235 casos, web e Android), 45% vieram de espera
   assíncrona. Seletor frágil é minoria. A ferramenta que mais reduziu
   flakiness no mobile, o Maestro, fez isso com espera automática e nova
   tentativa contra a árvore mais recente, não com IA. O executor do Mo baile
   hoje repete **coordenada** com `sleep(1.0)` fixo e ignora o localizador que
   gerou.

3. **Auto-cura funciona quando é conservadora e auditável.** O que tem
   evidência: múltiplos localizadores por passo com queda ordenada (Selenium
   IDE, Katalon), modelo de atributos com limiar de confiança (Healenium,
   mabl, Testim) e, na pesquisa, similaridade ponderada de atributos (Similo:
   11% de falha contra 27% do baseline). O que é marketing: números como
   "99,9% de cura" sem metodologia. O risco real é o falso positivo, o teste
   que passa clicando no elemento errado. Os produtos sérios exigem aprovação
   humana da cura (Katalon) ou só gravam a cura quando a execução inteira
   passa (mabl).

4. **Relatório de teste virou linha do tempo navegável.** O Trace Viewer do
   Playwright é a referência: por ação, snapshot antes/depois, rede, console e
   linha de código. Nenhuma ferramenta mobile entrega isso junto com **rede e
   eventos de analytics**. O Mo baile já captura as três coisas (passo, HTTP,
   Firebase), com timestamp em duas delas. Essa é a oportunidade de
   diferenciação mais barata e mais defensável que encontrei.

5. **Acessibilidade deixou de ser opcional.** EAA em vigor desde 28/06/2025 na
   UE, LBI art. 63 e ABNT NBR 17060:2022 no Brasil, WCAG2Mobile publicado em
   rascunho pela W3C em maio de 2025. As ferramentas mobile (Accessibility
   Scanner, `performAccessibilityAudit`, axe DevTools Mobile, Evinced) checam
   um núcleo parecido: rótulo, área de toque, contraste, texto cortado. Boa
   parte disso sai da árvore e da captura que o Mo baile já tem.

6. **IA em teste mobile: adoção real existe, mas no formato "agente com
   ferramentas determinísticas".** O padrão vencedor de 2025/2026 é o agente
   que lê a árvore de acessibilidade por MCP (Playwright MCP, mobile-mcp com
   8,4 mil estrelas, Appium MCP, Maestro MCP), não o agente que "olha a tela".
   Confiança continua baixa: 46% dos desenvolvedores desconfiam da precisão da
   IA (Stack Overflow 2025) e só 15% das empresas escalaram GenAI em QE (World
   Quality Report 2025). O motor do Mo baile já fala JSON-RPC 2.0 sobre stdio,
   que é o transporte do MCP.

7. **Mercado.** Quem cobra por minuto de dispositivo é quem hospeda aparelho
   (AWS, Firebase, BrowserStack, Maestro Cloud). Ferramenta local de desktop
   cobra por assento, muitas vezes com licença perpétua (Proxyman: US$ 89 a
   US$ 99 por pessoa; time a US$ 12 por assento/mês). O Mo baile não hospeda
   aparelho e não deveria competir nesse eixo.

**Posicionamento proposto** (seção 13): o Mo baile é o inspetor local, sem SDK
no app e sem nuvem, que liga **passo de UI, requisição HTTP e evento de
analytics na mesma linha do tempo** e gera Page Object Appium com localizador
validado contra a tela. Público: QA e dev de times mobile em empresa que
precisa provar tagueamento, contrato de API e acessibilidade (banco, fintech,
varejo, seguradora). Distribuição: núcleo aberto e gratuito, Pro por assento
para exportação de trace, relatório de acessibilidade e execução em CI.

---

## 2. Bloco A · Geração de código e localizadores

### 2.1 Playwright codegen e estratégia de locators

**O que é.** Gerador de teste do Playwright (Microsoft, Apache-2.0) que grava
interação no navegador e emite código de teste, e a API de locators que o
código gerado usa.

**Como escolhe o localizador.** A documentação diz que o codegen "olha a
página e descobre o melhor locator, priorizando role, text e test id", e que,
se houver mais de um elemento casando, "melhora o locator para torná-lo
resiliente e identificar o alvo de forma única"
([codegen](https://playwright.dev/docs/codegen)).

**Como valida.** Por construção da API: locators são **estritos**. Toda ação
que implica um elemento "lança exceção se mais de um elemento casar"
([locators](https://playwright.dev/docs/locators)). `.first()`, `.last()` e
`.nth()` existem, mas a documentação os desaconselha porque a página muda e o
índice passa a apontar outro elemento. Cada uso do locator reavalia o DOM
(auto-wait e retry). Ordem recomendada: `getByRole`, `getByText`,
`getByLabel`, `getByTestId`, outros atributos, e CSS/XPath "só como último
recurso", porque "podem quebrar quando a estrutura do DOM muda".

**Funcionalidades-chave do gravador.** Asserções durante a gravação (assert
visibility, text, value); "pick locator"; gravar a partir do cursor num teste
existente; emulação de dispositivo, viewport, idioma, fuso, geolocalização;
salvar e carregar estado de autenticação.

**Tecnologia.** Instrumentação do navegador via protocolos próprios (CDP no
Chromium e equivalentes patcheados em Firefox e WebKit), não WebDriver.

**Preço e licença.** Gratuito, Apache-2.0.

**Pontos fortes.** Estrictez como regra de execução, não como conselho.
Seletor orientado a acessibilidade, que por tabela incentiva app acessível.
Asserção gravada junto com a ação.

**Pontos fracos.** Web apenas. O código gerado ainda pede edição para virar
teste com Page Object.

### 2.2 Appium: estratégias dos drivers e Appium Inspector

**O que é.** Appium é o padrão de fato para automação mobile via protocolo
WebDriver, com drivers por plataforma: UiAutomator2 (Android) e XCUITest (iOS).
Appium 3 saiu em agosto de 2025, com o Inspector passando a rodar como plugin
do servidor (`appium plugin install inspector`) e com mascaramento de dado
sensível em log via cabeçalho `X-Appium-Is-Sensitive`
([release do Inspector 2025.8.2](https://github.com/appium/appium-inspector/releases/tag/v2025.8.2);
resumo de mudanças em [Codoid](https://codoid.com/mobile-application-testing/appium-3-features-migration-guide/), indício).

**Estratégias e desempenho, pela documentação dos drivers.**

| Driver | Estratégia | Nota do próprio driver |
|---|---|---|
| XCUITest | `accessibility id`, `id`, `name` | todos são alias do atributo `name`; 5 estrelas |
| XCUITest | `-ios predicate string` | nativo do XCTest; 5 estrelas |
| XCUITest | `-ios class chain` | nativo, respeita hierarquia; 4 estrelas |
| XCUITest | `xpath` | não nativo, exige gerar a árvore XML; "pode ser até 10x mais lento"; 2 estrelas |
| UiAutomator2 | `id`, `accessibility id`, `class name` | `By.res`, `By.desc`, `By.clazz`; 5 estrelas |
| UiAutomator2 | `-android uiautomator` | `UiSelector`, permite rolagem; 4 estrelas; Google anunciou remoção futura de `UiSelector` |
| UiAutomator2 | `xpath` | usa a mesma árvore do page source; 3 estrelas |

Fontes: [XCUITest locator strategies](https://appium.github.io/appium-xcuitest-driver/latest/reference/locator-strategies/),
[UiAutomator2 driver](https://github.com/appium/appium-uiautomator2-driver).

Detalhe que importa para o Mo baile: no XCUITest, **accessibility id é o
atributo `name`**, não o `label`.

**Appium Inspector.** Mostra uma tabela "Suggested Locators" com uma ou mais
estratégias para o elemento selecionado e permite medir o tempo de busca de
cada uma, adicionando uma coluna com o tempo até o elemento voltar
([Inspector, aba Source](https://appium.github.io/appium-inspector/latest/session-inspector/source/)).
A documentação não descreve o algoritmo de sugestão nem se valida unicidade
(não verificado). Tem aba Recorder que gera código cliente.

**Preço e licença.** Gratuito, open source (Apache-2.0 no Appium).

**Pontos fortes.** Padrão de mercado, multilinguagem, ecossistema de drivers e
plugins. Tempo de busca medido de verdade, contra o aparelho.

**Pontos fracos.** Captura estática e lenta, que é a dor declarada do público
do Mo baile. Sugestão de seletor sem explicação de por que um é melhor.

### 2.3 Maestro e Maestro Studio

**O que é.** Framework de teste de UI mobile e web com fluxos em YAML
(mobile.dev, CLI open source). Caixa-preta: "pilota o aparelho em vez do código
interno do app", instalando um pequeno app-driver companheiro no aparelho e
lendo a árvore de acessibilidade
([how Maestro works](https://docs.maestro.dev/get-started/how-maestro-works.md)).

**Localizadores.** Seletores por texto (com regex), id, índice, traços e
estado, e seletores relacionais (`above`, `below`, `leftOf`, `rightOf`,
`childOf`, `containsChild`, `containsDescendants`). A documentação recomenda
combinar relacional com atributo estável e "usar sempre o elemento mais
estável como âncora"
([relational selectors](https://docs.maestro.dev/reference/selectors/relational-selectors.md)).

**Como lida com flakiness.** Espera automática para a tela "assentar" e nova
tentativa contra a árvore mais recente, sem `sleep()` manual
([how Maestro works](https://docs.maestro.dev/get-started/how-maestro-works.md)).
Comandos de espera explícita existem para os casos restantes
(`waitForAnimationToEnd`, `extendedWaitUntil`, `scrollUntilVisible`).

**Maestro Studio.** App de desktop gratuito. Clique com o botão direito num
elemento do aparelho conectado adiciona o comando YAML com o seletor já
resolvido; o editor autocompleta com "seletores reais puxados da tela do
aparelho conectado"; toda execução é gravada e dá para voltar a qualquer passo
([Studio](https://docs.maestro.dev/maestro-studio/maestro-studio-overview.md)).

**IA e MCP.** Comandos `assertWithAI`, `extractTextWithAI`,
`assertNoDefectsWithAI`. Servidor MCP embutido na CLI, via stdio, com
ferramentas `list_devices`, `inspect_screen` (árvore em JSON compacto),
`take_screenshot`, `run` (YAML inline), `run_on_cloud`, `cheat_sheet`
([Maestro MCP](https://docs.maestro.dev/get-started/maestro-mcp.md)).

**Preço.** Local gratuito (CLI, Studio, MCP, Viewer, "self-healing com agentes
locais"). Cloud a US$ 250 por dispositivo/mês, medido por concorrência máxima.
Enterprise sob consulta ([pricing](https://maestro.dev/pricing)).

**Pontos fortes.** Menor tempo até o primeiro teste do segmento. Espera
automática resolve a principal causa de instabilidade. YAML legível por quem
não programa.

**Pontos fracos.** YAML limita lógica complexa. Não gera Page Object; quem já
tem suíte Appium não migra fácil.

### 2.4 Selenium IDE

**O que é.** Gravador e reprodutor web open source (Apache-2.0), mantido pela
comunidade Selenium, hoje em Electron, Node e React
([repositório](https://github.com/seleniumhq/selenium-ide)).

**Como escolhe e valida.** Cada passo gravado guarda **vários localizadores
candidatos** (id, CSS, variações de XPath) num array `targets`. Na reprodução,
se o primeiro falha, tenta o seguinte até esgotar
([QAFox, estratégia de fallback](https://www.qafox.com/new-selenium-ide-fallback-locators-strategy/),
indício; confirmado por issue do projeto sobre o localizador secundário não ser
usado em alguns comandos, [#1090](https://github.com/SeleniumHQ/selenium-ide/issues/1090)).

**Pontos fortes.** O multi-localizador mais simples possível, sem IA, e
auditável.

**Pontos fracos.** Queda silenciosa: o teste passa pelo segundo seletor e
ninguém fica sabendo que o primeiro quebrou. Projeto com ritmo de manutenção
irregular (não verificado em números).

### 2.5 Katalon Recorder e Katalon Studio

**O que é.** Recorder é extensão de navegador gratuita. Studio é IDE de
automação web, API e mobile (sobre Selenium e Appium).

**Como escolhe e valida.** Auto-cura em dois níveis. **Clássico**: quando o
localizador original falha, tenta os outros localizadores conhecidos do objeto,
numa ordem configurável (para mobile: Accessibility ID, XPath, Image,
UIAutomator). **IA**: se nenhum funciona, um LLM analisa fonte da página,
árvore de acessibilidade e captura para propor um novo. Depois da execução, o
painel "Self-healing Insights" mostra seletor quebrado, proposta, método e
captura do objeto, e a pessoa **aprova ou descarta**
([docs de self-healing](https://docs.katalon.com/katalon-studio/maintain-tests/self-healing-tests-in-katalon-studio)).

**Preço.** Plano gratuito; Professional a partir de US$ 84 por assento/mês
([pricing](https://katalon.com/pricing), valor via agregador, indício).

**Pontos fortes.** Aprovação humana explícita da cura. Ordem de estratégias
configurável por projeto.

**Pontos fracos.** Plataforma pesada e proprietária; lock-in no formato de
objeto de teste.

### 2.6 Gravadores nativos (Espresso Test Recorder, gravação do Xcode)

Existem e são documentados
([Espresso Test Recorder](https://developer.android.com/studio/test/other-testing-tools/espresso-test-recorder)),
mas a gravação de UI test do Xcode tem histórico de falhas por versão
(fórum da Apple, [thread 123069](https://developer.apple.com/forums/thread/123069))
e produz código sem abstração nem reuso. Ficam como referência de que
"gravar" sozinho não resolve: o valor está no que o gravador faz depois.

### 2.7 Síntese do bloco A

| Ferramenta | Prioridade de seletor | Valida unicidade? | Guarda alternativas? | Espera automática |
|---|---|---|---|---|
| Playwright | role > text > label > test id > CSS/XPath | sim, erro em execução (strict) | não, refina o único | sim |
| Appium Inspector | sugere várias | não documentado | mostra lista e tempo | não (é do cliente) |
| Maestro | id/texto + relacional | recomenda âncora estável | não | sim, retry contra árvore nova |
| Selenium IDE | id > CSS > XPath | não | sim, `targets` | parcial |
| Katalon | configurável | não documentado | sim, com cura aprovada | sim |
| **Mo baile hoje** | id > a11y > texto > XPath > posição | **tenta, com defeito** (seção 11) | calcula e devolve, **não usa** | **não**, `sleep(1.0)` fixo |

---

## 3. Bloco B · Auto-cura e redução de flakiness

### 3.1 O que a evidência diz antes do marketing

- Google: cerca de 1,5% das execuções de teste davam resultado instável, e
  flakiness respondia por cerca de 16% das falhas observadas
  ([Google Testing Blog, 2016](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)).
- Romano et al., ICSE 2021: 235 testes de UI instáveis em 62 projetos web e
  Android. **45% são espera assíncrona**. Outras categorias: animação, diferença
  de plataforma, uso errado da API do runner e fragilidade de seletor
  ([arXiv 2103.02669](https://arxiv.org/abs/2103.02669)).
- Nass et al., "Similo", TOSEM 2023: localizar pelo **grau de similaridade de
  vários atributos ponderados** errou 91 de 801 elementos (11%) contra 214
  (27%) do baseline de localizador único, em 48 sites populares; a extensão
  VON Similo ganhou +9,9% de acurácia
  ([arXiv 2208.00677](https://arxiv.org/pdf/2208.00677),
  [VON Similo](https://arxiv.org/html/2301.03863)).
- Revisão de ferramentas de teste com IA: as ferramentas de auto-cura "não são
  totalmente capazes de reparar todos os localizadores" nem de lidar bem com
  suítes grandes ([arXiv 2409.00411](https://arxiv.org/pdf/2409.00411)).

Leitura: consertar localizador ataca a minoria das falhas. Espera correta
ataca a maioria. E multi-atributo com pontuação tem base empírica; "IA que
cura tudo" não tem.

### 3.2 Fichas

**Testim (Tricentis).** Smart locators: acompanha o desempenho dos
localizadores entre execuções e atualiza o modelo com os atributos mais
estáveis. No mobile, "ML locators" com modelo treinado em dezenas de milhares
de apps e pontuação de confiança
([Tricentis, blog de locators](https://www.tricentis.com/blog/testim-locator-technologies),
indício de fornecedor; [docs Testim Mobile](https://docs.tricentis.com/all/manuals/testim_mobile.htm)).
Preço não publicado; Community gratuito, demais planos sob cotação
([pricing Testim Mobile](https://www.tricentis.com/products/testim-mobile/pricing)).
Forte: modelo de elemento que aprende. Fraco: caixa-preta, preço opaco,
lock-in.

**mabl.** Guarda histórico de atributos do elemento, incluindo ancestrais e
test ids, e procura "uma correspondência forte com o modelo aprendido". Se a
confiança não basta, tenta auto-cura; na nuvem, uma cura "avançada" com IA
generativa, que só liga após 5 execuções bem-sucedidas do plano. **O modelo do
elemento só é atualizado quando o teste inteiro passa e faz parte de um plano**;
execução local e ad hoc registra a tentativa mas não persiste
([How auto-heal works](https://help.mabl.com/hc/en-us/articles/19078583792404-How-auto-heal-works)).
Preço: base com 500 créditos de execução em nuvem por mês; valores de US$ 499/mês
em diante reportados por terceiros (indício,
[mabl pricing](https://www.mabl.com/pricing)); app nativo é add-on pago.
Forte: regra de persistência que evita "aprender errado". Fraco: SaaS caro,
mobile nativo como extra.

**Healenium (EPAM).** Open source, Apache-2.0. Proxy entre cliente e
Selenium/Appium. Guarda o último localizador bem-sucedido como base; ao
capturar `NoSuchElement`, compara o estado atual com o caminho salvo por um
algoritmo de subsequência comum mais longa e gera candidatos pontuados.
Parâmetros: `score-cap` (limiar de 0 a 1), `recovery-tries`, `heal-enabled`,
anotação `@DisableHealing` para testes que verificam ausência. Exige
`hlm-backend`, PostgreSQL e `hlm-imitator` via Docker Compose. Gera relatório
com o localizador curado, captura e botão de feedback
([how it works](https://healenium.io/docs/how_healenium_works),
[healenium-web](https://github.com/healenium/healenium-web),
[healenium-appium](https://github.com/healenium/healenium-appium)).
Forte: aberto, com limiar explícito. Fraco: infraestrutura pesada para o que
faz; Java.

**Functionize.** Plataforma enterprise de "agentes" que criam, executam e
curam testes. Anuncia "99,9% de cura" e "80% menos flakiness"
([self-healing](https://www.functionize.com/self-healing), marketing, sem
metodologia publicada). Preço só enterprise; faixa de US$ 5 mil a 15 mil/mês
citada por agregador (indício). Foco web.

**Applitools (Eyes, Visual AI, Ultrafast Grid).** Comparação visual por IA com
níveis de correspondência (Strict, Layout, Content) para ignorar mudança
irrelevante e pegar a relevante
([match levels](https://applitools.com/docs/eyes/concepts/best-practices/match-levels)).
O Ultrafast Grid sobe **snapshot de DOM**, não captura, e renderiza em paralelo
em contêineres para vários navegadores e viewports, reaproveitando recursos
inalterados ([docs UFG](https://applitools.com/docs/eyes/concepts/test-execution/ultrafast-grid)).
Preço: Starter a US$ 667/mês anual, com 1.000 checkpoints de página ou 100 mil
de componente; demais sob consulta; aparelho real iOS/Android como add-on
enterprise ([pricing](https://applitools.com/pricing/)). Forte: o melhor
comparador visual do mercado. Fraco: o truque do UFG é web (DOM); em app nativo
não há DOM para re-renderizar.

**Percy e App Percy (BrowserStack).** Teste visual por captura com revisão.
Gratuito com 5.000 capturas/mês no web e 1.000 no App Percy; Professional a
US$ 149/mês anual com 25 mil capturas
([plans and billing](https://www.browserstack.com/docs/percy/overview/plans-and-billing),
[App Percy](https://www.browserstack.com/docs/app-percy/overview/plans-and-billing)).
Forte: tier gratuito generoso. Fraco: diff visual de app nativo sofre com
conteúdo dinâmico.

**testRigor.** Testes escritos em inglês livre, interpretados por motor de NLP;
o localizador fica escondido do autor. Suporta nativo e híbrido iOS/Android.
Preço: público gratuito; privado a partir de cerca de US$ 900/mês
([agregadores](https://www.getapp.com/it-management-software/a/testrigor/),
indício; página oficial de preço fora do ar no acesso). Forte: autoria por não
programador. Fraco: nuvem obrigatória, pouca transparência do que foi
clicado.

**Playwright Healer (Test Agents, v1.56, outubro de 2025).** Reexecuta os
passos que falharam, inspeciona a UI atual para achar elemento equivalente,
**sugere um patch** e reexecuta; o resultado é teste verde ou teste marcado
como `skip` "se o healer acreditar que a funcionalidade está quebrada"
([test agents](https://playwright.dev/docs/test-agents)). Forte: o patch é
código revisável em PR, não mágica em tempo de execução. Fraco: depende de LLM
configurado; web.

### 3.3 O que funciona e o que é marketing

| Técnica | Evidência | Veredito |
|---|---|---|
| Espera automática e retry contra árvore nova | Romano 2021 (45% é espera); adoção do Maestro | **funciona**, e é o maior ganho |
| Strict mode (seletor tem de casar com um) | Playwright | **funciona**, evita a classe inteira de "clicou no primeiro" |
| Multi-localizador com queda ordenada | Selenium IDE, Katalon clássico, Leotta | funciona se a queda for **reportada** |
| Similaridade ponderada de atributos | Similo (11% vs 27%) | **funciona**, com base acadêmica |
| Modelo de elemento que aprende entre execuções | mabl, Testim | plausível; só persiste quando a execução passa (mabl) |
| Cura por LLM com patch revisável | Playwright Healer, Katalon IA | útil, desde que vire PR e não mutação silenciosa |
| "99,9% de cura", "80% menos flaky" | só página do fornecedor | **marketing** até haver metodologia |
| Cura visual por pixel em app nativo | Applitools/Percy mobile | funciona para regressão visual; não substitui localizador |

O risco que todos os sérios tratam: **falso positivo**. Teste que passa porque
curou para o elemento errado é pior que teste vermelho. Mitigações
observadas: limiar de confiança (Healenium `score-cap`), aprovação humana
(Katalon), persistência só em execução verde (mabl), desativar cura em teste
de ausência (`@DisableHealing`).

---

## 4. Bloco C · Relatórios e observabilidade de teste

**Allure Report.** Open source, agnóstico de framework. Adaptadores gravam JSON
em `allure-results`; um gerador monta HTML estático. Passos, anexos,
categorias, histórico, retry e marcação de instável; mais de 30 frameworks,
incluindo pytest ([docs](https://allurereport.org/docs/)). O Allure 3 é
reescrita em TypeScript com sistema de plugins e modo de relatório em tempo
real (`watch`) ([allure3](https://github.com/allure-framework/allure3)).
Allure TestOps (gestão) custa por usuário: cerca de US$ 30 on-premise e US$ 39
na nuvem ([server pricing](https://qameta.io/server-pricing), valores via
agregador, indício).

**ReportPortal.** Open source, Apache-2.0, da EPAM. Serviços com PostgreSQL,
OpenSearch e um serviço Analyzer. A auto-análise usa falhas já investigadas por
humanos como base: numa falha nova, busca similaridade no texto do erro e, acima
de um limiar, herda o tipo de defeito (Product Bug, Automation Bug, System
Issue, No Defect). Tem Pattern Analysis e Unique Error, que agrupa falhas
idênticas ([auto-analysis](https://reportportal.io/docs/analysis/AutoAnalysisOfLaunches/),
[docs](https://reportportal.io/docs/)). Quality gates são pagos.

**Currents.** Painel de CI focado em Playwright (e Cypress): detecção de
flaky, orquestração de paralelismo, traces, vídeo. US$ 49/mês com 10 mil
resultados, depois US$ 4,90 por mil; Business a US$ 99/mês
([pricing](https://currents.dev/pricing)).

**Playwright Trace Viewer.** Por ação: linha do tempo com filmstrip, snapshots
de DOM antes, durante e depois (com o ponto exato do clique), requisições de
rede filtráveis por ação, console, linha de código-fonte, erro. Modos
`on-first-retry`, `retain-on-failure`, `on`. Abre local
(`show-trace`) ou em trace.playwright.dev, processado só no navegador
([trace viewer](https://playwright.dev/docs/trace-viewer)).

**Síntese.** O padrão ouro tem quatro elementos: (1) artefato único e
portátil por execução, (2) passo a passo com estado visual antes/depois,
(3) rede correlacionada ao passo, (4) histórico entre execuções para detectar
instabilidade. Allure e ReportPortal cobrem (4) e parte de (2). Trace Viewer
cobre (1) a (3) no web. **No mobile, ninguém cobre (3) com eventos de
analytics**, que é justamente o que o Mo baile captura.

---

## 5. Bloco D · Acessibilidade mobile como qualidade

### 5.1 Norma e lei

- **WCAG 2.2**, SC 2.5.8 Target Size (Minimum), nível AA: alvo de toque de pelo
  menos 24 por 24 CSS px, com exceções de espaçamento, equivalente, inline,
  controle do agente e essencial
  ([Understanding 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)).
- **WCAG2Mobile**: Group Draft Note da W3C de 06/05/2025. Informativa, não
  normativa. Troca "página" por "tela" ou "view" e trata uma tela como a
  unidade de avaliação; destaca 2.5.8, orientação (1.3.4) e reflow (1.4.10)
  ([WCAG2Mobile](https://www.w3.org/TR/wcag2mobile-22/)).
- **Plataformas** pedem mais que o WCAG: Android recomenda 48 x 48 dp de área
  de toque e contraste de 4,5:1 para texto pequeno e 3:1 para o resto
  ([Android accessibility](https://developer.android.com/guide/topics/ui/accessibility/apps));
  a Apple recomenda 44 x 44 pt ([HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility),
  não reconsultado nesta sessão).
- **European Accessibility Act**: aplicável desde 28/06/2025 a e-commerce,
  bancos, telecom e transporte, com app incluído; norma técnica EN 301 549
  ([Level Access](https://www.levelaccess.com/compliance-overview/european-accessibility-act-eaa/),
  indício; [Wikipedia](https://en.wikipedia.org/wiki/European_Accessibility_Act)).
- **Brasil**: LBI (Lei 13.146/2015) art. 63 obriga acessibilidade em sites de
  empresas com sede ou representação no país; **ABNT NBR 17060:2022** traz 54
  requisitos para apps nativos, híbridos e web apps, alinhados ao WCAG
  ([CTA IFRS](https://cta.ifrs.edu.br/abnt-nbr-17060-2022-acessibilidade-em-aplicativos-de-dispositivos-moveis-requisitos/),
  [NIC.br](https://nic.br/noticia/releases/norma-da-abnt-sobre-acessibilidade-para-dispositivos-moveis-torna-a-navegacao-mais-inclusiva/)).

### 5.2 Ferramentas

**Android Accessibility Scanner (Google).** App no aparelho. Checa rótulo de
conteúdo, área de toque, item clicável e contraste de texto e imagem. Modo
snapshot (uma tela) e gravação (várias telas enquanto se navega). A própria
Google avisa que "não substitui teste manual"
([suporte](https://support.google.com/accessibility/android/answer/6376570)).
O motor por trás é o **Accessibility Test Framework for Android (ATF)**,
Apache-2.0, que roda checagens sobre `View` e `AccessibilityNodeInfo` e monta
um `AccessibilityHierarchy` analisável
([ATF](https://github.com/google/Accessibility-Test-Framework-for-Android)).

**Xcode Accessibility Inspector e `performAccessibilityAudit`.** Desde o Xcode
15 (WWDC23), `XCUIApplication.performAccessibilityAudit()` roda num UI test a
mesma auditoria do Inspector e falha o teste se achar problema. Tipos:
`contrast`, `elementDetection`, `hitRegion`, `sufficientElementDescription`,
`dynamicType`, `textClipped`, `trait`
([WWDC23 10035](https://developer.apple.com/videos/play/wwdc2023/10035/);
[resumo](https://www.polpiella.dev/xcode-15-automated-accessibility-audits/), indício).

**axe DevTools for Mobile (Deque).** Regras para iOS e Android nativos e
multiplataforma (React Native, Flutter, .NET MAUI). Plugin Appium que não exige
código Deque no app; em 2026 ganhou Auto Scan para os drivers Appium e suporte
a Appium 3 e iOS 26
([Appium plugin](https://docs.deque.com/devtools-mobile/2025.7.2/en/appium/),
[anúncio](https://www.deque.com/blog/deque-adds-new-appium-plugin-to-axe-devtools-mobile/)).
Preço mobile não publicado (não verificado).

**Evinced.** SDKs para Appium, XCUITest e Espresso ("5 linhas de código") e o
Mobile Flow Analyzer, que dispensa SDK e acesso ao código; detecta nome
acessível, área tocável e contraste, entre outros
([SDKs](https://www.evinced.com/products/auto-test-sdks),
[MFA](https://www.evinced.com/products/flow-analyzer-for-mobile)).
Preço não publicado.

### 5.3 O que dá para checar só com árvore e captura

| Checagem | Precisa de | Mo baile tem hoje? |
|---|---|---|
| Elemento clicável sem rótulo (sem `text` nem `content-desc`/`label`) | árvore | sim, `UIElement` |
| Rótulo duplicado entre clicáveis na mesma tela | árvore | sim |
| Área de toque abaixo de 48 dp / 44 pt | árvore + densidade | bounds sim; densidade não (Android `wm density`; iOS já vem em pontos) |
| Contraste de texto | captura + bounds | sim (screencap e bounds) |
| Texto cortado, Dynamic Type | executar com fonte ampliada | não |
| Ordem de foco, traits, estado | atributos extras | não: o parser descarta `enabled`, `checked`, `focusable`, `password` etc. |

---

## 6. Bloco E · Qualidade de código e arquitetura como ferramenta

| Ferramenta | O que é | Licença e preço | Para o Mo baile |
|---|---|---|---|
| SonarQube / SonarQube Cloud | análise estática multilinguagem, quality gate | Community Build LGPLv3, analisadores sob licença source-available desde nov/2024; Cloud grátis até 50 mil LOC, Team a partir de cerca de € 30/mês ([planos](https://www.sonarsource.com/plans-and-pricing/), [licença](https://www.sonarsource.com/license/)) | redundante com ruff + bandit hoje; útil só se o front Swift entrar na análise |
| CodeScene | análise comportamental: hotspots (código ruim que muda muito), Code Health de 1 a 10 | € 18 por autor ativo/mês; gratuito para open source ([pricing](https://codescene.com/pricing)) | bom sinal para priorizar refatoração de `rpc/server.py` |
| Semgrep | SAST por regras em padrão de código | CE sob LGPL-2.1; regras mantidas pela Semgrep sob licença própria restritiva; Team US$ 35/contribuidor/mês ([licensing](https://semgrep.dev/docs/licensing)); fork **Opengrep** LGPL-2.1 desde jan/2025 ([opengrep](https://www.opengrep.dev/)) | **adotar**: regras próprias codificam as invariantes de segurança já descobertas |
| Snyk | SCA, SAST, container, IaC | grátis com cota de testes; Team a partir de cerca de US$ 25/dev/mês (indício, [agregador](https://dev.to/rahulxsingh/snyk-pricing-in-2026-free-plan-team-business-and-enterprise-costs-breakdown-5e88)) | `pip-audit` já cobre SCA do motor; dispensável |
| DeepSource | análise estática com Autofix | grátis 1 repo privado; Starter US$ 8/assento ([pricing](https://deepsource.com/pricing), via agregador) | dispensável |
| Codacy | agregador de linters | Team cerca de US$ 18 a 21/usuário; grátis para open source (indício) | dispensável |
| Structurizr / C4 | arquitetura como código (DSL) no modelo C4 | DSL open source ([Structurizr](https://structurizr.com/), [C4](https://c4model.com/)) | útil para `docs/ARQUITETURA.md` e para o que o produto pode **oferecer** |
| ArchUnit | teste de arquitetura em Java | Apache-2.0 ([archunit.org](https://www.archunit.org/)) | referência de ideia; o equivalente Python é o import-linter |
| import-linter | contratos de import em Python: `layers`, `forbidden`, `independence` | open source ([layers](https://import-linter.readthedocs.io/en/latest/contract_types/layers/)) | **adotar já**: a regra de camadas do motor passa hoje (verificado por grep) e não tem guarda no CI |

**O que o Mo baile pode oferecer a partir disso (não só adotar).** Duas
coisas têm afinidade com o produto: (1) "lint de testabilidade" do app sob
teste, isto é, apontar tela com elementos clicáveis sem id estável, que é o
equivalente mobile de "adicione `data-testid`" e conversa com acessibilidade;
(2) exportar a arquitetura de telas descoberta na gravação (tela, transição,
endpoint chamado) como diagrama. A primeira é barata e vendável; a segunda é
curiosidade.

---

## 7. Bloco F · Tendências 2025/2026: agentes, MCP, linguagem natural

### 7.1 O que existe

| Iniciativa | Forma | Como enxerga a tela | Licença / preço | Fonte |
|---|---|---|---|---|
| Playwright Test Agents (v1.56) | planner, generator, healer; plano em Markdown em `specs/` | árvore de acessibilidade via MCP | Apache-2.0 | [docs](https://playwright.dev/docs/test-agents) |
| Playwright MCP | servidor MCP | snapshot de acessibilidade com `ref` por elemento, sem visão | Apache-2.0 | [MCP snapshots](https://playwright.dev/mcp/snapshots) |
| Appium MCP | servidor MCP oficial do Appium | page source; `generate_locators` com prioridade "accessibility id > id > nativo > xpath"; visão opcional | Apache-2.0, cerca de 480 estrelas | [repo](https://github.com/appium/appium-mcp) |
| mobile-mcp (mobile-next) | servidor MCP, 30+ ferramentas | "accessibility-first", captura só como fallback | Apache-2.0, cerca de 8,4 mil estrelas | [repo](https://github.com/mobile-next/mobile-mcp) |
| Maestro MCP | embutido na CLI | `inspect_screen` em JSON compacto | grátis local | [docs](https://docs.maestro.dev/get-started/maestro-mcp.md) |
| Firebase App Testing agent | objetivos em linguagem natural, Gemini, sem SDK | não documentado | preview, Android | [Firebase blog](https://firebase.blog/posts/2025/04/app-testing-agent/) |
| KaneAI / Kane CLI (TestMu AI, ex-LambdaTest) | linguagem natural; exporta Appium, Playwright etc.; mobile em simulador/emulador desde set/2026 | "vision-grounded" | comercial | [press release](https://www.globenewswire.com/news-release/2026/09/10/3359678/0/en/testmu-ai-launches-mobile-automation-in-kane-cli-bringing-natural-language-test-automation-to-ios-simulators-and-android-emulators.html) |
| GPT Driver (MobileBoost) | comandos determinísticos com fallback de visão, dentro de XCUITest, Espresso, Appium | híbrido | já foi US$ 799/mês (indício) | [site](https://www.mobileboost.io/) |
| Arbigent | agente open source em Kotlin; cenários com dependência; usa Maestro por baixo; MCP | árvore otimizada + imagem | open source | [repo](https://github.com/takahirom/arbigent) |

### 7.2 Adoção real versus hype

- 84% dos desenvolvedores usam ou pretendem usar IA; **46% desconfiam da
  precisão**, contra 31% no ano anterior; 66% reclamam de solução "quase certa"
  ([Stack Overflow 2025](https://survey.stackoverflow.co/2025/ai),
  [press release](https://stackoverflow.co/company/press/archive/stack-overflow-2025-developer-survey/)).
- World Quality Report 2025: 89% pilotam ou usam GenAI em QE, 37% em produção,
  **15% em escala corporativa**
  ([Capgemini](https://www.capgemini.com/news/press-releases/world-quality-report-2025-ai-adoption-surges-in-quality-engineering-but-enterprise-level-scaling-remains-elusive/)).

**Leitura.** O que pegou de verdade foi a camada de ferramentas: MCP que dá ao
agente uma visão estruturada e determinística da tela e ações precisas. O
agente autônomo que "testa o app sozinho" segue em preview ou em nuvem cara. A
aposta sensata para uma ferramenta pequena é **ser a melhor fonte de verdade
para o agente**, com seletor validado e contexto de rede e analytics, e não
competir com o agente.

---

## 8. Bloco G · Mercado

### 8.1 Quem compra

Não há fonte primária confiável sobre tamanho do mercado de QA mobile; os
números que circulam são de relatório pago e de marketing (não verificado).
O que os modelos de preço revelam sobre o comprador:

- **Por paralelo ou minuto de dispositivo** (AWS Device Farm US$ 0,17/min ou
  US$ 250/slot/mês, [pricing](https://aws.amazon.com/device-farm/pricing/);
  Firebase Test Lab US$ 5/h físico e US$ 1/h virtual,
  [pricing](https://firebase.google.com/docs/test-lab/usage-quotas-pricing);
  BrowserStack App Automate cerca de US$ 199/mês anual por paralelo, indício,
  [pricing](https://www.browserstack.com/pricing); Maestro Cloud US$ 250 por
  dispositivo/mês): quem compra é engenharia/plataforma, com orçamento de
  infraestrutura de CI.
- **Por assento** (Katalon, Allure TestOps, Proxyman time): gerência de QA ou
  o próprio profissional.
- **Por volume de artefato** (Applitools por checkpoint, Percy por captura,
  Currents por resultado, mabl por crédito): quem já tem suíte grande e quer
  reduzir custo de manutenção.
- **Perpétua individual** (Proxyman US$ 89 a 99 com 1 ano de atualização;
  time a US$ 12/assento/mês ou US$ 99/assento/ano,
  [pricing](https://proxyman.com/pricing)): o desenvolvedor paga do bolso ou
  com cartão corporativo sem compras. É a categoria mais parecida com o Mo
  baile: ferramenta local de desktop, macOS, sem hospedar nada.

### 8.2 O que faz uma dev tool ser adotada

- **Tempo até o primeiro valor.** O Maestro vende "primeiro teste em minutos"
  e cumpre porque a espera automática remove a primeira frustração. Há quem
  fale em "menos de 4 minutos" como meta para dev tools
  ([Mixpanel](https://mixpanel.com/blog/product-adoption/) e similares, opinião,
  sem estudo por trás).
- **Estar onde o dev já está.** Appium Inspector virou plugin do servidor;
  Maestro, Playwright e Appium publicaram MCP; Proxyman anuncia MCP em todos os
  planos.
- **Artefato compartilhável.** Trace de Playwright, relatório Allure, HAR: o
  artefato é o que espalha a ferramenta dentro do time.
- **Não acoplar ao app.** Lição do Flipper: a integração nativa com o React
  Native foi retirada do template a partir da 0.74 porque "consumia esforço
  significativo" do ciclo de release
  ([proposta RN 0641](https://github.com/react-native-community/discussions-and-proposals/blob/main/proposals/0641-decoupling-flipper-from-react-native-core.md),
  [RN 0.73](https://reactnative.dev/blog/2023/12/06/0.73-debugging-improvements-stable-symlinks)).
  O Mo baile não exige SDK no app, o que é vantagem; o acoplamento equivalente
  dele é com versões de adb, WDA e Xcode.

---

## 9. Matriz comparativa

| | Gera código | Valida unicidade | Espera automática | Cura | Trace passo a passo | Rede no trace | Analytics no trace | A11y | Local sem nuvem | Preço de entrada |
|---|---|---|---|---|---|---|---|---|---|---|
| Playwright | sim | sim (strict) | sim | Healer (LLM, patch) | sim | sim | não | via axe | sim | grátis |
| Appium + Inspector | sim | não documentado | não | não | não | não | não | via plugins | sim | grátis |
| Maestro | YAML | orientação | sim | local com agente | gravação de execução | não | não | não | sim (Cloud à parte) | grátis / US$ 250 disp./mês |
| Selenium IDE | sim | não | parcial | fallback silencioso | não | não | não | não | sim | grátis |
| Katalon | sim | não documentado | sim | clássico + IA, com aprovação | sim | parcial | não | não | parcial | grátis / US$ 84 assento/mês |
| Testim | codeless | modelo ML | sim | ML | sim | não verificado | não | não | não | sob cotação |
| mabl | codeless | modelo | sim | modelo + GenAI | sim | sim | não | sim | não | cerca de US$ 499/mês (indício) |
| Healenium | não | limiar | não | LCS + score | relatório de cura | não | não | não | sim (self-host) | grátis |
| Applitools | não | n/a | n/a | visual | visual | não | não | sim | não | US$ 667/mês |
| testRigor | NL | oculto | sim | NLP | sim | não verificado | não | não verificado | não | cerca de US$ 900/mês (indício) |
| **Mo baile (hoje)** | **Page Object Appium Python** | **com defeito** | **não** | **não** | **não** | **captura, não correlaciona** | **captura, não correlaciona** | **não** | **sim** | proprietário, sem preço |

A coluna "Analytics no trace" é vazia para todo o mercado. É o espaço.

---

## 10. O que isso significa para o Mo baile (opinião)

A tese: o Mo baile não ganha competindo em IA de cura (Playwright, Maestro e
Katalon já comoditizaram), em nuvem de dispositivos (capital intensivo) nem em
comparação visual (Applitools tem anos de dados). Ele ganha onde já tem
matéria-prima que ninguém junta: **árvore + captura + toque + HTTP + Firebase,
localmente, sem SDK**. O trabalho é transformar essa matéria-prima em dois
produtos: (a) código de teste que roda de primeira e não fica instável, e
(b) um artefato de evidência que o time compartilha.

---

## 11. Confronto com o código

Arquivos lidos: `engine/src/mobaile/services/codegen.py`, `flows.py`,
`hierarchy.py`, `domain/models.py`, `rpc/server.py` (codegen, flow e escuta
passiva), `config.py`, `qa/README.md`,
`apps/MoBaile/Sources/MoBaile/Views/Automation/*.swift`,
`Views/Workspace/*.swift` (listagem), `Engine/EngineSession.swift` (gravação),
`engine/tests/unit/test_hierarchy_codegen.py`, `.github/workflows/ci.yml`.

### 11.1 O que já existe e está certo

- `rank_locators` com a ordem certa (id, acessibilidade, texto, XPath,
  posição), contagem de correspondências na tela e "por quê" de cada
  candidato. É a intenção do Playwright e do Katalon.
- Modo `auto` no RPC (`codegen.record` com `strategy: "auto"`) devolvendo as
  alternativas descartadas.
- Parser endurecido contra XML hostil; runner gerado sem interpolar conteúdo do
  usuário como código (passos entram por JSON).
- Escuta passiva que distingue toque de tecla com o teclado aberto e guarda o
  texto digitado no passo.
- Rede e analytics com `timestamp` (`NetworkEvent`, `AnalyticsEvent`).
- Camadas do motor limpas: `domain`, `ports` e `security` não importam
  `adapters` nem `services`; `services` não importa `adapters` (verificado com
  grep nos imports em 29/09/2026).
- Gravação de vídeo existe (`adapters/screen_recorder.py`, `recording.*` no
  RPC).

### 11.2 Defeitos e lacunas encontrados

**D1. O localizador "escolhido" não é o localizador gerado.** Reproduzido
agora, com três botões de mesmo `resource-id` e textos diferentes:

```
text      1 True  (AppiumBy.XPATH, '//android.widget.Button[@resource-id="app:id/item"]')
xpath     1 True  (AppiumBy.XPATH, '//android.widget.Button[@resource-id="app:id/item"]')
position  1 True  (AppiumBy.XPATH, '//android.widget.Button[@resource-id="app:id/item"]')
id        3 False (AppiumBy.ID, "app:id/item")
escolhido: text -> estrategia aplicada: xpath
valor gerado: (AppiumBy.XPATH, '//android.widget.Button[@resource-id="app:id/item"]')
```

Três causas somadas: (1) o candidato `text` conta unicidade pelo texto, mas o
valor vem de `_generate_xpath`, que prefere `resource-id`; (2) `xpath` e
`position` têm `matches: 1` fixo, sem contar nada; (3) o RPC traduz a escolha
para `LocatorStrategy` (`{"accessibility_id": "id", "text": "xpath"}`) e
`generate_locator_value` refaz a escolha por conta própria. Resultado: o
seletor emitido casa com três elementos e está marcado como único. O teste
`test_id_repetido_perde_para_alternativa_unica` passa porque confere o
**rótulo** da estratégia, não o **seletor** produzido.

**D2. Código gerado quebra com aspas.** Texto `Joao's "cartao"` gera
`//android.widget.Button[@text="Joao's "cartao""]`, que é XPath inválido e,
dentro de `'...'` no Page Object, fecha a string Python antes da hora: o
arquivo salvo não compila. Mesmo problema em `ACCESSIBILITY_ID, "<texto>"`.

**D3. No iOS, "accessibility id" usa o `label`.** O parser põe `name` em
`resource_id` e `label` em `content_desc`; o candidato `accessibility_id` usa
`content_desc`. No XCUITest, accessibility id é alias de `name`. Quando o app
define `accessibilityIdentifier` diferente do rótulo, o seletor não acha nada.

**D4. Sem estratégias nativas.** Não há `-android uiautomator`,
`-ios predicate string` nem `-ios class chain`, que o próprio driver XCUITest
classifica como mais rápidas e estáveis que XPath (até 10x).

**D5. O executor ignora o localizador.** `generate_hidden_runner_script`
repete `input tap x y` (Android) e `/wda/tap` (iOS) na coordenada gravada, com
`time.sleep(1.0)` entre passos. Não espera elemento, não confere que o alvo
certo está lá, não gera asserção. Qualquer mudança de layout, teclado aberto ou
carregamento lento faz o passo tocar no lugar errado e **passar**, porque
sucesso é "o adb devolveu 0".

**D6. Padrão de fábrica é `position`.** `DEFAULT_STRATEGY` cai em `"position"`
(`config.py`), a pior estratégia pela própria régua do código. E
`PAGE_OBJECTS_KEY` padrão é `onboarding_credito_objs`, nome de um projeto
específico vazando para o produto.

**D7. Page Object gerado depende de uma base que não existe.** O código emite
`self.click_at_position(...)`, `self.send_keys(...)` e
`self.locators['<chave>']`. Nenhum desses está definido no repositório. Quem
baixa o Mo baile e salva o Page Object não consegue rodá-lo sem escrever a
base antes. É o maior freio de tempo até o primeiro valor.

**D8. Sem vínculo temporal entre passo, rede e analytics.** `AutomationStep`
não tem `timestamp`. Os eventos de rede e analytics têm. A correlação, que é o
diferencial possível, não existe no dado.

**D9. Fachadas no modal de execução.** `FlowRunnerModal` mostra
`tempo 0.0 s` literal e conta "aprovados" como passos cujo tipo não é `fail`.
`flow.stop` só marca a intenção; o subprocesso continua até o fim
(`rpc/server.py`, `flow_stop`). A interface Swift não mostra as
`alternatives` que o motor devolve (nenhuma ocorrência de `alternatives` em
`apps/MoBaile/Sources`).

**D10. Atributos descartados.** O parser Android lê só `class`, `resource-id`,
`text`, `content-desc`, `clickable`, `bounds`, `package`. Ficam de fora
`enabled`, `checked`, `focusable`, `scrollable`, `password`, `selected`,
`hint`, que alimentariam seletor mais preciso, asserção de estado e checagem de
acessibilidade.

**D11. O próprio app não é testável por id.** Zero `accessibilityIdentifier`
em `apps/MoBaile/Sources`. Para quem vende ferramenta de automação, é um
detalhe que o público nota.

---

## 12. Lições para o Mo baile

Ordem: valor para o usuário dividido por esforço, com dependências
respeitadas. Esforço: P (até 3 dias), M (1 a 2 semanas), G (mais de 2
semanas).

### L1. Corrigir o ranqueamento: o seletor emitido é o seletor validado

- **Problema.** D1, D2, D3. O Mo baile promete "localizador único" e entrega
  ambíguo, às vezes código que nem compila.
- **Evidência.** Playwright trata unicidade como regra de execução e refina o
  seletor até ser único. Appium documenta `accessibility id` = `name` no iOS.
- **O que fazer.** Cada candidato carrega o **valor final** e a contagem é
  feita **avaliando esse valor** contra a árvore atual (para XPath, avaliar a
  expressão sobre o XML; o `ElementTree` suporta um subconjunto, `lxml` resolve
  o resto). Se nenhum for único, refinar: id + texto, texto + classe, âncora
  relacional, e só então índice. O RPC passa a usar o candidato escolhido como
  está, sem retraduzir para `LocatorStrategy`. Escapar valores: XPath com
  `concat()` quando houver os dois tipos de aspas; linha Python com `repr()`.
  No iOS, `accessibility id` usa `name`.
- **Esforço.** P a M.
- **Risco.** Baixo. Muda o código gerado; avisar no changelog.
- **Pronto quando.** (1) O cenário de três botões com mesmo id gera seletor
  que casa com exatamente um nó, verificado por avaliação da expressão no XML;
  (2) teste de propriedade com textos contendo `'`, `"`, `\` e acentos gera
  arquivo que passa em `ast.parse` e XPath que avalia sem erro; (3) teste iOS
  com `name != label` gera `ACCESSIBILITY_ID` com o `name`.

### L2. Padrão sensato de fábrica

- **Problema.** D6.
- **Evidência.** Todos os concorrentes começam pelo seletor mais robusto.
- **O que fazer.** `DEFAULT_STRATEGY=auto`; chave padrão genérica
  (`page_objects` ou derivada do package do app).
- **Esforço.** P.
- **Risco.** Quem depende de `position` precisa setar a variável.
- **Pronto quando.** Instalação limpa grava passo com estratégia `auto` e
  arquivo sem nome de projeto de terceiros; `test_config` cobre o padrão.

### L3. Executar pelo localizador, com espera e multi-localizador reportado

- **Problema.** D5. O localizador é decorativo; a execução é por coordenada e
  `sleep`.
- **Evidência.** Espera assíncrona é 45% da instabilidade de UI (Romano 2021).
  Maestro reexecuta contra a árvore mais nova até o timeout. Selenium IDE e
  Katalon guardam vários seletores e caem para o próximo; Katalon e mabl só
  aceitam a cura com aprovação ou execução verde.
- **O que fazer.** Cada passo guarda a lista ordenada de candidatos de L1. Na
  execução: dump da árvore, resolver o primeiro candidato, se não achar,
  repetir até timeout (padrão 10 s, configurável); se o primário falhar e um
  secundário achar, tocar no centro dele e marcar o passo como **curado**, com
  o seletor antigo e o novo. Coordenada só para passo gravado sem nó. Nada de
  gravar a cura no Page Object sem a pessoa aprovar na interface. Não precisa
  de Appium: o motor já faz dump e toque.
- **Esforço.** M (motor) + P (interface para aprovar cura).
- **Risco.** Médio: dump do `uiautomator` custa 300 a 800 ms e pode deixar o
  fluxo lento; mitigar com cache por quadro inalterado (o streaming já detecta
  mudança). Falso positivo na cura; mitigar exigindo que o secundário também
  seja único.
- **Pronto quando.** Com o harness `qa/` e o `adb` falso: (1) botão deslocado
  200 px entre gravação e execução, fluxo passa; (2) botão removido, fluxo
  falha com mensagem que nomeia o seletor; (3) id trocado mas texto igual,
  passo passa marcado como curado e a interface pede aprovação; (4) tela que
  demora 3 s para carregar passa sem `sleep` fixo.

### L4. Page Object que roda de primeira: exportar projeto mínimo

- **Problema.** D7. O código salvo depende de uma base inexistente; tempo até
  o primeiro valor infinito para quem não é do time de origem.
- **Evidência.** Playwright e Maestro entregam teste executável no primeiro
  minuto. Xcode e Espresso Recorder mostram que gravação sem abstração vira
  código descartável.
- **O que fazer.** `codegen.export` gera uma pasta com `base_page.py` (Appium
  Python Client, `WebDriverWait` + `expected_conditions`, sem `sleep`),
  `pages/<tela>.py`, `locators/<tela>.py`, `tests/test_fluxo.py` com o fluxo
  gravado, `conftest.py` com capabilities do aparelho atual, `requirements.txt`
  e README de três comandos. Opcional e barato: exportar o mesmo fluxo como
  YAML do Maestro, que hoje é o formato com maior tração no segmento.
- **Esforço.** M.
- **Risco.** Baixo. Manter o formato atual como opção "base própria" para quem
  já tem framework.
- **Pronto quando.** Em máquina limpa com emulador e Appium, `pip install -r
  requirements.txt && pytest` roda o fluxo exportado e passa; CI valida o
  projeto exportado com `ruff` e `ast.parse`; YAML exportado passa em
  `maestro test` num emulador (verificação manual registrada em `docs/QA.md`).

### L5. Linha do tempo correlacionada: o "Trace Viewer" do mobile

- **Problema.** D8. O Mo baile captura passo, HTTP e Firebase, mas cada um vive
  numa aba. Ninguém no mercado junta os três.
- **Evidência.** Trace Viewer do Playwright: por ação, snapshot antes/depois,
  rede e código. Allure e ReportPortal mostram que o artefato portátil é o que
  espalha a ferramenta.
- **O que fazer.** `AutomationStep` ganha `timestamp`, hash da árvore e
  referência à captura antes e depois. Na gravação e na execução, eventos de
  rede e analytics entre o passo N e o N+1 ficam associados ao passo N. Exportar
  `.mobaile-trace` (zip com JSON, PNGs e HAR redigido) e um HTML estático que
  abre offline. Exportar também em formato `allure-results` para cair no
  relatório que os times já usam.
- **Esforço.** G (M para o dado e exportação, M para a visualização no front).
- **Risco.** Médio: volume de dados e redação (o HAR já é redigido; manter a
  mesma regra no trace, incluindo corpo e cabeçalho de resposta, como o
  defeito 2 do `RELATORIO_QA.md` ensinou).
- **Pronto quando.** Um fluxo de 5 passos gera um arquivo que, aberto em outra
  máquina sem o Mo baile, mostra para cada passo: captura antes/depois, seletor
  usado, requisições e eventos de analytics disparados, sem nenhum
  `Authorization`, `Cookie` ou `Set-Cookie` em claro; `allure generate` sobre a
  exportação produz relatório com os 5 passos.

### L6. Asserções a partir do que foi observado (UI, analytics, contrato)

- **Problema.** O fluxo gravado não verifica nada; a asserção de contrato da
  interface Tk é inventada e chama método inexistente (`ESTADO_ATUAL.md`).
- **Evidência.** Playwright codegen grava "assert visibility/text/value".
  Nenhuma ferramenta gera asserção de **evento de analytics** a partir do que
  foi observado.
- **O que fazer.** Na gravação, três botões: "afirmar visível/texto" sobre o
  elemento, "afirmar evento" sobre um evento de Firebase capturado (nome +
  parâmetros escolhidos, com os voláteis marcados como ignorados), "afirmar
  resposta" sobre uma requisição (status + esquema JSON inferido do corpo). O
  executor de L3 verifica as três.
- **Esforço.** M.
- **Risco.** Evento de analytics chega com atraso de lote no Firebase; tolerar
  janela configurável.
- **Pronto quando.** Com logcat e proxy falsos do harness: fluxo com
  `assert_event("purchase", {"value": 10})` passa quando o evento chega em até
  N s e falha com diff legível quando o parâmetro difere; asserção de resposta
  falha quando um campo obrigatório some.

### L7. Auditoria de acessibilidade pela árvore e pela captura

- **Problema.** Nenhuma checagem de acessibilidade, num momento em que EAA, LBI
  e NBR 17060 tornam isso cobrança de negócio.
- **Evidência.** Accessibility Scanner (ATF), `performAccessibilityAudit`, axe
  e Evinced checam o mesmo núcleo: rótulo, área de toque, contraste, texto
  cortado.
- **O que fazer.** Serviço `a11y` no motor: clicável sem rótulo, rótulo
  duplicado, área abaixo de 48 dp (Android, com `wm density`) ou 44 pt (iOS),
  contraste de texto por amostragem da captura dentro dos bounds (4,5:1 e 3:1).
  Cada achado aponta o SC do WCAG 2.2 e o item da NBR 17060 correspondente.
  Ampliar o parser com os atributos de D10. Relatório exportável e integrado ao
  trace de L5. Texto da interface deixa claro que é triagem automática e não
  substitui teste com TalkBack e VoiceOver, como a própria Google avisa.
- **Esforço.** M.
- **Risco.** Falso positivo em contraste (gradiente, imagem de fundo); marcar
  como "revisar" em vez de "falha" quando a variância de cor for alta.
- **Pronto quando.** Fixtures de hierarquia com casos conhecidos (botão
  36x36 dp, ImageButton sem descrição, texto cinza claro sobre branco) geram
  exatamente os achados esperados e nenhum a mais; comparação manual com o
  Accessibility Scanner numa tela real registrada em `docs/QA.md`.

### L8. Servidor MCP sobre o motor

- **Problema.** Agentes de código (Claude Code, Cursor, Copilot) já automatizam
  mobile por MCP; o Mo baile fica fora dessa conversa.
- **Evidência.** mobile-mcp com cerca de 8,4 mil estrelas; Appium, Maestro e
  Playwright publicaram MCP; Proxyman inclui MCP em todos os planos. Todos
  preferem árvore de acessibilidade a captura.
- **O que fazer.** Adaptador `mobaile-mcp` que expõe como ferramentas o que o
  RPC já faz: `hierarchy_snapshot` (compacta, com `ref`), `element_at`,
  `rank_locators`, `tap_ref`, `record_step`, `run_flow`, `network_events`,
  `analytics_events`, `a11y_audit`. O motor já fala JSON-RPC 2.0 sobre stdio,
  que é o transporte do MCP; o trabalho é o mapeamento e a descrição das
  ferramentas, não o protocolo.
- **Esforço.** M.
- **Risco.** Agente tocando em aparelho real. Manter stdio sem TCP (coerente
  com `ARQUITETURA.md`), confirmação para ações destrutivas (instalar,
  desinstalar, `proxy.start`), redação idêntica à do front.
- **Pronto quando.** Um cliente MCP de referência lista as ferramentas, pede a
  árvore de um emulador, obtém seletor único para um botão e executa o toque;
  teste de contrato garante que toda ferramenta MCP tem método RPC equivalente
  e vice-versa para o subconjunto exposto.

### L9. Medir instabilidade antes de entregar o teste

- **Problema.** Não há como saber se um fluxo gravado é estável.
- **Evidência.** Google trata flaky com reexecução e quarentena; Currents e
  Allure marcam instável pelo histórico.
- **O que fazer.** Botão "Rodar 5x" no modal de execução: executa o fluxo N
  vezes, marca passos que variaram (falha, cura, tempo acima do p95) e dá uma
  nota de estabilidade por seletor. Reaproveita L3 e L5.
- **Esforço.** P depois de L3.
- **Risco.** Tempo de execução; é opt-in.
- **Pronto quando.** Com o harness, um passo com atraso aleatório aparece
  marcado como instável em 5 execuções e um passo determinístico não.

### L10. Guardas internos de qualidade e arquitetura no CI

- **Problema.** A regra de camadas e as invariantes de segurança vivem em
  comentário e em teste pontual.
- **Evidência.** import-linter (contrato `layers`), Semgrep/Opengrep com regras
  próprias, ArchUnit como modelo.
- **O que fazer.** Contrato `layers` do import-linter:
  `mobaile.rpc > mobaile.services | mobaile.adapters > mobaile.security | mobaile.ports > mobaile.domain`
  (ajustar ao desenho real) mais um `forbidden` de `mobaile.services` para
  `mobaile.adapters`. Regras Opengrep para: `subprocess` sem `stdin` quando o
  pai é o servidor RPC, `shell=True`, caminho `/sdcard/`, interpolação de
  entrada em script gerado. Opcional: CodeScene (grátis se o repositório for
  aberto) para hotspots de `rpc/server.py`.
- **Esforço.** P.
- **Risco.** Nenhum; o contrato de camadas já passa hoje.
- **Pronto quando.** Job no `ci.yml` que falha num PR de teste que importa um
  adapter dentro de um service, e em outro que reintroduz `shell=True`.

### L11. Tirar as fachadas do caminho de execução

- **Problema.** D9.
- **Evidência.** `ESTADO_ATUAL.md` já trata fachada como defeito; confiança é
  o ativo de uma ferramenta de QA.
- **O que fazer.** Tempo real no rodapé, contagem de aprovados/falhas vinda de
  `flow.finished` com resultado por passo, `flow.stop` que encerra o
  subprocesso (SIGTERM, depois SIGKILL) e mostrar `alternatives` no painel do
  passo.
- **Esforço.** P.
- **Risco.** Baixo.
- **Pronto quando.** Teste de contrato de `flow.finished` com resultado por
  passo; teste de motor em que `flow.stop` encerra o processo em menos de 2 s;
  suíte Swift decodifica `alternatives`.

### L12. Dogfooding: o próprio Mo baile testável e acessível

- **Problema.** D11.
- **Evidência.** `performAccessibilityAudit` no XCUITest custa uma linha.
- **O que fazer.** `accessibilityIdentifier` nos controles principais; um UI
  test com `performAccessibilityAudit()` no CI macOS.
- **Esforço.** P.
- **Risco.** Baixo.
- **Pronto quando.** Job `front` roda o UI test com auditoria e passa.

### L13. Distribuição com tempo até o primeiro valor medido

- **Problema.** Hoje o caminho é `make setup`, Python 3.10+, `swift build`, WDA
  rodando. Não há medida de quanto tempo alguém leva até o primeiro Page
  Object.
- **Evidência.** Maestro e Proxyman se instalam em um passo; Appium Inspector
  virou plugin para reduzir atrito.
- **O que fazer.** DMG assinado e notarizado com o motor embutido (Python
  empacotado), cask do Homebrew, tela vazia que sobe um emulador Android com um
  clique (o motor já tem `emulators.boot`), tutorial de cinco minutos com app
  de exemplo. Medir: do download ao primeiro passo gravado, em máquina limpa.
- **Esforço.** M.
- **Risco.** Notarização com Python embutido dá trabalho; reservar tempo.
- **Pronto quando.** Três pessoas de fora do projeto, em máquina limpa com
  Android SDK, chegam ao primeiro Page Object em menos de 10 minutos, medido e
  registrado.

---

## 13. Proposta de posicionamento

### Para quem

Pessoa de QA ou desenvolvimento em time mobile que **já escreve Appium** (ou
quer começar) e trabalha num Mac, em empresa que precisa **provar** três coisas
a cada release: que o fluxo funciona, que o tagueamento de analytics está
certo e que o app atende acessibilidade. No Brasil isso é banco, fintech,
seguradora, varejo e telecom, onde time de dados cobra evento de Firebase
correto e jurídico cobra LBI/NBR 17060. Fora do Brasil, quem vende para a UE
sob a EAA.

Não é para: time que quer nuvem de dispositivos (AWS, BrowserStack, Maestro
Cloud), quem quer autoria 100% em linguagem natural sem código (testRigor,
KaneAI), nem regressão visual pixel a pixel (Applitools, Percy).

### Diferencial defensável

1. **Evidência correlacionada, local e sem SDK.** Passo de UI, requisição HTTP
   e evento de analytics na mesma linha do tempo, exportável e redigido. Nenhum
   concorrente estudado faz isso no mobile. É defensável porque exige três
   capturas difíceis juntas (espelho e árvore, proxy com `adb reverse`,
   logcat/Unified Logging do Firebase) que o Mo baile já tem e que um
   concorrente web ou de nuvem não tem incentivo para construir.
2. **Seletor validado contra a tela, com explicação.** O que o Playwright fez
   para o web (strict + prioridade por acessibilidade), aplicado a Appium, com
   a árvore inteira em mãos para provar unicidade antes de gravar.
3. **Velocidade de inspeção.** A promessa original do README (espelho ao vivo
   contra dez segundos de captura estática) continua sendo a porta de entrada.

O que **não** é defensável e não deve ser vendido como diferencial: auto-cura
por IA, geração por linguagem natural, execução em nuvem.

### Como se distribui

- **Núcleo aberto.** Motor e app gratuitos para uso individual, com código
  aberto (MIT ou Apache-2.0). Hoje `pyproject.toml` declara `Proprietary`; a
  decisão merece um ADR. O argumento: o público confia em ferramenta que roda
  no próprio aparelho e mexe em proxy e certificados quando pode ler o código,
  e a aquisição desse segmento é de baixo para cima.
- **Pro por assento.** Exportação de trace e de `allure-results`, relatório de
  acessibilidade com mapeamento WCAG/NBR, execução em CI (headless, com
  emulador) e asserções de analytics. Referência de preço: Proxyman (perpétua
  individual US$ 89 a 99; time a US$ 12 por assento/mês). Sem cobrança por
  minuto de dispositivo, porque o Mo baile não hospeda dispositivo.
- **Canais.** Homebrew, GitHub, registro de servidores MCP, plugin ou guia para
  Appium Inspector (o público já está lá), comunidade de QA brasileira, e
  conteúdo em português sobre tagueamento de Firebase e NBR 17060, tema com
  pouca concorrência de conteúdo (não verificado quantitativamente).
- **Artefato como vetor.** Cada trace exportado e cada relatório de
  acessibilidade compartilhado é propaganda para quem o recebe. É o mesmo
  mecanismo que espalhou o Trace Viewer e o Allure.

---

## 14. Fontes

Acesso em 29/09/2026. Marcadas como (indício) quando não primárias.

Geração e localizadores
- Playwright codegen: https://playwright.dev/docs/codegen
- Playwright locators: https://playwright.dev/docs/locators
- Playwright test agents: https://playwright.dev/docs/test-agents
- Playwright trace viewer: https://playwright.dev/docs/trace-viewer
- Playwright MCP snapshots: https://playwright.dev/mcp/snapshots
- Playwright 1.56 e agentes (indício): https://dev.to/testrig/playwright-v156-introducing-ai-powered-testing-agents-3ncj
- XCUITest locator strategies: https://appium.github.io/appium-xcuitest-driver/latest/reference/locator-strategies/
- UiAutomator2 driver: https://github.com/appium/appium-uiautomator2-driver
- Appium Inspector, Source: https://appium.github.io/appium-inspector/latest/session-inspector/source/
- Appium Inspector 2025.8.2: https://github.com/appium/appium-inspector/releases/tag/v2025.8.2
- Appium 3, resumo (indício): https://codoid.com/mobile-application-testing/appium-3-features-migration-guide/
- Maestro, como funciona: https://docs.maestro.dev/get-started/how-maestro-works.md
- Maestro, seletores relacionais: https://docs.maestro.dev/reference/selectors/relational-selectors.md
- Maestro Studio: https://docs.maestro.dev/maestro-studio/maestro-studio-overview.md
- Maestro MCP: https://docs.maestro.dev/get-started/maestro-mcp.md
- Maestro pricing: https://maestro.dev/pricing
- Selenium IDE: https://github.com/seleniumhq/selenium-ide
- Selenium IDE fallback (indício): https://www.qafox.com/new-selenium-ide-fallback-locators-strategy/
- Selenium IDE issue 1090: https://github.com/SeleniumHQ/selenium-ide/issues/1090
- Katalon self-healing: https://docs.katalon.com/katalon-studio/maintain-tests/self-healing-tests-in-katalon-studio
- Katalon pricing: https://katalon.com/pricing
- Espresso Test Recorder: https://developer.android.com/studio/test/other-testing-tools/espresso-test-recorder
- Fórum Apple, gravação de UI test: https://developer.apple.com/forums/thread/123069

Auto-cura e flakiness
- Google, Flaky Tests: https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html
- Romano et al., ICSE 2021: https://arxiv.org/abs/2103.02669
- Similo: https://arxiv.org/pdf/2208.00677
- VON Similo: https://arxiv.org/html/2301.03863
- Revisão de ferramentas de teste com IA: https://arxiv.org/pdf/2409.00411
- Testim locators (indício, fornecedor): https://www.tricentis.com/blog/testim-locator-technologies
- Testim Mobile docs: https://docs.tricentis.com/all/manuals/testim_mobile.htm
- Testim Mobile pricing: https://www.tricentis.com/products/testim-mobile/pricing
- mabl auto-heal: https://help.mabl.com/hc/en-us/articles/19078583792404-How-auto-heal-works
- mabl pricing: https://www.mabl.com/pricing
- Healenium: https://healenium.io/docs/how_healenium_works
- healenium-web: https://github.com/healenium/healenium-web
- healenium-appium: https://github.com/healenium/healenium-appium
- Functionize (marketing): https://www.functionize.com/self-healing
- Applitools match levels: https://applitools.com/docs/eyes/concepts/best-practices/match-levels
- Applitools Ultrafast Grid: https://applitools.com/docs/eyes/concepts/test-execution/ultrafast-grid
- Applitools pricing: https://applitools.com/pricing/
- Percy plans: https://www.browserstack.com/docs/percy/overview/plans-and-billing
- App Percy plans: https://www.browserstack.com/docs/app-percy/overview/plans-and-billing
- testRigor (indício): https://www.getapp.com/it-management-software/a/testrigor/

Relatórios
- Allure docs: https://allurereport.org/docs/
- Allure 3: https://github.com/allure-framework/allure3
- Allure TestOps server pricing: https://qameta.io/server-pricing
- ReportPortal docs: https://reportportal.io/docs/
- ReportPortal auto-analysis: https://reportportal.io/docs/analysis/AutoAnalysisOfLaunches/
- Currents pricing: https://currents.dev/pricing

Acessibilidade
- WCAG 2.2 SC 2.5.8: https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
- WCAG2Mobile: https://www.w3.org/TR/wcag2mobile-22/
- Android accessibility: https://developer.android.com/guide/topics/ui/accessibility/apps
- Apple HIG, acessibilidade: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Accessibility Scanner: https://support.google.com/accessibility/android/answer/6376570
- ATF: https://github.com/google/Accessibility-Test-Framework-for-Android
- WWDC23 10035: https://developer.apple.com/videos/play/wwdc2023/10035/
- performAccessibilityAudit, resumo (indício): https://www.polpiella.dev/xcode-15-automated-accessibility-audits/
- axe DevTools Mobile, Appium: https://docs.deque.com/devtools-mobile/2025.7.2/en/appium/
- Deque, plugin Appium: https://www.deque.com/blog/deque-adds-new-appium-plugin-to-axe-devtools-mobile/
- Evinced SDKs: https://www.evinced.com/products/auto-test-sdks
- Evinced MFA: https://www.evinced.com/products/flow-analyzer-for-mobile
- EAA (indício): https://www.levelaccess.com/compliance-overview/european-accessibility-act-eaa/
- EAA: https://en.wikipedia.org/wiki/European_Accessibility_Act
- NBR 17060, CTA IFRS: https://cta.ifrs.edu.br/abnt-nbr-17060-2022-acessibilidade-em-aplicativos-de-dispositivos-moveis-requisitos/
- NBR 17060, NIC.br: https://nic.br/noticia/releases/norma-da-abnt-sobre-acessibilidade-para-dispositivos-moveis-torna-a-navegacao-mais-inclusiva/

Qualidade de código e arquitetura
- Sonar planos: https://www.sonarsource.com/plans-and-pricing/
- Sonar licença: https://www.sonarsource.com/license/
- CodeScene pricing: https://codescene.com/pricing
- Semgrep licensing: https://semgrep.dev/docs/licensing
- Opengrep: https://www.opengrep.dev/
- Snyk pricing (indício): https://dev.to/rahulxsingh/snyk-pricing-in-2026-free-plan-team-business-and-enterprise-costs-breakdown-5e88
- DeepSource pricing: https://deepsource.com/pricing
- Structurizr: https://structurizr.com/
- C4 model: https://c4model.com/
- ArchUnit: https://www.archunit.org/
- import-linter layers: https://import-linter.readthedocs.io/en/latest/contract_types/layers/

Tendências e IA
- Appium MCP: https://github.com/appium/appium-mcp
- mobile-mcp: https://github.com/mobile-next/mobile-mcp
- Firebase App Testing agent: https://firebase.blog/posts/2025/04/app-testing-agent/
- Kane CLI mobile: https://www.globenewswire.com/news-release/2026/09/10/3359678/0/en/testmu-ai-launches-mobile-automation-in-kane-cli-bringing-natural-language-test-automation-to-ios-simulators-and-android-emulators.html
- GPT Driver: https://www.mobileboost.io/
- Arbigent: https://github.com/takahirom/arbigent
- Stack Overflow 2025, IA: https://survey.stackoverflow.co/2025/ai
- Stack Overflow 2025, press release: https://stackoverflow.co/company/press/archive/stack-overflow-2025-developer-survey/
- World Quality Report 2025: https://www.capgemini.com/news/press-releases/world-quality-report-2025-ai-adoption-surges-in-quality-engineering-but-enterprise-level-scaling-remains-elusive/

Mercado
- AWS Device Farm pricing: https://aws.amazon.com/device-farm/pricing/
- Firebase Test Lab pricing: https://firebase.google.com/docs/test-lab/usage-quotas-pricing
- BrowserStack pricing: https://www.browserstack.com/pricing
- Proxyman pricing: https://proxyman.com/pricing
- React Native, desacoplamento do Flipper: https://github.com/react-native-community/discussions-and-proposals/blob/main/proposals/0641-decoupling-flipper-from-react-native-core.md
- React Native 0.73: https://reactnative.dev/blog/2023/12/06/0.73-debugging-improvements-stable-symlinks
- Adoção de produto e TTV (opinião): https://mixpanel.com/blog/product-adoption/

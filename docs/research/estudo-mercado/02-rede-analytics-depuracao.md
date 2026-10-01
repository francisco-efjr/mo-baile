# Estudo de mercado 02: interceptação de rede, depuração e QA de analytics

Frente 2 de 4. Consultado em 29/09/2026. Autor: consultor-pesquisador do Mo baile.

Este estudo **não repete** o que já está em
[`../estudo-http-toolkit.md`](../estudo-http-toolkit.md) (arquitetura modular do
HTTP Toolkit, mockttp, injeção de CA via `tmpfs` + `nsenter`, esboço de addon
mitmproxy) nem em [`../interceptador-rede.md`](../interceptador-rede.md) (mapa do
módulo antigo em `recorder/`). Aqui entra o que falta: o resto do mercado, o
estado de 2026, o que cada ferramenta faz com HTTP/2, HTTP/3, WebSocket e gRPC,
as ferramentas que rodam dentro do app, o universo de QA de tagueamento e um
confronto linha a linha com o código atual do motor e do front.

---

## 1. Resumo executivo

1. **O mercado de proxy está maduro e caro de alcançar em amplitude.** Proxyman,
   Charles, HTTP Toolkit, Fiddler, Burp e mitmproxy fazem breakpoint, map local,
   rewrite, throttling, HAR e diff há anos. Competir nesse eixo é perder. O Mo
   baile não precisa ser um proxy melhor; precisa ser o único lugar em que **o
   toque, a requisição e o evento de analytics aparecem juntos e são
   verificados contra um plano de medição**. Nenhuma das ferramentas estudadas
   faz isso para app nativo (seções 8 e 9).
2. **O QA de tagueamento em app nativo continua artesanal.** Firebase DebugView e
   GA4 DebugView mostram eventos em quase tempo real, mas não sabem qual toque
   gerou qual evento nem o que o plano de medição exigia. Avo, Segment Protocols,
   Amplitude Data e Trackingplan validam contra plano, mas em produção ou em
   nuvem, por volume, e só para o próprio ecossistema. ObservePoint declara
   abertamente que depende de HAR exportado de Charles ou Proxyman para app.
3. **O Mo baile hoje não decifra HTTPS.** O proxy próprio abre túnel `CONNECT` e
   conta bytes. Como quase todo app moderno é HTTPS, a aba Rede mostra, na
   prática, uma lista de hosts. Qualquer correlação toque → requisição depende de
   resolver isso primeiro.
4. **A captura de Firebase por logcat é o ativo mais valioso da frente** e tem
   defeitos corrigíveis em horas: o parser quebra evento de e-commerce com
   `items` aninhado, perde tipo de parâmetro, deixa o modo debug do Firebase
   ligado no aparelho ao parar e acumula fila sem teto. Verificado com teste
   local (seção 10.2).
5. **O proxy HTTP em texto claro tem dois defeitos de protocolo** verificados:
   resposta `chunked` chega corrompida ao app, e corpo `gzip` aparece como lixo
   binário na inspeção.
6. **A regra "lógica no motor" está sendo violada nesta frente**: HAR e TSV são
   gerados em Swift, com resultado diferente do TSV do motor, e o
   `CorrelationCard` gera asserção com endpoint inventado quando não há tráfego.

A recomendação central (seção 11) é uma sequência: higiene do que já existe (P),
relógio único e linha do tempo (M), plano de medição com veredito por passo (M),
e só então HTTPS de verdade com um motor MITM maduro (G).

---

## 2. O que mudou desde os estudos anteriores

| Fato | Data | Impacto | Fonte |
|---|---|---|---|
| HTTP Toolkit desktop 1.27.2 | 14/09/2026 | Projeto ativo; nada invalida o estudo anterior | [releases](https://github.com/httptoolkit/httptoolkit-desktop/releases) |
| mitmproxy 12.2.3 exige **Python ≥ 3.12** (desde 11.1.0, jan/2025) | 12/05/2026 | O esboço de `DumpMaster` do estudo anterior não roda no motor, que declara `requires-python >=3.10` em `engine/pyproject.toml` | [PyPI](https://pypi.org/project/mitmproxy/), [CHANGELOG](https://github.com/mitmproxy/mitmproxy/blob/main/CHANGELOG.md) |
| Charles 5.0 lançado; 5.2.1 roda em Java 25 | 12/03/2025 e 04/08/2026 | HTTP/3 só aparece como reconhecimento de string de versão em importação, não como interceptação | [version history](https://www.charlesproxy.com/documentation/version-history/) |
| Proxyman 26.0.1, com servidor **MCP** (≥ 6.7/6.8) | 27/09/2026 | Proxy exposto a agentes de IA: listar fluxos, criar breakpoint e map local | [changelog](https://proxyman.com/changelog), [MCP](https://docs.proxyman.com/mcp.md) |
| Flipper arquivado | 26/09/2025 | A referência de depuração embarcada da Meta saiu de cena | [repo](https://github.com/facebook/flipper) |
| Stetho arquivado | 31/03/2026 | Idem | [repo](https://github.com/facebookarchive/stetho) |
| BrowserStack comprou o Requestly | 06/05/2025 | Roteiro anunciado inclui interceptação em dispositivo móvel | [press](https://www.browserstack.com/press/browserstack-acquires-requestly-a-ycombinator-startup-for-http-interception-mocking-debugging-network-requests) |
| Burp Pro subiu para US$ 499/usuário/ano | 06/01/2026 | Só indício: fonte secundária | [codeant.ai](https://codeant.ai/blogs/burp-suite-pricing) (não oficial) |
| Android 11 bloqueia instalar CA por intent de app | desde 2020 | Instalar CA de usuário exige o usuário ir em Configurações; ferramenta não automatiza | [HTTP Toolkit blog](https://httptoolkit.com/blog/android-11-trust-ca-certificates/) |

Correções ao estudo anterior: os caminhos citados lá (`recorder/*.py`) são da
estrutura antiga. O proxy vive hoje em `engine/src/mobaile/adapters/proxy.py`, o
analytics em `engine/src/mobaile/adapters/analytics_logcat.py` e a configuração
do aparelho em `engine/src/mobaile/adapters/adb.py`.

---

## 3. Fichas: proxies e depuradores HTTP

### 3.1 Proxyman

**O que é.** Depurador HTTP(S) com foco em Apple, hoje em macOS, Windows, Linux,
iOS e Android.

**Estrutura e arquitetura.** App nativo macOS construído sobre Apple SwiftNIO
([docs](https://docs.proxyman.com/)). Modos de captura: proxy HTTP clássico,
proxy reverso, SOCKS5, app iOS standalone com VPN e o framework **Atlantis**, que
é embarcado no app iOS e manda o tráfego ao Mac sem configurar proxy
([Atlantis](https://docs.proxyman.com/atlantis/atlantis-for-ios.md)). Para
emulador Android há script automático que troca o proxy e, desde 5.15.0, instala
a CA no **store de sistema**
([script](https://docs.proxyman.com/debug-devices/android-device/automatic-script-for-android-emulator.md));
para emulador com Google Play, roteiro com Magisk.

**Funcionalidades-chave.** Breakpoint com templates, Map Local (arquivo e
diretório), Map Remote, scripting em JavaScript com `require` de pacotes npm,
diff lado a lado, filtros compostos com jq, colunas customizadas lidas do corpo
JSON, Network Conditions (throttling), decodificação Protobuf, GraphQL por nome
de query, WebSocket, exportação HAR, CSV, arquivo Charles, coleção Postman,
OpenAPI 3.0 e "Copy as cURL", CLI e **MCP** com mais de 30 ferramentas
([índice](https://docs.proxyman.com/llms.txt)).

**Desempenho.** A empresa atribui o desempenho ao SwiftNIO; não há benchmark
público. Não verificado.

**Protocolos.** HTTP/1.1, HTTP/2 e WebSocket documentados. HTTP/3: pedido em
aberto desde fev/2023, sem entrada no changelog
([issue 1555](https://github.com/ProxymanApp/Proxyman/issues/1555)).

**Licença e preço.** Proprietário. Trial gratuito com **1 regra**; Standard
US$ 89 (1 dispositivo), Personal US$ 99 (2 dispositivos + apps móveis), Team
US$ 12/assento/mês com mínimo de 5 ([pricing](https://proxyman.com/pricing)).

**Pontos fortes.** Melhor experiência em macOS/iOS; Atlantis resolve o caso
"sem configurar proxy"; MCP abre automação por agente.
**Pontos fracos.** Recursos avançados atrás de licença; HTTP/3 ausente; no
Android real sem root continua dependendo de o app confiar em CA de usuário.

### 3.2 Charles Proxy

**O que é.** O proxy de depuração mais antigo em uso por QA mobile.

**Estrutura.** Aplicação Java com runtime embutido; a 5.2.1 roda em Java 25 com
threads virtuais ([version history](https://www.charlesproxy.com/documentation/version-history/)).

**Funcionalidades-chave.** Breakpoints, Map Local, Map Remote, Rewrite, No
Caching, Block Cookies, Block List, DNS Spoofing, Mirror, Auto Save, Repeat e
Repeat Advanced, Validate, ferramentas de linha de comando
([tools](https://www.charlesproxy.com/documentation/tools/)); throttling
([doc](https://www.charlesproxy.com/documentation/proxying/throttling/)).
Registro de descritores Protobuf, usado pela comunidade de analytics para
decodificar o `app-measurement.com/a` do Firebase (seção 7.11).

**Protocolos.** HTTP/2 com melhorias de robustez na série 5, WebSocket,
Protobuf 3. HTTP/3: não intercepta; só reconhece strings de versão em
importação HAR.

**Licença e preço.** Proprietário; US$ 30 por licença, trial de 30 dias,
desconto por volume, site license US$ 400
([buy](https://www.charlesproxy.com/buy/)).

**Pontos fortes.** Barato, onipresente, formato `.chls` aceito por outras
ferramentas. **Pontos fracos.** Interface datada; configuração de celular é
toda manual; sem HTTP/3.

### 3.3 HTTP Toolkit (atualização)

Arquitetura já coberta no estudo anterior. O que acrescentar:

- **Versão e ritmo.** 1.27.0 (07/08/2026), 1.27.1 (13/08/2026), 1.27.2
  (14/09/2026) ([releases](https://github.com/httptoolkit/httptoolkit-desktop/releases)).
- **Android na prática.** O app Android é uma **VPN local** que redireciona TCP
  nas portas 80, 443, 8000, 8001, 8080, 8888 e 9000 e, no Android 10+, também
  define proxy HTTP padrão. Sem root, instala CA de usuário, que só vale para
  app que opta por confiar nela; com root ou emulador, injeta no store de
  sistema via ADB ([guia Android](https://httptoolkit.com/docs/guides/android/)).
- **Unpinning.** Repositório `frida-interception-and-unpinning`, **AGPL-3.0**,
  com scripts separados: hook TLS nativo para BoringSSL, redirecionamento de
  `connect()` para o proxy, injeção de CA, unpinning com fallback para pinning
  ofuscado, e desabilitação de detecção de root e jailbreak
  ([repo](https://github.com/httptoolkit/frida-interception-and-unpinning)).
- **Protobuf.** Decodificação automática sem schema anunciada em 06/03/2024
  ([Mastodon](https://mastodon.social/@httptoolkit/112049686872777461)).
- **Preço.** Hobbyist gratuito e open source; Pro com mocking, rewrite,
  import/export e validação contra 2600+ APIs e OpenAPI próprio
  ([pricing](https://httptoolkit.com/pricing/)). Valor do Pro não aparece na
  página; agregadores citam a partir de US$ 14/mês (não verificado,
  [Capterra](https://www.capterra.com/p/211624/HTTP-Toolkit/)).

### 3.4 mitmproxy

**O que é.** Proxy interceptador em Python, com três interfaces: `mitmproxy`
(console), `mitmdump` (linha de comando) e `mitmweb` (web). **MIT**. Versão
12.2.3 de 12/05/2026, **Python ≥ 3.12** ([PyPI](https://pypi.org/project/mitmproxy/)).

**Arquitetura.** Núcleo em Python com partes em Rust (`mitmproxy_rs`) para os
modos de rede. Extensão por **addons**: objetos Python com um método por evento
(`request`, `response`, `websocket_message`, `error` etc.), carregados com
`-s script.py` e recarregados a quente em cerca de um segundo
([addons](https://docs.mitmproxy.org/stable/addons/overview/)). Exportação HAR
nativa desde 10.1 (`save.har` e opção `hardump`)
([post](https://www.mitmproxy.org/posts/har-support/)).

**Modos** ([modes](https://docs.mitmproxy.org/stable/concepts/modes/)):

| Modo | Uso | Desde |
|---|---|---|
| regular | proxy HTTP(S) explícito | sempre |
| local | captura transparente de processos da própria máquina, com filtro por nome ou PID; só saída em macOS/Linux | macOS 9.0 (out/2022), Linux 11.1 (jan/2025) |
| wireguard | sobe servidor WireGuard; o celular conecta com o app oficial WireGuard | 9.0 (out/2022) |
| transparent | roteamento no nível de rede | antigo |
| tun | interface virtual, só Linux e com root | 11.0.1 (nov/2024) |
| reverse, upstream, socks5, dns | variações | vários |

**Protocolos** ([protocols](https://docs.mitmproxy.org/stable/concepts/protocols/)):
HTTP/1, HTTP/2, HTTP/3 (experimental desde 10.0, ago/2023; só QUIC v1; testado
"extensivamente só com cURL"; replay de cliente quebrado), WebSocket (sem replay),
DNS, TCP/TLS e UDP/DTLS genéricos. Contentview gRPC/Protobuf reescrita na 12.0
(abr/2025) para suportar protos desconhecidos.

**Desempenho.** Sem benchmark oficial. Não verificado.

**Pontos fortes.** Gratuito, scriptável na mesma linguagem do motor do Mo baile,
o único do grupo com HTTP/3 e WireGuard. **Pontos fracos.** Python ≥ 3.12;
HTTP/3 imaturo; interface pensada para quem já sabe o que procura.

**Nota para o Mo baile.** O modo WireGuard depende de UDP do celular até a
máquina. O `adb reverse` só encaminha TCP (e sockets locais), então WireGuard
obriga a expor uma porta na rede local, o que vai contra a decisão registrada em
`docs/SEGURANCA.md` de manter o proxy só em loopback.

### 3.5 Fiddler Everywhere

**O que é.** Sucessor multiplataforma do Fiddler Classic, da Progress Telerik.

**Funcionalidades.** Captura local e remota, inspeção de protocolo, replay,
filtros, regras, breakpoints, composição de requisição, compartilhamento de
sessão, modo offline no Enterprise.

**Mobile.** Android por proxy manual e CA baixada de `http://<host>:8866`. A
documentação admite que apps rejeitam CA de usuário por padrão e que, mesmo com
root e CA de sistema, "muitas aplicações" ainda recusam
([Android](https://www.telerik.com/fiddler/fiddler-everywhere/documentation/capture-traffic/capture-from-android)).

**Preço.** Lite US$ 7, Pro US$ 13, Enterprise US$ 37 por usuário/mês, anual
([purchase](https://www.telerik.com/purchase/fiddler)). Regras e breakpoints só
a partir do Pro. **Stack.** Não verificado nesta rodada.

**Forte:** conformidade (SOC 2, HIPAA) e gestão corporativa. **Fraco:** nada de
especial para mobile; tudo por assinatura.

### 3.6 Burp Suite (referência de interceptação)

**O que é.** Plataforma de teste de segurança web; o proxy é uma das ferramentas.

**Por que importa.** É o padrão de referência de "interceptar e editar" (Proxy
Intercept, Repeater, Intruder) e o dono do ecossistema de extensões (BApp
Store). HTTP/3 chega por pilha QUIC própria e pela extensão HTTP/3 Adapter, que
converte requisição para HTTP/3 e devolve a resposta em versão compatível
([HTTP/3 Adapter](https://portswigger.net/bappstore/bfd526811899438080ca4bb6b8a03ab5),
[pesquisa](https://portswigger.net/research/http3-in-burp-suite)).

**Preço.** Community gratuita; Professional US$ 499/usuário/ano desde
06/01/2026 segundo fonte secundária (não oficial,
[codeant.ai](https://codeant.ai/blogs/burp-suite-pricing)); DAST (ex-Enterprise)
sob consulta ([DAST](https://portswigger.net/burp/dast/pricing)).

**Para o Mo baile.** Não é concorrente. Serve de modelo para dois detalhes: a
fila de interceptação com "encaminhar / descartar / editar" e o histórico
imutável separado da mensagem editada.

### 3.7 Requestly

**O que é.** Começou como extensão de navegador para regras HTTP (redirect,
modificar header e resposta, atraso, injetar script); hoje o investimento é num
cliente de API proprietário. Extensão e partes comunitárias em **AGPL-3.0**
([repo](https://github.com/requestly/requestly)). App desktop com proxy para
Android e iOS. Comprado pela BrowserStack em 06/05/2025, com promessa de
interceptação e mock em dispositivos e simuladores
([press](https://www.browserstack.com/press/browserstack-acquires-requestly-a-ycombinator-startup-for-http-interception-mocking-debugging-network-requests)).

**Preço.** Team US$ 10 e Team Pro US$ 15 por usuário/mês, mínimo de 5
([pricing](https://requestly.com/pricing/)).

**Para o Mo baile.** O sinal relevante é estratégico: um dono de device farm
comprou uma ferramenta de mock HTTP para levar ao celular. Mock de rede junto de
automação mobile é direção de mercado, não capricho.

### 3.8 Postman (proxy e Interceptor)

Proxy embutido no app, que exige instalar o certificado do Postman no celular
para HTTPS, e Interceptor como extensão de navegador. O que se captura vira
histórico ou coleção ([capture](https://learning.postman.com/docs/sending-requests/capturing-request-data/capture-overview/)).
Útil como destino ("transformar o que vi em coleção"), não como depurador.

---

## 4. Pontos específicos de mobile

### 4.1 Confiança de CA no Android, versão a versão

| Android | O que muda | Consequência para interceptar | Fonte |
|---|---|---|---|
| ≤ 6 (API ≤ 23) | App confia em CA de sistema **e de usuário** | Basta instalar CA de usuário | [security-config](https://developer.android.com/privacy-and-security/security-config) |
| 7–8.1 (API 24–27) | App que mira API 24+ confia **só em sistema** | CA de usuário não serve para app de terceiro | idem |
| 9+ (API 28+) | Texto claro desligado por padrão | HTTP sem TLS some da maioria dos apps | idem |
| 11 | CA não pode mais ser instalada por intent de app; só pelo app Configurações | Nenhuma ferramenta automatiza a CA de usuário | [HTTP Toolkit](https://httptoolkit.com/blog/android-11-trust-ca-certificates/) |
| 14 | CAs de sistema passam a vir do APEX `com.android.conscrypt`, com propagação de montagem privada | Com root: `tmpfs` + `nsenter` no zygote e em cada app | [HTTP Toolkit](https://httptoolkit.com/blog/android-14-install-system-ca-certificate/) |

### 4.2 `network_security_config`: o caminho sem root

Para o **app da própria empresa**, que é o caso típico de quem usa o Mo baile, o
caminho mais barato é o time de desenvolvimento declarar, só em build debug:

```xml
<network-security-config>
  <debug-overrides>
    <trust-anchors>
      <certificates src="user" />
    </trust-anchors>
  </debug-overrides>
</network-security-config>
```

`debug-overrides` só vale com `android:debuggable="true"`, e a documentação
lembra que loja recusa app debuggable, então não vaza para produção
([security-config](https://developer.android.com/privacy-and-security/security-config)).
Combinado com CA de usuário instalada à mão (Android 11+), resolve aparelho
físico sem root, sem Frida e sem mexer em partição.

`pin-set` também mora nesse arquivo. Pinning declarado ali é desligado pelo
mesmo `debug-overrides`; pinning em código (OkHttp `CertificatePinner`, TrustKit)
não.

### 4.3 Frida e objection

- **Frida** tem três modos: *injected* (`frida-server` no aparelho, exige root),
  *embedded* (Frida Gadget dentro do app, sem root) e *preloaded* (gadget
  carregando script do disco) ([modes](https://frida.re/docs/modes/)).
- **objection** é um kit de exploração em cima do Frida, **GPL-3.0**, que se
  apresenta como funcionando "sem jailbreak" e lista bypass de SSL pinning
  ([repo](https://github.com/sensepost/objection)).
- Os scripts do HTTP Toolkit (AGPL-3.0) são a referência mais completa de
  unpinning em 2026 (seção 3.3).

Para o Mo baile: Frida é ferramenta de segurança ofensiva. Embarcar isso num
inspetor de QA traz licença copyleft, superfície de ataque e conversa difícil
com o time de segurança do cliente. Recomendo **não embarcar**; no máximo
documentar e detectar (seção 11, ideia 11).

### 4.4 VPN local versus proxy global

| | Proxy global (`settings put global http_proxy`) | VPN local (app no aparelho) |
|---|---|---|
| Quem usa | Mo baile hoje, Proxyman (script), Charles e Fiddler (manual) | HTTP Toolkit, Proxyman iOS, mitmproxy WireGuard |
| App que ignora proxy (Flutter/Dart, alguns SDKs nativos) | **Escapa** | Capturado, se a porta estiver na lista |
| Exige instalar app no aparelho | Não | Sim |
| Alcance ao host | `adb reverse` (TCP, loopback) | Rede local ou túnel ADB |
| Efeito colateral | Fica no aparelho se o motor morrer sem limpar | Ícone de VPN; conflita com VPN corporativa |

Flutter usa a pilha `dart:io`, que não consulta o proxy do sistema nem o store de
CA do sistema ([OWASP MASTG-TECH-0109](https://mas.owasp.org/MASTG/techniques/android/MASTG-TECH-0109/),
[Proxyman Flutter](https://proxyman.com/flutter)). Um app Flutter, portanto,
**aparece vazio** na aba Rede do Mo baile, e hoje nada avisa isso ao usuário.

### 4.5 HTTP/2, HTTP/3/QUIC, WebSocket, gRPC

- **HTTP/2** é o padrão de fato de apps com OkHttp e URLSession. Proxy que só fala
  HTTP/1.1 do lado do cliente ainda funciona (o cliente negocia ALPN com o
  proxy), mas perde multiplexação e trailers, e trailers são onde o gRPC põe o
  status.
- **HTTP/3/QUIC** vai por UDP e não passa por proxy HTTP. Cronet (Chromium) tenta
  QUIC e cai para TCP quando UDP/443 é bloqueado; a queda nem sempre é graciosa
  ([ExoPlayer #5160](https://github.com/google/ExoPlayer/issues/5160)). Em VPN
  local, bloquear UDP/443 força TCP. Com proxy global, o comportamento de Cronet
  não foi verificado. Chucker 4.3.1 (28/02/2026) corrigiu tempos errados com
  Cronet + QUIC, o que indica uso real em apps
  ([release](https://github.com/ChuckerTeam/chucker/releases)).
- **WebSocket**: suportado por Proxyman, Charles, HTTP Toolkit e mitmproxy (sem
  replay neste).
- **gRPC**: exige HTTP/2 fim a fim e decodificação Protobuf. mitmproxy tem
  contentview interativa; Proxyman e Charles decodificam Protobuf com descritor;
  HTTP Toolkit decodifica sem schema.

### 4.6 Matriz de protocolo e captura mobile

| | HTTP/2 | HTTP/3 | WebSocket | gRPC/Protobuf | Android sem root | Injeção CA sistema | iOS |
|---|---|---|---|---|---|---|---|
| Proxyman | sim | não | sim | Protobuf | CA usuário | emulador (script) | Atlantis, VPN, simulador |
| Charles | sim | não | sim | Protobuf c/ descritor | CA usuário | manual | proxy manual |
| HTTP Toolkit | sim | não verificado | sim | Protobuf sem schema | VPN + CA usuário | root/emulador | proxy manual |
| mitmproxy | sim | experimental | sim | contentview | WireGuard + CA usuário | manual | WireGuard |
| Fiddler Everywhere | não verificado | não verificado | não verificado | não verificado | CA usuário | não oficial | proxy manual |
| Burp | sim | via extensão | sim | extensão | CA usuário | manual | proxy manual |
| **Mo baile hoje** | não | não | não | não | **só túnel, sem decifrar** | não | não configura |

---

## 5. Fichas: depuração dentro do app

Estas ferramentas não interceptam a rede: ficam **dentro** do processo, como
interceptor de OkHttp ou `URLProtocol`. Não precisam de CA nem de proxy e não
sofrem com pinning, mas exigem recompilar o app.

| Ferramenta | Plataforma | Mecanismo | Licença | Estado | Destaques | Fonte |
|---|---|---|---|---|---|---|
| **Chucker** | Android | Interceptor OkHttp + notificação + UI no app; artefato `library-no-op` para release | Apache-2.0 | 4.3.1, 28/02/2026 | Redação de headers, retenção configurável, decodificadores de corpo (Protobuf, Thrift), min SDK 21 | [repo](https://github.com/ChuckerTeam/chucker) |
| **Pulse** | iOS/macOS/watchOS/tvOS/visionOS | `URLSession` via `PulseProxy`/`URLSessionProxy`, `LoggerStore` local, `RemoteLogger` por Bonjour até o app de Mac | MIT (framework); app Pro proprietário, preço não verificado | 5.2.3, 10/06/2024 (parado desde então) | Busca em 1M+ mensagens, exportação `.pulse`, "não é proxy" por definição | [repo](https://github.com/kean/Pulse), [releases](https://github.com/kean/Pulse/releases) |
| **Flipper** (Network) | Android/iOS/RN | Plugin nativo + desktop Electron | MIT | **Arquivado** 26/09/2025 | Era a referência da Meta | [repo](https://github.com/facebook/flipper) |
| **Reactotron** | React/React Native | App desktop + biblioteca cliente por WebSocket | MIT | ativo | Rede, estado Redux/MST, AsyncStorage | [repo](https://github.com/infinitered/reactotron) |
| **Stetho** | Android | Chrome DevTools Protocol, interceptor OkHttp | MIT | **Arquivado** 31/03/2026 | Legado | [repo](https://github.com/facebookarchive/stetho) |
| **Wormholy** | iOS 16+ | Swizzling de `URLProtocol` em `URLSessionConfiguration.default/.ephemeral`; UI por shake | MIT | ativo | Exporta coleção Postman e cURL | [repo](https://github.com/pmusolino/Wormholy) |
| **netfox** | iOS/macOS | `URLProtocol`; UI por shake | MIT | 1.21.0 | Estatísticas, compartilhamento por e-mail | [repo](https://github.com/kasketis/netfox) |

**Lição do grupo.** O padrão "biblioteca embarcada que fala com um app de
desktop" (Pulse com Bonjour, Reactotron com WebSocket, Proxyman Atlantis) é o
único que vence pinning, Flutter e QUIC sem root. O custo é pedir ao time do app
que adicione uma dependência de debug. Para o Mo baile, isso é uma opção de
longo prazo (seção 11, ideia 12), não de curto.

---

## 6. Recursos de produtividade: quem faz o quê

| Recurso | Proxyman | Charles | HTTP Toolkit | mitmproxy | Fiddler | Burp | Mo baile hoje |
|---|---|---|---|---|---|---|---|
| Breakpoint (editar requisição/resposta) | sim | sim | Pro | sim (intercept) | Pro | sim | não |
| Map Local / mock | sim | sim | Pro | script | Pro | extensão | não |
| Map Remote / redirect | sim | sim | Pro | script | Pro | sim | não |
| Rewrite declarativo | script JS | Rewrite | Pro | script Python | regras | Match/Replace | não |
| Scripting | JS + npm | não | não | Python | não verificado | Java/Python | não |
| Diff de respostas | sim | não verificado | não | não | não verificado | Comparer | não |
| HAR export | sim | sim | Pro | sim | sim | sim | sim (**no Swift**) |
| Geração de código | cURL, código | não verificado | Pro | cURL | não verificado | cURL | asserção fictícia |
| Throttling | Network Conditions | sim | não verificado | script | não verificado | não | não |
| Filtro por corpo | jq | não | sim | expressões | sim | sim | só host/path/status |
| Automação externa | CLI + MCP | CLI | API local | Python | não verificado | REST | JSON-RPC (ótimo ponto de partida) |

Fontes: fichas acima. "Não verificado" onde a documentação consultada não
confirma.

---

## 7. Fichas: QA de analytics e tagueamento

### 7.1 Firebase DebugView

- **Ativação.** Android: `adb shell setprop debug.firebase.analytics.app PACOTE`.
  iOS: argumento `-FIRDebugEnabled`. **Persiste até ser desligado
  explicitamente** (`.none.` no Android, `-FIRDebugDisabled` no iOS).
- **Por que existe.** Fora do modo debug os eventos são agrupados "por cerca de
  uma hora" antes de subir; em debug sobem com atraso mínimo.
- **O que mostra.** Fluxo de segundos (60 s), fluxo de minutos (30 min), top
  eventos e propriedades de usuário por aparelho.
- **Efeito colateral.** Eventos em modo debug **entram na exportação diária do
  BigQuery por padrão**; o próprio Firebase recomenda filtro de tráfego de
  desenvolvedor.
- Fonte: [DebugView](https://firebase.google.com/docs/analytics/debugview).
- Log verboso: `setprop log.tag.FA VERBOSE`, `FA-SVC` e `logcat -v time -s FA FA-SVC`
  na documentação de eventos, aba Android
  ([events](https://firebase.google.com/docs/analytics/events?platform=android));
  no iOS, `-FIRAnalyticsVerboseLoggingEnabled` (verificado na aba iOS).

**Forte:** gratuito, oficial, mostra o que o servidor recebeu. **Fraco:** nuvem,
latência de segundos, sem noção de passo de teste, sem plano de medição, e depende
de o aparelho ter internet.

### 7.2 GA4 DebugView

Mesma tela no GA4. Ativação por `debug_mode` no gtag, no Google Tag Manager ou
pelo Tag Assistant. Janela de 30 minutos; seletor de aparelho. Eventos em debug
ficam fora dos relatórios comuns
([ajuda GA](https://support.google.com/analytics/answer/7201382)).

**Limites de coleta do GA4** que valem como regra de validação automática
([limites](https://support.google.com/analytics/answer/9267744)): nome de evento
até 40 caracteres, 25 parâmetros por evento, nome de parâmetro até 40, valor até
100 (exceções: `page_title` 300, `page_referrer` 420, `page_location` 1000), 25
propriedades de usuário com nome até 24 e valor até 36, 500 nomes de evento
distintos por usuário de app. Prefixos reservados (`firebase_`, `google_`,
`ga_`) constam da referência do SDK; não reverificado nesta rodada.

### 7.3 Adobe Experience Platform Assurance (ex-Project Griffon)

- **Arquitetura.** O SDK Mobile da Adobe abre sessão com o serviço Assurance por
  deep link, QR code ou botão, com handshake por **PIN**; eventos vão por HTTPS
  (TLS 1.2) e aparecem ao vivo no navegador.
- **Vistas.** Eventos brutos do SDK, logs, configuração e versões de extensão,
  Adobe Analytics com status pós-processamento, Media, Location, filtros e
  capturas de tela.
- **Acesso.** Todos os clientes Experience Cloud desde 15/10/2022; sessão apagada
  em 30 dias; criptografada em repouso.
- Fonte: [Assurance](https://experienceleague.adobe.com/en/docs/experience-platform/assurance/home).

**Lição:** o SDK sabe que está em sessão de QA e manda **tudo**, incluindo o
estado de configuração. É o equivalente a um "modo QA" de primeira classe, mas só
para o ecossistema Adobe.

### 7.4 Avo Inspector

- **Arquitetura.** SDK (ou integração via Segment/RudderStack) que envia **só o
  schema** do evento (`{revenue: "float"}`), nunca os valores. Em dev, sem
  batching; em produção, lotes de 30 schemas a cada 30 s.
- **Detecta.** Tipo divergente, propriedade obrigatória ausente, nomenclatura
  inconsistente, comparando com o Tracking Plan do Avo; Codegen gera funções
  tipadas.
- **Preço.** Free com 2 editores e 100 mil eventos observados; Team US$ 250/mês
  anual com 5 editores; Enterprise sob consulta.
- Fontes: [overview](https://www.avo.app/docs/inspector/avo-inspector-overview),
  [pricing](https://www.avo.app/pricing).

**Lição:** validar **forma** (nome, tipo, obrigatoriedade) resolve a maior parte
dos defeitos sem precisar guardar dado pessoal.

### 7.5 Segment Protocols e Source Debugger

Tracking Plan como fonte da verdade, violações agregadas e detalhadas com payload
de exemplo, encaminhamento de violações para outra Source, bloqueio de eventos
fora do plano, Typewriter para gerar cliente tipado. Protocols é **add-on do
plano Business**
([overview](https://segment.com/docs/protocols/),
[violations](https://segment.com/docs/protocols/validate/review-violations/)).
Source Debugger mostra eventos ao vivo por fonte
([debugger](https://segment.com/docs/connections/sources/debugger/), não
reverificado: 403 na consulta).

### 7.6 Amplitude Data e Ampli

Plano de tracking no Amplitude Data gera um wrapper tipado (Ampli). `ampli status`
varre o código-fonte, conta chamadas por evento e **falha se o plano tem evento
não implementado**; roda em CI com `ampli status -u -b main`
([Ampli CLI](https://amplitude.com/docs/sdks/ampli/ampli-cli),
[CI](https://amplitude.com/docs/sdks/ampli/validate-in-ci)). Free com 2 milhões
de eventos/mês; a página de preços não diz em que plano o Data/Ampli está
([pricing](https://amplitude.com/pricing)).

**Lição:** validação **estática** (o evento existe no código?) complementa a
dinâmica (o evento saiu quando o usuário tocou?). O Mo baile só pode fazer a
segunda, e é justamente a que ninguém faz bem em app nativo.

### 7.7 Mixpanel Lexicon

Dicionário de dados: descrição, tags, dono, ocultar, bloquear (irreversível),
mesclar eventos duplicados, importação de dicionários do Segment, Avo e
mParticle, API de schemas em JSON
([Lexicon](https://docs.mixpanel.com/docs/data-governance/lexicon)). Free até
1 milhão de eventos/mês; verificação de dados no Enterprise
([pricing](https://mixpanel.com/pricing/)). É governança pós-coleta, não QA.

### 7.8 Snowplow Micro

Pipeline Snowplow em miniatura num container Docker (`snowplow/snowplow-micro`,
porta 9090) que **recebe, valida contra schemas e enriquece** eventos; UI em
`/micro/ui`, API REST (`/micro/good` e afins), exportação TSV/JSON, feito para
teste automatizado e CI
([docs](https://docs.snowplow.io/docs/testing/snowplow-micro/basic-usage/)).
Licença **Snowplow Limited Use License**, não open source
([repo](https://github.com/snowplow-incubator/snowplow-micro)).

**Lição:** este é o modelo arquitetural mais próximo do que o Mo baile deveria
oferecer: um coletor local que o teste consulta por API (`quantos eventos bons,
quantos ruins, reset`) no meio da execução.

### 7.9 Trackingplan

Observador passivo das requisições de saída para mais de 80 destinos (GA4, Meta,
Google Ads, TikTok) via tag web, SDK iOS/Android ou hook de servidor; **descobre
o plano sozinho** a partir do tráfego real e alerta sobre propriedade ausente,
mudança de schema, pixel quebrado, disparo duplicado, violação de consentimento
e PII ([site](https://www.trackingplan.com/)). US$ 249/mês anual; Enterprise a
partir de US$ 1.750/mês; trial de 14 dias
([pricing](https://www.trackingplan.com/pricing)).

**Lição:** "inferir o plano do tráfego" é uma boa forma de **começar** um plano
de medição quando o cliente não tem um; o Mo baile pode fazer isso localmente, a
partir de uma sessão gravada.

### 7.10 ObservePoint

Auditoria de tags web (crawls, Journeys, privacidade, consentimento). Para app,
o próprio fornecedor aponta dois caminhos: **HAR Analyzer**, que processa HAR
exportado de Charles, Proxyman ou device farms, e **LiveConnect**, um proxy
hospedado pela ObservePoint com CA própria instalada no aparelho, que aplica
regras de tag e variável em tempo real
([HAR Analyzer](https://help.observepoint.com/en/articles/9113452-har-analyzer),
[LiveConnect](https://help.observepoint.com/en/articles/9113477-liveconnect-create-a-new-journey),
[App Journeys](https://www.observepoint.com/feature/app-journeys)). Preço sob
consulta.

**Lição:** o fornecedor mais caro do setor aceita **HAR** como formato de troca
para app. Um HAR bem feito pelo Mo baile entra direto nesse fluxo.

### 7.11 Charles (ou Proxyman) com filtro de GA

A prática de campo: filtrar `google-analytics.com/g/collect` para web e WebView
(parâmetros legíveis na query string) e `app-measurement.com/a` para app nativo.
No app nativo o corpo é **Protobuf sem `.proto` público**; a comunidade mantém um
`.proto` reconstruído, que se carrega no registro de descritores do Charles para
ler o lote como `app_measurement.Batch`
([lari/firebase-ga4-app-measurement-protobuf](https://github.com/lari/firebase-ga4-app-measurement-protobuf),
[Gunnar Griese, 05/05/2023](https://gunnargriese.com/posts/firebase-analytics-debugging/)).
Fora do modo debug, o lote sobe de hora em hora.

**Conclusão para o Mo baile:** para Firebase, **logcat e Unified Logging vencem o
proxy** (tempo real, legível, sem CA). Para SDKs que mandam JSON (Segment,
Amplitude, Mixpanel, Adobe Edge) e para GA4 em WebView, o proxy vence, desde que
decifre HTTPS.

---

## 8. Referências de correlação de linha do tempo

Nenhuma ferramenta de proxy correlaciona toque com requisição. Onde a ideia
existe, ela está em outras categorias:

| Ferramenta | O que faz | Como associa | Fonte |
|---|---|---|---|
| **Playwright Trace Viewer** | Linha do tempo de ações com snapshot antes/durante/depois; aba de rede filtrável pela janela de uma ação | Janela de tempo da ação | [docs](https://playwright.dev/docs/trace-viewer) |
| **Datadog RUM** | Ação de usuário (toque) e recursos (rede via interceptor OkHttp) | Atividade termina após **100 ms sem atividade** (browser); no Android, recursos ligados à ação/visão ativa | [page activity](https://docs.datadoghq.com/real_user_monitoring/browser/monitoring_page_performance/), [Android](https://docs.datadoghq.com/real_user_monitoring/android/advanced_configuration/) |
| **Sentry** | Breadcrumbs automáticos de clique de UI e HTTP (OkHttp) no mesmo rastro | Ordem temporal | [breadcrumbs](https://docs.sentry.io/platforms/android/enriching-events/breadcrumbs/) |
| **Adobe Assurance** | Eventos do SDK, analytics e capturas de tela na mesma sessão | Sessão | seção 7.3 |

A combinação que falta no mercado, **para app nativo, sem SDK embarcado e durante
a automação**, é: toque gravado (com elemento e localizador) + requisição HTTP +
evento de analytics + captura de tela, numa só linha do tempo, com veredito
contra um plano de medição. O Mo baile já tem três das quatro fontes no mesmo
processo.

---

## 9. Matriz comparativa geral

| | Categoria | Onde roda | Licença | Preço de entrada | Mobile nativo | Liga toque ↔ rede ↔ analytics | Valida plano de medição |
|---|---|---|---|---|---|---|---|
| Proxyman | proxy | macOS/Win/Linux/iOS/Android | proprietária | US$ 89 | forte (iOS) | não | não |
| Charles | proxy | Java desktop | proprietária | US$ 30 | manual | não | não |
| HTTP Toolkit | proxy | Electron + Node | AGPL (Free) + Pro | grátis | forte (Android) | não | OpenAPI (Pro) |
| mitmproxy | proxy | Python/Rust | MIT | grátis | WireGuard | não | não (script) |
| Fiddler Everywhere | proxy | desktop | proprietária | US$ 7/mês | manual | não | não |
| Burp | segurança | Java desktop | proprietária | grátis / US$ 499/ano | manual | não | não |
| Requestly | regras/mock/API | extensão + desktop | AGPL + proprietária | US$ 10/mês | prometido | não | não |
| Chucker / Pulse / Wormholy / netfox | in-app | dentro do app | Apache/MIT | grátis | sim (debug build) | não | não |
| Firebase / GA4 DebugView | analytics | nuvem | serviço | grátis | sim | não | não |
| Adobe Assurance | analytics | nuvem + SDK | serviço | incluso Adobe | sim (Adobe) | parcial (sessão) | validações próprias |
| Avo Inspector | plano | nuvem + SDK | serviço | grátis / US$ 250/mês | sim | não | **sim** (schema) |
| Segment Protocols | plano | nuvem | serviço | add-on Business | via Segment | não | **sim** |
| Amplitude Ampli | plano | CLI + nuvem | serviço | não verificado | estático | não | **sim** (estático) |
| Mixpanel Lexicon | governança | nuvem | serviço | Free 1M eventos | via Mixpanel | não | parcial |
| Snowplow Micro | coletor local | Docker | Limited Use | grátis | via tracker | não | **sim** (schemas) |
| Trackingplan | monitor | nuvem + SDK | serviço | US$ 249/mês | sim | não | **sim** (inferido) |
| ObservePoint | auditoria | nuvem | serviço | sob consulta | via HAR/LiveConnect | não | **sim** (regras) |
| **Mo baile (alvo)** | inspetor + automação | local | — | — | Android e iOS | **sim** | **sim**, por passo |

---

## 10. Confronto com o código do Mo baile

Lido em 29/09/2026, incluindo as mudanças não commitadas em `adb.py`,
`analytics_logcat.py`, `proxy.py` e `rpc/server.py`.

### 10.1 O que existe e funciona

- **Proxy próprio** (`engine/src/mobaile/adapters/proxy.py`): loopback, teto de
  corpo (256 KiB), histórico circular (2000), limite de conexões (512), redação na
  entrada, resposta genérica em erro, resposta local a *connectivity check*.
- **Configuração do aparelho** (`adb.py`, `setup_reverse_proxy` e
  `teardown_reverse_proxy`): `adb reverse` + `http_proxy`, com rollback em falha;
  agora desliga `captive_portal_mode` durante a sessão.
- **Analytics** (`analytics_logcat.py`): logcat com `FA`, `FA-SVC`,
  `FirebaseAnalytics`, `FA-GMS` em VERBOSE, buffer de 8 MB, modo DebugView para o
  pacote em primeiro plano; iOS por `xcrun simctl spawn … log stream`.
- **RPC** (`rpc/server.py`): `proxy.start/stop/events/clear`,
  `analytics.start/stop/events/clear`, notificações `proxy.event` e
  `analytics.event`; `shutdown` desfaz o proxy do aparelho.
- **Front**: tabela HTTP com filtro por host/path/status, detalhe de requisição e
  resposta, exportação HAR, tabela de analytics com parâmetros e log bruto, TSV e
  JSON; `CorrelationCard` na coluna do espelho.

### 10.2 Defeitos verificados

Reproduzidos com script local, sem aparelho (proxy real + servidor HTTP local, e
o parser real alimentado com linhas no formato do logcat).

| # | Onde | Defeito | Evidência |
|---|---|---|---|
| D1 | `proxy.py` `_handle_http` | Resposta `Transfer-Encoding: chunked`: `http.client` desfaz o chunking, mas o header `Transfer-Encoding: chunked` é repassado com o corpo já decodificado. O app recebe resposta malformada | Cliente recebeu `Transfer-Encoding: chunked` seguido de `{"a":1}` cru |
| D2 | `proxy.py` `_decode_body` | Corpo `Content-Encoding: gzip` é tratado como texto (o `Content-Type` é JSON) e aparece como lixo binário na inspeção e no HAR | Evento com `response_body` começando por `\x1f\x8b` |
| D3 | `proxy.py` `_handle_http` | `resp.read()` lê a resposta inteira antes de repassar: sem streaming (SSE, long-poll) e sem teto de memória para download em texto claro. O teto de 256 KiB vale só para a captura | Leitura do código, linhas 340–350 |
| D4 | `proxy.py` | Corpo de requisição `chunked` não é lido (só `Content-Length`) | Leitura do código, `_read_request_body` |
| D5 | `rpc/server.py` `proxy_start` e `analytics_start` | Cada chamada **adiciona outro callback** sem remover o anterior. Ligar, desligar e ligar de novo duplica cada linha na tela; o front (`EngineSession.swift`, `proxy.event`) faz `append` sem deduplicar por `id` | Linhas 581 e 606 do servidor; 787–794 do `EngineSession` |
| D6 | `analytics_logcat.py` | `event_queue = queue.Queue()` sem teto, alimentada a cada evento e **nunca drenada** no modo RPC (só a UI Tk legada consome). Sessão longa cresce sem limite | Busca por `event_queue` no motor |
| D7 | `analytics_logcat.py` `_parse_line` | Parâmetro `items` de e-commerce (Bundle aninhado) é quebrado: `items` vira `'[Bundle[{item_id=SKU1'` e `price`/`quantity` do **segundo item sobrescrevem** o nível de cima | `purchase` → `{'items': '[Bundle[{item_id=SKU1', 'price': '89.9', 'quantity': '1}]]'}` |
| D8 | idem | Todo valor vira `str`; o log distingue `99.9`, `5` e `BRL`, mas o parser descarta o tipo. Validação de tipo contra plano fica impossível | `engagement_time_msec: '5'` |
| D9 | `analytics_logcat.py` `stop` | `debug.firebase.analytics.app` fica ligado no aparelho depois de parar. Pelo Firebase, persiste até `.none.` (ou reboot) e o tráfego em debug **entra no BigQuery** do cliente por padrão | Doc DebugView; `stop()` não mexe em `setprop` |
| D10 | `adb.py` `teardown_reverse_proxy` | `captive_portal_mode` é apagado em vez de restaurado. Se o aparelho tinha valor próprio (MDM, laboratório), a sessão o perde | Leitura do código |
| D11 | `analytics_logcat.py` `_parse_line` | `timestamp` é a hora do **host** ao ler a linha; `time_str` é a hora do **aparelho** sem data e sem fuso. As duas colunas usam relógios diferentes | Leitura do código |
| D12 | `proxy.py` | O evento só é emitido no `finally`. Túnel `CONNECT` aparece quando fecha, até 120 s depois, com o `timestamp` do início: a linha do tempo recebe itens "do passado" | Leitura do código |

### 10.3 Lacunas e fachadas

- **HTTPS não é decifrado** (já registrado em `docs/SEGURANCA.md`, pendência 1).
  Com isso a aba Rede é, para app moderno, uma lista de túneis.
- **iOS sem proxy**: `proxy_start` só configura Android. Simulador iOS usa o
  proxy do macOS, que o Mo baile não toca.
- **iOS sem log de analytics garantido**: o predicado procura "Logging event",
  que o SDK só emite com `-FIRAnalyticsVerboseLoggingEnabled` (ou
  `-FIRDebugEnabled`). O Mo baile não lança o app com esses argumentos.
- **Lógica no front, contra a regra do projeto**:
  `apps/MoBaile/Sources/MoBaile/Models/HARExporter.swift` gera HAR; o TSV é
  montado em `AnalyticsToolbar.swift` com chaves **ordenadas**, enquanto
  `export_as_tsv` no motor usa a **ordem de chegada**. Duas implementações que
  já divergem.
- **`CorrelationCard` é fachada**: gera
  `self.network_interceptor.wait_for_request(...)`, função que não existe no
  código gerado, sobre "a última requisição" (não a do passo), e, sem tráfego,
  insere o endpoint fixo `/v2/credito/simulacao`.
- **Passo gravado não tem hora**: `AutomationStep` não carrega timestamp, então
  não há como saber quais requisições e eventos vieram depois dele.
- **App que ignora proxy** (Flutter) aparece como "nenhum tráfego", sem aviso.
- **Sem pacote de origem**: com proxy global, todo o tráfego do aparelho se
  mistura (Play Services, push, outros apps).

---

## 11. Lições para o Mo baile

Esforço: **P** até 2 dias, **M** até 2 semanas, **G** mais que isso. As ideias
estão em ordem de valor por custo; as marcadas com ★ formam o diferencial.

### Ideia 1: higiene do analytics (P)

- **Problema.** D5 a D9: duplicação de linhas, fila sem teto, e-commerce
  quebrado, tipo perdido, modo debug esquecido ligado.
- **Evidência.** Seção 10.2; Firebase documenta a persistência e o efeito no
  BigQuery.
- **Proposta.** Registrar o callback uma vez no `__init__` do servidor (ou
  guardar e remover); tirar a `event_queue` do caminho RPC ou dar `maxsize` com
  `put_nowait`; trocar o parser de `Bundle[...]` por um tokenizador com pilha que
  suporte `[Bundle[{...}], ...]`; inferir tipo (`int`, `float`, `bool`, `str`)
  e guardar `params` com tipo e `params_raw`; em `stop()`, `setprop
  debug.firebase.analytics.app .none.` e restaurar `log.tag.*` e o tamanho de
  buffer anteriores.
- **Risco.** Baixo. O formato do log do Firebase não é contrato público; manter
  fixtures de linhas reais por versão do SDK.
- **Pronto quando.** Teste com o `purchase` de dois itens devolve `items` como
  lista de dois dicionários com `price` `float`; ligar/desligar/ligar a escuta
  três vezes produz uma notificação por evento; depois de `analytics.stop`,
  `getprop debug.firebase.analytics.app` devolve `.none.`.

### Ideia 2: higiene do proxy HTTP (P)

- **Problema.** D1 a D4, D10, D12.
- **Evidência.** Seção 10.2, reproduzido.
- **Proposta.** Remover `Transfer-Encoding` e recalcular `Content-Length` (ou
  repassar em streaming); descomprimir `gzip`/`deflate`/`br` **só para exibição**;
  repassar corpo em blocos, capturando até o teto; ler requisição `chunked`;
  guardar e restaurar `captive_portal_mode`; emitir `proxy.request` no início e
  `proxy.event` no fim, com o mesmo `id`.
- **Risco.** Baixo. Se a ideia 6 adotar mitmproxy, parte disso vira descartável;
  ainda assim vale corrigir já, porque D1 quebra app.
- **Pronto quando.** Testes de integração com resposta `chunked` e `gzip`
  passam; download de 100 MB em texto claro não passa de 50 MB de RSS no motor;
  `captive_portal_mode` volta ao valor original.

### Ideia 3: exportações no motor e fim das fachadas (P)

- **Problema.** HAR e TSV em Swift, divergentes do motor; `CorrelationCard` com
  endpoint inventado.
- **Evidência.** Regra de disciplina em `docs/ARQUITETURA.md`; ObservePoint e
  Proxyman usam HAR como formato de troca.
- **Proposta.** `proxy.export_har` e `analytics.export` (TSV, JSON) no motor,
  usando campos customizados que o HAR 1.2 permite com prefixo `_`
  ([spec W3C](https://w3c.github.io/web-performance/specs/HAR/Overview.html)):
  `_mobaile.step`, `_mobaile.analytics`, `_mobaile.device`. O front só salva o
  arquivo. `CorrelationCard` fica desabilitado até a ideia 4 existir.
- **Risco.** Baixo; regerar fixtures com `make fixtures`.
- **Pronto quando.** `HARExporter.swift` removido; HAR do motor abre sem erro
  no Chrome DevTools e no HAR Analyzer; nenhum endpoint literal no front.

### ★ Ideia 4: relógio único e linha do tempo da sessão (M)

- **Problema.** Três fontes (toque, HTTP, analytics) com relógios diferentes e
  sem hora no passo gravado (D11, D12, seção 10.3). Sem isso, correlação é
  palpite.
- **Evidência.** Playwright Trace Viewer filtra a rede pela janela da ação;
  Datadog fecha a ação após 100 ms sem atividade; nenhum proxy faz isso
  (seção 8).
- **Proposta.**
  1. Relógio da sessão no motor: `time.monotonic_ns()` para ordenar, mais
     `time.time()` para exibir.
  2. Deslocamento do aparelho: medir `offset = t_aparelho − (t0 + t1)/2` com
     ida e volta pelo `adb shell` no início e a cada minuto; usar `logcat -v
     epoch,usec` (formatos documentados em
     [logcat](https://developer.android.com/tools/logcat)) para que o evento de
     analytics traga a hora do aparelho com data, convertida para o relógio da
     sessão. iOS em simulador compartilha o relógio do Mac.
  3. `AutomationStep` ganha `t_start` e `t_end` (toque e fim do *settle* do
     espelho, que o `stream.settled` já detecta).
  4. Entidade `TimelineItem {id, t, kind: step|http|analytics|frame, ref,
     step_id?, attribution: certa|provável|nenhuma}` e RPC `timeline.list`,
     notificação `timeline.item`.
  5. Atribuição: item pertence ao passo N se `t ∈ [t_start(N), t_start(N+1))`
     e, para HTTP, se começou até `W` segundos (padrão 3 s, configurável) após o
     toque; hosts de ruído (connectivity check, crash reporter, Play Services)
     numa lista de exclusão editável. Marcar como "provável": tempo não prova
     causa.
- **Risco.** Médio. Precisão limitada pela latência do adb (ordem de
  milissegundos a dezenas; não medido). Tráfego em segundo plano polui a janela.
  Sem HTTPS decifrado, o lado HTTP só mostra hosts.
- **Pronto quando.** Em `make qa`, com aparelho falso, um fluxo de 3 toques gera
  linha do tempo em que cada evento de analytics injetado cai no passo certo;
  com aparelho real, erro de relógio medido abaixo de 50 ms em 10 execuções.

### ★ Ideia 5: plano de medição e veredito por passo (M)

- **Problema.** O QA de tagueamento hoje compara à mão o `log_obtido.json` com
  uma planilha. Ninguém no mercado faz isso por passo de teste em app nativo.
- **Evidência.** Avo e Segment validam forma contra plano (em nuvem); Snowplow
  Micro valida contra schema localmente e responde por API; Trackingplan infere o
  plano do tráfego; limites do GA4 são públicos (seção 7).
- **Proposta.**
  - Formato `plano.json` (ou YAML), importável de TSV de planilha:
    ```json
    {"version": 1, "events": [{
      "name": "purchase",
      "when": {"after_step": "btn_finalizar", "within_s": 5},
      "params": {
        "currency": {"type": "string", "enum": ["BRL"], "required": true},
        "value":    {"type": "number", "min": 0, "required": true},
        "items":    {"type": "array", "min_items": 1}
      },
      "count": {"exactly": 1}
    }]}
    ```
  - Regras embutidas sem plano: limites do GA4 (40/40/100/25), nome em
    `^[A-Za-z][A-Za-z0-9_]*$`, prefixos reservados, evento duplicado no mesmo
    passo, parâmetro com cara de PII (reaproveitar as chaves de
    `mobaile.security.redaction`).
  - Serviço `services/measurement.py` no motor, sem I/O; RPC `plan.load`,
    `plan.validate`, notificação `plan.verdict` com
    `{step_id, expected, found, status: ok|ausente|extra|parametro_invalido, detalhe}`.
  - Modo "inferir plano": gerar um rascunho de plano a partir de uma sessão
    gravada, para quem não tem plano.
  - Relatório exportável (Markdown e TSV) por passo.
- **Risco.** Médio. Formato de plano varia por empresa; começar pelo mínimo e
  aceitar import. Não virar governança de dados (isso é Avo e Lexicon).
- **Pronto quando.** Carregar um plano de 10 eventos, executar o fluxo gravado e
  ver, por passo, verde, amarelo (extra) ou vermelho (ausente/parâmetro
  inválido); relatório reproduzível pela linha de comando sem o front.

### ★ Ideia 6: HTTPS de verdade, em camadas (G)

- **Problema.** Sem decifrar TLS, a metade HTTP do diferencial não existe.
- **Evidência.** Seções 3 e 4. Todas as ferramentas de mercado combinam CA
  própria + configuração do aparelho; o caminho sem root para app da própria
  empresa é `debug-overrides` + CA de usuário.
- **Proposta, em três degraus.**
  1. **CA do Mo baile** gerada na primeira execução, chave em
     `~/Library/Application Support/Mo baile/` com permissão `0600`, validade
     curta, nome que deixe claro que é de teste; botão "exportar CA" e
     assistente que mostra o XML de `debug-overrides` e o caminho em
     Configurações (Android 11+ não permite automatizar).
  2. **Emulador com root**: injeção no store de sistema pelo método já descrito
     no estudo anterior (tmpfs + `nsenter`), só quando `ro.debuggable=1`, com
     confirmação explícita e desfeita no reboot.
  3. **Motor MITM**: em vez de escrever TLS, HTTP/2 e WebSocket à mão, rodar
     `mitmdump` como **processo filho** com um addon que emite JSON por linha
     para o motor (mesmo padrão do logcat). Isso evita a exigência de Python
     ≥ 3.12 no motor, mantém a licença MIT e herda HTTP/2, WebSocket, gRPC e
     HAR. O proxy próprio fica como modo "só túnel".
- **Risco.** Alto em segurança: chave de CA é segredo; se vazar, permite MITM do
  aparelho de teste. Mitigar com CA por máquina, validade curta, aviso na tela e
  remoção guiada. Empacotar `mitmdump` aumenta o app (não medido). Pinning em
  código continua fora de alcance (ver ideia 11).
- **Pronto quando.** App de exemplo com `debug-overrides` mostra corpo JSON de
  requisição HTTPS na aba Rede, em aparelho físico sem root; emulador com root
  mostra HTTPS de app de terceiro; auditoria de segurança atualizada em
  `docs/SEGURANCA.md`.

### Ideia 7: decodificar hits de analytics no tráfego (M, depende da 6)

- **Problema.** Logcat só cobre Firebase. Apps usam Segment, Amplitude, Mixpanel,
  Adobe e GA4 em WebView.
- **Evidência.** Seção 7.11; Trackingplan observa 80+ destinos pela requisição;
  ObservePoint LiveConnect idem.
- **Proposta.** Decodificadores por destino, no motor, que transformam a
  requisição em `AnalyticsEvent` com `source="network:<vendor>"`: GA4
  `/g/collect` (query string), Segment `/v1/batch`, Amplitude `/2/httpapi`,
  Mixpanel `/track`, Adobe Edge `/ee/v1/interact`. Firebase
  `app-measurement.com/a` como opcional, usando o `.proto` comunitário.
- **Risco.** Médio: formatos mudam sem aviso; manter fixtures por vendor.
- **Pronto quando.** Uma sessão com dois SDKs mostra eventos das duas fontes na
  mesma tabela e na mesma linha do tempo, com a origem indicada.

### Ideia 8: asserção gerada de rede e tagueamento (M, depende das 4 e 5)

- **Problema.** O `CorrelationCard` gera código que não roda.
- **Evidência.** Playwright gera teste a partir da gravação; Snowplow Micro
  expõe API consultável durante o teste.
- **Proposta.** O motor expõe um coletor local consultável (como Snowplow Micro)
  e o gerador de Page Object emite, por passo, `expect_event("purchase",
  currency="BRL")` e `expect_request("POST", "/checkout", status=200)`, com um
  pequeno runtime Python que consulta o coletor. A asserção nasce do que foi
  atribuído ao passo na linha do tempo, não da "última requisição".
- **Risco.** Médio: o teste gerado passa a depender do Mo baile rodando; oferecer
  modo que grava as expectativas e as valida depois, a partir do HAR/JSON.
- **Pronto quando.** Fluxo gravado de 3 passos gera script que falha quando o
  evento de analytics de um passo é removido do app de exemplo.

### Ideia 9: iOS de primeira classe nesta frente (P/M)

- **Problema.** Simulador sem proxy e sem log verboso garantido (seção 10.3).
- **Evidência.** Firebase exige `-FIRDebugEnabled`/`-FIRAnalyticsVerboseLoggingEnabled`;
  Proxyman separa tráfego por simulador.
- **Proposta.** `analytics.start` em iOS relança o app com `xcrun simctl launch
  <udid> <bundle> -FIRDebugEnabled -FIRAnalyticsVerboseLoggingEnabled` (com
  confirmação, porque reinicia o app); proxy em simulador documentado como
  "proxy do macOS" com assistente, sem alterar configuração de rede sem
  consentimento.
- **Risco.** Baixo para analytics; médio para proxy (mexer no proxy do Mac afeta
  a máquina inteira).
- **Pronto quando.** Em simulador, `screen_view` aparece na tabela sem o usuário
  editar o scheme do Xcode.

### Ideia 10: mock mínimo para estados de erro (M, depende da 6)

- **Problema.** QA precisa provocar 500, timeout e resposta vazia para testar a
  tela de erro; hoje depende do backend.
- **Evidência.** Map Local, Rewrite e Breakpoint estão em todas as ferramentas da
  seção 6; Requestly foi comprado para levar isso ao mobile.
- **Proposta.** Regras declarativas no motor (`match` por método, host e path;
  `action` entre `status`, `body_from_file`, `delay_ms`, `drop`), exportáveis
  junto do fluxo gravado. Breakpoint interativo fica fora da primeira versão.
  Para emulador, `adb emu network speed/delay` como throttling sem proxy.
- **Risco.** Médio: regra esquecida ligada engana o QA. Mostrar faixa fixa
  "regras ativas: N" e desligar tudo ao fechar a sessão.
- **Pronto quando.** Regra "POST /checkout → 500" aplicada e visível na linha do
  tempo como "respondido pelo Mo baile".

### Ideia 11: diagnóstico honesto de "por que não vejo tráfego" (P)

- **Problema.** App Flutter, pinning ou QUIC resultam em tela vazia sem
  explicação.
- **Evidência.** Seção 4.4 e 4.5; Fiddler e HTTP Toolkit documentam o limite
  abertamente.
- **Proposta.** Heurísticas no motor: pacote em primeiro plano sem nenhum
  `CONNECT` após toques → "o app pode ignorar o proxy (ex.: Flutter)"; túnel
  fechado logo após o handshake (quando a ideia 6 existir) → "provável
  certificate pinning"; card de diagnóstico no padrão do `DiagnosticCard` que já
  existe. Frida fica **documentado**, não embarcado.
- **Risco.** Baixo; falso positivo aceitável se o texto disser "provável".
- **Pronto quando.** App Flutter de exemplo mostra o aviso em até 30 s de uso.

### Ideia 12: exposição para agentes e biblioteca embarcada (G, longo prazo)

- **Problema.** Casos que proxy nenhum alcança (pinning em código, Flutter em
  aparelho físico) e automação por agente.
- **Evidência.** Proxyman expõe MCP com 30+ ferramentas; Pulse, Reactotron e
  Atlantis usam biblioteca embarcada que fala com o desktop.
- **Proposta.** (a) Um servidor MCP fino sobre o JSON-RPC que já existe, só
  leitura no início (`timeline.list`, `plan.validate`). (b) Estudar um SDK de
  debug opcional (interceptor OkHttp / `URLProtocol`) que manda eventos ao motor
  por `adb reverse`.
- **Risco.** Alto em escopo. MCP abre porta ou processo novo, o que precisa
  passar pela mesma régua de `docs/SEGURANCA.md`.
- **Pronto quando.** Decisão registrada em ADR, com prova de conceito.

### Sequência sugerida

1. Ideias 1, 2, 3 e 11 (uma a duas semanas no total): o que existe fica confiável.
2. Ideias 4 e 5: o diferencial, já útil para Firebase via logcat, **sem depender
   de HTTPS**.
3. Ideia 9: iOS alcança o Android nesta frente.
4. Ideias 6, 7, 8 e 10: HTTPS e o que depende dele.
5. Ideia 12: depois de ter usuários.

---

## 12. Fontes

Todas consultadas em 29/09/2026, salvo indicação.

**Proxies**
- Proxyman: [docs](https://docs.proxyman.com/), [índice](https://docs.proxyman.com/llms.txt), [pricing](https://proxyman.com/pricing), [changelog](https://proxyman.com/changelog), [MCP](https://docs.proxyman.com/mcp.md), [script Android](https://docs.proxyman.com/debug-devices/android-device/automatic-script-for-android-emulator.md), [Atlantis](https://docs.proxyman.com/atlantis/atlantis-for-ios.md), [HTTP/3 issue](https://github.com/ProxymanApp/Proxyman/issues/1555), [Flutter](https://proxyman.com/flutter)
- Charles: [version history](https://www.charlesproxy.com/documentation/version-history/), [tools](https://www.charlesproxy.com/documentation/tools/), [throttling](https://www.charlesproxy.com/documentation/proxying/throttling/), [buy](https://www.charlesproxy.com/buy/)
- HTTP Toolkit: [releases](https://github.com/httptoolkit/httptoolkit-desktop/releases), [pricing](https://httptoolkit.com/pricing/), [Android](https://httptoolkit.com/docs/guides/android/), [Android 11](https://httptoolkit.com/blog/android-11-trust-ca-certificates/), [Android 14](https://httptoolkit.com/blog/android-14-install-system-ca-certificate/), [Frida scripts](https://github.com/httptoolkit/frida-interception-and-unpinning), [Protobuf](https://mastodon.social/@httptoolkit/112049686872777461), [Capterra (indício de preço)](https://www.capterra.com/p/211624/HTTP-Toolkit/)
- mitmproxy: [modes](https://docs.mitmproxy.org/stable/concepts/modes/), [protocols](https://docs.mitmproxy.org/stable/concepts/protocols/), [addons](https://docs.mitmproxy.org/stable/addons/overview/), [CHANGELOG](https://github.com/mitmproxy/mitmproxy/blob/main/CHANGELOG.md), [PyPI](https://pypi.org/project/mitmproxy/), [HAR](https://www.mitmproxy.org/posts/har-support/)
- Fiddler: [purchase](https://www.telerik.com/purchase/fiddler), [Android](https://www.telerik.com/fiddler/fiddler-everywhere/documentation/capture-traffic/capture-from-android)
- Burp: [HTTP/3 Adapter](https://portswigger.net/bappstore/bfd526811899438080ca4bb6b8a03ab5), [pesquisa HTTP/3](https://portswigger.net/research/http3-in-burp-suite), [DAST](https://portswigger.net/burp/dast/pricing), [preço Pro, fonte secundária](https://codeant.ai/blogs/burp-suite-pricing)
- Requestly: [repo](https://github.com/requestly/requestly), [pricing](https://requestly.com/pricing/), [aquisição](https://www.browserstack.com/press/browserstack-acquires-requestly-a-ycombinator-startup-for-http-interception-mocking-debugging-network-requests)
- Postman: [capture](https://learning.postman.com/docs/sending-requests/capturing-request-data/capture-overview/)

**Mobile**
- Android: [network security config](https://developer.android.com/privacy-and-security/security-config), [logcat](https://developer.android.com/tools/logcat)
- Frida: [modes](https://frida.re/docs/modes/); objection: [repo](https://github.com/sensepost/objection)
- Flutter: [OWASP MASTG-TECH-0109](https://mas.owasp.org/MASTG/techniques/android/MASTG-TECH-0109/), [flutter#26359](https://github.com/flutter/flutter/issues/26359)
- QUIC: [ExoPlayer #5160](https://github.com/google/ExoPlayer/issues/5160)

**Depuração embarcada**
- [Chucker](https://github.com/ChuckerTeam/chucker), [releases](https://github.com/ChuckerTeam/chucker/releases); [Pulse](https://github.com/kean/Pulse), [releases](https://github.com/kean/Pulse/releases); [Flipper](https://github.com/facebook/flipper); [Reactotron](https://github.com/infinitered/reactotron); [Stetho](https://github.com/facebookarchive/stetho); [Wormholy](https://github.com/pmusolino/Wormholy); [netfox](https://github.com/kasketis/netfox)

**Analytics**
- Firebase: [DebugView](https://firebase.google.com/docs/analytics/debugview), [events](https://firebase.google.com/docs/analytics/events?platform=android)
- GA4: [DebugView](https://support.google.com/analytics/answer/7201382), [limites](https://support.google.com/analytics/answer/9267744)
- Adobe: [Assurance](https://experienceleague.adobe.com/en/docs/experience-platform/assurance/home)
- Avo: [Inspector](https://www.avo.app/docs/inspector/avo-inspector-overview), [pricing](https://www.avo.app/pricing)
- Segment: [Protocols](https://segment.com/docs/protocols/), [violations](https://segment.com/docs/protocols/validate/review-violations/), [debugger](https://segment.com/docs/connections/sources/debugger/)
- Amplitude: [Ampli CLI](https://amplitude.com/docs/sdks/ampli/ampli-cli), [CI](https://amplitude.com/docs/sdks/ampli/validate-in-ci), [pricing](https://amplitude.com/pricing)
- Mixpanel: [Lexicon](https://docs.mixpanel.com/docs/data-governance/lexicon), [pricing](https://mixpanel.com/pricing/)
- Snowplow Micro: [uso](https://docs.snowplow.io/docs/testing/snowplow-micro/basic-usage/), [repo](https://github.com/snowplow-incubator/snowplow-micro)
- Trackingplan: [site](https://www.trackingplan.com/), [pricing](https://www.trackingplan.com/pricing)
- ObservePoint: [HAR Analyzer](https://help.observepoint.com/en/articles/9113452-har-analyzer), [LiveConnect](https://help.observepoint.com/en/articles/9113477-liveconnect-create-a-new-journey), [App Journeys](https://www.observepoint.com/feature/app-journeys)
- Firebase no proxy: [proto comunitário](https://github.com/lari/firebase-ga4-app-measurement-protobuf), [Gunnar Griese](https://gunnargriese.com/posts/firebase-analytics-debugging/)

**Correlação**
- [Playwright Trace Viewer](https://playwright.dev/docs/trace-viewer), [Datadog page activity](https://docs.datadoghq.com/real_user_monitoring/browser/monitoring_page_performance/), [Datadog Android](https://docs.datadoghq.com/real_user_monitoring/android/advanced_configuration/), [Sentry breadcrumbs](https://docs.sentry.io/platforms/android/enriching-events/breadcrumbs/), [HAR 1.2 (W3C)](https://w3c.github.io/web-performance/specs/HAR/Overview.html)

**Código do Mo baile lido**
- `engine/src/mobaile/adapters/proxy.py`, `analytics_logcat.py`, `adb.py`, `input_events.py`
- `engine/src/mobaile/rpc/server.py`, `engine/src/mobaile/domain/models.py`, `engine/src/mobaile/security/redaction.py`, `engine/pyproject.toml`
- `apps/MoBaile/Sources/MoBaile/Views/Network/*`, `Views/Analytics/*`, `Views/Mirror/CorrelationCard.swift`, `Models/HARExporter.swift`, `Engine/EngineSession.swift`

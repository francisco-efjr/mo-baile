# Modo leve e perfis de desempenho: como nichos parecidos resolvem e o que o Mo baile deve fazer

Pesquisa de 03 e 04/11/2026, trilha de desempenho da rodada
`melhoria/2026-11-03-pycharm-desempenho`. Base de código lida: 3.16.0 (commit
`5689f8e`). Fontes acessadas em 03 e 04/11/2026, salvo indicação.

Pedido do dono, resumido: o Mo baile pode usar o Mac à vontade, mas quando
estiver pesando demais precisa existir um modo mais amigável, "lite", que não
trave e continue bom de usar. Vai rodar em Mac Intel antigo, M1 com 8 GB e
máquinas fortes.

Rótulos usados no texto:

- **Verificado**: lido na fonte citada, nesta pesquisa.
- **Anedótico**: fórum, guia de comunidade ou relato de bug. Serve como indício.
- **Inferido**: dedução minha a partir das fontes ou do código, sem medição.
- **Suposição**: número de partida para calibrar, sem fonte.
- **Não verificado**: não achei fonte.

---

## 1. Resumo executivo

1. **Todo mundo que faz isso bem segue a mesma regra: o modo leve corta o que é
   especulativo e contínuo, não o que o usuário pediu.**
   - O Power Save Mode da JetBrains desliga a análise em segundo plano e o
     autocompletar automático. Build, run, debug, busca e inspeção manual
     continuam funcionando.
   - O Energy Saver do Chrome reduz a taxa de quadros e as tarefas de fundo,
     mas não toca em aba de videochamada nem em aba de áudio.
   - O Appium Inspector deixa pausar a releitura automática do XML, e o botão
     Atualizar continua lá.

   Para o Mo baile, o modo leve **reduz apresentação e cadência** (fps,
   resolução, releitura automática da hierarquia, vidro, animação, retenção de
   histórico). Ele **nunca reduz captura**: nenhum evento de analytics ou de
   rede pode se perder porque o perfil mudou.
2. **Há três jeitos de decidir, e os produtos maduros combinam os três.**
   - Detecção de hardware na primeira execução: Unreal, com
     `RunHardwareBenchmark` e valores de recuo.
   - Sinal do sistema operacional: Chrome e Electron com bateria; Apple com
     `thermalState`, Low Power Mode e oclusão.
   - Consumo medido, com sugestão ao usuário:
     - os "performance issue alerts" do Chrome, com botão "Fix now";
     - o aviso de memória baixa da JetBrains (5% do heap livre), com botão de
       configurar;
     - os alertas de memória do Figma, a 90% do limite;
     - o "Low system resources" do Zoom.
3. **O jeito de comunicar também converge.** Um indicador discreto na barra de
   status: o ícone do Power Save, o ícone do Energy Saver ao lado da barra de
   endereço. Uma sugestão pontual com ação de um clique: "Fix now",
   "Configure". O controle manual sempre ganha da decisão automática.
4. **O Mo baile já tem metade das peças, sem orquestração.**
   - Já existe:
     - `fps`, `max_width` e `quality` no `stream.start`;
     - descarte de quadro idêntico;
     - fila de quadros do Swift com `bufferingNewest(1)`;
     - decodificação fora da main thread;
     - tetos de histórico (proxy 2.000, analytics 5.000, UI 1.000);
     - releitura da hierarquia com debounce;
     - o `GlassSurface.resolve` como função pura;
     - a opção "Iniciar o espelho automaticamente".
   - Falta:
     - um lugar único que decida o perfil;
     - qualquer leitura de sinal do macOS: nada de `thermalState`, Low Power
       Mode, oclusão ou pressão de memória no código;
     - medição de consumo do próprio motor;
     - um jeito de mostrar o perfil ao usuário.
5. **Arquitetura proposta.**
   - Três perfis: **Completo**, **Equilibrado** e **Leve**, mais **Automático**,
     que escolhe entre os três.
   - Um **governador** cuja política é uma função pura no motor, seguindo a regra
     "lógica nova vai para o motor". O Swift atua como sensor (sinais do macOS e
     da janela) e como atuador (vidro, animação, decodificação).
   - O perfil chega aos dois lados por RPC.
   - Histerese: o perfil piora rápido e melhora devagar, com tempo mínimo de
     permanência.
   - Um badge `leve` na barra de status e uma sugestão por sessão quando o
     usuário fixou Completo e o Mac está sofrendo.
6. **Recomendações fortes**, detalhadas na seção 8:
   - (F1) pausar o espelho com a janela oculta;
   - (F2) obedecer `thermalState` e Low Power Mode;
   - (F3) política de perfis num lugar só, com histerese e testes de tabela;
   - (F4) o motor nunca enfileirar quadro, "o mais novo vence" também do lado
     Python;
   - (F5) Leve nunca perde captura;
   - (F6) badge e controle manual;
   - (F7) teto de memória do proxy por bytes, não só por contagem;
   - (F8) métricas locais e guarda de regressão com baseline próprio.

   Benchmark na primeira execução, MetricKit e QoS do processo do motor ficam
   como opcionais.

---

## 2. Método

- Fonte primária primeiro:
  - documentação oficial da Apple (Energy Efficiency Guide for Mac Apps,
    referência do Foundation, AppKit e Dispatch);
  - JetBrains, Android Developers, Appium, scrcpy, Chrome, Electron, Unity e
    Unreal.
- Fórum e guia de comunidade só onde não há documentação: Steam Deck, Xcode,
  Discord e OBS. Esses casos estão marcados como **Anedótico**.
- O estudo anterior
  [`estudo-mercado/03-arquitetura-desempenho-devtools.md`](estudo-mercado/03-arquitetura-desempenho-devtools.md)
  já cobre o transporte de quadros (scrcpy, Android Studio, IPC). Aqui não repito
  essa parte: foco em **modo completo × leve** e em quem decide.
- Código confrontado: `engine/src/mobaile/services/streaming.py`,
  `engine/src/mobaile/config.py`, `engine/src/mobaile/rpc/server.py`
  (`stream_start`, `notify`), `engine/src/mobaile/adapters/proxy.py`,
  `engine/src/mobaile/adapters/analytics_logcat.py`,
  `apps/MoBaile/Sources/MoBaile/Engine/EngineClient.swift`,
  `apps/MoBaile/Sources/MoBaile/Engine/EngineSession.swift` e
  `apps/MoBaile/Sources/MoBaile/Views/DesignSystem/Glass.swift`.
- Nenhuma medição nova foi feita. Os números de custo do Mo baile citados vêm de
  documentos do repositório.

---

## 3. Fichas por nicho

Formato de cada ficha: o que é; o que reduz; como decide; como comunica;
modelo e licença; pontos fortes e fracos; lição para o Mo baile; fontes.

### 3.1 IDEs

#### JetBrains (IntelliJ, PyCharm, Rider): Power Save Mode e aviso de memória

- **O que é.** Um modo global do IDE: Arquivo › Power Save Mode. O objetivo
  declarado é reduzir a atividade de fundo para poupar bateria e CPU (Verificado,
  Rider).
- **O que reduz** (lista oficial do Rider, Verificado):
  - **Análise de código:** inspeções enquanto se digita, análise da solução
    inteira, analisadores caros e Code Vision. A janela Problems para de
    atualizar.
  - **Autocompletar:** popup automático, parameter info automático e
    completion preemptivo em segundo plano.
  - **Interface e VCS:** rolagem suave, animação de cursor, animação de barra de
    progresso indeterminada, atualização automática do log do VCS, indexação do
    log e pré-carga de annotate.
- **O que continua funcionando** (Verificado):
  - completar manual (Ctrl+Space);
  - navegação, busca e refatoração;
  - build, run e debug;
  - commit e push;
  - realce de sintaxe;
  - inspeção sob demanda (Code › Inspect Code).
- **Como decide.** Só manualmente. A página não fala de ativação automática na
  bateria (Não verificado).
- **Como comunica.**
  - Um ícone do Power Save Mode aparece na barra de status e substitui o
    indicador de erros (Verificado).
  - À parte, o **aviso de memória baixa**: quando o heap livre fica abaixo de 5%
    do máximo, o IDE avisa e oferece um botão que abre o ajuste de `-Xmx` com um
    valor sugerido. O IDE não muda sozinho. A mudança exige reiniciar
    (Verificado no CLion; o IntelliJ diz o mesmo).
  - Para serviços de linguagem como o TypeScript, o IDE soma 1.000 MB e
    reinicia o serviço em segundo plano quando ele vai estourar (Verificado na
    página do IntelliJ, via busca). É a única ação automática.
- **Modelo e licença.** Comercial. A plataforma IntelliJ Community é Apache 2.0
  (conhecimento estável; não conferido nesta pesquisa).
- **Pontos fortes:**
  - a fronteira entre especulativo (desliga) e pedido explícito (mantém) é
    clara;
  - o indicador fica num lugar fixo.
- **Pontos fracos:**
  - é binário (liga ou desliga);
  - não reage sozinho a sinal do sistema;
  - a lista do que muda varia por produto e não é fácil de achar. O fórum
    reclama disso (Anedótico).
- **Lição para o Mo baile.**
  - Copiar a fronteira. No Leve, desligar o que roda sem pedido: espelho
    contínuo a cadência alta e releitura automática da hierarquia a cada
    `stream.settled`.
  - Manter tudo que é clique: capturar agora, ler hierarquia, rodar flow,
    auditar.
  - Copiar o aviso com valor sugerido e ação de um clique.
- **Fontes:**
  - [Rider: Power Save Mode](https://www.jetbrains.com/help/rider/Power_save_mode.html)
  - [CLion: Performance tuning tips](https://www.jetbrains.com/help/clion/performance-tuning-tips.html)
  - [IntelliJ: Increase the memory heap](https://www.jetbrains.com/help/idea/increasing-memory-heap.html)
  - [Fórum: "Power Save Mode – exact details?"](https://intellij-support.jetbrains.com/hc/en-us/community/posts/206356739/comments/206958045) (Anedótico)

#### Visual Studio Code: processos separados, exclusões do watcher e bisseção de extensões

- **O que é.** Editor Electron. O modelo de processos é a principal defesa de
  desempenho (Verificado, wiki oficial):
  - a interface fica no processo Renderer;
  - as extensões rodam num **Extension Host** separado;
  - existe ainda um Shared process.
- **O que reduz.** Não tem um "modo leve" único. O VS Code oferece ferramentas
  para o usuário cortar a causa:
  - **Process Explorer:** Help › Open Process Explorer, com CPU por processo;
  - `code --disable-extensions`;
  - **Extension Bisect:** desliga metade das extensões, recarrega e pergunta se
    o problema continua, até achar a culpada;
  - **Startup Performance:** cronômetros de inicialização.

  Tudo Verificado na wiki.
- **`files.watcherExclude`.** Tira pastas grandes do watcher de arquivos. Os
  mantenedores recomendam o ajuste quando o Extension Host é inundado por eventos
  de arquivo durante builds ou quando o processo do watcher prende uma CPU no
  arranque (Verificado em issues oficiais; o padrão exclui `.git/objects` e
  `node_modules`, segundo a busca).
- **Como decide.** O usuário decide, com a ferramenta de diagnóstico.
- **Como comunica.** Diagnóstico sob demanda. Sem badge de modo.
- **Modelo e licença.** Código-fonte MIT (repositório `microsoft/vscode`). O
  binário da Microsoft tem licença própria (conhecimento estável).
- **Pontos fortes:**
  - o isolamento por processo impede que uma extensão trave a digitação;
  - o diagnóstico mostra quem consome.
- **Pontos fracos:**
  - o usuário vira o investigador;
  - extensões novas ignoram as exclusões, como visto em issues de 2026 com
    watchers de agentes (Verificado como relato de bug).
- **Lição para o Mo baile.**
  - O Mo baile já tem o isolamento: o motor é processo filho e a interface não
    trava quando ele pesa, desde que o Swift não espere por ele na main thread.
  - O que falta é o **Process Explorer**: mostrar, no Ambiente ou num popover do
    badge, CPU e memória do motor e de cada filho (adb, scrcpy, iproxy, logcat).
  - Equivalente do watcherExclude: limitar o que o motor observa por padrão. Por
    exemplo, o logcat filtrado por tag em vez do logcat inteiro (Inferido; ver
    seção 5).
- **Fontes:**
  - [VS Code wiki: Performance Issues](https://github.com/microsoft/vscode/wiki/Performance-Issues)
  - [VS Code wiki: File Watcher Issues](https://github.com/microsoft/vscode/wiki/File-Watcher-Issues)
  - [Issue #194341](https://github.com/microsoft/vscode/issues/194341)
  - [Issue #235969](https://github.com/microsoft/vscode/issues/235969)

#### Xcode

- **O que é.** O IDE da Apple.
- **O que reduz.** Não há modo leve oficial documentado (Não verificado). Os
  fóruns da Apple citam três desligamentos manuais (Anedótico):
  - "Show live issues" (Settings › General), que para a compilação de fundo do
    arquivo atual;
  - "Suggest completions while typing";
  - esconder o canvas de Previews.

  Usuários relatam que desligar live issues não para a indexação.
- **Lição para o Mo baile.** Até a Apple deixa o custo de "ao vivo" como opção
  do usuário. O par "ao vivo × sob demanda" é o eixo certo.
- **Fontes:**
  - [Apple Developer Forums 651455](https://developer.apple.com/forums/thread/651455)
  - [Apple Developer Forums 728611](https://developer.apple.com/forums/thread/728611) (Anedótico)

### 3.2 Espelhamento e inspeção mobile

#### scrcpy

- **O que é.** Espelhamento Android de código aberto: servidor no aparelho,
  vídeo H.264 por socket do adb e cliente SDL. A arquitetura está no estudo
  anterior, seção 3.12.
- **O que reduz** (Verificado em `doc/video.md`):

  | Opção | Efeito | Padrão |
  | --- | --- | --- |
  | `--max-size` / `-m` | limita largura e altura | resolução do aparelho |
  | `--video-bit-rate` / `-b` | taxa de bits | 8 Mbps |
  | `--max-fps` | limita a taxa de captura | sem limite |
  | `--video-codec` | codec | h264; também h265, av1, vp8 e vp9 |
  | `--crop` | espelha só parte da tela | — |
  | `--no-video` | não encaminha vídeo | — |
  | `--no-playback` / `--no-video-playback` | não exibe no computador | — |
  | `--print-fps` | diagnóstico | — |

- **Como decide.** Manual, por linha de comando.
- **Como comunica.** `--print-fps` no terminal.
- **Modelo e licença.** Apache 2.0.
- **Pontos fortes:**
  - cada eixo de custo (resolução, bitrate, fps, região, vídeo ligado ou não) é
    independente;
  - o "sem vídeo" existe para quem só quer controle.
- **Pontos fracos:** não há perfil nem adaptação automática.
- **Lição para o Mo baile.**
  - Os eixos do perfil devem ser os mesmos do scrcpy: tamanho máximo, qualidade
    ou bitrate, fps e vídeo ligado ou não.
  - O Mo baile já chama `scrcpy.start` com `fps 60` e `max_size 1080` fixos em
    `EngineSession.startScrcpy`. Esses valores devem vir do perfil.
- **Fontes:**
  - [scrcpy doc/video.md](https://github.com/Genymobile/scrcpy/blob/master/doc/video.md)
  - [Arquivo bruto](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md)

#### Android Studio: Running Devices e Layout Inspector

- **O que é.** Espelhamento de aparelho e emulador dentro do IDE, com o Layout
  Inspector embutido no Running Devices.
- **O que reduz** (Verificado):
  - A Google recomenda o modo **embutido** "para desempenho ótimo".
  - No modo standalone, as **Live Updates** são um botão.
  - Existem **snapshots** exportáveis e importáveis da hierarquia, com render e
    atributos: inspeção sem aparelho, a custo zero de captura.
  - **Deep Inspect** é um modo separado, ligado só quando se quer selecionar
    componentes.
- **Como decide.** Manual.
- **Modelo e licença.** Gratuito. A plataforma é Apache 2.0 (conhecimento
  estável).
- **Lição para o Mo baile.**
  - "Ao vivo" é um botão, e o retrato estático é cidadão de primeira classe.
  - No Leve, a hierarquia vira retrato: lida ao parar a tela, só quando a aba de
    hierarquia estiver visível, ou por clique.
- **Fonte:** [Layout Inspector](https://developer.android.com/studio/debug/layout-inspector)

#### Appium Inspector

- **O que é.** Cliente Electron do Appium.
- **O que reduz** (Verificado):
  - Por padrão o screenshot e o XML são **estáticos** e só são atualizados no
    botão "Refresh Source & Screenshot".
  - Com MJPEG (`appium:mjpegServerPort`) o screenshot fica ao vivo.
  - Com MJPEG aparece um botão **Toggle Automatic Source Refresh**. A
    documentação justifica a pausa quando "o XML é complexo e demora" ou quando
    "a fonte não importa".
- **Como decide.** Manual.
- **Modelo e licença.** Apache 2.0 (conhecimento estável).
- **Pontos fracos.** É justamente a lentidão que o público do Mo baile quer
  deixar para trás. Por padrão, tudo é manual.
- **Lição para o Mo baile.** O piso do Leve não pode cair abaixo do Appium
  Inspector. Leve ainda é espelho com toque, só que a 1 ou 2 quadros por
  segundo, e com a hierarquia ainda automática ao parar a tela, desde que a aba
  esteja visível.
- **Fontes:**
  - [Appium Inspector: Header (2026.7)](https://appium.github.io/appium-inspector/2026.7/session-inspector/header/)
  - [Appium Inspector: Screenshot (2024.9)](https://appium.github.io/appium-inspector/2024.9/session-inspector/screenshot/)

#### Vysor

- **O que é.** Espelhamento Android comercial.
- **O que reduz.** A tabela de preços tem a linha "High Quality Mirroring"
  separando Vysor e Vysor Pro. A divisão exata por plano e os valores de
  resolução ou bitrate não ficaram legíveis na extração (Não verificado).
- **Lição para o Mo baile.** Qualidade do espelho como eixo de produto. Para o
  Mo baile, que é MIT e local, vira eixo de perfil, não de preço.
- **Fonte:** [vysor.io](https://www.vysor.io/)

#### Proxyman e Charles: retenção de tráfego

- **Proxyman** (Verificado na documentação e no changelog, via busca):
  - "Clear Session" (⌥⇧⌘⌫, também pela CLI) libera memória sem fechar o app;
  - "Automatically Remove Older Requests" (Settings › Advanced) remove as
    requisições antigas quando a memória passa de um limite editável;
  - no Windows e no Linux, corpos grandes vão para o disco.
  - Uma issue de 2026 relata o texto "4 GB, no máximo a cada 5 minutos" e um
    vazamento até 204 GB apesar da opção (Anedótico, não confirmado).
- **Charles** (Verificado na documentação atual):
  - guarda cabeçalhos e corpos em memória ou em arquivo temporário;
  - quando a memória fica demais, **avisa e para de gravar**;
  - em Recording Settings dá para limitar o tamanho máximo gravado;
  - historicamente teve o limite "só os últimos X eventos";
  - a recomendação é limpar a sessão.
- **Como decide.** Limite configurável, com ação automática ao cruzar o limite.
- **Lição para o Mo baile.**
  - O teto deve ser por **bytes**, não só por contagem.
  - Corpo grande vai para disco, ou é truncado mais cedo no Leve.
  - Parar de gravar sem avisar é inaceitável. O Charles avisa, e o Mo baile deve
    preferir descartar o mais antigo e avisar.
- **Fontes:**
  - [Proxyman: Clear Session](https://docs.proxyman.com/advanced-features/clear-session)
  - [Proxyman: consome muita RAM](https://proxyman.com/docs/troubleshooting/proxyman-consumes-too-much-ram-and-unresponsive)
  - [Issue #2804](https://github.com/ProxymanApp/Proxyman/issues/2804)
  - [Charles: Recording Settings](https://www.charlesproxy.com/documentation/configuration/recording-settings/)
  - [Charles: runs out of memory](https://www.charlesproxy.com/documentation/faqs/charles-runs-out-of-memory/)

### 3.3 Navegadores

#### Chrome: Memory Saver, Energy Saver e alertas de desempenho

- **O que reduz** (Verificado):
  - **Memory Saver** descarta abas inativas há algum tempo, em três níveis:
    Moderate, Balanced (recomendado) e Maximum.
    - A aba descartada mantém título e favicon e recarrega quando o usuário
      volta.
    - Áudio ou vídeo, compartilhamento de tela, download ativo, aba fixada e
      dispositivo USB ou Bluetooth conectado impedem o descarte.
    - Opcionalmente, um anel no ícone marca a aba inativa.
  - **Energy Saver** reduz a taxa de quadros (rolagem, animação e vídeo), a
    captura de imagem e as tarefas de fundo, e para abas de fundo que pesam na
    CPU.
    - Animações CSS e `requestAnimationFrame` se ajustam sozinhas.
    - Animação em JavaScript que assume 16,67 ms por quadro roda na metade da
      velocidade.
    - Videochamada e áudio não são afetados.
- **Como decide.**
  - O Energy Saver liga sozinho quando o aparelho está desconectado da tomada ou
    com bateria baixa, conforme a escolha do usuário.
  - O Memory Saver age de forma proativa desde o Chrome 108. Antes, só sob
    pressão de memória.
  - Os **performance issue alerts** vêm ligados por padrão. Quando o desempenho
    está ruim, uma notificação recomenda desativar abas, com o botão
    **"Fix now"**.
- **Como comunica.**
  - Ícone do Energy Saver ao lado da barra de endereço, com "Turn off now" para
    a sessão.
  - Anel no favicon.
  - Notificação de alerta.
- **Modelo e licença.** Chromium é BSD (conhecimento estável).
- **Pontos fortes.**
  - Exceções semânticas: o que o usuário está "usando de verdade" não sofre.
  - Desligar só para a sessão.
  - Detectar e sugerir, sem impor.
- **Lição para o Mo baile.** É o modelo mais próximo do pedido do dono:
  - Automático por sinal (bateria ou Low Power Mode e calor);
  - sugestão com ação de um clique quando o consumo medido é ruim;
  - exceções semânticas: gravação de flow, automação rodando e escuta de
    analytics ou rede contam como "videochamada". Não podem ser degradadas a
    ponto de perder evento.
- **Fontes:**
  - [Chrome blog: Memory and Energy Saver](https://developer.chrome.com/blog/memory-and-energy-saver-mode)
  - [Ajuda do Chrome 12929150](https://support.google.com/chrome/answer/12929150?hl=en)

#### Safari e WebKit

- **O que reduz** (Verificado, posts antigos):
  - Página inativa tem os timers estrangulados.
  - No macOS, abas de fundo caem no **App Nap**, que baixa a prioridade delas.
  - O WebKit chegou a alinhar os timers de página oculta em 1 s e a limitar o
    `requestAnimationFrame` a 30 fps em iframes de outra origem sem interação.
  - Sobre `requestAnimationFrame` pausado em página oculta, o comportamento
    atual ficou Não verificado.
- **Lição para o Mo baile.**
  - O macOS já estrangula o que está oculto (App Nap, ver 3.6).
  - O app tem duas tarefas: (a) parar ele mesmo o trabalho invisível, porque o
    App Nap não economiza energia por conta própria; (b) declarar atividade
    quando o trabalho oculto é desejado, como um flow rodando enquanto o usuário
    está no PyCharm.
- **Fonte:** [WebKit: How Web Content Can Affect Power Usage](https://webkit.org/blog/8970/how-web-content-can-affect-power-usage/)

### 3.4 Jogos e apps criativos

#### Unity: Quality Settings e Adaptive Performance

- **O que é.**
  - Quality Settings são níveis nomeados de qualidade: sombra, AA, textura, LOD
    e afins.
  - Adaptive Performance é um pacote que lê o estado térmico e o gargalo do
    dispositivo.
- **O que reduz** (Verificado no guia do usuário do Adaptive Performance 5.1):
  - Um **Indexer** acompanha o estado térmico (nível de alerta e nível de
    temperatura de 0 a 1) e o gargalo (CPU, GPU ou taxa-alvo) e produz um índice
    de qualidade.
  - **Scalers** independentes aplicam o índice: AdaptiveResolution,
    AdaptiveFramerate, AdaptiveLOD, AdaptiveViewDistance, AdaptivePhysics,
    AdaptiveLayerCulling e, no URP, sombras, MSAA, batching e outros.
  - Cada scaler começa em zero, e valor maior baixa a qualidade.
  - Dá para escrever scaler próprio.
- **Como decide.**
  - Automático por padrão, com controle manual possível, mas desaconselhado.
  - O ritmo das mudanças vem de **Thermal Action Delay** e **Performance Action
    Delay**, atrasos depois de aplicar ou remover um scaler. É a histerese do
    sistema.
  - Durante throttling, o sistema operacional pode tomar o controle.
- **Lição para o Mo baile.** A separação **Indexer** (uma política que decide um
  nível) × **Scalers** (cada subsistema traduz o nível nos seus knobs) é
  exatamente a arquitetura recomendada na seção 6:
  - política no motor;
  - "scalers" no espelho, na hierarquia, no proxy, no vidro e na animação.
- **Fontes:**
  - [Adaptive Performance 5.1: visão geral](https://docs.unity3d.com/Packages/com.unity.adaptiveperformance@5.1/manual/index.html)
  - [Adaptive Performance 5.1: guia do usuário](https://docs.unity3d.com/Packages/com.unity.adaptiveperformance@5.1/manual/user-guide.html)

#### Unreal Engine: Scalability e benchmark de hardware

- **O que reduz** (Verificado):
  - **grupos de escalabilidade:** resolução (`r.ScreenPercentage`, 10 a 100),
    distância de visão, AA, pós-processamento, sombras, texturas, efeitos e
    folhagem;
  - níveis de 0 a 3 (Low, Medium, High, Epic).
- **Como decide.**
  - `UGameUserSettings::RunHardwareBenchmark` mede a velocidade relativa de CPU
    e GPU e estima os grupos pelos limiares `PerfIndexThresholds` de
    `Scalability.ini`.
  - `ApplyHardwareBenchmarkResults` aplica.
  - `SetBenchmarkFallbackValues` dá valores sensatos quando o benchmark falha ou
    pode travar.
- **Lição para o Mo baile.**
  - A detecção na primeira execução é um **micro-benchmark** que só escolhe o
    ponto de partida.
  - Precisa ter recuo seguro se falhar.
  - Deve ser separada da aplicação, para poder ser mostrada e confirmada.
- **Fontes:**
  - [Scalability Reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-reference-for-unreal-engine)
  - [RunHardwareBenchmark](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UGameUserSettings/RunHardwareBenchmark)
  - [Lyra: Scalability and Device Profiles](https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-and-device-profiles-in-lyra-sample-game-for-unreal-engine)

#### Figma: limite de memória por arquivo

- **O que é.** Limite de cerca de 2 GB de memória ativa por aba (Verificado).
- **Como decide.** Pelo consumo medido.
  - O alerta aparece a **90%** do limite, como bloco vermelho que não se dispensa
    na barra lateral.
  - A 100%, o arquivo trava, e quem edita entra em **modo de recuperação** para
    reduzir.
  - Um artigo mais antigo fala em 60%, 75% e 100% (conflito de fontes; vale o
    mais recente).
- **O que sugere.** Tirar camadas ocultas, quebrar bibliotecas e reduzir
  imagens. O checklist sugere desligar cursores multiplayer, guias de layout e
  efeitos.
- **Lição para o Mo baile.** Alerta por limiar de consumo com ações concretas. E
  um "modo de recuperação" que garante que a pessoa não perde trabalho quando o
  limite estoura. No Mo baile, o equivalente é exportar HAR e eventos antes de
  podar o histórico.
- **Fontes:**
  - [Reduce memory usage in files](https://help.figma.com/hc/en-us/articles/360040528173-Reduce-memory-usage-in-files)
  - [Troubleshooting checklist](https://help.figma.com/hc/en-us/articles/360040523973-Troubleshooting-checklist)

#### Blender e Steam Deck

- **Blender.** O painel **Simplify** tem valores separados para viewport e
  render (subdivisão máxima, partículas filhas, limite de textura), seguindo a
  ideia "preview barato, resultado fiel". A página oficial não foi lida por
  completo (Não verificado no detalhe).
  - [Manual: Simplify](https://docs.blender.org/manual/en/latest/render/cycles/render_settings/simplify.html)
- **Steam Deck** (Anedótico, guias de comunidade):
  - perfil de desempenho **por jogo** no Quick Access Menu, com limite de fps
    que acompanha a taxa de atualização (40 fps a 40 Hz), limite de TDP, Half
    Rate Shading e overlay de desempenho com fps, CPU e GPU;
  - não achei documentação oficial da Valve.
  - [Guia de comunidade](https://steamcommunity.com/sharedfiles/filedetails/?id=3570235098)
- **Lição para o Mo baile:**
  - limite de fps que divide a cadência de origem;
  - perfil que pode valer por contexto: por aparelho, já que um iPhone por
    MJPEG custa diferente de um Android por `screencap`;
  - overlay de métricas para quem quer ver.

### 3.5 Tempo real: OBS e Zoom (nicho de vídeo ao vivo)

- **OBS**:
  - O aviso "Encoding overloaded! Consider turning down video settings or using
    a faster encoding preset" aparece na interface. Pelo fórum, o gatilho é
    perder mais de 0,1% dos quadros no encoder (Anedótico).
  - A base de conhecimento oficial recomenda reduzir a resolução de saída e
    tentar 30 fps no lugar de 60 (Verificado).
  - [KB: Encoding Performance Troubleshooting](https://obsproject.com/kb/encoding-performance-troubleshooting)
  - [Fórum](https://obsproject.com/forum/threads/how-to-debug-encoding-overloaded.168625/)
- **Zoom** (Verificado via busca nos artigos oficiais):
  - o erro **"Low system resources"** aparece quando o computador não acompanha
    o processamento de áudio e vídeo;
  - as correções sugeridas são manuais: desligar o HD e ficar sem vídeo quando
    não estiver falando;
  - as estatísticas da reunião mostram a CPU do Zoom comparada com a CPU total,
    com marcadores laranja e vermelho;
  - a única adaptação automática documentada é por banda de rede.
  - [KB0083331](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0083331)
  - [KB0073097](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0073097)
  - [KB0070504](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0070504)
- **Lição para o Mo baile.**
  - O sinal certo de sobrecarga num pipeline de quadros é a **proporção de
    quadros perdidos ou atrasados**, não a CPU sozinha.
  - O Mo baile já mede `frames_skipped`, `effective_fps` e `capture_ms`. Falta
    usar esses números para decidir.
  - O texto do aviso deve dizer o que fazer ("reduzir a resolução e o fps do
    espelho"), não só que está ruim.

### 3.6 Apple: o que o macOS oferece e espera

| Sinal ou mecanismo | O que diz a Apple | Disponível | Fonte |
| --- | --- | --- | --- |
| `ProcessInfo.thermalState` (`nominal`, `fair`, `serious`, `critical`) e `thermalStateDidChangeNotification` | **fair**: ventoinha audível, hora de começar a reduzir. **serious**: reduzir CPU, GPU e I/O, baixar fps e usar efeitos de menor qualidade. **critical**: reduzir ao mínimo para responder ao usuário. É preciso ler `thermalState` antes de registrar a notificação. Sem suporte térmico, fica sempre `nominal` | macOS 10.10.3+ | [Energy Guide: Thermal State](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html), [ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum), [notificação](https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification) |
| `ProcessInfo.isLowPowerModeEnabled` e `NSProcessInfoPowerStateDidChange` | Com Low Power Mode, o sistema reduz CPU e GPU e pausa trabalho discricionário. O app deve reduzir atividade e reler a propriedade na notificação | macOS 12+ | [isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled) |
| Modos de energia do Mac | Low Power, Automatic e High Power, por "Na bateria" e "No adaptador". O padrão é Automatic. No 15.1+ também pela Central de Controle, e o Low Power reduz o ruído da ventoinha | Ventura+ | [About Power Modes](https://support.apple.com/en-us/101613) |
| Oclusão: `NSApplication.occlusionState` e `NSWindow.occlusionState`, com `windowDidChangeOcclusionState` | Quando o app ou a janela fica oculta, **parar o trabalho que não ajuda o usuário**. Ao voltar, atualizar na hora. O exemplo da Apple é o Photo Booth desligando a câmera | macOS 10.9+ | [Energy Guide: Work When Visible](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html), [occlusionState](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property) |
| App Nap | O app fica elegível quando não está em primeiro plano, não atualizou janela visível, não toca áudio e não tem asserção de energia. O sistema baixa a prioridade de CPU, espaça os timers e desacelera o I/O. **Não economiza energia por si**: o app ainda deve chegar ao ocioso. Trabalho iniciado pelo usuário evita o App Nap com asserção (`beginActivity(options: .userInitiated)`) | — | [Energy Guide: App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) |
| Classes de QoS | user-interactive, user-initiated, utility e background. Ajustam o agendamento de CPU, o I/O e a latência de timer. A Apple recomenda ficar em **utility ou abaixo em pelo menos 90% do tempo** quando o usuário não está ativo. Medir com `powermetrics --show-process-qos` | — | [Energy Guide: QoS](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheTaskLevel.html) |
| Pressão de memória: `DispatchSource.makeMemoryPressureSource` | Fonte de despacho que avisa mudança de pressão. Os eventos `.normal`, `.warning` e `.critical` e a reação (liberar cache no warning, liberar o máximo no critical) vêm de conhecimento estável e não estavam na página lida | — | [makeMemoryPressureSource](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)) |
| Reduzir transparência: `NSWorkspace.accessibilityDisplayShouldReduceTransparency` e `accessibilityDisplayOptionsDidChangeNotification` | Com a opção ligada, o app deve usar superfícies opacas | macOS 10.10+ | [accessibilityDisplayShouldReduceTransparency](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency) |
| Travamento (hang) | As ferramentas da Apple reportam travamento quando o run loop principal fica sem responder **mais de 250 ms**. Abaixo de 100 ms numa interação raramente se percebe, e a meta do caminho entrada-tela é **< 100 ms** | — | [Understanding hangs](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app) |

**Lição para o Mo baile.**

- O macOS dá de graça os três sinais de que o modo Automático precisa: calor,
  Low Power Mode e oclusão.
- A Apple diz exatamente o que fazer com cada um: baixar fps, efeitos e I/O.
- Esses sinais são o gatilho mais confiável e mais barato.
- A meta de 100 ms e o limiar de 250 ms dão a régua objetiva de "não travar".

### 3.7 Electron, Slack e Discord

- **Electron** (Verificado):
  - `powerMonitor` expõe `on-battery`, `on-ac`, `thermal-state-change` (só no
    macOS, com os mesmos estados da Apple), `speed-limit-change` (porcentagem
    abaixo de 100 indica estrangulamento térmico), `getSystemIdleState` e
    `isOnBatteryPower`.
  - `backgroundThrottling`, que vem ligado, estrangula animação e timers quando a
    janela vai para o fundo, fica minimizada ou é ocultada.
  - `app.disableHardwareAcceleration()` só funciona antes do `ready`, ou seja,
    exige reiniciar.
- **Discord e Slack.**
  - O Discord oferece desligar a "Hardware Acceleration" em Ajustes › Avançado
    (ou em Voz e Vídeo › Avançado, conforme a página), como correção de lag
    (Verificado nos guias oficiais, que divergem no caminho).
  - Um pedido de "Discord Lite" no fórum oficial mostra que a demanda existe
    (Anedótico).
  - Não verifiquei a página do Slack.
- **Lição para o Mo baile.**
  - "Desligar a aceleração de hardware" é remédio de Electron, porque o
    Chromium compõe na GPU, e não se aplica a SwiftUI e AppKit. O equivalente
    útil no Mo baile é desligar o **vidro** e as **molas**, coisa que dá para
    fazer **sem reiniciar**.
  - Os sinais do `powerMonitor` são os mesmos da Apple. Ninguém inventa sinal
    próprio.
- **Fontes:**
  - [Electron powerMonitor](https://www.electronjs.org/docs/latest/api/power-monitor)
  - [BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window)
  - [app](https://www.electronjs.org/docs/latest/api/app)
  - [Discord Troubleshooting Guide](https://support.discord.com/hc/en-us/articles/31623498041623-Discord-Troubleshooting-Guide)
  - [Discord Voice and Video Troubleshooting](https://support.discord.com/hc/en-us/articles/360045138471-Discord-Voice-and-Video-Troubleshooting-Guide)
  - [Fórum "Discord needs a LITE version"](https://support.discord.com/hc/en-us/community/posts/360033994271-Discord-needs-a-LITE-version)

---

## 4. Matriz comparativa

| Produto | O que reduz | Quem decide | Como comunica | Exceções protegidas | Lição principal |
| --- | --- | --- | --- | --- | --- |
| JetBrains Power Save | análise de fundo, autocompletar automático, animação, VCS automático | manual | ícone na barra de status | build, run, debug, busca, inspeção manual | cortar o especulativo e manter o pedido |
| JetBrains Low Memory | heap (sugere `-Xmx`) | consumo medido (5% livre) | aviso com botão e valor sugerido | — | sugerir com valor e um clique |
| VS Code | extensões, watcher | usuário, com diagnóstico | Process Explorer, Bisect | — | mostrar quem consome |
| Xcode | live issues, sugestões, Previews | manual | — | — | "ao vivo" é opcional |
| scrcpy | tamanho, bitrate, fps, região, vídeo | manual (CLI) | `--print-fps` | — | eixos independentes |
| Android Studio LI | Live Updates, Deep Inspect, snapshot | manual | botões | — | retrato como modo de primeira classe |
| Appium Inspector | releitura automática do XML | manual | botão de pausa | botão Atualizar | o piso do Leve |
| Proxyman | requisições antigas | consumo medido (memória) | ajuste em Advanced | — | teto por bytes |
| Charles | gravação | consumo medido | aviso e parada | — | avisar sempre; não parar em silêncio |
| Chrome Memory Saver | abas inativas | proativo, em 3 níveis | anel no favicon | mídia, compartilhamento, download, fixada | exceções semânticas |
| Chrome Energy Saver | fps, captura, abas de fundo | sinal do SO (bateria) | ícone com "Turn off now" | videochamada, áudio | desligar só para a sessão |
| Chrome alerts | abas | consumo medido | notificação com "Fix now" | — | detectar e sugerir |
| Safari/WebKit | timers, prioridade | sistema (App Nap) | — | — | o SO já estrangula; o app para o resto |
| Unity Adaptive Perf. | resolução, fps, LOD, sombras… | automático (térmico e gargalo) com atrasos | API | — | Indexer × Scalers; histerese por atraso |
| Unreal Scalability | grupos 0–3 | benchmark e recuo | menu | — | detecção inicial com recuo |
| Figma | — (usuário reduz) | consumo medido (90%) | bloco vermelho e modo de recuperação | o trabalho do usuário | não perder trabalho no limite |
| OBS | resolução, fps, preset | usuário, após aviso | "Encoding overloaded" | — | sinal = quadros perdidos |
| Zoom | HD, vídeo | usuário, após erro | "Low system resources" e estatísticas de CPU | áudio | aviso que diz o que fazer |
| Apple (SO) | CPU, timers, I/O de app oculto | sistema | Monitor de Atividade | asserção de atividade | parar ao ocultar; declarar o que importa |
| Electron | timers e animação no fundo; GPU | sistema e app | — | — | mesmos sinais da Apple |

---

## 5. Confronto com o código do Mo baile (3.16.0)

### 5.1 O que já existe

| Peça | Onde | Observação |
| --- | --- | --- |
| Espelho com `fps`, `max_width`, `format` e `quality` | `rpc/server.py` (`stream_start`), `PROTOCOLO_RPC.md` | O front pede fixo `fps 6.0`, `max_width 900` (`EngineSession.startStream`, linha ~856). O padrão do motor é `STREAM_FPS 3.5` e `STREAM_QUALITY 80` (`config.py`) |
| Quadro só sai quando a tela muda | `services/streaming.py` (`ScreenDiffDetector`, miniatura 32×32) | Captura na cadência pedida e descarta quadro idêntico. **A captura em si (adb `screencap` ou `simctl`) continua rodando na cadência mesmo com a tela parada**: o diff vem depois da captura |
| `stream.settled` com releitura da hierarquia debounced (150 ms) | `EngineSession.handle`, `debouncedRefreshHierarchy` | Toda tela que para gera um `hierarchy.dump`, esteja a aba visível ou não |
| Fila de quadros "o mais novo vence" no Swift | `EngineClient`: `frames` com `bufferingNewest(1)` | Bom. O lado Swift não acumula |
| Decodificação de quadro fora da main thread | `EngineSession.decodeFrameNotification` (`Task.detached`, `.userInitiated`) | Bom. O comentário registra cerca de 7 ms por quadro na main thread antes da mudança |
| Métricas no quadro | `fps`, `capture_ms` e `skipped` em `stream.frame` | Já são o sinal de sobrecarga do tipo OBS. Ninguém as usa para decidir |
| Tetos de histórico | proxy `MAX_HISTORY = 2000` e `MAX_BODY_CAPTURE = 256 KB` (`adapters/proxy.py`); analytics `MAX_HISTORY = 5000` (`adapters/analytics_logcat.py`); UI 1.000 em `trimTraffic` e 5.000 em `runLog` | Teto **por contagem**. Pior caso teórico do proxy: 2.000 × (256 KB de pedido + 256 KB de resposta), da ordem de 1 GB em `str` Python, mais a cópia na UI. Inferido, não medido |
| Detecção de aparelho por polling | `services/devices.py`, `POLL_INTERVAL 1.5 s` | Barato, mas contínuo |
| Vidro decidido por função pura | `Glass.swift`, `GlassSurface.resolve(role, glassAvailable, reduceTransparency, interactive)` | Já tem o recuo para material e sólido. Falta a entrada "perfil" |
| Molas com recuo para Reduzir movimento | `DesignTokens.swift` (`Motion.smooth`, `Motion.snappy`) | Falta a entrada "perfil" |
| "Iniciar o espelho automaticamente" | Ajustes › Geral (`state.autoStartStream`) | Já é um knob manual de modo leve |
| scrcpy | `EngineSession.startScrcpy`: `fps 60`, `max_size 1080` fixos | Deve vir do perfil |
| Bancadas | `tools/bench_frame.py`, `tools/bench_report.py` | Base para o guarda de regressão |

### 5.2 O que falta

- **Nenhum sinal do macOS é lido.** Um `grep` em `apps/MoBaile/Sources` não acha
  `thermalState`, `isLowPowerModeEnabled`, `occlusionState`,
  `makeMemoryPressureSource` nem `beginActivity`. Com a janela coberta pelo
  PyCharm, o motor continua capturando a 6 fps, e o Swift continua decodificando
  quadros que ninguém vê. É exatamente o caso que a Apple pede para evitar.
- **O motor não mede o próprio consumo.** Não há CPU nem RSS do motor e dos
  filhos.
- **O motor bloqueia em vez de descartar quando o stdout enche.** `notify` grava
  sob `_write_lock`. Um quadro de centenas de KB em base64 (416 KB por linha com
  PNG, medição M7 do estudo anterior; com JPEG é menor, não medido aqui) segura o
  lock enquanto o pipe esvazia.
  - Resultado: respostas de RPC, `proxy.event` e `analytics.event` esperam atrás
    do quadro (bloqueio na cabeça da fila).
  - A thread do espelho fica presa na escrita. Isso limita a cadência na marra,
    mas também atrasa a próxima captura de forma imprevisível.
  - Inferido pela leitura de `rpc/server.py`. É o F1 de
    `docs/MELHORIAS_2026-10-09.md`.
- **O processo do motor não tem QoS definido.** `EngineClient` cria o `Process()`
  sem `qualityOfService` (Inferido pela leitura; não há atribuição no arquivo).
- **Não existe o conceito de perfil nem uma superfície que o mostre.**

### 5.3 Custo de máquina (contexto)

- O motor roda em Python do sistema ou do Homebrew. Num Mac Apple silicon com o
  Homebrew Intel antigo em `/usr/local`, o Python pode estar rodando **sob
  Rosetta**, o que é mais lento (Inferido).
- A detecção da primeira execução deve olhar `sysctl.proc_translated` no próprio
  motor e avisar no Ambiente.
- A máquina usada nesta pesquisa é um Mac16,8 (M4 Pro) com 24 GB. **Não
  representa** M1 com 8 GB nem Intel. Todo número de orçamento abaixo é
  Suposição até ser medido nessas máquinas.

---

## 6. Arquitetura proposta: perfis de desempenho

### 6.1 Princípios

1. **Leve reduz apresentação e cadência, nunca captura.** Eventos de analytics,
   eventos de rede, passos gravados e logs de automação não são descartados por
   causa do perfil. O que muda é quanto do passado fica em memória (com
   exportação antes de podar) e quanto de "ao vivo" se mostra.
2. **O que o usuário pediu não piora.** Clique em capturar, ler hierarquia,
   rodar flow ou auditar roda com a mesma prioridade em qualquer perfil, como o
   Power Save mantém build e debug.
3. **Uma política, vários atuadores** (Indexer × Scalers da Unity). Uma função
   decide o nível, e cada subsistema traduz o nível nos seus knobs.
4. **Piorar rápido, melhorar devagar**, com permanência mínima. Sem
   oscilação.
5. **O manual ganha sempre.** O Automático nunca contraria uma escolha explícita.
   No máximo, sugere.
6. **Sem telemetria.** Toda métrica fica local (regra do projeto em
   `CONTEXTO_DO_PROJETO.md`).

### 6.2 Perfis

| Perfil | Para quem | Ideia |
| --- | --- | --- |
| **Completo** | Mac forte na tomada | tudo ao vivo e na qualidade de hoje (ou acima) |
| **Equilibrado** | padrão do Automático em máquina média, na bateria ou com `thermalState == fair` | ao vivo, com cadência e resolução menores |
| **Leve** | M1 com 8 GB, Intel antigo, Low Power Mode, `serious` ou `critical`, ou sobrecarga medida | espelho a baixa cadência, hierarquia por retrato, sem vidro nem molas, histórico curto |
| **Automático** (a preferência, não um perfil) | padrão de instalação | escolhe entre os três pelas regras de 6.4 |

### 6.3 Knobs por perfil

Os valores são **Suposição** de partida, a calibrar com a bancada de 6.8 em M1
com 8 GB e num Intel.

| Knob | Onde mora | Completo | Equilibrado | Leve |
| --- | --- | --- | --- | --- |
| Espelho: fps pedido | motor (`stream.start`) | 6 (hoje); 10 se a bancada aprovar | 4 | 1,5 |
| Espelho: `max_width` | motor | 900 | 720 | 540 |
| Espelho: qualidade JPEG | motor | 80 | 70 | 60 |
| Espelho com a janela oculta | Swift (sinal) → motor (`stream.pause`) | pausa (fica parado) | pausa | pausa |
| Espelho, exceção | — | gravação e automação mantêm o espelho, a 2 fps, com a janela oculta | idem | idem |
| Espelho iOS por MJPEG do WDA | motor | `mjpegScalingFactor` pelo `max_width` (já existe) | idem | idem |
| scrcpy | motor (`scrcpy.start`) | 60 fps, 1080 | 30 fps, 1024, `--video-bit-rate 4M` | 30 fps, 720, 2M |
| Hierarquia em `stream.settled` | Swift | automática | automática só com a aba de hierarquia ou o inspector visível | retrato: só por clique ou ao entrar na aba |
| Detecção de aparelho (`poll_interval`) | motor | 1,5 s | 3 s | 5 s |
| Proxy: histórico retido | motor | 2.000 itens / 256 MB | 1.000 / 128 MB | 300 / 48 MB |
| Proxy: corpo capturado por mensagem | motor | 256 KB | 128 KB | 32 KB (o restante marcado como truncado, com o tamanho total) |
| Analytics: histórico retido | motor | 5.000 | 3.000 | 1.500 (eventos fora da janela vão para arquivo de sessão; a auditoria lê dali) |
| Tabelas da UI (rede e analytics) | Swift | 1.000 | 600 | 300 |
| Vidro próprio (`GlassSurface.resolve`) | Swift | vidro | vidro | material ou sólido (como Reduzir transparência) |
| Molas (`Motion`) | Swift | molas | molas | crossfade curto (como Reduzir movimento) |
| Busca em tudo | Swift | ao digitar, com debounce de 150 ms | idem | com debounce de 300 ms; corpos só com Enter |
| Trabalho de fundo do motor (auditoria, OCR, export) | motor | utility | utility | background, salvo quando o usuário espera o resultado |

O Leve **não** mexe em:

- toque repassado;
- gravação de passo;
- `flow.run` e as esperas do SYNC-1 a SYNC-6;
- escuta de analytics e de rede (a captura);
- auditoria pedida (só a prioridade relativa);
- export.

### 6.4 Quem decide

Três entradas, nesta ordem de precedência:

1. **Escolha manual** (Ajustes › Desempenho: Automático | Completo | Equilibrado
   | Leve).
   - Fixar um perfil desliga as transições automáticas.
   - Duas exceções continuam valendo em qualquer perfil, porque são do sistema e
     a Apple pede: a pausa com a janela oculta e o `thermalState == critical`.
   - Com Completo fixado e sobrecarga medida, o app **sugere** (ver 6.7) e não
     troca sozinho.
2. **Sinais do sistema operacional** (Automático):

   | Sinal | Ação |
   | --- | --- |
   | `thermalState == critical` | Leve imediato, mesmo com perfil fixado. Aviso no badge |
   | `thermalState == serious` | Leve |
   | `thermalState == fair` | no máximo Equilibrado |
   | `isLowPowerModeEnabled` | no máximo Equilibrado (Leve, se a detecção inicial já indicou máquina fraca) |
   | Na bateria (sem Low Power) | sem efeito por padrão; opção "Economizar na bateria", à la Energy Saver. Ler a fonte de energia exige IOKit (`IOPSCopyPowerSourcesInfo`), o que é Inferido e não foi conferido nesta pesquisa |
   | Pressão de memória `warning` | podar histórico ao teto do Equilibrado e liberar caches de imagem |
   | Pressão de memória `critical` | teto do Leve e sugestão de exportar a sessão |
   | Janela oculta (`occlusionState` sem `.visible`) | pausa do espelho e da releitura de hierarquia; não muda o perfil |
   | Reduzir transparência ou movimento | só os knobs visuais, como já acontece |

3. **Consumo medido** (Automático), com janela deslizante:
   - **motor:** CPU do processo e dos filhos (`resource.getrusage` para
     `RUSAGE_SELF` e `RUSAGE_CHILDREN`, em delta por segundo), RSS, e proporção
     de quadros atrasados (`capture_ms` maior que o intervalo pedido ou
     `effective_fps` abaixo de 70% do pedido);
   - **front:** travamentos da main thread (sentinela que agenda um ping a cada
     100 ms e conta atrasos acima de 250 ms, a régua da Apple) e tempo de
     decodificação de quadro.
   - Limiares de partida (Suposição): CPU do motor e filhos acima de 150% de um
     núcleo por 15 s, **ou** mais de 2 travamentos acima de 250 ms em 30 s,
     **ou** quadros atrasados acima de 30% por 15 s.
4. **Detecção na primeira execução** (só define o teto inicial do Automático):
   - Lida pelo motor: `hw.memsize`, arquitetura (`uname -m` e
     `sysctl.proc_translated`), número de núcleos (`os.cpu_count()`) e versão do
     macOS (abaixo de 26 já não há vidro).
   - Regra de partida (Suposição):

     | Máquina | Ponto de partida |
     | --- | --- |
     | Intel, ou até 8 GB | Equilibrado, com Leve sugerido no primeiro aviso |
     | Python sob Rosetta | aviso no Ambiente ("o Python do Mo baile está rodando traduzido; instale o Python nativo") |
     | Demais | Completo |

   - Opcional: um micro-benchmark de cerca de 2 s no motor (redimensionar e
     codificar 20 quadros sintéticos com o mesmo código do espelho), no espírito
     do `RunHardwareBenchmark` da Unreal.
     - Tem valores de recuo se falhar.
     - O resultado é mostrado no Ambiente, não aplicado em silêncio.

**Histerese** (Suposição de partida, no modelo dos "Action Delay" da Unity):

- **Piorar:** o sinal do sistema age na hora. O consumo medido age depois de 15 s
  sustentados.
- **Melhorar:** só depois de 60 s com todos os sinais abaixo de **80% do limiar**
  de piora. Sobe um degrau por vez (Leve, depois Equilibrado, depois Completo).
- **Permanência mínima** de 30 s em cada perfil.
- No máximo 4 trocas automáticas por 10 minutos. Passou disso, o app trava no
  perfil mais leve da janela e registra o fato no diagnóstico.

### 6.5 Onde mora o governador

**Recomendação: política no motor; sensores e atuadores visuais no Swift.**

```
Swift (sensores)                       motor (política)                      atuadores
─────────────────                      ────────────────                      ─────────
thermalState, Low Power,  ──perf.signals──▶  PerfGovernor.resolve(            ─▶ motor: espelho, scrcpy,
occlusion, mem pressure,     (notificação     sinais, medições do motor,          poll, histórico, QoS
hangs da main thread,         do front ou      preferência, estado anterior)
tempo de decodificação        request)              │
preferência do usuário                                └──perf.profile (notificação)──▶ Swift: vidro, molas,
                                                                                  hierarquia, busca, badge
```

- **Por quê no motor.** A regra de `ARQUITETURA.md` é "lógica nova vai para o
  motor" e "a mesma regra em Python e em Swift é defeito". A decisão de perfil é
  regra de produto, e precisa valer para o app Tk e para uma futura CLI.
  - A função `resolve` é pura, como a `GlassSurface.resolve`, e testável com
    tabela no pytest.
  - A resposta entra nas fixtures do contrato.
- **O que fica no Swift.** É comportamento genuinamente de interface:
  - ler os sinais do AppKit e do Foundation, que o Python não vê sem PyObjC;
  - aplicar vidro e animação;
  - decidir quando reler a hierarquia conforme a aba visível;
  - desenhar o badge.
- **Contrato RPC novo** (aditivo, `PROTOCOL_VERSION` continua 2):
  - `perf.signals`: o front informa os sinais quando mudam. É barato e raro,
    porque térmico, energia e oclusão mudam pouco. Os hangs vão agregados a cada
    10 s.
  - `perf.set_preference`: `auto | completo | equilibrado | leve`, persistida no
    motor.
  - `perf.status`: perfil efetivo, motivo (`thermal_serious`, `low_power`,
    `cpu_motor`, `manual`…), knobs efetivos e métricas recentes. Alimenta o
    popover do badge e o Ambiente.
  - Notificação `perf.profile`, emitida em toda troca: `{profile, reason,
    knobs}`.
  - `stream.pause` e `stream.resume` (ou `stream.start` com `paused`). O
    `RealTimeStreamEngine` já tem `pause()` e `resume()`.
- **Recuo de segurança no Swift.** Se o motor não responder ao `perf.signals` em
  2 s, ou se o próprio motor for a causa da sobrecarga, o Swift aplica sozinho
  os knobs **visuais** do Leve e para de decodificar quadros acima de 2 por
  segundo.
  - É um freio de mão local, sem duplicar a política: o Swift só sabe "motor não
    responde, então estou em Leve visual".
- **Alternativa considerada: governador inteiro no Swift.** Reage mais rápido a
  sinais do SO. Mas duplicaria a regra para o Tk, deixaria a política fora das
  fixtures e contraria o ADR 0001. Rejeitada.

### 6.6 Como não travar

1. **Main thread só desenha.** Já vale para os quadros. Estender a regra:
   - filtro da busca em tudo e cálculo de diff de tabelas fora do MainActor
     (F2 de `MELHORIAS_2026-10-09.md`);
   - nunca `await` de RPC dentro de um handler que segura o laço de
     notificações. O comentário em `handle` já registra esse erro antigo com
     `stream.stats`.
2. **Quadro descartado, não enfileirado, também no motor.**
   - Trocar a escrita síncrona do quadro por um **slot único**: a thread do
     espelho deixa o quadro mais novo num slot, e uma thread escritora o envia.
   - Se chegar um quadro novo antes de o anterior sair, o anterior é
     descartado, e `skipped` conta isso.
   - Respostas e eventos de rede e analytics passam por uma fila de
     **prioridade maior** que a do quadro, para nunca ficarem atrás de 400 KB de
     base64.
   - O passo seguinte é o canal de quadros separado (estudo anterior, lição 4).
3. **Não capturar o que ninguém vai ver.**
   - Pausa do espelho com a janela oculta (Apple: Work When Visible).
   - No Leve e no Equilibrado, a cadência de captura cai quando a tela está
     parada há mais de alguns segundos ("modo ocioso" com fps menor). O diff
     hoje vem depois da captura, então a captura em si continua custando.
4. **Single-flight na hierarquia.** No máximo um `hierarchy.dump` em voo. Os
   pedidos que chegarem nesse meio-tempo se fundem num só, a ser executado no
   fim. O debounce de 150 ms já existe; falta a garantia de um só em voo.
   Inferido: não conferi se o `hierarchyRequestGeneration` impede a chamada ou
   só descarta o resultado. Pelo código, só descarta.
5. **QoS e App Nap.**
   - Trabalho de fundo do motor (auditoria grande, OCR, export) em thread de
     prioridade baixa. No macOS, `os.setpriority` ou `taskpolicy`; o efeito
     sobre a QoS do macOS não foi verificado.
   - Opcional: `Process.qualityOfService` do motor em `.userInitiated`.
   - Durante **gravação de flow e `flow.run`**, o Swift abre
     `beginActivity(options: .userInitiated)`. Assim o App Nap não estrangula a
     automação enquanto a pessoa está no PyCharm.
     - Fecha a atividade quando o flow termina.
     - Fora disso, deixa o App Nap agir.
   - O App Nap só se aplica a processos filhos via o pai? Não verificado. Medir
     com `powermetrics --show-process-qos`.
6. **Orçamento de memória por bytes.**
   - O histórico do proxy passa a ter teto em bytes, além da contagem.
   - Corpos acima de um limite vão para arquivo temporário da sessão, como o
     Charles e o Proxyman no Windows fazem.
   - A UI guarda só um resumo por linha e busca o corpo sob demanda.

### 6.7 Como mostrar ao usuário

Segue a voz do design system: status em minúsculas e mono, botão no infinitivo,
erro que diz o que fazer, sem emoji.

- **Badge na barra de status** (22 pt, já existe a barra):
  - texto mono `leve` ou `equilibrado`;
  - nada no Completo, para não poluir;
  - com motivo automático, um ponto de cor de aviso.
  - Tooltip: "modo leve: Mac quente" ou "modo leve: Economia de Energia ligada".
- **Popover do badge:**
  - perfil efetivo e motivo;
  - três números (CPU do motor, memória do motor, fps do espelho);
  - os knobs que estão reduzidos;
  - **"Usar Completo nesta Sessão"**, o "Turn off now" do Chrome;
  - link para Ajustes › Desempenho.
- **Sugestão** (para o Completo fixado com sobrecarga, ou na primeira vez que o
  Automático cair para Leve):
  - Faixa discreta no topo do workspace, no estilo do `EngineStatusBanner`:
    "O Mo baile está pesando no Mac (motor em 180% de CPU há 20 s). Ativar o
    modo leve?"
  - Botões: **Ativar Modo Leve**, **Agora Não** e "Não perguntar de novo".
  - No máximo uma vez por sessão. "Agora Não" silencia por 30 minutos.
- **Ajustes › Desempenho:**
  - segmentado Automático | Completo | Equilibrado | Leve;
  - abaixo, a tabela dos knobs efetivos;
  - opção "Economizar na bateria";
  - o resultado da detecção da primeira execução.
- **Ambiente (⌘5):**
  - seção "Desempenho" com o "Process Explorer" do Mo baile: CPU e memória do
    motor e dos filhos (adb, scrcpy, iproxy, logcat, Maestro);
  - aviso de Python sob Rosetta.
- **Acessibilidade.** Com Reduzir transparência ou movimento, os knobs visuais
  já ficam no recuo, e o badge não aparece só por isso.

### 6.8 Métricas e guardas de regressão

Seguindo a skill `performance-engineering` (baseline próprio, mediana de 3 a 5
execuções, ausência não é zero, gates determinísticos primeiro):

1. **Determinísticos, no `make check`:**
   - teste de tabela da função `PerfGovernor.resolve`: todas as combinações de
     sinal, histerese, permanência mínima e limite de trocas, com relógio falso;
   - teste de contrato de `perf.*` com as fixtures;
   - teste de que nenhum perfil altera a captura: com o perfil Leve,
     `analytics.event` e `proxy.event` saem todos (contagem de entrada igual à
     de saída);
   - teste de que o histórico respeita o teto em bytes;
   - teste do slot único: com o escritor bloqueado, a thread do espelho nunca
     bloqueia e `skipped` cresce.
2. **Bancada, local e no CI macOS, como aviso:**
   - `tools/bench_frame.py` estendido com os três perfis. Mede capturar,
     codificar e serializar por quadro e bytes por quadro, em mediana de 5.
     Regride se piorar mais de 20% contra o baseline commitado (Suposição,
     limiar do autor do gstack citado na skill).
   - `XCTMetric` (Q5 de `MELHORIAS_2026-10-09.md`): decodificar um quadro,
     filtrar 1.000 requisições e trocar de perfil sem travamento acima de
     100 ms.
3. **Orçamentos por perfil**, medidos em M1 com 8 GB e num Intel antes de
   fechar. Valores de partida (Suposição):

   | Métrica, espelho ligado e tela parada por 60 s | Completo | Equilibrado | Leve |
   | --- | --- | --- | --- |
   | CPU do motor e dos filhos (média) | ≤ 60% | ≤ 35% | ≤ 15% |
   | CPU do app Swift (média) | ≤ 20% | ≤ 12% | ≤ 6% |
   | RSS do motor após 30 min de proxy | ≤ 600 MB | ≤ 350 MB | ≤ 200 MB |
   | Travamentos acima de 250 ms na main thread | 0 | 0 | 0 |
   | Janela oculta: CPU do motor | ≤ 3% | ≤ 3% | ≤ 3% |

4. **Campo, só local:** `perf.status` guarda os últimos 15 minutos de métricas
   em memória. "Copiar Diagnóstico", no popover do badge, junta isso ao relato de
   bug. Nada sai da máquina.

---

## 7. Lições para o Mo baile (opinião)

- O pedido do dono ("consumir o PC, mas com uma opção amigável sem travar") é o
  que Chrome, JetBrains e Unity fazem. Nenhum deles trata o modo leve como
  "outro produto". É **o mesmo produto, com cadência e retenção menores**.
- Um "Mo baile Lite" separado seria duplicação, e a regra do projeto proíbe.
- O ganho mais barato e mais visível não é o modo Leve, é **parar de trabalhar
  com a janela oculta**.
  - O público do Mo baile alterna o tempo todo entre o app e o PyCharm.
  - Hoje o motor captura a tela do aparelho a 6 fps durante todo esse tempo, e o
    Swift decodifica cada quadro.
- O segundo ganho é estrutural: **o quadro não pode segurar o canal**. O
  bloqueio na cabeça da fila do `_write_lock` é o que transforma "o Mac está
  pesado" em "o clique demorou".
  - O slot único resolve sem esperar pelo canal de quadros separado.
- O vidro do macOS 26 é bonito e custa composição de GPU.
  - Ligar o Leve à mesma rota de recuo da acessibilidade (Reduzir transparência
    e movimento) não cria código novo de visual. Só acrescenta uma entrada a duas
    funções puras que já existem.
  - Num Intel com GPU integrada, é provável que a diferença apareça (Inferido,
    não medido).
- A detecção de hardware é útil para escolher o ponto de partida. Não é o
  mecanismo principal: o mesmo M1 com 8 GB está ótimo sozinho e sofre com o
  Android Studio e o emulador abertos.
  - Sinais do SO e consumo medido cobrem os dois casos. A detecção cobre só o
    primeiro.

---

## 8. Recomendações

Esforço: P (até 1 dia), M (2 a 5 dias), G (mais de 1 semana).

### Fortes

| # | Recomendação | Problema que resolve | Evidência | Esforço | Risco | Pronto quando |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | **Pausar espelho e releitura de hierarquia com a janela oculta** (`NSWindow.occlusionState`), exceto durante gravação e `flow.run` | O motor captura e o Swift decodifica quadros que ninguém vê enquanto o usuário está no IDE | Apple: Work When Visible e App Nap; Electron `backgroundThrottling` | P | Baixo. Risco de o espelho voltar congelado: ao ficar visível, pedir `screen.capture` na hora | Com a janela coberta por 60 s, a CPU do motor fica ≤ 3% e não sai `stream.frame`. Ao voltar, há quadro novo em ≤ 500 ms. Teste de unidade do Swift com notificação simulada |
| F2 | **Obedecer `thermalState` e Low Power Mode** (sinais em 6.4) | O Mac esquenta ou está em economia, e o app continua no máximo | Apple: Thermal State e `isLowPowerModeEnabled`; Chrome Energy Saver | P (sinal) + M (com F3) | Baixo | Com `thermalState` simulado em `serious`, o perfil vai a Leve em ≤ 1 s e o badge mostra o motivo. Em `nominal` por 60 s, volta um degrau |
| F3 | **Governador com política pura no motor** (`PerfGovernor.resolve`), contrato `perf.*`, histerese e permanência mínima | Sem um lugar único, cada knob reagiria por conta própria e oscilaria | Unity Indexer × Scalers e Action Delay; ADR 0001 | M | Médio: oscilação com limiares mal calibrados (mitigada pelo limite de trocas) | Testes de tabela cobrindo todas as transições; fixtures regeneradas; `PROTOCOLO_RPC.md` atualizado |
| F4 | **Slot único de quadro e prioridade de escrita no motor** | O quadro grande segura `_write_lock`, e respostas e eventos esperam: "o clique demorou" | OBS (quadro perdido em vez de atraso); estudo anterior, lição 2; F1 de MELHORIAS | M | Médio: concorrência na escrita do stdout (manter um único escritor) | Teste: com o escritor bloqueado, a thread do espelho não bloqueia e uma resposta de RPC sai antes do próximo quadro. Bancada sem regressão |
| F5 | **Invariante "Leve não perde captura"** | Modo leve que perde evento destrói a confiança no relatório de tagueamento | Chrome (exceções de videochamada); JetBrains (mantém build e debug); Figma (não perde trabalho) | P | Baixo | Teste de contagem: N eventos de entrada, N eventos de saída, em todos os perfis. Poda do histórico só depois de gravar em arquivo de sessão |
| F6 | **Badge, popover e Ajustes › Desempenho** com o manual acima do automático | O usuário não sabe por que o espelho ficou mais lento | JetBrains (ícone), Chrome (ícone e "Turn off now"), Steam Deck (perfil visível) | M | Baixo | Captura no catálogo `docs/design/telas` em claro e escuro. Teste de acessibilidade do badge (rótulo e tooltip). "Usar Completo nesta Sessão" funciona |
| F7 | **Teto de memória do proxy e do analytics por bytes**, corpo grande em disco, UI guardando só resumo | Pior caso teórico de ~1 GB no proxy (2.000 × 512 KB) mais a cópia na UI, num M1 com 8 GB | Proxyman (remove antigos acima de um limite de memória; corpos em disco); Charles (avisa, limita o tamanho) | M | Médio: a busca em corpo passa a ler do disco | Teste com 3.000 respostas de 256 KB: RSS do motor abaixo do teto do perfil; busca encontra corpo podado da memória |
| F8 | **Métricas locais e guarda de regressão** (CPU e RSS do motor, travamentos da main thread, quadros atrasados; bancada por perfil com baseline e mediana de 5) | Sem número, "ficou mais leve" é opinião, e regressão passa | Apple (250 ms, < 100 ms); skill `performance-engineering` (baseline próprio, mediana) | M | Baixo; ruído no CI (usar como aviso) | `perf.status` traz as métricas. `bench_frame.py --perfil` grava o baseline. O CI avisa acima de 20% |

### Opcionais

| # | Recomendação | Por quê opcional | Esforço |
| --- | --- | --- | --- |
| O1 | Detecção de hardware e micro-benchmark na primeira execução, com recuo | Os sinais e o consumo já cobrem; só melhora o ponto de partida | P (hardware) + M (benchmark) |
| O2 | Aviso de Python sob Rosetta no Ambiente | Ganho alto em poucos Macs; depende de como o Python é achado | P |
| O3 | Cadência ociosa: o motor baixa o fps de captura quando a tela está parada há N segundos | Bom ganho, mas mexe na latência do primeiro quadro após uma mudança | P |
| O4 | Hierarquia "retrato" no Leve (só por clique ou ao entrar na aba) | Muda um hábito do produto; validar com o dono | P |
| O5 | Pressão de memória (`makeMemoryPressureSource`) no Swift e no motor | Sinal útil, mas raro antes do F7 | P |
| O6 | `beginActivity(.userInitiated)` durante gravação e `flow.run` | Precisa medir se o App Nap realmente estrangula o laço do flow hoje (Não verificado) | P |
| O7 | Opção "Economizar na bateria" (fonte de energia via IOKit) | A Apple já tem o Low Power Mode; útil para quem não o usa | P |
| O8 | QoS do processo do motor e prioridade baixa para auditoria e OCR | Efeito no macOS não verificado para processo Python filho; medir com `powermetrics` antes | P |
| O9 | MetricKit no front (diagnóstico de hang em campo, só local) | Duplica a sentinela do F8; a disponibilidade no macOS e o formato não foram verificados aqui | M |
| O10 | Canal de quadros separado (socket ou `IOSurface`) | É a solução definitiva do transporte, mas G e já mapeada no estudo anterior | G |

### Ordem sugerida

F1 → F5 → F4 → F3 + F2 → F6 → F7 → F8, e depois os opcionais.

- F1 e F5 são pequenos e dão ganho imediato e segurança.
- F4 tira a causa de "travar".
- F3, F2 e F6 entregam o "modo leve" que o dono pediu, com motivo visível.
- F7 e F8 fecham memória e regressão.

---

## 9. Fontes

Acessadas em 03 e 04/11/2026.

**IDEs**

- JetBrains Rider, Power Save Mode: https://www.jetbrains.com/help/rider/Power_save_mode.html
- JetBrains CLion, Performance tuning tips: https://www.jetbrains.com/help/clion/performance-tuning-tips.html
- JetBrains IntelliJ, Increase the memory heap: https://www.jetbrains.com/help/idea/increasing-memory-heap.html
- Fórum JetBrains, Power Save Mode exact details (Anedótico): https://intellij-support.jetbrains.com/hc/en-us/community/posts/206356739/comments/206958045
- VS Code wiki, Performance Issues: https://github.com/microsoft/vscode/wiki/Performance-Issues
- VS Code wiki, File Watcher Issues: https://github.com/microsoft/vscode/wiki/File-Watcher-Issues
- VS Code issues #194341 e #235969: https://github.com/microsoft/vscode/issues/194341 · https://github.com/microsoft/vscode/issues/235969
- Apple Developer Forums sobre Xcode (Anedótico): https://developer.apple.com/forums/thread/651455 · https://developer.apple.com/forums/thread/728611

**Espelhamento e inspeção mobile**

- scrcpy, video.md: https://github.com/Genymobile/scrcpy/blob/master/doc/video.md
- Android Studio, Layout Inspector: https://developer.android.com/studio/debug/layout-inspector
- Appium Inspector, Header: https://appium.github.io/appium-inspector/2026.7/session-inspector/header/
- Appium Inspector, Screenshot: https://appium.github.io/appium-inspector/2024.9/session-inspector/screenshot/
- Vysor: https://www.vysor.io/

**Proxies**

- Proxyman: https://docs.proxyman.com/advanced-features/clear-session · https://proxyman.com/docs/troubleshooting/proxyman-consumes-too-much-ram-and-unresponsive · https://github.com/ProxymanApp/Proxyman/issues/2804
- Charles: https://www.charlesproxy.com/documentation/configuration/recording-settings/ · https://www.charlesproxy.com/documentation/faqs/charles-runs-out-of-memory/

**Navegadores**

- Chrome: https://developer.chrome.com/blog/memory-and-energy-saver-mode · https://support.google.com/chrome/answer/12929150?hl=en
- WebKit: https://webkit.org/blog/8970/how-web-content-can-affect-power-usage/

**Jogos e apps criativos**

- Unity Adaptive Performance 5.1: https://docs.unity3d.com/Packages/com.unity.adaptiveperformance@5.1/manual/index.html · https://docs.unity3d.com/Packages/com.unity.adaptiveperformance@5.1/manual/user-guide.html
- Unreal: https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-reference-for-unreal-engine · https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UGameUserSettings/RunHardwareBenchmark · https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-and-device-profiles-in-lyra-sample-game-for-unreal-engine
- Figma: https://help.figma.com/hc/en-us/articles/360040528173-Reduce-memory-usage-in-files · https://help.figma.com/hc/en-us/articles/360040523973-Troubleshooting-checklist
- Blender, Simplify: https://docs.blender.org/manual/en/latest/render/cycles/render_settings/simplify.html
- Steam Deck (Anedótico): https://steamcommunity.com/sharedfiles/filedetails/?id=3570235098

**Vídeo ao vivo**

- OBS: https://obsproject.com/kb/encoding-performance-troubleshooting · https://obsproject.com/forum/threads/how-to-debug-encoding-overloaded.168625/ (Anedótico)
- Zoom: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0083331 · https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0073097 · https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0070504

**Apple**

- Energy Efficiency Guide for Mac Apps:
  - Thermal State: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html
  - Work When Visible: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html
  - App Nap: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html
  - QoS: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheTaskLevel.html
- Foundation:
  - https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum
  - https://developer.apple.com/documentation/foundation/processinfo/thermalstatedidchangenotification
  - https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled
- AppKit:
  - https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.property
  - https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency
- Dispatch: https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)
- Xcode, Understanding hangs: https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app
- Apple Support, Power Modes: https://support.apple.com/en-us/101613

**Electron e Discord**

- Electron: https://www.electronjs.org/docs/latest/api/power-monitor · https://www.electronjs.org/docs/latest/api/browser-window · https://www.electronjs.org/docs/latest/api/app
- Discord: https://support.discord.com/hc/en-us/articles/31623498041623-Discord-Troubleshooting-Guide · https://support.discord.com/hc/en-us/articles/360045138471-Discord-Voice-and-Video-Troubleshooting-Guide · https://support.discord.com/hc/en-us/community/posts/360033994271-Discord-needs-a-LITE-version (Anedótico)

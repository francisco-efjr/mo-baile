# PROMPT DE DESIGN UI/UX — MOBILE ELEMENT RECORDER (macOS)

---

## 🎯 1. VISÃO GERAL E OBJETIVOS DO PRODUTO

### Quem somos e o que fazemos
O **Mobile Element Recorder** é uma ferramenta desktop de alta performance desenvolvida para engenheiros de automação de testes (QA / SDET) e desenvolvedores mobile. 

### O Problema que Resolvemos
Ferramentas tradicionais de inspeção mobile (como o Appium Inspector clássico ou UI Automator Viewer) são lentas, travadas e desconectadas da realidade:
- Demoram de 5 a 10 segundos para cada captura de tela estática.
- Não possuem espelhamento em tempo real.
- Não permitem interação direta do mouse repassando toques para o dispositivo físico/emulador.
- Têm interfaces pesadas, confusas e desatualizadas.

### A Nossa Solução (O que o nosso app entrega)
- **Espelhamento em Tempo Real:** Streaming contínuo da tela do dispositivo (iOS via WDA/MJPEG e Android via ADB / Minicap) com baixíssima latência.
- **Passagem Direta de Toques (Tap Forwarding):** Ao clicar com o mouse no espelho da tela no Mac, o clique é imediatamente convertido nas coordenadas lógicas exatas e executado no dispositivo físico ou simulador.
- **Inspetor de Hierarquia UI Dinâmico:** Leitura e estruturação da árvore de elementos de acessibilidade (XML/JSON) sem travar a transmissão de vídeo.
- **Gerador Automático de Código (Page Objects / Appium):** Ao inspecionar elementos, o código de automação limpo (Python / Robot Framework) é gerado instantaneamente no padrão da arquitetura do time.

---

## 🖥️ 2. DIRETRIZES DE DESIGN E PLATAFORMA (macOS HIG)

- **Plataforma Alvo:** macOS (otimizado para macOS Ventura, Sonoma e Sequoia, telas Retina / Liquid Retina).
- **Linguagem Visual:** Seguir rigorosamente o **Apple Human Interface Guidelines (HIG)** para aplicativos de produtividade e desenvolvimento (semelhante ao padrão de ferramentas modernas como *Xcode, Instruments, HTTP Toolkit, Raycast e Linear*).
- **Sensação do Usuário:** Profissional, rápida, minimalista, moderna, com sensação de fluidez e feedback visual instantâneo.
- **Estilo dos Cantos:** Arredondamento contínuo nativo (macOS squircle).
- **Linhas divisórias:** Bordas sutis de 1px (hairlines) com contraste refinado, sem linhas pesadas.

---

## 📐 3. RESOLUÇÃO E PROPORÇÕES DA JANELA (PADRÃO APPLE)

- **Tamanho Padrão de Abertura:** `1440 x 900 px` (Proporção canônica 16:10 do macOS, perfeitamente centralizada na tela do usuário).
- **Tamanho Mínimo da Janela:** `1100 x 720 px`.
- **Comportamento Responsivo:** Layout dividido em 3 colunas redimensionáveis com splitters suaves e capacidade de colapsar painéis laterais.
- **Splash Screen de Abertura:** 
  - A animação em vídeo (`splash_app.mp4`) deve preencher **100% da área da janela do aplicativo** (`1440 x 900 px`), sem bordas brancas ou cortes bruscos, fazendo um fade/transição fluida diretamente para o workspace do app assim que a animação conclui ou se o usuário clicar/pressionar espaço/ESC.

---

## 🎨 4. PALETA DE CORES E DESIGN TOKENS

Adotamos uma identidade Dark Mode moderna de alto contraste, inspirada nas melhores paletas de desenvolvimento (Catppuccin Macchiato/Mocha + Apple System Dark):

| Token | Hex | Aplicação / Significado |
|---|---|---|
| **Base Background** | `#1E1E2E` | Fundo principal da aplicação |
| **Surface / Mantle** | `#181825` | Painéis laterais, cards, árvore de elementos |
| **Deep Surface / Crust** | `#11111B` | Barra de título unificada, inputs de código |
| **Borders / Separators** | `#313244` | Linhas de divisão sutis (1px hairline) |
| **Primary Text** | `#CDD6F4` | Textos principais, títulos, rótulos de elementos |
| **Secondary Text** | `#A6ADC8` | Metadados, tags secundárias, dicas e atalhos |
| **Brand / Accent** | `#89B4FA` | Destaques de ação, botões primários, seleções |
| **Success / Active** | `#A6E3A1` | Status Online, dispositivo conectado, elemento selecionado |
| **Warning** | `#F9E2AF` | Alertas de sincronização, latência, reconexão |
| **Error / Offline** | `#F38BA8` | Falha de conexão, elemento não localizado |
| **iOS Identity** | `#0A84FF` | Badge e indicador de contexto iOS |
| **Android Identity** | `#34C759` | Badge e indicador de contexto Android |

### Tipografia
- **UI & Títulos:** `SF Pro Display` / `SF Pro Text` (ou inter / sistema operacional).
- **Código & Hierarquia:** `SF Mono` ou `JetBrains Mono` (com ligaduras de código, tamanho legível para seletores e atributos de coordenadas).

---

## 🏗️ 5. ESTRUTURA DOS PAINÉIS E COMPONENTES DA INTERFACE

A interface deve ser composta por 4 grandes regiões funcionais:

```
+--------------------------------------------------------------------------------------------------+
|  🔴 🟡 🟢   [🍎 iOS | 🤖 Android]   📱 Dispositivo: [ iPhone 15 Pro ▼ ]  [⚪ Live] [⚪ Tap] [⚙️] |
+--------------------------------------------------------------------------------------------------+
|        COLUNA 1 (40%)        |        COLUNA 2 (30%)        |        COLUNA 3 (30%)              |
|   ESPELHO EM TEMPO REAL      |   HIERARQUIA DE ELEMENTOS    |    GERADOR DE CÓDIGO PAGE OBJECT   |
|                              |                              |                                    |
|   +----------------------+   |  🔍 [Buscar ID, texto, xpath] |  Estratégia: [Posição / ID / Path] |
|   |                      |   |                              |  Chave: [onboarding_credito_objs]  |
|   |   Tela do Mobile     |   |  ▼ View                      |                                    |
|   |   (com overlay de    |   |    ▼ Button (id: btn_login)  |  ```python                         |
|   |    bounding box      |   |    ► Text ("Continuar")      |  def get_botao_continuar(self):    |
|   |    ao passar mouse)  |   |                              |      return self.driver.find_...   |
|   |                      |   |  --------------------------  |  ```                               |
|   +----------------------+   |  PROPRIEDADES DO ELEMENTO:   |                                    |
|                              |  • Tag: XCUIElementTypeBtn   |  [ 📋 Copiar ]  [ 💾 Salvar ]       |
|   [◀ Voltar] [⭕ Home] [🔲]   |  • Bounds: [120, 450, 200, 40] |                                    |
+--------------------------------------------------------------------------------------------------+
|  🟢 Conectado: iPhone 15 Pro | WDA: 8100 OK | Stream: 30 FPS | Latência: 18ms | Toque: (210, 480) |
+--------------------------------------------------------------------------------------------------+
```

### 1. Barra Superior Unificada (macOS Unified Toolbar)
- **Controles nativos macOS:** Botões fechar, minimizar, expandir (`traffic lights`) integrados organicamente.
- **Seletor de Plataforma:** Segmented Control elegante com ícones: `[ 🍎 iOS | 🤖 Android ]`.
- **Combo de Dispositivos:** Dropdown com status visual em tempo real (bolinha verde pulsante para conectado, indicador de simulador vs. aparelho físico via USB/Wi-Fi).
- **Toggles Rápidos com Feedback Luminoso:**
  - `Espelhamento Contínuo` (Ativado/Desativado).
  - `Repassar Toque ao Clicar` (Direct Tap Forwarding).
  - `Modo Passivo` (Escuta toques feitos no aparelho e sincroniza o código).
- **Ações:** Botão de Captura Manual / Forçar Refresh e Acesso às Configurações.

### 2. Coluna da Esquerda (Viewport / Espelho do Dispositivo - 40% largura)
- **Moldura do Device:** Apresentação elegante da tela mobile, mantendo o aspect ratio original (sem esticar ou deformar a proporção do celular).
- **Interatividade na Tela:**
  - Ao passar o mouse pela tela, desenhar um bounding box sutil destacando o componente sob o cursor.
  - Ao clicar na tela, exibir uma animação de pulso/ripple suave no ponto do clique (indicando o toque repassado ao celular).
  - Caixa de seleção destacada em verde quando um elemento for selecionado.
- **Barra de Navegação Rápida (Abaixo do espelho):**
  - Botões rápidos: `Voltar`, `Home`, `Trocar Apps`, `Girar Tela (Retrato/Paisagem)` e indicador de resolução da captura.

### 3. Coluna Central (Árvore de Hierarquia & Inspetor - 30% largura)
- **Campo de Busca Rápida:** Filtro em tempo real por `resource-id`, `accessibility-id`, `texto` ou `tipo de elemento`.
- **Tree View Dinâmica:** Exibição hierárquica em árvore com ícones específicos para cada tipo de elemento (`Button`, `Input/TextField`, `Image`, `Label/TextView`, `ScrollView`, `Container`).
- **Painel de Atributos do Elemento Selecionado:**
  - Tabela organizada com cópia em 1 clique para qualquer atributo:
    - `Tipo / ClassName`
    - `Accessibility ID / Name`
    - `Resource ID`
    - `Text / Value`
    - `Bounds (X, Y, Largura, Altura)`
    - `Flags (Clickable, Enabled, Visible, Focused)`

### 4. Coluna da Direita (Gerador de Código & Exportação - 30% largura)
- **Seletor de Estratégia de Localizador:**
  - Opções: `ID / Accessibility ID`, `XPath Relativo`, `Posição / Coordenadas Lógicas`, `Predicado iOS`.
- **Input de Chave/Page Object:** Nome do dicionário ou classe onde o seletor será registrado.
- **Editor de Código com Syntax Highlighting:**
  - Apresentação formatada do snippet de automação (Appium / Python / Robot Framework).
- **Ações Rápidas:**
  - Botão de destaque `[ 📋 Copiar Código ]`.
  - Botão `[ 💾 Salvar no Arquivo ]`.
  - Indicador de sucesso com microanimação (check verde temporário ao copiar).

### 5. Barra de Rodapé / Status Bar (Footer)
- Status dos daemons locais: WDA (WebDriverAgent para iOS na porta 8100) e ADB Server para Android.
- FPS em tempo real da transmissão.
- Posição atual do mouse em coordenadas nativas do aparelho: `X: 384, Y: 812`.
- Latência média de resposta.

---

## 🔄 6. ESTADOS DE TELA NECESSÁRIOS NO PROJETO

1. **Splash Screen (Abertura):**
   - Preenche a janela inteira de `1440 x 900 px`.
   - Executa a animação/vídeo e transiciona de forma imperceptível e sem saltos de janela para a tela principal.
2. **Estado Desconectado / Vazio (Empty State):**
   - Ilustração amigável orientando o usuário a conectar um iPhone via cabo/WDA ou dispositivo Android via USB Debugging.
   - Instruções passo a passo com link para ajuda.
3. **Estado Conectado & Inspecionando (Default State):**
   - Transmissão ativa, árvore preenchida e código pronto.
4. **Estado de Erro / Reconexão:**
   - Mensagem visual amigável com botão de "Tentar Reconectar" caso o WDA ou ADB perca o sinal.

---

## 📦 7. ENTREGÁVEIS ESPERADOS DO DESIGNER

- **Arquivo Figma (.fig) ou Protótipo navegável:**
  - Telas em resolução base de **1440 x 900 px**.
  - Guia de estilos com Design Tokens (Cores, Tipografia, Espaçamentos múltiplos de 4/8px).
  - Biblioteca de componentes reutilizáveis (botões, switches, badges, cards, nós da árvore).
  - Especificação das microinterações (hover nos elementos da tela, ripple do clique e transição do splash).

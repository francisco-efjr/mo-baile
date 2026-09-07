# Documentação para Futuros Agentes: Módulo "Visualizar HTTP" (Network Interception)

> **ATENÇÃO PARA FUTUROS AGENTES / ENGENHEIROS DE SOFTWARE:**
> 
> Este documento explica o funcionamento, a localização e a filosofia de design da funcionalidade **"visualizar http"** adicionada ao **Mobile Element Recorder**.
>
> **PRINCÍPIO DE PRESERVAÇÃO DO PROJETO:**
> Este recurso é **100% modular, desacoplado e não interfere no fluxo oficial** de gravação de tela, espelhamento com `stream_engine.py`, escuta passiva de toques com `passive_listener.py`, inspeção de elementos com `element_parser.py` ou geração de Page Objects Appium com `codegen.py`.

---

## 1. O que é e por que foi criado?

Inspirado na arquitetura do **HTTP Toolkit** (estudo completo documentado em [`estrutua_httptoolkit.md`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/estrutua_httptoolkit.md)), este módulo permite que o usuário capture, inspecione e gere testes a partir do **tráfego de rede (HTTP/HTTPS)** emitido por dispositivos móveis (Android e emuladores), sem a necessidade de ferramentas externas pesadas.

---

## 2. Onde está o ponto de entrada no sistema?

Na interface principal (`recorder/ui.py`), há um botão minimalista posicionado na barra superior direita (`top_bar`):

```python
# recorder/ui.py
self.btn_view_http = tk.Button(
    top_bar,
    text="🌐 visualizar http",
    command=self._open_http_viewer,
    ...
)
```

Ao ser clicado, ele abre a janela independente **`HTTPViewerWindow`** definida em [`recorder/http_viewer.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/http_viewer.py).

---

## 3. Mapa de Arquivos do Módulo

| Arquivo | Descrição | Impacto no Projeto Oficial |
| :--- | :--- | :--- |
| [`recorder/network_interceptor.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/network_interceptor.py) | Servidor proxy local em background (`MobileNetworkProxy`) rodando por padrão na porta `8082`. Trata requisições HTTP e túneis HTTPS `CONNECT`. Despacha eventos `NetworkEvent` para fila de threads segura (`queue.Queue`). | **Zero.** Opera como thread independente. |
| [`recorder/analytics_listener.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/analytics_listener.py) | Captura contínua em streaming de eventos de Firebase Analytics (`FA` e `FA-SVC`) via ADB logcat. Parseia Bundles de parâmetros e exporta em TSV/JSON para auditoria da skill `/tagueamento`. | **Zero.** Subprocesso isolado do ADB. |
| [`recorder/http_viewer.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/http_viewer.py) | Janela gráfica com abas duplas: **Tráfego HTTP/HTTPS** e **Tagueamento Analytics**. Controles para `adb reverse`, `setprop VERBOSE`, `adb logcat -c`, exportação TSV/JSON e filtros em tempo real. | **Zero.** Aberta apenas sob demanda. |
| [`recorder/adb_bridge.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/adb_bridge.py) | Adicionados os métodos auxiliares `setup_reverse_proxy()`, `teardown_reverse_proxy()` e `is_proxy_configured()`. | **Aditivo apenas.** Não altera nenhum método existente de gravação ou captura de tela. |
| [`recorder/ui.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/ui.py) | Inserção do botão minimalista `self.btn_view_http` no canto superior direito e do método `_open_http_viewer()`. | **Mínimo.** Não modifica a lógica de streaming ou de canvas. |
| [`tests/test_network_interceptor.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/tests/test_network_interceptor.py) | Testes unitários cobrindo o ciclo de vida do proxy, captura de requisições e geração de código. | Testes adicionais isolados. |

---

## 4. Como funciona a conexão com o Android via ADB?

1. **Túnel Reverso:** Executa `adb reverse tcp:8082 tcp:8082`. Isso permite que conexões originadas dentro do Android para `127.0.0.1:8082` cheguem ao proxy do host via cabo USB.
2. **Configuração Global:** Executa `adb shell settings put global http_proxy 127.0.0.1:8082`.
3. **Desconexão Segura:** Ao desconectar, o sistema executa `settings put global http_proxy :0` e `adb reverse --remove tcp:8082`, restaurando o estado original do aparelho.

---

## 5. Próximos Passos e Oportunidades de Evolução

Se um futuro agente ou usuário desejar unificar a gravação de tela com o tráfego de rede:
- Correlacione o `timestamp` do toque capturado pelo [`passive_listener.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/passive_listener.py) com os `NetworkEvent` registrados no mesmo intervalo de tempo.
- Adicione uma opção no [`codegen.py`](file:///Users/francisco.junior/Documents/antigravity/epic-fermi/recorder/codegen.py) para que, ao clicar em um elemento, o gerador também crie a asserção da requisição de backend correspondente.

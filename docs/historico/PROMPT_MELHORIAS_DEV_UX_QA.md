# Prompt Especialista: Melhorias de Desenvolvimento, Usabilidade (UI/UX) e Qualidade em Diferentes Níveis

> **Projeto:** Mo baile (`epic-fermi`) — Versão Base: 2.1.0 (Branch `etapa-1/motor-que-nao-trava`)  
> **Data do Diagnóstico:** 05/10/2026  
> **Especialidade:** Arquitetura de Devtools Desktop (Python/Swift), macOS HIG / Ergonomia QA, Pirâmide de Testes e Engenharia de Resiliência  
> **Status:** Pronto para Execução por Agente Especializado ou Equipe de Engenharia

---

## 🧭 Como Usar Este Documento

Este documento possui duas partes complementares:
1. **Parte 1 — Diagnóstico Técnico Detalhado do Estado Atual:** Uma análise profunda e sem rodeios de onde o Mo baile está hoje, o que foi resolvido na Etapa 1 e quais débitos críticos persistem nas frentes de Desenvolvimento, Usabilidade e Qualidade.
2. **Parte 2 — Mega-Prompt Operacional para o Agente:** O bloco de instruções formatado e autocontido pronto para ser copiado ou injetado em uma sessão de desenvolvimento (Antigravity, Claude Code, Cursor ou agente autônomo) para executar as melhorias de forma cirúrgica e orientada a testes.

---

# PARTE 1: DIAGNÓSTICO TÉCNICO DO ESTADO ATUAL

## 1.1 Panorama Geral após a Etapa 1 (`motor-que-nao-trava`)

Em 05/10/2026, a Etapa 1 do plano de evolução foi concluída com sucesso na branch `etapa-1/motor-que-nao-trava`. O motor passou de um servidor RPC síncrono e travável para uma arquitetura moderna inspirada no LSP (Language Server Protocol):

* **JSON-RPC 2.0 v2:** Implementação de aperto de mão versionado (`engine.hello`), 6 filas de despacho concorrente (`inline`, `fast`, `capture`, `services`, `query`, `environment`), cancelamento cooperativo (`$/cancelRequest`) e notificações de progresso (`$/progress`).
* **Segurança e Higiene de Dados:** Redação ativa de tokens, credenciais e cookies em URLs, query parameters, formulários e corpos JSON/HTTP; buffers de proxy delimitados com streaming em blocos de 64 KiB e teto de captura em 256 KiB; desativação garantida de propriedades de debug do Firebase no encerramento.
* **Resiliência do Front Swift:** `EngineSession` agora utiliza controle estrito de gerações (`hierarchyRequestGeneration`, `frameGeneration`, `recordingStateGeneration`) para prevenir condições de corrida em respostas assíncronas; preservação de estado da UI caso chamadas RPC falhem; 120+ testes Swift passando.
* **Harness de QA com Fake Devices (`qa/`):** 4 fluxos de ponta a ponta (sem device, iOS falso, Android falso, HTTPS com TLS real) com 119 asserções cobrindo o motor real sem exigir hardware.

---

## 1.2 Débitos e Oportunidades por Pilar

### 🛠️ Pilar 1: Desenvolvimento & Arquitetura (Engine & Código)

| Componente | Diagnóstico Atual | Impacto no Produto | Correção Necessária |
|---|---|---|---|
| `services/codegen.py` | `"matches": 1` é fixo para XPath e Posição (linhas 172 e 178). Não valida unicidade real avaliando a árvore. Gera `click_at_position(...)` inexistente para elementos de posição. | O código de automação gerado quebra na primeira execução do cliente (`AttributeError` no teste) ou usa seletores ambíguos. | 1. Avaliar a expressão de XPath e contar matches reais na árvore atual.<br>2. Eliminar `click_at_position` e padronizar com `wda/tap` e `adb input tap` encapsulados em um `BasePage` portável.<br>3. Implementar predicados iOS (`predicateString`) e `UiSelector` do Android. |
| `services/flows.py` | A execução de fluxos gravados (`execute_android_step` e `execute_ios_step`) faz replay cego por coordenadas absolutas (`x, y`) via `adb shell input tap` e WDA `/wda/tap`, ignorando completamente os localizadores calculados. | Qualquer alteração sutil de renderização, teclado na tela ou diferença de resolução entre gravação e execução faz o teste clicar no vazio. | Implementar Replay inteligente com busca de elementos por localizador, espera explícita automática (`waitForIdle`), retry com backoff e fallback graceful de coordenada apenas se configurado. |
| `web_app.py` | Script Streamlit criado recentemente que faz chamadas diretas a `subprocess.run([adb, "devices"])` contornando completamente o motor Python e o protocolo RPC. | Viola a Regra de Ouro do ADR 0001 ("Toda a lógica vive no motor"). Não suporta iOS, não herda segurança nem cancelamento. | Refatorar para que o `web_app.py` consuma o motor via JSON-RPC como cliente oficial, ou isolá-lo em `tools/experimental` com escopo restrito. |
| `services/streaming.py` / `rpc/server.py` | Cada frame do espelho ao vivo é codificado em PNG e serializado em base64 dentro de uma notificação JSON-RPC. | Sobrecarga extrema de CPU (25 ms no motor + 7 ms no MainActor do macOS por frame), limitando a taxa a 1-5 fps no Android. | Migrar o espelho para JPEG (Etapa 2.1) e preparar canal dedicado de vídeo H.264 via protocolo do scrcpy / MJPEG do WDA na porta 9100. |
| `apps/tk-legacy/` | Código de transição contendo mais de 400 cores hexadecimais literais e componentes duplicados (`FluidPillButton`, `_draw_round_rect`). | Dificuldade de manutenção paralela enquanto o front Swift amadurece para substituir o Tkinter em definitivo. | Centralizar tokens em `resources.py` e preparar a desativação planejada do Tkinter após a homologação completa do app nativo. |

---

### 🎨 Pilar 2: Usabilidade & UI/UX (macOS HIG & Ergonomia QA)

| Área / Tela | Diagnóstico Atual | Fricção de UX | Solução Proposta |
|---|---|---|---|
| `CorrelationCard.swift` | Gera código fixo com endpoint `/v2/credito/simulacao` e chama método fictício `wait_for_request`. | O usuário clica em "Gerar asserção de contrato" e recebe um mock inventado que não funciona, quebrando a confiança no app. | Conectar o clique ao histórico real de requisições (`appState.httpRequests` filtrado pelo timestamp da ação) e gerar asserção válida baseada no endpoint real capturado. |
| `FlowRunnerModal.swift` | O rodapé exibe `tempo 0.0 s` fixo. O cálculo de aprovados/falhas é simplista. | O QA não sabe quanto tempo o teste levou, nem a duração individual de cada passo durante a execução. | Implementar cronômetro real com `ContinuousClock` e exibir tempos parciais por passo na `TerminalView`. |
| `HierarchyTreeView.swift` | Árvore agora é hierárquica, mas a navegação é exclusivamente via mouse. | Engenheiros de automação acostumados com DevTools e Xcode perdem tempo clicando em nós em vez de usar setas do teclado. | Adicionar atalhos de teclado: `←` colapsa nó, `→` expande nó, `↑/↓` navega, `⌘C` copia o localizador ideal do nó selecionado, `⌘F` foca busca. |
| Operações Longas (`DiagnosticCard.swift`) | WDA pode levar até 10 minutos para compilar na 1ª vez; boot de AVD leva ~2 min. O app exibe apenas "iniciando…". | O usuário assume que o app travou e força o encerramento. | Exibir barra de progresso indeterminada com tempo decorrido ("Compilando WDA · 2m 14s decorridos"), consumindo as notificações de `$/progress`. |
| Diagnóstico de Falha de Tráfego | Se o app móvel usa SSL Pinning ou Flutter, nenhuma requisição HTTP aparece na tabela e o usuário não sabe o motivo. | Frustração ("o proxy não funciona"). | Adicionar card inteligente de diagnóstico: *"Nenhum tráfego detectado? Verifique se o app possui Certificate Pinning ou desative o modo captive portal"*. |
| Acessibilidade Geral (macOS HIG) | Elementos de controle sem VoiceOver hints detalhados; falta de feedback háptico/sonoro em ações de término de fluxo. | Baixa nota em acessibilidade e ergonomia macOS. | Auditar com Accessibility Inspector da Apple, adicionar `.accessibilityLabel` e `.accessibilityHint` ricos em todos os botões da toolbar e do dock. |

---

### 🧪 Pilar 3: Qualidade em Diferentes Níveis (Estratégia de QA)

```
        / \
       /   \        Nível 5: Segurança, Privacidade & Performance Contínua
      /     \       Nível 4: E2E & Harness sem Hardware (qa/run_all.py)
     /       \      Nível 3: Integração & Resiliência a Desconexão (Sockets, USB)
    /         \     Nível 2: Contrato RPC, Fixtures & Validação de Esquema
   /           \    Nível 1: Testes Unitários de Lógica & AST Codegen
  /_____________\
```

* **Nível 1 (Unitário):**
  * *Débito:* `services/codegen.py` não valida se todo código Python gerado passa em `ast.parse(actions_code)`.
  * *Meta:* 100% de cobertura com árvores sintéticas complexas (Android, iOS, elementos com caracteres especiais, acentos, aspas simples e duplas no texto).
* **Nível 2 (Contrato RPC & Deriva de Esquema):**
  * *Débito:* Hoje a verificação depende de rodar `tools/generate_fixtures.py` manualmente e esperar o teste Swift falhar.
  * *Meta:* Guard de CI automático que detecta discrepâncias entre `rpc/contract.py` e os modelos Swift de forma estática antes do commit.
* **Nível 3 (Integração & Resiliência):**
  * *Débito:* Falta de testes automatizados simulando desconexão física de cabo USB durante operações ativas (streaming ativo, dump de 60s em andamento, gravação de tela).
  * *Meta:* O motor deve detectar a perda do socket/dispositivo, emitir `device.changed`, encerrar workers limpos sem thread zumbi e restaurar as configurações de rede do host.
* **Nível 4 (E2E & Fake Harness):**
  * *Débito:* Os testes de `qa/` cobrem 4 fluxos básicos, mas não testam a execução de automação (`flow.run`), nem a integridade de exportação de arquivos HAR/TSV.
  * *Meta:* Criar o Fluxo 5 (`qa_fluxo5_automacao_e_exportacao.py`) exercitando gravação, replay, parada e exportação.
* **Nível 5 (Segurança & Performance):**
  * *Débito:* Streaming não possui benchmark automatizado no repositório comprovando que a taxa de quadros não causa vazamento de memória ou acúmulo de fila (Bounded Ring Buffer).
  * *Meta:* Suíte de estresse simulando 1000 frames em rajada verificando estabilidade de RSS de memória.

---

# PARTE 2: MEGA-PROMPT OPERACIONAL PARA O AGENTE

```markdown
# MEGA-PROMPT: ESPECIALISTA EM MELHORIAS DE DESENVOLVIMENTO, USABILIDADE E QUALIDADE — MO BAILE

Você é o **Engenheiro e Arquiteto Especialista Sênior** encarregado de elevar a maturidade técnica do **Mo baile** (`epic-fermi`), uma plataforma desktop de engenharia reversa, inspeção de UI, espelhamento ao vivo e geração de testes para Android e iOS.

## 🏛️ REGRAS DE OURO ARQUITETURAIS (INVIOLÁVEIS)
1. **Regra de Disciplina de Camadas (ADR 0001):** Toda a lógica de negócio, automação, geração de código, proxy e comunicação com dispositivos vive estritamente no motor Python (`engine/`). As interfaces (front SwiftUI em `apps/MoBaile/` e Tkinter em `apps/tk-legacy/`) são meras apresentações: desenham estado e transformam interações do usuário em chamadas RPC. Jamais duplique regras de negócio em Swift.
2. **Contrato Declarativo JSON-RPC 2.0:** Qualquer método novo deve ser declarado em `engine/src/mobaile/rpc/contract.py`, com lane apropriada e prazo (`timeout_s`). Sempre que mudar o contrato, execute `make fixtures` para sincronizar `engine_payloads.json` e os DTOs Swift.
3. **Sem Dados Inventados ou Fachadas:** Nenhum indicador de UI pode mentir. Se não há dispositivo, nada de visto verde. Se o tempo decorrido é medido, use relógio de verdade. Se uma chamada gera código de asserção, use o tráfego real interceptado.
4. **Resiliência e Tolerância a Falhas:** Jamais use `except Exception: pass`. Trate erros de forma tipada, registre diagnósticos no log e notifique a UI de forma contextual.
5. **Portão de Qualidade:** Nenhum trabalho está pronto sem passar no `make check` (versão, ruff, bandit e suítes de teste). Todo bug corrigido exige um teste de regressão correspondente.

---

## 🎯 ROTEIRO DE MELHORIAS (BACKLOG PRIORIZADO)

Execute as melhorias estruturadas nos quatro épicos abaixo, seguindo a ordem de prioridade e dependência:

### ÉPICO A: DESENVOLVIMENTO & CODEGEN CONFIÁVEL (P1)
**Objetivo:** Fazer com que o código gerado pelo Mo baile seja 100% executável, robusto e livre de fragilidades.

1. **Unicidade Real de Seletores em `services/codegen.py`:**
   - Elimine `"matches": 1` estático nas estratégias de XPath e Posição.
   - Implemente contador real de correspondências avaliando a árvore XML/UIElements atual. Se um `resource-id` aparecer em 3 elementos, marque `matches: 3` e refine o seletor (adicionando texto, classe ou predicado) até obter unicidade (`matches: 1`).
   - Adicione suporte a predicados nativos no iOS (`NSPredicate` / `XCUIElementTypeButton AND label == '...'`).
2. **Eliminação de Código Zumbi no Page Object:**
   - Remova a geração da chamada inexistente `click_at_position(...)`.
   - Crie uma estrutura base (`BasePage`) padrão que encapsula cliques com espera explícita (`WebDriverWait`), suporte a toques em coordenadas quando estritamente necessário e envio de texto seguro.
   - Adicione validação sintática obrigatória: todo código Python gerado pelo codegen deve passar sem erro em `ast.parse(...)`.
3. **Replay Inteligente em `services/flows.py`:**
   - Substitua o replay cego baseado em coordenadas físicas (`input tap x y`) por busca por localizador do elemento com espera ativa (`waitForIdle`).
   - Adicione mecanismo de fallback com aviso no log se apenas a coordenada estiver disponível.
   - Exponha o tempo individual de cada passo executado e emita notificações via `flow.log`.
4. **Governança do `web_app.py`:**
   - Refatore o executor Streamlit para comunicar com o motor via cliente JSON-RPC (`EngineClient`) em vez de chamar subprocessos ADB soltos, ou restrinja sua execução para um ambiente de demonstração claramente isolado em `tools/`.

---

### ÉPICO B: USABILIDADE & UI/UX MAC OS HIG (P1)
**Objetivo:** Transformar a experiência de uso do Mo baile em uma ferramenta desktop de classe mundial, com feedback honesto e alta produtividade para QAs.

1. **Correlação Real no `CorrelationCard.swift`:**
   - Elimine o endpoint fixo `/v2/credito/simulacao` e o método fictício `wait_for_request`.
   - Correlacione o último elemento tocado ou gravado com as requisições HTTP ocorridas na janela temporal da ação (`appState.httpRequests`).
   - Gere asserção real de status code, cabeçalhos ou payload da requisição selecionada.
2. **Métricas Reais no `FlowRunnerModal.swift`:**
   - Substitua a string `"tempo 0.0 s"` por cronômetro dinâmico de execução (`ContinuousClock`).
   - Exiba a duração acumulada e o status passo a passo conforme o motor emite `flow.log`.
3. **Ergonomia e Atalhos na Árvore de Hierarquia (`HierarchyTreeView.swift`):**
   - Habilite navegação completa por teclado na árvore (`↑` e `↓` para selecionar, `→` para expandir ramo, `←` para recolher ramo).
   - Implemente atalho `⌘C` sobre qualquer nó da árvore para copiar imediatamente o localizador recomendado para o clipboard do sistema com notificação toast na `StatusBar`.
   - Adicione indicador visual (opacidade reduzida ou tag `hidden`) para elementos com `visible: false` ou fora dos bounds da tela.
4. **Feedback de Operações Longas:**
   - Consuma as notificações `$/progress` do motor para exibir o status real de inicializações demoradas (como compilação do WebDriverAgent no Xcode e boot de emuladores AVD), com tempo decorrido em tempo real.
5. **Acessibilidade do Aplicativo:**
   - Assegure que todos os botões de ação possuam `.accessibilityLabel` e `.accessibilityHint` adequados para navegação via VoiceOver.

---

### ÉPICO C: QUALIDADE MULTI-NÍVEL & RESILIÊNCIA (P2)
**Objetivo:** Blindar o Mo baile contra regressões, comportamentos intermitentes e falhas de ambiente.

1. **Nível 1 (Unitário):**
   - Escreva testes unitários para o gerador de código testando 10+ variações de árvores de UI (elementos sem ID, textos repetidos, caracteres especiais, aspas escapadas).
   - Valide que todo output passa em `ast.parse`.
2. **Nível 2 (Contrato RPC):**
   - Adicione teste de integridade que valida que nenhum método em `contract.py` possui discrepância de parâmetros em relação a `server.py` e `EngineDTO.swift`.
3. **Nível 3 (Integração & Resiliência):**
   - Implemente testes simulando a desconexão abrupta de dispositivo enquanto uma gravação de tela ou streaming está em andamento. O motor deve desarmar workers graciosamente sem travar filas.
4. **Nível 4 (Harness E2E sem Device):**
   - Expanda o harness em `qa/` para incluir o Fluxo 5: teste de ponta a ponta de gravação de passos, execução de fluxo e exportação de HAR e TSV com dados sintéticos.

---

### ÉPICO D: ESPELHO RÁPIDO & PERFORMANCE (P2)
**Objetivo:** Reduzir latência e consumo de CPU no streaming da tela.

1. **Substituição de Formato (PNG para JPEG):**
   - Altere o pipeline de captura do motor para comprimir quadros em JPEG com qualidade configurável (ex: 80%), reduzindo o tamanho do payload em mais de 60% e o uso de CPU em cerca de 40%.
2. **Descarte Inteligente de Quadros (Ring Buffer Bounded):**
   - Assegure que se a interface SwiftUI estiver ocupada renderizando, quadros intermediários sejam descartados no motor antes de congestionar a fila de I/O do JSON-RPC.

---

## 📋 DEFINITION OF DONE (CRITÉRIOS DE ACEITE)
Para considerar qualquer tarefa pronta:
1. `make check` deve passar sem falhas (`version`, `lint`, `security` e suítes Python).
2. Se houve alteração no contrato RPC, `make fixtures` foi executado e versionado.
3. Se houve alteração no front nativo, `swift test` passa sem erros no pacote `apps/MoBaile`.
4. Nenhum texto ou valor estático/fictício foi introduzido nas telas do app.
5. Cada correção possui teste de regressão automatizado com comentário explicando o defeito corrigido.
```

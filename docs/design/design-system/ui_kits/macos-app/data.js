// Dados de exemplo do protótipo (conteúdo do catálogo de telas original).
window.MB_DATA = (() => {
  const nodes = [
    { id: "app", type: "W", label: "Banco Praia", depth: 0, attrs: { type: "XCUIElementTypeApplication", name: "Banco Praia", label: "Banco Praia", bounds: "[0,0][1179,2556]", enabled: "true" } },
    { id: "win", type: "W", label: "XCUIElementTypeWindow", depth: 1, attrs: { type: "XCUIElementTypeWindow", name: "", label: "", bounds: "[0,0][1179,2556]", enabled: "true" } },
    { id: "nav", type: "V", label: "Crédito pessoal", depth: 2, attrs: { type: "XCUIElementTypeNavigationBar", name: "Crédito pessoal", label: "Crédito pessoal", bounds: "[0,141][1179,317]", enabled: "true" } },
    { id: "voltar", type: "B", label: "Voltar", depth: 3, box: [6, 9, 12, 5], var: "BOTAO_VOLTAR", attrs: { type: "XCUIElementTypeButton", name: "Voltar", label: "Voltar", bounds: "[24,170][156,290]", center: "[90,230]", enabled: "true" } },
    { id: "titulo", type: "T", label: "Crédito pessoal", depth: 3, box: [30, 9, 40, 5], attrs: { type: "XCUIElementTypeStaticText", name: "Crédito pessoal", label: "Crédito pessoal", bounds: "[420,200][760,260]", enabled: "true" } },
    { id: "conteudo", type: "V", label: "conteudo", depth: 2, attrs: { type: "XCUIElementTypeOther", name: "conteudo", label: "", bounds: "[0,317][1179,2556]", enabled: "true" } },
    { id: "h1", type: "T", label: "Simule seu crédito em minutos", depth: 3, box: [8, 41, 60, 8], attrs: { type: "XCUIElementTypeStaticText", name: "Simule seu crédito em minutos", label: "Simule seu crédito em minutos", bounds: "[72,1020][860,1210]", enabled: "true" } },
    { id: "sub", type: "T", label: "Sem compromisso. A taxa aparece antes de você contratar.", depth: 3, box: [8, 50, 84, 5], attrs: { type: "XCUIElementTypeStaticText", name: "", label: "Sem compromisso. A taxa aparece antes de você contratar.", bounds: "[72,1230][1107,1330]", enabled: "true" } },
    { id: "cpf", type: "I", label: "CPF", depth: 3, box: [8, 58, 84, 6], var: "CAMPO_CPF", key: "campo_cpf", attrs: { type: "XCUIElementTypeTextField", name: "campo_cpf", label: "CPF", bounds: "[72,1480][1107,1630]", center: "[589,1555]", enabled: "true" } },
    { id: "valor", type: "I", label: "Valor desejado", depth: 3, box: [8, 67.5, 84, 6], var: "CAMPO_VALOR", key: "campo_valor", attrs: { type: "XCUIElementTypeTextField", name: "campo_valor", label: "Valor desejado", bounds: "[72,1720][1107,1870]", center: "[589,1795]", enabled: "true" } },
    { id: "continuar", type: "B", label: "Continuar", depth: 3, box: [8, 82, 84, 6], var: "BOTAO_CONTINUAR", key: "Continuar", hit: "44pt", attrs: { type: "XCUIElementTypeButton", name: "Continuar", label: "Continuar", bounds: "[72,2148][1107,2310]", center: "[589,2229]", enabled: "true" } },
    { id: "agora", type: "B", label: "Agora não", depth: 3, box: [34, 89.5, 32, 4], var: "BOTAO_AGORA_NAO", key: "Agora não", attrs: { type: "XCUIElementTypeButton", name: "Agora não", label: "Agora não", bounds: "[420,2340][760,2420]", center: "[589,2380]", enabled: "true" } }
  ];
  const steps = [
    { id: "s1", action: "click", element: "Simular crédito", varName: "BOTAO_SIMULAR_CREDITO", strategy: "id", selector: "Simular crédito", method: "click_botao_simular_credito" },
    { id: "s2", action: "send_keys", element: "campo_cpf", varName: "CAMPO_CPF", strategy: "id", selector: "campo_cpf", value: "•••••••••••", method: "preencher_campo_cpf" },
    { id: "s3", action: "send_keys", element: "campo_valor", varName: "CAMPO_VALOR", strategy: "id", selector: "campo_valor", value: "5000", method: "preencher_campo_valor" },
    { id: "s4", action: "click", element: "Continuar", varName: "BOTAO_CONTINUAR", strategy: "id", selector: "Continuar", method: "click_botao_continuar" },
    { id: "s5", action: "click", element: "Confirmar contratação", varName: "BOTAO_CONFIRMAR_CONTRATACAO", strategy: "xpath", selector: "//XCUIElementTypeButton[@name=\"Confirmar contratação\"]", method: "click_botao_confirmar_contratacao" },
    { id: "s6", action: "click", element: "position", varName: "TOQUE_FECHAR", strategy: "coords", selector: "x: 1.095, y: 210", method: "click_toque_fechar" }
  ];
  const requests = [
    { id: 1, method: "DELETE", status: null, host: "api.bancopraia.com.br", path: "/v2/credito/simulacao/sim_8f2c", size: 0, time: null },
    { id: 2, method: "GET", status: 500, host: "api.bancopraia.com.br", path: "/v2/clientes/me/preferencias", size: 18, time: 1800 },
    { id: 3, method: "POST", status: 422, host: "api.bancopraia.com.br", path: "/v2/credito/contratacao", size: 76, time: 266, resBody: "{\n  \"erro\": \"limite_excedido\",\n  \"mensagem\": \"Valor acima do limite pré-aprovado.\"\n}" },
    { id: 4, method: "GET", status: 304, host: "cdn.bancopraia.com.br", path: "/img/onboarding/credito@3x.png", size: 0, time: 41 },
    { id: 5, method: "CONNECT", status: 200, host: "app-measurement.com", path: ":443", size: 0, time: 58, tunnel: true },
    { id: 6, method: "POST", status: 200, host: "firebaselogging-pa.googleapis.com", path: "/v1/firelog/legacy/batchlog", size: 2, time: 128 },
    { id: 7, method: "POST", status: 201, host: "api.bancopraia.com.br", path: "/v2/credito/simulacao", size: 116, time: 812, resBody: "{\n  \"cet_anual\": 28.399999999999,\n  \"parcelas\": 12,\n  \"primeiro_vencimento\": \"2026-11-10\",\n  \"simulacao_id\": \"sim_8f2c\",\n  \"valor_parcela\": 487.31999999999\n}" },
    { id: 8, method: "GET", status: 200, host: "api.bancopraia.com.br", path: "/v2/credito/ofertas", size: 103, time: 342 }
  ];
  const reqHeaders = [["Accept-Language", "pt-BR"], ["Authorization", "Bearer eyJhbGciOi…"], ["Content-Type", "application/json"], ["User-Agent", "BancoPraia/5.42.0 (iPhone; iOS 18.6; Scale/3.00)"], ["X-Correlation-Id", "7c1e9f4a-2b3d-4e5f-9a8b-0c1d2e3f4a5b"]];
  const events = [
    { id: 1, time: "13:02:19.740", name: "erro_contratacao", params: { canal: "app_ios", codigo: "limite_excedido" } },
    { id: 2, time: "13:02:18.051", name: "clique_continuar", params: { tela: "simulacao", etapa: "2" } },
    { id: 3, time: "13:02:14.920", name: "simulacao_credito_iniciada", params: { canal: "app_ios", parcelas: "12", produto: "pessoal", valor: "5000" } },
    { id: 4, time: "13:02:12.340", name: "select_content", params: { content_type: "banner", item_id: "credito" } },
    { id: 5, time: "13:02:11.102", name: "screen_view", params: { firebase_previous_screen: "home", firebase_screen: "onboarding_credito", firebase_screen_class: "OnboardingCreditoViewController" } },
    { id: 6, time: "13:02:10.880", name: "session_start", params: {} }
  ];
  const log = [
    ["11:03:20", "INFO", "Sessão Appium aberta · XCUITest · iPhone 16 (iOS 18.6)"],
    ["11:03:21", "INFO", "Page Object onboarding_credito_objs carregado (5 locators)"],
    ["11:03:22", "RUN", "passo 1 · click BOTAO_SIMULAR_CREDITO"], ["11:03:23", "PASS", "passo 1 ok"],
    ["11:03:24", "RUN", "passo 2 · send_keys CAMPO_CPF"], ["11:03:24", "HTTP", "POST /v2/credito/simulacao → 201 (812 ms)"], ["11:03:25", "PASS", "passo 2 ok"],
    ["11:03:26", "RUN", "passo 3 · send_keys CAMPO_VALOR"], ["11:03:27", "PASS", "passo 3 ok"],
    ["11:03:28", "RUN", "passo 4 · click BOTAO_CONTINUAR"], ["11:03:28", "FA", "clique_continuar {tela: simulacao, etapa: 2}"], ["11:03:29", "PASS", "passo 4 ok"],
    ["11:03:30", "RUN", "passo 5 · click BOTAO_CONFIRMAR_CONTRATACAO"], ["11:03:31", "PASS", "passo 5 ok"],
    ["11:03:32", "RUN", "passo 6 · click TOQUE_FECHAR"], ["11:03:33", "PASS", "passo 6 ok"]
  ];
  const failLine = ["11:03:45", "FAIL", "NoSuchElementError: BOTAO_CONFIRMAR_CONTRATACAO não ficou visível em 15 s"];
  const devices = [
    { id: "iphone16", name: "iPhone 16", platform: "ios", detail: "Simulador · iOS 18.6" },
    { id: "iphone15", name: "iPhone 15 Pro", platform: "ios", detail: "Simulador · desligado", off: true },
    { id: "pixel7", name: "Pixel 7", platform: "android", detail: "emulator-5554" }
  ];
  return { nodes, steps, requests, reqHeaders, events, log, failLine, devices };
})();

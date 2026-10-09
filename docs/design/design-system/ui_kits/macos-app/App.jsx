// Mo baile — protótipo macOS. Estado, toolbar, layout em colunas, menus e atalhos.
const NSX = () => window.MoBaileDesignSystem_ce6669;
const D = window.MB_DATA;
const SECTION_TITLE = { pageObjects: "Page Objects", network: "Rede HTTP", analytics: "Analytics" };

function App() {
  const { Window, TrafficLights, Toolbar, ToolbarTitle, ToolbarSpacer, ToolbarButton, ToolbarGroup, ToolbarSearch, SegmentedControl, PopUpButton,
    Splitter, StatusIndicator, MenuBar, Menu, Popover, Alert, Button, Icon, Tooltip } = NSX();
  const useSpring = window.mbUseSpring;
  // Preferências (Ajustes) e painel do protótipo
  const [prefs, setPrefs] = React.useState({ appearance: "light", sidebarSize: "medium", strategy: "auto", autoStream: true, wda: "http://localhost:8100", proxyHost: "127.0.0.1", proxyPort: "8082" });
  const setPref = (k, v) => setPrefs(p => ({ ...p, [k]: v }));
  const [demo, setDemoState] = React.useState({ active: true, reduceMotion: false, reduceTransparency: false, contrast: false, scenario: "connected", outcome: "pass" });
  const setDemo = (k, v) => setDemoState(d => ({ ...d, [k]: v }));
  const [demoCollapsed, setDemoCollapsed] = React.useState(window.innerWidth < 1500);
  const sysDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  const dark = prefs.appearance === "dark" || (prefs.appearance === "system" && sysDark);
  React.useEffect(() => {
    const h = document.documentElement;
    dark ? h.setAttribute("data-theme", "dark") : h.removeAttribute("data-theme");
    demo.contrast ? h.setAttribute("data-contrast", "high") : h.removeAttribute("data-contrast");
    h.setAttribute("data-reduce-motion", demo.reduceMotion); h.setAttribute("data-reduce-transparency", demo.reduceTransparency);
    h.setAttribute("data-sidebar-size", prefs.sidebarSize);
  }, [dark, demo.contrast, demo.reduceMotion, demo.reduceTransparency, prefs.sidebarSize]);

  // Painéis
  const [sidebarOpen, setSidebarOpen] = React.useState(true);
  const [inspectorOpen, setInspectorOpen] = React.useState(true);
  const [mirrorOpen, setMirrorOpen] = React.useState(true);
  const [workspaceOpen, setWorkspaceOpen] = React.useState(true);
  const [sidebarW, setSidebarW] = React.useState(240);
  const [inspectorW, setInspectorW] = React.useState(272);
  const [mirrorW, setMirrorW] = React.useState(290);
  const [dragging, setDragging] = React.useState(false);
  const springOpts = { duration: 0.5, bounce: 0, instant: demo.reduceMotion || dragging };
  const sbW = useSpring(sidebarOpen ? sidebarW : 0, springOpts);
  const inW = useSpring(inspectorOpen ? inspectorW : 0, springOpts);
  const [win, setWin] = React.useState({ w: 1280, h: 800 });

  // Conteúdo
  const scenario = demo.scenario;
  const connected = ["connected", "loading", "error"].includes(scenario);
  const loading = scenario === "loading";
  const [section, setSectionRaw] = React.useState("pageObjects");
  const [fade, setFade] = React.useState(1);
  const setSection = s => { if (s === section) return; setFade(0); setTimeout(() => { setSectionRaw(s); setFade(1); }, 90); };
  const [selectedStep, setSelectedStep] = React.useState(null);
  const [device, setDevice] = React.useState("iphone16");
  const [mode, setMode] = React.useState("record");
  const [strategy, setStrategy] = React.useState("auto");
  const [split, setSplit] = React.useState(false);
  const [data, setData] = React.useState({ steps: D.steps, requests: D.requests, events: D.events });
  const [past, setPast] = React.useState([]); const [future, setFuture] = React.useState([]);
  const commit = (label, fn) => { setPast(p => [...p.slice(-30), { label, data }]); setFuture([]); setData(fn(data)); };
  const undo = () => { if (!past.length) return; const last = past[past.length - 1]; setFuture(f => [...f, { label: last.label, data }]); setData(last.data); setPast(p => p.slice(0, -1)); toast("Desfeito: " + last.label); };
  const redo = () => { if (!future.length) return; const n = future[future.length - 1]; setPast(p => [...p, { label: n.label, data }]); setData(n.data); setFuture(f => f.slice(0, -1)); toast("Refeito: " + n.label); };
  const [newIds, setNewIds] = React.useState([]);
  const [nodeSel, setNodeSel] = React.useState("continuar");
  const [hierQuery, setHierQuery] = React.useState("");
  const [focusPane, setFocusPane] = React.useState("content");
  const [reqSel, setReqSel] = React.useState([7]); const [evSel, setEvSel] = React.useState([3]);
  const [proxyOn, setProxyOn] = React.useState(true); const [debugOn, setDebugOn] = React.useState(false);
  const [listening, setListening] = React.useState(true); const [source, setSource] = React.useState("auto");
  const [filter, setFilter] = React.useState({ network: "", analytics: "" });
  const [searchOpen, setSearchOpen] = React.useState(false);
  const [netError, setNetError] = React.useState(null);
  const [passive, setPassive] = React.useState(false); const [screenRec, setScreenRec] = React.useState(false); const [scrcpy, setScrcpy] = React.useState(false);
  const [sheet, setSheet] = React.useState(null);
  const [alert, setAlert] = React.useState(null);
  const [settings, setSettings] = React.useState({ open: false, front: false });
  const [corrOpen, setCorrOpen] = React.useState(false);
  const corrRef = React.useRef(null); const hierSearch = React.useRef(null); const tbSearch = React.useRef(null);
  const [msg, setMsg] = React.useState(""); const msgT = React.useRef(0);
  const toast = m => { setMsg(m); clearTimeout(msgT.current); msgT.current = setTimeout(() => setMsg(""), 3200); };
  const [cursor, setCursor] = React.useState({ x: 589, y: 2229 });
  const [splash, setSplash] = React.useState(true);
  const [scan, setScan] = React.useState("10:13:35");
  React.useEffect(() => { const t = setTimeout(() => setSplash(false), 1500); return () => clearTimeout(t); }, []);
  React.useEffect(() => { if (scenario === "error") { setSectionRaw("network"); setProxyOn(false); setNetError(true); } else setNetError(null); }, [scenario]);

  const dev = D.devices.find(d => d.id === device);
  const steps = data.steps;
  const windowActive = demo.active && !settings.front;
  const effSection = connected ? section : "noDevice";
  const showMirror = connected && mirrorOpen;
  const showWork = workspaceOpen || !showMirror;

  // Ações
  const recordStep = node => {
    if (!node || !node.box) return;
    const strat = strategy === "auto" ? (node.key ? "id" : "xpath") : strategy;
    const id = "s" + Date.now();
    const isInput = node.type === "I";
    const s = { id, action: isInput ? "send_keys" : "click", element: node.key || node.label, varName: node.var || node.label.toUpperCase().replace(/\W+/g, "_"), strategy: strat,
      selector: strat === "xpath" ? "//" + node.attrs.type + "[@name=\"" + node.attrs.name + "\"]" : strat === "coords" ? "x: " + node.attrs.center : node.key || node.label,
      method: (isInput ? "preencher_" : "click_") + (node.var || node.label).toLowerCase().replace(/\W+/g, "_"), value: isInput ? "texto" : undefined };
    commit("Gravar passo", d => ({ ...d, steps: [...d.steps, s] }));
    setNewIds([id]); setTimeout(() => setNewIds([]), 700);
    toast("Passo " + (steps.length + 1) + " gravado · " + s.action + " " + s.element);
  };
  const onTap = (node, pt) => {
    setCursor({ x: Math.round(pt.px * 11.79), y: Math.round(pt.py * 25.56) });
    if (mode === "record" && section === "pageObjects") recordStep(node);
    else {
      toast("Toque enviado ao aparelho em x " + Math.round(pt.px * 11.79) + " · y " + Math.round(pt.py * 25.56));
      if (proxyOn && node && node.type === "B") {
        const id = Date.now();
        setData(d => ({ ...d, requests: [...d.requests, { id, method: "POST", status: 200, host: "api.bancopraia.com.br", path: "/v2/eventos/toque", size: 24, time: 96 }] }));
        setNewIds([id]); setTimeout(() => setNewIds([]), 700);
      }
    }
  };
  const deleteStep = id => { commit("Excluir passo", d => ({ ...d, steps: d.steps.filter(s => s.id !== id) })); if (selectedStep === id) setSelectedStep(null); toast("Passo excluído · ⌘Z para desfazer"); };
  const reorder = (a, b) => commit("Reordenar passos", d => { const s = [...d.steps]; const [x] = s.splice(a, 1); s.splice(b, 0, x); return { ...d, steps: s }; });
  const askClear = kind => setAlert(kind);
  const doClear = kind => {
    if (kind === "network") { commit("Limpar tráfego", d => ({ ...d, requests: [] })); setReqSel([]); }
    if (kind === "analytics") { commit("Limpar eventos", d => ({ ...d, events: [] })); setEvSel([]); }
    if (kind === "steps") { commit("Limpar passos", d => ({ ...d, steps: [] })); setSelectedStep(null); }
    setAlert(null); toast("Removido · ⌘Z para desfazer");
  };
  const openSearch = () => {
    if (section === "pageObjects" || !connected) { setInspectorOpen(true); setTimeout(() => hierSearch.current && hierSearch.current.focus(), 60); }
    else setSearchOpen(true);
  };
  const run = () => steps.length && connected && setSheet("runner");
  const goStep = id => { setSelectedStep(id); setSectionRaw("pageObjects"); };

  // Menus (toda ação da toolbar também aparece aqui)
  const menus = [
    { title: "Mo baile", items: [{ label: "Sobre o Mo baile" }, { separator: true }, { label: "Ajustes…", shortcut: "⌘,", onSelect: () => setSettings({ open: true, front: true }) }, { separator: true }, { label: "Ocultar Mo baile", shortcut: "⌘H" }, { label: "Sair do Mo baile", shortcut: "⌘Q" }] },
    { title: "Arquivo", items: [
      { label: "Salvar Page Object", shortcut: "⌘S", disabled: !steps.length, onSelect: () => toast("onboarding_credito_objs.py salvo") },
      { label: "Exportar HAR…", shortcut: "⇧⌘E", disabled: !data.requests.length, onSelect: () => toast("network_traffic.har exportado") },
      { label: "Exportar JSON de Analytics…", disabled: !data.events.length, onSelect: () => toast("log_obtido.json exportado") },
      { separator: true }, { label: "Fechar Janela", shortcut: "⌘W" }] },
    { title: "Editar", items: [
      { label: past.length ? "Desfazer " + past[past.length - 1].label : "Desfazer", shortcut: "⌘Z", disabled: !past.length, onSelect: undo },
      { label: future.length ? "Refazer " + future[future.length - 1].label : "Refazer", shortcut: "⇧⌘Z", disabled: !future.length, onSelect: redo },
      { separator: true }, { label: "Recortar", shortcut: "⌘X" }, { label: "Copiar", shortcut: "⌘C" }, { label: "Colar", shortcut: "⌘V" }, { label: "Selecionar Tudo", shortcut: "⌘A" },
      { separator: true }, { label: "Buscar", shortcut: "⌘F", onSelect: openSearch },
      { separator: true }, { label: "Limpar Tráfego…", disabled: !data.requests.length, onSelect: () => askClear("network") }, { label: "Limpar Eventos…", disabled: !data.events.length, onSelect: () => askClear("analytics") }] },
    { title: "Visualizar", items: [
      { label: sidebarOpen ? "Ocultar Barra Lateral" : "Mostrar Barra Lateral", shortcut: "⌃⌘S", onSelect: () => setSidebarOpen(o => !o) },
      { label: inspectorOpen ? "Ocultar Inspector" : "Mostrar Inspector", shortcut: "⌥⌘I", onSelect: () => setInspectorOpen(o => !o) },
      { label: mirrorOpen ? "Ocultar Espelho" : "Mostrar Espelho", shortcut: "⌥1", onSelect: () => setMirrorOpen(o => !o) },
      { label: workspaceOpen ? "Ocultar Workspace" : "Mostrar Workspace", shortcut: "⌥2", onSelect: () => setWorkspaceOpen(o => !o) },
      { label: "Mostrar Todos os Painéis", shortcut: "⌥⌘F", onSelect: () => { setSidebarOpen(true); setInspectorOpen(true); setMirrorOpen(true); setWorkspaceOpen(true); } },
      { label: sidebarOpen || inspectorOpen ? "Modo Zen" : "Sair do Modo Zen", shortcut: "⌃⌘Z", onSelect: () => { const z = sidebarOpen || inspectorOpen; setSidebarOpen(!z); setInspectorOpen(!z); setMirrorOpen(true); setWorkspaceOpen(true); } },
      { separator: true },
      { label: "Page Objects", shortcut: "⌘1", checked: section === "pageObjects", onSelect: () => setSection("pageObjects") },
      { label: "Rede HTTP", shortcut: "⌘2", checked: section === "network", onSelect: () => setSection("network") },
      { label: "Analytics", shortcut: "⌘3", checked: section === "analytics", onSelect: () => setSection("analytics") }] },
    { title: "Dispositivo", items: [
      { label: "Atualizar Lista", shortcut: "⇧⌘R", onSelect: () => toast("Lista de aparelhos atualizada") },
      { label: "Atualizar Tela", shortcut: "⌘K", disabled: !connected, onSelect: () => toast("Tela capturada") },
      { label: "Parar Espelho", shortcut: "⌘E", disabled: !connected },
      { separator: true },
      { label: "Repassar Toque", checked: mode === "forward", disabled: !connected, onSelect: () => setMode("forward") },
      { label: "Gravar Passo", checked: mode === "record", disabled: !connected, onSelect: () => setMode("record") },
      { separator: true },
      { label: passive ? "Parar Captura do Aparelho" : "Gravar do Aparelho", disabled: !connected, onSelect: () => setPassive(p => !p) },
      { label: screenRec ? "Parar de Gravar a Tela" : "Gravar a Tela", disabled: !connected, onSelect: () => setScreenRec(r => !r) },
      { label: "Espelho 60 FPS (scrcpy)", checked: scrcpy, disabled: !connected || dev.platform !== "android", onSelect: () => setScrcpy(s => !s) }] },
    { title: "Automação", items: [
      { label: "Estrutura do Fluxo…", disabled: !steps.length, onSelect: () => setSheet("structure") },
      { label: "Rodar Automação", shortcut: "⌘R", disabled: !steps.length || !connected, onSelect: run },
      { separator: true }, { label: "Limpar Passos…", disabled: !steps.length, destructive: true, onSelect: () => askClear("steps") }] },
    { title: "Janela", items: [{ label: "Minimizar", shortcut: "⌘M" }, { label: "Zoom" }, { separator: true }, { label: "Mostrar Splash", onSelect: () => { setSplash(true); setTimeout(() => setSplash(false), 1500); } }, { separator: true }, { label: "Mo baile", checked: !settings.front, onSelect: () => setSettings(s => ({ ...s, front: false })) }] },
    { title: "Ajuda", items: [{ label: "Ajuda do Mo baile" }, { label: "Atalhos de Teclado" }] }
  ];

  // Atalhos
  React.useEffect(() => {
    const k = e => {
      const m = e.metaKey || e.ctrlKey;
      const t = e.target; const typing = t.tagName === "INPUT" || t.tagName === "TEXTAREA";
      if (e.key === "Escape" && settings.front) { setSettings({ open: false, front: false }); return; }
      if (e.ctrlKey && e.metaKey && e.key.toLowerCase() === "s") { e.preventDefault(); setSidebarOpen(o => !o); return; }
      if (e.ctrlKey && e.metaKey && e.key.toLowerCase() === "z") { e.preventDefault(); const z = sidebarOpen || inspectorOpen; setSidebarOpen(!z); setInspectorOpen(!z); return; }
      if (e.altKey && e.metaKey && (e.code === "KeyI")) { e.preventDefault(); setInspectorOpen(o => !o); return; }
      if (e.altKey && e.metaKey && e.code === "KeyF") { e.preventDefault(); setSidebarOpen(true); setInspectorOpen(true); setMirrorOpen(true); setWorkspaceOpen(true); return; }
      if (e.altKey && !m && e.code === "Digit1") { e.preventDefault(); setMirrorOpen(o => !o); return; }
      if (e.altKey && !m && e.code === "Digit2") { e.preventDefault(); setWorkspaceOpen(o => !o); return; }
      if (!m) return;
      const key = e.key.toLowerCase();
      if (key === ",") { e.preventDefault(); setSettings({ open: true, front: true }); }
      else if (key === "f") { e.preventDefault(); openSearch(); }
      else if (key === "z" && !typing) { e.preventDefault(); e.shiftKey ? redo() : undo(); }
      else if (key === "r" && !e.shiftKey) { e.preventDefault(); run(); }
      else if (key === "k") { e.preventDefault(); connected && toast("Tela capturada"); }
      else if (key === "s") { e.preventDefault(); steps.length && toast("onboarding_credito_objs.py salvo"); }
      else if (["1", "2", "3"].includes(key)) { e.preventDefault(); setSelectedStep(null); setSection(["pageObjects", "network", "analytics"][+key - 1]); }
    };
    window.addEventListener("keydown", k); return () => window.removeEventListener("keydown", k);
  });

  // Toolbar adaptável: com pouco espaço, itens de menor prioridade vão para o menu » e o segmentado vira pop-up.
  const mainW = win.w - sbW - inW;
  const compact = mainW < 700, tight = mainW < 560;
  const [overflow, setOverflow] = React.useState(null);
  const overflowBtn = React.useRef(null);
  const recItems = [
    { label: passive ? "Parar Captura" : "Gravar do Aparelho", icon: passive ? "square" : "hand", on: passive, fn: () => setPassive(p => !p), tip: passive ? "Para de gravar os toques feitos no aparelho" : "Grava o que você fizer direto no aparelho, sem clicar no espelho" },
    { label: screenRec ? "Parar de Gravar a Tela" : "Gravar a Tela", icon: screenRec ? "square" : "video", on: screenRec, fn: () => setScreenRec(r => !r), tip: screenRec ? "Encerra a gravação e salva o vídeo" : "Grava vídeo da tela do aparelho" }
  ];
  if (dev.platform === "android") recItems.push({ label: "Espelho 60 FPS", icon: "activity", on: scrcpy, fn: () => setScrcpy(s => !s), tip: "Abrir espelho nativo a 60 FPS (scrcpy)" });
  const deviceOptions = [{ header: "iOS" }, ...D.devices.filter(d => d.platform === "ios"), { header: "Android" }, ...D.devices.filter(d => d.platform === "android")];
  const subtitle = !connected ? "Nenhum dispositivo" : effSection === "pageObjects" ? (selectedStep ? "Passo " + (steps.findIndex(s => s.id === selectedStep) + 1) + " de " + steps.length : steps.length + " passos") + " · " + dev.name
    : effSection === "network" ? data.requests.length + " requisições" : data.events.length + " eventos";
  const leftPad = Math.max(12, 116 - sbW);
  const noteKey = settings.front ? "settings" : effSection;

  const [vp, setVp] = React.useState({ w: window.innerWidth, h: window.innerHeight });
  React.useEffect(() => { const r = () => setVp({ w: window.innerWidth, h: window.innerHeight }); window.addEventListener("resize", r); return () => window.removeEventListener("resize", r); }, []);
  // Ajusta a página inteira ao painel de visualização (a janela tem 1280×800 pt de referência).
  const zoom = Math.min(1, (vp.w - 16) / (win.w + 40), (vp.h - 8) / (win.h + 60));
  React.useEffect(() => { document.documentElement.style.zoom = zoom; }, [zoom]);
  return (
    <>
      <MenuBar menus={menus} right={<span>qui 8 out  15:31</span>} />
      <div style={{ position: "relative", minHeight: win.h + 60, display: "flex", justifyContent: "center", paddingTop: 22 }}>
        <div style={{ position: "relative" }} onMouseDown={() => settings.front && setSettings(s => ({ ...s, front: false }))}>
          <Window active={windowActive} width={win.w} height={win.h} ariaLabel={SECTION_TITLE[section] || "Mo baile"}>
            <div style={{ flex: 1, display: "flex", minHeight: 0, position: "relative" }}>
              {/* Sidebar */}
              <div style={{ width: sbW, flex: "none", overflow: "hidden", position: "relative", zIndex: 2 }}>
                <div style={{ width: sidebarW, height: "100%", transform: "translateX(" + (sbW - sidebarW) + "px)" }}>
                  <AppSidebar width={sidebarW} section={section} selectedStep={selectedStep} onSection={s => { setSelectedStep(null); setSection(s); }} onStep={goStep}
                    steps={steps} counts={{ steps: steps.length, requests: data.requests.length, events: data.events.length }} onReorder={reorder} onDelete={deleteStep}
                    onRecord={() => { setMode("record"); setSection("pageObjects"); toast("Gravar passo: clique em um elemento no espelho"); }} newIds={newIds} device={dev.name} connected={connected} scanning={scenario === "checking"} sidebarSize={prefs.sidebarSize} />
                </div>
              </div>
              {sbW > 1 && <Splitter ariaLabel="Redimensionar barra lateral" onDrag={d => { setDragging(true); setSidebarW(w => Math.max(232, Math.min(360, w + d))); }} onDragEnd={() => setDragging(false)} />}
              {/* Conteúdo */}
              <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", background: "var(--bg-content)" }} onMouseDown={() => setFocusPane("content")}>
                <Toolbar style={{ paddingLeft: leftPad, paddingRight: inW > 1 ? 10 : 56, borderBottom: "1px solid var(--separator)" }}>
                  <ToolbarTitle title={connected ? SECTION_TITLE[section] : "Sem dispositivo"} subtitle={subtitle} />
                  <PopUpButton variant="plain" ariaLabel="Dispositivo" disabled={!connected && scenario === "checking"}
                    label={<span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><Icon name={connected ? "circle-check" : "circle-x"} size={12} strokeWidth={2.2} color={connected ? "var(--success)" : "var(--destructive)"} />{connected ? dev.name : "Nenhum dispositivo"}</span>}
                    options={[]} extraItems={[...deviceOptions.map(o => o.header ? { header: o.header } : { label: o.name + "  ·  " + o.detail, checked: connected && o.id === device, disabled: o.off || !connected, onSelect: () => { setDevice(o.id); toast(o.name + " selecionado"); } }), { separator: true }, { label: "Atualizar Lista", shortcut: "⇧⌘R", onSelect: () => toast("Lista de aparelhos atualizada") }]} />
                  {tight ? <PopUpButton size="small" ariaLabel="Ação do clique no espelho" disabled={!connected} value={mode} onChange={setMode} options={[{ value: "forward", label: "Repassar toque" }, { value: "record", label: "Gravar passo" }]} />
                    : <Tooltip label="Define o que acontece ao clicar no espelho"><SegmentedControl ariaLabel="Ação do clique no espelho" disabled={!connected} value={mode} onChange={setMode} items={[{ value: "forward", label: "Repassar toque", icon: "pointer" }, { value: "record", label: "Gravar passo", icon: "circle-dot" }]} /></Tooltip>}
                  <ToolbarSpacer />
                  {compact ? (
                    <ToolbarGroup><ToolbarButton ref={overflowBtn} icon="chevrons-right" label="Mais itens" disabled={!connected} onClick={() => { const r = overflowBtn.current.getBoundingClientRect(); setOverflow({ x: r.left, y: r.bottom + 6 }); }} /></ToolbarGroup>
                  ) : (
                    <ToolbarGroup ariaLabel="Gravação">{recItems.map(it => <ToolbarButton key={it.icon} icon={it.icon} label={it.tip} disabled={!connected} variant={it.on && it.icon === "square" ? "recording" : undefined} on={it.on} onClick={it.fn} />)}</ToolbarGroup>
                  )}
                  <ToolbarGroup tinted><ToolbarButton icon="play" label="Rodar Automação" shortcut="⌘R" variant="tinted" disabled={!steps.length || !connected} onClick={run} /></ToolbarGroup>
                  {section !== "pageObjects" && connected
                    ? <ToolbarSearch inputRef={tbSearch} open={searchOpen || !!filter[section]} onOpenChange={setSearchOpen} value={filter[section] || ""} onChange={v => setFilter(f => ({ ...f, [section]: v }))} placeholder={section === "network" ? "Filtrar host, path ou status" : "Filtrar eventos e tags"} />
                    : <ToolbarGroup><ToolbarButton icon="search" label="Buscar na hierarquia" shortcut="⌘F" onClick={openSearch} /></ToolbarGroup>}
                </Toolbar>
                <div style={{ flex: 1, display: "flex", minHeight: 0, opacity: fade, transition: "opacity var(--motion-crossfade) linear" }}>
                  {showMirror && <div style={{ width: showWork ? (section === "pageObjects" ? mirrorW : 230) : "100%", flex: showWork ? "none" : 1 }}>
                    <MirrorPane compact={section !== "pageObjects" && showWork} connected={connected} loading={loading} mode={mode} nodes={D.nodes} selectedId={nodeSel} onSelectNode={setNodeSel} onTap={onTap} fps={24} section={section}
                      correlationRef={corrRef} onCorrelation={() => setCorrOpen(o => !o)} onRefresh={() => toast("Tela capturada")} />
                  </div>}
                  {showMirror && showWork && <Splitter ariaLabel="Redimensionar espelho" onDrag={d => setMirrorW(w => Math.max(240, Math.min(420, w + d)))} />}
                  {showWork && <div style={{ flex: 1, minWidth: 0 }}>
                    {effSection === "noDevice" ? <NoDeviceView phase={scenario} lastScan={scan} onRescan={() => { setScan(new Date().toTimeString().slice(0, 8)); toast("Procurando dispositivos…"); }}
                        onStartWDA={() => scenario === "iosReady" ? setDemo("scenario", "connected") : setDemo("scenario", "iosReady")} onOpenEmulator={() => toast("Abrindo emulador Pixel 7 API 34…")} />
                      : section === "pageObjects" ? <PageObjectsView steps={steps} strategy={strategy} setStrategy={setStrategy} split={split} setSplit={setSplit} activeStep={selectedStep} connected={connected}
                        onStructure={() => setSheet("structure")} onToast={toast} onClearSteps={() => askClear("steps")} onRecordMode={() => { setMode("record"); toast("Gravar passo ativo"); }} />
                      : section === "network" ? <NetworkView rows={data.requests} proxyOn={proxyOn} setProxyOn={setProxyOn} debugOn={debugOn} setDebugOn={setDebugOn} filter={filter.network} selected={reqSel} setSelected={setReqSel}
                        newKeys={newIds} onClear={() => askClear("network")} onToast={toast} error={netError} setError={setNetError} loading={loading} />
                      : <AnalyticsView rows={data.events} listening={listening} setListening={setListening} source={source} setSource={setSource} filter={filter.analytics} selected={evSel} setSelected={setEvSel} newKeys={newIds} onClear={() => askClear("analytics")} onToast={toast} />}
                  </div>}
                </div>
                <div style={{ height: 22, flex: "none", display: "flex", alignItems: "center", gap: 12, padding: "0 12px", borderTop: "1px solid var(--separator)", background: "var(--bg-content-alt)" }}>
                  <StatusIndicator status={connected && dev.platform === "ios" ? (scenario === "error" ? "warn" : "ok") : "off"} label="WDA 8100" />
                  <StatusIndicator status={dev.platform === "android" && connected ? "ok" : "busy"} label="ADB server" />
                  <StatusIndicator status={netError ? "error" : proxyOn ? "ok" : "off"} label="Proxy MITM 8082" />
                  <StatusIndicator status={listening ? "ok" : "off"} label="FA listener" />
                  <span style={{ flex: 1 }} />
                  <span className="mb-truncate" role="status" aria-live="polite" style={{ fontSize: 11, color: "var(--label-primary)" }}>{msg}</span>
                  {connected && <span className="mb-mono mb-tabular" style={{ fontSize: 10.5, color: "var(--label-secondary)", whiteSpace: "nowrap" }}>x {cursor.x} · y {cursor.y}  24 fps  settle 180 ms  latência 42 ms</span>}
                </div>
              </div>
              {inW > 1 && <Splitter ariaLabel="Redimensionar inspector" onDrag={d => { setDragging(true); setInspectorW(w => Math.max(260, Math.min(380, w - d))); }} onDragEnd={() => setDragging(false)} />}
              <div style={{ width: inW, flex: "none", overflow: "hidden" }} onMouseDown={() => setFocusPane("inspector")}>
                <div style={{ width: inspectorW, height: "100%" }}>
                  <InspectorPane nodes={D.nodes} selectedId={nodeSel} onSelect={setNodeSel} state={!connected ? "empty" : loading ? "loading" : "ready"} query={hierQuery} setQuery={setHierQuery}
                    searchRef={hierSearch} onRecordNode={n => { setSection("pageObjects"); recordStep(n); }} toast={toast} focused={focusPane === "inspector" && windowActive} />
                </div>
              </div>
              {/* Controles ancorados: nunca se movem quando os painéis abrem ou fecham */}
              <div style={{ position: "absolute", left: 0, top: 0, height: 52, display: "flex", alignItems: "center", zIndex: 10 }}>
                <TrafficLights onClose={() => toast("⌘W fecha a janela")} />
                <span style={{ width: 14 }} />
                <ToolbarButton icon="panel-left" label={sidebarOpen ? "Ocultar Barra Lateral" : "Mostrar Barra Lateral"} shortcut="⌃⌘S" ariaPressed={sidebarOpen} onClick={() => setSidebarOpen(o => !o)} />
              </div>
              <div style={{ position: "absolute", right: 10, top: 8, zIndex: 10 }}>
                <ToolbarGroup><ToolbarButton icon="panel-right" label={inspectorOpen ? "Ocultar Inspector" : "Mostrar Inspector"} shortcut="⌥⌘I" ariaPressed={inspectorOpen} onClick={() => setInspectorOpen(o => !o)} /></ToolbarGroup>
              </div>
              <StructureSheet open={sheet === "structure"} steps={steps} onClose={() => setSheet(null)} onRun={run} />
              <FlowRunnerSheet open={sheet === "runner"} steps={steps} outcome={demo.outcome} onClose={() => setSheet(null)} onToast={toast} />
              <Alert open={!!alert} iconSrc="../../assets/app-icon.png"
                title={{ network: "Limpar o tráfego capturado?", analytics: "Limpar os eventos capturados?", steps: "Limpar todos os passos do fluxo?" }[alert]}
                message={alert === "network" ? data.requests.length + " requisições serão removidas. Você pode desfazer com ⌘Z." : alert === "analytics" ? data.events.length + " eventos serão removidos. Você pode desfazer com ⌘Z." : "O Page Object e os locators gerados serão esvaziados. Você pode desfazer com ⌘Z."}
                buttons={[{ label: { network: "Limpar Tráfego", analytics: "Limpar Eventos", steps: "Limpar Passos" }[alert] || "", role: "destructive", onClick: () => doClear(alert) }, { label: "Cancelar", role: "default", onClick: () => setAlert(null) }]} onCancel={() => setAlert(null)} />
            </div>
            <span aria-label="Redimensionar janela" style={{ position: "absolute", right: 0, bottom: 0, width: 14, height: 14, cursor: "nwse-resize", zIndex: 20 }}
              onPointerDown={e => { e.preventDefault(); let x = e.clientX, y = e.clientY; setDragging(true);
                const mv = ev => { setWin(w => ({ w: Math.max(980, w.w + (ev.clientX - x) / zoom), h: Math.max(600, w.h + (ev.clientY - y) / zoom) })); x = ev.clientX; y = ev.clientY; };
                const up = () => { setDragging(false); window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); };
                window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up); }} />
          </Window>
          <SplashWindow show={splash} />
        </div>
        <SettingsWindow open={settings.open} active={settings.front && demo.active} onFocus={() => setSettings(s => ({ ...s, front: true }))} onClose={() => setSettings({ open: false, front: false })} prefs={prefs} setPref={setPref} />
      </div>
      <Popover open={corrOpen} anchorRef={corrRef} onClose={() => setCorrOpen(false)} placement="top" width={300} ariaLabel="Correlação">
        <div style={{ padding: 14, display: "flex", flexDirection: "column", gap: 8 }}>
          <b style={{ fontWeight: 700 }}>Correlação · passo {steps.length}</b>
          <div style={{ color: "var(--label-secondary)", fontSize: 12 }}>O último toque disparou {Math.min(3, data.requests.length)} requisições e 1 evento de analytics.</div>
          <div className="mb-mono" style={{ fontSize: 10.5, lineHeight: "14px", color: "var(--label-secondary)", background: "var(--fill-tertiary)", borderRadius: 8, padding: 8, userSelect: "text" }}>
            AutomationStep(stepNum: {steps.length}, actionType: "click", varName: "{steps.length ? steps[steps.length - 1].varName : "—"}", strategy: coords, platform: ios)
          </div>
          <div><Button size="small" variant="default" onClick={() => { setCorrOpen(false); toast("Asserção de contrato gerada e inserida no código"); }}>Gerar Asserção de Contrato</Button></div>
        </div>
      </Popover>
      {overflow && <Menu x={overflow.x} y={overflow.y} onClose={() => setOverflow(null)} items={recItems.map(it => ({ label: it.label, icon: it.icon, onSelect: it.fn }))} />}
      <DemoPanel demo={demo} setDemo={setDemo} appearance={dark ? "dark" : "light"} setAppearance={v => setPref("appearance", v)} noteKey={noteKey} collapsed={demoCollapsed} setCollapsed={setDemoCollapsed} />
    </>
  );
}
Object.assign(window, { App });

function Row({ label, children, top }) { return (<><div style={{ textAlign: "right", alignSelf: top ? "start" : "center", paddingTop: top ? 3 : 0 }}>{label}</div><div style={{ display: "flex", flexDirection: "column", alignItems: "flex-start", gap: 6 }}>{children}</div></>); }
// Janela de Ajustes (⌘,): abas por ícone na toolbar; mudanças valem na hora, sem Salvar/Cancelar.
function SettingsWindow({ open, onClose, prefs, setPref, active, onFocus }) {
  const { Window, TrafficLights, Icon, PopUpButton, SegmentedControl, Checkbox, TextField } = window.MoBaileDesignSystem_ce6669;
  const [tab, setTab] = React.useState("geral");
  const [pos, setPos] = React.useState({ x: 380, y: 120 });
  const [portErr, setPortErr] = React.useState(false);
  if (!open) return null;
  const drag = e => {
    if (e.target.closest("button,[role=button]")) return;
    onFocus(); let lx = e.clientX, ly = e.clientY;
    const mv = ev => { setPos(p => ({ x: p.x + ev.clientX - lx, y: Math.max(0, p.y + ev.clientY - ly) })); lx = ev.clientX; ly = ev.clientY; };
    const up = () => { window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up);
  };
  const tabs = [["geral", "Geral", "settings"], ["conexoes", "Conexões", "cable"]];
  return (
    <div style={{ position: "absolute", left: pos.x, top: pos.y, zIndex: active ? 60 : 40 }} onMouseDown={onFocus} onKeyDown={e => e.key === "Escape" && onClose()}>
      <Window active={active} width={520} height="auto" style={{ minWidth: 0, minHeight: 0 }} ariaLabel="Ajustes">
        <div onPointerDown={drag} style={{ display: "flex", flexDirection: "column", alignItems: "center", paddingBottom: 6, borderBottom: "1px solid var(--separator)", background: "var(--bg-window)" }}>
          <div style={{ alignSelf: "stretch", display: "flex", alignItems: "center", height: 28 }}><TrafficLights onClose={onClose} /><span style={{ flex: 1, textAlign: "center", fontWeight: 700, marginRight: 66 }}>{tabs.find(t => t[0] === tab)[1]}</span></div>
          <div role="tablist" style={{ display: "flex", gap: 2 }}>
            {tabs.map(([id, l, ic]) => (
              <button key={id} type="button" role="tab" aria-selected={tab === id} onClick={() => setTab(id)} className="mb-tb-item"
                style={{ flexDirection: "column", height: 46, width: 72, gap: 2, borderRadius: 8, background: tab === id ? "var(--fill-secondary)" : undefined, color: tab === id ? "var(--accent-text)" : "var(--label-secondary)" }}>
                <Icon name={ic} size={20} /><span style={{ fontSize: 11 }}>{l}</span>
              </button>
            ))}
          </div>
        </div>
        <div style={{ padding: 20, display: "grid", gridTemplateColumns: "1fr 1.25fr", gap: "10px 6px", alignItems: "center", background: "var(--bg-window)" }}>
          {tab === "geral" ? <>
            <Row label="Aparência:"><SegmentedControl items={[{ value: "system", label: "Sistema" }, { value: "light", label: "Claro" }, { value: "dark", label: "Escuro" }]} value={prefs.appearance} onChange={v => setPref("appearance", v)} /></Row>
            <Row label="Tamanho dos itens da barra lateral:"><PopUpButton minWidth={160} options={[{ value: "small", label: "Pequeno" }, { value: "medium", label: "Médio" }, { value: "large", label: "Grande" }]} value={prefs.sidebarSize} onChange={v => setPref("sidebarSize", v)} /></Row>
            <Row label="Seletor padrão:"><PopUpButton minWidth={160} options={[{ value: "auto", label: "Auto" }, { value: "id", label: "ID" }, { value: "xpath", label: "XPath" }, { value: "coords", label: "Coords" }]} value={prefs.strategy} onChange={v => setPref("strategy", v)} /></Row>
            <div style={{ gridColumn: "1 / -1", height: 1, background: "var(--separator)", margin: "6px 0" }} />
            <Row label="Ao conectar:" top><Checkbox checked={prefs.autoStream} onChange={v => setPref("autoStream", v)} label="Iniciar o espelho automaticamente" help="O streaming começa assim que um aparelho é detectado." /></Row>
          </> : <>
            <Row label="WebDriverAgent:"><TextField mono width={200} value={prefs.wda} onChange={v => setPref("wda", v)} /></Row>
            <Row label="Host do proxy:" top><TextField mono width={200} value={prefs.proxyHost} onChange={v => setPref("proxyHost", v)} />
              <span style={{ fontSize: 11, color: "var(--label-secondary)", maxWidth: 230 }}>Mantenha 127.0.0.1. Escutar em 0.0.0.0 transforma a máquina em proxy aberto para a rede.</span></Row>
            <Row label="Porta do proxy:" top><TextField mono width={80} value={prefs.proxyPort} invalid={portErr} onChange={v => { setPref("proxyPort", v); setPortErr(!/^\d{2,5}$/.test(v)); }} />
              {portErr && <span role="alert" style={{ fontSize: 11, color: "var(--destructive)" }}>Use um número de porta, como 8082.</span>}</Row>
          </>}
        </div>
      </Window>
    </div>
  );
}

function SplashWindow({ show }) {
  if (!show) return null;
  return (
    <div style={{ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%,-50%)", zIndex: 90, width: 640, height: 380, borderRadius: 16, overflow: "hidden", boxShadow: "var(--shadow-window-active)", background: "url(../../assets/splash_bg.png) center/cover", display: "flex", alignItems: "center", justifyContent: "center", gap: 20, animation: "mb-fade 240ms linear both" }}>
      <img src="../../assets/mascot.png" alt="" style={{ height: 260 }} />
      <div>
        <div style={{ fontSize: 48, fontWeight: 700, letterSpacing: -1.4, color: "#141543", fontFamily: "var(--font-display)" }}>Mo baile</div>
        <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: ".08em", color: "#141543", opacity: .75 }}>ELEMENT RECORDER</div>
        <div className="mb-progress" style={{ width: 190, marginTop: 16, background: "rgba(255,255,255,.55)" }}><div className="mb-progress__bar" style={{ width: "100%", transition: "width 1.4s linear" }} /></div>
        <div style={{ fontSize: 11, color: "#141543", marginTop: 6, opacity: .7 }}>Iniciando o motor…</div>
      </div>
    </div>
  );
}
Object.assign(window, { SettingsWindow, SplashWindow });

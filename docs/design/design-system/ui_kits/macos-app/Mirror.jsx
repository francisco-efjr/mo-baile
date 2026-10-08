// Coluna do espelho ao vivo: tela do aparelho, destaque do elemento sob o cursor, clique vira toque/passo.
function MirrorPane({ compact, connected, loading, mode, nodes, selectedId, onSelectNode, onTap, fps, section, steps, correlationRef, onCorrelation, onRefresh }) {
  const { DeviceFrame, Button, Icon, ProgressIndicator, Tooltip, ToolbarButton, ToolbarGroup, EmptyState } = window.MoBaileDesignSystem_ce6669;
  const [hover, setHover] = React.useState(null);
  const [ripples, setRipples] = React.useState([]);
  const screen = React.useRef(null);
  const W = compact ? 176 : 222, H = compact ? 368 : 464;
  const hit = (e) => {
    const r = screen.current.getBoundingClientRect();
    const px = ((e.clientX - r.left) / r.width) * 100, py = ((e.clientY - r.top) / r.height) * 100;
    return { px, py, node: nodes.filter(n => n.box).find(n => px >= n.box[0] && px <= n.box[0] + n.box[2] && py >= n.box[1] && py <= n.box[1] + n.box[3]) };
  };
  const click = e => {
    if (!connected || loading) return;
    const { px, py, node } = hit(e);
    const id = Date.now();
    setRipples(rs => [...rs, { id, px, py }]);
    setTimeout(() => setRipples(rs => rs.filter(r => r.id !== id)), 420);
    if (node) onSelectNode(node.id);
    onTap && onTap(node, { px, py });
  };
  const hv = nodes.find(n => n.id === (hover || selectedId));
  return (
    <section aria-label="Espelho" style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", alignItems: "center", background: "var(--bg-content-alt)", position: "relative" }}>
      <div style={{ alignSelf: "stretch", display: "flex", alignItems: "center", height: 30, padding: "0 12px", gap: 6, color: "var(--label-secondary)", fontSize: 11, fontWeight: 600 }}>
        <span style={{ flex: 1 }}>Espelho</span>
        {connected && !loading && <span className="mb-tabular" style={{ fontWeight: 400, whiteSpace: "nowrap" }}>{fps} fps</span>}
      </div>
      <div style={{ flex: 1, display: "grid", placeItems: "center", minHeight: 0 }}>
        <DeviceFrame width={W} height={H} screenRef={screen}
          onMouseMove={e => { if (connected && !loading) { const h = hit(e); setHover(h.node ? h.node.id : null); } }}
          onMouseLeave={() => setHover(null)} onClick={click}>
          {connected && !loading ? <BankScreen scale={(W - 14) / 208} /> : (
            <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", background: "var(--bg-device-screen)" }}>
              {loading ? <ProgressIndicator kind="spinner" size={20} /> : <span className="mb-mono" style={{ fontSize: 11, color: "var(--label-secondary)" }}>sem sinal</span>}
            </div>
          )}
          {connected && !loading && hv && hv.box && (
            <div style={{ position: "absolute", left: hv.box[0] + "%", top: hv.box[1] + "%", width: hv.box[2] + "%", height: hv.box[3] + "%", border: "2px solid var(--accent)", borderRadius: 8, boxShadow: "0 0 0 4px var(--accent-tint)", pointerEvents: "none", transition: "all 120ms var(--ease-out-standard)", zIndex: 4 }}>
              <span className="mb-mono" style={{ position: "absolute", bottom: "100%", left: -2, marginBottom: 3, background: "var(--accent)", color: "#fff", fontSize: 9.5, padding: "1px 5px", borderRadius: 4, whiteSpace: "nowrap" }}>
                {(hv.var || hv.label).toLowerCase()}{hv.hit ? " · " + hv.hit : ""}
              </span>
            </div>
          )}
          {ripples.map(r => <span key={r.id} style={{ position: "absolute", left: r.px + "%", top: r.py + "%", width: 26, height: 26, margin: -13, borderRadius: "50%", border: "2px solid #fff", boxShadow: "0 0 0 1px rgba(0,0,0,.2)", zIndex: 5, pointerEvents: "none", animation: "mb-ripple 300ms ease-out forwards" }} />)}
        </DeviceFrame>
      </div>
      <div style={{ display: "flex", gap: 8, padding: "12px 0 16px", alignItems: "center" }}>
        <Tooltip label="Atualizar tela  ⌘K"><Button size="small" icon="refresh-cw" disabled={!connected} onClick={onRefresh}>Atualizar</Button></Tooltip>
        {(section === "network" || section === "analytics") && (
          <Tooltip label="Correlação do último toque"><Button size="small" icon="link" disabled={!connected} onClick={onCorrelation}>
            <span ref={correlationRef}>Correlação</span>
          </Button></Tooltip>
        )}
      </div>
    </section>
  );
}

// Tela do app em teste (conteúdo do catálogo original: "Crédito pessoal").
function BankScreen({ scale = 1 }) {
  const ink = "#17323F", blue = "#0F6E99";
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: 208, height: 450, transform: "scale(" + scale + ")", transformOrigin: "0 0", background: "#fff", color: ink, fontFamily: "var(--font-ui)", letterSpacing: 0 }}>
      <div style={{ display: "flex", justifyContent: "space-between", padding: "13px 20px 0 22px", fontSize: 10.5, fontWeight: 600 }}><span>9:41</span><span style={{ opacity: .8 }}>●●● ▮</span></div>
      <div style={{ position: "absolute", top: "9.5%", left: 0, right: 0, textAlign: "center", fontSize: 10.5, fontWeight: 600 }}>Crédito pessoal</div>
      <div style={{ position: "absolute", top: "9.2%", left: "8%", color: blue, fontSize: 15, lineHeight: 1 }}>‹</div>
      <div style={{ position: "absolute", top: "19%", left: "50%", transform: "translateX(-50%)", width: 72, height: 72, borderRadius: 36, background: "#E3EEF3", display: "grid", placeItems: "center" }}>
        <div style={{ width: 32, height: 22, borderRadius: 4, background: blue, position: "relative" }}><div style={{ position: "absolute", left: 0, right: 0, top: 6, height: 3, background: "#fff" }} /><div style={{ position: "absolute", left: 5, bottom: 4, width: 6, height: 4, background: "#fff", borderRadius: 1 }} /></div>
      </div>
      <div style={{ position: "absolute", top: "41.5%", left: "8%", right: "8%", fontSize: 15, fontWeight: 700, lineHeight: "18px" }}>Simule seu crédito<br />em minutos</div>
      <div style={{ position: "absolute", top: "50.5%", left: "8%", right: "8%", fontSize: 8, lineHeight: "11px", color: "#5A7C8B" }}>Sem compromisso. A taxa aparece antes de você contratar.</div>
      {[["CPF", "000.000.000-00", 55.5], ["Valor desejado", "R$ 5.000,00", 65]].map(([l, p, t]) => (
        <div key={l} style={{ position: "absolute", top: t + "%", left: "8%", right: "8%" }}>
          <div style={{ fontSize: 7, color: "#5A7C8B", marginBottom: 2 }}>{l}</div>
          <div style={{ height: 26, border: "1px solid #CBDCE3", borderRadius: 6, fontSize: 8.5, color: "#9AB0BA", display: "flex", alignItems: "center", padding: "0 8px" }}>{p}</div>
        </div>
      ))}
      <div style={{ position: "absolute", top: "82%", left: "8%", right: "8%", height: "6%", borderRadius: 7, background: blue, color: "#fff", fontSize: 9.5, fontWeight: 600, display: "grid", placeItems: "center" }}>Continuar</div>
      <div style={{ position: "absolute", top: "90%", left: 0, right: 0, textAlign: "center", fontSize: 8.5, color: blue, fontWeight: 500 }}>Agora não</div>
      <div style={{ position: "absolute", bottom: 7, left: "50%", transform: "translateX(-50%)", width: 80, height: 3, borderRadius: 2, background: ink }} />
    </div>
  );
}
Object.assign(window, { MirrorPane, BankScreen });

// Sheets: Estrutura do Fluxo e Executar Fluxo.
function StructureSheet({ open, steps, onClose, onRun }) {
  const { Sheet, Button, DataTable } = window.MoBaileDesignSystem_ce6669;
  const [sel, setSel] = React.useState([]);
  const rows = steps.map((s, i) => ({ ...s, n: i + 1 }));
  return (
    <Sheet open={open} onClose={onClose} onConfirm={onClose} width={680} ariaLabel="Estrutura do fluxo"
      footer={<><button type="button" className="mb-help" aria-label="Ajuda">?</button><span style={{ flex: 1 }} /><Button style={{ minWidth: 96 }} onClick={() => { onClose(); setTimeout(onRun, 350); }}>Rodar…</Button><Button variant="default" style={{ minWidth: 96 }} onClick={onClose}>Concluir</Button></>}>
      <h2 style={{ margin: "0 0 4px", fontSize: 13, fontWeight: 700 }}>Estrutura do fluxo</h2>
      <p style={{ margin: "0 0 12px", color: "var(--label-secondary)" }}>onboarding_credito · {steps.length} passos. Arraste na barra lateral para reordenar.</p>
      <DataTable style={{ height: 230, borderRadius: 8, boxShadow: "inset 0 0 0 .5px var(--separator)" }} selected={sel} onSelectionChange={setSel} rowKey="id" rows={rows}
        columns={[{ key: "n", label: "#", width: 34, align: "right" }, { key: "action", label: "Ação", width: 90, mono: true }, { key: "element", label: "Elemento", width: "1fr" }, { key: "strategy", label: "Estratégia", width: 80 }, { key: "selector", label: "Coordenadas/Seletor", width: "1.3fr", mono: true }]} />
    </Sheet>
  );
}

function FlowRunnerSheet({ open, steps, outcome, onClose, onToast }) {
  const { Sheet, Button, ProgressIndicator, Icon, StatusIndicator, Tooltip } = window.MoBaileDesignSystem_ce6669;
  const [phase, setPhase] = React.useState("idle");
  const [cur, setCur] = React.useState(0);
  const [lines, setLines] = React.useState([]);
  const timer = React.useRef(null);
  const term = React.useRef(null);
  const failAt = Math.min(4, steps.length - 1);
  React.useEffect(() => {
    clearInterval(timer.current);
    if (!open) return;
    const L = window.MB_DATA.log; let li = 0, step = 0;
    setPhase("running"); setCur(0); setLines([]);
    timer.current = setInterval(() => {
      if (li >= L.length) { clearInterval(timer.current); setPhase("passed"); setCur(steps.length); return; }
      const l = L[li++];
      if (outcome === "fail" && l[1] === "PASS" && step === failAt) { setLines(x => [...x, window.MB_DATA.failLine]); clearInterval(timer.current); setPhase("failed"); return; }
      setLines(x => [...x, l]);
      if (l[1] === "PASS") { step++; setCur(step); }
    }, 420);
    return () => clearInterval(timer.current);
  }, [open, outcome]);
  React.useEffect(() => { if (term.current) term.current.scrollTop = term.current.scrollHeight; }, [lines]);
  const stop = () => { clearInterval(timer.current); setPhase("stopped"); };
  const passed = phase === "failed" ? failAt : Math.min(cur, steps.length);
  const badge = { running: ["Em execução", "busy"], passed: ["Concluído", "ok"], failed: ["Falha", "error"], stopped: ["Interrompido", "warn"], idle: ["", "off"] }[phase];
  const tagColor = { INFO: "var(--info)", RUN: "var(--info)", PASS: "var(--success)", HTTP: "var(--warning)", FA: "var(--warning)", FAIL: "var(--destructive)" };
  const done = phase !== "running";
  return (
    <Sheet open={open} onClose={done ? onClose : stop} onConfirm={done ? onClose : undefined} width={820} ariaLabel="Executar fluxo"
      footer={<>
        <button type="button" className="mb-help" aria-label="Ajuda">?</button>
        <span className="mb-tabular" style={{ flex: 1, fontSize: 12, color: "var(--label-secondary)" }}>{passed} aprovados · {phase === "failed" ? 1 : 0} falhas · tempo {(lines.length * 0.42).toFixed(1).replace(".", ",")} s</span>
        <Button style={{ minWidth: 96 }} icon="terminal" onClick={() => onToast("flow_runner.log aberto")}>Abrir Log</Button>
        {!done ? <Tooltip label="Interromper  ⌘."><Button variant="destructive" style={{ minWidth: 96 }} onClick={stop}>Interromper</Button></Tooltip>
          : <Button variant="default" style={{ minWidth: 96 }} onClick={onClose}>Concluir</Button>}
      </>}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
        <h2 style={{ margin: 0, fontSize: 13, fontWeight: 700 }}>Executar fluxo · onboarding_credito</h2>
        <StatusIndicator status={badge[1]} label={badge[0]} mono={false} />
        <span style={{ flex: 1 }} />
        <StatusIndicator status="ok" label="WDA 8100" /><StatusIndicator status="ok" label="Proxy 8082" />
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
        <div style={{ flex: 1 }}><ProgressIndicator value={passed / steps.length} tone={phase === "failed" ? "error" : phase === "passed" ? "success" : undefined} /></div>
        <span className="mb-tabular" style={{ fontSize: 11, color: "var(--label-secondary)" }}>passo {Math.min(cur + (done ? 0 : 1), steps.length)} de {steps.length}</span>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "280px 1fr", gap: 12, height: 300 }}>
        <ol style={{ margin: 0, padding: 4, listStyle: "none", overflow: "auto", borderRadius: 10, background: "var(--bg-content)", boxShadow: "inset 0 0 0 .5px var(--separator)" }}>
          {steps.map((s, i) => {
            const st = i < passed ? "ok" : phase === "failed" && i === failAt ? "error" : phase === "running" && i === cur ? "run" : "todo";
            return (
              <li key={s.id} style={{ display: "flex", alignItems: "center", gap: 8, height: 28, padding: "0 8px", borderRadius: 6, background: st === "run" ? "var(--selection-content)" : undefined, color: st === "todo" ? "var(--label-secondary)" : undefined }}>
                {st === "ok" ? <Icon name="circle-check" size={14} color="var(--success)" /> : st === "error" ? <Icon name="circle-x" size={14} color="var(--destructive)" /> : st === "run" ? <ProgressIndicator kind="spinner" size={14} /> : <Icon name="circle-dot" size={14} color="var(--label-tertiary)" />}
                <span className="mb-truncate" style={{ flex: 1 }}>{s.action} {s.element}</span>
                {s.value && <span className="mb-mono" style={{ fontSize: 11, color: "var(--label-secondary)" }}>{s.value}</span>}
              </li>
            );
          })}
        </ol>
        <div style={{ borderRadius: 10, background: "var(--bg-terminal)", color: "#CDD6F4", display: "flex", flexDirection: "column", overflow: "hidden" }}>
          <div className="mb-mono" style={{ display: "flex", justifyContent: "space-between", padding: "8px 12px", fontSize: 10.5, color: "#7F849C", borderBottom: "1px solid rgba(255,255,255,.08)" }}><span>.flow_runner.py</span><span>stdout · streaming</span></div>
          <div ref={term} className="mb-mono" style={{ flex: 1, overflow: "auto", padding: "8px 12px", fontSize: 11, lineHeight: "17px", userSelect: "text", cursor: "text" }}>
            {lines.map((l, i) => <div key={i}><span style={{ color: "#585B70" }}>{l[0]}</span> <span style={{ color: { INFO: "#89B4FA", RUN: "#89B4FA", PASS: "#A6E3A1", HTTP: "#F9E2AF", FA: "#F9E2AF", FAIL: "#F38BA8" }[l[1]] }}>[{l[1]}]</span> {l[2]}</div>)}
          </div>
        </div>
      </div>
    </Sheet>
  );
}
Object.assign(window, { StructureSheet, FlowRunnerSheet });

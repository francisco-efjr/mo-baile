// Workspace "Page Objects": dois editores (pages / locators) gerados a partir dos passos.
const PY_KW = new Set(["def", "self", "from", "import", "return", "class"]);
function highlight(line) {
  const out = []; let i = 0; const re = /("[^"]*"|'[^']*')|(\b\d+(?:\.\d+)?\b)|(#.*$)|([A-Za-z_][A-Za-z0-9_]*)/g; let m;
  while ((m = re.exec(line))) {
    if (m.index > i) out.push(line.slice(i, m.index));
    const t = m[0]; let c = null;
    if (m[1]) c = "var(--syntax-string)"; else if (m[2]) c = "var(--syntax-number)"; else if (m[3]) c = "var(--syntax-comment)";
    else if (PY_KW.has(t)) c = "var(--syntax-keyword)"; else if (t === "AppiumBy") c = "var(--syntax-type)";
    else if (/^[a-z_]+$/.test(t) && line.slice(re.lastIndex).startsWith("(")) c = "var(--syntax-function)";
    out.push(c ? <span key={m.index} style={{ color: c }}>{t}</span> : t);
    i = re.lastIndex;
  }
  if (i < line.length) out.push(line.slice(i));
  return out;
}
function genPages(steps) {
  const L = [];
  steps.forEach(s => {
    const ref = "self.locators['onboarding_credito_objs']." + s.varName;
    const arg = s.action === "send_keys" ? "self, texto" : "self";
    L.push({ t: "def " + s.method + "(" + arg + "):", step: s.id });
    L.push({ t: "    self.wait_to_be_visible(" + ref + ", 15)", step: s.id });
    L.push({ t: s.action === "send_keys" ? "    self.send_keys(" + ref + ", texto)" : "    self.click(" + ref + ", 2)", step: s.id });
    L.push({ t: "" });
  });
  return L;
}
function genLocators(steps) {
  const L = [{ t: "from appium.webdriver.common.appiumby import AppiumBy" }, { t: "" }];
  steps.forEach(s => {
    const by = s.strategy === "xpath" ? "AppiumBy.XPATH, '" + s.selector + "'" : s.strategy === "coords" ? null : "AppiumBy.ACCESSIBILITY_ID, \"" + s.selector + "\"";
    L.push({ t: by ? s.varName + " = (" + by + ")" : s.varName + " = (1095, 210)  # coords", step: s.id });
  });
  return L;
}
function CodeEditor({ title, path, color, lines, activeStep, onToast, onClear, disabled }) {
  const { Icon, Tooltip } = window.MoBaileDesignSystem_ce6669;
  const act = (icon, label, fn, dis) => (
    <Tooltip key={label} label={label}><button type="button" className="mb-tb-item" aria-label={label} disabled={dis} onClick={fn} style={{ minWidth: 24, height: 22, padding: "0 5px" }}><Icon name={icon} size={14} /></button></Tooltip>
  );
  return (
    <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", background: "var(--bg-content)" }}>
      <div style={{ height: 30, flex: "none", display: "flex", alignItems: "center", gap: 6, padding: "0 6px 0 12px", borderBottom: "1px solid var(--separator)", fontSize: 12 }}>
        <Icon name="folder" size={13} color={color} />
        <span style={{ color: "var(--label-secondary)" }}>{path}</span><span style={{ color: "var(--label-tertiary)" }}>/</span>
        <span className="mb-truncate mb-mono" style={{ fontSize: 11.5, color, flex: 1 }} title={title}>{title}</span>
        <span className="mb-count" style={{ fontSize: 11 }}>{lines.length} linhas</span>
        {act("copy", "Copiar  ⇧⌘C", () => onToast("Código copiado"), disabled)}
        {act("save", "Salvar  ⌘S", () => onToast(title + " salvo"), disabled)}
        {act("trash-2", "Limpar", onClear, disabled)}
      </div>
      <div className="mb-mono" style={{ flex: 1, overflow: "auto", fontSize: 11.5, lineHeight: "19px", padding: "6px 0", userSelect: "text", cursor: "text", color: "var(--syntax-plain)" }}>
        {lines.map((l, i) => (
          <div key={i} style={{ display: "flex", background: activeStep && l.step === activeStep ? "var(--selection-content)" : undefined, transition: "background-color var(--motion-crossfade)" }}>
            <span className="mb-tabular" style={{ width: 34, flex: "none", textAlign: "right", paddingRight: 10, color: "var(--syntax-gutter)", userSelect: "none" }}>{i + 1}</span>
            <span style={{ whiteSpace: "pre", paddingRight: 12 }}>{highlight(l.t)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
function PageObjectsView({ steps, strategy, setStrategy, split, setSplit, activeStep, onStructure, onToast, onClearSteps, onRecordMode, connected }) {
  const { AccessoryBar, SegmentedControl, Button, ToolbarButton, EmptyState, StatusIndicator, Tooltip } = window.MoBaileDesignSystem_ce6669;
  const [tab, setTab] = React.useState("pages");
  const pages = genPages(steps), locs = genLocators(steps);
  const last = steps[steps.length - 1];
  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", minWidth: 0 }}>
      <AccessoryBar>
        <span style={{ fontSize: 12, color: "var(--label-secondary)" }}>Seletor:</span>
        <SegmentedControl size="small" ariaLabel="Estratégia de seletor" value={strategy} onChange={setStrategy}
          items={[{ value: "auto", label: "Auto", tooltip: "O motor escolhe o localizador único mais robusto" }, { value: "id", label: "ID" }, { value: "xpath", label: "XPath" }, { value: "coords", label: "Coords" }]} />
        <span style={{ flex: 1 }} />
        {!split && <SegmentedControl size="small" ariaLabel="Arquivo" value={tab} onChange={setTab} items={[{ value: "pages", label: "pages" }, { value: "locators", label: "locators" }]} />}
        <Tooltip label="Estrutura do fluxo…"><Button size="small" icon="list-ordered" disabled={!steps.length} onClick={onStructure}>Estrutura…</Button></Tooltip>
        <Tooltip label={split ? "Mostrar um arquivo por vez" : "Mostrar pages e locators lado a lado"}>
          <button type="button" className={"mb-tb-item" + (split ? " is-on" : "")} aria-pressed={split} aria-label="Lado a lado" onClick={() => setSplit(!split)} style={{ height: 22, minWidth: 26, padding: "0 5px" }}><window.MoBaileDesignSystem_ce6669.Icon name="columns-2" size={15} /></button>
        </Tooltip>
      </AccessoryBar>
      {steps.length === 0 ? (
        <div style={{ flex: 1, display: "grid", placeItems: "center", background: "var(--bg-content)" }}>
          <EmptyState icon="file-code" title="Nenhum passo gravado" text="Com “Gravar passo” ativo, clique em um elemento no espelho. Cada toque vira um locator e um método do Page Object." actionLabel={connected ? "Gravar Passo" : undefined} onAction={onRecordMode} />
        </div>
      ) : (
        <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
          {(split || tab === "pages") && <CodeEditor title="onboarding_credito_objs.py" path="pages" color="var(--syntax-function)" lines={pages} activeStep={activeStep} onToast={onToast} onClear={onClearSteps} />}
          {split && <div className="mb-splitter" />}
          {(split || tab === "locators") && <CodeEditor title="onboarding_credito_objs.py" path="locators" color="var(--accent-text)" lines={locs} activeStep={activeStep} onToast={onToast} onClear={onClearSteps} />}
        </div>
      )}
      <div style={{ height: 26, flex: "none", display: "flex", alignItems: "center", gap: 8, padding: "0 12px", borderTop: "1px solid var(--separator)", fontSize: 11, color: "var(--label-secondary)", background: "var(--bg-content)" }}>
        <span className="mb-mono mb-truncate" style={{ flex: 1 }}>{last ? "passo " + steps.length + " · " + last.action + " · " + last.strategy : "nenhum passo"}</span>
        <StatusIndicator status="ok" label="Código sincronizado" mono={false} />
      </div>
    </div>
  );
}
Object.assign(window, { PageObjectsView, genPages, genLocators, highlight });

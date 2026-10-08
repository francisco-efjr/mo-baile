// Inspector: hierarquia de acessibilidade (árvore com busca) + atributos do elemento selecionado.
function InspectorPane({ nodes, selectedId, onSelect, state, query, setQuery, searchRef, onRecordNode, toast, focused }) {
  const { SearchField, TypeChip, Icon, Button, EmptyState, ContextMenu, Tooltip } = window.MoBaileDesignSystem_ce6669;
  const [collapsed, setCollapsed] = React.useState({});
  const hasKids = i => nodes[i + 1] && nodes[i + 1].depth > nodes[i].depth;
  const q = query.trim().toLowerCase();
  const visible = [];
  let hideBelow = null;
  nodes.forEach((n, i) => {
    if (hideBelow != null && n.depth > hideBelow) return;
    hideBelow = null;
    if (q && !(n.label + " " + n.attrs.type + " " + n.attrs.name).toLowerCase().includes(q)) return;
    visible.push({ n, i });
    if (!q && collapsed[n.id] && hasKids(i)) hideBelow = n.depth;
  });
  const sel = nodes.find(n => n.id === selectedId);
  const onKey = e => {
    const k = visible.findIndex(v => v.n.id === selectedId);
    if (e.key === "ArrowDown") { e.preventDefault(); const v = visible[Math.min(visible.length - 1, k + 1)]; v && onSelect(v.n.id); }
    if (e.key === "ArrowUp") { e.preventDefault(); const v = visible[Math.max(0, k - 1)]; v && onSelect(v.n.id); }
    if (e.key === "ArrowLeft" && sel) setCollapsed(c => ({ ...c, [sel.id]: true }));
    if (e.key === "ArrowRight" && sel) setCollapsed(c => ({ ...c, [sel.id]: false }));
  };
  const copy = (txt, msg) => { navigator.clipboard && navigator.clipboard.writeText(txt).catch(() => {}); toast(msg); };
  const menu = n => [
    { label: "Copiar Locator", shortcut: "⌘C", onSelect: () => copy(n.var || n.label, "Locator copiado") },
    { label: "Copiar XPath", shortcut: "⌥⌘C", onSelect: () => copy("//" + n.attrs.type + "[@name=\"" + n.attrs.name + "\"]", "XPath copiado") },
    { label: "Copiar Atributos", onSelect: () => copy(JSON.stringify(n.attrs, null, 2), "Atributos copiados") },
    { separator: true },
    { label: "Gravar como Passo", disabled: !n.box, onSelect: () => onRecordNode(n) }
  ];
  return (
    <aside aria-label="Inspector" style={{ height: "100%", display: "flex", flexDirection: "column", background: "var(--bg-content)", minWidth: 0 }}>
      <div style={{ height: "var(--toolbar-height)", flex: "none", display: "flex", alignItems: "center", padding: "0 52px 0 14px" }}>
        <b style={{ fontSize: 13, fontWeight: 700 }}>Hierarquia</b>
        <span className="mb-count" style={{ marginLeft: 6 }}>{state === "ready" ? nodes.length : ""}</span>
      </div>
      <div style={{ padding: "0 10px 8px", flex: "none" }}>
        <SearchField inputRef={searchRef} value={query} onChange={setQuery} placeholder="Buscar texto, ID ou XPath" shortcut="⌘F" />
      </div>
      <div className="mb-splitter mb-splitter--h" style={{ pointerEvents: "none" }} />
      <div role="tree" tabIndex={0} onKeyDown={onKey} aria-label="Árvore de acessibilidade" style={{ flex: 1, overflow: "auto", padding: "4px 6px" }}>
        {state === "loading" && <EmptyState compact loading text="Lendo a hierarquia…" />}
        {state === "empty" && <EmptyState compact icon="list-tree" text="Conecte um aparelho para ver a hierarquia da tela." />}
        {state === "ready" && visible.length === 0 && <EmptyState compact icon="search" title="Nenhum elemento encontrado" text={"Nada corresponde a “" + query + "”."} />}
        {state === "ready" && visible.map(({ n, i }) => (
          <ContextMenu key={n.id} items={() => menu(n)} onOpen={() => onSelect(n.id)}>
            <div role="treeitem" aria-selected={n.id === selectedId} aria-expanded={hasKids(i) ? !collapsed[n.id] : undefined}
              className={"mb-sb-item" + (n.id === selectedId ? " is-selected" : "")}
              onMouseDown={() => onSelect(n.id)} title={n.label}
              style={{ height: 24, fontSize: 12, paddingLeft: 4 + (q ? 0 : n.depth * 14), gap: 5, "--selection": focused ? "var(--accent)" : "var(--selection-inactive)", color: n.id === selectedId && !focused ? "var(--label-primary)" : undefined }}>
              <span style={{ width: 12, display: "grid", placeItems: "center", flex: "none" }}
                onMouseDown={e => { if (hasKids(i)) { e.stopPropagation(); setCollapsed(c => ({ ...c, [n.id]: !c[n.id] })); } }}>
                {hasKids(i) && !q && <Icon name="chevron-right" size={11} strokeWidth={2.2} style={{ transform: collapsed[n.id] ? "none" : "rotate(90deg)", transition: "transform var(--spring-snappy-duration) var(--spring-snappy-ease)", color: "currentColor" }} />}
              </span>
              <TypeChip type={n.type} />
              <span className="mb-sb-item__label">{n.label}</span>
            </div>
          </ContextMenu>
        ))}
      </div>
      <div className="mb-splitter mb-splitter--h" style={{ pointerEvents: "none" }} />
      <div style={{ flex: "none", height: 196, display: "flex", flexDirection: "column", padding: "8px 14px 12px", gap: 6 }}>
        <div style={{ display: "flex", alignItems: "center" }}>
          <span style={{ flex: 1, fontSize: 11, fontWeight: 600, color: "var(--label-secondary)" }}>Atributos</span>
          <Button size="mini" variant="plain" disabled={!sel || state !== "ready"} onClick={() => copy(JSON.stringify(sel.attrs, null, 2), "Atributos copiados")}>Copiar Tudo</Button>
        </div>
        {sel && state === "ready" ? (
          <div className="mb-mono" style={{ display: "grid", gridTemplateColumns: "64px 1fr", gap: "3px 8px", fontSize: 11, lineHeight: "15px", userSelect: "text", cursor: "text" }}>
            {Object.entries(sel.attrs).map(([k, v]) => (
              <React.Fragment key={k}><span style={{ color: "var(--label-secondary)", textAlign: "right" }}>{k}</span><span className="mb-truncate" title={v}>{v || "—"}</span></React.Fragment>
            ))}
          </div>
        ) : <div style={{ fontSize: 12, color: "var(--label-secondary)", textAlign: "center", paddingTop: 30 }}>Nenhum elemento selecionado</div>}
      </div>
    </aside>
  );
}
Object.assign(window, { InspectorPane });

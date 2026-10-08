// Workspaces "Rede HTTP" e "Analytics": barra acessória, tabela e painel de detalhes.
const methodColor = m => ({ GET: "var(--http-get)", POST: "var(--http-post)", PUT: "var(--http-post)", DELETE: "var(--http-delete)", CONNECT: "var(--http-connect)" }[m]);
const statusColor = s => s == null ? "var(--label-tertiary)" : s >= 400 ? "var(--status-4xx)" : s >= 300 ? "var(--status-3xx)" : "var(--status-2xx)";
const fmtTime = t => t == null ? "—" : t >= 1000 ? (t / 1000).toFixed(1).replace(".", ",") + " s" : t + " ms";
function sortRows(rows, sort) {
  if (!sort) return rows;
  return [...rows].sort((a, b) => { const x = a[sort.key], y = b[sort.key]; const r = x == null ? -1 : y == null ? 1 : x > y ? 1 : x < y ? -1 : 0; return sort.dir === "asc" ? r : -r; });
}
function DetailHeader({ title, extra, tab, setTab, tabs, onCopy }) {
  const { SegmentedControl, Button } = window.MoBaileDesignSystem_ce6669;
  return (
    <div style={{ height: 34, display: "flex", alignItems: "center", gap: 8, padding: "0 10px 0 12px", borderBottom: "1px solid var(--separator)", flex: "none" }}>
      <b style={{ fontWeight: 600, fontSize: 12, whiteSpace: "nowrap" }}>{title}</b><span className="mb-truncate" style={{ display: "inline-flex", gap: 6 }}>{extra}</span><span style={{ flex: 1 }} />
      {tabs && <SegmentedControl size="small" items={tabs} value={tab} onChange={setTab} />}
      <Button size="mini" icon="copy" onClick={onCopy} aria-label="Copiar"><span className="mb-hide-narrow">Copiar</span></Button>
    </div>
  );
}
function KV({ rows }) {
  return (
    <div className="mb-mono" style={{ display: "grid", gridTemplateColumns: "minmax(90px,auto) 1fr", fontSize: 11, lineHeight: "15px", userSelect: "text", cursor: "text" }}>
      {rows.map(([k, v], i) => <React.Fragment key={k}><span style={{ padding: "4px 12px", color: "var(--accent-text)", borderBottom: "1px solid var(--separator)" }}>{k}</span><span className="mb-truncate" title={v} style={{ padding: "4px 12px 4px 0", borderBottom: "1px solid var(--separator)" }}>{v}</span></React.Fragment>)}
    </div>
  );
}
function Body({ text }) { return <pre className="mb-mono" style={{ margin: 10, padding: 10, borderRadius: 8, background: "var(--bg-content-alt)", fontSize: 11, lineHeight: "16px", whiteSpace: "pre-wrap", userSelect: "text", cursor: "text" }}>{text}</pre>; }

function NetworkView({ rows, proxyOn, setProxyOn, debugOn, setDebugOn, filter, selected, setSelected, newKeys, onClear, onToast, error, setError, loading }) {
  const NS = window.MoBaileDesignSystem_ce6669;
  const { AccessoryBar, Button, StatusIndicator, DataTable, EmptyState, InlineError, Icon, Tooltip, Menu, Splitter } = NS;
  const [sort, setSort] = React.useState(null);
  const [reqTab, setReqTab] = React.useState("h"), [resTab, setResTab] = React.useState("b");
  const [menu, setMenu] = React.useState(null);
  const [split, setSplit] = React.useState(0.5);
  const box = React.useRef(null);
  const f = filter.trim().toLowerCase();
  const shown = sortRows(rows.filter(r => !f || (r.host + r.path + r.status + r.method).toLowerCase().includes(f)), sort);
  const sel = rows.find(r => r.id === selected[selected.length - 1]);
  const cols = [
    { key: "method", label: "Método", width: 78, sortable: true, mono: true, color: r => methodColor(r.method) },
    { key: "status", label: "Status", width: 58, sortable: true, mono: true, align: "right", render: r => r.status || "—", color: r => statusColor(r.status) },
    { key: "host", label: "Host", width: "1fr", minWidth: 120, sortable: true, mono: true },
    { key: "path", label: "Caminho", width: "1.4fr", minWidth: 120, sortable: true, mono: true },
    { key: "size", label: "Tamanho", width: 68, sortable: true, align: "right", render: r => r.size + " B" },
    { key: "time", label: "Tempo", width: 64, sortable: true, align: "right", render: r => fmtTime(r.time) }
  ];
  return (
    <div ref={box} className="mb-cq" style={{ display: "flex", flexDirection: "column", height: "100%", minWidth: 0, background: "var(--bg-content)" }}>
      <AccessoryBar>
        <span className="mb-hide-xnarrow"><StatusIndicator status={proxyOn ? "ok" : "off"} label={proxyOn ? "Proxy 8082 ativo" : "Proxy 8082 inativo"} /></span>
        <span style={{ flex: 1 }} />
        <Tooltip label={debugOn ? "Desfaz a configuração de proxy no iPhone" : "Configura o iPhone físico para usar o proxy"}><Button size="small" icon="smartphone" disabled={!proxyOn} onClick={() => setDebugOn(!debugOn)}><span className="mb-hide-narrow">{debugOn ? "Parar iPhone Debug" : "iPhone em Debug"}</span></Button></Tooltip>
        <Tooltip label={proxyOn ? "Encerra o proxy e desfaz a rota reversa no aparelho" : "Inicia o proxy MITM e configura a rota reversa no aparelho"}>
          <Button size="small" icon="network" onClick={() => { setError(null); setProxyOn(!proxyOn); }}><span className="mb-hide-narrow">{proxyOn ? "Parar Proxy" : "Configurar Proxy"}</span></Button></Tooltip>
        <Tooltip label="Exporta o tráfego capturado no formato HAR 1.2"><Button size="small" icon="share" disabled={!rows.length} onClick={() => onToast("network_traffic.har exportado")}><span className="mb-hide-narrow">Exportar HAR…</span></Button></Tooltip>
        <Button size="small" variant="plain-destructive" disabled={!rows.length} onClick={onClear}>Limpar Tráfego</Button>
      </AccessoryBar>
      {error && <div style={{ padding: "8px 12px 0" }}><InlineError title="Não foi possível iniciar o proxy." text="A porta 8082 já está em uso por outro app. Feche-o ou troque a porta em Ajustes › Conexões." actionLabel="Tentar de Novo" onAction={() => { setError(null); setProxyOn(true); }} /></div>}
      <div style={{ flex: split, minHeight: 100, display: "flex", flexDirection: "column" }}>
        {loading ? <div style={{ flex: 1, display: "grid", placeItems: "center" }}><EmptyState compact loading text="Iniciando o proxy…" /></div>
          : !proxyOn && !rows.length ? <div style={{ flex: 1, display: "grid", placeItems: "center" }}><EmptyState icon="network" title="O proxy está desligado" text="Inicie o proxy para registrar o tráfego HTTP do aparelho. As credenciais são redigidas." actionLabel="Configurar Proxy" onAction={() => setProxyOn(true)} /></div>
          : <DataTable style={{ flex: 1 }} columns={cols} rows={shown} selected={selected} onSelectionChange={setSelected} sort={sort} onSortChange={setSort} newKeys={newKeys}
              onRowContextMenu={(r, e) => { e.preventDefault(); setMenu({ x: e.clientX, y: e.clientY, r }); }}
              empty={<EmptyState compact icon={f ? "search" : "radio-tower"} text={f ? "Nenhuma requisição corresponde ao filtro." : "Aguardando tráfego do aparelho…"} />} />}
      </div>
      <Splitter orientation="horizontal" onDrag={d => { const h = box.current.offsetHeight; setSplit(s => Math.max(.25, Math.min(.8, s + d / h))); }} />
      <div style={{ flex: 1 - split, minHeight: 120, display: "flex", minWidth: 0 }}>
        {!sel ? <div style={{ flex: 1, display: "grid", placeItems: "center" }}><EmptyState compact icon="info" text="Selecione uma requisição para ver os detalhes." /></div> : (
          <>
            <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
              <DetailHeader title="Request" extra={<span className="mb-mono" style={{ fontSize: 10.5, color: methodColor(sel.method) }}>{sel.method}</span>} tabs={[{ value: "h", label: "Headers", count: sel.tunnel ? 0 : 5 }, { value: "b", label: "Body" }]} tab={reqTab} setTab={setReqTab} onCopy={() => onToast("Request copiada")} />
              <div style={{ flex: 1, overflow: "auto" }}>{sel.tunnel ? <EmptyState compact icon="info" text="Sem headers na requisição." /> : reqTab === "h" ? <KV rows={window.MB_DATA.reqHeaders} /> : <Body text={"{\n  \"valor\": 5000,\n  \"parcelas\": 12\n}"} />}</div>
            </div>
            <div className="mb-splitter" />
            <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
              <DetailHeader title="Response" extra={<span className="mb-mono mb-tabular" style={{ fontSize: 10.5, color: statusColor(sel.status) }}>{sel.status || "—"} · {fmtTime(sel.time)}</span>} tabs={[{ value: "h", label: "Headers" }, { value: "b", label: "Body" }]} tab={resTab} setTab={setResTab} onCopy={() => onToast("Response copiada")} />
              <div style={{ flex: 1, overflow: "auto" }}>
                {sel.tunnel ? <EmptyState compact icon="shield-check" title="Túnel HTTPS estabelecido" text="Conexão criptografada de ponta a ponta. 200 Connection Established · 58 ms." />
                  : resTab === "h" ? <KV rows={[["Content-Type", "application/json"], ["Content-Length", String(sel.size)], ["Date", "Thu, 08 Oct 2026 13:02:14 GMT"]]} />
                  : sel.resBody ? <Body text={sel.resBody} /> : <EmptyState compact icon="info" text="Resposta sem corpo." />}
              </div>
            </div>
          </>
        )}
      </div>
      {menu && <Menu x={menu.x} y={menu.y} onClose={() => setMenu(null)} items={[
        { label: "Copiar URL", shortcut: "⌘C", onSelect: () => onToast("URL copiada") },
        { label: "Copiar como cURL", onSelect: () => onToast("cURL copiado") },
        { label: "Gerar Asserção de Contrato", onSelect: () => onToast("Asserção de contrato inserida no código") },
        { separator: true },
        { label: "Exportar HAR…", onSelect: () => onToast("network_traffic.har exportado") }
      ]} />}
    </div>
  );
}

function AnalyticsView({ rows, listening, setListening, source, setSource, filter, selected, setSelected, newKeys, onClear, onToast }) {
  const { AccessoryBar, Button, StatusIndicator, DataTable, EmptyState, PopUpButton, Tooltip, SegmentedControl } = window.MoBaileDesignSystem_ce6669;
  const [tab, setTab] = React.useState("p");
  const [sort, setSort] = React.useState(null);
  const f = filter.trim().toLowerCase();
  const shown = sortRows(rows.filter(r => !f || (r.name + JSON.stringify(r.params)).toLowerCase().includes(f)), sort);
  const sel = rows.find(r => r.id === selected[selected.length - 1]);
  const cols = [
    { key: "time", label: "Hora", width: 100, sortable: true, mono: true, align: "right" },
    { key: "name", label: "Evento", width: "1fr", sortable: true, mono: true, color: () => "var(--accent-text)" },
    { key: "n", label: "Parâmetros", width: 84, align: "right", render: r => Object.keys(r.params).length },
    { key: "o", label: "Origem", width: 100, render: () => "iOS (Firebase)" }
  ];
  const raw = sel && ("2026-10-08 " + sel.time + " BancoPraia[4821:91234] 11.3.0 - [FirebaseAnalytics][I-ACS023051] Logging event: origin, name, params: app, " + sel.name + ", {\n    " + Object.entries(sel.params).map(([k, v]) => k + ": " + v).join(", ") + "\n}");
  return (
    <div className="mb-cq" style={{ display: "flex", flexDirection: "column", height: "100%", minWidth: 0, background: "var(--bg-content)" }}>
      <AccessoryBar>
        <span className="mb-hide-xnarrow"><StatusIndicator status={listening ? "ok" : "off"} label={listening ? "FA Listener ativo" : "FA Listener inativo"} /></span>
        <Tooltip label={listening ? "Para trocar a origem, pare a escuta" : "De onde ler o tagueamento"}>
          <PopUpButton variant="plain" size="small" icon="wand-sparkles" disabled={listening} value={source} onChange={setSource}
            options={[{ value: "auto", label: "Automático" }, { value: "sim", label: "Simulador" }, "-", { value: "cabo", label: "Nenhum iPhone conectado por cabo", disabled: true }]} /></Tooltip>
        <span style={{ flex: 1 }} />
        <Button size="small" icon={listening ? "square" : "radio-tower"} onClick={() => setListening(!listening)}><span className="mb-hide-narrow">{listening ? "Parar Escuta" : "Iniciar Escuta"}</span></Button>
        <Tooltip label="Copia a tabela em TSV para colar no Google Planilhas"><Button size="small" icon="copy" disabled={!rows.length} onClick={() => onToast(rows.length + " eventos copiados como TSV")}><span className="mb-hide-narrow">Copiar TSV</span></Button></Tooltip>
        <Tooltip label="Exporta os eventos em log_obtido.json"><Button size="small" icon="share" disabled={!rows.length} onClick={() => onToast("log_obtido.json exportado")}><span className="mb-hide-narrow">Exportar JSON…</span></Button></Tooltip>
        <Button size="small" variant="plain-destructive" disabled={!rows.length} onClick={onClear}>Limpar</Button>
      </AccessoryBar>
      <div style={{ flex: 1, minHeight: 100, display: "flex", flexDirection: "column" }}>
        {!listening && !rows.length ? <div style={{ flex: 1, display: "grid", placeItems: "center" }}><EmptyState icon="chart-line" title="Nenhum evento capturado" text="Inicie a escuta para ver os eventos de Firebase Analytics em tempo real." actionLabel="Iniciar Escuta" onAction={() => setListening(true)} /></div>
          : <DataTable style={{ flex: 1 }} columns={cols} rows={shown} selected={selected} onSelectionChange={setSelected} sort={sort} onSortChange={setSort} newKeys={newKeys}
              empty={<EmptyState compact icon={f ? "search" : "radio-tower"} text={f ? "Nenhum evento corresponde ao filtro." : "Aguardando eventos…"} />} />}
      </div>
      <div className="mb-splitter mb-splitter--h" />
      <div style={{ flex: 1, minHeight: 120, display: "flex", minWidth: 0 }}>
        {!sel ? <div style={{ flex: 1, display: "grid", placeItems: "center" }}><EmptyState compact icon="info" text="Selecione um evento para ver os detalhes." /></div> : (
          <>
            <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
              <DetailHeader title="Parâmetros" extra={<span className="mb-count">{Object.keys(sel.params).length}</span>} onCopy={() => onToast("Parâmetros copiados")} />
              <div style={{ flex: 1, overflow: "auto" }}>{Object.keys(sel.params).length ? <KV rows={Object.entries(sel.params)} /> : <EmptyState compact text="Evento sem parâmetros." />}</div>
            </div>
            <div className="mb-splitter" />
            <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" }}>
              <DetailHeader title="Log Bruto" extra={<span style={{ fontSize: 11, color: "var(--label-secondary)" }}>iOS (Firebase)</span>} onCopy={() => onToast("Log copiado")} />
              <div style={{ flex: 1, overflow: "auto" }}><Body text={raw} /></div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
Object.assign(window, { NetworkView, AnalyticsView });

// Sidebar do app: Workspace (3 áreas) + Fluxo (passos gravados, reordenáveis por arraste).
const ACTION_ICON = { click: "pointer", send_keys: "keyboard" };
function StepsList({ steps, selected, onSelect, onReorder, onDelete, onReveal, newIds, sidebarSize }) {
  const { SidebarItem, ContextMenu } = window.MoBaileDesignSystem_ce6669;
  const rowH = sidebarSize === "small" ? 24 : sidebarSize === "large" ? 32 : 28;
  const [drag, setDrag] = React.useState(null);
  const start = (e, i) => {
    if (e.button !== 0) return;
    const y0 = e.clientY; let started = false;
    const mv = ev => {
      const dy = ev.clientY - y0;
      if (!started && Math.abs(dy) < 4) return;
      started = true;
      setDrag({ from: i, dy, to: Math.max(0, Math.min(steps.length - 1, i + Math.round(dy / rowH))) });
    };
    const up = () => {
      window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up);
      setDrag(d => { if (d && d.to !== d.from) onReorder(d.from, d.to); return null; });
    };
    window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up);
  };
  const shift = i => {
    if (!drag || i === drag.from) return 0;
    if (drag.from < drag.to && i > drag.from && i <= drag.to) return -rowH;
    if (drag.from > drag.to && i < drag.from && i >= drag.to) return rowH;
    return 0;
  };
  return (
    <div style={{ position: "relative" }}>
      {steps.map((s, i) => {
        const isDrag = drag && drag.from === i;
        const menu = [
          { label: "Mostrar no Código", onSelect: () => onReveal(s.id) },
          { label: "Copiar Locator", shortcut: "⌘C", onSelect: () => navigator.clipboard && navigator.clipboard.writeText(s.varName).catch(() => {}) },
          { separator: true },
          { label: "Mover para Cima", disabled: i === 0, onSelect: () => onReorder(i, i - 1) },
          { label: "Mover para Baixo", disabled: i === steps.length - 1, onSelect: () => onReorder(i, i + 1) },
          { separator: true },
          { label: "Excluir Passo", shortcut: "⌫", destructive: true, onSelect: () => onDelete(s.id) }
        ];
        return (
          <ContextMenu key={s.id} items={menu} onOpen={() => onSelect(s.id)}
            className={newIds.includes(s.id) ? "mb-step-new" : undefined}
            style={{ position: "relative", zIndex: isDrag ? 5 : 1, transform: "translateY(" + (isDrag ? drag.dy : shift(i)) + "px)" + (isDrag ? " scale(1.02)" : ""),
              transition: isDrag ? "none" : "transform var(--spring-smooth-duration) var(--spring-smooth-ease)", boxShadow: isDrag ? "var(--shadow-drag)" : "none", borderRadius: 8, background: isDrag ? "var(--bg-content)" : undefined }}>
            <div onPointerDown={e => start(e, i)} onKeyDown={e => { if (e.key === "Backspace" || e.key === "Delete") onDelete(s.id); }}>
              <SidebarItem icon={s.strategy === "coords" ? "scan-search" : ACTION_ICON[s.action]} iconColor="var(--label-secondary)"
                label={s.action + " " + s.element} selected={selected === s.id} onSelect={() => onSelect(s.id)}
                trailing={s.value ? <span className="mb-mono" style={{ fontSize: 10.5, color: "var(--label-tertiary)" }}>{s.value}</span> : null} />
            </div>
          </ContextMenu>
        );
      })}
    </div>
  );
}

function AppSidebar({ width, section, selectedStep, onSection, onStep, steps, counts, onReorder, onDelete, onRecord, newIds, device, connected, scanning, sidebarSize }) {
  const { Sidebar, SidebarSection, SidebarItem, SidebarBottomBar, StatusIndicator, EmptyState } = window.MoBaileDesignSystem_ce6669;
  const sel = k => !selectedStep && section === k;
  return (
    <Sidebar width={width} header={<div style={{ width: "100%" }} />}
      bottomBar={<SidebarBottomBar actions={[
        { icon: "plus", label: "Gravar Passo", onClick: onRecord, disabled: !connected },
        { icon: "minus", label: "Excluir Passo", onClick: () => selectedStep && onDelete(selectedStep), disabled: !selectedStep }
      ]} status={<StatusIndicator mono={false} status={connected ? "ok" : scanning ? "busy" : "off"} label={connected ? device + " conectado" : scanning ? "Procurando…" : "Sem aparelho"} />} />}>
      <SidebarSection title="Workspace">
        <SidebarItem icon="file-code" iconColor="var(--cat-1)" label="Page Objects" count={counts.steps || null} selected={sel("pageObjects")} onSelect={() => onSection("pageObjects")} />
        <SidebarItem icon="network" iconColor="var(--cat-3)" label="Rede HTTP" count={counts.requests || null} selected={sel("network")} onSelect={() => onSection("network")} />
        <SidebarItem icon="chart-line" iconColor="var(--cat-2)" label="Analytics" count={counts.events || null} selected={sel("analytics")} onSelect={() => onSection("analytics")} />
      </SidebarSection>
      <SidebarSection title="Fluxo · onboarding_credito">
        {steps.length ? <StepsList steps={steps} selected={selectedStep} onSelect={onStep} onReorder={onReorder} onDelete={onDelete} onReveal={onStep} newIds={newIds} sidebarSize={sidebarSize} />
          : <div style={{ padding: "4px 8px", fontSize: 12, color: "var(--label-secondary)" }}>Nenhum passo gravado.</div>}
      </SidebarSection>
    </Sidebar>
  );
}
Object.assign(window, { AppSidebar });

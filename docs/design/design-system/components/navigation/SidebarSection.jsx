import React from "react";
import { Icon } from "../indicators/Icon.jsx";

// Seção da sidebar: cabeçalho discreto; recolhível com seta que aparece no hover.
export function SidebarSection({ title, collapsible = true, defaultCollapsed = false, children }) {
  const [collapsed, setCollapsed] = React.useState(defaultCollapsed);
  const body = React.useRef(null);
  const [h, setH] = React.useState("auto");
  const toggle = () => {
    const el = body.current; const full = el.scrollHeight;
    if (collapsed) { setH(full); setCollapsed(false); setTimeout(() => setH("auto"), 600); }
    else { setH(full); requestAnimationFrame(() => requestAnimationFrame(() => setH(0))); setCollapsed(true); }
  };
  return (
    <div className={"mb-sb-section" + (collapsed ? " is-collapsed" : "")} role="group" aria-label={title}>
      {title && (
        <div className="mb-sb-section__head">
          <span>{title}</span>
          {collapsible && <button type="button" className="mb-sb-section__toggle" aria-expanded={!collapsed} aria-label={(collapsed ? "Mostrar " : "Ocultar ") + title} onClick={toggle}>
            <Icon name="chevron-down" size={12} strokeWidth={2.2} />
          </button>}
        </div>
      )}
      <div ref={body} className="mb-sb-section__body" style={{ height: collapsed && h !== "auto" ? h : h, opacity: collapsed ? 0 : 1 }}>{children}</div>
    </div>
  );
}

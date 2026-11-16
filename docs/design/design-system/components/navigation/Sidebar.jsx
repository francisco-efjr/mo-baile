import React from "react";

// Sidebar de altura total (inclusive sob a toolbar). header = espaço da toolbar (botões da janela + alternar sidebar).
export function Sidebar({ header, search, children, bottomBar, width, style, ariaLabel = "Barra lateral" }) {
  return (
    <nav className="mb-sidebar" aria-label={ariaLabel} style={{ width, ...style }}>
      {header && <div style={{ height: "var(--toolbar-height)", display: "flex", alignItems: "center", flex: "none" }}>{header}</div>}
      {search && <div style={{ padding: "0 10px 4px" }}>{search}</div>}
      <div className="mb-sidebar__scroll" role="tree">{children}</div>
      {bottomBar}
    </nav>
  );
}

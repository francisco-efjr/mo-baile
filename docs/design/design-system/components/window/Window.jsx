import React from "react";

// Janela de app Mac: cantos de 16 pt, sombra maior quando ativa. active=false neutraliza seleções e toolbar.
export function Window({ active = true, width = 1280, height = 800, children, style, ariaLabel }) {
  return (
    <div className="mb-window" data-window-active={active ? "true" : "false"} role="application" aria-label={ariaLabel}
      style={{ width, height, minWidth: "var(--window-min-width)", minHeight: "var(--window-min-height)", ...style }}>
      {children}
    </div>
  );
}

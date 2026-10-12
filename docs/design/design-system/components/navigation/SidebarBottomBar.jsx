import React from "react";
import { Icon } from "../indicators/Icon.jsx";
import { Tooltip } from "../overlays/Tooltip.jsx";

// Barra inferior da sidebar (32 pt, botões 31×18, 1 pt entre botões, 8 pt da borda). size="small" = 22 pt.
// actions: [{icon, label, onClick, disabled}]; status: conteúdo à direita (ex.: estado de sincronização).
export function SidebarBottomBar({ actions = [], status, size = "large" }) {
  return (
    <div className={"mb-bottombar" + (size === "small" ? " mb-bottombar--small" : "")} role="toolbar">
      {actions.map(a => (
        <Tooltip key={a.label} label={a.label}>
          <button type="button" className="mb-bottombar__btn" aria-label={a.label} disabled={a.disabled} onClick={a.onClick}>
            <Icon name={a.icon} size={size === "small" ? 12 : 14} />
          </button>
        </Tooltip>
      ))}
      <div style={{ flex: 1, minWidth: 0, display: "flex", justifyContent: "flex-end", alignItems: "center", gap: 6, fontSize: "var(--text-subheadline)", color: "var(--label-secondary)" }}>{status}</div>
    </div>
  );
}

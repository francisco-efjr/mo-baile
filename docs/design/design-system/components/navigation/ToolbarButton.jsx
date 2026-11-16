import React from "react";
import { Icon } from "../indicators/Icon.jsx";
import { Tooltip } from "../overlays/Tooltip.jsx";

// Item de toolbar só com ícone. label vira tooltip e rótulo acessível. Fundo aparece só no hover.
export const ToolbarButton = React.forwardRef(function ToolbarButton({ icon, label, shortcut, onClick, disabled, on, variant, text, iconSize = 17, ariaPressed }, ref) {
  const cls = "mb-tb-item" + (on ? " is-on" : "") + (variant === "tinted" ? " mb-tb-item--tinted" : "") + (variant === "recording" ? " mb-tb-item--recording" : "");
  return (
    <Tooltip label={shortcut ? label + "  " + shortcut : label}>
      <button ref={ref} type="button" className={cls} aria-label={label} aria-pressed={ariaPressed} disabled={disabled} onClick={onClick}
        style={text ? { padding: "0 12px" } : undefined}>
        {icon && <Icon name={icon} size={iconSize} />}
        {text && <span style={{ fontWeight: 500 }}>{text}</span>}
      </button>
    </Tooltip>
  );
});

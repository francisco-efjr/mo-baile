import React from "react";
import { Icon } from "../indicators/Icon.jsx";

// Item da sidebar: ícone colorido à esquerda, rótulo truncado (tooltip com texto completo), contador à direita.
export function SidebarItem({ icon, iconColor, label, sublabel, count, trailing, selected, onSelect, onContextMenu, indent, disabled, onKeyDown }) {
  const ref = React.useRef(null);
  const [trunc, setTrunc] = React.useState(false);
  React.useLayoutEffect(() => {
    const el = ref.current && ref.current.querySelector(".mb-sb-item__label");
    if (el) setTrunc(el.scrollWidth > el.clientWidth);
  });
  return (
    <div ref={ref} role="treeitem" aria-selected={!!selected} aria-disabled={disabled || undefined} tabIndex={selected ? 0 : -1}
      title={trunc ? label : undefined}
      className={"mb-sb-item" + (selected ? " is-selected" : "") + (indent ? " is-indented" : "")}
      style={{ "--sb-icon": iconColor, opacity: disabled ? .42 : 1 }}
      onMouseDown={() => !disabled && onSelect && onSelect()} onContextMenu={onContextMenu}
      onKeyDown={e => { if (e.key === "Enter" && onSelect) onSelect(); onKeyDown && onKeyDown(e); }}>
      {icon && <Icon name={icon} size={16} />}
      <span className="mb-sb-item__label">{label}{sublabel && <span className="mb-sb-item__sub"> {sublabel}</span>}</span>
      {trailing}
      {count != null && <span className="mb-count">{count}</span>}
    </div>
  );
}

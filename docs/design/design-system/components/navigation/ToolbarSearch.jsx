import React from "react";
import { Icon } from "../indicators/Icon.jsx";
import { Tooltip } from "../overlays/Tooltip.jsx";

// Buscar: começa como botão com lupa e se funde (morph) em campo ao clicar ou com ⌘F.
export function ToolbarSearch({ value, onChange, placeholder = "Buscar", open: openProp, onOpenChange, inputRef, width = 220 }) {
  const [openState, setOpen] = React.useState(false);
  const open = openProp != null ? openProp : openState;
  const local = React.useRef(null);
  const ref = inputRef || local;
  const set = v => { setOpen(v); onOpenChange && onOpenChange(v); };
  React.useEffect(() => { if (open && ref.current) setTimeout(() => ref.current && ref.current.focus(), 30); }, [open]);
  return (
    <div className={"mb-tb-search mb-glass" + (open ? " is-open" : "")} style={open ? { width } : undefined}>
      <Tooltip label={open ? null : "Buscar  ⌘F"}>
        <button type="button" className="mb-tb-item" aria-label="Buscar" style={{ width: 32, margin: 2, height: 32 }} onClick={() => set(true)}>
          <Icon name="search" size={16} />
        </button>
      </Tooltip>
      {open && <input ref={ref} value={value} placeholder={placeholder} spellCheck={false} aria-label={placeholder}
        onChange={e => onChange && onChange(e.target.value)}
        onBlur={() => !value && set(false)}
        onKeyDown={e => { if (e.key === "Escape") { e.stopPropagation(); onChange && onChange(""); set(false); } }} />}
    </div>
  );
}

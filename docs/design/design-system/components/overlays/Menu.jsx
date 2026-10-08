import React from "react";
import { Icon } from "../indicators/Icon.jsx";

export function portal(node) {
  const RD = typeof window !== "undefined" && window.ReactDOM;
  const host = typeof document !== "undefined" && (document.querySelector("[data-mb-portal]") || document.body);
  return RD && RD.createPortal && host ? RD.createPortal(node, host) : node;
}

// Menu (dropdown ou contexto). Aparece instantaneamente; some com fade curto.
// items: [{label, shortcut, icon, checked, disabled, destructive, onSelect} | {separator:true} | {header:"…"}]
export function Menu({ x = 0, y = 0, items = [], onClose, minWidth = 200, ariaLabel }) {
  const ref = React.useRef(null);
  const [active, setActive] = React.useState(-1);
  const [leaving, setLeaving] = React.useState(false);
  const [pos, setPos] = React.useState({ x, y });
  const close = React.useCallback(fn => {
    setLeaving(true);
    setTimeout(() => { onClose && onClose(); fn && fn(); }, 150);
  }, [onClose]);
  const actionable = items.map((it, i) => (!it.separator && !it.header && !it.disabled ? i : -1)).filter(i => i >= 0);
  React.useLayoutEffect(() => {
    const el = ref.current; if (!el) return;
    const r = el.getBoundingClientRect();
    setPos({ x: Math.min(x, window.innerWidth - r.width - 6), y: y + r.height > window.innerHeight - 6 ? Math.max(6, y - r.height) : y });
    el.focus();
  }, [x, y]);
  React.useEffect(() => {
    const down = e => { if (ref.current && !ref.current.contains(e.target)) close(); };
    const t = setTimeout(() => document.addEventListener("mousedown", down), 0);
    return () => { clearTimeout(t); document.removeEventListener("mousedown", down); };
  }, [close]);
  const onKey = e => {
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); }
    else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const k = actionable.indexOf(active), d = e.key === "ArrowDown" ? 1 : -1;
      setActive(actionable[(k + d + actionable.length) % actionable.length]);
    } else if (e.key === "Enter" && active >= 0) { e.preventDefault(); const it = items[active]; close(it.onSelect); }
  };
  const hasChecks = items.some(it => it.checked != null);
  return portal(
    <div ref={ref} role="menu" aria-label={ariaLabel} tabIndex={-1} onKeyDown={onKey} onContextMenu={e => e.preventDefault()}
      className={"mb-menu" + (leaving ? " is-leaving" : "")} style={{ position: "fixed", left: pos.x, top: pos.y, minWidth }}>
      {items.map((it, i) => it.separator ? <div key={i} className="mb-menu__sep" role="separator" />
        : it.header ? <div key={i} className="mb-menu__header">{it.header}</div>
        : (
          <div key={i} role="menuitem" aria-disabled={it.disabled || undefined}
            className={"mb-menu__item" + (it.disabled ? " is-disabled" : "") + (it.destructive ? " is-destructive" : "") + (i === active ? " is-active" : "")}
            onMouseEnter={() => setActive(it.disabled ? -1 : i)} onMouseLeave={() => setActive(-1)}
            onClick={() => !it.disabled && close(it.onSelect)}>
            {(hasChecks || it.icon) && <span className="mb-menu__check">{it.checked ? <Icon name="check" size={12} strokeWidth={2.4} /> : it.icon ? <Icon name={it.icon} size={14} /> : null}</span>}
            <span className="mb-menu__label">{it.label}</span>
            {it.shortcut && <span className="mb-menu__kbd">{it.shortcut}</span>}
          </div>
        ))}
    </div>
  );
}

// Envolve qualquer item manipulável: clique direito abre o menu de contexto.
export function ContextMenu({ items, children, onOpen, style, className }) {
  const [at, setAt] = React.useState(null);
  return (
    <div style={style} className={className} onContextMenu={e => { e.preventDefault(); e.stopPropagation(); onOpen && onOpen(); setAt({ x: e.clientX, y: e.clientY }); }}>
      {children}
      {at && <Menu x={at.x} y={at.y} items={typeof items === "function" ? items() : items} onClose={() => setAt(null)} />}
    </div>
  );
}

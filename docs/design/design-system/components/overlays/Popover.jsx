import React from "react";
import { portal } from "./Menu.jsx";

// Popover com seta apontando para a origem. Surge com escala 95%→100% + fade (mola snappy). Fecha ao clicar fora ou Esc.
export function Popover({ open, anchorRef, onClose, placement = "bottom", width = 280, children, ariaLabel }) {
  const ref = React.useRef(null);
  const [pos, setPos] = React.useState(null);
  React.useLayoutEffect(() => {
    if (!open || !anchorRef || !anchorRef.current) return;
    const a = anchorRef.current.getBoundingClientRect();
    const cx = a.left + a.width / 2;
    let left = Math.max(8, Math.min(cx - width / 2, window.innerWidth - width - 8));
    if (placement === "bottom") setPos({ left, top: a.bottom + 10, arrowX: cx - left - 9, origin: (cx - left) + "px 0" });
    else setPos({ left, bottom: window.innerHeight - a.top + 10, arrowX: cx - left - 9, origin: (cx - left) + "px 100%" });
  }, [open, placement, width]);
  React.useEffect(() => {
    if (!open) return;
    const down = e => { if (ref.current && !ref.current.contains(e.target) && !(anchorRef.current && anchorRef.current.contains(e.target))) onClose && onClose(); };
    const key = e => { if (e.key === "Escape") onClose && onClose(); };
    document.addEventListener("mousedown", down); document.addEventListener("keydown", key);
    return () => { document.removeEventListener("mousedown", down); document.removeEventListener("keydown", key); };
  }, [open, onClose]);
  if (!open || !pos) return null;
  return portal(
    <div ref={ref} role="dialog" aria-label={ariaLabel} className="mb-popover"
      style={{ position: "fixed", left: pos.left, top: pos.top, bottom: pos.bottom, width, "--origin": pos.origin }}>
      <span className="mb-popover__arrow" style={placement === "bottom" ? { top: -9, left: pos.arrowX } : { bottom: -9, left: pos.arrowX, transform: "rotate(180deg)" }} />
      {children}
    </div>
  );
}

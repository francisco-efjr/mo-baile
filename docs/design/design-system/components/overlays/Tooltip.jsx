import React from "react";
import { portal } from "./Menu.jsx";

// Tooltip com atraso (~700 ms) — obrigatório em todo botão só com ícone.
export function Tooltip({ label, children, delay = 700 }) {
  const [at, setAt] = React.useState(null);
  const t = React.useRef(0);
  if (!label) return children;
  const enter = e => {
    const r = e.currentTarget.getBoundingClientRect();
    clearTimeout(t.current);
    t.current = setTimeout(() => setAt({ x: r.left + r.width / 2, y: r.bottom + 6 }), delay);
  };
  const leave = () => { clearTimeout(t.current); setAt(null); };
  return (
    <span style={{ display: "inline-flex" }} onMouseEnter={enter} onMouseLeave={leave} onMouseDown={leave}>
      {children}
      {at && portal(<div className="mb-tooltip" role="tooltip" style={{ left: at.x, top: at.y, transform: "translateX(-50%)" }}>{label}</div>)}
    </span>
  );
}

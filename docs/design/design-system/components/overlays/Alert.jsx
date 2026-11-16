import React from "react";
import { Button } from "../controls/Button.jsx";

// Alerta: só para decisões importantes ou destrutivas. A ação destrutiva é nomeada pelo verbo e nunca é o botão padrão.
// buttons: [{label, role:"default"|"cancel"|"destructive", onClick}]
export function Alert({ open, title, message, iconSrc, buttons = [], onCancel }) {
  const ref = React.useRef(null);
  React.useEffect(() => { if (open && ref.current) ref.current.focus(); }, [open]);
  if (!open) return null;
  const def = buttons.find(b => b.role === "default");
  const cancel = buttons.find(b => b.role === "cancel");
  const onKey = e => {
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); (cancel && cancel.onClick || onCancel || (() => {}))(); }
    if (e.key === "Enter" && def) { e.preventDefault(); def.onClick(); }
  };
  return (
    <div onKeyDown={onKey} style={{ position: "absolute", inset: 0, zIndex: 850, display: "grid", placeItems: "center", background: "var(--scrim)", animation: "mb-fade 180ms linear both" }}>
      <div ref={ref} tabIndex={-1} role="alertdialog" aria-label={title} className="mb-alert mb-popover" style={{ position: "relative" }}>
        {iconSrc && <img className="mb-alert__icon" src={iconSrc} alt="" />}
        <h3>{title}</h3>
        {message && <p>{message}</p>}
        <div className="mb-alert__buttons">
          {buttons.map(b => (
            <Button key={b.label} variant={b.role === "default" ? "default" : b.role === "destructive" ? "destructive" : "secondary"} onClick={b.onClick}>{b.label}</Button>
          ))}
        </div>
      </div>
    </div>
  );
}

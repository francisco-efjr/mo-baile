import React from "react";

// Sheet: tarefa modal da janela. Desce da base da toolbar e escurece a janela. Esc cancela, Return confirma.
// Renderize dentro do container da janela (position: relative).
export function Sheet({ open, onClose, onConfirm, width = 560, children, footer, ariaLabel }) {
  const [mounted, setMounted] = React.useState(open);
  const [shown, setShown] = React.useState(false);
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (open) { setMounted(true); requestAnimationFrame(() => requestAnimationFrame(() => setShown(true))); }
    else { setShown(false); const t = setTimeout(() => setMounted(false), 600); return () => clearTimeout(t); }
  }, [open]);
  React.useEffect(() => { if (shown && ref.current) ref.current.focus(); }, [shown]);
  if (!mounted) return null;
  const onKey = e => {
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); onClose && onClose(); }
    if (e.key === "Enter" && onConfirm && e.target.tagName !== "TEXTAREA" && e.target.tagName !== "BUTTON") { e.preventDefault(); onConfirm(); }
  };
  return (
    <div className={"mb-sheet-layer" + (shown ? " is-open" : "")} onKeyDown={onKey}>
      <div className="mb-sheet-scrim" />
      <div ref={ref} tabIndex={-1} role="dialog" aria-modal="true" aria-label={ariaLabel} className="mb-sheet" style={{ width }}>
        <div className="mb-sheet__body">{children}</div>
        {footer && <div className="mb-sheet__footer">{footer}</div>}
      </div>
    </div>
  );
}

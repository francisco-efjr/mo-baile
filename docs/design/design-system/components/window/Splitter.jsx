import React from "react";

// Divisor arrastável entre colunas (1 px; área de arraste de 9 px; cursor de redimensionar).
export function Splitter({ onDrag, onDragEnd, orientation = "vertical", ariaLabel = "Redimensionar" }) {
  const down = e => {
    e.preventDefault();
    let last = orientation === "vertical" ? e.clientX : e.clientY;
    const move = ev => { const p = orientation === "vertical" ? ev.clientX : ev.clientY; onDrag && onDrag(p - last); last = p; };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); document.body.style.cursor = ""; onDragEnd && onDragEnd(); };
    document.body.style.cursor = orientation === "vertical" ? "col-resize" : "row-resize";
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  };
  return <div role="separator" aria-orientation={orientation} aria-label={ariaLabel} className={"mb-splitter" + (orientation === "horizontal" ? " mb-splitter--h" : "")} onPointerDown={down} />;
}

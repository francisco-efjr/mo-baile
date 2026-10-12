import React from "react";

// Cápsula de Liquid Glass que agrupa itens relacionados. tinted só para o elemento primário da tela.
export function ToolbarGroup({ children, tinted, scrolled, ariaLabel, style }) {
  return (
    <div role="group" aria-label={ariaLabel} style={style}
      className={"mb-tb-group " + (tinted ? "mb-tb-group--tinted" : "mb-glass") + (scrolled ? " is-scrolled" : "")}>
      {children}
    </div>
  );
}

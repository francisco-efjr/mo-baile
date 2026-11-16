import React from "react";

// Barra acessória: controles secundários do conteúdo selecionado. Fica só sobre a coluna de conteúdo.
export function AccessoryBar({ children, style }) {
  return <div className="mb-accessory" role="toolbar" style={style}>{children}</div>;
}

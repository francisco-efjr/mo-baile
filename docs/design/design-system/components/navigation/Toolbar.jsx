import React from "react";

// Toolbar unificada: botões da janela, título da seção e itens numa única faixa.
export function Toolbar({ children, style, className = "" }) {
  return <div className={"mb-toolbar " + className} role="toolbar" style={style}>{children}</div>;
}

// Título = nome da seção atual (nunca o nome do app) + subtítulo opcional.
export function ToolbarTitle({ title, subtitle }) {
  return (
    <div className="mb-toolbar__title">
      <b className="mb-truncate">{title}</b>
      {subtitle && <span className="mb-truncate mb-tabular">{subtitle}</span>}
    </div>
  );
}

export function ToolbarSpacer() { return <div className="mb-toolbar__spacer" />; }

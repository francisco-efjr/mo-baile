import React from "react";

// Indicador de progresso do sistema: barra (determinada ou não) ou círculo giratório.
export function ProgressIndicator({ kind = "bar", value, size = 16, tone, ariaLabel = "Carregando" }) {
  if (kind === "spinner") return <span className="mb-spinner" role="progressbar" aria-label={ariaLabel} style={{ width: size, height: size }} />;
  const ind = value == null;
  return (
    <div className={"mb-progress" + (ind ? " mb-progress--indeterminate" : "")} role="progressbar" aria-label={ariaLabel}
      aria-valuenow={ind ? undefined : Math.round(value * 100)} aria-valuemin={0} aria-valuemax={100}>
      <div className="mb-progress__bar" style={{ width: ind ? undefined : (value * 100) + "%", background: tone === "success" ? "var(--success-fill)" : tone === "error" ? "var(--destructive-fill)" : undefined }} />
    </div>
  );
}

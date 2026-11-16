import React from "react";

// Switch: só para ligar/desligar um recurso inteiro de forma destacada. Em formulários, prefira Checkbox.
export function Switch({ checked, onChange, disabled, size = "regular", ariaLabel, label }) {
  const sw = (
    <button type="button" role="switch" aria-checked={!!checked} aria-label={ariaLabel || label} disabled={disabled}
      className={"mb-switch" + (size === "small" ? " mb-switch--small" : "")} onClick={() => onChange && onChange(!checked)} />
  );
  if (!label) return sw;
  return <span style={{ display: "inline-flex", alignItems: "center", gap: 8, opacity: disabled ? .42 : 1 }}>{label}{sw}</span>;
}

import React from "react";

// Contador: texto secundário com algarismos tabulares. variant="pill" só dentro de controles segmentados.
export function CountBadge({ value, variant = "text", ariaLabel }) {
  if (value == null) return null;
  return <span className={"mb-count" + (variant === "pill" ? " mb-count--pill" : "")} aria-label={ariaLabel}>{value}</span>;
}

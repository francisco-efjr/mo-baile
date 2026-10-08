import React from "react";

const NAMES = { W: "Janela", V: "Contêiner", T: "Texto", I: "Campo", B: "Botão" };

// Chip de tipo de nó da hierarquia: letra + cor (W, V, T, I, B).
export function TypeChip({ type = "V" }) {
  return <span className={"mb-chip mb-chip--" + type} title={NAMES[type]} aria-label={NAMES[type]}>{type}</span>;
}

import React from "react";
import { Icon } from "./Icon.jsx";

const ICON = { ok: "circle-check", busy: "refresh-cw", warn: "triangle-alert", error: "circle-x", off: "minus" };
const WORD = { ok: "ok", busy: "ocupado", warn: "atenção", error: "erro", off: "inativo" };

// Estado de um serviço (WDA, ADB, Proxy, FA). Cor + forma do ícone + texto: nunca só cor.
export function StatusIndicator({ status = "off", label, detail, mono = true }) {
  return (
    <span className={"mb-status mb-status--" + status} title={(label ? label + " — " : "") + WORD[status] + (detail ? ". " + detail : "")}>
      <Icon name={ICON[status]} size={11} strokeWidth={2.2} />
      <span style={{ fontFamily: mono ? "var(--font-mono)" : undefined }}>{label}</span>
    </span>
  );
}

import React from "react";
import { Icon } from "../indicators/Icon.jsx";
import { Button } from "../controls/Button.jsx";
import { ProgressIndicator } from "../indicators/ProgressIndicator.jsx";

const MARK = { ok: ["circle-check", "var(--success)"], warn: ["triangle-alert", "var(--warning)"], error: ["circle-x", "var(--destructive)"], off: ["minus", "var(--label-tertiary)"] };

// Cartão de diagnóstico por plataforma (iOS · WebDriverAgent / Android · ADB). checks=null → verificando.
export function DiagnosticCard({ platform = "ios", title, ready, checks, actionLabel, onAction, actionDisabled, busy, footer }) {
  return (
    <div className="mb-card" style={{ display: "flex", flexDirection: "column", gap: 12, minHeight: 236 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span aria-hidden="true" style={{ width: 8, height: 8, borderRadius: 4, background: platform === "ios" ? "var(--platform-ios)" : "var(--platform-android)" }} />
        <b style={{ fontWeight: 600, flex: 1 }}>{title || (platform === "ios" ? "iOS" : "Android")}</b>
        {ready && <span style={{ display: "inline-flex", alignItems: "center", gap: 3, fontSize: 11, color: "var(--success)" }}><Icon name="check" size={11} strokeWidth={2.6} />Pronto</span>}
      </div>
      {checks ? (
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {checks.map(c => (
            <div key={c.label} style={{ display: "flex", gap: 8, alignItems: "flex-start" }}>
              <Icon name={MARK[c.state][0]} size={14} color={MARK[c.state][1]} strokeWidth={2} style={{ marginTop: 1 }} />
              <div style={{ minWidth: 0 }}>
                <div>{c.label}</div>
                {c.detail && <div style={{ fontSize: 11, lineHeight: "14px", color: "var(--label-secondary)", textWrap: "pretty" }}>{c.detail}</div>}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div style={{ display: "flex", alignItems: "center", gap: 6, color: "var(--label-secondary)", fontSize: 12 }}>
          <ProgressIndicator kind="spinner" size={14} /> Verificando ambiente…
        </div>
      )}
      <div style={{ flex: 1 }} />
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        {actionLabel && <Button variant="default" disabled={actionDisabled || busy} onClick={onAction}>{busy ? "Iniciando…" : actionLabel}</Button>}
        {footer}
      </div>
    </div>
  );
}

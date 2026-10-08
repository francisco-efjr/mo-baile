import React from "react";
import { Icon } from "../indicators/Icon.jsx";
import { Button } from "../controls/Button.jsx";
import { ProgressIndicator } from "../indicators/ProgressIndicator.jsx";

// Estado vazio / carregando: ícone discreto, uma frase e (opcional) a ação principal.
export function EmptyState({ icon = "info", title, text, actionLabel, onAction, loading, compact, children }) {
  return (
    <div className="mb-empty" style={compact ? { padding: 16, gap: 4 } : undefined}>
      {loading ? <ProgressIndicator kind="spinner" size={compact ? 16 : 22} /> : <Icon name={icon} size={compact ? 22 : 32} strokeWidth={1.4} className="mb-empty__icon" />}
      {title && <p className="mb-empty__title" style={compact ? { fontSize: 13 } : undefined}>{title}</p>}
      {text && <p className="mb-empty__text" style={compact ? { fontSize: 12 } : undefined}>{text}</p>}
      {actionLabel && <Button onClick={onAction}>{actionLabel}</Button>}
      {children}
    </div>
  );
}

// Erro em linha, perto de onde aconteceu: o que houve e o que fazer.
export function InlineError({ title, text, actionLabel, onAction }) {
  return (
    <div className="mb-inline-error" role="alert">
      <Icon name="circle-alert" size={14} strokeWidth={2} style={{ marginTop: 1 }} />
      <div style={{ flex: 1 }}><b>{title}</b>{text && <span style={{ color: "var(--label-primary)" }}> {text}</span>}</div>
      {actionLabel && <Button size="small" onClick={onAction}>{actionLabel}</Button>}
    </div>
  );
}

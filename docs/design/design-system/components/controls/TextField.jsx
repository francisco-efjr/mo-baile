import React from "react";

export function TextField({ value, onChange, placeholder, invalid, mono, width, disabled, ariaLabel, onKeyDown, type = "text" }) {
  return (
    <input type={type} className={"mb-field" + (invalid ? " is-invalid" : "")} value={value} placeholder={placeholder} disabled={disabled}
      aria-label={ariaLabel} aria-invalid={invalid || undefined} spellCheck={!mono} onKeyDown={onKeyDown}
      style={{ width, fontFamily: mono ? "var(--font-mono)" : undefined, opacity: disabled ? .42 : 1 }}
      onChange={e => onChange && onChange(e.target.value)} />
  );
}

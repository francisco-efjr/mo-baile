import React from "react";
import { Icon } from "../indicators/Icon.jsx";

export function Checkbox({ checked, onChange, label, help, disabled }) {
  return (
    <span className="mb-check" style={{ opacity: disabled ? .42 : 1 }} onClick={() => !disabled && onChange && onChange(!checked)}>
      <button type="button" role="checkbox" aria-checked={!!checked} disabled={disabled} className="mb-check__box" onClick={e => e.stopPropagation() || (onChange && onChange(!checked))}>
        {checked && <Icon name="check" size={11} strokeWidth={3} />}
      </button>
      {label && <span>{label}{help && <span className="mb-check__help">{help}</span>}</span>}
    </span>
  );
}

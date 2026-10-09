import React from "react";
import { Icon } from "../indicators/Icon.jsx";

export function SearchField({ value, onChange, placeholder = "Buscar", shortcut, autoFocus, inputRef, width, onKeyDown, ariaLabel }) {
  return (
    <label className="mb-search" style={{ width }}>
      <Icon name="search" size={13} />
      <input ref={inputRef} value={value} placeholder={placeholder} autoFocus={autoFocus} aria-label={ariaLabel || placeholder}
        spellCheck={false} onKeyDown={e => { if (e.key === "Escape" && value) { e.stopPropagation(); onChange && onChange(""); } onKeyDown && onKeyDown(e); }}
        onChange={e => onChange && onChange(e.target.value)} />
      {value ? <button type="button" className="mb-search__clear" aria-label="Limpar busca" onClick={() => onChange && onChange("")}><Icon name="x" size={9} strokeWidth={3} /></button>
        : shortcut ? <span className="mb-kbd">{shortcut}</span> : null}
    </label>
  );
}

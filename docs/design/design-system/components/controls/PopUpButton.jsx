import React from "react";
import { Icon } from "../indicators/Icon.jsx";
import { Menu } from "../overlays/Menu.jsx";

// Menu pop-up: escolha entre muitas opções. options: [{value,label,disabled}] ou "-" para separador.
export function PopUpButton({ options = [], value, onChange, label, prefix, icon, variant = "bordered", size = "regular", disabled, ariaLabel, minWidth, extraItems = [] }) {
  const ref = React.useRef(null);
  const [menu, setMenu] = React.useState(null);
  const cur = options.find(o => o !== "-" && o.value === value);
  const open = () => {
    const r = ref.current.getBoundingClientRect();
    setMenu({ x: r.left, y: r.bottom + 4 });
  };
  const items = options.map(o => o === "-" ? { separator: true } : { label: o.label, checked: o.value === value, disabled: o.disabled, onSelect: () => onChange && onChange(o.value) }).concat(extraItems);
  return (
    <>
      <button ref={ref} type="button" aria-haspopup="menu" aria-label={ariaLabel} disabled={disabled} onClick={open}
        style={{ minWidth }} className={["mb-popup", variant === "plain" && "mb-popup--plain", size === "small" && "mb-popup--small"].filter(Boolean).join(" ")}>
        {icon && <Icon name={icon} size={14} />}
        {prefix && <span style={{ color: "var(--label-secondary)" }}>{prefix}</span>}
        <span className="mb-truncate" style={{ flex: 1, textAlign: "left" }}>{label || (cur && cur.label)}</span>
        <Icon name="chevrons-up-down" size={12} className="mb-popup__chev" />
      </button>
      {menu && <Menu x={menu.x} y={menu.y} items={items} onClose={() => setMenu(null)} />}
    </>
  );
}

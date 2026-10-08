import React from "react";
import { Icon } from "../indicators/Icon.jsx";

export function SegmentedControl({ items = [], value, onChange, size = "regular", disabled, ariaLabel, className = "" }) {
  const ref = React.useRef(null);
  const [thumb, setThumb] = React.useState(null);
  const idx = Math.max(0, items.findIndex(it => (typeof it === "string" ? it : it.value) === value));
  React.useLayoutEffect(() => {
    const el = ref.current && ref.current.querySelectorAll(".mb-seg__item")[idx];
    if (el) setThumb({ left: el.offsetLeft, width: el.offsetWidth });
  }, [idx, items.length, size]);
  const onKey = e => {
    if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
    e.preventDefault();
    const n = (idx + (e.key === "ArrowRight" ? 1 : -1) + items.length) % items.length;
    const it = items[n]; onChange && onChange(typeof it === "string" ? it : it.value);
  };
  return (
    <div ref={ref} role="radiogroup" aria-label={ariaLabel} tabIndex={0} onKeyDown={onKey}
      className={["mb-seg", size !== "regular" && "mb-seg--" + size, disabled && "is-disabled", className].filter(Boolean).join(" ")}>
      {thumb && <span className="mb-seg__thumb" style={{ left: thumb.left, width: thumb.width }} />}
      {items.map((it, i) => {
        const o = typeof it === "string" ? { value: it, label: it } : it;
        return (
          <button key={o.value} type="button" role="radio" aria-checked={i === idx} tabIndex={-1} title={o.tooltip}
            className={"mb-seg__item" + (i === idx ? " is-selected" : "")} onClick={() => onChange && onChange(o.value)}>
            {o.icon && <Icon name={o.icon} size={size === "small" ? 12 : 14} />}
            {o.label}
            {o.count != null && <span className="mb-count mb-count--pill">{o.count}</span>}
          </button>
        );
      })}
    </div>
  );
}

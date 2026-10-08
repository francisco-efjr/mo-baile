import React from "react";
import { Menu } from "../overlays/Menu.jsx";

// Barra de menus do macOS simulada. menus: [{title, items:[…itens de Menu]}]. O primeiro é o menu do app (negrito).
export function MenuBar({ menus = [], right }) {
  const [open, setOpen] = React.useState(null);
  const refs = React.useRef([]);
  const at = i => { const r = refs.current[i].getBoundingClientRect(); return { x: r.left, y: r.bottom + 2 }; };
  return (
    <div className="mb-menubar" role="menubar">
      {menus.map((m, i) => (
        <button key={m.title} ref={el => (refs.current[i] = el)} type="button" role="menuitem" aria-haspopup="menu" aria-expanded={open === i}
          className={"mb-menubar__item" + (i === 0 ? " is-app" : "") + (open === i ? " is-open" : "")}
          onMouseDown={e => { e.preventDefault(); setOpen(open === i ? null : i); }}
          onMouseEnter={() => open != null && open !== i && setOpen(i)}>
          {m.title}
        </button>
      ))}
      <div className="mb-menubar__right">{right}</div>
      {open != null && <Menu key={open} {...at(open)} items={menus[open].items} minWidth={220} ariaLabel={menus[open].title} onClose={() => setOpen(null)} />}
    </div>
  );
}

import React from "react";
import { Icon } from "../indicators/Icon.jsx";

// Tabela: cabeçalhos clicáveis para ordenar, colunas redimensionáveis, seleção com ⌘ e ⇧, duplo clique abre, setas navegam.
// columns: [{key,label,width,minWidth,align,sortable,mono,render(row)}]; width numérico em px ou "1fr".
export function DataTable({ columns = [], rows = [], rowKey = "id", selected = [], onSelectionChange, onOpen, sort, onSortChange, onRowContextMenu, newKeys = [], focused = true, empty, style }) {
  const [widths, setWidths] = React.useState(() => columns.map(c => c.width || "1fr"));
  const anchor = React.useRef(null);
  const tpl = widths.map((w, i) => typeof w === "number" ? w + "px" : "minmax(" + (columns[i].minWidth || 80) + "px," + w + ")").join(" ");
  const keys = rows.map(r => r[rowKey]);
  const sel = new Set(selected);
  const select = (k, e) => {
    let next;
    if (e && (e.metaKey || e.ctrlKey)) { next = new Set(sel); next.has(k) ? next.delete(k) : next.add(k); anchor.current = k; }
    else if (e && e.shiftKey && anchor.current != null) {
      const a = keys.indexOf(anchor.current), b = keys.indexOf(k);
      next = new Set(keys.slice(Math.min(a, b), Math.max(a, b) + 1));
    } else { next = new Set([k]); anchor.current = k; }
    onSelectionChange && onSelectionChange([...next]);
  };
  const onKey = e => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp" && e.key !== "Enter") return;
    e.preventDefault();
    const cur = keys.indexOf(selected[selected.length - 1]);
    if (e.key === "Enter") { cur >= 0 && onOpen && onOpen(rows[cur]); return; }
    const n = Math.max(0, Math.min(keys.length - 1, cur + (e.key === "ArrowDown" ? 1 : -1)));
    select(keys[n], e.shiftKey ? e : null);
  };
  const startResize = (i, e) => {
    e.preventDefault(); e.stopPropagation();
    const th = e.currentTarget.parentElement; let w = th.offsetWidth, x = e.clientX;
    const move = ev => { w = Math.max(columns[i].minWidth || 48, w + ev.clientX - x); x = ev.clientX; setWidths(ws => ws.map((v, j) => j === i ? w : v)); };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  };
  return (
    <div className={"mb-table" + (focused ? "" : " is-unfocused")} role="grid" tabIndex={0} onKeyDown={onKey} style={style}>
      <div className="mb-table__head" style={{ gridTemplateColumns: tpl, padding: "0 4px" }} role="row">
        {columns.map((c, i) => {
          const active = sort && sort.key === c.key;
          return (
            <div key={c.key} role="columnheader" aria-sort={active ? (sort.dir === "asc" ? "ascending" : "descending") : undefined}
              className={"mb-table__th" + (c.sortable ? " is-sortable" : "") + (c.align === "right" ? " is-right" : "")}
              onClick={() => c.sortable && onSortChange && onSortChange({ key: c.key, dir: active && sort.dir === "asc" ? "desc" : "asc" })}>
              <span className="mb-truncate">{c.label}</span>
              {active && <Icon name={sort.dir === "asc" ? "chevron-up" : "chevron-down"} size={11} strokeWidth={2.2} />}
              {i < columns.length - 1 && <span className="mb-table__resize" onPointerDown={e => startResize(i, e)} onClick={e => e.stopPropagation()} />}
            </div>
          );
        })}
      </div>
      <div className="mb-table__body">
        {rows.length === 0 && empty}
        {rows.map(r => {
          const k = r[rowKey];
          return (
            <div key={k} role="row" aria-selected={sel.has(k)} className={"mb-table__row" + (sel.has(k) ? " is-selected" : "") + (newKeys.includes(k) ? " is-new" : "")}
              style={{ gridTemplateColumns: tpl }} onMouseDown={e => select(k, e)} onDoubleClick={() => onOpen && onOpen(r)}
              onContextMenu={e => { if (!sel.has(k)) select(k); onRowContextMenu && onRowContextMenu(r, e); }}>
              {columns.map(c => (
                <div key={c.key} role="gridcell" className={"mb-table__td" + (c.align === "right" ? " is-right mb-tabular" : "")}
                  style={{ fontFamily: c.mono ? "var(--font-mono)" : undefined, color: c.color ? c.color(r) : undefined }}>
                  {c.render ? c.render(r) : r[c.key]}
                </div>
              ))}
            </div>
          );
        })}
      </div>
    </div>
  );
}

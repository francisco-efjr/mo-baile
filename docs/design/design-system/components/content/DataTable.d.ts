import * as React from "react";

/**
 * Tabela Mac: ordenar pelo cabeçalho, colunas redimensionáveis, ⌘/⇧ multi-seleção, duplo clique abre, setas navegam.
 */
export interface DataTableProps {
  columns: Array<{ key: string; label: string; width?: number | string; minWidth?: number; align?: "left" | "right"; sortable?: boolean; mono?: boolean; render?: (row: any) => React.ReactNode; color?: (row: any) => string }>;
  rows: any[]; rowKey?: string; selected?: any[]; onSelectionChange?: (keys: any[]) => void; onOpen?: (row: any) => void;
  sort?: { key: string; dir: "asc" | "desc" }; onSortChange?: (s: { key: string; dir: "asc" | "desc" }) => void; onRowContextMenu?: (row: any, e: any) => void;
  newKeys?: any[]; focused?: boolean; empty?: React.ReactNode; style?: React.CSSProperties;
}

export declare function DataTable(props: DataTableProps): JSX.Element | null;

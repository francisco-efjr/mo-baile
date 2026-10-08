import * as React from "react";

/**
 * Sidebar de altura total, até a borda da janela, com busca opcional e barra inferior.
 */
export interface SidebarProps {
  header?: React.ReactNode; search?: React.ReactNode; children?: React.ReactNode; bottomBar?: React.ReactNode; width?: number; style?: React.CSSProperties; ariaLabel?: string;
}

export declare function Sidebar(props: SidebarProps): JSX.Element | null;

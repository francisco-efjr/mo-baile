import * as React from "react";

/**
 * Barra inferior da sidebar (adicionar, remover, status). Toda ação também no menu de contexto.
 */
export interface SidebarBottomBarProps {
  actions?: Array<{ icon: string; label: string; onClick?: () => void; disabled?: boolean }>; status?: React.ReactNode; size?: "large" | "small";
}

export declare function SidebarBottomBar(props: SidebarBottomBarProps): JSX.Element | null;

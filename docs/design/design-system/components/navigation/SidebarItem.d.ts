import * as React from "react";

/**
 * Linha de navegação da sidebar: ícone colorido, rótulo truncado com tooltip, contador à direita.
 */
export interface SidebarItemProps {
  icon?: string; iconColor?: string; label: string; sublabel?: string; count?: number | string; trailing?: React.ReactNode; selected?: boolean;
  onSelect?: () => void; onContextMenu?: (e: any) => void; indent?: boolean; disabled?: boolean; onKeyDown?: (e: any) => void;
}

export declare function SidebarItem(props: SidebarItemProps): JSX.Element | null;

import * as React from "react";

/**
 * Menu suspenso/contexto em vidro. Aparece instantâneo, some com fade. Setas, Return e Esc. Exporta também ContextMenu e portal().
 */
export interface MenuProps {
  x?: number; y?: number; items: Array<{ label?: string; shortcut?: string; icon?: string; checked?: boolean; disabled?: boolean; destructive?: boolean; separator?: boolean; header?: string; onSelect?: () => void }>;
  onClose?: () => void; minWidth?: number; ariaLabel?: string;
}

export declare function Menu(props: MenuProps): JSX.Element | null;

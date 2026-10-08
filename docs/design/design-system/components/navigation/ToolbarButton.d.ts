import * as React from "react";

/**
 * Item de toolbar só com ícone; label vira tooltip e rótulo acessível. variant="tinted" só para o primário.
 */
export interface ToolbarButtonProps {
  icon?: string; label: string; shortcut?: string; onClick?: () => void; disabled?: boolean; on?: boolean; variant?: "tinted" | "recording"; text?: string; iconSize?: number; ariaPressed?: boolean;
}

export declare function ToolbarButton(props: ToolbarButtonProps): JSX.Element | null;

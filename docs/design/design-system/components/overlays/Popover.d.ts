import * as React from "react";

/**
 * Popover com seta para informação/ação contextual rápida. Escala 95→100% + fade. Fecha ao clicar fora.
 */
export interface PopoverProps {
  open: boolean; anchorRef: any; onClose?: () => void; placement?: "bottom" | "top"; width?: number; children?: React.ReactNode; ariaLabel?: string;
}

export declare function Popover(props: PopoverProps): JSX.Element | null;

import * as React from "react";

/**
 * Janela Mac (cantos 16 pt, sombra ativa/inativa). active=false neutraliza seleções.
 */
export interface WindowProps {
  active?: boolean; width?: number | string; height?: number | string; children?: React.ReactNode; style?: React.CSSProperties; ariaLabel?: string;
}

export declare function Window(props: WindowProps): JSX.Element | null;

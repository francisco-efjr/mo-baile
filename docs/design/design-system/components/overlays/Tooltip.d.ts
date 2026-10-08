import * as React from "react";

/**
 * Tooltip com atraso, obrigatório em todo botão só com ícone.
 */
export interface TooltipProps {
  label?: React.ReactNode; children: React.ReactNode; delay?: number;
}

export declare function Tooltip(props: TooltipProps): JSX.Element | null;

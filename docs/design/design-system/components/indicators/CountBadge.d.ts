import * as React from "react";

/**
 * Contador alinhado à direita em texto secundário (sidebar, abas). Sem cápsula colorida.
 */
export interface CountBadgeProps {
  value?: number | string; variant?: "text" | "pill"; ariaLabel?: string;
}

export declare function CountBadge(props: CountBadgeProps): JSX.Element | null;

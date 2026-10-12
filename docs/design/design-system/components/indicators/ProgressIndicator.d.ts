import * as React from "react";

/**
 * Indicador de progresso do sistema: barra determinada/indeterminada ou círculo giratório. Nada de loaders customizados.
 */
export interface ProgressIndicatorProps {
  kind?: "bar" | "spinner"; value?: number; size?: number; tone?: "success" | "error"; ariaLabel?: string;
}

export declare function ProgressIndicator(props: ProgressIndicatorProps): JSX.Element | null;

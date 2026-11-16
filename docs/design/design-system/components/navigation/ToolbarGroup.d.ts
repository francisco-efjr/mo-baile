import * as React from "react";

/**
 * Cápsula de Liquid Glass agrupando itens relacionados. Grupos diferentes, cápsulas separadas.
 */
export interface ToolbarGroupProps {
  children?: React.ReactNode; tinted?: boolean; scrolled?: boolean; ariaLabel?: string; style?: React.CSSProperties;
}

export declare function ToolbarGroup(props: ToolbarGroupProps): JSX.Element | null;

import * as React from "react";

/**
 * Ícone de linha estilo SF Symbols (Lucide como substituto). Herda currentColor.
 */
export interface IconProps {
  name: string; size?: number; strokeWidth?: number; color?: string; title?: string; className?: string; style?: React.CSSProperties;
}

export declare function Icon(props: IconProps): JSX.Element | null;

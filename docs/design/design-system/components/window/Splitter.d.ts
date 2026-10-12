import * as React from "react";

/**
 * Divisor arrastável de 1 px entre colunas; cursor de redimensionar.
 */
export interface SplitterProps {
  onDrag?: (delta: number) => void; onDragEnd?: () => void; orientation?: "vertical" | "horizontal"; ariaLabel?: string;
}

export declare function Splitter(props: SplitterProps): JSX.Element | null;

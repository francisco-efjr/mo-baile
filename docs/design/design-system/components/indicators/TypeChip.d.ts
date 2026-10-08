import * as React from "react";

/**
 * Chip de tipo de nó da árvore de acessibilidade (W janela, V contêiner, T texto, I campo, B botão).
 */
export interface TypeChipProps {
  type: "W" | "V" | "T" | "I" | "B";
}

export declare function TypeChip(props: TypeChipProps): JSX.Element | null;

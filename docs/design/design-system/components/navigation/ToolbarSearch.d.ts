import * as React from "react";

/**
 * Buscar na toolbar: botão com lupa que se funde em campo (morph) ao clicar ou com ⌘F.
 */
export interface ToolbarSearchProps {
  value: string; onChange?: (v: string) => void; placeholder?: string; open?: boolean; onOpenChange?: (v: boolean) => void; inputRef?: any; width?: number;
}

export declare function ToolbarSearch(props: ToolbarSearchProps): JSX.Element | null;

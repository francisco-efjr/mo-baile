import * as React from "react";

/**
 * Campo de texto padrão do sistema (seleção, copiar/colar, correção ortográfica). invalid mostra borda de erro.
 */
export interface TextFieldProps {
  value: string; onChange?: (v: string) => void; placeholder?: string; invalid?: boolean; mono?: boolean; width?: number | string; disabled?: boolean; ariaLabel?: string; type?: string; onKeyDown?: (e: any) => void;
}

export declare function TextField(props: TextFieldProps): JSX.Element | null;

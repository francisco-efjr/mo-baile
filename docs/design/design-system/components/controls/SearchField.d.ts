import * as React from "react";

/**
 * Campo de busca em cápsula com lupa, botão limpar e atalho opcional. Esc limpa.
 */
export interface SearchFieldProps {
  value: string; onChange?: (v: string) => void; placeholder?: string; shortcut?: string; autoFocus?: boolean; inputRef?: any; width?: number | string; onKeyDown?: (e: any) => void; ariaLabel?: string;
}

export declare function SearchField(props: SearchFieldProps): JSX.Element | null;

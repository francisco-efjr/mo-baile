import * as React from "react";

/**
 * Sheet modal da janela: desce da base da toolbar e escurece a janela. Esc cancela, Return confirma.
 */
export interface SheetProps {
  open: boolean; onClose?: () => void; onConfirm?: () => void; width?: number; children?: React.ReactNode; footer?: React.ReactNode; ariaLabel?: string;
}

export declare function Sheet(props: SheetProps): JSX.Element | null;

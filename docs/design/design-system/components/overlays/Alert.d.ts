import * as React from "react";

/**
 * Alerta só para decisões importantes/destrutivas. Ação destrutiva nomeada pelo verbo, nunca padrão.
 */
export interface AlertProps {
  open: boolean; title: string; message?: string; iconSrc?: string; buttons: Array<{ label: string; role?: "default" | "cancel" | "destructive"; onClick: () => void }>; onCancel?: () => void;
}

export declare function Alert(props: AlertProps): JSX.Element | null;

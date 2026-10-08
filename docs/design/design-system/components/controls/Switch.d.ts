import * as React from "react";

/**
 * Switch para ligar/desligar um recurso inteiro de forma destacada. Em formulários, use Checkbox.
 */
export interface SwitchProps {
  checked: boolean; onChange?: (v: boolean) => void; disabled?: boolean; size?: "small" | "regular"; ariaLabel?: string; label?: React.ReactNode;
}

export declare function Switch(props: SwitchProps): JSX.Element | null;

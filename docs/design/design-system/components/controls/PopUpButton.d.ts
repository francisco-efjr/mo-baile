import * as React from "react";

/**
 * Menu pop-up para escolher entre muitas opções (aparelho, Seletor, origem do tagueamento).
 */
export interface PopUpButtonProps {
  options: Array<{ value: string; label: string; disabled?: boolean } | "-">; value?: string; onChange?: (v: string) => void;
  label?: string; prefix?: string; icon?: string; variant?: "bordered" | "plain"; size?: "small" | "regular"; disabled?: boolean; ariaLabel?: string; minWidth?: number;
  extraItems?: Array<any>;
}

export declare function PopUpButton(props: PopUpButtonProps): JSX.Element | null;

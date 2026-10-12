import * as React from "react";

/**
 * Checkbox para ajustes on/off em formulários, com descrição auxiliar opcional 4 pt abaixo.
 */
export interface CheckboxProps {
  checked: boolean; onChange?: (v: boolean) => void; label?: React.ReactNode; help?: React.ReactNode; disabled?: boolean;
}

export declare function Checkbox(props: CheckboxProps): JSX.Element | null;

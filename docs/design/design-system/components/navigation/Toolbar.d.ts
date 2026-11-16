import * as React from "react";

/**
 * Toolbar unificada (52 pt). Componha com TrafficLights, ToolbarButton, ToolbarGroup, ToolbarTitle, ToolbarSpacer.
 */
export interface ToolbarProps {
  children?: React.ReactNode; style?: React.CSSProperties; className?: string;
}

export declare function Toolbar(props: ToolbarProps): JSX.Element | null;

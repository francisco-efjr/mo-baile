import * as React from "react";

/**
 * Barra acessória abaixo da toolbar com controles secundários do conteúdo. Não invade sidebar nem inspector.
 */
export interface AccessoryBarProps {
  children?: React.ReactNode; style?: React.CSSProperties;
}

export declare function AccessoryBar(props: AccessoryBarProps): JSX.Element | null;

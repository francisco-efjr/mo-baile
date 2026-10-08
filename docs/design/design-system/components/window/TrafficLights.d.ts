import * as React from "react";

/**
 * Botões fechar/minimizar/zoom no canto superior esquerdo, dentro da toolbar.
 */
export interface TrafficLightsProps {
  onClose?: () => void; onMinimize?: () => void; onZoom?: () => void;
}

export declare function TrafficLights(props: TrafficLightsProps): JSX.Element | null;

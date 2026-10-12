import * as React from "react";

/**
 * Moldura do aparelho para o espelho ao vivo (raios concêntricos 40/33).
 */
export interface DeviceFrameProps {
  width?: number; height?: number; notch?: boolean; children?: React.ReactNode; onMouseMove?: (e: any) => void; onMouseLeave?: () => void; onClick?: (e: any) => void; screenRef?: any;
}

export declare function DeviceFrame(props: DeviceFrameProps): JSX.Element | null;

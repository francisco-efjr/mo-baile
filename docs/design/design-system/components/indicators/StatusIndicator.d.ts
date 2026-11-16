import * as React from "react";

/**
 * Estado de serviço (WDA, ADB, Proxy, FA): ícone + cor + texto, nunca só cor.
 */
export interface StatusIndicatorProps {
  status: "ok" | "busy" | "warn" | "error" | "off"; label?: string; detail?: string; mono?: boolean;
}

export declare function StatusIndicator(props: StatusIndicatorProps): JSX.Element | null;

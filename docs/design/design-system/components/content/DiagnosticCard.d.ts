import * as React from "react";

/**
 * Cartão de diagnóstico do ambiente por plataforma, com checklist (ícone+cor+texto) e ação.
 */
export interface DiagnosticCardProps {
  platform: "ios" | "android"; title?: string; ready?: boolean; checks?: Array<{ label: string; detail?: string; state: "ok" | "warn" | "error" | "off" }> | null;
  actionLabel?: string; onAction?: () => void; actionDisabled?: boolean; busy?: boolean; footer?: React.ReactNode;
}

export declare function DiagnosticCard(props: DiagnosticCardProps): JSX.Element | null;

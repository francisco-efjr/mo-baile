import * as React from "react";

/**
 * Push button em cápsula. Use "default" (destaque, Return) para a ação principal; "destructive" para ações destrutivas fora do padrão.
 */
export interface ButtonProps {
  variant?: "default" | "secondary" | "destructive" | "destructive-fill" | "recording" | "plain" | "plain-destructive";
  size?: "mini" | "small" | "regular" | "large";
  icon?: string; iconRight?: string; disabled?: boolean; title?: string;
  onClick?: (e: any) => void; children?: React.ReactNode; type?: "button" | "submit";
}

export declare function Button(props: ButtonProps): JSX.Element | null;

import * as React from "react";

/**
 * Controle segmentado para 2–5 modos (plataforma, estratégia de seletor, Headers/Body). Thumb desliza com mola snappy.
 */
export interface SegmentedControlProps {
  items: Array<string | { value: string; label: React.ReactNode; icon?: string; count?: number; tooltip?: string }>;
  value: string; onChange?: (v: string) => void; size?: "small" | "regular" | "large"; disabled?: boolean; ariaLabel?: string; className?: string;
}

export declare function SegmentedControl(props: SegmentedControlProps): JSX.Element | null;

import * as React from "react";

/**
 * Estado vazio/carregando: ícone discreto, uma frase e a ação principal. Exporta também InlineError.
 */
export interface EmptyStateProps {
  icon?: string; title?: string; text?: string; actionLabel?: string; onAction?: () => void; loading?: boolean; compact?: boolean; children?: React.ReactNode;
}

export declare function EmptyState(props: EmptyStateProps): JSX.Element | null;

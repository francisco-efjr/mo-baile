import * as React from "react";

/**
 * Seção da sidebar com cabeçalho discreto; recolhível pela seta que aparece no hover.
 */
export interface SidebarSectionProps {
  title?: string; collapsible?: boolean; defaultCollapsed?: boolean; children?: React.ReactNode;
}

export declare function SidebarSection(props: SidebarSectionProps): JSX.Element | null;

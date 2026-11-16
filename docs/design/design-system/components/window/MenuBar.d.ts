import * as React from "react";

/**
 * Barra de menus do macOS simulada com menus padrão e atalhos com símbolos ⌘ ⇧ ⌥ ⌃.
 */
export interface MenuBarProps {
  menus: Array<{ title: string; items: Array<any> }>; right?: React.ReactNode;
}

export declare function MenuBar(props: MenuBarProps): JSX.Element | null;

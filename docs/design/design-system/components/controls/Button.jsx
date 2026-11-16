import React from "react";
import { Icon } from "../indicators/Icon.jsx";

export function Button({ children, variant = "secondary", size = "regular", icon, iconRight, disabled, onClick, type = "button", title, className = "", style, ...rest }) {
  const cls = ["mb-btn",
    variant === "default" && "mb-btn--default",
    variant === "destructive" && "mb-btn--destructive",
    variant === "destructive-fill" && "mb-btn--destructive-fill",
    variant === "recording" && "mb-btn--recording",
    variant === "plain" && "mb-btn--plain",
    variant === "plain-destructive" && "mb-btn--plain mb-btn--destructive",
    size !== "regular" && "mb-btn--" + size, className].filter(Boolean).join(" ");
  const is = size === "small" || size === "mini" ? 13 : 15;
  return (
    <button type={type} className={cls} disabled={disabled} onClick={onClick} title={title} style={style} {...rest}>
      {icon && <Icon name={icon} size={is} />}
      {children}
      {iconRight && <Icon name={iconRight} size={is} />}
    </button>
  );
}

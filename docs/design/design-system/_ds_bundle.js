/* @ds-bundle: {"format":4,"namespace":"MoBaileDesignSystem_ce6669","components":[{"name":"DataTable","sourcePath":"components/content/DataTable.jsx"},{"name":"DiagnosticCard","sourcePath":"components/content/DiagnosticCard.jsx"},{"name":"EmptyState","sourcePath":"components/content/EmptyState.jsx"},{"name":"InlineError","sourcePath":"components/content/EmptyState.jsx"},{"name":"Button","sourcePath":"components/controls/Button.jsx"},{"name":"Checkbox","sourcePath":"components/controls/Checkbox.jsx"},{"name":"PopUpButton","sourcePath":"components/controls/PopUpButton.jsx"},{"name":"SearchField","sourcePath":"components/controls/SearchField.jsx"},{"name":"SegmentedControl","sourcePath":"components/controls/SegmentedControl.jsx"},{"name":"Switch","sourcePath":"components/controls/Switch.jsx"},{"name":"TextField","sourcePath":"components/controls/TextField.jsx"},{"name":"CountBadge","sourcePath":"components/indicators/CountBadge.jsx"},{"name":"ICON_NAMES","sourcePath":"components/indicators/Icon.jsx"},{"name":"Icon","sourcePath":"components/indicators/Icon.jsx"},{"name":"ProgressIndicator","sourcePath":"components/indicators/ProgressIndicator.jsx"},{"name":"StatusIndicator","sourcePath":"components/indicators/StatusIndicator.jsx"},{"name":"TypeChip","sourcePath":"components/indicators/TypeChip.jsx"},{"name":"AccessoryBar","sourcePath":"components/navigation/AccessoryBar.jsx"},{"name":"Sidebar","sourcePath":"components/navigation/Sidebar.jsx"},{"name":"SidebarBottomBar","sourcePath":"components/navigation/SidebarBottomBar.jsx"},{"name":"SidebarItem","sourcePath":"components/navigation/SidebarItem.jsx"},{"name":"SidebarSection","sourcePath":"components/navigation/SidebarSection.jsx"},{"name":"Toolbar","sourcePath":"components/navigation/Toolbar.jsx"},{"name":"ToolbarTitle","sourcePath":"components/navigation/Toolbar.jsx"},{"name":"ToolbarSpacer","sourcePath":"components/navigation/Toolbar.jsx"},{"name":"ToolbarButton","sourcePath":"components/navigation/ToolbarButton.jsx"},{"name":"ToolbarGroup","sourcePath":"components/navigation/ToolbarGroup.jsx"},{"name":"ToolbarSearch","sourcePath":"components/navigation/ToolbarSearch.jsx"},{"name":"Alert","sourcePath":"components/overlays/Alert.jsx"},{"name":"Menu","sourcePath":"components/overlays/Menu.jsx"},{"name":"ContextMenu","sourcePath":"components/overlays/Menu.jsx"},{"name":"Popover","sourcePath":"components/overlays/Popover.jsx"},{"name":"Sheet","sourcePath":"components/overlays/Sheet.jsx"},{"name":"Tooltip","sourcePath":"components/overlays/Tooltip.jsx"},{"name":"DeviceFrame","sourcePath":"components/window/DeviceFrame.jsx"},{"name":"MenuBar","sourcePath":"components/window/MenuBar.jsx"},{"name":"Splitter","sourcePath":"components/window/Splitter.jsx"},{"name":"TrafficLights","sourcePath":"components/window/TrafficLights.jsx"},{"name":"Window","sourcePath":"components/window/Window.jsx"}],"sourceHashes":{"components/content/DataTable.jsx":"a40651794562","components/content/DiagnosticCard.jsx":"65b9c6650918","components/content/EmptyState.jsx":"d2222ec312c0","components/controls/Button.jsx":"2c0cea62cc1f","components/controls/Checkbox.jsx":"72fd181b472c","components/controls/PopUpButton.jsx":"6f8d8e184563","components/controls/SearchField.jsx":"df474927fe89","components/controls/SegmentedControl.jsx":"7f5b74a99b1a","components/controls/Switch.jsx":"9afe67c8b016","components/controls/TextField.jsx":"b57903a3ff1e","components/indicators/CountBadge.jsx":"78c80645e24a","components/indicators/Icon.jsx":"42afd8ce1bd2","components/indicators/ProgressIndicator.jsx":"e69008f0de96","components/indicators/StatusIndicator.jsx":"354b57399daa","components/indicators/TypeChip.jsx":"60b56ac0abb8","components/navigation/AccessoryBar.jsx":"903d2f12d9dd","components/navigation/Sidebar.jsx":"d9d6da7db509","components/navigation/SidebarBottomBar.jsx":"b3590dd37800","components/navigation/SidebarItem.jsx":"7b2879280921","components/navigation/SidebarSection.jsx":"7affe824db50","components/navigation/Toolbar.jsx":"b1bf3356b7a5","components/navigation/ToolbarButton.jsx":"ffe928cf39e6","components/navigation/ToolbarGroup.jsx":"55280fb7ccdd","components/navigation/ToolbarSearch.jsx":"dea81a580d83","components/overlays/Alert.jsx":"ea5164b72818","components/overlays/Menu.jsx":"acf7a6634d16","components/overlays/Popover.jsx":"60a107bb75f8","components/overlays/Sheet.jsx":"28632a72fa10","components/overlays/Tooltip.jsx":"5101da3b50d8","components/window/DeviceFrame.jsx":"a748c98a9063","components/window/MenuBar.jsx":"a7161c033096","components/window/Splitter.jsx":"148b8df5fd3c","components/window/TrafficLights.jsx":"2199eaa47d2e","components/window/Window.jsx":"ea4c2f0da003","ui_kits/macos-app/App.jsx":"0130c5bea227","ui_kits/macos-app/AppSidebar.jsx":"cff8c2bf3695","ui_kits/macos-app/Demo.jsx":"f90527ee73ef","ui_kits/macos-app/Inspector.jsx":"f7decdab1c4d","ui_kits/macos-app/Mirror.jsx":"1dde90b3779b","ui_kits/macos-app/NoDevice.jsx":"b1422f178032","ui_kits/macos-app/PageObjects.jsx":"855ed2acebcd","ui_kits/macos-app/Settings.jsx":"8c7357bae3cc","ui_kits/macos-app/Sheets.jsx":"bfe4075f8e70","ui_kits/macos-app/Traffic.jsx":"d500368e08cb","ui_kits/macos-app/data.js":"a71c86fc6a74","ui_kits/macos-app/spring.js":"fd96a0983064"},"inlinedExternals":[],"unexposedExports":[{"name":"portal","sourcePath":"components/overlays/Menu.jsx"}]} */

(() => {

const __ds_ns = (window.MoBaileDesignSystem_ce6669 = window.MoBaileDesignSystem_ce6669 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/controls/Switch.jsx
try { (() => {
// Switch: só para ligar/desligar um recurso inteiro de forma destacada. Em formulários, prefira Checkbox.
function Switch({
  checked,
  onChange,
  disabled,
  size = "regular",
  ariaLabel,
  label
}) {
  const sw = /*#__PURE__*/React.createElement("button", {
    type: "button",
    role: "switch",
    "aria-checked": !!checked,
    "aria-label": ariaLabel || label,
    disabled: disabled,
    className: "mb-switch" + (size === "small" ? " mb-switch--small" : ""),
    onClick: () => onChange && onChange(!checked)
  });
  if (!label) return sw;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 8,
      opacity: disabled ? .42 : 1
    }
  }, label, sw);
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Switch.jsx", error: String((e && e.message) || e) }); }

// components/controls/TextField.jsx
try { (() => {
function TextField({
  value,
  onChange,
  placeholder,
  invalid,
  mono,
  width,
  disabled,
  ariaLabel,
  onKeyDown,
  type = "text"
}) {
  return /*#__PURE__*/React.createElement("input", {
    type: type,
    className: "mb-field" + (invalid ? " is-invalid" : ""),
    value: value,
    placeholder: placeholder,
    disabled: disabled,
    "aria-label": ariaLabel,
    "aria-invalid": invalid || undefined,
    spellCheck: !mono,
    onKeyDown: onKeyDown,
    style: {
      width,
      fontFamily: mono ? "var(--font-mono)" : undefined,
      opacity: disabled ? .42 : 1
    },
    onChange: e => onChange && onChange(e.target.value)
  });
}
Object.assign(__ds_scope, { TextField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/TextField.jsx", error: String((e && e.message) || e) }); }

// components/indicators/CountBadge.jsx
try { (() => {
// Contador: texto secundário com algarismos tabulares. variant="pill" só dentro de controles segmentados.
function CountBadge({
  value,
  variant = "text",
  ariaLabel
}) {
  if (value == null) return null;
  return /*#__PURE__*/React.createElement("span", {
    className: "mb-count" + (variant === "pill" ? " mb-count--pill" : ""),
    "aria-label": ariaLabel
  }, value);
}
Object.assign(__ds_scope, { CountBadge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/indicators/CountBadge.jsx", error: String((e && e.message) || e) }); }

// components/indicators/Icon.jsx
try { (() => {
// Ícones Lucide (lucide-static@0.460.0, ISC), copiados programaticamente como substitutos de SF Symbols.
const PATHS = {
  "chevrons-up-down": "<path d=\"m7 15 5 5 5-5\" /> <path d=\"m7 9 5-5 5 5\" />",
  "chevron-left": "<path d=\"m15 18-6-6 6-6\" />",
  "chevron-up": "<path d=\"m18 15-6-6-6 6\" />",
  "check": "<path d=\"M20 6 9 17l-5-5\" />",
  "x": "<path d=\"M18 6 6 18\" /> <path d=\"m6 6 12 12\" />",
  "share": "<path d=\"M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8\" /> <polyline points=\"16 6 12 2 8 6\" /> <line x1=\"12\" x2=\"12\" y1=\"2\" y2=\"15\" />",
  "search": "<circle cx=\"11\" cy=\"11\" r=\"8\" /> <path d=\"m21 21-4.3-4.3\" />",
  "plus": "<path d=\"M5 12h14\" /> <path d=\"M12 5v14\" />",
  "copy": "<rect width=\"14\" height=\"14\" x=\"8\" y=\"8\" rx=\"2\" ry=\"2\" /> <path d=\"M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2\" />",
  "minus": "<path d=\"M5 12h14\" />",
  "save": "<path d=\"M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z\" /> <path d=\"M17 21v-7a1 1 0 0 0-1-1H8a1 1 0 0 0-1 1v7\" /> <path d=\"M7 3v4a1 1 0 0 0 1 1h7\" />",
  "trash-2": "<path d=\"M3 6h18\" /> <path d=\"M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6\" /> <path d=\"M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2\" /> <line x1=\"10\" x2=\"10\" y1=\"11\" y2=\"17\" /> <line x1=\"14\" x2=\"14\" y1=\"11\" y2=\"17\" />",
  "pointer": "<path d=\"M22 14a8 8 0 0 1-8 8\" /> <path d=\"M18 11v-1a2 2 0 0 0-2-2a2 2 0 0 0-2 2\" /> <path d=\"M14 10V9a2 2 0 0 0-2-2a2 2 0 0 0-2 2v1\" /> <path d=\"M10 9.5V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v10\" /> <path d=\"M18 11a2 2 0 1 1 4 0v3a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15\" />",
  "refresh-cw": "<path d=\"M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8\" /> <path d=\"M21 3v5h-5\" /> <path d=\"M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16\" /> <path d=\"M8 16H3v5\" />",
  "square": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" />",
  "download": "<path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" /> <polyline points=\"7 10 12 15 17 10\" /> <line x1=\"12\" x2=\"12\" y1=\"15\" y2=\"3\" />",
  "upload": "<path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" /> <polyline points=\"17 8 12 3 7 8\" /> <line x1=\"12\" x2=\"12\" y1=\"3\" y2=\"15\" />",
  "file-code": "<path d=\"M10 12.5 8 15l2 2.5\" /> <path d=\"m14 12.5 2 2.5-2 2.5\" /> <path d=\"M14 2v4a2 2 0 0 0 2 2h4\" /> <path d=\"M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z\" />",
  "circle-dot": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <circle cx=\"12\" cy=\"12\" r=\"1\" />",
  "play": "<polygon points=\"6 3 20 12 6 21 6 3\" />",
  "braces": "<path d=\"M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1\" /> <path d=\"M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1\" />",
  "rotate-cw": "<path d=\"M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8\" /> <path d=\"M21 3v5h-5\" />",
  "folder": "<path d=\"M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z\" />",
  "smartphone": "<rect width=\"14\" height=\"20\" x=\"5\" y=\"2\" rx=\"2\" ry=\"2\" /> <path d=\"M12 18h.01\" />",
  "list-filter": "<path d=\"M3 6h18\" /> <path d=\"M7 12h10\" /> <path d=\"M10 18h4\" />",
  "monitor-smartphone": "<path d=\"M18 8V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h8\" /> <path d=\"M10 19v-3.96 3.15\" /> <path d=\"M7 19h5\" /> <rect width=\"6\" height=\"10\" x=\"16\" y=\"12\" rx=\"2\" />",
  "panel-left": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /> <path d=\"M9 3v18\" />",
  "chevron-down": "<path d=\"m6 9 6 6 6-6\" />",
  "radio-tower": "<path d=\"M4.9 16.1C1 12.2 1 5.8 4.9 1.9\" /> <path d=\"M7.8 4.7a6.14 6.14 0 0 0-.8 7.5\" /> <circle cx=\"12\" cy=\"9\" r=\"2\" /> <path d=\"M16.2 4.8c2 2 2.26 5.11.8 7.47\" /> <path d=\"M19.1 1.9a9.96 9.96 0 0 1 0 14.1\" /> <path d=\"M9.5 18h5\" /> <path d=\"m8 22 4-11 4 11\" />",
  "circle-x": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"m15 9-6 6\" /> <path d=\"m9 9 6 6\" />",
  "globe": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20\" /> <path d=\"M2 12h20\" />",
  "network": "<rect x=\"16\" y=\"16\" width=\"6\" height=\"6\" rx=\"1\" /> <rect x=\"2\" y=\"16\" width=\"6\" height=\"6\" rx=\"1\" /> <rect x=\"9\" y=\"2\" width=\"6\" height=\"6\" rx=\"1\" /> <path d=\"M5 16v-3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v3\" /> <path d=\"M12 12V8\" />",
  "chart-line": "<path d=\"M3 3v16a2 2 0 0 0 2 2h16\" /> <path d=\"m19 9-5 5-4-4-3 3\" />",
  "list-ordered": "<path d=\"M10 12h11\" /> <path d=\"M10 18h11\" /> <path d=\"M10 6h11\" /> <path d=\"M4 10h2\" /> <path d=\"M4 6h1v4\" /> <path d=\"M6 18H4c0-1 2-2 2-3s-1-1.5-2-1\" />",
  "house": "<path d=\"M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8\" /> <path d=\"M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z\" />",
  "panel-right": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /> <path d=\"M15 3v18\" />",
  "video": "<path d=\"m16 13 5.223 3.482a.5.5 0 0 0 .777-.416V7.87a.5.5 0 0 0-.752-.432L16 10.5\" /> <rect x=\"2\" y=\"6\" width=\"14\" height=\"12\" rx=\"2\" />",
  "circle-help": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3\" /> <path d=\"M12 17h.01\" />",
  "triangle-alert": "<path d=\"m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3\" /> <path d=\"M12 9v4\" /> <path d=\"M12 17h.01\" />",
  "circle-check": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"m9 12 2 2 4-4\" />",
  "undo-2": "<path d=\"M9 14 4 9l5-5\" /> <path d=\"M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11\" />",
  "circle-alert": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <line x1=\"12\" x2=\"12\" y1=\"8\" y2=\"12\" /> <line x1=\"12\" x2=\"12.01\" y1=\"16\" y2=\"16\" />",
  "chevrons-right": "<path d=\"m6 17 5-5-5-5\" /> <path d=\"m13 17 5-5-5-5\" />",
  "info": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"M12 16v-4\" /> <path d=\"M12 8h.01\" />",
  "shield-check": "<path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\" /> <path d=\"m9 12 2 2 4-4\" />",
  "wand-sparkles": "<path d=\"m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72\" /> <path d=\"m14 7 3 3\" /> <path d=\"M5 6v4\" /> <path d=\"M19 14v4\" /> <path d=\"M10 2v2\" /> <path d=\"M7 8H3\" /> <path d=\"M21 16h-4\" /> <path d=\"M11 3H9\" />",
  "settings": "<path d=\"M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z\" /> <circle cx=\"12\" cy=\"12\" r=\"3\" />",
  "sun": "<circle cx=\"12\" cy=\"12\" r=\"4\" /> <path d=\"M12 2v2\" /> <path d=\"M12 20v2\" /> <path d=\"m4.93 4.93 1.41 1.41\" /> <path d=\"m17.66 17.66 1.41 1.41\" /> <path d=\"M2 12h2\" /> <path d=\"M20 12h2\" /> <path d=\"m6.34 17.66-1.41 1.41\" /> <path d=\"m19.07 4.93-1.41 1.41\" />",
  "cable": "<path d=\"M17 21v-2a1 1 0 0 1-1-1v-1a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v1a1 1 0 0 1-1 1\" /> <path d=\"M19 15V6.5a1 1 0 0 0-7 0v11a1 1 0 0 1-7 0V9\" /> <path d=\"M21 21v-2h-4\" /> <path d=\"M3 5h4V3\" /> <path d=\"M7 5a1 1 0 0 1 1 1v1a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a1 1 0 0 1 1-1V3\" />",
  "accessibility": "<circle cx=\"16\" cy=\"4\" r=\"1\" /> <path d=\"m18 19 1-7-6 1\" /> <path d=\"m5 8 3-3 5.5 3-2.36 3.5\" /> <path d=\"M4.24 14.5a5 5 0 0 0 6.88 6\" /> <path d=\"M13.76 17.5a5 5 0 0 0-6.88-6\" />",
  "sliders-horizontal": "<line x1=\"21\" x2=\"14\" y1=\"4\" y2=\"4\" /> <line x1=\"10\" x2=\"3\" y1=\"4\" y2=\"4\" /> <line x1=\"21\" x2=\"12\" y1=\"12\" y2=\"12\" /> <line x1=\"8\" x2=\"3\" y1=\"12\" y2=\"12\" /> <line x1=\"21\" x2=\"16\" y1=\"20\" y2=\"20\" /> <line x1=\"12\" x2=\"3\" y1=\"20\" y2=\"20\" /> <line x1=\"14\" x2=\"14\" y1=\"2\" y2=\"6\" /> <line x1=\"8\" x2=\"8\" y1=\"10\" y2=\"14\" /> <line x1=\"16\" x2=\"16\" y1=\"18\" y2=\"22\" />",
  "terminal": "<polyline points=\"4 17 10 11 4 5\" /> <line x1=\"12\" x2=\"20\" y1=\"19\" y2=\"19\" />",
  "moon": "<path d=\"M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z\" />",
  "link": "<path d=\"M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71\" /> <path d=\"M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71\" />",
  "scan-search": "<path d=\"M3 7V5a2 2 0 0 1 2-2h2\" /> <path d=\"M17 3h2a2 2 0 0 1 2 2v2\" /> <path d=\"M21 17v2a2 2 0 0 1-2 2h-2\" /> <path d=\"M7 21H5a2 2 0 0 1-2-2v-2\" /> <circle cx=\"12\" cy=\"12\" r=\"3\" /> <path d=\"m16 16-1.9-1.9\" />",
  "ellipsis": "<circle cx=\"12\" cy=\"12\" r=\"1\" /> <circle cx=\"19\" cy=\"12\" r=\"1\" /> <circle cx=\"5\" cy=\"12\" r=\"1\" />",
  "hand": "<path d=\"M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2\" /> <path d=\"M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2\" /> <path d=\"M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8\" /> <path d=\"M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15\" />",
  "layers": "<path d=\"m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z\" /> <path d=\"m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65\" /> <path d=\"m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65\" />",
  "activity": "<path d=\"M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2\" />",
  "keyboard": "<path d=\"M10 8h.01\" /> <path d=\"M12 12h.01\" /> <path d=\"M14 8h.01\" /> <path d=\"M16 12h.01\" /> <path d=\"M18 8h.01\" /> <path d=\"M6 8h.01\" /> <path d=\"M7 16h10\" /> <path d=\"M8 12h.01\" /> <rect width=\"20\" height=\"16\" x=\"2\" y=\"4\" rx=\"2\" />",
  "lock": "<rect width=\"18\" height=\"11\" x=\"3\" y=\"11\" rx=\"2\" ry=\"2\" /> <path d=\"M7 11V7a5 5 0 0 1 10 0v4\" />",
  "chevron-right": "<path d=\"m9 18 6-6-6-6\" />",
  "camera": "<path d=\"M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z\" /> <circle cx=\"12\" cy=\"13\" r=\"3\" />",
  "list-tree": "<path d=\"M21 12h-8\" /> <path d=\"M21 6H8\" /> <path d=\"M21 18h-8\" /> <path d=\"M3 6v4c0 1.1.9 2 2 2h3\" /> <path d=\"M3 10v6c0 1.1.9 2 2 2h3\" />",
  "columns-2": "<rect width=\"18\" height=\"18\" x=\"3\" y=\"3\" rx=\"2\" /> <path d=\"M12 3v18\" />",
  "contrast": "<circle cx=\"12\" cy=\"12\" r=\"10\" /> <path d=\"M12 18a6 6 0 0 0 0-12v12z\" />",
  "square-stack": "<path d=\"M4 10c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h4c1.1 0 2 .9 2 2\" /> <path d=\"M10 16c-1.1 0-2-.9-2-2v-4c0-1.1.9-2 2-2h4c1.1 0 2 .9 2 2\" /> <rect width=\"8\" height=\"8\" x=\"14\" y=\"14\" rx=\"2\" />"
};
const ICON_NAMES = Object.keys(PATHS);
function Icon({
  name,
  size = 16,
  strokeWidth = 1.6,
  color,
  title,
  className = "",
  style
}) {
  const inner = PATHS[name];
  if (!inner) return null;
  return React.createElement("svg", {
    className: "mb-icon " + className,
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: color || "currentColor",
    strokeWidth,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    role: title ? "img" : undefined,
    "aria-label": title,
    "aria-hidden": title ? undefined : true,
    style,
    dangerouslySetInnerHTML: {
      __html: inner
    }
  });
}
Object.assign(__ds_scope, { ICON_NAMES, Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/indicators/Icon.jsx", error: String((e && e.message) || e) }); }

// components/content/DataTable.jsx
try { (() => {
// Tabela: cabeçalhos clicáveis para ordenar, colunas redimensionáveis, seleção com ⌘ e ⇧, duplo clique abre, setas navegam.
// columns: [{key,label,width,minWidth,align,sortable,mono,render(row)}]; width numérico em px ou "1fr".
function DataTable({
  columns = [],
  rows = [],
  rowKey = "id",
  selected = [],
  onSelectionChange,
  onOpen,
  sort,
  onSortChange,
  onRowContextMenu,
  newKeys = [],
  focused = true,
  empty,
  style
}) {
  const [widths, setWidths] = React.useState(() => columns.map(c => c.width || "1fr"));
  const anchor = React.useRef(null);
  const tpl = widths.map((w, i) => typeof w === "number" ? w + "px" : "minmax(" + (columns[i].minWidth || 80) + "px," + w + ")").join(" ");
  const keys = rows.map(r => r[rowKey]);
  const sel = new Set(selected);
  const select = (k, e) => {
    let next;
    if (e && (e.metaKey || e.ctrlKey)) {
      next = new Set(sel);
      next.has(k) ? next.delete(k) : next.add(k);
      anchor.current = k;
    } else if (e && e.shiftKey && anchor.current != null) {
      const a = keys.indexOf(anchor.current),
        b = keys.indexOf(k);
      next = new Set(keys.slice(Math.min(a, b), Math.max(a, b) + 1));
    } else {
      next = new Set([k]);
      anchor.current = k;
    }
    onSelectionChange && onSelectionChange([...next]);
  };
  const onKey = e => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp" && e.key !== "Enter") return;
    e.preventDefault();
    const cur = keys.indexOf(selected[selected.length - 1]);
    if (e.key === "Enter") {
      cur >= 0 && onOpen && onOpen(rows[cur]);
      return;
    }
    const n = Math.max(0, Math.min(keys.length - 1, cur + (e.key === "ArrowDown" ? 1 : -1)));
    select(keys[n], e.shiftKey ? e : null);
  };
  const startResize = (i, e) => {
    e.preventDefault();
    e.stopPropagation();
    const th = e.currentTarget.parentElement;
    let w = th.offsetWidth,
      x = e.clientX;
    const move = ev => {
      w = Math.max(columns[i].minWidth || 48, w + ev.clientX - x);
      x = ev.clientX;
      setWidths(ws => ws.map((v, j) => j === i ? w : v));
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-table" + (focused ? "" : " is-unfocused"),
    role: "grid",
    tabIndex: 0,
    onKeyDown: onKey,
    style: style
  }, /*#__PURE__*/React.createElement("div", {
    className: "mb-table__head",
    style: {
      gridTemplateColumns: tpl,
      padding: "0 4px"
    },
    role: "row"
  }, columns.map((c, i) => {
    const active = sort && sort.key === c.key;
    return /*#__PURE__*/React.createElement("div", {
      key: c.key,
      role: "columnheader",
      "aria-sort": active ? sort.dir === "asc" ? "ascending" : "descending" : undefined,
      className: "mb-table__th" + (c.sortable ? " is-sortable" : "") + (c.align === "right" ? " is-right" : ""),
      onClick: () => c.sortable && onSortChange && onSortChange({
        key: c.key,
        dir: active && sort.dir === "asc" ? "desc" : "asc"
      })
    }, /*#__PURE__*/React.createElement("span", {
      className: "mb-truncate"
    }, c.label), active && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      name: sort.dir === "asc" ? "chevron-up" : "chevron-down",
      size: 11,
      strokeWidth: 2.2
    }), i < columns.length - 1 && /*#__PURE__*/React.createElement("span", {
      className: "mb-table__resize",
      onPointerDown: e => startResize(i, e),
      onClick: e => e.stopPropagation()
    }));
  })), /*#__PURE__*/React.createElement("div", {
    className: "mb-table__body"
  }, rows.length === 0 && empty, rows.map(r => {
    const k = r[rowKey];
    return /*#__PURE__*/React.createElement("div", {
      key: k,
      role: "row",
      "aria-selected": sel.has(k),
      className: "mb-table__row" + (sel.has(k) ? " is-selected" : "") + (newKeys.includes(k) ? " is-new" : ""),
      style: {
        gridTemplateColumns: tpl
      },
      onMouseDown: e => select(k, e),
      onDoubleClick: () => onOpen && onOpen(r),
      onContextMenu: e => {
        if (!sel.has(k)) select(k);
        onRowContextMenu && onRowContextMenu(r, e);
      }
    }, columns.map(c => /*#__PURE__*/React.createElement("div", {
      key: c.key,
      role: "gridcell",
      className: "mb-table__td" + (c.align === "right" ? " is-right mb-tabular" : ""),
      style: {
        fontFamily: c.mono ? "var(--font-mono)" : undefined,
        color: c.color ? c.color(r) : undefined
      }
    }, c.render ? c.render(r) : r[c.key])));
  })));
}
Object.assign(__ds_scope, { DataTable });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/content/DataTable.jsx", error: String((e && e.message) || e) }); }

// components/controls/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function Button({
  children,
  variant = "secondary",
  size = "regular",
  icon,
  iconRight,
  disabled,
  onClick,
  type = "button",
  title,
  className = "",
  style,
  ...rest
}) {
  const cls = ["mb-btn", variant === "default" && "mb-btn--default", variant === "destructive" && "mb-btn--destructive", variant === "destructive-fill" && "mb-btn--destructive-fill", variant === "recording" && "mb-btn--recording", variant === "plain" && "mb-btn--plain", variant === "plain-destructive" && "mb-btn--plain mb-btn--destructive", size !== "regular" && "mb-btn--" + size, className].filter(Boolean).join(" ");
  const is = size === "small" || size === "mini" ? 13 : 15;
  return /*#__PURE__*/React.createElement("button", _extends({
    type: type,
    className: cls,
    disabled: disabled,
    onClick: onClick,
    title: title,
    style: style
  }, rest), icon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: is
  }), children, iconRight && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: iconRight,
    size: is
  }));
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Button.jsx", error: String((e && e.message) || e) }); }

// components/controls/Checkbox.jsx
try { (() => {
function Checkbox({
  checked,
  onChange,
  label,
  help,
  disabled
}) {
  return /*#__PURE__*/React.createElement("span", {
    className: "mb-check",
    style: {
      opacity: disabled ? .42 : 1
    },
    onClick: () => !disabled && onChange && onChange(!checked)
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    role: "checkbox",
    "aria-checked": !!checked,
    disabled: disabled,
    className: "mb-check__box",
    onClick: e => e.stopPropagation() || onChange && onChange(!checked)
  }, checked && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "check",
    size: 11,
    strokeWidth: 3
  })), label && /*#__PURE__*/React.createElement("span", null, label, help && /*#__PURE__*/React.createElement("span", {
    className: "mb-check__help"
  }, help)));
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/controls/SearchField.jsx
try { (() => {
function SearchField({
  value,
  onChange,
  placeholder = "Buscar",
  shortcut,
  autoFocus,
  inputRef,
  width,
  onKeyDown,
  ariaLabel
}) {
  return /*#__PURE__*/React.createElement("label", {
    className: "mb-search",
    style: {
      width
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "search",
    size: 13
  }), /*#__PURE__*/React.createElement("input", {
    ref: inputRef,
    value: value,
    placeholder: placeholder,
    autoFocus: autoFocus,
    "aria-label": ariaLabel || placeholder,
    spellCheck: false,
    onKeyDown: e => {
      if (e.key === "Escape" && value) {
        e.stopPropagation();
        onChange && onChange("");
      }
      onKeyDown && onKeyDown(e);
    },
    onChange: e => onChange && onChange(e.target.value)
  }), value ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "mb-search__clear",
    "aria-label": "Limpar busca",
    onClick: () => onChange && onChange("")
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "x",
    size: 9,
    strokeWidth: 3
  })) : shortcut ? /*#__PURE__*/React.createElement("span", {
    className: "mb-kbd"
  }, shortcut) : null);
}
Object.assign(__ds_scope, { SearchField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/SearchField.jsx", error: String((e && e.message) || e) }); }

// components/controls/SegmentedControl.jsx
try { (() => {
function SegmentedControl({
  items = [],
  value,
  onChange,
  size = "regular",
  disabled,
  ariaLabel,
  className = ""
}) {
  const ref = React.useRef(null);
  const [thumb, setThumb] = React.useState(null);
  const idx = Math.max(0, items.findIndex(it => (typeof it === "string" ? it : it.value) === value));
  React.useLayoutEffect(() => {
    const el = ref.current && ref.current.querySelectorAll(".mb-seg__item")[idx];
    if (el) setThumb({
      left: el.offsetLeft,
      width: el.offsetWidth
    });
  }, [idx, items.length, size]);
  const onKey = e => {
    if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
    e.preventDefault();
    const n = (idx + (e.key === "ArrowRight" ? 1 : -1) + items.length) % items.length;
    const it = items[n];
    onChange && onChange(typeof it === "string" ? it : it.value);
  };
  return /*#__PURE__*/React.createElement("div", {
    ref: ref,
    role: "radiogroup",
    "aria-label": ariaLabel,
    tabIndex: 0,
    onKeyDown: onKey,
    className: ["mb-seg", size !== "regular" && "mb-seg--" + size, disabled && "is-disabled", className].filter(Boolean).join(" ")
  }, thumb && /*#__PURE__*/React.createElement("span", {
    className: "mb-seg__thumb",
    style: {
      left: thumb.left,
      width: thumb.width
    }
  }), items.map((it, i) => {
    const o = typeof it === "string" ? {
      value: it,
      label: it
    } : it;
    return /*#__PURE__*/React.createElement("button", {
      key: o.value,
      type: "button",
      role: "radio",
      "aria-checked": i === idx,
      tabIndex: -1,
      title: o.tooltip,
      className: "mb-seg__item" + (i === idx ? " is-selected" : ""),
      onClick: () => onChange && onChange(o.value)
    }, o.icon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      name: o.icon,
      size: size === "small" ? 12 : 14
    }), o.label, o.count != null && /*#__PURE__*/React.createElement("span", {
      className: "mb-count mb-count--pill"
    }, o.count));
  }));
}
Object.assign(__ds_scope, { SegmentedControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/SegmentedControl.jsx", error: String((e && e.message) || e) }); }

// components/indicators/ProgressIndicator.jsx
try { (() => {
// Indicador de progresso do sistema: barra (determinada ou não) ou círculo giratório.
function ProgressIndicator({
  kind = "bar",
  value,
  size = 16,
  tone,
  ariaLabel = "Carregando"
}) {
  if (kind === "spinner") return /*#__PURE__*/React.createElement("span", {
    className: "mb-spinner",
    role: "progressbar",
    "aria-label": ariaLabel,
    style: {
      width: size,
      height: size
    }
  });
  const ind = value == null;
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-progress" + (ind ? " mb-progress--indeterminate" : ""),
    role: "progressbar",
    "aria-label": ariaLabel,
    "aria-valuenow": ind ? undefined : Math.round(value * 100),
    "aria-valuemin": 0,
    "aria-valuemax": 100
  }, /*#__PURE__*/React.createElement("div", {
    className: "mb-progress__bar",
    style: {
      width: ind ? undefined : value * 100 + "%",
      background: tone === "success" ? "var(--success-fill)" : tone === "error" ? "var(--destructive-fill)" : undefined
    }
  }));
}
Object.assign(__ds_scope, { ProgressIndicator });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/indicators/ProgressIndicator.jsx", error: String((e && e.message) || e) }); }

// components/content/DiagnosticCard.jsx
try { (() => {
const MARK = {
  ok: ["circle-check", "var(--success)"],
  warn: ["triangle-alert", "var(--warning)"],
  error: ["circle-x", "var(--destructive)"],
  off: ["minus", "var(--label-tertiary)"]
};

// Cartão de diagnóstico por plataforma (iOS · WebDriverAgent / Android · ADB). checks=null → verificando.
function DiagnosticCard({
  platform = "ios",
  title,
  ready,
  checks,
  actionLabel,
  onAction,
  actionDisabled,
  busy,
  footer
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-card",
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 12,
      minHeight: 236
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      width: 8,
      height: 8,
      borderRadius: 4,
      background: platform === "ios" ? "var(--platform-ios)" : "var(--platform-android)"
    }
  }), /*#__PURE__*/React.createElement("b", {
    style: {
      fontWeight: 600,
      flex: 1
    }
  }, title || (platform === "ios" ? "iOS" : "Android")), ready && /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 3,
      fontSize: 11,
      color: "var(--success)"
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "check",
    size: 11,
    strokeWidth: 2.6
  }), "Pronto")), checks ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 8
    }
  }, checks.map(c => /*#__PURE__*/React.createElement("div", {
    key: c.label,
    style: {
      display: "flex",
      gap: 8,
      alignItems: "flex-start"
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: MARK[c.state][0],
    size: 14,
    color: MARK[c.state][1],
    strokeWidth: 2,
    style: {
      marginTop: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", null, c.label), c.detail && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      lineHeight: "14px",
      color: "var(--label-secondary)",
      textWrap: "pretty"
    }
  }, c.detail))))) : /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 6,
      color: "var(--label-secondary)",
      fontSize: 12
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.ProgressIndicator, {
    kind: "spinner",
    size: 14
  }), " Verificando ambiente\u2026"), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8
    }
  }, actionLabel && /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "default",
    disabled: actionDisabled || busy,
    onClick: onAction
  }, busy ? "Iniciando…" : actionLabel), footer));
}
Object.assign(__ds_scope, { DiagnosticCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/content/DiagnosticCard.jsx", error: String((e && e.message) || e) }); }

// components/content/EmptyState.jsx
try { (() => {
// Estado vazio / carregando: ícone discreto, uma frase e (opcional) a ação principal.
function EmptyState({
  icon = "info",
  title,
  text,
  actionLabel,
  onAction,
  loading,
  compact,
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-empty",
    style: compact ? {
      padding: 16,
      gap: 4
    } : undefined
  }, loading ? /*#__PURE__*/React.createElement(__ds_scope.ProgressIndicator, {
    kind: "spinner",
    size: compact ? 16 : 22
  }) : /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: compact ? 22 : 32,
    strokeWidth: 1.4,
    className: "mb-empty__icon"
  }), title && /*#__PURE__*/React.createElement("p", {
    className: "mb-empty__title",
    style: compact ? {
      fontSize: 13
    } : undefined
  }, title), text && /*#__PURE__*/React.createElement("p", {
    className: "mb-empty__text",
    style: compact ? {
      fontSize: 12
    } : undefined
  }, text), actionLabel && /*#__PURE__*/React.createElement(__ds_scope.Button, {
    onClick: onAction
  }, actionLabel), children);
}

// Erro em linha, perto de onde aconteceu: o que houve e o que fazer.
function InlineError({
  title,
  text,
  actionLabel,
  onAction
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-inline-error",
    role: "alert"
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "circle-alert",
    size: 14,
    strokeWidth: 2,
    style: {
      marginTop: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("b", null, title), text && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--label-primary)"
    }
  }, " ", text)), actionLabel && /*#__PURE__*/React.createElement(__ds_scope.Button, {
    size: "small",
    onClick: onAction
  }, actionLabel));
}
Object.assign(__ds_scope, { EmptyState, InlineError });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/content/EmptyState.jsx", error: String((e && e.message) || e) }); }

// components/indicators/StatusIndicator.jsx
try { (() => {
const ICON = {
  ok: "circle-check",
  busy: "refresh-cw",
  warn: "triangle-alert",
  error: "circle-x",
  off: "minus"
};
const WORD = {
  ok: "ok",
  busy: "ocupado",
  warn: "atenção",
  error: "erro",
  off: "inativo"
};

// Estado de um serviço (WDA, ADB, Proxy, FA). Cor + forma do ícone + texto: nunca só cor.
function StatusIndicator({
  status = "off",
  label,
  detail,
  mono = true
}) {
  return /*#__PURE__*/React.createElement("span", {
    className: "mb-status mb-status--" + status,
    title: (label ? label + " — " : "") + WORD[status] + (detail ? ". " + detail : "")
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: ICON[status],
    size: 11,
    strokeWidth: 2.2
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: mono ? "var(--font-mono)" : undefined
    }
  }, label));
}
Object.assign(__ds_scope, { StatusIndicator });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/indicators/StatusIndicator.jsx", error: String((e && e.message) || e) }); }

// components/indicators/TypeChip.jsx
try { (() => {
const NAMES = {
  W: "Janela",
  V: "Contêiner",
  T: "Texto",
  I: "Campo",
  B: "Botão"
};

// Chip de tipo de nó da hierarquia: letra + cor (W, V, T, I, B).
function TypeChip({
  type = "V"
}) {
  return /*#__PURE__*/React.createElement("span", {
    className: "mb-chip mb-chip--" + type,
    title: NAMES[type],
    "aria-label": NAMES[type]
  }, type);
}
Object.assign(__ds_scope, { TypeChip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/indicators/TypeChip.jsx", error: String((e && e.message) || e) }); }

// components/navigation/AccessoryBar.jsx
try { (() => {
// Barra acessória: controles secundários do conteúdo selecionado. Fica só sobre a coluna de conteúdo.
function AccessoryBar({
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-accessory",
    role: "toolbar",
    style: style
  }, children);
}
Object.assign(__ds_scope, { AccessoryBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/AccessoryBar.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Sidebar.jsx
try { (() => {
// Sidebar de altura total (inclusive sob a toolbar). header = espaço da toolbar (botões da janela + alternar sidebar).
function Sidebar({
  header,
  search,
  children,
  bottomBar,
  width,
  style,
  ariaLabel = "Barra lateral"
}) {
  return /*#__PURE__*/React.createElement("nav", {
    className: "mb-sidebar",
    "aria-label": ariaLabel,
    style: {
      width,
      ...style
    }
  }, header && /*#__PURE__*/React.createElement("div", {
    style: {
      height: "var(--toolbar-height)",
      display: "flex",
      alignItems: "center",
      flex: "none"
    }
  }, header), search && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "0 10px 4px"
    }
  }, search), /*#__PURE__*/React.createElement("div", {
    className: "mb-sidebar__scroll",
    role: "tree"
  }, children), bottomBar);
}
Object.assign(__ds_scope, { Sidebar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Sidebar.jsx", error: String((e && e.message) || e) }); }

// components/navigation/SidebarItem.jsx
try { (() => {
// Item da sidebar: ícone colorido à esquerda, rótulo truncado (tooltip com texto completo), contador à direita.
function SidebarItem({
  icon,
  iconColor,
  label,
  sublabel,
  count,
  trailing,
  selected,
  onSelect,
  onContextMenu,
  indent,
  disabled,
  onKeyDown
}) {
  const ref = React.useRef(null);
  const [trunc, setTrunc] = React.useState(false);
  React.useLayoutEffect(() => {
    const el = ref.current && ref.current.querySelector(".mb-sb-item__label");
    if (el) setTrunc(el.scrollWidth > el.clientWidth);
  });
  return /*#__PURE__*/React.createElement("div", {
    ref: ref,
    role: "treeitem",
    "aria-selected": !!selected,
    "aria-disabled": disabled || undefined,
    tabIndex: selected ? 0 : -1,
    title: trunc ? label : undefined,
    className: "mb-sb-item" + (selected ? " is-selected" : "") + (indent ? " is-indented" : ""),
    style: {
      "--sb-icon": iconColor,
      opacity: disabled ? .42 : 1
    },
    onMouseDown: () => !disabled && onSelect && onSelect(),
    onContextMenu: onContextMenu,
    onKeyDown: e => {
      if (e.key === "Enter" && onSelect) onSelect();
      onKeyDown && onKeyDown(e);
    }
  }, icon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 16
  }), /*#__PURE__*/React.createElement("span", {
    className: "mb-sb-item__label"
  }, label, sublabel && /*#__PURE__*/React.createElement("span", {
    className: "mb-sb-item__sub"
  }, " ", sublabel)), trailing, count != null && /*#__PURE__*/React.createElement("span", {
    className: "mb-count"
  }, count));
}
Object.assign(__ds_scope, { SidebarItem });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/SidebarItem.jsx", error: String((e && e.message) || e) }); }

// components/navigation/SidebarSection.jsx
try { (() => {
// Seção da sidebar: cabeçalho discreto; recolhível com seta que aparece no hover.
function SidebarSection({
  title,
  collapsible = true,
  defaultCollapsed = false,
  children
}) {
  const [collapsed, setCollapsed] = React.useState(defaultCollapsed);
  const body = React.useRef(null);
  const [h, setH] = React.useState("auto");
  const toggle = () => {
    const el = body.current;
    const full = el.scrollHeight;
    if (collapsed) {
      setH(full);
      setCollapsed(false);
      setTimeout(() => setH("auto"), 600);
    } else {
      setH(full);
      requestAnimationFrame(() => requestAnimationFrame(() => setH(0)));
      setCollapsed(true);
    }
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-sb-section" + (collapsed ? " is-collapsed" : ""),
    role: "group",
    "aria-label": title
  }, title && /*#__PURE__*/React.createElement("div", {
    className: "mb-sb-section__head"
  }, /*#__PURE__*/React.createElement("span", null, title), collapsible && /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "mb-sb-section__toggle",
    "aria-expanded": !collapsed,
    "aria-label": (collapsed ? "Mostrar " : "Ocultar ") + title,
    onClick: toggle
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron-down",
    size: 12,
    strokeWidth: 2.2
  }))), /*#__PURE__*/React.createElement("div", {
    ref: body,
    className: "mb-sb-section__body",
    style: {
      height: collapsed && h !== "auto" ? h : h,
      opacity: collapsed ? 0 : 1
    }
  }, children));
}
Object.assign(__ds_scope, { SidebarSection });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/SidebarSection.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Toolbar.jsx
try { (() => {
// Toolbar unificada: botões da janela, título da seção e itens numa única faixa.
function Toolbar({
  children,
  style,
  className = ""
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-toolbar " + className,
    role: "toolbar",
    style: style
  }, children);
}

// Título = nome da seção atual (nunca o nome do app) + subtítulo opcional.
function ToolbarTitle({
  title,
  subtitle
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-toolbar__title"
  }, /*#__PURE__*/React.createElement("b", {
    className: "mb-truncate"
  }, title), subtitle && /*#__PURE__*/React.createElement("span", {
    className: "mb-truncate mb-tabular"
  }, subtitle));
}
function ToolbarSpacer() {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-toolbar__spacer"
  });
}
Object.assign(__ds_scope, { Toolbar, ToolbarTitle, ToolbarSpacer });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Toolbar.jsx", error: String((e && e.message) || e) }); }

// components/navigation/ToolbarGroup.jsx
try { (() => {
// Cápsula de Liquid Glass que agrupa itens relacionados. tinted só para o elemento primário da tela.
function ToolbarGroup({
  children,
  tinted,
  scrolled,
  ariaLabel,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "group",
    "aria-label": ariaLabel,
    style: style,
    className: "mb-tb-group " + (tinted ? "mb-tb-group--tinted" : "mb-glass") + (scrolled ? " is-scrolled" : "")
  }, children);
}
Object.assign(__ds_scope, { ToolbarGroup });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/ToolbarGroup.jsx", error: String((e && e.message) || e) }); }

// components/overlays/Alert.jsx
try { (() => {
// Alerta: só para decisões importantes ou destrutivas. A ação destrutiva é nomeada pelo verbo e nunca é o botão padrão.
// buttons: [{label, role:"default"|"cancel"|"destructive", onClick}]
function Alert({
  open,
  title,
  message,
  iconSrc,
  buttons = [],
  onCancel
}) {
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (open && ref.current) ref.current.focus();
  }, [open]);
  if (!open) return null;
  const def = buttons.find(b => b.role === "default");
  const cancel = buttons.find(b => b.role === "cancel");
  const onKey = e => {
    if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      (cancel && cancel.onClick || onCancel || (() => {}))();
    }
    if (e.key === "Enter" && def) {
      e.preventDefault();
      def.onClick();
    }
  };
  return /*#__PURE__*/React.createElement("div", {
    onKeyDown: onKey,
    style: {
      position: "absolute",
      inset: 0,
      zIndex: 850,
      display: "grid",
      placeItems: "center",
      background: "var(--scrim)",
      animation: "mb-fade 180ms linear both"
    }
  }, /*#__PURE__*/React.createElement("div", {
    ref: ref,
    tabIndex: -1,
    role: "alertdialog",
    "aria-label": title,
    className: "mb-alert mb-popover",
    style: {
      position: "relative"
    }
  }, iconSrc && /*#__PURE__*/React.createElement("img", {
    className: "mb-alert__icon",
    src: iconSrc,
    alt: ""
  }), /*#__PURE__*/React.createElement("h3", null, title), message && /*#__PURE__*/React.createElement("p", null, message), /*#__PURE__*/React.createElement("div", {
    className: "mb-alert__buttons"
  }, buttons.map(b => /*#__PURE__*/React.createElement(__ds_scope.Button, {
    key: b.label,
    variant: b.role === "default" ? "default" : b.role === "destructive" ? "destructive" : "secondary",
    onClick: b.onClick
  }, b.label)))));
}
Object.assign(__ds_scope, { Alert });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/overlays/Alert.jsx", error: String((e && e.message) || e) }); }

// components/overlays/Menu.jsx
try { (() => {
function portal(node) {
  const RD = typeof window !== "undefined" && window.ReactDOM;
  const host = typeof document !== "undefined" && (document.querySelector("[data-mb-portal]") || document.body);
  return RD && RD.createPortal && host ? RD.createPortal(node, host) : node;
}

// Menu (dropdown ou contexto). Aparece instantaneamente; some com fade curto.
// items: [{label, shortcut, icon, checked, disabled, destructive, onSelect} | {separator:true} | {header:"…"}]
function Menu({
  x = 0,
  y = 0,
  items = [],
  onClose,
  minWidth = 200,
  ariaLabel
}) {
  const ref = React.useRef(null);
  const [active, setActive] = React.useState(-1);
  const [leaving, setLeaving] = React.useState(false);
  const [pos, setPos] = React.useState({
    x,
    y
  });
  const close = React.useCallback(fn => {
    setLeaving(true);
    setTimeout(() => {
      onClose && onClose();
      fn && fn();
    }, 150);
  }, [onClose]);
  const actionable = items.map((it, i) => !it.separator && !it.header && !it.disabled ? i : -1).filter(i => i >= 0);
  React.useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    setPos({
      x: Math.min(x, window.innerWidth - r.width - 6),
      y: y + r.height > window.innerHeight - 6 ? Math.max(6, y - r.height) : y
    });
    el.focus();
  }, [x, y]);
  React.useEffect(() => {
    const down = e => {
      if (ref.current && !ref.current.contains(e.target)) close();
    };
    const t = setTimeout(() => document.addEventListener("mousedown", down), 0);
    return () => {
      clearTimeout(t);
      document.removeEventListener("mousedown", down);
    };
  }, [close]);
  const onKey = e => {
    if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      close();
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const k = actionable.indexOf(active),
        d = e.key === "ArrowDown" ? 1 : -1;
      setActive(actionable[(k + d + actionable.length) % actionable.length]);
    } else if (e.key === "Enter" && active >= 0) {
      e.preventDefault();
      const it = items[active];
      close(it.onSelect);
    }
  };
  const hasChecks = items.some(it => it.checked != null);
  return portal(/*#__PURE__*/React.createElement("div", {
    ref: ref,
    role: "menu",
    "aria-label": ariaLabel,
    tabIndex: -1,
    onKeyDown: onKey,
    onContextMenu: e => e.preventDefault(),
    className: "mb-menu" + (leaving ? " is-leaving" : ""),
    style: {
      position: "fixed",
      left: pos.x,
      top: pos.y,
      minWidth
    }
  }, items.map((it, i) => it.separator ? /*#__PURE__*/React.createElement("div", {
    key: i,
    className: "mb-menu__sep",
    role: "separator"
  }) : it.header ? /*#__PURE__*/React.createElement("div", {
    key: i,
    className: "mb-menu__header"
  }, it.header) : /*#__PURE__*/React.createElement("div", {
    key: i,
    role: "menuitem",
    "aria-disabled": it.disabled || undefined,
    className: "mb-menu__item" + (it.disabled ? " is-disabled" : "") + (it.destructive ? " is-destructive" : "") + (i === active ? " is-active" : ""),
    onMouseEnter: () => setActive(it.disabled ? -1 : i),
    onMouseLeave: () => setActive(-1),
    onClick: () => !it.disabled && close(it.onSelect)
  }, (hasChecks || it.icon) && /*#__PURE__*/React.createElement("span", {
    className: "mb-menu__check"
  }, it.checked ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "check",
    size: 12,
    strokeWidth: 2.4
  }) : it.icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: it.icon,
    size: 14
  }) : null), /*#__PURE__*/React.createElement("span", {
    className: "mb-menu__label"
  }, it.label), it.shortcut && /*#__PURE__*/React.createElement("span", {
    className: "mb-menu__kbd"
  }, it.shortcut)))));
}

// Envolve qualquer item manipulável: clique direito abre o menu de contexto.
function ContextMenu({
  items,
  children,
  onOpen,
  style,
  className
}) {
  const [at, setAt] = React.useState(null);
  return /*#__PURE__*/React.createElement("div", {
    style: style,
    className: className,
    onContextMenu: e => {
      e.preventDefault();
      e.stopPropagation();
      onOpen && onOpen();
      setAt({
        x: e.clientX,
        y: e.clientY
      });
    }
  }, children, at && /*#__PURE__*/React.createElement(Menu, {
    x: at.x,
    y: at.y,
    items: typeof items === "function" ? items() : items,
    onClose: () => setAt(null)
  }));
}
Object.assign(__ds_scope, { portal, Menu, ContextMenu });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/overlays/Menu.jsx", error: String((e && e.message) || e) }); }

// components/controls/PopUpButton.jsx
try { (() => {
// Menu pop-up: escolha entre muitas opções. options: [{value,label,disabled}] ou "-" para separador.
function PopUpButton({
  options = [],
  value,
  onChange,
  label,
  prefix,
  icon,
  variant = "bordered",
  size = "regular",
  disabled,
  ariaLabel,
  minWidth,
  extraItems = []
}) {
  const ref = React.useRef(null);
  const [menu, setMenu] = React.useState(null);
  const cur = options.find(o => o !== "-" && o.value === value);
  const open = () => {
    const r = ref.current.getBoundingClientRect();
    setMenu({
      x: r.left,
      y: r.bottom + 4
    });
  };
  const items = options.map(o => o === "-" ? {
    separator: true
  } : {
    label: o.label,
    checked: o.value === value,
    disabled: o.disabled,
    onSelect: () => onChange && onChange(o.value)
  }).concat(extraItems);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("button", {
    ref: ref,
    type: "button",
    "aria-haspopup": "menu",
    "aria-label": ariaLabel,
    disabled: disabled,
    onClick: open,
    style: {
      minWidth
    },
    className: ["mb-popup", variant === "plain" && "mb-popup--plain", size === "small" && "mb-popup--small"].filter(Boolean).join(" ")
  }, icon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 14
  }), prefix && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--label-secondary)"
    }
  }, prefix), /*#__PURE__*/React.createElement("span", {
    className: "mb-truncate",
    style: {
      flex: 1,
      textAlign: "left"
    }
  }, label || cur && cur.label), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevrons-up-down",
    size: 12,
    className: "mb-popup__chev"
  })), menu && /*#__PURE__*/React.createElement(__ds_scope.Menu, {
    x: menu.x,
    y: menu.y,
    items: items,
    onClose: () => setMenu(null)
  }));
}
Object.assign(__ds_scope, { PopUpButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/PopUpButton.jsx", error: String((e && e.message) || e) }); }

// components/overlays/Popover.jsx
try { (() => {
// Popover com seta apontando para a origem. Surge com escala 95%→100% + fade (mola snappy). Fecha ao clicar fora ou Esc.
function Popover({
  open,
  anchorRef,
  onClose,
  placement = "bottom",
  width = 280,
  children,
  ariaLabel
}) {
  const ref = React.useRef(null);
  const [pos, setPos] = React.useState(null);
  React.useLayoutEffect(() => {
    if (!open || !anchorRef || !anchorRef.current) return;
    const a = anchorRef.current.getBoundingClientRect();
    const cx = a.left + a.width / 2;
    let left = Math.max(8, Math.min(cx - width / 2, window.innerWidth - width - 8));
    if (placement === "bottom") setPos({
      left,
      top: a.bottom + 10,
      arrowX: cx - left - 9,
      origin: cx - left + "px 0"
    });else setPos({
      left,
      bottom: window.innerHeight - a.top + 10,
      arrowX: cx - left - 9,
      origin: cx - left + "px 100%"
    });
  }, [open, placement, width]);
  React.useEffect(() => {
    if (!open) return;
    const down = e => {
      if (ref.current && !ref.current.contains(e.target) && !(anchorRef.current && anchorRef.current.contains(e.target))) onClose && onClose();
    };
    const key = e => {
      if (e.key === "Escape") onClose && onClose();
    };
    document.addEventListener("mousedown", down);
    document.addEventListener("keydown", key);
    return () => {
      document.removeEventListener("mousedown", down);
      document.removeEventListener("keydown", key);
    };
  }, [open, onClose]);
  if (!open || !pos) return null;
  return __ds_scope.portal(/*#__PURE__*/React.createElement("div", {
    ref: ref,
    role: "dialog",
    "aria-label": ariaLabel,
    className: "mb-popover",
    style: {
      position: "fixed",
      left: pos.left,
      top: pos.top,
      bottom: pos.bottom,
      width,
      "--origin": pos.origin
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-popover__arrow",
    style: placement === "bottom" ? {
      top: -9,
      left: pos.arrowX
    } : {
      bottom: -9,
      left: pos.arrowX,
      transform: "rotate(180deg)"
    }
  }), children));
}
Object.assign(__ds_scope, { Popover });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/overlays/Popover.jsx", error: String((e && e.message) || e) }); }

// components/overlays/Sheet.jsx
try { (() => {
// Sheet: tarefa modal da janela. Desce da base da toolbar e escurece a janela. Esc cancela, Return confirma.
// Renderize dentro do container da janela (position: relative).
function Sheet({
  open,
  onClose,
  onConfirm,
  width = 560,
  children,
  footer,
  ariaLabel
}) {
  const [mounted, setMounted] = React.useState(open);
  const [shown, setShown] = React.useState(false);
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (open) {
      setMounted(true);
      requestAnimationFrame(() => requestAnimationFrame(() => setShown(true)));
    } else {
      setShown(false);
      const t = setTimeout(() => setMounted(false), 600);
      return () => clearTimeout(t);
    }
  }, [open]);
  React.useEffect(() => {
    if (shown && ref.current) ref.current.focus();
  }, [shown]);
  if (!mounted) return null;
  const onKey = e => {
    if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      onClose && onClose();
    }
    if (e.key === "Enter" && onConfirm && e.target.tagName !== "TEXTAREA" && e.target.tagName !== "BUTTON") {
      e.preventDefault();
      onConfirm();
    }
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-sheet-layer" + (shown ? " is-open" : ""),
    onKeyDown: onKey
  }, /*#__PURE__*/React.createElement("div", {
    className: "mb-sheet-scrim"
  }), /*#__PURE__*/React.createElement("div", {
    ref: ref,
    tabIndex: -1,
    role: "dialog",
    "aria-modal": "true",
    "aria-label": ariaLabel,
    className: "mb-sheet",
    style: {
      width
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "mb-sheet__body"
  }, children), footer && /*#__PURE__*/React.createElement("div", {
    className: "mb-sheet__footer"
  }, footer)));
}
Object.assign(__ds_scope, { Sheet });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/overlays/Sheet.jsx", error: String((e && e.message) || e) }); }

// components/overlays/Tooltip.jsx
try { (() => {
// Tooltip com atraso (~700 ms) — obrigatório em todo botão só com ícone.
function Tooltip({
  label,
  children,
  delay = 700
}) {
  const [at, setAt] = React.useState(null);
  const t = React.useRef(0);
  if (!label) return children;
  const enter = e => {
    const r = e.currentTarget.getBoundingClientRect();
    clearTimeout(t.current);
    t.current = setTimeout(() => setAt({
      x: r.left + r.width / 2,
      y: r.bottom + 6
    }), delay);
  };
  const leave = () => {
    clearTimeout(t.current);
    setAt(null);
  };
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex"
    },
    onMouseEnter: enter,
    onMouseLeave: leave,
    onMouseDown: leave
  }, children, at && __ds_scope.portal(/*#__PURE__*/React.createElement("div", {
    className: "mb-tooltip",
    role: "tooltip",
    style: {
      left: at.x,
      top: at.y,
      transform: "translateX(-50%)"
    }
  }, label)));
}
Object.assign(__ds_scope, { Tooltip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/overlays/Tooltip.jsx", error: String((e && e.message) || e) }); }

// components/navigation/SidebarBottomBar.jsx
try { (() => {
// Barra inferior da sidebar (32 pt, botões 31×18, 1 pt entre botões, 8 pt da borda). size="small" = 22 pt.
// actions: [{icon, label, onClick, disabled}]; status: conteúdo à direita (ex.: estado de sincronização).
function SidebarBottomBar({
  actions = [],
  status,
  size = "large"
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-bottombar" + (size === "small" ? " mb-bottombar--small" : ""),
    role: "toolbar"
  }, actions.map(a => /*#__PURE__*/React.createElement(__ds_scope.Tooltip, {
    key: a.label,
    label: a.label
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "mb-bottombar__btn",
    "aria-label": a.label,
    disabled: a.disabled,
    onClick: a.onClick
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: a.icon,
    size: size === "small" ? 12 : 14
  })))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: "flex",
      justifyContent: "flex-end",
      alignItems: "center",
      gap: 6,
      fontSize: "var(--text-subheadline)",
      color: "var(--label-secondary)"
    }
  }, status));
}
Object.assign(__ds_scope, { SidebarBottomBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/SidebarBottomBar.jsx", error: String((e && e.message) || e) }); }

// components/navigation/ToolbarButton.jsx
try { (() => {
// Item de toolbar só com ícone. label vira tooltip e rótulo acessível. Fundo aparece só no hover.
const ToolbarButton = React.forwardRef(function ToolbarButton({
  icon,
  label,
  shortcut,
  onClick,
  disabled,
  on,
  variant,
  text,
  iconSize = 17,
  ariaPressed
}, ref) {
  const cls = "mb-tb-item" + (on ? " is-on" : "") + (variant === "tinted" ? " mb-tb-item--tinted" : "") + (variant === "recording" ? " mb-tb-item--recording" : "");
  return /*#__PURE__*/React.createElement(__ds_scope.Tooltip, {
    label: shortcut ? label + "  " + shortcut : label
  }, /*#__PURE__*/React.createElement("button", {
    ref: ref,
    type: "button",
    className: cls,
    "aria-label": label,
    "aria-pressed": ariaPressed,
    disabled: disabled,
    onClick: onClick,
    style: text ? {
      padding: "0 12px"
    } : undefined
  }, icon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: iconSize
  }), text && /*#__PURE__*/React.createElement("span", {
    style: {
      fontWeight: 500
    }
  }, text)));
});
Object.assign(__ds_scope, { ToolbarButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/ToolbarButton.jsx", error: String((e && e.message) || e) }); }

// components/navigation/ToolbarSearch.jsx
try { (() => {
// Buscar: começa como botão com lupa e se funde (morph) em campo ao clicar ou com ⌘F.
function ToolbarSearch({
  value,
  onChange,
  placeholder = "Buscar",
  open: openProp,
  onOpenChange,
  inputRef,
  width = 220
}) {
  const [openState, setOpen] = React.useState(false);
  const open = openProp != null ? openProp : openState;
  const local = React.useRef(null);
  const ref = inputRef || local;
  const set = v => {
    setOpen(v);
    onOpenChange && onOpenChange(v);
  };
  React.useEffect(() => {
    if (open && ref.current) setTimeout(() => ref.current && ref.current.focus(), 30);
  }, [open]);
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-tb-search mb-glass" + (open ? " is-open" : ""),
    style: open ? {
      width
    } : undefined
  }, /*#__PURE__*/React.createElement(__ds_scope.Tooltip, {
    label: open ? null : "Buscar  ⌘F"
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "mb-tb-item",
    "aria-label": "Buscar",
    style: {
      width: 32,
      margin: 2,
      height: 32
    },
    onClick: () => set(true)
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "search",
    size: 16
  }))), open && /*#__PURE__*/React.createElement("input", {
    ref: ref,
    value: value,
    placeholder: placeholder,
    spellCheck: false,
    "aria-label": placeholder,
    onChange: e => onChange && onChange(e.target.value),
    onBlur: () => !value && set(false),
    onKeyDown: e => {
      if (e.key === "Escape") {
        e.stopPropagation();
        onChange && onChange("");
        set(false);
      }
    }
  }));
}
Object.assign(__ds_scope, { ToolbarSearch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/ToolbarSearch.jsx", error: String((e && e.message) || e) }); }

// components/window/DeviceFrame.jsx
try { (() => {
// Moldura de aparelho para o espelho ao vivo (raio 40 / tela 33 — concêntricos com padding 7).
function DeviceFrame({
  width = 258,
  height = 540,
  notch = true,
  children,
  onMouseMove,
  onMouseLeave,
  onClick,
  screenRef
}) {
  const scale = width / 258;
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-device",
    style: {
      width,
      height,
      borderRadius: 40 * scale,
      padding: 7 * scale
    }
  }, /*#__PURE__*/React.createElement("div", {
    ref: screenRef,
    className: "mb-device__screen",
    style: {
      borderRadius: 33 * scale
    },
    onMouseMove: onMouseMove,
    onMouseLeave: onMouseLeave,
    onClick: onClick
  }, notch && /*#__PURE__*/React.createElement("div", {
    className: "mb-device__notch",
    style: {
      width: 76 * scale,
      height: 20 * scale,
      top: 9 * scale
    }
  }), children));
}
Object.assign(__ds_scope, { DeviceFrame });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/window/DeviceFrame.jsx", error: String((e && e.message) || e) }); }

// components/window/MenuBar.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
// Barra de menus do macOS simulada. menus: [{title, items:[…itens de Menu]}]. O primeiro é o menu do app (negrito).
function MenuBar({
  menus = [],
  right
}) {
  const [open, setOpen] = React.useState(null);
  const refs = React.useRef([]);
  const at = i => {
    const r = refs.current[i].getBoundingClientRect();
    return {
      x: r.left,
      y: r.bottom + 2
    };
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-menubar",
    role: "menubar"
  }, menus.map((m, i) => /*#__PURE__*/React.createElement("button", {
    key: m.title,
    ref: el => refs.current[i] = el,
    type: "button",
    role: "menuitem",
    "aria-haspopup": "menu",
    "aria-expanded": open === i,
    className: "mb-menubar__item" + (i === 0 ? " is-app" : "") + (open === i ? " is-open" : ""),
    onMouseDown: e => {
      e.preventDefault();
      setOpen(open === i ? null : i);
    },
    onMouseEnter: () => open != null && open !== i && setOpen(i)
  }, m.title)), /*#__PURE__*/React.createElement("div", {
    className: "mb-menubar__right"
  }, right), open != null && /*#__PURE__*/React.createElement(__ds_scope.Menu, _extends({
    key: open
  }, at(open), {
    items: menus[open].items,
    minWidth: 220,
    ariaLabel: menus[open].title,
    onClose: () => setOpen(null)
  })));
}
Object.assign(__ds_scope, { MenuBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/window/MenuBar.jsx", error: String((e && e.message) || e) }); }

// components/window/Splitter.jsx
try { (() => {
// Divisor arrastável entre colunas (1 px; área de arraste de 9 px; cursor de redimensionar).
function Splitter({
  onDrag,
  onDragEnd,
  orientation = "vertical",
  ariaLabel = "Redimensionar"
}) {
  const down = e => {
    e.preventDefault();
    let last = orientation === "vertical" ? e.clientX : e.clientY;
    const move = ev => {
      const p = orientation === "vertical" ? ev.clientX : ev.clientY;
      onDrag && onDrag(p - last);
      last = p;
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      document.body.style.cursor = "";
      onDragEnd && onDragEnd();
    };
    document.body.style.cursor = orientation === "vertical" ? "col-resize" : "row-resize";
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  return /*#__PURE__*/React.createElement("div", {
    role: "separator",
    "aria-orientation": orientation,
    "aria-label": ariaLabel,
    className: "mb-splitter" + (orientation === "horizontal" ? " mb-splitter--h" : ""),
    onPointerDown: down
  });
}
Object.assign(__ds_scope, { Splitter });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/window/Splitter.jsx", error: String((e && e.message) || e) }); }

// components/window/TrafficLights.jsx
try { (() => {
const G = {
  close: /*#__PURE__*/React.createElement("svg", {
    width: "8",
    height: "8",
    viewBox: "0 0 8 8"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M1.5 1.5l5 5M6.5 1.5l-5 5",
    stroke: "currentColor",
    strokeWidth: "1.2"
  })),
  min: /*#__PURE__*/React.createElement("svg", {
    width: "8",
    height: "8",
    viewBox: "0 0 8 8"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M1 4h6",
    stroke: "currentColor",
    strokeWidth: "1.2"
  })),
  zoom: /*#__PURE__*/React.createElement("svg", {
    width: "8",
    height: "8",
    viewBox: "0 0 8 8"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M2 2h3L2 5zM6 6H3l3-3z",
    fill: "currentColor"
  }))
};

// Botões fechar / minimizar / zoom. Os glifos aparecem no hover do grupo; cinza na janela inativa.
function TrafficLights({
  onClose,
  onMinimize,
  onZoom
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-traffic"
  }, /*#__PURE__*/React.createElement("i", {
    role: "button",
    "aria-label": "Fechar",
    onClick: onClose
  }, G.close), /*#__PURE__*/React.createElement("i", {
    role: "button",
    "aria-label": "Minimizar",
    onClick: onMinimize
  }, G.min), /*#__PURE__*/React.createElement("i", {
    role: "button",
    "aria-label": "Zoom",
    onClick: onZoom
  }, G.zoom));
}
Object.assign(__ds_scope, { TrafficLights });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/window/TrafficLights.jsx", error: String((e && e.message) || e) }); }

// components/window/Window.jsx
try { (() => {
// Janela de app Mac: cantos de 16 pt, sombra maior quando ativa. active=false neutraliza seleções e toolbar.
function Window({
  active = true,
  width = 1280,
  height = 800,
  children,
  style,
  ariaLabel
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-window",
    "data-window-active": active ? "true" : "false",
    role: "application",
    "aria-label": ariaLabel,
    style: {
      width,
      height,
      minWidth: "var(--window-min-width)",
      minHeight: "var(--window-min-height)",
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { Window });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/window/Window.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/App.jsx
try { (() => {
// Mo baile — protótipo macOS. Estado, toolbar, layout em colunas, menus e atalhos.
const NSX = () => window.MoBaileDesignSystem_ce6669;
const D = window.MB_DATA;
const SECTION_TITLE = {
  pageObjects: "Page Objects",
  network: "Rede HTTP",
  analytics: "Analytics"
};
function App() {
  const {
    Window,
    TrafficLights,
    Toolbar,
    ToolbarTitle,
    ToolbarSpacer,
    ToolbarButton,
    ToolbarGroup,
    ToolbarSearch,
    SegmentedControl,
    PopUpButton,
    Splitter,
    StatusIndicator,
    MenuBar,
    Menu,
    Popover,
    Alert,
    Button,
    Icon,
    Tooltip
  } = NSX();
  const useSpring = window.mbUseSpring;
  // Preferências (Ajustes) e painel do protótipo
  const [prefs, setPrefs] = React.useState({
    appearance: "light",
    sidebarSize: "medium",
    strategy: "auto",
    autoStream: true,
    wda: "http://localhost:8100",
    proxyHost: "127.0.0.1",
    proxyPort: "8082"
  });
  const setPref = (k, v) => setPrefs(p => ({
    ...p,
    [k]: v
  }));
  const [demo, setDemoState] = React.useState({
    active: true,
    reduceMotion: false,
    reduceTransparency: false,
    contrast: false,
    scenario: "connected",
    outcome: "pass"
  });
  const setDemo = (k, v) => setDemoState(d => ({
    ...d,
    [k]: v
  }));
  const [demoCollapsed, setDemoCollapsed] = React.useState(window.innerWidth < 1500);
  const sysDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  const dark = prefs.appearance === "dark" || prefs.appearance === "system" && sysDark;
  React.useEffect(() => {
    const h = document.documentElement;
    dark ? h.setAttribute("data-theme", "dark") : h.removeAttribute("data-theme");
    demo.contrast ? h.setAttribute("data-contrast", "high") : h.removeAttribute("data-contrast");
    h.setAttribute("data-reduce-motion", demo.reduceMotion);
    h.setAttribute("data-reduce-transparency", demo.reduceTransparency);
    h.setAttribute("data-sidebar-size", prefs.sidebarSize);
  }, [dark, demo.contrast, demo.reduceMotion, demo.reduceTransparency, prefs.sidebarSize]);

  // Painéis
  const [sidebarOpen, setSidebarOpen] = React.useState(true);
  const [inspectorOpen, setInspectorOpen] = React.useState(true);
  const [mirrorOpen, setMirrorOpen] = React.useState(true);
  const [workspaceOpen, setWorkspaceOpen] = React.useState(true);
  const [sidebarW, setSidebarW] = React.useState(240);
  const [inspectorW, setInspectorW] = React.useState(272);
  const [mirrorW, setMirrorW] = React.useState(290);
  const [dragging, setDragging] = React.useState(false);
  const springOpts = {
    duration: 0.5,
    bounce: 0,
    instant: demo.reduceMotion || dragging
  };
  const sbW = useSpring(sidebarOpen ? sidebarW : 0, springOpts);
  const inW = useSpring(inspectorOpen ? inspectorW : 0, springOpts);
  const [win, setWin] = React.useState({
    w: 1280,
    h: 800
  });

  // Conteúdo
  const scenario = demo.scenario;
  const connected = ["connected", "loading", "error"].includes(scenario);
  const loading = scenario === "loading";
  const [section, setSectionRaw] = React.useState("pageObjects");
  const [fade, setFade] = React.useState(1);
  const setSection = s => {
    if (s === section) return;
    setFade(0);
    setTimeout(() => {
      setSectionRaw(s);
      setFade(1);
    }, 90);
  };
  const [selectedStep, setSelectedStep] = React.useState(null);
  const [device, setDevice] = React.useState("iphone16");
  const [mode, setMode] = React.useState("record");
  const [strategy, setStrategy] = React.useState("auto");
  const [split, setSplit] = React.useState(false);
  const [data, setData] = React.useState({
    steps: D.steps,
    requests: D.requests,
    events: D.events
  });
  const [past, setPast] = React.useState([]);
  const [future, setFuture] = React.useState([]);
  const commit = (label, fn) => {
    setPast(p => [...p.slice(-30), {
      label,
      data
    }]);
    setFuture([]);
    setData(fn(data));
  };
  const undo = () => {
    if (!past.length) return;
    const last = past[past.length - 1];
    setFuture(f => [...f, {
      label: last.label,
      data
    }]);
    setData(last.data);
    setPast(p => p.slice(0, -1));
    toast("Desfeito: " + last.label);
  };
  const redo = () => {
    if (!future.length) return;
    const n = future[future.length - 1];
    setPast(p => [...p, {
      label: n.label,
      data
    }]);
    setData(n.data);
    setFuture(f => f.slice(0, -1));
    toast("Refeito: " + n.label);
  };
  const [newIds, setNewIds] = React.useState([]);
  const [nodeSel, setNodeSel] = React.useState("continuar");
  const [hierQuery, setHierQuery] = React.useState("");
  const [focusPane, setFocusPane] = React.useState("content");
  const [reqSel, setReqSel] = React.useState([7]);
  const [evSel, setEvSel] = React.useState([3]);
  const [proxyOn, setProxyOn] = React.useState(true);
  const [debugOn, setDebugOn] = React.useState(false);
  const [listening, setListening] = React.useState(true);
  const [source, setSource] = React.useState("auto");
  const [filter, setFilter] = React.useState({
    network: "",
    analytics: ""
  });
  const [searchOpen, setSearchOpen] = React.useState(false);
  const [netError, setNetError] = React.useState(null);
  const [passive, setPassive] = React.useState(false);
  const [screenRec, setScreenRec] = React.useState(false);
  const [scrcpy, setScrcpy] = React.useState(false);
  const [sheet, setSheet] = React.useState(null);
  const [alert, setAlert] = React.useState(null);
  const [settings, setSettings] = React.useState({
    open: false,
    front: false
  });
  const [corrOpen, setCorrOpen] = React.useState(false);
  const corrRef = React.useRef(null);
  const hierSearch = React.useRef(null);
  const tbSearch = React.useRef(null);
  const [msg, setMsg] = React.useState("");
  const msgT = React.useRef(0);
  const toast = m => {
    setMsg(m);
    clearTimeout(msgT.current);
    msgT.current = setTimeout(() => setMsg(""), 3200);
  };
  const [cursor, setCursor] = React.useState({
    x: 589,
    y: 2229
  });
  const [splash, setSplash] = React.useState(true);
  const [scan, setScan] = React.useState("10:13:35");
  React.useEffect(() => {
    const t = setTimeout(() => setSplash(false), 1500);
    return () => clearTimeout(t);
  }, []);
  React.useEffect(() => {
    if (scenario === "error") {
      setSectionRaw("network");
      setProxyOn(false);
      setNetError(true);
    } else setNetError(null);
  }, [scenario]);
  const dev = D.devices.find(d => d.id === device);
  const steps = data.steps;
  const windowActive = demo.active && !settings.front;
  const effSection = connected ? section : "noDevice";
  const showMirror = connected && mirrorOpen;
  const showWork = workspaceOpen || !showMirror;

  // Ações
  const recordStep = node => {
    if (!node || !node.box) return;
    const strat = strategy === "auto" ? node.key ? "id" : "xpath" : strategy;
    const id = "s" + Date.now();
    const isInput = node.type === "I";
    const s = {
      id,
      action: isInput ? "send_keys" : "click",
      element: node.key || node.label,
      varName: node.var || node.label.toUpperCase().replace(/\W+/g, "_"),
      strategy: strat,
      selector: strat === "xpath" ? "//" + node.attrs.type + "[@name=\"" + node.attrs.name + "\"]" : strat === "coords" ? "x: " + node.attrs.center : node.key || node.label,
      method: (isInput ? "preencher_" : "click_") + (node.var || node.label).toLowerCase().replace(/\W+/g, "_"),
      value: isInput ? "texto" : undefined
    };
    commit("Gravar passo", d => ({
      ...d,
      steps: [...d.steps, s]
    }));
    setNewIds([id]);
    setTimeout(() => setNewIds([]), 700);
    toast("Passo " + (steps.length + 1) + " gravado · " + s.action + " " + s.element);
  };
  const onTap = (node, pt) => {
    setCursor({
      x: Math.round(pt.px * 11.79),
      y: Math.round(pt.py * 25.56)
    });
    if (mode === "record" && section === "pageObjects") recordStep(node);else {
      toast("Toque enviado ao aparelho em x " + Math.round(pt.px * 11.79) + " · y " + Math.round(pt.py * 25.56));
      if (proxyOn && node && node.type === "B") {
        const id = Date.now();
        setData(d => ({
          ...d,
          requests: [...d.requests, {
            id,
            method: "POST",
            status: 200,
            host: "api.bancopraia.com.br",
            path: "/v2/eventos/toque",
            size: 24,
            time: 96
          }]
        }));
        setNewIds([id]);
        setTimeout(() => setNewIds([]), 700);
      }
    }
  };
  const deleteStep = id => {
    commit("Excluir passo", d => ({
      ...d,
      steps: d.steps.filter(s => s.id !== id)
    }));
    if (selectedStep === id) setSelectedStep(null);
    toast("Passo excluído · ⌘Z para desfazer");
  };
  const reorder = (a, b) => commit("Reordenar passos", d => {
    const s = [...d.steps];
    const [x] = s.splice(a, 1);
    s.splice(b, 0, x);
    return {
      ...d,
      steps: s
    };
  });
  const askClear = kind => setAlert(kind);
  const doClear = kind => {
    if (kind === "network") {
      commit("Limpar tráfego", d => ({
        ...d,
        requests: []
      }));
      setReqSel([]);
    }
    if (kind === "analytics") {
      commit("Limpar eventos", d => ({
        ...d,
        events: []
      }));
      setEvSel([]);
    }
    if (kind === "steps") {
      commit("Limpar passos", d => ({
        ...d,
        steps: []
      }));
      setSelectedStep(null);
    }
    setAlert(null);
    toast("Removido · ⌘Z para desfazer");
  };
  const openSearch = () => {
    if (section === "pageObjects" || !connected) {
      setInspectorOpen(true);
      setTimeout(() => hierSearch.current && hierSearch.current.focus(), 60);
    } else setSearchOpen(true);
  };
  const run = () => steps.length && connected && setSheet("runner");
  const goStep = id => {
    setSelectedStep(id);
    setSectionRaw("pageObjects");
  };

  // Menus (toda ação da toolbar também aparece aqui)
  const menus = [{
    title: "Mo baile",
    items: [{
      label: "Sobre o Mo baile"
    }, {
      separator: true
    }, {
      label: "Ajustes…",
      shortcut: "⌘,",
      onSelect: () => setSettings({
        open: true,
        front: true
      })
    }, {
      separator: true
    }, {
      label: "Ocultar Mo baile",
      shortcut: "⌘H"
    }, {
      label: "Sair do Mo baile",
      shortcut: "⌘Q"
    }]
  }, {
    title: "Arquivo",
    items: [{
      label: "Salvar Page Object",
      shortcut: "⌘S",
      disabled: !steps.length,
      onSelect: () => toast("onboarding_credito_objs.py salvo")
    }, {
      label: "Exportar HAR…",
      shortcut: "⇧⌘E",
      disabled: !data.requests.length,
      onSelect: () => toast("network_traffic.har exportado")
    }, {
      label: "Exportar JSON de Analytics…",
      disabled: !data.events.length,
      onSelect: () => toast("log_obtido.json exportado")
    }, {
      separator: true
    }, {
      label: "Fechar Janela",
      shortcut: "⌘W"
    }]
  }, {
    title: "Editar",
    items: [{
      label: past.length ? "Desfazer " + past[past.length - 1].label : "Desfazer",
      shortcut: "⌘Z",
      disabled: !past.length,
      onSelect: undo
    }, {
      label: future.length ? "Refazer " + future[future.length - 1].label : "Refazer",
      shortcut: "⇧⌘Z",
      disabled: !future.length,
      onSelect: redo
    }, {
      separator: true
    }, {
      label: "Recortar",
      shortcut: "⌘X"
    }, {
      label: "Copiar",
      shortcut: "⌘C"
    }, {
      label: "Colar",
      shortcut: "⌘V"
    }, {
      label: "Selecionar Tudo",
      shortcut: "⌘A"
    }, {
      separator: true
    }, {
      label: "Buscar",
      shortcut: "⌘F",
      onSelect: openSearch
    }, {
      separator: true
    }, {
      label: "Limpar Tráfego…",
      disabled: !data.requests.length,
      onSelect: () => askClear("network")
    }, {
      label: "Limpar Eventos…",
      disabled: !data.events.length,
      onSelect: () => askClear("analytics")
    }]
  }, {
    title: "Visualizar",
    items: [{
      label: sidebarOpen ? "Ocultar Barra Lateral" : "Mostrar Barra Lateral",
      shortcut: "⌃⌘S",
      onSelect: () => setSidebarOpen(o => !o)
    }, {
      label: inspectorOpen ? "Ocultar Inspector" : "Mostrar Inspector",
      shortcut: "⌥⌘I",
      onSelect: () => setInspectorOpen(o => !o)
    }, {
      label: mirrorOpen ? "Ocultar Espelho" : "Mostrar Espelho",
      shortcut: "⌥1",
      onSelect: () => setMirrorOpen(o => !o)
    }, {
      label: workspaceOpen ? "Ocultar Workspace" : "Mostrar Workspace",
      shortcut: "⌥2",
      onSelect: () => setWorkspaceOpen(o => !o)
    }, {
      label: "Mostrar Todos os Painéis",
      shortcut: "⌥⌘F",
      onSelect: () => {
        setSidebarOpen(true);
        setInspectorOpen(true);
        setMirrorOpen(true);
        setWorkspaceOpen(true);
      }
    }, {
      label: sidebarOpen || inspectorOpen ? "Modo Zen" : "Sair do Modo Zen",
      shortcut: "⌃⌘Z",
      onSelect: () => {
        const z = sidebarOpen || inspectorOpen;
        setSidebarOpen(!z);
        setInspectorOpen(!z);
        setMirrorOpen(true);
        setWorkspaceOpen(true);
      }
    }, {
      separator: true
    }, {
      label: "Page Objects",
      shortcut: "⌘1",
      checked: section === "pageObjects",
      onSelect: () => setSection("pageObjects")
    }, {
      label: "Rede HTTP",
      shortcut: "⌘2",
      checked: section === "network",
      onSelect: () => setSection("network")
    }, {
      label: "Analytics",
      shortcut: "⌘3",
      checked: section === "analytics",
      onSelect: () => setSection("analytics")
    }]
  }, {
    title: "Dispositivo",
    items: [{
      label: "Atualizar Lista",
      shortcut: "⇧⌘R",
      onSelect: () => toast("Lista de aparelhos atualizada")
    }, {
      label: "Atualizar Tela",
      shortcut: "⌘K",
      disabled: !connected,
      onSelect: () => toast("Tela capturada")
    }, {
      label: "Parar Espelho",
      shortcut: "⌘E",
      disabled: !connected
    }, {
      separator: true
    }, {
      label: "Repassar Toque",
      checked: mode === "forward",
      disabled: !connected,
      onSelect: () => setMode("forward")
    }, {
      label: "Gravar Passo",
      checked: mode === "record",
      disabled: !connected,
      onSelect: () => setMode("record")
    }, {
      separator: true
    }, {
      label: passive ? "Parar Captura do Aparelho" : "Gravar do Aparelho",
      disabled: !connected,
      onSelect: () => setPassive(p => !p)
    }, {
      label: screenRec ? "Parar de Gravar a Tela" : "Gravar a Tela",
      disabled: !connected,
      onSelect: () => setScreenRec(r => !r)
    }, {
      label: "Espelho 60 FPS (scrcpy)",
      checked: scrcpy,
      disabled: !connected || dev.platform !== "android",
      onSelect: () => setScrcpy(s => !s)
    }]
  }, {
    title: "Automação",
    items: [{
      label: "Estrutura do Fluxo…",
      disabled: !steps.length,
      onSelect: () => setSheet("structure")
    }, {
      label: "Rodar Automação",
      shortcut: "⌘R",
      disabled: !steps.length || !connected,
      onSelect: run
    }, {
      separator: true
    }, {
      label: "Limpar Passos…",
      disabled: !steps.length,
      destructive: true,
      onSelect: () => askClear("steps")
    }]
  }, {
    title: "Janela",
    items: [{
      label: "Minimizar",
      shortcut: "⌘M"
    }, {
      label: "Zoom"
    }, {
      separator: true
    }, {
      label: "Mostrar Splash",
      onSelect: () => {
        setSplash(true);
        setTimeout(() => setSplash(false), 1500);
      }
    }, {
      separator: true
    }, {
      label: "Mo baile",
      checked: !settings.front,
      onSelect: () => setSettings(s => ({
        ...s,
        front: false
      }))
    }]
  }, {
    title: "Ajuda",
    items: [{
      label: "Ajuda do Mo baile"
    }, {
      label: "Atalhos de Teclado"
    }]
  }];

  // Atalhos
  React.useEffect(() => {
    const k = e => {
      const m = e.metaKey || e.ctrlKey;
      const t = e.target;
      const typing = t.tagName === "INPUT" || t.tagName === "TEXTAREA";
      if (e.key === "Escape" && settings.front) {
        setSettings({
          open: false,
          front: false
        });
        return;
      }
      if (e.ctrlKey && e.metaKey && e.key.toLowerCase() === "s") {
        e.preventDefault();
        setSidebarOpen(o => !o);
        return;
      }
      if (e.ctrlKey && e.metaKey && e.key.toLowerCase() === "z") {
        e.preventDefault();
        const z = sidebarOpen || inspectorOpen;
        setSidebarOpen(!z);
        setInspectorOpen(!z);
        return;
      }
      if (e.altKey && e.metaKey && e.code === "KeyI") {
        e.preventDefault();
        setInspectorOpen(o => !o);
        return;
      }
      if (e.altKey && e.metaKey && e.code === "KeyF") {
        e.preventDefault();
        setSidebarOpen(true);
        setInspectorOpen(true);
        setMirrorOpen(true);
        setWorkspaceOpen(true);
        return;
      }
      if (e.altKey && !m && e.code === "Digit1") {
        e.preventDefault();
        setMirrorOpen(o => !o);
        return;
      }
      if (e.altKey && !m && e.code === "Digit2") {
        e.preventDefault();
        setWorkspaceOpen(o => !o);
        return;
      }
      if (!m) return;
      const key = e.key.toLowerCase();
      if (key === ",") {
        e.preventDefault();
        setSettings({
          open: true,
          front: true
        });
      } else if (key === "f") {
        e.preventDefault();
        openSearch();
      } else if (key === "z" && !typing) {
        e.preventDefault();
        e.shiftKey ? redo() : undo();
      } else if (key === "r" && !e.shiftKey) {
        e.preventDefault();
        run();
      } else if (key === "k") {
        e.preventDefault();
        connected && toast("Tela capturada");
      } else if (key === "s") {
        e.preventDefault();
        steps.length && toast("onboarding_credito_objs.py salvo");
      } else if (["1", "2", "3"].includes(key)) {
        e.preventDefault();
        setSelectedStep(null);
        setSection(["pageObjects", "network", "analytics"][+key - 1]);
      }
    };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  });

  // Toolbar adaptável: com pouco espaço, itens de menor prioridade vão para o menu » e o segmentado vira pop-up.
  const mainW = win.w - sbW - inW;
  const compact = mainW < 700,
    tight = mainW < 560;
  const [overflow, setOverflow] = React.useState(null);
  const overflowBtn = React.useRef(null);
  const recItems = [{
    label: passive ? "Parar Captura" : "Gravar do Aparelho",
    icon: passive ? "square" : "hand",
    on: passive,
    fn: () => setPassive(p => !p),
    tip: passive ? "Para de gravar os toques feitos no aparelho" : "Grava o que você fizer direto no aparelho, sem clicar no espelho"
  }, {
    label: screenRec ? "Parar de Gravar a Tela" : "Gravar a Tela",
    icon: screenRec ? "square" : "video",
    on: screenRec,
    fn: () => setScreenRec(r => !r),
    tip: screenRec ? "Encerra a gravação e salva o vídeo" : "Grava vídeo da tela do aparelho"
  }];
  if (dev.platform === "android") recItems.push({
    label: "Espelho 60 FPS",
    icon: "activity",
    on: scrcpy,
    fn: () => setScrcpy(s => !s),
    tip: "Abrir espelho nativo a 60 FPS (scrcpy)"
  });
  const deviceOptions = [{
    header: "iOS"
  }, ...D.devices.filter(d => d.platform === "ios"), {
    header: "Android"
  }, ...D.devices.filter(d => d.platform === "android")];
  const subtitle = !connected ? "Nenhum dispositivo" : effSection === "pageObjects" ? (selectedStep ? "Passo " + (steps.findIndex(s => s.id === selectedStep) + 1) + " de " + steps.length : steps.length + " passos") + " · " + dev.name : effSection === "network" ? data.requests.length + " requisições" : data.events.length + " eventos";
  const leftPad = Math.max(12, 116 - sbW);
  const noteKey = settings.front ? "settings" : effSection;
  const [vp, setVp] = React.useState({
    w: window.innerWidth,
    h: window.innerHeight
  });
  React.useEffect(() => {
    const r = () => setVp({
      w: window.innerWidth,
      h: window.innerHeight
    });
    window.addEventListener("resize", r);
    return () => window.removeEventListener("resize", r);
  }, []);
  // Ajusta a página inteira ao painel de visualização (a janela tem 1280×800 pt de referência).
  const zoom = Math.min(1, (vp.w - 16) / (win.w + 40), (vp.h - 8) / (win.h + 60));
  React.useEffect(() => {
    document.documentElement.style.zoom = zoom;
  }, [zoom]);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(MenuBar, {
    menus: menus,
    right: /*#__PURE__*/React.createElement("span", null, "qui 8 out  15:31")
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      minHeight: win.h + 60,
      display: "flex",
      justifyContent: "center",
      paddingTop: 22
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative"
    },
    onMouseDown: () => settings.front && setSettings(s => ({
      ...s,
      front: false
    }))
  }, /*#__PURE__*/React.createElement(Window, {
    active: windowActive,
    width: win.w,
    height: win.h,
    ariaLabel: SECTION_TITLE[section] || "Mo baile"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "flex",
      minHeight: 0,
      position: "relative"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: sbW,
      flex: "none",
      overflow: "hidden",
      position: "relative",
      zIndex: 2
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: sidebarW,
      height: "100%",
      transform: "translateX(" + (sbW - sidebarW) + "px)"
    }
  }, /*#__PURE__*/React.createElement(AppSidebar, {
    width: sidebarW,
    section: section,
    selectedStep: selectedStep,
    onSection: s => {
      setSelectedStep(null);
      setSection(s);
    },
    onStep: goStep,
    steps: steps,
    counts: {
      steps: steps.length,
      requests: data.requests.length,
      events: data.events.length
    },
    onReorder: reorder,
    onDelete: deleteStep,
    onRecord: () => {
      setMode("record");
      setSection("pageObjects");
      toast("Gravar passo: clique em um elemento no espelho");
    },
    newIds: newIds,
    device: dev.name,
    connected: connected,
    scanning: scenario === "checking",
    sidebarSize: prefs.sidebarSize
  }))), sbW > 1 && /*#__PURE__*/React.createElement(Splitter, {
    ariaLabel: "Redimensionar barra lateral",
    onDrag: d => {
      setDragging(true);
      setSidebarW(w => Math.max(232, Math.min(360, w + d)));
    },
    onDragEnd: () => setDragging(false)
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: "flex",
      flexDirection: "column",
      background: "var(--bg-content)"
    },
    onMouseDown: () => setFocusPane("content")
  }, /*#__PURE__*/React.createElement(Toolbar, {
    style: {
      paddingLeft: leftPad,
      paddingRight: inW > 1 ? 10 : 56,
      borderBottom: "1px solid var(--separator)"
    }
  }, /*#__PURE__*/React.createElement(ToolbarTitle, {
    title: connected ? SECTION_TITLE[section] : "Sem dispositivo",
    subtitle: subtitle
  }), /*#__PURE__*/React.createElement(PopUpButton, {
    variant: "plain",
    ariaLabel: "Dispositivo",
    disabled: !connected && scenario === "checking",
    label: /*#__PURE__*/React.createElement("span", {
      style: {
        display: "inline-flex",
        alignItems: "center",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: connected ? "circle-check" : "circle-x",
      size: 12,
      strokeWidth: 2.2,
      color: connected ? "var(--success)" : "var(--destructive)"
    }), connected ? dev.name : "Nenhum dispositivo"),
    options: [],
    extraItems: [...deviceOptions.map(o => o.header ? {
      header: o.header
    } : {
      label: o.name + "  ·  " + o.detail,
      checked: connected && o.id === device,
      disabled: o.off || !connected,
      onSelect: () => {
        setDevice(o.id);
        toast(o.name + " selecionado");
      }
    }), {
      separator: true
    }, {
      label: "Atualizar Lista",
      shortcut: "⇧⌘R",
      onSelect: () => toast("Lista de aparelhos atualizada")
    }]
  }), tight ? /*#__PURE__*/React.createElement(PopUpButton, {
    size: "small",
    ariaLabel: "A\xE7\xE3o do clique no espelho",
    disabled: !connected,
    value: mode,
    onChange: setMode,
    options: [{
      value: "forward",
      label: "Repassar toque"
    }, {
      value: "record",
      label: "Gravar passo"
    }]
  }) : /*#__PURE__*/React.createElement(Tooltip, {
    label: "Define o que acontece ao clicar no espelho"
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    ariaLabel: "A\xE7\xE3o do clique no espelho",
    disabled: !connected,
    value: mode,
    onChange: setMode,
    items: [{
      value: "forward",
      label: "Repassar toque",
      icon: "pointer"
    }, {
      value: "record",
      label: "Gravar passo",
      icon: "circle-dot"
    }]
  })), /*#__PURE__*/React.createElement(ToolbarSpacer, null), compact ? /*#__PURE__*/React.createElement(ToolbarGroup, null, /*#__PURE__*/React.createElement(ToolbarButton, {
    ref: overflowBtn,
    icon: "chevrons-right",
    label: "Mais itens",
    disabled: !connected,
    onClick: () => {
      const r = overflowBtn.current.getBoundingClientRect();
      setOverflow({
        x: r.left,
        y: r.bottom + 6
      });
    }
  })) : /*#__PURE__*/React.createElement(ToolbarGroup, {
    ariaLabel: "Grava\xE7\xE3o"
  }, recItems.map(it => /*#__PURE__*/React.createElement(ToolbarButton, {
    key: it.icon,
    icon: it.icon,
    label: it.tip,
    disabled: !connected,
    variant: it.on && it.icon === "square" ? "recording" : undefined,
    on: it.on,
    onClick: it.fn
  }))), /*#__PURE__*/React.createElement(ToolbarGroup, {
    tinted: true
  }, /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "play",
    label: "Rodar Automa\xE7\xE3o",
    shortcut: "\u2318R",
    variant: "tinted",
    disabled: !steps.length || !connected,
    onClick: run
  })), section !== "pageObjects" && connected ? /*#__PURE__*/React.createElement(ToolbarSearch, {
    inputRef: tbSearch,
    open: searchOpen || !!filter[section],
    onOpenChange: setSearchOpen,
    value: filter[section] || "",
    onChange: v => setFilter(f => ({
      ...f,
      [section]: v
    })),
    placeholder: section === "network" ? "Filtrar host, path ou status" : "Filtrar eventos e tags"
  }) : /*#__PURE__*/React.createElement(ToolbarGroup, null, /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "search",
    label: "Buscar na hierarquia",
    shortcut: "\u2318F",
    onClick: openSearch
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "flex",
      minHeight: 0,
      opacity: fade,
      transition: "opacity var(--motion-crossfade) linear"
    }
  }, showMirror && /*#__PURE__*/React.createElement("div", {
    style: {
      width: showWork ? section === "pageObjects" ? mirrorW : 230 : "100%",
      flex: showWork ? "none" : 1
    }
  }, /*#__PURE__*/React.createElement(MirrorPane, {
    compact: section !== "pageObjects" && showWork,
    connected: connected,
    loading: loading,
    mode: mode,
    nodes: D.nodes,
    selectedId: nodeSel,
    onSelectNode: setNodeSel,
    onTap: onTap,
    fps: 24,
    section: section,
    correlationRef: corrRef,
    onCorrelation: () => setCorrOpen(o => !o),
    onRefresh: () => toast("Tela capturada")
  })), showMirror && showWork && /*#__PURE__*/React.createElement(Splitter, {
    ariaLabel: "Redimensionar espelho",
    onDrag: d => setMirrorW(w => Math.max(240, Math.min(420, w + d)))
  }), showWork && /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, effSection === "noDevice" ? /*#__PURE__*/React.createElement(NoDeviceView, {
    phase: scenario,
    lastScan: scan,
    onRescan: () => {
      setScan(new Date().toTimeString().slice(0, 8));
      toast("Procurando dispositivos…");
    },
    onStartWDA: () => scenario === "iosReady" ? setDemo("scenario", "connected") : setDemo("scenario", "iosReady"),
    onOpenEmulator: () => toast("Abrindo emulador Pixel 7 API 34…")
  }) : section === "pageObjects" ? /*#__PURE__*/React.createElement(PageObjectsView, {
    steps: steps,
    strategy: strategy,
    setStrategy: setStrategy,
    split: split,
    setSplit: setSplit,
    activeStep: selectedStep,
    connected: connected,
    onStructure: () => setSheet("structure"),
    onToast: toast,
    onClearSteps: () => askClear("steps"),
    onRecordMode: () => {
      setMode("record");
      toast("Gravar passo ativo");
    }
  }) : section === "network" ? /*#__PURE__*/React.createElement(NetworkView, {
    rows: data.requests,
    proxyOn: proxyOn,
    setProxyOn: setProxyOn,
    debugOn: debugOn,
    setDebugOn: setDebugOn,
    filter: filter.network,
    selected: reqSel,
    setSelected: setReqSel,
    newKeys: newIds,
    onClear: () => askClear("network"),
    onToast: toast,
    error: netError,
    setError: setNetError,
    loading: loading
  }) : /*#__PURE__*/React.createElement(AnalyticsView, {
    rows: data.events,
    listening: listening,
    setListening: setListening,
    source: source,
    setSource: setSource,
    filter: filter.analytics,
    selected: evSel,
    setSelected: setEvSel,
    newKeys: newIds,
    onClear: () => askClear("analytics"),
    onToast: toast
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 22,
      flex: "none",
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "0 12px",
      borderTop: "1px solid var(--separator)",
      background: "var(--bg-content-alt)"
    }
  }, /*#__PURE__*/React.createElement(StatusIndicator, {
    status: connected && dev.platform === "ios" ? scenario === "error" ? "warn" : "ok" : "off",
    label: "WDA 8100"
  }), /*#__PURE__*/React.createElement(StatusIndicator, {
    status: dev.platform === "android" && connected ? "ok" : "busy",
    label: "ADB server"
  }), /*#__PURE__*/React.createElement(StatusIndicator, {
    status: netError ? "error" : proxyOn ? "ok" : "off",
    label: "Proxy MITM 8082"
  }), /*#__PURE__*/React.createElement(StatusIndicator, {
    status: listening ? "ok" : "off",
    label: "FA listener"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "mb-truncate",
    role: "status",
    "aria-live": "polite",
    style: {
      fontSize: 11,
      color: "var(--label-primary)"
    }
  }, msg), connected && /*#__PURE__*/React.createElement("span", {
    className: "mb-mono mb-tabular",
    style: {
      fontSize: 10.5,
      color: "var(--label-secondary)",
      whiteSpace: "nowrap"
    }
  }, "x ", cursor.x, " \xB7 y ", cursor.y, "  24 fps  settle 180 ms  lat\xEAncia 42 ms"))), inW > 1 && /*#__PURE__*/React.createElement(Splitter, {
    ariaLabel: "Redimensionar inspector",
    onDrag: d => {
      setDragging(true);
      setInspectorW(w => Math.max(260, Math.min(380, w - d)));
    },
    onDragEnd: () => setDragging(false)
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      width: inW,
      flex: "none",
      overflow: "hidden"
    },
    onMouseDown: () => setFocusPane("inspector")
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: inspectorW,
      height: "100%"
    }
  }, /*#__PURE__*/React.createElement(InspectorPane, {
    nodes: D.nodes,
    selectedId: nodeSel,
    onSelect: setNodeSel,
    state: !connected ? "empty" : loading ? "loading" : "ready",
    query: hierQuery,
    setQuery: setHierQuery,
    searchRef: hierSearch,
    onRecordNode: n => {
      setSection("pageObjects");
      recordStep(n);
    },
    toast: toast,
    focused: focusPane === "inspector" && windowActive
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      top: 0,
      height: 52,
      display: "flex",
      alignItems: "center",
      zIndex: 10
    }
  }, /*#__PURE__*/React.createElement(TrafficLights, {
    onClose: () => toast("⌘W fecha a janela")
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 14
    }
  }), /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "panel-left",
    label: sidebarOpen ? "Ocultar Barra Lateral" : "Mostrar Barra Lateral",
    shortcut: "\u2303\u2318S",
    ariaPressed: sidebarOpen,
    onClick: () => setSidebarOpen(o => !o)
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      right: 10,
      top: 8,
      zIndex: 10
    }
  }, /*#__PURE__*/React.createElement(ToolbarGroup, null, /*#__PURE__*/React.createElement(ToolbarButton, {
    icon: "panel-right",
    label: inspectorOpen ? "Ocultar Inspector" : "Mostrar Inspector",
    shortcut: "\u2325\u2318I",
    ariaPressed: inspectorOpen,
    onClick: () => setInspectorOpen(o => !o)
  }))), /*#__PURE__*/React.createElement(StructureSheet, {
    open: sheet === "structure",
    steps: steps,
    onClose: () => setSheet(null),
    onRun: run
  }), /*#__PURE__*/React.createElement(FlowRunnerSheet, {
    open: sheet === "runner",
    steps: steps,
    outcome: demo.outcome,
    onClose: () => setSheet(null),
    onToast: toast
  }), /*#__PURE__*/React.createElement(Alert, {
    open: !!alert,
    iconSrc: "../../assets/app-icon.png",
    title: {
      network: "Limpar o tráfego capturado?",
      analytics: "Limpar os eventos capturados?",
      steps: "Limpar todos os passos do fluxo?"
    }[alert],
    message: alert === "network" ? data.requests.length + " requisições serão removidas. Você pode desfazer com ⌘Z." : alert === "analytics" ? data.events.length + " eventos serão removidos. Você pode desfazer com ⌘Z." : "O Page Object e os locators gerados serão esvaziados. Você pode desfazer com ⌘Z.",
    buttons: [{
      label: {
        network: "Limpar Tráfego",
        analytics: "Limpar Eventos",
        steps: "Limpar Passos"
      }[alert] || "",
      role: "destructive",
      onClick: () => doClear(alert)
    }, {
      label: "Cancelar",
      role: "default",
      onClick: () => setAlert(null)
    }],
    onCancel: () => setAlert(null)
  })), /*#__PURE__*/React.createElement("span", {
    "aria-label": "Redimensionar janela",
    style: {
      position: "absolute",
      right: 0,
      bottom: 0,
      width: 14,
      height: 14,
      cursor: "nwse-resize",
      zIndex: 20
    },
    onPointerDown: e => {
      e.preventDefault();
      let x = e.clientX,
        y = e.clientY;
      setDragging(true);
      const mv = ev => {
        setWin(w => ({
          w: Math.max(980, w.w + (ev.clientX - x) / zoom),
          h: Math.max(600, w.h + (ev.clientY - y) / zoom)
        }));
        x = ev.clientX;
        y = ev.clientY;
      };
      const up = () => {
        setDragging(false);
        window.removeEventListener("pointermove", mv);
        window.removeEventListener("pointerup", up);
      };
      window.addEventListener("pointermove", mv);
      window.addEventListener("pointerup", up);
    }
  })), /*#__PURE__*/React.createElement(SplashWindow, {
    show: splash
  })), /*#__PURE__*/React.createElement(SettingsWindow, {
    open: settings.open,
    active: settings.front && demo.active,
    onFocus: () => setSettings(s => ({
      ...s,
      front: true
    })),
    onClose: () => setSettings({
      open: false,
      front: false
    }),
    prefs: prefs,
    setPref: setPref
  })), /*#__PURE__*/React.createElement(Popover, {
    open: corrOpen,
    anchorRef: corrRef,
    onClose: () => setCorrOpen(false),
    placement: "top",
    width: 300,
    ariaLabel: "Correla\xE7\xE3o"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 14,
      display: "flex",
      flexDirection: "column",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("b", {
    style: {
      fontWeight: 700
    }
  }, "Correla\xE7\xE3o \xB7 passo ", steps.length), /*#__PURE__*/React.createElement("div", {
    style: {
      color: "var(--label-secondary)",
      fontSize: 12
    }
  }, "O \xFAltimo toque disparou ", Math.min(3, data.requests.length), " requisi\xE7\xF5es e 1 evento de analytics."), /*#__PURE__*/React.createElement("div", {
    className: "mb-mono",
    style: {
      fontSize: 10.5,
      lineHeight: "14px",
      color: "var(--label-secondary)",
      background: "var(--fill-tertiary)",
      borderRadius: 8,
      padding: 8,
      userSelect: "text"
    }
  }, "AutomationStep(stepNum: ", steps.length, ", actionType: \"click\", varName: \"", steps.length ? steps[steps.length - 1].varName : "—", "\", strategy: coords, platform: ios)"), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    variant: "default",
    onClick: () => {
      setCorrOpen(false);
      toast("Asserção de contrato gerada e inserida no código");
    }
  }, "Gerar Asser\xE7\xE3o de Contrato")))), overflow && /*#__PURE__*/React.createElement(Menu, {
    x: overflow.x,
    y: overflow.y,
    onClose: () => setOverflow(null),
    items: recItems.map(it => ({
      label: it.label,
      icon: it.icon,
      onSelect: it.fn
    }))
  }), /*#__PURE__*/React.createElement(DemoPanel, {
    demo: demo,
    setDemo: setDemo,
    appearance: dark ? "dark" : "light",
    setAppearance: v => setPref("appearance", v),
    noteKey: noteKey,
    collapsed: demoCollapsed,
    setCollapsed: setDemoCollapsed
  }));
}
Object.assign(window, {
  App
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/App.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/AppSidebar.jsx
try { (() => {
// Sidebar do app: Workspace (3 áreas) + Fluxo (passos gravados, reordenáveis por arraste).
const ACTION_ICON = {
  click: "pointer",
  send_keys: "keyboard"
};
function StepsList({
  steps,
  selected,
  onSelect,
  onReorder,
  onDelete,
  onReveal,
  newIds,
  sidebarSize
}) {
  const {
    SidebarItem,
    ContextMenu
  } = window.MoBaileDesignSystem_ce6669;
  const rowH = sidebarSize === "small" ? 24 : sidebarSize === "large" ? 32 : 28;
  const [drag, setDrag] = React.useState(null);
  const start = (e, i) => {
    if (e.button !== 0) return;
    const y0 = e.clientY;
    let started = false;
    const mv = ev => {
      const dy = ev.clientY - y0;
      if (!started && Math.abs(dy) < 4) return;
      started = true;
      setDrag({
        from: i,
        dy,
        to: Math.max(0, Math.min(steps.length - 1, i + Math.round(dy / rowH)))
      });
    };
    const up = () => {
      window.removeEventListener("pointermove", mv);
      window.removeEventListener("pointerup", up);
      setDrag(d => {
        if (d && d.to !== d.from) onReorder(d.from, d.to);
        return null;
      });
    };
    window.addEventListener("pointermove", mv);
    window.addEventListener("pointerup", up);
  };
  const shift = i => {
    if (!drag || i === drag.from) return 0;
    if (drag.from < drag.to && i > drag.from && i <= drag.to) return -rowH;
    if (drag.from > drag.to && i < drag.from && i >= drag.to) return rowH;
    return 0;
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative"
    }
  }, steps.map((s, i) => {
    const isDrag = drag && drag.from === i;
    const menu = [{
      label: "Mostrar no Código",
      onSelect: () => onReveal(s.id)
    }, {
      label: "Copiar Locator",
      shortcut: "⌘C",
      onSelect: () => navigator.clipboard && navigator.clipboard.writeText(s.varName).catch(() => {})
    }, {
      separator: true
    }, {
      label: "Mover para Cima",
      disabled: i === 0,
      onSelect: () => onReorder(i, i - 1)
    }, {
      label: "Mover para Baixo",
      disabled: i === steps.length - 1,
      onSelect: () => onReorder(i, i + 1)
    }, {
      separator: true
    }, {
      label: "Excluir Passo",
      shortcut: "⌫",
      destructive: true,
      onSelect: () => onDelete(s.id)
    }];
    return /*#__PURE__*/React.createElement(ContextMenu, {
      key: s.id,
      items: menu,
      onOpen: () => onSelect(s.id),
      className: newIds.includes(s.id) ? "mb-step-new" : undefined,
      style: {
        position: "relative",
        zIndex: isDrag ? 5 : 1,
        transform: "translateY(" + (isDrag ? drag.dy : shift(i)) + "px)" + (isDrag ? " scale(1.02)" : ""),
        transition: isDrag ? "none" : "transform var(--spring-smooth-duration) var(--spring-smooth-ease)",
        boxShadow: isDrag ? "var(--shadow-drag)" : "none",
        borderRadius: 8,
        background: isDrag ? "var(--bg-content)" : undefined
      }
    }, /*#__PURE__*/React.createElement("div", {
      onPointerDown: e => start(e, i),
      onKeyDown: e => {
        if (e.key === "Backspace" || e.key === "Delete") onDelete(s.id);
      }
    }, /*#__PURE__*/React.createElement(SidebarItem, {
      icon: s.strategy === "coords" ? "scan-search" : ACTION_ICON[s.action],
      iconColor: "var(--label-secondary)",
      label: s.action + " " + s.element,
      selected: selected === s.id,
      onSelect: () => onSelect(s.id),
      trailing: s.value ? /*#__PURE__*/React.createElement("span", {
        className: "mb-mono",
        style: {
          fontSize: 10.5,
          color: "var(--label-tertiary)"
        }
      }, s.value) : null
    })));
  }));
}
function AppSidebar({
  width,
  section,
  selectedStep,
  onSection,
  onStep,
  steps,
  counts,
  onReorder,
  onDelete,
  onRecord,
  newIds,
  device,
  connected,
  scanning,
  sidebarSize
}) {
  const {
    Sidebar,
    SidebarSection,
    SidebarItem,
    SidebarBottomBar,
    StatusIndicator,
    EmptyState
  } = window.MoBaileDesignSystem_ce6669;
  const sel = k => !selectedStep && section === k;
  return /*#__PURE__*/React.createElement(Sidebar, {
    width: width,
    header: /*#__PURE__*/React.createElement("div", {
      style: {
        width: "100%"
      }
    }),
    bottomBar: /*#__PURE__*/React.createElement(SidebarBottomBar, {
      actions: [{
        icon: "plus",
        label: "Gravar Passo",
        onClick: onRecord,
        disabled: !connected
      }, {
        icon: "minus",
        label: "Excluir Passo",
        onClick: () => selectedStep && onDelete(selectedStep),
        disabled: !selectedStep
      }],
      status: /*#__PURE__*/React.createElement(StatusIndicator, {
        mono: false,
        status: connected ? "ok" : scanning ? "busy" : "off",
        label: connected ? device + " conectado" : scanning ? "Procurando…" : "Sem aparelho"
      })
    })
  }, /*#__PURE__*/React.createElement(SidebarSection, {
    title: "Workspace"
  }, /*#__PURE__*/React.createElement(SidebarItem, {
    icon: "file-code",
    iconColor: "var(--cat-1)",
    label: "Page Objects",
    count: counts.steps || null,
    selected: sel("pageObjects"),
    onSelect: () => onSection("pageObjects")
  }), /*#__PURE__*/React.createElement(SidebarItem, {
    icon: "network",
    iconColor: "var(--cat-3)",
    label: "Rede HTTP",
    count: counts.requests || null,
    selected: sel("network"),
    onSelect: () => onSection("network")
  }), /*#__PURE__*/React.createElement(SidebarItem, {
    icon: "chart-line",
    iconColor: "var(--cat-2)",
    label: "Analytics",
    count: counts.events || null,
    selected: sel("analytics"),
    onSelect: () => onSection("analytics")
  })), /*#__PURE__*/React.createElement(SidebarSection, {
    title: "Fluxo \xB7 onboarding_credito"
  }, steps.length ? /*#__PURE__*/React.createElement(StepsList, {
    steps: steps,
    selected: selectedStep,
    onSelect: onStep,
    onReorder: onReorder,
    onDelete: onDelete,
    onReveal: onStep,
    newIds: newIds,
    sidebarSize: sidebarSize
  }) : /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "4px 8px",
      fontSize: 12,
      color: "var(--label-secondary)"
    }
  }, "Nenhum passo gravado.")));
}
Object.assign(window, {
  AppSidebar
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/AppSidebar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/Demo.jsx
try { (() => {
// Painel do protótipo (fora do app): aparência, acessibilidade, estados e nota da tela atual.
const MB_NOTES = {
  pageObjects: "Page Objects. Antes: 3 colunas fixas (espelho | hierarquia | código) e duas barras no topo. Agora: as áreas viram itens da sidebar, a hierarquia vai para o Inspector recolhível e o seletor (Auto/ID/XPath/Coords), Estrutura e Lado a lado ficam na barra acessória, só sobre o conteúdo. Os passos gravados aparecem na sidebar, com arraste, menu de contexto e desfazer.",
  network: "Rede HTTP. Antes: os botões do proxy dividiam a barra com o filtro. Agora o filtro é a busca da toolbar (⌘F). Proxy, iPhone em Debug, Exportar HAR… e Limpar Tráfego ficam na barra acessória. A tabela tem colunas ordenáveis e redimensionáveis. Limpar pede confirmação e pode ser desfeito. O cartão de Correlação virou um popover.",
  analytics: "Analytics. Mesma estrutura de Rede para a mesma tarefa: estado do listener, origem do tagueamento (pop-up desabilitado durante a escuta), Iniciar/Parar, Copiar TSV, Exportar JSON… e Limpar. O detalhe divide Parâmetros e Log bruto.",
  noDevice: "Sem dispositivo. O conteúdo e os cartões de diagnóstico são os mesmos do original, com uma diferença: o checklist agora usa ícone, cor e texto juntos. A busca roda de novo a cada 1,5 s, e “Verificar de Novo” força uma busca na hora.",
  settings: "Ajustes (⌘,). Janela separada com abas por ícone. Aparência e o seletor padrão saíram da barra principal. Portas e host vêm do .env. Cada mudança vale na hora, sem botão Salvar."
};
function DemoPanel({
  demo,
  setDemo,
  appearance,
  setAppearance,
  noteKey,
  collapsed,
  setCollapsed
}) {
  const {
    Switch,
    SegmentedControl,
    PopUpButton,
    Icon
  } = window.MoBaileDesignSystem_ce6669;
  const row = (label, ctrl) => /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 10,
      minHeight: 24
    }
  }, /*#__PURE__*/React.createElement("span", null, label), ctrl);
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-root",
    style: {
      position: "fixed",
      right: 14,
      bottom: 14,
      zIndex: 3000,
      width: 272,
      borderRadius: 14,
      background: "var(--glass-bg-strong)",
      WebkitBackdropFilter: "var(--glass-filter)",
      backdropFilter: "var(--glass-filter)",
      boxShadow: "var(--glass-highlight), var(--shadow-popover)",
      fontSize: 12
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: () => setCollapsed(!collapsed),
    style: {
      all: "unset",
      display: "flex",
      alignItems: "center",
      gap: 6,
      width: "100%",
      boxSizing: "border-box",
      padding: "9px 12px",
      fontWeight: 600,
      cursor: "default"
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sliders-horizontal",
    size: 14
  }), " ", /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }, "Prot\xF3tipo"), /*#__PURE__*/React.createElement(Icon, {
    name: collapsed ? "chevron-up" : "chevron-down",
    size: 13
  })), !collapsed && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "0 12px 12px",
      display: "flex",
      flexDirection: "column",
      gap: 6
    }
  }, row("Aparência", /*#__PURE__*/React.createElement(SegmentedControl, {
    size: "small",
    items: [{
      value: "light",
      label: "Claro"
    }, {
      value: "dark",
      label: "Escuro"
    }],
    value: appearance,
    onChange: setAppearance
  })), row("Janela ativa", /*#__PURE__*/React.createElement(Switch, {
    size: "small",
    checked: demo.active,
    onChange: v => setDemo("active", v)
  })), row("Reduzir movimento", /*#__PURE__*/React.createElement(Switch, {
    size: "small",
    checked: demo.reduceMotion,
    onChange: v => setDemo("reduceMotion", v)
  })), row("Reduzir transparência", /*#__PURE__*/React.createElement(Switch, {
    size: "small",
    checked: demo.reduceTransparency,
    onChange: v => setDemo("reduceTransparency", v)
  })), row("Aumentar contraste", /*#__PURE__*/React.createElement(Switch, {
    size: "small",
    checked: demo.contrast,
    onChange: v => setDemo("contrast", v)
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 1,
      background: "var(--separator)",
      margin: "4px 0"
    }
  }), row("Estado", /*#__PURE__*/React.createElement(PopUpButton, {
    size: "small",
    minWidth: 150,
    value: demo.scenario,
    onChange: v => setDemo("scenario", v),
    options: [{
      value: "connected",
      label: "Conectado"
    }, {
      value: "loading",
      label: "Carregando"
    }, {
      value: "error",
      label: "Erro (proxy)"
    }, "-", {
      value: "checking",
      label: "Sem aparelho · verificando"
    }, {
      value: "noDevice",
      label: "Sem aparelho"
    }, {
      value: "iosReady",
      label: "Sem aparelho · iOS pronto"
    }]
  })), row("Execução do fluxo", /*#__PURE__*/React.createElement(SegmentedControl, {
    size: "small",
    items: [{
      value: "pass",
      label: "Sucesso"
    }, {
      value: "fail",
      label: "Falha"
    }],
    value: demo.outcome,
    onChange: v => setDemo("outcome", v)
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 1,
      background: "var(--separator)",
      margin: "4px 0"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      fontWeight: 600,
      color: "var(--label-secondary)"
    }
  }, "O que mudou nesta tela"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      lineHeight: "15px",
      color: "var(--label-secondary)",
      textWrap: "pretty",
      maxHeight: 150,
      overflow: "auto"
    }
  }, MB_NOTES[noteKey])));
}
Object.assign(window, {
  DemoPanel,
  MB_NOTES
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/Demo.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/Inspector.jsx
try { (() => {
// Inspector: hierarquia de acessibilidade (árvore com busca) + atributos do elemento selecionado.
function InspectorPane({
  nodes,
  selectedId,
  onSelect,
  state,
  query,
  setQuery,
  searchRef,
  onRecordNode,
  toast,
  focused
}) {
  const {
    SearchField,
    TypeChip,
    Icon,
    Button,
    EmptyState,
    ContextMenu,
    Tooltip
  } = window.MoBaileDesignSystem_ce6669;
  const [collapsed, setCollapsed] = React.useState({});
  const hasKids = i => nodes[i + 1] && nodes[i + 1].depth > nodes[i].depth;
  const q = query.trim().toLowerCase();
  const visible = [];
  let hideBelow = null;
  nodes.forEach((n, i) => {
    if (hideBelow != null && n.depth > hideBelow) return;
    hideBelow = null;
    if (q && !(n.label + " " + n.attrs.type + " " + n.attrs.name).toLowerCase().includes(q)) return;
    visible.push({
      n,
      i
    });
    if (!q && collapsed[n.id] && hasKids(i)) hideBelow = n.depth;
  });
  const sel = nodes.find(n => n.id === selectedId);
  const onKey = e => {
    const k = visible.findIndex(v => v.n.id === selectedId);
    if (e.key === "ArrowDown") {
      e.preventDefault();
      const v = visible[Math.min(visible.length - 1, k + 1)];
      v && onSelect(v.n.id);
    }
    if (e.key === "ArrowUp") {
      e.preventDefault();
      const v = visible[Math.max(0, k - 1)];
      v && onSelect(v.n.id);
    }
    if (e.key === "ArrowLeft" && sel) setCollapsed(c => ({
      ...c,
      [sel.id]: true
    }));
    if (e.key === "ArrowRight" && sel) setCollapsed(c => ({
      ...c,
      [sel.id]: false
    }));
  };
  const copy = (txt, msg) => {
    navigator.clipboard && navigator.clipboard.writeText(txt).catch(() => {});
    toast(msg);
  };
  const menu = n => [{
    label: "Copiar Locator",
    shortcut: "⌘C",
    onSelect: () => copy(n.var || n.label, "Locator copiado")
  }, {
    label: "Copiar XPath",
    shortcut: "⌥⌘C",
    onSelect: () => copy("//" + n.attrs.type + "[@name=\"" + n.attrs.name + "\"]", "XPath copiado")
  }, {
    label: "Copiar Atributos",
    onSelect: () => copy(JSON.stringify(n.attrs, null, 2), "Atributos copiados")
  }, {
    separator: true
  }, {
    label: "Gravar como Passo",
    disabled: !n.box,
    onSelect: () => onRecordNode(n)
  }];
  return /*#__PURE__*/React.createElement("aside", {
    "aria-label": "Inspector",
    style: {
      height: "100%",
      display: "flex",
      flexDirection: "column",
      background: "var(--bg-content)",
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      height: "var(--toolbar-height)",
      flex: "none",
      display: "flex",
      alignItems: "center",
      padding: "0 52px 0 14px"
    }
  }, /*#__PURE__*/React.createElement("b", {
    style: {
      fontSize: 13,
      fontWeight: 700
    }
  }, "Hierarquia"), /*#__PURE__*/React.createElement("span", {
    className: "mb-count",
    style: {
      marginLeft: 6
    }
  }, state === "ready" ? nodes.length : "")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "0 10px 8px",
      flex: "none"
    }
  }, /*#__PURE__*/React.createElement(SearchField, {
    inputRef: searchRef,
    value: query,
    onChange: setQuery,
    placeholder: "Buscar texto, ID ou XPath",
    shortcut: "\u2318F"
  })), /*#__PURE__*/React.createElement("div", {
    className: "mb-splitter mb-splitter--h",
    style: {
      pointerEvents: "none"
    }
  }), /*#__PURE__*/React.createElement("div", {
    role: "tree",
    tabIndex: 0,
    onKeyDown: onKey,
    "aria-label": "\xC1rvore de acessibilidade",
    style: {
      flex: 1,
      overflow: "auto",
      padding: "4px 6px"
    }
  }, state === "loading" && /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    loading: true,
    text: "Lendo a hierarquia\u2026"
  }), state === "empty" && /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    icon: "list-tree",
    text: "Conecte um aparelho para ver a hierarquia da tela."
  }), state === "ready" && visible.length === 0 && /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    icon: "search",
    title: "Nenhum elemento encontrado",
    text: "Nada corresponde a “" + query + "”."
  }), state === "ready" && visible.map(({
    n,
    i
  }) => /*#__PURE__*/React.createElement(ContextMenu, {
    key: n.id,
    items: () => menu(n),
    onOpen: () => onSelect(n.id)
  }, /*#__PURE__*/React.createElement("div", {
    role: "treeitem",
    "aria-selected": n.id === selectedId,
    "aria-expanded": hasKids(i) ? !collapsed[n.id] : undefined,
    className: "mb-sb-item" + (n.id === selectedId ? " is-selected" : ""),
    onMouseDown: () => onSelect(n.id),
    title: n.label,
    style: {
      height: 24,
      fontSize: 12,
      paddingLeft: 4 + (q ? 0 : n.depth * 14),
      gap: 5,
      "--selection": focused ? "var(--accent)" : "var(--selection-inactive)",
      color: n.id === selectedId && !focused ? "var(--label-primary)" : undefined
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 12,
      display: "grid",
      placeItems: "center",
      flex: "none"
    },
    onMouseDown: e => {
      if (hasKids(i)) {
        e.stopPropagation();
        setCollapsed(c => ({
          ...c,
          [n.id]: !c[n.id]
        }));
      }
    }
  }, hasKids(i) && !q && /*#__PURE__*/React.createElement(Icon, {
    name: "chevron-right",
    size: 11,
    strokeWidth: 2.2,
    style: {
      transform: collapsed[n.id] ? "none" : "rotate(90deg)",
      transition: "transform var(--spring-snappy-duration) var(--spring-snappy-ease)",
      color: "currentColor"
    }
  })), /*#__PURE__*/React.createElement(TypeChip, {
    type: n.type
  }), /*#__PURE__*/React.createElement("span", {
    className: "mb-sb-item__label"
  }, n.label))))), /*#__PURE__*/React.createElement("div", {
    className: "mb-splitter mb-splitter--h",
    style: {
      pointerEvents: "none"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: "none",
      height: 196,
      display: "flex",
      flexDirection: "column",
      padding: "8px 14px 12px",
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      fontSize: 11,
      fontWeight: 600,
      color: "var(--label-secondary)"
    }
  }, "Atributos"), /*#__PURE__*/React.createElement(Button, {
    size: "mini",
    variant: "plain",
    disabled: !sel || state !== "ready",
    onClick: () => copy(JSON.stringify(sel.attrs, null, 2), "Atributos copiados")
  }, "Copiar Tudo")), sel && state === "ready" ? /*#__PURE__*/React.createElement("div", {
    className: "mb-mono",
    style: {
      display: "grid",
      gridTemplateColumns: "64px 1fr",
      gap: "3px 8px",
      fontSize: 11,
      lineHeight: "15px",
      userSelect: "text",
      cursor: "text"
    }
  }, Object.entries(sel.attrs).map(([k, v]) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: k
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--label-secondary)",
      textAlign: "right"
    }
  }, k), /*#__PURE__*/React.createElement("span", {
    className: "mb-truncate",
    title: v
  }, v || "—")))) : /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      color: "var(--label-secondary)",
      textAlign: "center",
      paddingTop: 30
    }
  }, "Nenhum elemento selecionado")));
}
Object.assign(window, {
  InspectorPane
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/Inspector.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/Mirror.jsx
try { (() => {
// Coluna do espelho ao vivo: tela do aparelho, destaque do elemento sob o cursor, clique vira toque/passo.
function MirrorPane({
  compact,
  connected,
  loading,
  mode,
  nodes,
  selectedId,
  onSelectNode,
  onTap,
  fps,
  section,
  steps,
  correlationRef,
  onCorrelation,
  onRefresh
}) {
  const {
    DeviceFrame,
    Button,
    Icon,
    ProgressIndicator,
    Tooltip,
    ToolbarButton,
    ToolbarGroup,
    EmptyState
  } = window.MoBaileDesignSystem_ce6669;
  const [hover, setHover] = React.useState(null);
  const [ripples, setRipples] = React.useState([]);
  const screen = React.useRef(null);
  const W = compact ? 176 : 222,
    H = compact ? 368 : 464;
  const hit = e => {
    const r = screen.current.getBoundingClientRect();
    const px = (e.clientX - r.left) / r.width * 100,
      py = (e.clientY - r.top) / r.height * 100;
    return {
      px,
      py,
      node: nodes.filter(n => n.box).find(n => px >= n.box[0] && px <= n.box[0] + n.box[2] && py >= n.box[1] && py <= n.box[1] + n.box[3])
    };
  };
  const click = e => {
    if (!connected || loading) return;
    const {
      px,
      py,
      node
    } = hit(e);
    const id = Date.now();
    setRipples(rs => [...rs, {
      id,
      px,
      py
    }]);
    setTimeout(() => setRipples(rs => rs.filter(r => r.id !== id)), 420);
    if (node) onSelectNode(node.id);
    onTap && onTap(node, {
      px,
      py
    });
  };
  const hv = nodes.find(n => n.id === (hover || selectedId));
  return /*#__PURE__*/React.createElement("section", {
    "aria-label": "Espelho",
    style: {
      width: "100%",
      height: "100%",
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      background: "var(--bg-content-alt)",
      position: "relative"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      alignSelf: "stretch",
      display: "flex",
      alignItems: "center",
      height: 30,
      padding: "0 12px",
      gap: 6,
      color: "var(--label-secondary)",
      fontSize: 11,
      fontWeight: 600
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }, "Espelho"), connected && !loading && /*#__PURE__*/React.createElement("span", {
    className: "mb-tabular",
    style: {
      fontWeight: 400,
      whiteSpace: "nowrap"
    }
  }, fps, " fps")), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "grid",
      placeItems: "center",
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement(DeviceFrame, {
    width: W,
    height: H,
    screenRef: screen,
    onMouseMove: e => {
      if (connected && !loading) {
        const h = hit(e);
        setHover(h.node ? h.node.id : null);
      }
    },
    onMouseLeave: () => setHover(null),
    onClick: click
  }, connected && !loading ? /*#__PURE__*/React.createElement(BankScreen, {
    scale: (W - 14) / 208
  }) : /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      inset: 0,
      display: "grid",
      placeItems: "center",
      background: "var(--bg-device-screen)"
    }
  }, loading ? /*#__PURE__*/React.createElement(ProgressIndicator, {
    kind: "spinner",
    size: 20
  }) : /*#__PURE__*/React.createElement("span", {
    className: "mb-mono",
    style: {
      fontSize: 11,
      color: "var(--label-secondary)"
    }
  }, "sem sinal")), connected && !loading && hv && hv.box && /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: hv.box[0] + "%",
      top: hv.box[1] + "%",
      width: hv.box[2] + "%",
      height: hv.box[3] + "%",
      border: "2px solid var(--accent)",
      borderRadius: 8,
      boxShadow: "0 0 0 4px var(--accent-tint)",
      pointerEvents: "none",
      transition: "all 120ms var(--ease-out-standard)",
      zIndex: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-mono",
    style: {
      position: "absolute",
      bottom: "100%",
      left: -2,
      marginBottom: 3,
      background: "var(--accent)",
      color: "#fff",
      fontSize: 9.5,
      padding: "1px 5px",
      borderRadius: 4,
      whiteSpace: "nowrap"
    }
  }, (hv.var || hv.label).toLowerCase(), hv.hit ? " · " + hv.hit : "")), ripples.map(r => /*#__PURE__*/React.createElement("span", {
    key: r.id,
    style: {
      position: "absolute",
      left: r.px + "%",
      top: r.py + "%",
      width: 26,
      height: 26,
      margin: -13,
      borderRadius: "50%",
      border: "2px solid #fff",
      boxShadow: "0 0 0 1px rgba(0,0,0,.2)",
      zIndex: 5,
      pointerEvents: "none",
      animation: "mb-ripple 300ms ease-out forwards"
    }
  })))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 8,
      padding: "12px 0 16px",
      alignItems: "center"
    }
  }, /*#__PURE__*/React.createElement(Tooltip, {
    label: "Atualizar tela  \u2318K"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "refresh-cw",
    disabled: !connected,
    onClick: onRefresh
  }, "Atualizar")), (section === "network" || section === "analytics") && /*#__PURE__*/React.createElement(Tooltip, {
    label: "Correla\xE7\xE3o do \xFAltimo toque"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "link",
    disabled: !connected,
    onClick: onCorrelation
  }, /*#__PURE__*/React.createElement("span", {
    ref: correlationRef
  }, "Correla\xE7\xE3o")))));
}

// Tela do app em teste (conteúdo do catálogo original: "Crédito pessoal").
function BankScreen({
  scale = 1
}) {
  const ink = "#17323F",
    blue = "#0F6E99";
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      top: 0,
      width: 208,
      height: 450,
      transform: "scale(" + scale + ")",
      transformOrigin: "0 0",
      background: "#fff",
      color: ink,
      fontFamily: "var(--font-ui)",
      letterSpacing: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      justifyContent: "space-between",
      padding: "13px 20px 0 22px",
      fontSize: 10.5,
      fontWeight: 600
    }
  }, /*#__PURE__*/React.createElement("span", null, "9:41"), /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .8
    }
  }, "\u25CF\u25CF\u25CF \u25AE")), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "9.5%",
      left: 0,
      right: 0,
      textAlign: "center",
      fontSize: 10.5,
      fontWeight: 600
    }
  }, "Cr\xE9dito pessoal"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "9.2%",
      left: "8%",
      color: blue,
      fontSize: 15,
      lineHeight: 1
    }
  }, "\u2039"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "19%",
      left: "50%",
      transform: "translateX(-50%)",
      width: 72,
      height: 72,
      borderRadius: 36,
      background: "#E3EEF3",
      display: "grid",
      placeItems: "center"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 32,
      height: 22,
      borderRadius: 4,
      background: blue,
      position: "relative"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      top: 6,
      height: 3,
      background: "#fff"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 5,
      bottom: 4,
      width: 6,
      height: 4,
      background: "#fff",
      borderRadius: 1
    }
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "41.5%",
      left: "8%",
      right: "8%",
      fontSize: 15,
      fontWeight: 700,
      lineHeight: "18px"
    }
  }, "Simule seu cr\xE9dito", /*#__PURE__*/React.createElement("br", null), "em minutos"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "50.5%",
      left: "8%",
      right: "8%",
      fontSize: 8,
      lineHeight: "11px",
      color: "#5A7C8B"
    }
  }, "Sem compromisso. A taxa aparece antes de voc\xEA contratar."), [["CPF", "000.000.000-00", 55.5], ["Valor desejado", "R$ 5.000,00", 65]].map(([l, p, t]) => /*#__PURE__*/React.createElement("div", {
    key: l,
    style: {
      position: "absolute",
      top: t + "%",
      left: "8%",
      right: "8%"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 7,
      color: "#5A7C8B",
      marginBottom: 2
    }
  }, l), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 26,
      border: "1px solid #CBDCE3",
      borderRadius: 6,
      fontSize: 8.5,
      color: "#9AB0BA",
      display: "flex",
      alignItems: "center",
      padding: "0 8px"
    }
  }, p))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "82%",
      left: "8%",
      right: "8%",
      height: "6%",
      borderRadius: 7,
      background: blue,
      color: "#fff",
      fontSize: 9.5,
      fontWeight: 600,
      display: "grid",
      placeItems: "center"
    }
  }, "Continuar"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      top: "90%",
      left: 0,
      right: 0,
      textAlign: "center",
      fontSize: 8.5,
      color: blue,
      fontWeight: 500
    }
  }, "Agora n\xE3o"), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      bottom: 7,
      left: "50%",
      transform: "translateX(-50%)",
      width: 80,
      height: 3,
      borderRadius: 2,
      background: ink
    }
  }));
}
Object.assign(window, {
  MirrorPane,
  BankScreen
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/Mirror.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/NoDevice.jsx
try { (() => {
// Sem dispositivo: placeholder do aparelho + diagnóstico do ambiente por plataforma.
function NoDeviceView({
  phase,
  onStartWDA,
  onOpenEmulator,
  onRescan,
  lastScan
}) {
  const {
    DiagnosticCard,
    Button,
    PopUpButton,
    Icon
  } = window.MoBaileDesignSystem_ce6669;
  const checking = phase === "checking";
  const iosReady = phase === "iosReady";
  const ios = checking ? null : [{
    label: "Ferramentas do Xcode",
    detail: "xcrun disponível",
    state: "ok"
  }, {
    label: "Simulador instalado",
    detail: "2 disponíveis",
    state: "ok"
  }, {
    label: "Simulador ligado",
    detail: "iPhone 16 Pro",
    state: "ok"
  }, iosReady ? {
    label: "WebDriverAgent",
    detail: "Respondendo em http://localhost:8100",
    state: "ok"
  } : {
    label: "WebDriverAgent",
    detail: "Sem resposta em http://localhost:8100. O espelho funciona; toque e hierarquia precisam dele.",
    state: "warn"
  }];
  const android = checking ? null : iosReady ? [{
    label: "ADB instalado",
    detail: "adb não encontrado no PATH. Instale com brew install android-platform-tools.",
    state: "error"
  }, {
    label: "Dispositivo autorizado",
    state: "off"
  }, {
    label: "Emulador disponível",
    detail: "Nenhum AVD criado.",
    state: "warn"
  }] : [{
    label: "ADB instalado",
    detail: "adb",
    state: "ok"
  }, {
    label: "Dispositivo autorizado",
    detail: "Nenhum aparelho conectado.",
    state: "warn"
  }, {
    label: "Emulador disponível",
    detail: "2 AVD(s) parados.",
    state: "warn"
  }];
  const sims = [{
    value: "16p",
    label: "iPhone 16 Pro"
  }, {
    value: "15",
    label: "iPhone 15"
  }];
  const avds = [{
    value: "p7",
    label: "Pixel 7 API 34"
  }, {
    value: "p4",
    label: "Pixel 4a API 30"
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: "100%",
      overflow: "auto",
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      padding: "28px 20px 20px",
      background: "var(--bg-content)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    "aria-hidden": "true",
    style: {
      width: 92,
      height: 184,
      borderRadius: 22,
      border: "1.5px dashed var(--label-quaternary)",
      display: "grid",
      placeItems: "center",
      marginBottom: 18
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "smartphone",
    size: 28,
    strokeWidth: 1.3,
    color: "var(--label-tertiary)"
  })), /*#__PURE__*/React.createElement("h2", {
    style: {
      margin: 0,
      fontSize: 17,
      lineHeight: "22px",
      fontWeight: 600
    }
  }, "Conecte um dispositivo para come\xE7ar"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: "6px 0 20px",
      color: "var(--label-secondary)",
      textAlign: "center",
      maxWidth: 440,
      textWrap: "pretty"
    }
  }, "O Mo baile detecta simuladores, emuladores e aparelhos f\xEDsicos automaticamente. Se n\xE3o houver nenhum ligado, d\xE1 para abrir um daqui."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gridTemplateColumns: "repeat(2, 264px)",
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(DiagnosticCard, {
    platform: "ios",
    title: checking ? "iOS" : "iOS · WebDriverAgent",
    ready: iosReady,
    checks: ios,
    actionLabel: iosReady ? "Ir para o Simulador" : "Iniciar WebDriverAgent",
    actionDisabled: checking,
    onAction: onStartWDA
  }), /*#__PURE__*/React.createElement(PopUpButton, {
    variant: "plain",
    size: "small",
    options: sims,
    value: "16p",
    prefix: "Simulador:"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(DiagnosticCard, {
    platform: "android",
    title: checking ? "Android" : "Android · ADB",
    checks: android,
    actionLabel: "Abrir Emulador",
    actionDisabled: checking || iosReady,
    onAction: onOpenEmulator
  }), /*#__PURE__*/React.createElement(PopUpButton, {
    variant: "plain",
    size: "small",
    options: avds,
    value: "p7",
    prefix: "Emulador:"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      marginTop: 18,
      fontSize: 11,
      color: "var(--label-secondary)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-mono mb-tabular"
  }, checking ? "procurando dispositivos…" : "último scan " + lastScan), /*#__PURE__*/React.createElement(Button, {
    size: "small",
    variant: "plain",
    icon: "refresh-cw",
    onClick: onRescan
  }, "Verificar de Novo")));
}
Object.assign(window, {
  NoDeviceView
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/NoDevice.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/PageObjects.jsx
try { (() => {
// Workspace "Page Objects": dois editores (pages / locators) gerados a partir dos passos.
const PY_KW = new Set(["def", "self", "from", "import", "return", "class"]);
function highlight(line) {
  const out = [];
  let i = 0;
  const re = /("[^"]*"|'[^']*')|(\b\d+(?:\.\d+)?\b)|(#.*$)|([A-Za-z_][A-Za-z0-9_]*)/g;
  let m;
  while (m = re.exec(line)) {
    if (m.index > i) out.push(line.slice(i, m.index));
    const t = m[0];
    let c = null;
    if (m[1]) c = "var(--syntax-string)";else if (m[2]) c = "var(--syntax-number)";else if (m[3]) c = "var(--syntax-comment)";else if (PY_KW.has(t)) c = "var(--syntax-keyword)";else if (t === "AppiumBy") c = "var(--syntax-type)";else if (/^[a-z_]+$/.test(t) && line.slice(re.lastIndex).startsWith("(")) c = "var(--syntax-function)";
    out.push(c ? /*#__PURE__*/React.createElement("span", {
      key: m.index,
      style: {
        color: c
      }
    }, t) : t);
    i = re.lastIndex;
  }
  if (i < line.length) out.push(line.slice(i));
  return out;
}
function genPages(steps) {
  const L = [];
  steps.forEach(s => {
    const ref = "self.locators['onboarding_credito_objs']." + s.varName;
    const arg = s.action === "send_keys" ? "self, texto" : "self";
    L.push({
      t: "def " + s.method + "(" + arg + "):",
      step: s.id
    });
    L.push({
      t: "    self.wait_to_be_visible(" + ref + ", 15)",
      step: s.id
    });
    L.push({
      t: s.action === "send_keys" ? "    self.send_keys(" + ref + ", texto)" : "    self.click(" + ref + ", 2)",
      step: s.id
    });
    L.push({
      t: ""
    });
  });
  return L;
}
function genLocators(steps) {
  const L = [{
    t: "from appium.webdriver.common.appiumby import AppiumBy"
  }, {
    t: ""
  }];
  steps.forEach(s => {
    const by = s.strategy === "xpath" ? "AppiumBy.XPATH, '" + s.selector + "'" : s.strategy === "coords" ? null : "AppiumBy.ACCESSIBILITY_ID, \"" + s.selector + "\"";
    L.push({
      t: by ? s.varName + " = (" + by + ")" : s.varName + " = (1095, 210)  # coords",
      step: s.id
    });
  });
  return L;
}
function CodeEditor({
  title,
  path,
  color,
  lines,
  activeStep,
  onToast,
  onClear,
  disabled
}) {
  const {
    Icon,
    Tooltip
  } = window.MoBaileDesignSystem_ce6669;
  const act = (icon, label, fn, dis) => /*#__PURE__*/React.createElement(Tooltip, {
    key: label,
    label: label
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "mb-tb-item",
    "aria-label": label,
    disabled: dis,
    onClick: fn,
    style: {
      minWidth: 24,
      height: 22,
      padding: "0 5px"
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: icon,
    size: 14
  })));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: "flex",
      flexDirection: "column",
      background: "var(--bg-content)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      height: 30,
      flex: "none",
      display: "flex",
      alignItems: "center",
      gap: 6,
      padding: "0 6px 0 12px",
      borderBottom: "1px solid var(--separator)",
      fontSize: 12
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "folder",
    size: 13,
    color: color
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--label-secondary)"
    }
  }, path), /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--label-tertiary)"
    }
  }, "/"), /*#__PURE__*/React.createElement("span", {
    className: "mb-truncate mb-mono",
    style: {
      fontSize: 11.5,
      color,
      flex: 1
    },
    title: title
  }, title), /*#__PURE__*/React.createElement("span", {
    className: "mb-count",
    style: {
      fontSize: 11
    }
  }, lines.length, " linhas"), act("copy", "Copiar  ⇧⌘C", () => onToast("Código copiado"), disabled), act("save", "Salvar  ⌘S", () => onToast(title + " salvo"), disabled), act("trash-2", "Limpar", onClear, disabled)), /*#__PURE__*/React.createElement("div", {
    className: "mb-mono",
    style: {
      flex: 1,
      overflow: "auto",
      fontSize: 11.5,
      lineHeight: "19px",
      padding: "6px 0",
      userSelect: "text",
      cursor: "text",
      color: "var(--syntax-plain)"
    }
  }, lines.map((l, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      display: "flex",
      background: activeStep && l.step === activeStep ? "var(--selection-content)" : undefined,
      transition: "background-color var(--motion-crossfade)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-tabular",
    style: {
      width: 34,
      flex: "none",
      textAlign: "right",
      paddingRight: 10,
      color: "var(--syntax-gutter)",
      userSelect: "none"
    }
  }, i + 1), /*#__PURE__*/React.createElement("span", {
    style: {
      whiteSpace: "pre",
      paddingRight: 12
    }
  }, highlight(l.t))))));
}
function PageObjectsView({
  steps,
  strategy,
  setStrategy,
  split,
  setSplit,
  activeStep,
  onStructure,
  onToast,
  onClearSteps,
  onRecordMode,
  connected
}) {
  const {
    AccessoryBar,
    SegmentedControl,
    Button,
    ToolbarButton,
    EmptyState,
    StatusIndicator,
    Tooltip
  } = window.MoBaileDesignSystem_ce6669;
  const [tab, setTab] = React.useState("pages");
  const pages = genPages(steps),
    locs = genLocators(steps);
  const last = steps[steps.length - 1];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      height: "100%",
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement(AccessoryBar, null, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 12,
      color: "var(--label-secondary)"
    }
  }, "Seletor:"), /*#__PURE__*/React.createElement(SegmentedControl, {
    size: "small",
    ariaLabel: "Estrat\xE9gia de seletor",
    value: strategy,
    onChange: setStrategy,
    items: [{
      value: "auto",
      label: "Auto",
      tooltip: "O motor escolhe o localizador único mais robusto"
    }, {
      value: "id",
      label: "ID"
    }, {
      value: "xpath",
      label: "XPath"
    }, {
      value: "coords",
      label: "Coords"
    }]
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), !split && /*#__PURE__*/React.createElement(SegmentedControl, {
    size: "small",
    ariaLabel: "Arquivo",
    value: tab,
    onChange: setTab,
    items: [{
      value: "pages",
      label: "pages"
    }, {
      value: "locators",
      label: "locators"
    }]
  }), /*#__PURE__*/React.createElement(Tooltip, {
    label: "Estrutura do fluxo\u2026"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "list-ordered",
    disabled: !steps.length,
    onClick: onStructure
  }, "Estrutura\u2026")), /*#__PURE__*/React.createElement(Tooltip, {
    label: split ? "Mostrar um arquivo por vez" : "Mostrar pages e locators lado a lado"
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "mb-tb-item" + (split ? " is-on" : ""),
    "aria-pressed": split,
    "aria-label": "Lado a lado",
    onClick: () => setSplit(!split),
    style: {
      height: 22,
      minWidth: 26,
      padding: "0 5px"
    }
  }, /*#__PURE__*/React.createElement(window.MoBaileDesignSystem_ce6669.Icon, {
    name: "columns-2",
    size: 15
  })))), steps.length === 0 ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "grid",
      placeItems: "center",
      background: "var(--bg-content)"
    }
  }, /*#__PURE__*/React.createElement(EmptyState, {
    icon: "file-code",
    title: "Nenhum passo gravado",
    text: "Com \u201CGravar passo\u201D ativo, clique em um elemento no espelho. Cada toque vira um locator e um m\xE9todo do Page Object.",
    actionLabel: connected ? "Gravar Passo" : undefined,
    onAction: onRecordMode
  })) : /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "flex",
      minHeight: 0
    }
  }, (split || tab === "pages") && /*#__PURE__*/React.createElement(CodeEditor, {
    title: "onboarding_credito_objs.py",
    path: "pages",
    color: "var(--syntax-function)",
    lines: pages,
    activeStep: activeStep,
    onToast: onToast,
    onClear: onClearSteps
  }), split && /*#__PURE__*/React.createElement("div", {
    className: "mb-splitter"
  }), (split || tab === "locators") && /*#__PURE__*/React.createElement(CodeEditor, {
    title: "onboarding_credito_objs.py",
    path: "locators",
    color: "var(--accent-text)",
    lines: locs,
    activeStep: activeStep,
    onToast: onToast,
    onClear: onClearSteps
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 26,
      flex: "none",
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: "0 12px",
      borderTop: "1px solid var(--separator)",
      fontSize: 11,
      color: "var(--label-secondary)",
      background: "var(--bg-content)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-mono mb-truncate",
    style: {
      flex: 1
    }
  }, last ? "passo " + steps.length + " · " + last.action + " · " + last.strategy : "nenhum passo"), /*#__PURE__*/React.createElement(StatusIndicator, {
    status: "ok",
    label: "C\xF3digo sincronizado",
    mono: false
  })));
}
Object.assign(window, {
  PageObjectsView,
  genPages,
  genLocators,
  highlight
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/PageObjects.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/Settings.jsx
try { (() => {
function Row({
  label,
  children,
  top
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: "right",
      alignSelf: top ? "start" : "center",
      paddingTop: top ? 3 : 0
    }
  }, label), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "flex-start",
      gap: 6
    }
  }, children));
}
// Janela de Ajustes (⌘,): abas por ícone na toolbar; mudanças valem na hora, sem Salvar/Cancelar.
function SettingsWindow({
  open,
  onClose,
  prefs,
  setPref,
  active,
  onFocus
}) {
  const {
    Window,
    TrafficLights,
    Icon,
    PopUpButton,
    SegmentedControl,
    Checkbox,
    TextField
  } = window.MoBaileDesignSystem_ce6669;
  const [tab, setTab] = React.useState("geral");
  const [pos, setPos] = React.useState({
    x: 380,
    y: 120
  });
  const [portErr, setPortErr] = React.useState(false);
  if (!open) return null;
  const drag = e => {
    if (e.target.closest("button,[role=button]")) return;
    onFocus();
    let lx = e.clientX,
      ly = e.clientY;
    const mv = ev => {
      setPos(p => ({
        x: p.x + ev.clientX - lx,
        y: Math.max(0, p.y + ev.clientY - ly)
      }));
      lx = ev.clientX;
      ly = ev.clientY;
    };
    const up = () => {
      window.removeEventListener("pointermove", mv);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", mv);
    window.addEventListener("pointerup", up);
  };
  const tabs = [["geral", "Geral", "settings"], ["conexoes", "Conexões", "cable"]];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: pos.x,
      top: pos.y,
      zIndex: active ? 60 : 40
    },
    onMouseDown: onFocus,
    onKeyDown: e => e.key === "Escape" && onClose()
  }, /*#__PURE__*/React.createElement(Window, {
    active: active,
    width: 520,
    height: "auto",
    style: {
      minWidth: 0,
      minHeight: 0
    },
    ariaLabel: "Ajustes"
  }, /*#__PURE__*/React.createElement("div", {
    onPointerDown: drag,
    style: {
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      paddingBottom: 6,
      borderBottom: "1px solid var(--separator)",
      background: "var(--bg-window)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      alignSelf: "stretch",
      display: "flex",
      alignItems: "center",
      height: 28
    }
  }, /*#__PURE__*/React.createElement(TrafficLights, {
    onClose: onClose
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      textAlign: "center",
      fontWeight: 700,
      marginRight: 66
    }
  }, tabs.find(t => t[0] === tab)[1])), /*#__PURE__*/React.createElement("div", {
    role: "tablist",
    style: {
      display: "flex",
      gap: 2
    }
  }, tabs.map(([id, l, ic]) => /*#__PURE__*/React.createElement("button", {
    key: id,
    type: "button",
    role: "tab",
    "aria-selected": tab === id,
    onClick: () => setTab(id),
    className: "mb-tb-item",
    style: {
      flexDirection: "column",
      height: 46,
      width: 72,
      gap: 2,
      borderRadius: 8,
      background: tab === id ? "var(--fill-secondary)" : undefined,
      color: tab === id ? "var(--accent-text)" : "var(--label-secondary)"
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: ic,
    size: 20
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 11
    }
  }, l))))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 20,
      display: "grid",
      gridTemplateColumns: "1fr 1.25fr",
      gap: "10px 6px",
      alignItems: "center",
      background: "var(--bg-window)"
    }
  }, tab === "geral" ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Row, {
    label: "Apar\xEAncia:"
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      value: "system",
      label: "Sistema"
    }, {
      value: "light",
      label: "Claro"
    }, {
      value: "dark",
      label: "Escuro"
    }],
    value: prefs.appearance,
    onChange: v => setPref("appearance", v)
  })), /*#__PURE__*/React.createElement(Row, {
    label: "Tamanho dos itens da barra lateral:"
  }, /*#__PURE__*/React.createElement(PopUpButton, {
    minWidth: 160,
    options: [{
      value: "small",
      label: "Pequeno"
    }, {
      value: "medium",
      label: "Médio"
    }, {
      value: "large",
      label: "Grande"
    }],
    value: prefs.sidebarSize,
    onChange: v => setPref("sidebarSize", v)
  })), /*#__PURE__*/React.createElement(Row, {
    label: "Seletor padr\xE3o:"
  }, /*#__PURE__*/React.createElement(PopUpButton, {
    minWidth: 160,
    options: [{
      value: "auto",
      label: "Auto"
    }, {
      value: "id",
      label: "ID"
    }, {
      value: "xpath",
      label: "XPath"
    }, {
      value: "coords",
      label: "Coords"
    }],
    value: prefs.strategy,
    onChange: v => setPref("strategy", v)
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      gridColumn: "1 / -1",
      height: 1,
      background: "var(--separator)",
      margin: "6px 0"
    }
  }), /*#__PURE__*/React.createElement(Row, {
    label: "Ao conectar:",
    top: true
  }, /*#__PURE__*/React.createElement(Checkbox, {
    checked: prefs.autoStream,
    onChange: v => setPref("autoStream", v),
    label: "Iniciar o espelho automaticamente",
    help: "O streaming come\xE7a assim que um aparelho \xE9 detectado."
  }))) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Row, {
    label: "WebDriverAgent:"
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    width: 200,
    value: prefs.wda,
    onChange: v => setPref("wda", v)
  })), /*#__PURE__*/React.createElement(Row, {
    label: "Host do proxy:",
    top: true
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    width: 200,
    value: prefs.proxyHost,
    onChange: v => setPref("proxyHost", v)
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 11,
      color: "var(--label-secondary)",
      maxWidth: 230
    }
  }, "Mantenha 127.0.0.1. Escutar em 0.0.0.0 transforma a m\xE1quina em proxy aberto para a rede.")), /*#__PURE__*/React.createElement(Row, {
    label: "Porta do proxy:",
    top: true
  }, /*#__PURE__*/React.createElement(TextField, {
    mono: true,
    width: 80,
    value: prefs.proxyPort,
    invalid: portErr,
    onChange: v => {
      setPref("proxyPort", v);
      setPortErr(!/^\d{2,5}$/.test(v));
    }
  }), portErr && /*#__PURE__*/React.createElement("span", {
    role: "alert",
    style: {
      fontSize: 11,
      color: "var(--destructive)"
    }
  }, "Use um n\xFAmero de porta, como 8082."))))));
}
function SplashWindow({
  show
}) {
  if (!show) return null;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: "50%",
      top: "50%",
      transform: "translate(-50%,-50%)",
      zIndex: 90,
      width: 640,
      height: 380,
      borderRadius: 16,
      overflow: "hidden",
      boxShadow: "var(--shadow-window-active)",
      background: "url(../../assets/splash_bg.png) center/cover",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 20,
      animation: "mb-fade 240ms linear both"
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/mascot.png",
    alt: "",
    style: {
      height: 260
    }
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 48,
      fontWeight: 700,
      letterSpacing: -1.4,
      color: "#141543",
      fontFamily: "var(--font-display)"
    }
  }, "Mo baile"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      fontWeight: 600,
      letterSpacing: ".08em",
      color: "#141543",
      opacity: .75
    }
  }, "ELEMENT RECORDER"), /*#__PURE__*/React.createElement("div", {
    className: "mb-progress",
    style: {
      width: 190,
      marginTop: 16,
      background: "rgba(255,255,255,.55)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "mb-progress__bar",
    style: {
      width: "100%",
      transition: "width 1.4s linear"
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11,
      color: "#141543",
      marginTop: 6,
      opacity: .7
    }
  }, "Iniciando o motor\u2026")));
}
Object.assign(window, {
  SettingsWindow,
  SplashWindow
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/Settings.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/Sheets.jsx
try { (() => {
// Sheets: Estrutura do Fluxo e Executar Fluxo.
function StructureSheet({
  open,
  steps,
  onClose,
  onRun
}) {
  const {
    Sheet,
    Button,
    DataTable
  } = window.MoBaileDesignSystem_ce6669;
  const [sel, setSel] = React.useState([]);
  const rows = steps.map((s, i) => ({
    ...s,
    n: i + 1
  }));
  return /*#__PURE__*/React.createElement(Sheet, {
    open: open,
    onClose: onClose,
    onConfirm: onClose,
    width: 680,
    ariaLabel: "Estrutura do fluxo",
    footer: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("button", {
      type: "button",
      className: "mb-help",
      "aria-label": "Ajuda"
    }, "?"), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1
      }
    }), /*#__PURE__*/React.createElement(Button, {
      style: {
        minWidth: 96
      },
      onClick: () => {
        onClose();
        setTimeout(onRun, 350);
      }
    }, "Rodar\u2026"), /*#__PURE__*/React.createElement(Button, {
      variant: "default",
      style: {
        minWidth: 96
      },
      onClick: onClose
    }, "Concluir"))
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      margin: "0 0 4px",
      fontSize: 13,
      fontWeight: 700
    }
  }, "Estrutura do fluxo"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: "0 0 12px",
      color: "var(--label-secondary)"
    }
  }, "onboarding_credito \xB7 ", steps.length, " passos. Arraste na barra lateral para reordenar."), /*#__PURE__*/React.createElement(DataTable, {
    style: {
      height: 230,
      borderRadius: 8,
      boxShadow: "inset 0 0 0 .5px var(--separator)"
    },
    selected: sel,
    onSelectionChange: setSel,
    rowKey: "id",
    rows: rows,
    columns: [{
      key: "n",
      label: "#",
      width: 34,
      align: "right"
    }, {
      key: "action",
      label: "Ação",
      width: 90,
      mono: true
    }, {
      key: "element",
      label: "Elemento",
      width: "1fr"
    }, {
      key: "strategy",
      label: "Estratégia",
      width: 80
    }, {
      key: "selector",
      label: "Coordenadas/Seletor",
      width: "1.3fr",
      mono: true
    }]
  }));
}
function FlowRunnerSheet({
  open,
  steps,
  outcome,
  onClose,
  onToast
}) {
  const {
    Sheet,
    Button,
    ProgressIndicator,
    Icon,
    StatusIndicator,
    Tooltip
  } = window.MoBaileDesignSystem_ce6669;
  const [phase, setPhase] = React.useState("idle");
  const [cur, setCur] = React.useState(0);
  const [lines, setLines] = React.useState([]);
  const timer = React.useRef(null);
  const term = React.useRef(null);
  const failAt = Math.min(4, steps.length - 1);
  React.useEffect(() => {
    clearInterval(timer.current);
    if (!open) return;
    const L = window.MB_DATA.log;
    let li = 0,
      step = 0;
    setPhase("running");
    setCur(0);
    setLines([]);
    timer.current = setInterval(() => {
      if (li >= L.length) {
        clearInterval(timer.current);
        setPhase("passed");
        setCur(steps.length);
        return;
      }
      const l = L[li++];
      if (outcome === "fail" && l[1] === "PASS" && step === failAt) {
        setLines(x => [...x, window.MB_DATA.failLine]);
        clearInterval(timer.current);
        setPhase("failed");
        return;
      }
      setLines(x => [...x, l]);
      if (l[1] === "PASS") {
        step++;
        setCur(step);
      }
    }, 420);
    return () => clearInterval(timer.current);
  }, [open, outcome]);
  React.useEffect(() => {
    if (term.current) term.current.scrollTop = term.current.scrollHeight;
  }, [lines]);
  const stop = () => {
    clearInterval(timer.current);
    setPhase("stopped");
  };
  const passed = phase === "failed" ? failAt : Math.min(cur, steps.length);
  const badge = {
    running: ["Em execução", "busy"],
    passed: ["Concluído", "ok"],
    failed: ["Falha", "error"],
    stopped: ["Interrompido", "warn"],
    idle: ["", "off"]
  }[phase];
  const tagColor = {
    INFO: "var(--info)",
    RUN: "var(--info)",
    PASS: "var(--success)",
    HTTP: "var(--warning)",
    FA: "var(--warning)",
    FAIL: "var(--destructive)"
  };
  const done = phase !== "running";
  return /*#__PURE__*/React.createElement(Sheet, {
    open: open,
    onClose: done ? onClose : stop,
    onConfirm: done ? onClose : undefined,
    width: 820,
    ariaLabel: "Executar fluxo",
    footer: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("button", {
      type: "button",
      className: "mb-help",
      "aria-label": "Ajuda"
    }, "?"), /*#__PURE__*/React.createElement("span", {
      className: "mb-tabular",
      style: {
        flex: 1,
        fontSize: 12,
        color: "var(--label-secondary)"
      }
    }, passed, " aprovados \xB7 ", phase === "failed" ? 1 : 0, " falhas \xB7 tempo ", (lines.length * 0.42).toFixed(1).replace(".", ","), " s"), /*#__PURE__*/React.createElement(Button, {
      style: {
        minWidth: 96
      },
      icon: "terminal",
      onClick: () => onToast("flow_runner.log aberto")
    }, "Abrir Log"), !done ? /*#__PURE__*/React.createElement(Tooltip, {
      label: "Interromper  \u2318."
    }, /*#__PURE__*/React.createElement(Button, {
      variant: "destructive",
      style: {
        minWidth: 96
      },
      onClick: stop
    }, "Interromper")) : /*#__PURE__*/React.createElement(Button, {
      variant: "default",
      style: {
        minWidth: 96
      },
      onClick: onClose
    }, "Concluir"))
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      marginBottom: 10
    }
  }, /*#__PURE__*/React.createElement("h2", {
    style: {
      margin: 0,
      fontSize: 13,
      fontWeight: 700
    }
  }, "Executar fluxo \xB7 onboarding_credito"), /*#__PURE__*/React.createElement(StatusIndicator, {
    status: badge[1],
    label: badge[0],
    mono: false
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(StatusIndicator, {
    status: "ok",
    label: "WDA 8100"
  }), /*#__PURE__*/React.createElement(StatusIndicator, {
    status: "ok",
    label: "Proxy 8082"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      marginBottom: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }, /*#__PURE__*/React.createElement(ProgressIndicator, {
    value: passed / steps.length,
    tone: phase === "failed" ? "error" : phase === "passed" ? "success" : undefined
  })), /*#__PURE__*/React.createElement("span", {
    className: "mb-tabular",
    style: {
      fontSize: 11,
      color: "var(--label-secondary)"
    }
  }, "passo ", Math.min(cur + (done ? 0 : 1), steps.length), " de ", steps.length)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "grid",
      gridTemplateColumns: "280px 1fr",
      gap: 12,
      height: 300
    }
  }, /*#__PURE__*/React.createElement("ol", {
    style: {
      margin: 0,
      padding: 4,
      listStyle: "none",
      overflow: "auto",
      borderRadius: 10,
      background: "var(--bg-content)",
      boxShadow: "inset 0 0 0 .5px var(--separator)"
    }
  }, steps.map((s, i) => {
    const st = i < passed ? "ok" : phase === "failed" && i === failAt ? "error" : phase === "running" && i === cur ? "run" : "todo";
    return /*#__PURE__*/React.createElement("li", {
      key: s.id,
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        height: 28,
        padding: "0 8px",
        borderRadius: 6,
        background: st === "run" ? "var(--selection-content)" : undefined,
        color: st === "todo" ? "var(--label-secondary)" : undefined
      }
    }, st === "ok" ? /*#__PURE__*/React.createElement(Icon, {
      name: "circle-check",
      size: 14,
      color: "var(--success)"
    }) : st === "error" ? /*#__PURE__*/React.createElement(Icon, {
      name: "circle-x",
      size: 14,
      color: "var(--destructive)"
    }) : st === "run" ? /*#__PURE__*/React.createElement(ProgressIndicator, {
      kind: "spinner",
      size: 14
    }) : /*#__PURE__*/React.createElement(Icon, {
      name: "circle-dot",
      size: 14,
      color: "var(--label-tertiary)"
    }), /*#__PURE__*/React.createElement("span", {
      className: "mb-truncate",
      style: {
        flex: 1
      }
    }, s.action, " ", s.element), s.value && /*#__PURE__*/React.createElement("span", {
      className: "mb-mono",
      style: {
        fontSize: 11,
        color: "var(--label-secondary)"
      }
    }, s.value));
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      borderRadius: 10,
      background: "var(--bg-terminal)",
      color: "#CDD6F4",
      display: "flex",
      flexDirection: "column",
      overflow: "hidden"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "mb-mono",
    style: {
      display: "flex",
      justifyContent: "space-between",
      padding: "8px 12px",
      fontSize: 10.5,
      color: "#7F849C",
      borderBottom: "1px solid rgba(255,255,255,.08)"
    }
  }, /*#__PURE__*/React.createElement("span", null, ".flow_runner.py"), /*#__PURE__*/React.createElement("span", null, "stdout \xB7 streaming")), /*#__PURE__*/React.createElement("div", {
    ref: term,
    className: "mb-mono",
    style: {
      flex: 1,
      overflow: "auto",
      padding: "8px 12px",
      fontSize: 11,
      lineHeight: "17px",
      userSelect: "text",
      cursor: "text"
    }
  }, lines.map((l, i) => /*#__PURE__*/React.createElement("div", {
    key: i
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: "#585B70"
    }
  }, l[0]), " ", /*#__PURE__*/React.createElement("span", {
    style: {
      color: {
        INFO: "#89B4FA",
        RUN: "#89B4FA",
        PASS: "#A6E3A1",
        HTTP: "#F9E2AF",
        FA: "#F9E2AF",
        FAIL: "#F38BA8"
      }[l[1]]
    }
  }, "[", l[1], "]"), " ", l[2]))))));
}
Object.assign(window, {
  StructureSheet,
  FlowRunnerSheet
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/Sheets.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/Traffic.jsx
try { (() => {
// Workspaces "Rede HTTP" e "Analytics": barra acessória, tabela e painel de detalhes.
const methodColor = m => ({
  GET: "var(--http-get)",
  POST: "var(--http-post)",
  PUT: "var(--http-post)",
  DELETE: "var(--http-delete)",
  CONNECT: "var(--http-connect)"
})[m];
const statusColor = s => s == null ? "var(--label-tertiary)" : s >= 400 ? "var(--status-4xx)" : s >= 300 ? "var(--status-3xx)" : "var(--status-2xx)";
const fmtTime = t => t == null ? "—" : t >= 1000 ? (t / 1000).toFixed(1).replace(".", ",") + " s" : t + " ms";
function sortRows(rows, sort) {
  if (!sort) return rows;
  return [...rows].sort((a, b) => {
    const x = a[sort.key],
      y = b[sort.key];
    const r = x == null ? -1 : y == null ? 1 : x > y ? 1 : x < y ? -1 : 0;
    return sort.dir === "asc" ? r : -r;
  });
}
function DetailHeader({
  title,
  extra,
  tab,
  setTab,
  tabs,
  onCopy
}) {
  const {
    SegmentedControl,
    Button
  } = window.MoBaileDesignSystem_ce6669;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: 34,
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: "0 10px 0 12px",
      borderBottom: "1px solid var(--separator)",
      flex: "none"
    }
  }, /*#__PURE__*/React.createElement("b", {
    style: {
      fontWeight: 600,
      fontSize: 12,
      whiteSpace: "nowrap"
    }
  }, title), /*#__PURE__*/React.createElement("span", {
    className: "mb-truncate",
    style: {
      display: "inline-flex",
      gap: 6
    }
  }, extra), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), tabs && /*#__PURE__*/React.createElement(SegmentedControl, {
    size: "small",
    items: tabs,
    value: tab,
    onChange: setTab
  }), /*#__PURE__*/React.createElement(Button, {
    size: "mini",
    icon: "copy",
    onClick: onCopy,
    "aria-label": "Copiar"
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-narrow"
  }, "Copiar")));
}
function KV({
  rows
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-mono",
    style: {
      display: "grid",
      gridTemplateColumns: "minmax(90px,auto) 1fr",
      fontSize: 11,
      lineHeight: "15px",
      userSelect: "text",
      cursor: "text"
    }
  }, rows.map(([k, v], i) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: k
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      padding: "4px 12px",
      color: "var(--accent-text)",
      borderBottom: "1px solid var(--separator)"
    }
  }, k), /*#__PURE__*/React.createElement("span", {
    className: "mb-truncate",
    title: v,
    style: {
      padding: "4px 12px 4px 0",
      borderBottom: "1px solid var(--separator)"
    }
  }, v))));
}
function Body({
  text
}) {
  return /*#__PURE__*/React.createElement("pre", {
    className: "mb-mono",
    style: {
      margin: 10,
      padding: 10,
      borderRadius: 8,
      background: "var(--bg-content-alt)",
      fontSize: 11,
      lineHeight: "16px",
      whiteSpace: "pre-wrap",
      userSelect: "text",
      cursor: "text"
    }
  }, text);
}
function NetworkView({
  rows,
  proxyOn,
  setProxyOn,
  debugOn,
  setDebugOn,
  filter,
  selected,
  setSelected,
  newKeys,
  onClear,
  onToast,
  error,
  setError,
  loading
}) {
  const NS = window.MoBaileDesignSystem_ce6669;
  const {
    AccessoryBar,
    Button,
    StatusIndicator,
    DataTable,
    EmptyState,
    InlineError,
    Icon,
    Tooltip,
    Menu,
    Splitter
  } = NS;
  const [sort, setSort] = React.useState(null);
  const [reqTab, setReqTab] = React.useState("h"),
    [resTab, setResTab] = React.useState("b");
  const [menu, setMenu] = React.useState(null);
  const [split, setSplit] = React.useState(0.5);
  const box = React.useRef(null);
  const f = filter.trim().toLowerCase();
  const shown = sortRows(rows.filter(r => !f || (r.host + r.path + r.status + r.method).toLowerCase().includes(f)), sort);
  const sel = rows.find(r => r.id === selected[selected.length - 1]);
  const cols = [{
    key: "method",
    label: "Método",
    width: 78,
    sortable: true,
    mono: true,
    color: r => methodColor(r.method)
  }, {
    key: "status",
    label: "Status",
    width: 58,
    sortable: true,
    mono: true,
    align: "right",
    render: r => r.status || "—",
    color: r => statusColor(r.status)
  }, {
    key: "host",
    label: "Host",
    width: "1fr",
    minWidth: 120,
    sortable: true,
    mono: true
  }, {
    key: "path",
    label: "Caminho",
    width: "1.4fr",
    minWidth: 120,
    sortable: true,
    mono: true
  }, {
    key: "size",
    label: "Tamanho",
    width: 68,
    sortable: true,
    align: "right",
    render: r => r.size + " B"
  }, {
    key: "time",
    label: "Tempo",
    width: 64,
    sortable: true,
    align: "right",
    render: r => fmtTime(r.time)
  }];
  return /*#__PURE__*/React.createElement("div", {
    ref: box,
    className: "mb-cq",
    style: {
      display: "flex",
      flexDirection: "column",
      height: "100%",
      minWidth: 0,
      background: "var(--bg-content)"
    }
  }, /*#__PURE__*/React.createElement(AccessoryBar, null, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-xnarrow"
  }, /*#__PURE__*/React.createElement(StatusIndicator, {
    status: proxyOn ? "ok" : "off",
    label: proxyOn ? "Proxy 8082 ativo" : "Proxy 8082 inativo"
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Tooltip, {
    label: debugOn ? "Desfaz a configuração de proxy no iPhone" : "Configura o iPhone físico para usar o proxy"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "smartphone",
    disabled: !proxyOn,
    onClick: () => setDebugOn(!debugOn)
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-narrow"
  }, debugOn ? "Parar iPhone Debug" : "iPhone em Debug"))), /*#__PURE__*/React.createElement(Tooltip, {
    label: proxyOn ? "Encerra o proxy e desfaz a rota reversa no aparelho" : "Inicia o proxy MITM e configura a rota reversa no aparelho"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "network",
    onClick: () => {
      setError(null);
      setProxyOn(!proxyOn);
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-narrow"
  }, proxyOn ? "Parar Proxy" : "Configurar Proxy"))), /*#__PURE__*/React.createElement(Tooltip, {
    label: "Exporta o tr\xE1fego capturado no formato HAR 1.2"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "share",
    disabled: !rows.length,
    onClick: () => onToast("network_traffic.har exportado")
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-narrow"
  }, "Exportar HAR\u2026"))), /*#__PURE__*/React.createElement(Button, {
    size: "small",
    variant: "plain-destructive",
    disabled: !rows.length,
    onClick: onClear
  }, "Limpar Tr\xE1fego")), error && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "8px 12px 0"
    }
  }, /*#__PURE__*/React.createElement(InlineError, {
    title: "N\xE3o foi poss\xEDvel iniciar o proxy.",
    text: "A porta 8082 j\xE1 est\xE1 em uso por outro app. Feche-o ou troque a porta em Ajustes \u203A Conex\xF5es.",
    actionLabel: "Tentar de Novo",
    onAction: () => {
      setError(null);
      setProxyOn(true);
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: split,
      minHeight: 100,
      display: "flex",
      flexDirection: "column"
    }
  }, loading ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "grid",
      placeItems: "center"
    }
  }, /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    loading: true,
    text: "Iniciando o proxy\u2026"
  })) : !proxyOn && !rows.length ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "grid",
      placeItems: "center"
    }
  }, /*#__PURE__*/React.createElement(EmptyState, {
    icon: "network",
    title: "O proxy est\xE1 desligado",
    text: "Inicie o proxy para registrar o tr\xE1fego HTTP do aparelho. As credenciais s\xE3o redigidas.",
    actionLabel: "Configurar Proxy",
    onAction: () => setProxyOn(true)
  })) : /*#__PURE__*/React.createElement(DataTable, {
    style: {
      flex: 1
    },
    columns: cols,
    rows: shown,
    selected: selected,
    onSelectionChange: setSelected,
    sort: sort,
    onSortChange: setSort,
    newKeys: newKeys,
    onRowContextMenu: (r, e) => {
      e.preventDefault();
      setMenu({
        x: e.clientX,
        y: e.clientY,
        r
      });
    },
    empty: /*#__PURE__*/React.createElement(EmptyState, {
      compact: true,
      icon: f ? "search" : "radio-tower",
      text: f ? "Nenhuma requisição corresponde ao filtro." : "Aguardando tráfego do aparelho…"
    })
  })), /*#__PURE__*/React.createElement(Splitter, {
    orientation: "horizontal",
    onDrag: d => {
      const h = box.current.offsetHeight;
      setSplit(s => Math.max(.25, Math.min(.8, s + d / h)));
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1 - split,
      minHeight: 120,
      display: "flex",
      minWidth: 0
    }
  }, !sel ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "grid",
      placeItems: "center"
    }
  }, /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    icon: "info",
    text: "Selecione uma requisi\xE7\xE3o para ver os detalhes."
  })) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: "flex",
      flexDirection: "column"
    }
  }, /*#__PURE__*/React.createElement(DetailHeader, {
    title: "Request",
    extra: /*#__PURE__*/React.createElement("span", {
      className: "mb-mono",
      style: {
        fontSize: 10.5,
        color: methodColor(sel.method)
      }
    }, sel.method),
    tabs: [{
      value: "h",
      label: "Headers",
      count: sel.tunnel ? 0 : 5
    }, {
      value: "b",
      label: "Body"
    }],
    tab: reqTab,
    setTab: setReqTab,
    onCopy: () => onToast("Request copiada")
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflow: "auto"
    }
  }, sel.tunnel ? /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    icon: "info",
    text: "Sem headers na requisi\xE7\xE3o."
  }) : reqTab === "h" ? /*#__PURE__*/React.createElement(KV, {
    rows: window.MB_DATA.reqHeaders
  }) : /*#__PURE__*/React.createElement(Body, {
    text: "{\n  \"valor\": 5000,\n  \"parcelas\": 12\n}"
  }))), /*#__PURE__*/React.createElement("div", {
    className: "mb-splitter"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: "flex",
      flexDirection: "column"
    }
  }, /*#__PURE__*/React.createElement(DetailHeader, {
    title: "Response",
    extra: /*#__PURE__*/React.createElement("span", {
      className: "mb-mono mb-tabular",
      style: {
        fontSize: 10.5,
        color: statusColor(sel.status)
      }
    }, sel.status || "—", " \xB7 ", fmtTime(sel.time)),
    tabs: [{
      value: "h",
      label: "Headers"
    }, {
      value: "b",
      label: "Body"
    }],
    tab: resTab,
    setTab: setResTab,
    onCopy: () => onToast("Response copiada")
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflow: "auto"
    }
  }, sel.tunnel ? /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    icon: "shield-check",
    title: "T\xFAnel HTTPS estabelecido",
    text: "Conex\xE3o criptografada de ponta a ponta. 200 Connection Established \xB7 58 ms."
  }) : resTab === "h" ? /*#__PURE__*/React.createElement(KV, {
    rows: [["Content-Type", "application/json"], ["Content-Length", String(sel.size)], ["Date", "Thu, 08 Oct 2026 13:02:14 GMT"]]
  }) : sel.resBody ? /*#__PURE__*/React.createElement(Body, {
    text: sel.resBody
  }) : /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    icon: "info",
    text: "Resposta sem corpo."
  }))))), menu && /*#__PURE__*/React.createElement(Menu, {
    x: menu.x,
    y: menu.y,
    onClose: () => setMenu(null),
    items: [{
      label: "Copiar URL",
      shortcut: "⌘C",
      onSelect: () => onToast("URL copiada")
    }, {
      label: "Copiar como cURL",
      onSelect: () => onToast("cURL copiado")
    }, {
      label: "Gerar Asserção de Contrato",
      onSelect: () => onToast("Asserção de contrato inserida no código")
    }, {
      separator: true
    }, {
      label: "Exportar HAR…",
      onSelect: () => onToast("network_traffic.har exportado")
    }]
  }));
}
function AnalyticsView({
  rows,
  listening,
  setListening,
  source,
  setSource,
  filter,
  selected,
  setSelected,
  newKeys,
  onClear,
  onToast
}) {
  const {
    AccessoryBar,
    Button,
    StatusIndicator,
    DataTable,
    EmptyState,
    PopUpButton,
    Tooltip,
    SegmentedControl
  } = window.MoBaileDesignSystem_ce6669;
  const [tab, setTab] = React.useState("p");
  const [sort, setSort] = React.useState(null);
  const f = filter.trim().toLowerCase();
  const shown = sortRows(rows.filter(r => !f || (r.name + JSON.stringify(r.params)).toLowerCase().includes(f)), sort);
  const sel = rows.find(r => r.id === selected[selected.length - 1]);
  const cols = [{
    key: "time",
    label: "Hora",
    width: 100,
    sortable: true,
    mono: true,
    align: "right"
  }, {
    key: "name",
    label: "Evento",
    width: "1fr",
    sortable: true,
    mono: true,
    color: () => "var(--accent-text)"
  }, {
    key: "n",
    label: "Parâmetros",
    width: 84,
    align: "right",
    render: r => Object.keys(r.params).length
  }, {
    key: "o",
    label: "Origem",
    width: 100,
    render: () => "iOS (Firebase)"
  }];
  const raw = sel && "2026-10-08 " + sel.time + " BancoPraia[4821:91234] 11.3.0 - [FirebaseAnalytics][I-ACS023051] Logging event: origin, name, params: app, " + sel.name + ", {\n    " + Object.entries(sel.params).map(([k, v]) => k + ": " + v).join(", ") + "\n}";
  return /*#__PURE__*/React.createElement("div", {
    className: "mb-cq",
    style: {
      display: "flex",
      flexDirection: "column",
      height: "100%",
      minWidth: 0,
      background: "var(--bg-content)"
    }
  }, /*#__PURE__*/React.createElement(AccessoryBar, null, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-xnarrow"
  }, /*#__PURE__*/React.createElement(StatusIndicator, {
    status: listening ? "ok" : "off",
    label: listening ? "FA Listener ativo" : "FA Listener inativo"
  })), /*#__PURE__*/React.createElement(Tooltip, {
    label: listening ? "Para trocar a origem, pare a escuta" : "De onde ler o tagueamento"
  }, /*#__PURE__*/React.createElement(PopUpButton, {
    variant: "plain",
    size: "small",
    icon: "wand-sparkles",
    disabled: listening,
    value: source,
    onChange: setSource,
    options: [{
      value: "auto",
      label: "Automático"
    }, {
      value: "sim",
      label: "Simulador"
    }, "-", {
      value: "cabo",
      label: "Nenhum iPhone conectado por cabo",
      disabled: true
    }]
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: listening ? "square" : "radio-tower",
    onClick: () => setListening(!listening)
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-narrow"
  }, listening ? "Parar Escuta" : "Iniciar Escuta")), /*#__PURE__*/React.createElement(Tooltip, {
    label: "Copia a tabela em TSV para colar no Google Planilhas"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "copy",
    disabled: !rows.length,
    onClick: () => onToast(rows.length + " eventos copiados como TSV")
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-narrow"
  }, "Copiar TSV"))), /*#__PURE__*/React.createElement(Tooltip, {
    label: "Exporta os eventos em log_obtido.json"
  }, /*#__PURE__*/React.createElement(Button, {
    size: "small",
    icon: "share",
    disabled: !rows.length,
    onClick: () => onToast("log_obtido.json exportado")
  }, /*#__PURE__*/React.createElement("span", {
    className: "mb-hide-narrow"
  }, "Exportar JSON\u2026"))), /*#__PURE__*/React.createElement(Button, {
    size: "small",
    variant: "plain-destructive",
    disabled: !rows.length,
    onClick: onClear
  }, "Limpar")), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 100,
      display: "flex",
      flexDirection: "column"
    }
  }, !listening && !rows.length ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "grid",
      placeItems: "center"
    }
  }, /*#__PURE__*/React.createElement(EmptyState, {
    icon: "chart-line",
    title: "Nenhum evento capturado",
    text: "Inicie a escuta para ver os eventos de Firebase Analytics em tempo real.",
    actionLabel: "Iniciar Escuta",
    onAction: () => setListening(true)
  })) : /*#__PURE__*/React.createElement(DataTable, {
    style: {
      flex: 1
    },
    columns: cols,
    rows: shown,
    selected: selected,
    onSelectionChange: setSelected,
    sort: sort,
    onSortChange: setSort,
    newKeys: newKeys,
    empty: /*#__PURE__*/React.createElement(EmptyState, {
      compact: true,
      icon: f ? "search" : "radio-tower",
      text: f ? "Nenhum evento corresponde ao filtro." : "Aguardando eventos…"
    })
  })), /*#__PURE__*/React.createElement("div", {
    className: "mb-splitter mb-splitter--h"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 120,
      display: "flex",
      minWidth: 0
    }
  }, !sel ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "grid",
      placeItems: "center"
    }
  }, /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    icon: "info",
    text: "Selecione um evento para ver os detalhes."
  })) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: "flex",
      flexDirection: "column"
    }
  }, /*#__PURE__*/React.createElement(DetailHeader, {
    title: "Par\xE2metros",
    extra: /*#__PURE__*/React.createElement("span", {
      className: "mb-count"
    }, Object.keys(sel.params).length),
    onCopy: () => onToast("Parâmetros copiados")
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflow: "auto"
    }
  }, Object.keys(sel.params).length ? /*#__PURE__*/React.createElement(KV, {
    rows: Object.entries(sel.params)
  }) : /*#__PURE__*/React.createElement(EmptyState, {
    compact: true,
    text: "Evento sem par\xE2metros."
  }))), /*#__PURE__*/React.createElement("div", {
    className: "mb-splitter"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: "flex",
      flexDirection: "column"
    }
  }, /*#__PURE__*/React.createElement(DetailHeader, {
    title: "Log Bruto",
    extra: /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 11,
        color: "var(--label-secondary)"
      }
    }, "iOS (Firebase)"),
    onCopy: () => onToast("Log copiado")
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      overflow: "auto"
    }
  }, /*#__PURE__*/React.createElement(Body, {
    text: raw
  }))))));
}
Object.assign(window, {
  NetworkView,
  AnalyticsView
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/Traffic.jsx", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/data.js
try { (() => {
// Dados de exemplo do protótipo (conteúdo do catálogo de telas original).
window.MB_DATA = (() => {
  const nodes = [{
    id: "app",
    type: "W",
    label: "Banco Praia",
    depth: 0,
    attrs: {
      type: "XCUIElementTypeApplication",
      name: "Banco Praia",
      label: "Banco Praia",
      bounds: "[0,0][1179,2556]",
      enabled: "true"
    }
  }, {
    id: "win",
    type: "W",
    label: "XCUIElementTypeWindow",
    depth: 1,
    attrs: {
      type: "XCUIElementTypeWindow",
      name: "",
      label: "",
      bounds: "[0,0][1179,2556]",
      enabled: "true"
    }
  }, {
    id: "nav",
    type: "V",
    label: "Crédito pessoal",
    depth: 2,
    attrs: {
      type: "XCUIElementTypeNavigationBar",
      name: "Crédito pessoal",
      label: "Crédito pessoal",
      bounds: "[0,141][1179,317]",
      enabled: "true"
    }
  }, {
    id: "voltar",
    type: "B",
    label: "Voltar",
    depth: 3,
    box: [6, 9, 12, 5],
    var: "BOTAO_VOLTAR",
    attrs: {
      type: "XCUIElementTypeButton",
      name: "Voltar",
      label: "Voltar",
      bounds: "[24,170][156,290]",
      center: "[90,230]",
      enabled: "true"
    }
  }, {
    id: "titulo",
    type: "T",
    label: "Crédito pessoal",
    depth: 3,
    box: [30, 9, 40, 5],
    attrs: {
      type: "XCUIElementTypeStaticText",
      name: "Crédito pessoal",
      label: "Crédito pessoal",
      bounds: "[420,200][760,260]",
      enabled: "true"
    }
  }, {
    id: "conteudo",
    type: "V",
    label: "conteudo",
    depth: 2,
    attrs: {
      type: "XCUIElementTypeOther",
      name: "conteudo",
      label: "",
      bounds: "[0,317][1179,2556]",
      enabled: "true"
    }
  }, {
    id: "h1",
    type: "T",
    label: "Simule seu crédito em minutos",
    depth: 3,
    box: [8, 41, 60, 8],
    attrs: {
      type: "XCUIElementTypeStaticText",
      name: "Simule seu crédito em minutos",
      label: "Simule seu crédito em minutos",
      bounds: "[72,1020][860,1210]",
      enabled: "true"
    }
  }, {
    id: "sub",
    type: "T",
    label: "Sem compromisso. A taxa aparece antes de você contratar.",
    depth: 3,
    box: [8, 50, 84, 5],
    attrs: {
      type: "XCUIElementTypeStaticText",
      name: "",
      label: "Sem compromisso. A taxa aparece antes de você contratar.",
      bounds: "[72,1230][1107,1330]",
      enabled: "true"
    }
  }, {
    id: "cpf",
    type: "I",
    label: "CPF",
    depth: 3,
    box: [8, 58, 84, 6],
    var: "CAMPO_CPF",
    key: "campo_cpf",
    attrs: {
      type: "XCUIElementTypeTextField",
      name: "campo_cpf",
      label: "CPF",
      bounds: "[72,1480][1107,1630]",
      center: "[589,1555]",
      enabled: "true"
    }
  }, {
    id: "valor",
    type: "I",
    label: "Valor desejado",
    depth: 3,
    box: [8, 67.5, 84, 6],
    var: "CAMPO_VALOR",
    key: "campo_valor",
    attrs: {
      type: "XCUIElementTypeTextField",
      name: "campo_valor",
      label: "Valor desejado",
      bounds: "[72,1720][1107,1870]",
      center: "[589,1795]",
      enabled: "true"
    }
  }, {
    id: "continuar",
    type: "B",
    label: "Continuar",
    depth: 3,
    box: [8, 82, 84, 6],
    var: "BOTAO_CONTINUAR",
    key: "Continuar",
    hit: "44pt",
    attrs: {
      type: "XCUIElementTypeButton",
      name: "Continuar",
      label: "Continuar",
      bounds: "[72,2148][1107,2310]",
      center: "[589,2229]",
      enabled: "true"
    }
  }, {
    id: "agora",
    type: "B",
    label: "Agora não",
    depth: 3,
    box: [34, 89.5, 32, 4],
    var: "BOTAO_AGORA_NAO",
    key: "Agora não",
    attrs: {
      type: "XCUIElementTypeButton",
      name: "Agora não",
      label: "Agora não",
      bounds: "[420,2340][760,2420]",
      center: "[589,2380]",
      enabled: "true"
    }
  }];
  const steps = [{
    id: "s1",
    action: "click",
    element: "Simular crédito",
    varName: "BOTAO_SIMULAR_CREDITO",
    strategy: "id",
    selector: "Simular crédito",
    method: "click_botao_simular_credito"
  }, {
    id: "s2",
    action: "send_keys",
    element: "campo_cpf",
    varName: "CAMPO_CPF",
    strategy: "id",
    selector: "campo_cpf",
    value: "•••••••••••",
    method: "preencher_campo_cpf"
  }, {
    id: "s3",
    action: "send_keys",
    element: "campo_valor",
    varName: "CAMPO_VALOR",
    strategy: "id",
    selector: "campo_valor",
    value: "5000",
    method: "preencher_campo_valor"
  }, {
    id: "s4",
    action: "click",
    element: "Continuar",
    varName: "BOTAO_CONTINUAR",
    strategy: "id",
    selector: "Continuar",
    method: "click_botao_continuar"
  }, {
    id: "s5",
    action: "click",
    element: "Confirmar contratação",
    varName: "BOTAO_CONFIRMAR_CONTRATACAO",
    strategy: "xpath",
    selector: "//XCUIElementTypeButton[@name=\"Confirmar contratação\"]",
    method: "click_botao_confirmar_contratacao"
  }, {
    id: "s6",
    action: "click",
    element: "position",
    varName: "TOQUE_FECHAR",
    strategy: "coords",
    selector: "x: 1.095, y: 210",
    method: "click_toque_fechar"
  }];
  const requests = [{
    id: 1,
    method: "DELETE",
    status: null,
    host: "api.bancopraia.com.br",
    path: "/v2/credito/simulacao/sim_8f2c",
    size: 0,
    time: null
  }, {
    id: 2,
    method: "GET",
    status: 500,
    host: "api.bancopraia.com.br",
    path: "/v2/clientes/me/preferencias",
    size: 18,
    time: 1800
  }, {
    id: 3,
    method: "POST",
    status: 422,
    host: "api.bancopraia.com.br",
    path: "/v2/credito/contratacao",
    size: 76,
    time: 266,
    resBody: "{\n  \"erro\": \"limite_excedido\",\n  \"mensagem\": \"Valor acima do limite pré-aprovado.\"\n}"
  }, {
    id: 4,
    method: "GET",
    status: 304,
    host: "cdn.bancopraia.com.br",
    path: "/img/onboarding/credito@3x.png",
    size: 0,
    time: 41
  }, {
    id: 5,
    method: "CONNECT",
    status: 200,
    host: "app-measurement.com",
    path: ":443",
    size: 0,
    time: 58,
    tunnel: true
  }, {
    id: 6,
    method: "POST",
    status: 200,
    host: "firebaselogging-pa.googleapis.com",
    path: "/v1/firelog/legacy/batchlog",
    size: 2,
    time: 128
  }, {
    id: 7,
    method: "POST",
    status: 201,
    host: "api.bancopraia.com.br",
    path: "/v2/credito/simulacao",
    size: 116,
    time: 812,
    resBody: "{\n  \"cet_anual\": 28.399999999999,\n  \"parcelas\": 12,\n  \"primeiro_vencimento\": \"2026-11-10\",\n  \"simulacao_id\": \"sim_8f2c\",\n  \"valor_parcela\": 487.31999999999\n}"
  }, {
    id: 8,
    method: "GET",
    status: 200,
    host: "api.bancopraia.com.br",
    path: "/v2/credito/ofertas",
    size: 103,
    time: 342
  }];
  const reqHeaders = [["Accept-Language", "pt-BR"], ["Authorization", "Bearer eyJhbGciOi…"], ["Content-Type", "application/json"], ["User-Agent", "BancoPraia/5.42.0 (iPhone; iOS 18.6; Scale/3.00)"], ["X-Correlation-Id", "7c1e9f4a-2b3d-4e5f-9a8b-0c1d2e3f4a5b"]];
  const events = [{
    id: 1,
    time: "13:02:19.740",
    name: "erro_contratacao",
    params: {
      canal: "app_ios",
      codigo: "limite_excedido"
    }
  }, {
    id: 2,
    time: "13:02:18.051",
    name: "clique_continuar",
    params: {
      tela: "simulacao",
      etapa: "2"
    }
  }, {
    id: 3,
    time: "13:02:14.920",
    name: "simulacao_credito_iniciada",
    params: {
      canal: "app_ios",
      parcelas: "12",
      produto: "pessoal",
      valor: "5000"
    }
  }, {
    id: 4,
    time: "13:02:12.340",
    name: "select_content",
    params: {
      content_type: "banner",
      item_id: "credito"
    }
  }, {
    id: 5,
    time: "13:02:11.102",
    name: "screen_view",
    params: {
      firebase_previous_screen: "home",
      firebase_screen: "onboarding_credito",
      firebase_screen_class: "OnboardingCreditoViewController"
    }
  }, {
    id: 6,
    time: "13:02:10.880",
    name: "session_start",
    params: {}
  }];
  const log = [["11:03:20", "INFO", "Sessão Appium aberta · XCUITest · iPhone 16 (iOS 18.6)"], ["11:03:21", "INFO", "Page Object onboarding_credito_objs carregado (5 locators)"], ["11:03:22", "RUN", "passo 1 · click BOTAO_SIMULAR_CREDITO"], ["11:03:23", "PASS", "passo 1 ok"], ["11:03:24", "RUN", "passo 2 · send_keys CAMPO_CPF"], ["11:03:24", "HTTP", "POST /v2/credito/simulacao → 201 (812 ms)"], ["11:03:25", "PASS", "passo 2 ok"], ["11:03:26", "RUN", "passo 3 · send_keys CAMPO_VALOR"], ["11:03:27", "PASS", "passo 3 ok"], ["11:03:28", "RUN", "passo 4 · click BOTAO_CONTINUAR"], ["11:03:28", "FA", "clique_continuar {tela: simulacao, etapa: 2}"], ["11:03:29", "PASS", "passo 4 ok"], ["11:03:30", "RUN", "passo 5 · click BOTAO_CONFIRMAR_CONTRATACAO"], ["11:03:31", "PASS", "passo 5 ok"], ["11:03:32", "RUN", "passo 6 · click TOQUE_FECHAR"], ["11:03:33", "PASS", "passo 6 ok"]];
  const failLine = ["11:03:45", "FAIL", "NoSuchElementError: BOTAO_CONFIRMAR_CONTRATACAO não ficou visível em 15 s"];
  const devices = [{
    id: "iphone16",
    name: "iPhone 16",
    platform: "ios",
    detail: "Simulador · iOS 18.6"
  }, {
    id: "iphone15",
    name: "iPhone 15 Pro",
    platform: "ios",
    detail: "Simulador · desligado",
    off: true
  }, {
    id: "pixel7",
    name: "Pixel 7",
    platform: "android",
    detail: "emulator-5554"
  }];
  return {
    nodes,
    steps,
    requests,
    reqHeaders,
    events,
    log,
    failLine,
    devices
  };
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/data.js", error: String((e && e.message) || e) }); }

// ui_kits/macos-app/spring.js
try { (() => {
// Mola com velocidade preservada (WWDC23 "Animate with springs"): massa 1,
// rigidez = (2π/duração)², amortecimento = 4π(1−bounce)/duração. Interrompível: um novo alvo
// continua a partir da posição e da velocidade atuais.
(function () {
  const params = (duration, bounce) => ({
    k: Math.pow(2 * Math.PI / duration, 2),
    c: bounce >= 0 ? 4 * Math.PI * (1 - bounce) / duration : 4 * Math.PI / (duration * (1 + bounce))
  });
  function useSpring(target, {
    duration = 0.5,
    bounce = 0,
    instant = false
  } = {}) {
    const [value, setValue] = React.useState(target);
    const st = React.useRef({
      x: target,
      v: 0,
      raf: 0,
      last: 0
    });
    React.useEffect(() => {
      const s = st.current;
      cancelAnimationFrame(s.raf);
      if (instant) {
        s.x = target;
        s.v = 0;
        setValue(target);
        return;
      }
      const {
        k,
        c
      } = params(duration, bounce);
      s.last = performance.now();
      const tick = now => {
        const dt = Math.min(0.032, (now - s.last) / 1000);
        s.last = now;
        const a = k * (target - s.x) - c * s.v;
        s.v += a * dt;
        s.x += s.v * dt;
        if (Math.abs(target - s.x) < 0.3 && Math.abs(s.v) < 2) {
          s.x = target;
          s.v = 0;
          setValue(target);
          return;
        }
        setValue(s.x);
        s.raf = requestAnimationFrame(tick);
      };
      s.raf = requestAnimationFrame(tick);
      return () => cancelAnimationFrame(s.raf);
    }, [target, duration, bounce, instant]);
    return value;
  }
  window.mbUseSpring = useSpring;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/macos-app/spring.js", error: String((e && e.message) || e) }); }

__ds_ns.DataTable = __ds_scope.DataTable;

__ds_ns.DiagnosticCard = __ds_scope.DiagnosticCard;

__ds_ns.EmptyState = __ds_scope.EmptyState;

__ds_ns.InlineError = __ds_scope.InlineError;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.PopUpButton = __ds_scope.PopUpButton;

__ds_ns.SearchField = __ds_scope.SearchField;

__ds_ns.SegmentedControl = __ds_scope.SegmentedControl;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.TextField = __ds_scope.TextField;

__ds_ns.CountBadge = __ds_scope.CountBadge;

__ds_ns.ICON_NAMES = __ds_scope.ICON_NAMES;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.ProgressIndicator = __ds_scope.ProgressIndicator;

__ds_ns.StatusIndicator = __ds_scope.StatusIndicator;

__ds_ns.TypeChip = __ds_scope.TypeChip;

__ds_ns.AccessoryBar = __ds_scope.AccessoryBar;

__ds_ns.Sidebar = __ds_scope.Sidebar;

__ds_ns.SidebarBottomBar = __ds_scope.SidebarBottomBar;

__ds_ns.SidebarItem = __ds_scope.SidebarItem;

__ds_ns.SidebarSection = __ds_scope.SidebarSection;

__ds_ns.Toolbar = __ds_scope.Toolbar;

__ds_ns.ToolbarTitle = __ds_scope.ToolbarTitle;

__ds_ns.ToolbarSpacer = __ds_scope.ToolbarSpacer;

__ds_ns.ToolbarButton = __ds_scope.ToolbarButton;

__ds_ns.ToolbarGroup = __ds_scope.ToolbarGroup;

__ds_ns.ToolbarSearch = __ds_scope.ToolbarSearch;

__ds_ns.Alert = __ds_scope.Alert;

__ds_ns.Menu = __ds_scope.Menu;

__ds_ns.ContextMenu = __ds_scope.ContextMenu;

__ds_ns.Popover = __ds_scope.Popover;

__ds_ns.Sheet = __ds_scope.Sheet;

__ds_ns.Tooltip = __ds_scope.Tooltip;

__ds_ns.DeviceFrame = __ds_scope.DeviceFrame;

__ds_ns.MenuBar = __ds_scope.MenuBar;

__ds_ns.Splitter = __ds_scope.Splitter;

__ds_ns.TrafficLights = __ds_scope.TrafficLights;

__ds_ns.Window = __ds_scope.Window;

})();

import React from "react";

const G = {
  close: <svg width="8" height="8" viewBox="0 0 8 8"><path d="M1.5 1.5l5 5M6.5 1.5l-5 5" stroke="currentColor" strokeWidth="1.2" /></svg>,
  min: <svg width="8" height="8" viewBox="0 0 8 8"><path d="M1 4h6" stroke="currentColor" strokeWidth="1.2" /></svg>,
  zoom: <svg width="8" height="8" viewBox="0 0 8 8"><path d="M2 2h3L2 5zM6 6H3l3-3z" fill="currentColor" /></svg>
};

// Botões fechar / minimizar / zoom. Os glifos aparecem no hover do grupo; cinza na janela inativa.
export function TrafficLights({ onClose, onMinimize, onZoom }) {
  return (
    <div className="mb-traffic">
      <i role="button" aria-label="Fechar" onClick={onClose}>{G.close}</i>
      <i role="button" aria-label="Minimizar" onClick={onMinimize}>{G.min}</i>
      <i role="button" aria-label="Zoom" onClick={onZoom}>{G.zoom}</i>
    </div>
  );
}

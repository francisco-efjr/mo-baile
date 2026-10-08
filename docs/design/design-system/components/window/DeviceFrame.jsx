import React from "react";

// Moldura de aparelho para o espelho ao vivo (raio 40 / tela 33 — concêntricos com padding 7).
export function DeviceFrame({ width = 258, height = 540, notch = true, children, onMouseMove, onMouseLeave, onClick, screenRef }) {
  const scale = width / 258;
  return (
    <div className="mb-device" style={{ width, height, borderRadius: 40 * scale, padding: 7 * scale }}>
      <div ref={screenRef} className="mb-device__screen" style={{ borderRadius: 33 * scale }} onMouseMove={onMouseMove} onMouseLeave={onMouseLeave} onClick={onClick}>
        {notch && <div className="mb-device__notch" style={{ width: 76 * scale, height: 20 * scale, top: 9 * scale }} />}
        {children}
      </div>
    </div>
  );
}

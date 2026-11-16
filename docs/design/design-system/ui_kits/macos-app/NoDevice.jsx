// Sem dispositivo: placeholder do aparelho + diagnóstico do ambiente por plataforma.
function NoDeviceView({ phase, onStartWDA, onOpenEmulator, onRescan, lastScan }) {
  const { DiagnosticCard, Button, PopUpButton, Icon } = window.MoBaileDesignSystem_ce6669;
  const checking = phase === "checking";
  const iosReady = phase === "iosReady";
  const ios = checking ? null : [
    { label: "Ferramentas do Xcode", detail: "xcrun disponível", state: "ok" },
    { label: "Simulador instalado", detail: "2 disponíveis", state: "ok" },
    { label: "Simulador ligado", detail: "iPhone 16 Pro", state: "ok" },
    iosReady ? { label: "WebDriverAgent", detail: "Respondendo em http://localhost:8100", state: "ok" }
      : { label: "WebDriverAgent", detail: "Sem resposta em http://localhost:8100. O espelho funciona; toque e hierarquia precisam dele.", state: "warn" }
  ];
  const android = checking ? null : iosReady ? [
    { label: "ADB instalado", detail: "adb não encontrado no PATH. Instale com brew install android-platform-tools.", state: "error" },
    { label: "Dispositivo autorizado", state: "off" },
    { label: "Emulador disponível", detail: "Nenhum AVD criado.", state: "warn" }
  ] : [
    { label: "ADB instalado", detail: "adb", state: "ok" },
    { label: "Dispositivo autorizado", detail: "Nenhum aparelho conectado.", state: "warn" },
    { label: "Emulador disponível", detail: "2 AVD(s) parados.", state: "warn" }
  ];
  const sims = [{ value: "16p", label: "iPhone 16 Pro" }, { value: "15", label: "iPhone 15" }];
  const avds = [{ value: "p7", label: "Pixel 7 API 34" }, { value: "p4", label: "Pixel 4a API 30" }];
  return (
    <div style={{ height: "100%", overflow: "auto", display: "flex", flexDirection: "column", alignItems: "center", padding: "28px 20px 20px", background: "var(--bg-content)" }}>
      <div aria-hidden="true" style={{ width: 92, height: 184, borderRadius: 22, border: "1.5px dashed var(--label-quaternary)", display: "grid", placeItems: "center", marginBottom: 18 }}>
        <Icon name="smartphone" size={28} strokeWidth={1.3} color="var(--label-tertiary)" />
      </div>
      <h2 style={{ margin: 0, fontSize: 17, lineHeight: "22px", fontWeight: 600 }}>Conecte um dispositivo para começar</h2>
      <p style={{ margin: "6px 0 20px", color: "var(--label-secondary)", textAlign: "center", maxWidth: 440, textWrap: "pretty" }}>O Mo baile detecta simuladores, emuladores e aparelhos físicos automaticamente. Se não houver nenhum ligado, dá para abrir um daqui.</p>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(2, 264px)", gap: 14 }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <DiagnosticCard platform="ios" title={checking ? "iOS" : "iOS · WebDriverAgent"} ready={iosReady} checks={ios}
            actionLabel={iosReady ? "Ir para o Simulador" : "Iniciar WebDriverAgent"} actionDisabled={checking} onAction={onStartWDA} />
          <PopUpButton variant="plain" size="small" options={sims} value="16p" prefix="Simulador:" />
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          <DiagnosticCard platform="android" title={checking ? "Android" : "Android · ADB"} checks={android}
            actionLabel="Abrir Emulador" actionDisabled={checking || iosReady} onAction={onOpenEmulator} />
          <PopUpButton variant="plain" size="small" options={avds} value="p7" prefix="Emulador:" />
        </div>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 18, fontSize: 11, color: "var(--label-secondary)" }}>
        <span className="mb-mono mb-tabular">{checking ? "procurando dispositivos…" : "último scan " + lastScan}</span>
        <Button size="small" variant="plain" icon="refresh-cw" onClick={onRescan}>Verificar de Novo</Button>
      </div>
    </div>
  );
}
Object.assign(window, { NoDeviceView });

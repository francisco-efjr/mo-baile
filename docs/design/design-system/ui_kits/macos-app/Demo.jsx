// Painel do protótipo (fora do app): aparência, acessibilidade, estados e nota da tela atual.
const MB_NOTES = {
  pageObjects: "Page Objects. Antes: 3 colunas fixas (espelho | hierarquia | código) e duas barras no topo. Agora: as áreas viram itens da sidebar, a hierarquia vai para o Inspector recolhível e o seletor (Auto/ID/XPath/Coords), Estrutura e Lado a lado ficam na barra acessória, só sobre o conteúdo. Os passos gravados aparecem na sidebar, com arraste, menu de contexto e desfazer.",
  network: "Rede HTTP. Antes: os botões do proxy dividiam a barra com o filtro. Agora o filtro é a busca da toolbar (⌘F). Proxy, iPhone em Debug, Exportar HAR… e Limpar Tráfego ficam na barra acessória. A tabela tem colunas ordenáveis e redimensionáveis. Limpar pede confirmação e pode ser desfeito. O cartão de Correlação virou um popover.",
  analytics: "Analytics. Mesma estrutura de Rede para a mesma tarefa: estado do listener, origem do tagueamento (pop-up desabilitado durante a escuta), Iniciar/Parar, Copiar TSV, Exportar JSON… e Limpar. O detalhe divide Parâmetros e Log bruto.",
  noDevice: "Sem dispositivo. O conteúdo e os cartões de diagnóstico são os mesmos do original, com uma diferença: o checklist agora usa ícone, cor e texto juntos. A busca roda de novo a cada 1,5 s, e “Verificar de Novo” força uma busca na hora.",
  settings: "Ajustes (⌘,). Janela separada com abas por ícone. Aparência e o seletor padrão saíram da barra principal. Portas e host vêm do .env. Cada mudança vale na hora, sem botão Salvar."
};
function DemoPanel({ demo, setDemo, appearance, setAppearance, noteKey, collapsed, setCollapsed }) {
  const { Switch, SegmentedControl, PopUpButton, Icon } = window.MoBaileDesignSystem_ce6669;
  const row = (label, ctrl) => <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, minHeight: 24 }}><span>{label}</span>{ctrl}</div>;
  return (
    <div className="mb-root" style={{ position: "fixed", right: 14, bottom: 14, zIndex: 3000, width: 272, borderRadius: 14, background: "var(--glass-bg-strong)", WebkitBackdropFilter: "var(--glass-filter)", backdropFilter: "var(--glass-filter)", boxShadow: "var(--glass-highlight), var(--shadow-popover)", fontSize: 12 }}>
      <button type="button" onClick={() => setCollapsed(!collapsed)} style={{ all: "unset", display: "flex", alignItems: "center", gap: 6, width: "100%", boxSizing: "border-box", padding: "9px 12px", fontWeight: 600, cursor: "default" }}>
        <Icon name="sliders-horizontal" size={14} /> <span style={{ flex: 1 }}>Protótipo</span><Icon name={collapsed ? "chevron-up" : "chevron-down"} size={13} />
      </button>
      {!collapsed && <div style={{ padding: "0 12px 12px", display: "flex", flexDirection: "column", gap: 6 }}>
        {row("Aparência", <SegmentedControl size="small" items={[{ value: "light", label: "Claro" }, { value: "dark", label: "Escuro" }]} value={appearance} onChange={setAppearance} />)}
        {row("Janela ativa", <Switch size="small" checked={demo.active} onChange={v => setDemo("active", v)} />)}
        {row("Reduzir movimento", <Switch size="small" checked={demo.reduceMotion} onChange={v => setDemo("reduceMotion", v)} />)}
        {row("Reduzir transparência", <Switch size="small" checked={demo.reduceTransparency} onChange={v => setDemo("reduceTransparency", v)} />)}
        {row("Aumentar contraste", <Switch size="small" checked={demo.contrast} onChange={v => setDemo("contrast", v)} />)}
        <div style={{ height: 1, background: "var(--separator)", margin: "4px 0" }} />
        {row("Estado", <PopUpButton size="small" minWidth={150} value={demo.scenario} onChange={v => setDemo("scenario", v)} options={[
          { value: "connected", label: "Conectado" }, { value: "loading", label: "Carregando" }, { value: "error", label: "Erro (proxy)" }, "-",
          { value: "checking", label: "Sem aparelho · verificando" }, { value: "noDevice", label: "Sem aparelho" }, { value: "iosReady", label: "Sem aparelho · iOS pronto" }]} />)}
        {row("Execução do fluxo", <SegmentedControl size="small" items={[{ value: "pass", label: "Sucesso" }, { value: "fail", label: "Falha" }]} value={demo.outcome} onChange={v => setDemo("outcome", v)} />)}
        <div style={{ height: 1, background: "var(--separator)", margin: "4px 0" }} />
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--label-secondary)" }}>O que mudou nesta tela</div>
        <div style={{ fontSize: 11, lineHeight: "15px", color: "var(--label-secondary)", textWrap: "pretty", maxHeight: 150, overflow: "auto" }}>{MB_NOTES[noteKey]}</div>
      </div>}
    </div>
  );
}
Object.assign(window, { DemoPanel, MB_NOTES });

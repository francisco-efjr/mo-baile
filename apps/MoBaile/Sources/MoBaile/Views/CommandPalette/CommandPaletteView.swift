import SwiftUI
import AppKit

/// Paleta de comandos (FLU-1): todas as ações do app num campo de busca.
///
/// Painel flutuante sobre a janela, no vidro da camada de navegação. ⇧⌘P
/// abre; ↑ e ↓ escolhem; Enter executa; Esc ou clique fora fecham. Ação
/// indisponível aparece esmaecida, com o motivo, e Enter só lê o motivo.
///
/// Montagem: `ContentView` põe `CommandPaletteOverlay()` como overlay da
/// janela, e a entrada e a saída usam `Motion.crossfade` (só opacidade, então
/// já vale para Reduzir movimento). Doc: `docs/design/componentes/command-palette.md`.
struct CommandPaletteOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        if appState.commandPalettePresented {
            ZStack(alignment: .top) {
                // Clique fora fecha, como um popover.
                themeManager.current.floatingScrim
                    .contentShape(Rectangle())
                    .onTapGesture { appState.commandPalettePresented = false }
                    .accessibilityHidden(true)
                CommandPaletteView()
                    .padding(.top, DesignMetrics.CommandPalette.topOffset)
                    .padding(.horizontal, DesignMetrics.Spacing.s7)
            }
            .transition(.opacity)
        }
    }
}

/// O painel da paleta: campo, lista por seção, aviso de indisponível e rodapé.
///
/// Lê `AppState`, `EngineSession` e `ThemeManager` do ambiente (obrigatórios;
/// faltar um deles derruba o preview na hora, o que é o aviso que se quer).
/// O termo buscado pode ser controlado de fora por `query`; sem ele, a paleta
/// guarda o próprio termo e abre vazia.
struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openSettings) private var openSettings

    /// Termo controlado de fora, quando houver. `nil`: estado interno.
    private let externalQuery: Binding<String>?
    @State private var internalQuery = ""
    @State private var selection: CommandID?
    @State private var keyMonitor: Any?
    /// Janela onde a paleta abriu. Tecla de outra janela não é da paleta.
    @State private var janela: NSWindow?
    @State private var aviso: String?
    @FocusState private var campoFocado: Bool

    private let recents = CommandRecents()
    /// Largura do painel. Alias do token, mantido para quem já lia daqui.
    static let width: CGFloat = DesignMetrics.CommandPalette.width

    /// - Parameter query: termo buscado, controlado por quem monta. Omitido, a
    ///   paleta abre com o campo vazio e guarda o termo sozinha.
    init(query: Binding<String>? = nil) {
        self.externalQuery = query
    }

    private var queryBinding: Binding<String> { externalQuery ?? $internalQuery }
    private var query: String { queryBinding.wrappedValue }

    private var theme: any ThemeTokens { themeManager.current }

    private var context: CommandContext { .current(appState, session, themeManager) }

    private var sections: [CommandSearch.Section] {
        CommandSearch.sections(CommandRegistry.commands(in: context), query: query, recents: recents.ids)
    }

    private var flat: [AppCommand] { sections.flatMap(\.commands) }

    var body: some View {
        VStack(spacing: 0) {
            campo
            Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
            lista
            if let aviso {
                Text(aviso)
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignMetrics.Spacing.s6)
                    .padding(.vertical, DesignMetrics.Spacing.s4)
                    .background(theme.warningTint)
            }
            rodape
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous)
                .strokeBorder(theme.separatorStrong, lineWidth: DesignMetrics.hairline / 2)
        )
        .shadow(color: theme.floatingShadow, radius: DesignMetrics.Shadow.floatingRadius, y: DesignMetrics.Shadow.floatingY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paleta de comandos")
        .accessibilityAddTraits(.isModal)
        .onAppear {
            campoFocado = true
            selection = flat.first(where: \.isEnabled)?.id ?? flat.first?.id
            janela = NSApp.keyWindow
            instalarTeclado(em: janela)
        }
        .onDisappear(perform: removerTeclado)
        // A janela perdeu o foco (Ajustes, painel de arquivo, outro app): a
        // paleta fecha, como um popover.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { aviso in
            guard let janela, (aviso.object as? NSWindow) === janela else { return }
            fechar()
        }
        .onChange(of: query) { _, _ in
            aviso = nil
            selection = flat.first(where: \.isEnabled)?.id ?? flat.first?.id
        }
    }

    // MARK: - Partes

    private var campo: some View {
        HStack(spacing: DesignMetrics.CommandPalette.gap) {
            Image(systemName: "command")
                .font(DSFont.Symbol.field)
                .foregroundStyle(theme.labelSecondary)
                .accessibilityHidden(true)
            TextField("Buscar ação: rodar, proxy, aparelho, ajustes…", text: queryBinding)
                .textFieldStyle(.plain)
                .font(DSFont.title3.weight(.regular))
                .focused($campoFocado)
                .accessibilityLabel("Buscar ação")
                .accessibilityHint("Setas para escolher, Enter para executar, Esc para fechar")
        }
        .padding(.horizontal, DesignMetrics.Spacing.s6)
        .frame(height: DesignMetrics.CommandPalette.fieldHeight)
    }

    private var lista: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if flat.isEmpty {
                        Text("Nenhuma ação encontrada para “\(query)”.")
                            .font(DSFont.body)
                            .foregroundStyle(theme.labelSecondary)
                            .padding(DesignMetrics.Spacing.s7)
                    }
                    ForEach(sections) { secao in
                        Text(secao.title)
                            .font(DSFont.subheadlineSemibold)
                            .foregroundStyle(theme.labelSecondary)
                            .padding(.horizontal, DesignMetrics.Spacing.s6)
                            .padding(.top, DesignMetrics.CommandPalette.gap)
                            .padding(.bottom, DesignMetrics.Spacing.s2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(secao.commands) { comando in
                            CommandPaletteRow(command: comando, selected: comando.id == selection)
                                .id(comando.id)
                                .onTapGesture { executar(comando) }
                                .onHover { dentro in if dentro { selection = comando.id } }
                        }
                    }
                }
                .padding(.bottom, DesignMetrics.Spacing.s3)
            }
            .frame(maxHeight: DesignMetrics.CommandPalette.listMaxHeight)
            .onChange(of: selection) { _, nova in
                guard let nova else { return }
                proxy.scrollTo(nova, anchor: nil)
            }
        }
    }

    private var rodape: some View {
        HStack(spacing: DesignMetrics.Spacing.s6) {
            dica("↑↓", "escolher")
            dica("↩", "executar")
            dica("esc", "fechar")
            Spacer()
        }
        .padding(.horizontal, DesignMetrics.Spacing.s6)
        .frame(height: DesignMetrics.CommandPalette.footerHeight)
        .background(theme.fillQuaternary)
        .accessibilityHidden(true)
    }

    private func dica(_ tecla: String, _ texto: String) -> some View {
        HStack(spacing: DesignMetrics.Spacing.s2) {
            Text(tecla).font(DSFont.mono(11)).foregroundStyle(theme.labelPrimary)
            Text(texto).font(DSFont.subheadline).foregroundStyle(theme.labelSecondary)
        }
    }

    // MARK: - Teclado

    /// Setas, Enter e Esc enquanto a paleta está aberta. O monitor local pega
    /// a tecla antes do editor do campo, que usaria ↑ e ↓ para mover o cursor.
    /// Ele vê as teclas de todas as janelas do app; quem decide se a tecla é
    /// da paleta é `CommandPaletteKeyboard` (R-01).
    private func instalarTeclado(em alvo: NSWindow?) {
        removerTeclado()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak alvo] evento in
            let situacao = CommandPaletteKeyboard.Situation(
                paletteOpen: appState.commandPalettePresented,
                eventInPaletteWindow: alvo != nil && evento.window === alvo,
                modalOpen: NSApp.modalWindow != nil,
                sheetAttached: alvo?.attachedSheet != nil
            )
            switch CommandPaletteKeyboard.action(keyCode: evento.keyCode, modifiers: evento.modifierFlags, situation: situacao) {
            case .move(let passo):
                mover(passo)
                return nil
            case .execute:
                if let atual = flat.first(where: { $0.id == selection }) { executar(atual) }
                return nil
            case .close:
                fechar()
                return nil
            case .passThrough:
                return evento
            }
        }
    }

    private func removerTeclado() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func mover(_ passo: Int) {
        let itens = flat
        guard !itens.isEmpty else { return }
        let atual = itens.firstIndex { $0.id == selection } ?? -1
        let proximo = (atual + passo + itens.count) % itens.count
        selection = itens[proximo].id
        aviso = nil
        // O foco do VoiceOver fica no campo; o anúncio diz onde a seleção está.
        AccessibilityNotification.Announcement(CommandPaletteRow.spokenLabel(itens[proximo])).post()
    }

    /// Fecha a paleta. O monitor sai aqui, antes de o estado mudar: a view
    /// só some no fim da transição, e um Return nesse intervalo não pode
    /// executar o comando de novo nem chegar a um alerta aberto pela ação.
    private func fechar() {
        removerTeclado()
        appState.commandPalettePresented = false
    }

    private func executar(_ comando: AppCommand) {
        guard comando.isEnabled else {
            let motivo = "\(comando.title): \(comando.disabledReason ?? "indisponível agora")."
            aviso = motivo
            AccessibilityNotification.Announcement(motivo).post()
            return
        }
        recents.record(comando.id)
        fechar()
        let performer = CommandPerformer(
            appState: appState, session: session, themeManager: themeManager,
            openSettings: { openSettings() }
        )
        // Depois de fechar: alertas e sheets abertos pela ação não disputam a
        // tela com a paleta.
        DispatchQueue.main.async { performer.perform(comando.id) }
    }
}

/// Uma linha da paleta: ícone, título, motivo quando indisponível e atalho.
///
/// Não é botão de verdade: o foco de teclado fica no campo da paleta, e a
/// linha é escolhida por ↑ e ↓ ou pelo mouse. Para o VoiceOver, ela se
/// apresenta como botão com o rótulo de `spokenLabel(_:)`.
struct CommandPaletteRow: View {
    @Environment(ThemeManager.self) private var themeManager
    /// A ação desenhada. `disabledReason` não nulo esmaece a linha e mostra o motivo.
    let command: AppCommand
    /// Linha sob o cursor do teclado ou do mouse.
    let selected: Bool

    /// - Parameters:
    ///   - command: a ação, já com a disponibilidade do contexto.
    ///   - selected: se é a linha escolhida.
    init(command: AppCommand, selected: Bool) {
        self.command = command
        self.selected = selected
    }

    /// Transparência do ícone, do título e do atalho de ação indisponível (D6).
    static let disabledOpacity: Double = 0.42

    /// O que o VoiceOver lê: título, atalho e motivo de indisponibilidade.
    static func spokenLabel(_ command: AppCommand) -> String {
        var texto = command.title
        if let atalho = command.shortcut { texto += ", atalho \(atalho.spoken)" }
        if let motivo = command.disabledReason { texto += ". Indisponível: \(motivo)" }
        return texto
    }

    var body: some View {
        let theme = themeManager.current
        // Selecionada e disponível: fundo no destaque e texto branco. Selecionada
        // e indisponível: fundo neutro, para não parecer que Enter vai executar.
        let destaque = selected && command.isEnabled
        // Desabilitado: 42% no ícone e no título, sem sumir (design system). O
        // motivo fica com a cor secundária, legível.
        let esmaecer = command.isEnabled ? 1 : Self.disabledOpacity
        HStack(spacing: DesignMetrics.CommandPalette.gap) {
            Image(systemName: command.symbol)
                .font(DSFont.Symbol.body)
                .frame(width: DesignMetrics.CommandPalette.rowIconWidth)
                .foregroundStyle(destaque ? theme.onAccent : theme.labelSecondary)
                .opacity(esmaecer)
            VStack(alignment: .leading, spacing: DesignMetrics.CommandPalette.titleReasonGap) {
                Text(command.title)
                    .font(DSFont.body)
                    .foregroundStyle(destaque ? theme.onAccent : theme.labelPrimary)
                    .lineLimit(1)
                    .opacity(esmaecer)
                if let motivo = command.disabledReason {
                    Text(motivo)
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DesignMetrics.Spacing.s4)
            if let atalho = command.shortcut {
                Text(atalho.display)
                    .font(DSFont.mono(12))
                    .foregroundStyle(destaque ? theme.onAccent : theme.labelSecondary)
                    .opacity(esmaecer)
            }
        }
        .padding(.horizontal, DesignMetrics.CommandPalette.gap)
        .padding(.vertical, DesignMetrics.Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.menuItem, style: .continuous)
                .fill(destaque ? theme.accent : (selected ? theme.fillPrimary : Color.clear))
        )
        .padding(.horizontal, DesignMetrics.Spacing.s3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(command))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Previews

/// Ambiente de preview: estado novo, motor que não sobe (sem processo de
/// verdade) e o tema Praia. Sem aparelho e com o motor parado, boa parte das
/// ações aparece indisponível com o motivo, como na primeira abertura.
@MainActor
private enum CommandPalettePreview {
    static func ambiente<V: View>(_ conteudo: V, tema: any ThemeTokens = PraiaLightTheme()) -> some View {
        let estado = AppState()
        let sessao = EngineSession(state: estado) {
            throw EngineError.engineNotFound("Preview: o motor não sobe aqui.")
        }
        return conteudo
            .environment(estado)
            .environment(sessao)
            .environment(ThemeManager(preview: tema))
            .padding(DesignMetrics.Spacing.s7)
    }

    static let rodar = AppCommand(
        id: .run, title: "Rodar Automação", category: .automation, symbol: "play.fill",
        shortcut: .cmd("r")
    )
    static let proxy = AppCommand(
        id: .proxy, title: "Iniciar Proxy", category: .services, symbol: "network"
    )
    static let rodarSemPassos = AppCommand(
        id: .run, title: "Rodar Automação", category: .automation, symbol: "play.fill",
        shortcut: .cmd("r"), disabledReason: "Grave ao menos um passo"
    )
    static let exportarHAR = AppCommand(
        id: .exportHAR, title: "Exportar HAR…", category: .network, symbol: "square.and.arrow.up",
        shortcut: .cmdShift("e"), disabledReason: "Nenhum tráfego capturado ainda"
    )
}

#Preview("Paleta: sem termo (recentes e categorias)") {
    CommandPalettePreview.ambiente(CommandPaletteView())
}

#Preview("Paleta: com resultados (proxy)") {
    @Previewable @State var termo = "proxy"
    CommandPalettePreview.ambiente(CommandPaletteView(query: $termo))
}

#Preview("Paleta: sem resultado") {
    @Previewable @State var termo = "teletransportar"
    CommandPalettePreview.ambiente(CommandPaletteView(query: $termo))
}

#Preview("Linhas: selecionada, comum e indisponível") {
    VStack(spacing: 0) {
        CommandPaletteRow(command: CommandPalettePreview.rodar, selected: true)
        CommandPaletteRow(command: CommandPalettePreview.proxy, selected: false)
        CommandPaletteRow(command: CommandPalettePreview.rodarSemPassos, selected: false)
        CommandPaletteRow(command: CommandPalettePreview.exportarHAR, selected: true)
    }
    .frame(width: DesignMetrics.CommandPalette.width)
    .padding(.vertical, DesignMetrics.Spacing.s3)
    .environment(ThemeManager(preview: PraiaLightTheme()))
}

#Preview("Linhas: escuro") {
    VStack(spacing: 0) {
        CommandPaletteRow(command: CommandPalettePreview.rodar, selected: true)
        CommandPaletteRow(command: CommandPalettePreview.rodarSemPassos, selected: false)
    }
    .frame(width: DesignMetrics.CommandPalette.width)
    .padding(.vertical, DesignMetrics.Spacing.s3)
    .environment(ThemeManager(preview: PraiaDarkTheme()))
}

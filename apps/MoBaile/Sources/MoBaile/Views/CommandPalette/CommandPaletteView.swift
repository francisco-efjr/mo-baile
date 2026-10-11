import SwiftUI
import AppKit

/// Paleta de comandos (FLU-1): todas as ações do app num campo de busca.
///
/// Painel flutuante sobre a janela, no vidro da camada de navegação. ⇧⌘P
/// abre; ↑ e ↓ escolhem; Enter executa; Esc ou clique fora fecham. Ação
/// indisponível aparece esmaecida, com o motivo, e Enter só lê o motivo.
struct CommandPaletteOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        if appState.commandPalettePresented {
            ZStack(alignment: .top) {
                // Clique fora fecha, como um popover.
                Color.black.opacity(themeManager.current.isDark ? 0.18 : 0.06)
                    .contentShape(Rectangle())
                    .onTapGesture { appState.commandPalettePresented = false }
                    .accessibilityHidden(true)
                CommandPaletteView()
                    .padding(.top, 56)
                    .padding(.horizontal, 16)
            }
            .transition(.opacity)
        }
    }
}

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var selection: CommandID?
    @State private var keyMonitor: Any?
    @State private var aviso: String?
    @FocusState private var campoFocado: Bool

    private let recents = CommandRecents()
    static let width: CGFloat = 560

    private var theme: any ThemeTokens { themeManager.current }

    private var context: CommandContext { .current(appState, session, themeManager) }

    private var sections: [CommandSearch.Section] {
        CommandSearch.sections(CommandRegistry.commands(in: context), query: query, recents: recents.ids)
    }

    private var flat: [AppCommand] { sections.flatMap(\.commands) }

    var body: some View {
        VStack(spacing: 0) {
            campo
            Rectangle().fill(theme.separator).frame(height: 1)
            lista
            if let aviso {
                Text(aviso)
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.warningTint)
            }
            rodape
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.separatorStrong, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paleta de comandos")
        .accessibilityAddTraits(.isModal)
        .onAppear {
            campoFocado = true
            selection = flat.first(where: \.isEnabled)?.id ?? flat.first?.id
            instalarTeclado()
        }
        .onDisappear(perform: removerTeclado)
        .onChange(of: query) { _, _ in
            aviso = nil
            selection = flat.first(where: \.isEnabled)?.id ?? flat.first?.id
        }
    }

    // MARK: - Partes

    private var campo: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.labelSecondary)
                .accessibilityHidden(true)
            TextField("Buscar ação: rodar, proxy, aparelho, ajustes…", text: $query)
                .textFieldStyle(.plain)
                .font(DSFont.title3.weight(.regular))
                .focused($campoFocado)
                .accessibilityLabel("Buscar ação")
                .accessibilityHint("Setas para escolher, Enter para executar, Esc para fechar")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var lista: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if flat.isEmpty {
                        Text("Nenhuma ação encontrada para “\(query)”.")
                            .font(DSFont.body)
                            .foregroundStyle(theme.labelSecondary)
                            .padding(16)
                    }
                    ForEach(sections) { secao in
                        Text(secao.title)
                            .font(DSFont.subheadlineSemibold)
                            .foregroundStyle(theme.labelSecondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(secao.commands) { comando in
                            CommandPaletteRow(command: comando, selected: comando.id == selection)
                                .id(comando.id)
                                .onTapGesture { executar(comando) }
                                .onHover { dentro in if dentro { selection = comando.id } }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 380)
            .onChange(of: selection) { _, nova in
                guard let nova else { return }
                proxy.scrollTo(nova, anchor: nil)
            }
        }
    }

    private var rodape: some View {
        HStack(spacing: 14) {
            dica("↑↓", "escolher")
            dica("↩", "executar")
            dica("esc", "fechar")
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(theme.fillQuaternary)
        .accessibilityHidden(true)
    }

    private func dica(_ tecla: String, _ texto: String) -> some View {
        HStack(spacing: 4) {
            Text(tecla).font(DSFont.mono(11)).foregroundStyle(theme.labelPrimary)
            Text(texto).font(DSFont.subheadline).foregroundStyle(theme.labelSecondary)
        }
    }

    // MARK: - Teclado

    /// Setas, Enter e Esc enquanto a paleta está aberta. O monitor local pega
    /// a tecla antes do editor do campo, que usaria ↑ e ↓ para mover o cursor.
    private func instalarTeclado() {
        removerTeclado()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            switch evento.keyCode {
            case 125: mover(1); return nil          // ↓
            case 126: mover(-1); return nil         // ↑
            case 36, 76:                            // Return, Enter do teclado numérico
                if let atual = flat.first(where: { $0.id == selection }) { executar(atual) }
                return nil
            case 53: fechar(); return nil           // Esc
            default: return evento
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

    private func fechar() {
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
struct CommandPaletteRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let command: AppCommand
    let selected: Bool

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
        let esmaecer = command.isEnabled ? 1 : 0.42
        HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(destaque ? theme.onAccent : theme.labelSecondary)
                .opacity(esmaecer)
            VStack(alignment: .leading, spacing: 1) {
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
            Spacer(minLength: 8)
            if let atalho = command.shortcut {
                Text(atalho.display)
                    .font(DSFont.mono(12))
                    .foregroundStyle(destaque ? theme.onAccent : theme.labelSecondary)
                    .opacity(esmaecer)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(destaque ? theme.accent : (selected ? theme.fillPrimary : Color.clear))
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(command))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

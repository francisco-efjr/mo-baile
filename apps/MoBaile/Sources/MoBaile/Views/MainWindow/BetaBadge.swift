import AppKit
import SwiftUI

/// Selo "Beta" (LIB-3): o Mo baile é um produto em desenvolvimento e tem bugs.
/// Fica na barra de status, visível em toda área e no Modo Zen; o clique abre
/// Relatar um Problema. Sem vidro próprio: a barra já é superfície do sistema.
/// O texto é "Beta", então o significado nunca depende só da cor.
struct BetaBadge: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let theme = themeManager.current
        Button {
            openWindow(id: "relato")
        } label: {
            BetaCapsule()
        }
        .buttonStyle(.plain)
        .help(BetaNotice.tooltip)
        .accessibilityLabel("Versão beta")
        .accessibilityValue("em desenvolvimento, pode ter bugs")
        .accessibilityHint("Abre o relato de problema")
        .foregroundStyle(theme.labelPrimary)
    }
}

/// A cápsula em si, reaproveitada na barra lateral.
struct BetaCapsule: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        Text("Beta")
            .font(DSFont.mono(11).weight(.semibold))
            .foregroundStyle(theme.labelPrimary)
            .padding(.horizontal, 6)
            .frame(minHeight: 16)
            .background(theme.warningTint, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.highContrast ? theme.controlBorder : theme.warning, lineWidth: 1))
    }
}

/// Linha "Relatar Problema" no rodapé da barra lateral, com o selo à direita.
struct SidebarReportRow: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let theme = themeManager.current
        Button {
            openWindow(id: "relato")
        } label: {
            HStack(spacing: DesignMetrics.Spacing.s3) {
                Image(systemName: "ladybug")
                    .foregroundStyle(theme.labelSecondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("Relatar Problema")
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelPrimary)
                Spacer(minLength: DesignMetrics.Spacing.s2)
                BetaCapsule()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Conte um bug ou um erro. O relato vai para o GitHub.")
        .accessibilityLabel("Relatar Problema")
        .accessibilityValue("Beta")
    }
}

/// Sobre o Mo baile: versão, commit, aviso de beta e crédito (LIB-3).
@MainActor
enum AboutPanel {
    static func credits(commit: String?) -> String {
        var linhas = [
            "Versão beta, em desenvolvimento. Pode conter bugs e mudar sem aviso.",
            "Encontrou um problema? Use Ajuda › Relatar um Problema…",
            "",
            "Desenvolvido por Francisco Edson Ferreira Junior.",
            "Código aberto (MIT): github.com/francisco-efjr/mo-baile",
        ]
        if let commit { linhas.append("Commit \(commit.prefix(7))") }
        return linhas.joined(separator: "\n")
    }

    static func show() {
        let commit = Bundle.main.object(forInfoDictionaryKey: "MoBaileGitCommit") as? String
        let texto = NSAttributedString(
            string: credits(commit: commit),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: texto, .applicationName: "Mo baile"])
        NSApp.activate(ignoringOtherApps: true)
    }
}

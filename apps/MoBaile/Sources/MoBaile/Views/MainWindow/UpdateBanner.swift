import AppKit
import SwiftUI

/// Faixa "Versão nova disponível", no topo da coluna central, abaixo da faixa
/// do motor (LIB-4). Discreta: tom de destaque, sem som nem alerta modal, e
/// some com Lembrar Depois ou Ignorar Esta Versão.
struct UpdateBanner: View {
    /// Opcional: previews e testes que montam a janela sem o estado não têm faixa.
    @Environment(UpdateState.self) private var updates: UpdateState?

    var body: some View {
        UpdateBannerView(
            release: updates?.available,
            installed: updates?.currentVersion ?? "dev",
            onNotes: { if let r = updates?.available, r.htmlURL.scheme == "https" { NSWorkspace.shared.open(r.htmlURL) } },
            onDownload: { if let r = updates?.available, r.downloadURL.scheme == "https" { NSWorkspace.shared.open(r.downloadURL) } },
            onSnooze: { updates?.snooze() },
            onIgnore: { updates?.ignoreCurrent() }
        )
    }
}

/// Desenho da faixa, sem depender do `UpdateState` (previews e testes).
struct UpdateBannerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let release: ReleaseInfo?
    let installed: String
    let onNotes: () -> Void
    let onDownload: () -> Void
    let onSnooze: () -> Void
    let onIgnore: () -> Void

    static func title(_ release: ReleaseInfo) -> String {
        "Versão \(release.version?.description ?? release.tagName) disponível"
    }

    var body: some View {
        Group {
            if let release {
                faixa(release)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.smooth(reduceMotion: reduceMotion), value: release)
        .onChange(of: release) { _, novo in
            if let novo { AccessibilityNotification.Announcement(Self.title(novo)).post() }
        }
    }

    private func faixa(_ release: ReleaseInfo) -> some View {
        let theme = themeManager.current
        return HStack(alignment: .center, spacing: DesignMetrics.EngineBanner.gap) {
            Image(systemName: "arrow.down.circle.fill")
                .font(DSFont.Symbol.banner)
                .foregroundStyle(theme.accent)
                .frame(width: DesignMetrics.EngineBanner.iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text(Self.title(release))
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                Text("Você está na \(installed). Baixe o zip, feche o Mo baile e troque o app na pasta Aplicativos.")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Ver Novidades", action: onNotes)
                .help("Abre as notas da versão no GitHub")
            Button("Baixar", action: onDownload)
                .buttonStyle(.borderedProminent)
                .help("Baixa o zip da versão nova pelo navegador")
            Menu {
                Button("Lembrar Amanhã", action: onSnooze)
                Button("Ignorar Esta Versão", action: onIgnore)
            } label: {
                Image(systemName: "xmark")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Lembrar depois ou ignorar esta versão")
            .accessibilityLabel("Dispensar aviso de versão")
        }
        .padding(.horizontal, DesignMetrics.Spacing.s6)
        .padding(.vertical, DesignMetrics.EngineBanner.verticalPadding)
        .background(theme.accentTint)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Atualização disponível")
    }
}

#Preview("Versão nova") {
    UpdateBannerView(
        release: ReleaseInfo(tagName: "v3.24.0", htmlURL: URL(string: "https://example.test/r")!),
        installed: "3.23.0", onNotes: {}, onDownload: {}, onSnooze: {}, onIgnore: {}
    )
    .environment(ThemeManager(preview: PraiaLightTheme()))
    .frame(width: DesignMetrics.Window.minSize.width - DesignMetrics.Widths.sidebarIdeal)
}

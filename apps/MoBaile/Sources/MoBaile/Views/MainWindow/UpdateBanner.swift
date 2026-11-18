import AppKit
import SwiftUI

/// Faixa "Versão nova disponível", no topo da coluna central, abaixo da faixa
/// do motor (LIB-4, ADR 0008). Discreta: tom de destaque, sem som nem alerta
/// modal. Acompanha a instalação: Atualizar, baixando, pronta para reiniciar,
/// instalando ou falha com o motivo.
struct UpdateBanner: View {
    /// Opcional: previews e testes que montam a janela sem o estado não têm faixa.
    @Environment(UpdateState.self) private var updates: UpdateState?

    var body: some View {
        UpdateBannerView(
            release: updates?.available,
            installed: updates?.currentVersion ?? "dev",
            phase: updates?.phase ?? .idle,
            blocker: updates?.inPlaceBlocker,
            actions: UpdateBannerActions(
                notes: { updates?.openReleaseNotes() },
                update: { updates?.update() },
                restart: { updates?.restartNow() },
                cancel: { updates?.cancelDownload() },
                retry: { updates?.retry() },
                manualDownload: { updates?.openDownloadPage() },
                quit: { NSApp.terminate(nil) },
                snooze: { updates?.snooze() },
                ignore: { updates?.ignoreCurrent() }
            )
        )
    }
}

struct UpdateBannerActions {
    var notes: () -> Void = {}
    var update: () -> Void = {}
    var restart: () -> Void = {}
    var cancel: () -> Void = {}
    var retry: () -> Void = {}
    var manualDownload: () -> Void = {}
    var quit: () -> Void = {}
    var snooze: () -> Void = {}
    var ignore: () -> Void = {}
}

/// Desenho da faixa, sem depender do `UpdateState` (previews e testes).
struct UpdateBannerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let release: ReleaseInfo?
    let installed: String
    var phase: UpdateState.Phase = .idle
    /// Por que não dá para instalar com um clique (o botão vira Baixar).
    var blocker: String? = nil
    var actions = UpdateBannerActions()

    static func title(_ release: ReleaseInfo, phase: UpdateState.Phase = .idle) -> String {
        let versao = release.version?.description ?? release.tagName
        switch phase {
        case .idle: return "Versão \(versao) disponível"
        case .downloading: return "Baixando a versão \(versao)…"
        case .ready: return "Versão \(versao) pronta para instalar"
        case .installing: return "Instalando a versão \(versao)…"
        case .installedNeedsRestart: return "Versão \(versao) instalada"
        case .failed: return "Não deu para atualizar para a \(versao)"
        }
    }

    static func detail(installed: String, phase: UpdateState.Phase, blocker: String?) -> String {
        switch phase {
        case .idle:
            if let blocker { return "Você está na \(installed). \(blocker)" }
            return "Você está na \(installed). O Mo baile baixa a versão nova, confere a assinatura e abre de novo já atualizado."
        case .downloading(let fracao):
            return "\(Int((fracao * 100).rounded()))% · dá para continuar usando o app enquanto baixa."
        case .ready:
            return "O Mo baile fecha e abre de novo. Salve o que estiver aberto antes."
        case .installing:
            return "O Mo baile vai fechar e abrir de novo."
        case .installedNeedsRestart:
            return "Feche e abra o Mo baile para usar a versão nova."
        case .failed(let motivo):
            return motivo
        }
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
            if let novo { AccessibilityNotification.Announcement(Self.title(novo, phase: phase)).post() }
        }
        .onChange(of: phase) { _, novo in
            guard let release else { return }
            switch novo {
            case .ready, .failed, .installedNeedsRestart:
                AccessibilityNotification.Announcement(Self.title(release, phase: novo)).post()
            default:
                break
            }
        }
    }

    private var symbol: String {
        switch phase {
        case .failed: "exclamationmark.triangle.fill"
        case .ready, .installedNeedsRestart: "checkmark.circle.fill"
        default: "arrow.down.circle.fill"
        }
    }

    private func faixa(_ release: ReleaseInfo) -> some View {
        let theme = themeManager.current
        return HStack(alignment: .center, spacing: DesignMetrics.EngineBanner.gap) {
            Image(systemName: symbol)
                .font(DSFont.Symbol.banner)
                .foregroundStyle(theme.accent)
                .frame(width: DesignMetrics.EngineBanner.iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text(Self.title(release, phase: phase))
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                Text(Self.detail(installed: installed, phase: phase, blocker: blocker))
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            botoes
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

    @ViewBuilder
    private var botoes: some View {
        switch phase {
        case .idle:
            Button("Ver Novidades", action: actions.notes)
                .help("Abre as notas da versão no GitHub")
            if blocker == nil {
                Button("Atualizar", action: actions.update)
                    .buttonStyle(.borderedProminent)
                    .help("Baixa a versão nova e confere a assinatura; o app só fecha quando você mandar")
            } else {
                Button("Baixar", action: actions.manualDownload)
                    .buttonStyle(.borderedProminent)
                    .help("Baixa o zip da versão nova pelo navegador")
            }
            dispensar
        case .downloading(let fracao):
            ProgressView(value: fracao)
                .frame(width: 120)
                .accessibilityLabel("Progresso do download")
            Button("Cancelar", action: actions.cancel)
        case .ready:
            Button("Ver Novidades", action: actions.notes)
                .help("Abre as notas da versão no GitHub")
            Button("Reiniciar e Atualizar", action: actions.restart)
                .buttonStyle(.borderedProminent)
                .help("Fecha o Mo baile, troca o app e abre a versão nova")
            dispensar
        case .installing:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Instalando")
        case .installedNeedsRestart:
            Button("Encerrar o Mo baile", action: actions.quit)
                .buttonStyle(.borderedProminent)
        case .failed:
            Button("Baixar", action: actions.manualDownload)
                .help("Baixa o zip da versão nova pelo navegador, para trocar à mão")
            Button("Tentar de Novo", action: actions.retry)
                .buttonStyle(.borderedProminent)
            dispensar
        }
    }

    private var dispensar: some View {
        Menu {
            Button("Lembrar Amanhã", action: actions.snooze)
            Button("Ignorar Esta Versão", action: actions.ignore)
        } label: {
            Image(systemName: "xmark")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Lembrar depois ou ignorar esta versão")
        .accessibilityLabel("Dispensar aviso de versão")
    }
}

#Preview("Versão nova") {
    UpdateBannerView(
        release: ReleaseInfo(tagName: "v3.26.0", htmlURL: URL(string: "https://example.test/r")!),
        installed: "3.25.0"
    )
    .environment(ThemeManager(preview: PraiaLightTheme()))
    .frame(width: DesignMetrics.Window.minSize.width - DesignMetrics.Widths.sidebarIdeal)
}

#Preview("Baixando") {
    UpdateBannerView(
        release: ReleaseInfo(tagName: "v3.26.0", htmlURL: URL(string: "https://example.test/r")!),
        installed: "3.25.0", phase: .downloading(0.42)
    )
    .environment(ThemeManager(preview: PraiaLightTheme()))
    .frame(width: DesignMetrics.Window.minSize.width - DesignMetrics.Widths.sidebarIdeal)
}

#Preview("Pronta") {
    UpdateBannerView(
        release: ReleaseInfo(tagName: "v3.26.0", htmlURL: URL(string: "https://example.test/r")!),
        installed: "3.25.0", phase: .ready
    )
    .environment(ThemeManager(preview: PraiaLightTheme()))
    .frame(width: DesignMetrics.Window.minSize.width - DesignMetrics.Widths.sidebarIdeal)
}

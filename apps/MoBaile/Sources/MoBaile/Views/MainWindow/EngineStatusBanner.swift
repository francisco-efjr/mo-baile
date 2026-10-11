import SwiftUI

/// Faixa global "Motor parado", no topo da coluna central (FLU-2).
///
/// Antes, quando o motor caía e a supervisão desistia, ou quando ele nem
/// subia (Python sem as dependências), a única pista era a barra de status, e
/// o texto mandava fechar e abrir o app. A faixa diz o que houve e oferece o
/// reinício ali mesmo. Quem decide o estado é a `EngineSession`; a faixa só
/// desenha `engineStatus` e chama `restartEngine()`.
///
/// Esta é a versão montada: lê a sessão do ambiente. O desenho fica em
/// `EngineStatusBannerView`, que recebe o estado e a ação por parâmetro e é o
/// que os previews e a documentação usam (`docs/design/componentes/engine-status-banner.md`).
struct EngineStatusBanner: View {
    @Environment(EngineSession.self) private var session

    var body: some View {
        EngineStatusBannerView(status: session.engineStatus) {
            Task { await session.restartEngine() }
        }
    }

    /// Texto e estilo de cada estado que merece faixa.
    struct Conteudo: Equatable {
        /// Variante visual da faixa. Fechada: um estado novo do motor que
        /// mereça faixa entra aqui, com fundo e símbolo próprios.
        enum Tom: Equatable {
            /// A supervisão está subindo outro motor: progresso, sem botão.
            case reiniciando
            /// Ninguém vai tentar de novo sozinho: mensagem e Reiniciar Motor.
            case parado
        }

        /// Primeira linha, em negrito.
        let titulo: String
        /// O motivo, como veio do motor ou do `EngineLocator`.
        let mensagem: String
        /// Variante visual.
        let tom: Tom

        /// Atalho de leitura para quem só precisa saber se há botão.
        var reiniciando: Bool { tom == .reiniciando }

        /// `nil` quando o estado não merece faixa (conectado ou primeira subida,
        /// que o splash cobre).
        init?(_ status: EngineStatus) {
            switch status {
            case .starting, .running:
                return nil
            case .restarting(let mensagem):
                titulo = "O motor caiu. Reiniciando…"
                self.mensagem = mensagem
                tom = .reiniciando
            case .stopped(let mensagem):
                titulo = "O motor está parado"
                self.mensagem = mensagem
                tom = .parado
            }
        }

        /// O que o VoiceOver ouve quando a faixa aparece.
        var anuncio: String { "\(titulo) \(mensagem)" }
    }
}

/// Desenho da faixa do motor, sem depender da `EngineSession`.
///
/// Em `.running` e `.starting` não desenha nada. A entrada desliza do topo e
/// esmaece; com Reduzir movimento, só esmaece.
struct EngineStatusBannerView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Estado do motor a desenhar. Só `.restarting` e `.stopped` mostram faixa.
    let status: EngineStatus
    /// Chamado pelo botão Reiniciar Motor (só no tom parado).
    let onRestart: () -> Void

    /// - Parameters:
    ///   - status: estado do motor, normalmente `EngineSession.engineStatus`.
    ///   - onRestart: ação do botão Reiniciar Motor.
    init(status: EngineStatus, onRestart: @escaping () -> Void) {
        self.status = status
        self.onRestart = onRestart
    }

    var body: some View {
        Group {
            if let conteudo = EngineStatusBanner.Conteudo(status) {
                faixa(conteudo)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.smooth(reduceMotion: reduceMotion), value: status)
        .onChange(of: status) { _, novo in
            // O VoiceOver não percebe uma view que aparece fora do foco; o
            // anúncio diz o que mudou sem tirar a pessoa de onde ela está.
            if let conteudo = EngineStatusBanner.Conteudo(novo) {
                AccessibilityNotification.Announcement(conteudo.anuncio).post()
            }
        }
    }

    private func faixa(_ conteudo: EngineStatusBanner.Conteudo) -> some View {
        let theme = themeManager.current
        return HStack(alignment: .center, spacing: DesignMetrics.EngineBanner.gap) {
            Group {
                switch conteudo.tom {
                case .reiniciando:
                    ProgressView().controlSize(.small)
                case .parado:
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(DSFont.Symbol.banner)
                        .foregroundStyle(theme.destructive)
                }
            }
            .frame(width: DesignMetrics.EngineBanner.iconWidth)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text(conteudo.titulo)
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                Text(conteudo.mensagem)
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if conteudo.tom == .parado {
                Button("Reiniciar Motor", action: onRestart)
                    .buttonStyle(.borderedProminent)
                    .help("Sobe o motor de novo, sem fechar o Mo baile")
            }
        }
        .padding(.horizontal, DesignMetrics.Spacing.s6)
        .padding(.vertical, DesignMetrics.EngineBanner.verticalPadding)
        .background(conteudo.tom == .reiniciando ? theme.warningTint : theme.dangerTint)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Estado do motor")
    }
}

// MARK: - Previews

#Preview("Parado: motor caiu de vez") {
    EngineStatusBannerView(
        status: .stopped("O motor caiu e não voltou depois de 3 tentativas de reinício. "
            + "O motor encerrou inesperadamente (codigo 1). Use Reiniciar Motor para tentar de novo."),
        onRestart: {}
    )
    .environment(ThemeManager(preview: PraiaLightTheme()))
    .frame(width: DesignMetrics.Window.minSize.width - DesignMetrics.Widths.sidebarIdeal)
}

#Preview("Reiniciando") {
    EngineStatusBannerView(
        status: .restarting("O motor encerrou inesperadamente (codigo 1). Reiniciando o motor (tentativa 2 de 3)…"),
        onRestart: {}
    )
    .environment(ThemeManager(preview: PraiaLightTheme()))
    .frame(width: DesignMetrics.Window.minSize.width - DesignMetrics.Widths.sidebarIdeal)
}

#Preview("Python inadequado (escuro)") {
    EngineStatusBannerView(
        status: .stopped(EngineLocator.unsuitableMessage(found: [
            "/usr/bin/python3 (Python 3.9.6, antigo demais)",
            "/opt/homebrew/bin/python3 (Python 3.12.4, sem Pillow)",
        ])),
        onRestart: {}
    )
    .environment(ThemeManager(preview: PraiaDarkTheme()))
    .frame(width: DesignMetrics.Window.minSize.width - DesignMetrics.Widths.sidebarIdeal)
}

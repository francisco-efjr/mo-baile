import SwiftUI

/// Faixa global "Motor parado", no topo da coluna central (FLU-2).
///
/// Antes, quando o motor caía e a supervisão desistia, ou quando ele nem
/// subia (Python sem as dependências), a única pista era a barra de status, e
/// o texto mandava fechar e abrir o app. A faixa diz o que houve e oferece o
/// reinício ali mesmo. Quem decide o estado é a `EngineSession`; a faixa só
/// desenha `engineStatus` e chama `restartEngine()`.
struct EngineStatusBanner: View {
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let status = session.engineStatus
        Group {
            if let conteudo = Conteudo(status) {
                faixa(conteudo)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.smooth(), value: status)
        .onChange(of: status) { _, novo in
            // O VoiceOver não percebe uma view que aparece fora do foco; o
            // anúncio diz o que mudou sem tirar a pessoa de onde ela está.
            if let conteudo = Conteudo(novo) {
                AccessibilityNotification.Announcement(conteudo.anuncio).post()
            }
        }
    }

    /// Texto e estilo de cada estado que merece faixa.
    struct Conteudo: Equatable {
        let titulo: String
        let mensagem: String
        let reiniciando: Bool

        init?(_ status: EngineStatus) {
            switch status {
            case .starting, .running:
                return nil
            case .restarting(let mensagem):
                titulo = "O motor caiu. Reiniciando…"
                self.mensagem = mensagem
                reiniciando = true
            case .stopped(let mensagem):
                titulo = "O motor está parado"
                self.mensagem = mensagem
                reiniciando = false
            }
        }

        var anuncio: String { "\(titulo) \(mensagem)" }
    }

    private func faixa(_ conteudo: Conteudo) -> some View {
        let theme = themeManager.current
        return HStack(alignment: .center, spacing: 10) {
            Group {
                if conteudo.reiniciando {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.destructive)
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
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

            if !conteudo.reiniciando {
                Button("Reiniciar Motor") {
                    Task { await session.restartEngine() }
                }
                .buttonStyle(.borderedProminent)
                .help("Sobe o motor de novo, sem fechar o Mo baile")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(conteudo.reiniciando ? theme.warningTint : theme.dangerTint)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Estado do motor")
    }
}

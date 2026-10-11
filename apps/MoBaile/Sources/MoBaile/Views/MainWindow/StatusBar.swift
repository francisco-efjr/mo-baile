import SwiftUI

/// Barra de status de 22 pt, embaixo da coluna central.
///
/// Os rotulos traziam a porta do proxy e a do WDA escritas no codigo. Se a
/// configuracao do motor apontasse para outra porta, a barra mentiria com toda
/// a confianca. Os numeros vem do proprio motor, e o estado de cada servico
/// aparece por icone e texto, nao so por cor.
struct StatusBar: View {
    @Environment(AppState.self) var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) var themeManager

    var theme: any ThemeTokens { themeManager.current }

    /// Porta que o motor informa; sem motor, o rótulo fica sem número em vez
    /// de afirmar uma porta escrita no código.
    private var portas: StatusBar.Portas {
        let wda = session.engineInfo.flatMap { URL(string: $0.wdaUrl)?.port }
        return Portas(wda: wda, proxy: session.engineInfo?.proxy.port)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Os serviços cedem espaço em vez de impor largura: com tudo em
            // `fixedSize`, a barra sozinha exigia 690 pt, e esse mínimo
            // impedia a janela de encolher numa tela de MacBook.
            ViewThatFits(in: .horizontal) {
                servicos(compacto: false)
                servicos(compacto: true)
            }
            .layoutPriority(1)

            Text(appState.statusMessage)
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
                .help(appState.statusMessage)

            if appState.isDeviceConnected {
                ViewThatFits(in: .horizontal) {
                    metricasView(metricas)
                    metricasView(metricasCurtas)
                    Color.clear.frame(width: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: DesignMetrics.Heights.statusBar)
        .background(theme.bgContentAlt)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    /// Serviço que a barra mostra. O WDA só serve ao iOS e o ADB só ao
    /// Android; o da outra plataforma vai para o tooltip da barra (D4).
    enum Servico: CaseIterable {
        case wda, adb, proxy, fa

        static func visiveis(_ plataforma: Platform) -> [Servico] {
            plataforma == .ios ? [.wda, .proxy, .fa] : [.adb, .proxy, .fa]
        }

        /// Rótulo curto da barra. A sigla fica para quem já conhece; o resto
        /// vai em `nome` e `explicacao` (UX-4).
        func rotulo(_ portas: Portas) -> String {
            switch self {
            case .wda: return portas.wda.map { "WDA \($0)" } ?? "WDA"
            case .adb: return "ADB"
            case .proxy: return portas.proxy.map { "Proxy \($0)" } ?? "Proxy"
            case .fa: return "Analytics"
            }
        }

        /// Nome por extenso, lido pelo VoiceOver.
        func nome(_ portas: Portas) -> String {
            switch self {
            case .wda: return "WebDriverAgent" + (portas.wda.map { ", porta \($0)" } ?? "")
            case .adb: return "Android Debug Bridge (ADB)"
            case .proxy: return "Proxy de rede" + (portas.proxy.map { ", porta \($0)" } ?? "")
            case .fa: return "Escuta do Firebase Analytics"
            }
        }

        /// O que o serviço faz, em linguagem natural.
        var explicacao: String {
            switch self {
            case .wda: return "Deixa o Mo baile tocar na tela do iPhone e ler os elementos dela."
            case .adb: return "Liga o Mac ao aparelho Android para espelhar, tocar e ler a tela."
            case .proxy: return "Intercepta o tráfego HTTP e HTTPS do aparelho para a área Rede HTTP."
            case .fa: return "Lê os eventos de tagueamento que o app envia para a área Analytics."
            }
        }
    }

    struct Portas: Equatable {
        var wda: Int?
        var proxy: Int?
    }

    /// Menor tamanho de texto da barra (UX-4).
    static let metricsFontSize: CGFloat = 11

    /// Métricas do espelho: o texto curto da barra e a frase por extenso.
    struct Metricas: Equatable {
        var x: Int, y: Int, fps: Int, estavelMs: Int, latenciaMs: Int

        var completa: String { "x \(x) · y \(y)  \(fps) fps  estável em \(estavelMs) ms  latência \(latenciaMs) ms" }
        var curta: String { "\(fps) fps  \(latenciaMs) ms" }

        /// O que o VoiceOver lê e o tooltip mostra, sem abreviação.
        var porExtenso: String {
            "Ponteiro em x \(x), y \(y) na tela do aparelho. \(fps) quadros por segundo no espelho. "
                + "A tela levou \(estavelMs) milissegundos para parar de mudar. "
                + "O aparelho responde em \(latenciaMs) milissegundos."
        }
    }

    private func estado(_ servico: Servico) -> DaemonState {
        switch servico {
        case .wda: return appState.daemonStatus.wda
        case .adb: return appState.daemonStatus.adb
        case .proxy: return appState.daemonStatus.proxy
        case .fa: return appState.daemonStatus.fa
        }
    }

    private func rotulo(_ servico: Servico) -> String { servico.rotulo(portas) }

    /// Os serviços da plataforma ativa; no modo compacto, só o ícone (o nome vai
    /// no tooltip e no leitor de tela).
    private func servicos(compacto: Bool) -> some View {
        let visiveis = Servico.visiveis(appState.platform)
        let ocultos = Servico.allCases.filter { !visiveis.contains($0) }
        return HStack(spacing: compacto ? 8 : 12) {
            ForEach(visiveis, id: \.self) { servico($0, compacto) }
        }
        .help(ocultos.map { "\($0.nome(portas)): \(StatusIndicator.word(estado($0)))" }.joined(separator: "\n"))
    }

    @ViewBuilder
    private func servico(_ servico: Servico, _ compacto: Bool) -> some View {
        let estado = estado(servico)
        let nome = servico.nome(portas)
        if compacto {
            Image(systemName: StatusIndicator.symbol(estado))
                .font(.system(size: Self.metricsFontSize, weight: .semibold))
                .foregroundStyle(cor(estado))
                .help("\(nome): \(StatusIndicator.word(estado)). \(servico.explicacao)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nome)
                .accessibilityValue(StatusIndicator.word(estado))
                .accessibilityHint(servico.explicacao)
        } else {
            StatusIndicator(status: estado, label: rotulo(servico), detail: servico.explicacao, spokenName: nome)
        }
    }

    private func cor(_ estado: DaemonState) -> Color {
        switch estado {
        case .ok: return theme.success
        case .busy: return theme.info
        case .warn: return theme.warning
        case .error: return theme.destructive
        case .off: return theme.labelTertiary
        }
    }

    private func metricasView(_ texto: String) -> some View {
        Text(texto)
            .font(DSFont.mono(Self.metricsFontSize).monospacedDigit())
            .foregroundStyle(theme.labelSecondary)
            .lineLimit(1)
            .fixedSize()
            .help(metricasAtuais.porExtenso)
            .accessibilityLabel("Métricas do espelho")
            .accessibilityValue(metricasAtuais.porExtenso)
    }

    private var metricasAtuais: Metricas {
        Metricas(
            x: Int(appState.cursorPosition.x), y: Int(appState.cursorPosition.y),
            fps: appState.fps, estavelMs: appState.settleMs, latenciaMs: appState.latencyMs
        )
    }

    private var metricasCurtas: String { metricasAtuais.curta }

    private var metricas: String { metricasAtuais.completa }
}

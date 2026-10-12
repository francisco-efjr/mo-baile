import SwiftUI
import AppKit
import Observation

/// Andamento mostrado no splash: a frase da fase e a barra.
@MainActor
@Observable
final class SplashProgress {
    var message: String
    var fraction: Double

    init(message: String = "Iniciando o motor…", fraction: Double = 0) {
        self.message = message
        self.fraction = fraction
    }
}

/// Quando o splash sai e quanto a barra anda, sem relógio nem janela: regra
/// pura, testada em `SplashTimingTests`.
///
/// O splash saía em 1,5 s fixos, antes de o motor terminar de subir: a janela
/// aparecia com "Procurando…", os indicadores mudavam na frente da pessoa e o
/// primeiro clique às vezes caía antes de o motor responder. Agora ele fica até
/// o app estar pronto, com um mínimo (não pisca) e um teto (nunca prende).
enum SplashTiming {
    /// Tempo mínimo na tela, mesmo que tudo fique pronto antes.
    static let minimum: TimeInterval = 2.5
    /// Teto: passado isso o splash sai, pronto ou não. A janela mostra o resto.
    static let maximum: TimeInterval = 12
    static let tick: TimeInterval = 0.1

    static func message(_ phase: LaunchPhase) -> String {
        switch phase {
        case .startingEngine: return "Iniciando o motor…"
        case .scanning: return "Procurando aparelhos e simuladores…"
        case .ready: return "Pronto"
        case .failed: return "Abrindo…"
        }
    }

    /// Até onde a barra pode ir em cada fase. Ela anda sozinha até esse teto e
    /// só completa quando a fase seguinte chega: barra cheia significa pronto.
    static func target(_ phase: LaunchPhase) -> Double {
        switch phase {
        case .startingEngine: return 0.45
        case .scanning: return 0.88
        case .ready, .failed: return 1
        }
    }

    static func nextFraction(current: Double, phase: LaunchPhase) -> Double {
        let passo = (phase == .ready || phase == .failed) ? 0.12 : 0.025
        return min(target(phase), current + passo)
    }

    static func shouldClose(elapsed: TimeInterval, phase: LaunchPhase, fraction: Double) -> Bool {
        if elapsed >= maximum { return true }
        guard elapsed >= minimum else { return false }
        switch phase {
        case .ready: return fraction >= 0.999
        case .failed: return true
        case .startingEngine, .scanning: return false
        }
    }
}

/// Splash de abertura: mascote, piscina e barra de progresso.
///
/// Aparece ao abrir o app enquanto o motor sobe e procura aparelhos, e pode ser
/// reaberto em Janela › Mostrar Splash (aí, por tempo fixo). É a única
/// ilustração da interface (além do ícone): o resto do app tem fundos lisos.
@MainActor
final class SplashController {
    static let shared = SplashController()
    private var window: NSWindow?
    private var timer: Timer?

    /// Mostra o splash. Com `phase`, acompanha a abertura do app; sem, fica
    /// `SplashTiming.minimum` e sai (Janela › Mostrar Splash).
    func show(phase: (@MainActor () -> LaunchPhase)? = nil) {
        timer?.invalidate()
        window?.close()
        let progress = SplashProgress()
        let size = NSSize(width: 640, height: 380)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SplashView(progress: progress))
        window.center()
        window.orderFrontRegardless()
        self.window = window

        let inicio = Date()
        let fase = phase ?? { .ready }
        timer = Timer.scheduledTimer(withTimeInterval: SplashTiming.tick, repeats: true) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.window === window else { return }
                let atual = fase()
                progress.message = SplashTiming.message(atual)
                progress.fraction = SplashTiming.nextFraction(current: progress.fraction, phase: atual)
                if SplashTiming.shouldClose(elapsed: Date().timeIntervalSince(inicio), phase: atual,
                                            fraction: progress.fraction) {
                    self.dismiss(window)
                }
            }
        }
    }

    private func dismiss(_ window: NSWindow) {
        timer?.invalidate()
        timer = nil
        NSAnimationContext.runAnimationGroup { contexto in
            contexto.duration = 0.24
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                window.close()
                if self.window === window { self.window = nil }
            }
        }
    }
}

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: SplashProgress

    @State private var visivel = false

    private static let navy = Color(hex: "#141543")

    var body: some View {
        ZStack {
            fundo
            HStack(spacing: 20) {
                if let mascote = NSImage(named: "mascot") {
                    Image(nsImage: mascote)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 260)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mo baile")
                        .font(.system(size: 48, weight: .bold))
                        .tracking(-1.4)
                        .foregroundStyle(Self.navy)
                    Text("ELEMENT RECORDER")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(Self.navy.opacity(0.75))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.55))
                            Capsule()
                                .fill(Color(hex: "#C2456E"))
                                .frame(width: geo.size.width * progress.fraction)
                                .animation(reduceMotion ? nil : .linear(duration: SplashTiming.tick), value: progress.fraction)
                        }
                    }
                    .frame(width: 190, height: 5)
                    .padding(.top, 16)
                    Text(progress.message)
                        .font(.system(size: 11))
                        .foregroundStyle(Self.navy.opacity(0.7))
                        .contentTransition(.opacity)
                        .padding(.top, 6)
                }
            }
        }
        .frame(width: 640, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.window, style: .continuous))
        .opacity(visivel ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mo baile. \(progress.message)")
        .onAppear {
            withAnimation(.linear(duration: 0.24)) { visivel = true }
        }
    }

    @ViewBuilder
    private var fundo: some View {
        if let imagem = NSImage(named: "splash_bg") {
            Image(nsImage: imagem)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Rodando fora do bundle (swift run), sem a imagem copiada: o
            // degradê azul-piscina do ícone.
            LinearGradient(
                colors: [Color(hex: "#BFE6F5"), Color(hex: "#9BDCF3"), Color(hex: "#86CDE8")],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

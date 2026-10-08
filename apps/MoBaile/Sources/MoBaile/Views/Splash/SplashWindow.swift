import SwiftUI
import AppKit

/// Splash de abertura: mascote, piscina e barra de progresso.
///
/// Aparece por 1,5 s ao abrir o app e pode ser reaberto em Janela › Mostrar
/// Splash. É a única ilustração da interface (além do ícone): o resto do app
/// tem fundos lisos.
@MainActor
final class SplashController {
    static let shared = SplashController()
    private var window: NSWindow?

    func show(duration: TimeInterval = 1.5) {
        window?.close()
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
        window.contentView = NSHostingView(rootView: SplashView(duration: duration))
        window.center()
        window.orderFrontRegardless()
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak window] in
            guard let window, self?.window === window else { return }
            NSAnimationContext.runAnimationGroup { contexto in
                contexto.duration = 0.24
                window.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    window.close()
                    if self?.window === window { self?.window = nil }
                }
            }
        }
    }
}

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duration: TimeInterval

    @State private var progresso: Double = 0
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
                                .frame(width: geo.size.width * progresso)
                        }
                    }
                    .frame(width: 190, height: 5)
                    .padding(.top, 16)
                    Text("Iniciando o motor…")
                        .font(.system(size: 11))
                        .foregroundStyle(Self.navy.opacity(0.7))
                        .padding(.top, 6)
                }
            }
        }
        .frame(width: 640, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.window, style: .continuous))
        .opacity(visivel ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mo baile. Iniciando o motor.")
        .onAppear {
            withAnimation(.linear(duration: 0.24)) { visivel = true }
            withAnimation(reduceMotion ? .linear(duration: 0.2) : .linear(duration: max(0.2, duration - 0.1))) {
                progresso = 1
            }
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

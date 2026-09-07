import AppKit
import SwiftUI

/// Espelho interativo do dispositivo.
///
/// Duas correcoes em relacao a versao anterior:
///
/// 1. **Projecao.** A conversao entre ponto do mouse e coordenada do aparelho
///    usava 1080x1920 fixo. Fora dessa proporcao, a caixa de selecao aparecia
///    deslocada, e o toque repassado caia no lugar errado. Agora a escala vem
///    de `appState.deviceSize`, lido do proprio dispositivo, e leva em conta a
///    letterbox de `scaledToFit`.
/// 2. **Clique.** Antes o clique so marcava o elemento na arvore. Repassar o
///    toque e gravar o passo, que sao o motivo de a ferramenta existir, nao
///    tinham caminho na interface nativa.
struct ScreenCanvas: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    @State private var hoveredElement: UIElement?
    @State private var clickLocation: CGPoint?
    @State private var clickPhase: CGFloat = 0
    @State private var clickOpacity: Double = 0
    @State private var isHovering = false

    var body: some View {
        let theme = themeManager.current

        GeometryReader { geometry in
            let projection = Projection(
                viewport: geometry.size,
                device: appState.deviceSize
            )

            ZStack {
                if let frame = appState.currentFrame {
                    Image(nsImage: frame)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // O espelho e conteudo decorativo repetido da arvore de
                        // acessibilidade, que ja e navegavel por leitor de tela.
                        .accessibilityHidden(true)
                }

                if let hovered = hoveredElement, isHovering {
                    let rect = projection.toView(hovered.bounds)

                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.accent.opacity(0.2), lineWidth: 4)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.accent, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .animation(.easeInOut(duration: 0.12), value: hovered.bounds)

                    Text(overlayLabel(for: hovered, rect: rect))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(theme.accentPressed)
                        .cornerRadius(4)
                        .position(x: rect.midX, y: max(10, rect.minY - 12))
                }

                if let location = clickLocation, clickOpacity > 0 {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .scaleEffect(clickPhase)
                        .opacity(clickOpacity)
                        .position(location)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                    hoveredElement = nil
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    appState.cursorPosition = projection.toDevice(location)
                    hoveredElement = element(at: location, projection: projection)
                case .ended:
                    hoveredElement = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { location in
                handleTap(at: location, projection: projection)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Espelho do dispositivo")
            .accessibilityValue(
                appState.currentFrame == nil
                    ? "Sem imagem"
                    : "\(appState.hierarchyElements.count) elementos na tela"
            )
        }
    }

    // MARK: - Interacao

    private func handleTap(at location: CGPoint, projection: Projection) {
        clickLocation = location
        clickPhase = 0.6
        clickOpacity = 1.0
        withAnimation(.easeOut(duration: 0.3)) {
            clickPhase = 1.0
            clickOpacity = 0.0
        }

        let target = element(at: location, projection: projection)
        hoveredElement = target
        appState.selectedElement = target

        let devicePoint = projection.toDevice(location)
        switch appState.interactionMode {
        case .inspect:
            Task { await session.selectElement(at: devicePoint) }
        case .forward:
            Task { await session.tap(at: devicePoint) }
        case .record:
            Task { await session.record(at: devicePoint) }
        }
    }

    private func element(at location: CGPoint, projection: Projection) -> UIElement? {
        // O menor elemento que contem o ponto e o mais especifico, que e o que
        // o usuario quer selecionar.
        var found: UIElement?
        var smallestArea = CGFloat.infinity
        for element in appState.hierarchyElements {
            let rect = projection.toView(element.bounds)
            guard rect.contains(location) else { continue }
            let area = rect.width * rect.height
            if area < smallestArea {
                smallestArea = area
                found = element
            }
        }
        return found
    }

    private func overlayLabel(for element: UIElement, rect: CGRect) -> String {
        let name = element.resourceId.isEmpty ? element.displayName : element.resourceId
        return "\(name) · \(Int(rect.width))x\(Int(rect.height)) pt"
    }
}

/// Conversao entre coordenada da tela do Mac e coordenada do aparelho.
///
/// `scaledToFit` centraliza a imagem e deixa faixa vazia num dos eixos. Ignorar
/// essa faixa foi a causa do desalinhamento anterior: o clique no topo da
/// janela virava um toque acima do topo da tela do aparelho.
struct Projection {
    let scale: CGFloat
    let offset: CGPoint
    let deviceSize: CGSize

    init(viewport: CGSize, device: CGSize) {
        let safeDevice = CGSize(
            width: max(device.width, 1),
            height: max(device.height, 1)
        )
        let scale = min(viewport.width / safeDevice.width, viewport.height / safeDevice.height)
        self.scale = scale > 0 ? scale : 1
        self.deviceSize = safeDevice
        self.offset = CGPoint(
            x: (viewport.width - safeDevice.width * self.scale) / 2,
            y: (viewport.height - safeDevice.height * self.scale) / 2
        )
    }

    func toView(_ rect: CGRect) -> CGRect {
        CGRect(
            x: offset.x + rect.minX * scale,
            y: offset.y + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    func toDevice(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: ((point.x - offset.x) / scale).clamped(to: 0...deviceSize.width),
            y: ((point.y - offset.y) / scale).clamped(to: 0...deviceSize.height)
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

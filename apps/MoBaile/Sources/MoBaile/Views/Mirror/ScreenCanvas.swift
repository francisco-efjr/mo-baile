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
                } else if appState.isDeviceConnected {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    Text("sem sinal")
                        .font(DSFont.mono(11))
                        .foregroundStyle(theme.labelSecondary)
                        .accessibilityHidden(true)
                }

                // Sob o cursor, o elemento apontado; fora dele, o escolhido na
                // árvore, para a árvore e o espelho contarem a mesma história.
                if appState.currentFrame != nil,
                   let alvo = (isHovering ? hoveredElement : nil) ?? appState.selectedElement {
                    let rect = projection.toView(alvo.bounds)

                    // Borda de 2 pt no destaque e um anel de 4 pt na tinta.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.accent, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(theme.accentTint, lineWidth: 4)
                                .padding(-3)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .animation(.easeOut(duration: 0.12), value: alvo.bounds)
                        .allowsHitTesting(false)

                    Text(overlayLabel(for: alvo, rect: rect))
                        .font(DSFont.mono(9.5))
                        .foregroundColor(theme.onAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .position(x: rect.midX, y: max(10, rect.minY - 10))
                        .allowsHitTesting(false)
                }

                if let location = clickLocation, clickOpacity > 0 {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1).padding(-1))
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
            // Sem papel, o leitor anunciava o espelho como elemento
            // desconhecido, e nada dizia o que um clique ali faria.
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Espelho do dispositivo")
            .accessibilityValue(
                appState.currentFrame == nil
                    ? "Sem imagem"
                    : "\(appState.hierarchyElements.count) elementos na tela. Clique: \(appState.interactionMode.displayName)"
            )
        }
    }

    // MARK: - Interacao

    private func handleTap(at location: CGPoint, projection: Projection) {
        clickLocation = location
        clickPhase = 0.6
        clickOpacity = 1.0
        withAnimation(.easeOut(duration: 0.3)) {
            clickPhase = 1.6
            clickOpacity = 0.0
        }

        let target = element(at: location, projection: projection)
        hoveredElement = target
        appState.selectedElement = target

        let devicePoint = projection.toDevice(location)
        switch appState.interactionMode {
        case .forward:
            Task { await session.tap(at: devicePoint) }
        case .record:
            // Gravar tambem toca no aparelho: gravar um fluxo exige navegar
            // por ele, e alternar de modo a cada passo tornava a gravacao
            // inviavel na pratica.
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

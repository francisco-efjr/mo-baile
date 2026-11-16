import AppKit
import SwiftUI

/// Tabela em cima, detalhe embaixo, com divisória arrastável.
///
/// Substitui o `VSplitView`: dentro da NavigationSplitView o NSSplitView mede o
/// conteúdo pela largura ideal e não informa esse mínimo ao SwiftUI. A janela
/// pedia até 160 pt a mais de largura no Relatório e, em Rede e Analytics,
/// deixava o workspace mais largo que a coluna: o espelho ia parar embaixo da
/// barra lateral e o inspector saía pela borda (D1).
///
/// A altura de cima é a que a pessoa arrastou, guardada por cena; sem folga,
/// ela cede até o mínimo antes de a janela crescer.
struct VerticalSplit<Top: View, Bottom: View>: View {
    private let limites: ClosedRange<CGFloat>
    private let minimoDeBaixo: CGFloat
    private let top: Top
    private let bottom: Bottom
    @SceneStorage private var altura: Double

    init(
        storageKey: String,
        topHeight: ClosedRange<CGFloat>,
        idealTopHeight: CGFloat,
        minBottomHeight: CGFloat,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.limites = topHeight
        self.minimoDeBaixo = minBottomHeight
        self.top = top()
        self.bottom = bottom()
        _altura = SceneStorage(wrappedValue: Double(idealTopHeight), storageKey)
    }

    var body: some View {
        let atual = CGFloat(altura).clamped(to: limites)
        VStack(spacing: 0) {
            top
                .frame(minHeight: limites.lowerBound, idealHeight: atual, maxHeight: atual)
            RowDivider(altura: atual, limites: limites) { altura = $0 }
            bottom
                .frame(minHeight: minimoDeBaixo, maxHeight: .infinity)
        }
    }
}

/// Divisória horizontal: linha de 1 pt com área de toque de 7 pt e o cursor de
/// redimensionar, como a do NSSplitView.
private struct RowDivider: View {
    @Environment(ThemeManager.self) private var themeManager
    let altura: CGFloat
    let limites: ClosedRange<CGFloat>
    let mudou: (Double) -> Void

    @State private var inicio: CGFloat?
    @State private var cursor = PaneDividerCursor(push: { NSCursor.resizeUpDown.push() })

    var body: some View {
        Rectangle()
            .fill(themeManager.current.separator)
            .frame(height: 1)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .padding(.vertical, -3)
            .onHover { dentro in
                if dentro { cursor.enter() } else { cursor.leave() }
            }
            .onDisappear { cursor.leave() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { arraste in
                        let base = inicio ?? altura
                        if inicio == nil { inicio = altura }
                        mudou(Double((base + arraste.translation.height).clamped(to: limites)))
                    }
                    .onEnded { _ in inicio = nil }
            )
            .accessibilityHidden(true)
    }
}

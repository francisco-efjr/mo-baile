import SwiftUI

/// Liquid Glass do design system (ADR 0006).
///
/// No macOS 26 o vidro é o do sistema (`glassEffect`), que refrata o que está
/// atrás e reage sozinho a Aumentar contraste e Reduzir movimento. No macOS 14
/// e 15 o mesmo papel cai no material ou no preenchimento que o app já usava.
/// Com Reduzir transparência, todo vidro próprio vira superfície opaca do tema,
/// como em `tokens/materials.css`.
///
/// Vidro só na camada de navegação e em controles que flutuam sobre o
/// conteúdo. Toolbar, barra lateral, popovers, sheets e menus já recebem o
/// vidro do sistema: nada aqui pinta por cima deles, e nada aqui vai dentro
/// deles (vidro sobre vidro). Este arquivo e a toolbar são os únicos lugares
/// com `#available(macOS 26`; as telas pedem um papel.
enum GlassRole: CaseIterable {
    /// Painel solto sobre a janela: paleta de comandos.
    case flutuante
    /// Controle em cápsula sobre conteúdo liso: cápsula do Ambiente na Início.
    case capsula
    /// Sobre imagem ou gradiente (splash): vidro transparente, que deixa a
    /// imagem aparecer.
    case midia
}

/// O que desenhar, decidido fora do SwiftUI para dar para testar.
enum GlassSurface: Equatable {
    /// Vidro do sistema. `clear` é a variante transparente, só sobre mídia.
    case glass(clear: Bool, interactive: Bool)
    /// macOS 14 e 15: material translúcido do sistema.
    case material
    /// macOS 14 e 15: preenchimento do tema, como antes do vidro.
    case fill
    /// Reduzir transparência: superfície opaca.
    case solid

    static func resolve(_ role: GlassRole, glassAvailable: Bool, reduceTransparency: Bool,
                        interactive: Bool = false) -> GlassSurface {
        if reduceTransparency { return .solid }
        if glassAvailable { return .glass(clear: role == .midia, interactive: interactive) }
        return role == .flutuante ? .material : .fill
    }

    /// O vidro do sistema já tem borda e sombra; o material antigo não.
    var drawsOwnEdge: Bool { self == .material || self == .solid }
}

enum GlassSupport {
    /// Liquid Glass existe neste Mac. `MOBAILE_SEM_VIDRO=1` força o caminho do
    /// macOS 14 e 15 no que é do app; aproxima o recuo, mas o vidro do sistema
    /// (toolbar, barra lateral) continua. `getenv`, e não `ProcessInfo`, porque
    /// é lido a cada `body` e não deve alocar.
    static var available: Bool {
        if let valor = getenv("MOBAILE_SEM_VIDRO"), String(cString: valor) == "1" { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

extension View {
    /// Fundo de vidro no papel pedido, recortado em `shape`. Aplique depois do
    /// `padding` e do `frame`: o vidro toma a forma do que já está medido.
    /// `highlighted` é o hover de quem não tem vidro interativo (macOS 14 e 15,
    /// Reduzir transparência); sobre o vidro, um véu do tema.
    func mbGlass(_ role: GlassRole, in shape: some InsettableShape, interactive: Bool = false,
                 highlighted: Bool = false) -> some View {
        modifier(GlassBackground(role: role, shape: shape, interactive: interactive, highlighted: highlighted))
    }

    /// Botão primário tingido com o destaque da paleta: vidro tingido no macOS
    /// 26, cápsula preenchida antes. Estilo próprio, e não `.glassProminent` ou
    /// `.borderedProminent`: os dois desenham o rótulo branco e ignoram o
    /// `foregroundStyle`, e o dourado da Costes pede rótulo escuro (`onAccent`).
    /// Desabilitado ou com a janela inativa, a cápsula perde o tom e o rótulo
    /// volta ao primário, para o botão não sumir no tema claro (D2).
    func mbProminentGlassButton(_ ativo: Bool = true) -> some View {
        modifier(ProminentGlassButton(tingido: ativo))
    }

    /// Barra presa à base de uma área que rola (rodapé da barra lateral). No
    /// macOS 26 é `safeAreaBar`: o conteúdo passa por baixo e o sistema aplica
    /// o efeito de borda de rolagem, sem vidro próprio. Antes, `safeAreaInset`.
    func mbBottomBar(@ViewBuilder _ barra: () -> some View) -> some View {
        modifier(BottomBar(barra: barra()))
    }

    /// Transição do vidro ao entrar e sair: o vidro se forma do nada
    /// (`materialize`). Com Reduzir movimento, só aparece.
    func mbGlassTransition() -> some View {
        modifier(GlassTransition())
    }
}

private struct GlassBackground<S: InsettableShape>: ViewModifier {
    /// Opcional: o splash abre antes da janela e não tem tema no ambiente.
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let role: GlassRole
    let shape: S
    let interactive: Bool
    let highlighted: Bool

    func body(content: Content) -> some View {
        let theme = themeManager?.current ?? PraiaLightTheme()
        let surface = GlassSurface.resolve(role, glassAvailable: GlassSupport.available,
                                           reduceTransparency: reduceTransparency, interactive: interactive)
        glass(content.background(highlighted && surface != .fill ? theme.fillSecondary : .clear, in: shape),
              surface, theme)
            .overlay {
                // Aumentar contraste já põe borda no vidro do sistema; o
                // material e o sólido ganham a borda do tema, e o
                // preenchimento também, para o controle ter limite visível.
                if surface.drawsOwnEdge || (surface == .fill && theme.highContrast) {
                    shape.strokeBorder(theme.highContrast ? theme.controlBorder : theme.separatorStrong,
                                       lineWidth: theme.highContrast ? 1 : DesignMetrics.hairline / 2)
                }
            }
    }

    @ViewBuilder
    private func glass(_ content: some View, _ surface: GlassSurface, _ theme: any ThemeTokens) -> some View {
        switch surface {
        case let .glass(clear, interactive):
            if #available(macOS 26.0, *) {
                content.glassEffect((clear ? Glass.clear : Glass.regular).tint(tint(theme)).interactive(interactive),
                                    in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        case .material:
            content
                .background(.regularMaterial, in: shape)
                .shadow(color: theme.floatingShadow, radius: DesignMetrics.Shadow.floatingRadius,
                        y: DesignMetrics.Shadow.floatingY)
        case .fill:
            content.background(role == .midia ? Color.white.opacity(0.55)
                               : (highlighted ? theme.fillPrimary : theme.fillSecondary), in: shape)
        case .solid:
            content.background(solid(theme), in: shape)
        }
    }

    /// Vidro sobre fundo liso não tem o que refratar e some, sobretudo no
    /// escuro. A cápsula leva o preenchimento do tema como tom, para continuar
    /// parecendo controle; o trilho do splash, um véu branco. Tom de cor
    /// (destaque) é só do botão primário.
    private func tint(_ theme: any ThemeTokens) -> Color? {
        switch role {
        case .flutuante: return nil
        case .capsula: return theme.fillPrimary
        case .midia: return Color.white.opacity(0.3)
        }
    }

    private func solid(_ theme: any ThemeTokens) -> Color {
        switch role {
        case .flutuante: return theme.bgContentAlt
        case .capsula: return theme.bgControl
        case .midia: return .white
        }
    }
}

private struct ProminentGlassButton: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    let tingido: Bool

    func body(content: Content) -> some View {
        content.buttonStyle(ProminentGlassButtonStyle(theme: themeManager.current, tingido: tingido))
    }
}

struct ProminentGlassButtonStyle: ButtonStyle {
    let theme: any ThemeTokens
    let tingido: Bool

    func makeBody(configuration: Configuration) -> some View {
        ProminentBody(configuration: configuration, theme: theme, tingido: tingido)
    }

    private struct ProminentBody: View {
        let configuration: ButtonStyleConfiguration
        let theme: any ThemeTokens
        let tingido: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        var body: some View {
            let rotulo = configuration.label
                .foregroundStyle(tingido ? theme.onAccent : theme.labelPrimary)
                .opacity(isEnabled ? 1 : 0.38)
                .padding(.horizontal, DesignMetrics.Spacing.s5)
                .frame(minWidth: DesignMetrics.Heights.controlLarge + 4, minHeight: DesignMetrics.Heights.controlLarge + 4)
                .contentShape(Capsule())
            if GlassSupport.available, !reduceTransparency, #available(macOS 26.0, *) {
                // O vidro interativo já responde ao clique.
                rotulo.glassEffect(tingido ? Glass.regular.tint(theme.accent).interactive() : .regular.interactive(),
                                   in: Capsule())
            } else {
                rotulo
                    .background(tingido ? theme.accent : theme.bgControl, in: Capsule())
                    .overlay { Capsule().strokeBorder(tingido ? .clear : theme.controlBorder, lineWidth: DesignMetrics.hairline / 2) }
                    .opacity(configuration.isPressed ? 0.82 : 1)
            }
        }
    }
}

private struct GlassTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if GlassSupport.available, #available(macOS 26.0, *) {
            content.glassEffectTransition(reduceMotion ? .identity : .materialize)
        } else {
            content
        }
    }
}

private struct BottomBar<Barra: View>: ViewModifier {
    let barra: Barra

    func body(content: Content) -> some View {
        if GlassSupport.available, #available(macOS 26.0, *) {
            content.safeAreaBar(edge: .bottom, spacing: 0) { barra }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { barra }
        }
    }
}

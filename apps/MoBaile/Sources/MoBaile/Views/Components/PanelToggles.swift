import SwiftUI

/// Mostra e esconde as três colunas.
///
/// Substitui o `PanelToggleGroup`, que desenhava três glifos abstratos de
/// retângulo com barra em alvos de 26x22. Dois problemas: o alvo é menor que o
/// mínimo confortável do HIG, e o glifo não dizia qual coluna era qual — só se
/// descobria clicando e vendo o que sumia.
///
/// Aqui cada botão tem 32x28, ícone que nomeia a coluna e dica com o atalho.
public struct PanelToggles: View {
    @Environment(ThemeManager.self) private var themeManager

    @Binding var mirrorVisible: Bool
    @Binding var hierarchyVisible: Bool
    @Binding var workspaceVisible: Bool

    public init(
        mirrorVisible: Binding<Bool>,
        hierarchyVisible: Binding<Bool>,
        workspaceVisible: Binding<Bool>
    ) {
        self._mirrorVisible = mirrorVisible
        self._hierarchyVisible = hierarchyVisible
        self._workspaceVisible = workspaceVisible
    }

    public var body: some View {
        HStack(spacing: 2) {
            botao(icone: "iphone", nome: "Espelho", atalho: "⌥1", ligado: $mirrorVisible)
            botao(icone: "list.bullet.indent", nome: "Hierarquia", atalho: "⌥2", ligado: $hierarchyVisible)
            botao(icone: "curlybraces", nome: "Workspace", atalho: "⌥3", ligado: $workspaceVisible)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(themeManager.current.bgControlTrack)
        )
    }

    @ViewBuilder
    private func botao(icone: String, nome: String, atalho: String, ligado: Binding<Bool>) -> some View {
        let theme = themeManager.current
        Button {
            withAnimation(.easeOut(duration: 0.14)) { ligado.wrappedValue.toggle() }
        } label: {
            Image(systemName: icone)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ligado.wrappedValue ? theme.textPrimary : theme.textLabel)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ligado.wrappedValue ? theme.bgControl : Color.clear)
                )
                // Sem isto só o traço do ícone recebe o clique, e não a área
                // toda do botão — parte do que tornava o controle anterior
                // difícil de acertar.
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(nome) (\(atalho))")
        .accessibilityLabel(nome)
        .accessibilityValue(ligado.wrappedValue ? "visível" : "oculto")
    }
}

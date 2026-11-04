import SwiftUI

/// O que estava nos editores no último `codegen.save` que deu certo.
struct CodigoSalvo: Equatable {
    let acoes: String
    let locators: String
    let em: Date
    let caminho: String?
}

/// Textos do rodapé do editor (PO-4), testáveis sem view.
enum EditorStatus {
    /// "não salvo" ou "salvo às 14:32". `nil` sem código nos editores.
    static func salvamento(acoes: String, locators: String, salvo: CodigoSalvo?) -> (texto: String, sujo: Bool)? {
        guard !acoes.isEmpty || !locators.isEmpty else { return nil }
        guard let salvo, salvo.acoes == acoes, salvo.locators == locators else { return ("não salvo", true) }
        let hora = salvo.em.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return ("salvo às \(hora)", false)
    }

    static func interpretador(versao: String?) -> String {
        versao.map { "Python \($0)" } ?? "Python"
    }
}

/// Lado direito do rodapé, como a status bar do PyCharm: `linha:coluna`,
/// separador de linha, codificação, recuo, interpretador e estado salvo.
struct EditorStatusBar: View {
    @Environment(ThemeManager.self) private var themeManager
    let linha: Int
    let coluna: Int
    let python: String?
    let pythonPath: String?
    let salvamento: (texto: String, sujo: Bool)?
    let caminho: String?
    /// Coluna estreita: só posição e estado salvo.
    var compacto = false
    var separador = "LF"
    var codificacao = "UTF-8"

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 14) {
            item("\(linha):\(coluna)", falado: "Linha \(linha), coluna \(coluna)")
            if !compacto {
                item(separador, falado: "Separador de linha \(separador)")
                item(codificacao, falado: "Codificação \(codificacao)")
                item("4 espaços", falado: "Recuo de 4 espaços")
                item(EditorStatus.interpretador(versao: python), falado: "Interpretador \(EditorStatus.interpretador(versao: python))")
                    .help(pythonPath.map { "Python do motor: \($0)" } ?? "Python do motor")
            }
            if let salvamento {
                StatusIndicator(
                    status: salvamento.sujo ? .warn : .ok, label: salvamento.texto,
                    detail: salvamento.sujo ? "Salve com ⌘S" : caminho.map { "Gravado em \($0)" }
                )
            }
        }
        .font(DSFont.mono(11))
        .foregroundStyle(theme.labelSecondary)
        .lineLimit(1)
        .fixedSize()
    }

    private func item(_ texto: String, falado: String) -> some View {
        Text(texto).accessibilityLabel(falado)
    }
}

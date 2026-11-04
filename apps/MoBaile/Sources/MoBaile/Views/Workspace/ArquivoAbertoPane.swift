import SwiftUI

/// Arquivo da árvore Projeto aberto numa aba (PO-5). Guarda o que o motor leu
/// (separador, BOM, somente leitura) para gravar de volta do mesmo jeito.
struct ArquivoAberto: Identifiable, Equatable {
    var arquivo: EngineDTO.WorkspaceFile
    var texto: String
    var salvoEm: Date?

    var id: String { arquivo.path }
    var sujo: Bool { texto != arquivo.text }

    /// Para o rodapé: "não salvo", "salvo às hh:mm" ou nada.
    var salvamento: (texto: String, sujo: Bool)? {
        if sujo { return ("não salvo", true) }
        guard let salvoEm else { return nil }
        return EditorStatus.salvamento(
            acoes: texto, locators: "", salvo: CodigoSalvo(acoes: texto, locators: "", em: salvoEm, caminho: nil)
        )
    }
}

/// Editor de um arquivo aberto da árvore: cabeçalho com o caminho, cadeado
/// quando não é UTF-8 e Salvar (grava com o separador e o BOM originais).
struct ArquivoAbertoPane: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Binding var aberto: ArquivoAberto
    var onCursor: ((Int, Int) -> Void)?
    let aoSalvar: () -> Void

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if aberto.arquivo.readOnly {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(theme.labelTertiary)
                        .help("Somente leitura: o arquivo não é UTF-8")
                        .accessibilityLabel("Somente leitura")
                }
                Text(aberto.arquivo.path)
                    .font(DSFont.mono(11.5))
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(EditorText.rotuloDeLinhas(aberto.texto))
                    .font(DSFont.subheadline.monospacedDigit())
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityHidden(true)
                BarIconButton(icon: "square.and.arrow.down", label: "Salvar \(aberto.arquivo.path)") {
                    Task { await salvar() }
                }
                .disabled(aberto.arquivo.readOnly || !aberto.sujo)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: DesignMetrics.Heights.editorHeader)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }

            CodeEditorView(
                text: $aberto.texto,
                accessibilityLabel: "Arquivo \(aberto.arquivo.path)",
                python: aberto.arquivo.path.hasSuffix(".py"),
                editable: !aberto.arquivo.readOnly,
                onCursor: onCursor
            )
        }
    }

    private func salvar() async {
        do {
            let texto = aberto.texto
            _ = try await session.writeWorkspaceFile(aberto.arquivo, text: texto)
            aberto.arquivo = EngineDTO.WorkspaceFile(
                path: aberto.arquivo.path, text: texto, encoding: aberto.arquivo.encoding,
                lineSeparator: aberto.arquivo.lineSeparator, bom: aberto.arquivo.bom,
                readOnly: false, size: aberto.arquivo.size
            )
            aberto.salvoEm = Date()
            appState.statusMessage = "Salvo \(aberto.arquivo.path)"
            aoSalvar()
        } catch {
            appState.statusMessage = "Não deu para salvar: \(error.localizedDescription)"
        }
    }
}

/// Editor vazio como o do PyCharm: dicas de atalho, só com os atalhos que o
/// Mo baile tem (D-2). O atalho vem do registro de comandos, então a dica não
/// envelhece se um atalho mudar.
struct DicasDoEditorVazio: View {
    @Environment(ThemeManager.self) private var themeManager

    static let dicas: [(titulo: String, comando: CommandID)] = [
        ("Paleta de Comandos", .palette),
        ("Iniciar Espelho", .stream),
        ("Salvar Page Object", .save),
        ("Mostrar ou Ocultar Projeto", .projectTree),
    ]

    var body: some View {
        let theme = themeManager.current
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(Self.dicas, id: \.titulo) { dica in
                GridRow {
                    Text(dica.titulo).foregroundStyle(theme.labelSecondary)
                    Text(Self.atalho(dica.comando)).foregroundStyle(theme.accentText).font(DSFont.mono(12))
                }
                .accessibilityElement(children: .combine)
            }
            GridRow {
                Text("Abrir arquivo do Projeto").foregroundStyle(theme.labelSecondary)
                Text("↩ na árvore").foregroundStyle(theme.accentText).font(DSFont.mono(12))
            }
            .accessibilityElement(children: .combine)
        }
        .font(DSFont.callout)
        .frame(maxWidth: .infinity)
    }

    static func atalho(_ id: CommandID) -> String {
        CommandRegistry.command(id, in: CommandContext())?.shortcut?.display ?? "paleta ⇧⌘P"
    }
}

/// Divisória arrastável à direita do painel Projeto. A largura fica guardada
/// por cena (`@SceneStorage`), entre 160 e 360 pt.
struct DivisoriaDoProjeto: View {
    @Environment(ThemeManager.self) private var themeManager
    @Binding var largura: Double
    @State private var inicio: Double?

    var body: some View {
        Rectangle()
            .fill(themeManager.current.separator)
            .frame(width: 1)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onHover { dentro in if dentro { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { gesto in
                        let base = inicio ?? largura
                        inicio = base
                        largura = min(max(base + gesto.translation.width, 160), 360)
                    }
                    .onEnded { _ in inicio = nil }
            )
            .accessibilityHidden(true)
    }
}

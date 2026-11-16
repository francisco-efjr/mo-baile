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

/// O que fazer com as abas da árvore Projeto. Fica no `AppState` (R-01): a
/// aba Page Objects é recriada ao trocar de área, e as abas não podem sumir
/// com ela. Toda atualização depois de um `await` procura a aba pelo id, e não
/// pelo índice: ela pode ter sido fechada no meio (R-07).
extension AppState {
    func indiceDoArquivo(_ id: String) -> Int? { arquivosAbertos.firstIndex { $0.id == id } }

    /// Abre (ou traz para a frente) um arquivo lido pelo motor. Confere de
    /// novo depois do `await`: dois ↩ rápidos não abrem duas abas (R-08).
    @MainActor
    func abrirArquivo(_ caminho: String, sessao: EngineSession) async {
        if indiceDoArquivo(caminho) != nil { arquivoAtivo = caminho; return }
        do {
            let lido = try await sessao.readWorkspaceFile(caminho)
            if indiceDoArquivo(caminho) == nil {
                arquivosAbertos.append(ArquivoAberto(arquivo: lido, texto: lido.text))
            }
            arquivoAtivo = caminho
        } catch {
            statusMessage = "Não deu para abrir \(caminho): \(error.localizedDescription)"
        }
    }

    /// Grava a aba. Sem `sobrescrever`, manda o `mtime_ns` lido e, se outro
    /// editor gravou no meio, marca o conflito para a aba perguntar (R-04).
    @MainActor
    @discardableResult
    func salvarArquivo(_ id: String, sessao: EngineSession, sobrescrever: Bool = false) async -> Bool {
        guard let indice = indiceDoArquivo(id), !arquivosAbertos[indice].arquivo.readOnly else { return false }
        let arquivo = arquivosAbertos[indice].arquivo
        let texto = arquivosAbertos[indice].texto
        do {
            let gravado = try await sessao.writeWorkspaceFile(arquivo, text: texto, sobrescrever: sobrescrever)
            if let i = indiceDoArquivo(id) {
                arquivosAbertos[i].arquivo.text = texto
                arquivosAbertos[i].arquivo.mtimeNs = gravado.mtimeNs
                arquivosAbertos[i].salvoEm = Date()
            }
            if conflitoDeArquivo == id { conflitoDeArquivo = nil }
            statusMessage = "Salvo \(id)"
            return true
        } catch EngineError.engine(let codigo, _) where codigo == "file_changed" {
            conflitoDeArquivo = id
            statusMessage = "\(id) mudou no disco depois de aberto"
            return false
        } catch {
            statusMessage = "Não deu para salvar \(id): \(error.localizedDescription)"
            return false
        }
    }

    /// Relê do disco e descarta o que estava na aba (conflito: "Recarregar").
    @MainActor
    func recarregarArquivo(_ id: String, sessao: EngineSession) async {
        do {
            let lido = try await sessao.readWorkspaceFile(id)
            if let i = indiceDoArquivo(id) {
                arquivosAbertos[i] = ArquivoAberto(arquivo: lido, texto: lido.text)
            }
            if conflitoDeArquivo == id { conflitoDeArquivo = nil }
        } catch {
            statusMessage = "Não deu para recarregar \(id): \(error.localizedDescription)"
        }
    }

    func fecharArquivo(_ id: String) {
        arquivosAbertos.removeAll { $0.id == id }
        if arquivoAtivo == id { arquivoAtivo = arquivosAbertos.last?.id }
        if conflitoDeArquivo == id { conflitoDeArquivo = nil }
    }
}

/// Editor de um arquivo aberto da árvore: cabeçalho com o caminho, cadeado
/// quando não é UTF-8 e Salvar (grava com o separador e o BOM originais).
struct ArquivoAbertoPane: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Binding var aberto: ArquivoAberto
    var cursor: CursorDoEditor?

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
                    Task { await appState.salvarArquivo(aberto.id, sessao: session) }
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
                cursor: cursor
            )
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
    /// O cursor de redimensionar foi empilhado: sai se a divisória sumir com o
    /// mouse em cima (painel ocultado, coluna estreita), senão fica preso (R-13).
    @State private var empilhado = false

    var body: some View {
        Rectangle()
            .fill(themeManager.current.separator)
            .frame(width: 1)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onHover { dentro in
                if dentro, !empilhado { NSCursor.resizeLeftRight.push(); empilhado = true }
                if !dentro, empilhado { NSCursor.pop(); empilhado = false }
            }
            .onDisappear { if empilhado { NSCursor.pop(); empilhado = false } }
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

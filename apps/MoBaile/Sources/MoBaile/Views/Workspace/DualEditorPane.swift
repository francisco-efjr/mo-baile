import AppKit
import SwiftUI

struct DualEditorPane: View {
    @Environment(AppState.self) var appState
    @Environment(EngineSession.self) var session
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        @Bindable var state = appState
        
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left Editor
                VStack(spacing: 0) {
                    editorHeader(
                        title: "pages/\(chaveDoArquivo).py",
                        color: themeManager.current.fileTitleActions ?? Color.blue,
                        conteudo: appState.actionsCode
                    )
                    CodeEditorContainer(text: $state.actionsCode)
                }
                
                if appState.splitEditors {
                Divider().background(themeManager.current.border ?? Color.gray)
                
                // Right Editor
                VStack(spacing: 0) {
                    editorHeader(
                        title: "locators/\(chaveDoArquivo).py",
                        color: themeManager.current.fileTitleLocators ?? Color.orange,
                        conteudo: appState.locatorsCode
                    )
                    CodeEditorContainer(text: $state.locatorsCode)
                }
                }
            }
            
            Divider().background(themeManager.current.border ?? Color.gray)
            
            CodeFooter()
        }
    }
    
    private func contagemDeLinhas(_ texto: String) -> String {
        let linhas = texto.split(separator: "\n", omittingEmptySubsequences: false).count - 1
        return linhas == 1 ? "1 linha" : "\(linhas) linhas"
    }

    /// O nome do arquivo carrega a chave do Page Object, que é o que dá nome
    /// aos arquivos gravados. Era "feature.py" fixo, o que não correspondia ao
    /// que o Salvar escreve em disco.
    private var chaveDoArquivo: String {
        session.engineInfo?.pageObjectsKey ?? "feature"
    }

    /// Copiar é do sistema, não do motor: área de transferência é da máquina de
    /// quem está usando, e não do processo do motor.
    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        appState.statusMessage = "Copiado para a área de transferência"
    }

    /// O `conteudo` entra aqui de propósito, e não só pelo `Binding` do editor.
    ///
    /// `$state.actionsCode` cria um Binding sem **ler** o valor, e o
    /// `@Observable` só registra dependência no que o corpo lê. Sem esta
    /// leitura, gravar um passo mudava o estado e a coluna não redesenhava: o
    /// código só aparecia quando alguma outra coisa forçasse o redesenho.
    ///
    /// A contagem de linhas é útil por si só, e é o que torna a leitura
    /// honesta em vez de um acesso solto só para enganar o observador.
    @ViewBuilder
    func editorHeader(title: String, color: Color, conteudo: String) -> some View {
        HStack {
            // O caminho do arquivo e o que pode ceder espaco aqui; os rotulos
            // dos botoes, nao. Sem isto "Copiar" quebrava em "Copi" / "ar".
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .truncationMode(.head)

            if !conteudo.isEmpty {
                Text(contagemDeLinhas(conteudo))
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.current.textTertiary ?? Color.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 8)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Copiar") { copiar(conteudo) }
                    .disabled(conteudo.isEmpty)
                Button("Salvar") { Task { await session.saveCode() } }
                    .disabled(appState.actionsCode.isEmpty && appState.locatorsCode.isEmpty)
                Button("Limpar") { Task { await session.clearSteps() } }
                    .disabled(appState.steps.isEmpty && conteudo.isEmpty)
            }
            .font(.system(size: 10))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .buttonStyle(.plain)
            .foregroundColor(themeManager.current.textSecondary ?? Color.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(themeManager.current.bgSubtle ?? Color.clear)
    }
}

struct CodeEditorContainer: View {
    @Binding var text: String
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        // A numeração de linha virou régua do próprio scroll do editor, então
        // ela rola junto e conta as linhas de verdade. O `CodeGutter`, que
        // desenhava um "1" fixo ao lado, saiu.
        CodeEditorView(text: $text)
    }
}

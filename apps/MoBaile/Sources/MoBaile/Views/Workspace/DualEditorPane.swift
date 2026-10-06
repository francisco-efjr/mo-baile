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
                // Left Editor: Pages
                VStack(spacing: 0) {
                    ideHeader(
                        folder: "pages",
                        file: "\(chaveDoArquivo).py",
                        accentColor: themeManager.current.fileTitleActions ?? Color.blue,
                        conteudo: appState.actionsCode,
                        copyLabel: "Copiar código das ações",
                        onCopy: { copiar(appState.actionsCode) },
                        onSave: { Task { await session.saveCode() } },
                        onClear: { Task { await session.clearSteps() } },
                        canSave: !appState.actionsCode.isEmpty || !appState.locatorsCode.isEmpty,
                        canClear: !appState.steps.isEmpty || !appState.actionsCode.isEmpty
                    )
                    CodeEditorContainer(text: $state.actionsCode, accessibilityLabel: "Código das ações (pages)")
                }
                
                if appState.splitEditors {
                    Divider().background(themeManager.current.border ?? Color.gray)
                    
                    // Right Editor: Locators
                    VStack(spacing: 0) {
                        ideHeader(
                            folder: "locators",
                            file: "\(chaveDoArquivo).py",
                            accentColor: themeManager.current.fileTitleLocators ?? Color.orange,
                            conteudo: appState.locatorsCode,
                            copyLabel: "Copiar localizadores",
                            onCopy: { copiar(appState.locatorsCode) },
                            onSave: { Task { await session.saveCode() } },
                            onClear: { Task { await session.clearSteps() } },
                            canSave: !appState.actionsCode.isEmpty || !appState.locatorsCode.isEmpty,
                            canClear: !appState.steps.isEmpty || !appState.locatorsCode.isEmpty
                        )
                        CodeEditorContainer(text: $state.locatorsCode, accessibilityLabel: "Código dos localizadores (locators)")
                    }
                }
            }
            
            Divider().background(themeManager.current.border ?? Color.gray)
            
            CodeFooter()
        }
    }
    
    private func contagemDeLinhas(_ texto: String) -> String {
        guard !texto.isEmpty else { return "0 linhas" }
        let linhas = texto.split(separator: "\n", omittingEmptySubsequences: false)
        let total = (linhas.last?.isEmpty == true && linhas.count > 1) ? (linhas.count - 1) : linhas.count
        return total == 1 ? "1 linha" : "\(total) linhas"
    }

    /// O nome do arquivo carrega a chave do Page Object, que é o que dá nome
    /// aos arquivos gravados.
    private var chaveDoArquivo: String {
        session.engineInfo?.pageObjectsKey ?? "feature"
    }

    /// Copiar para a área de transferência nativa do macOS.
    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        appState.statusMessage = "Copiado para a área de transferência"
    }

    /// Cabeçalho com abas no estilo autêntico de IDE (VS Code / Xcode).
    @ViewBuilder
    func ideHeader(
        folder: String,
        file: String,
        accentColor: Color,
        conteudo: String,
        copyLabel: String,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onClear: @escaping () -> Void,
        canSave: Bool,
        canClear: Bool
    ) -> some View {
        HStack(spacing: 0) {
            // Aba Ativa da IDE
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)

                Text(folder)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(themeManager.current.textSecondary)

                Text("/")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(themeManager.current.textTertiary)

                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accentColor)

                Text(file)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.current.textPrimary)

                if !conteudo.isEmpty {
                    Text(contagemDeLinhas(conteudo))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.current.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(themeManager.current.bgControlTrack)
                        )
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            // Os ícones eram lidos pela descrição automática do símbolo ("Mover",
            // "Código Incorporado") e a pasta e o arquivo, como textos soltos
            // ("pages", "/", "feature.py"). Vira uma frase só.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Arquivo \(folder)/\(file)")
            .accessibilityValue(conteudo.isEmpty ? "vazio" : contagemDeLinhas(conteudo))
            .background(themeManager.current.bgContent)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(accentColor),
                alignment: .top
            )
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(themeManager.current.borderSubtle),
                alignment: .trailing
            )

            Spacer(minLength: 8)

            // Botões de Ação da IDE
            HStack(spacing: 6) {
                IDEActionButton(
                    title: "Copiar",
                    icon: "doc.on.doc",
                    disabled: conteudo.isEmpty,
                    accessibilityLabel: copyLabel,
                    action: onCopy
                )
                // Salvar e Limpar agem sobre os dois arquivos e os passos, não
                // só sobre o editor do cabeçalho: o rótulo diz o que acontece.
                IDEActionButton(
                    title: "Salvar",
                    icon: "arrow.down.doc",
                    disabled: !canSave,
                    accessibilityLabel: "Salvar pages e locators",
                    action: onSave
                )
                IDEActionButton(
                    title: "Limpar",
                    icon: "trash",
                    disabled: !canClear,
                    accessibilityLabel: "Limpar passos e código",
                    action: onClear
                )
            }
            .padding(.trailing, 10)
        }
        .frame(height: 32)
        .background(themeManager.current.bgToolbar)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(themeManager.current.borderSubtle),
            alignment: .bottom
        )
    }
}

/// Botão de ação estilizado para a barra superior da IDE.
struct IDEActionButton: View {
    let title: String
    let icon: String
    let disabled: Bool
    /// Nome para o leitor de tela quando o título curto ("Copiar") é ambíguo,
    /// como nos dois cabeçalhos de editor, que têm os mesmos três botões.
    var accessibilityLabel: String? = nil
    let action: () -> Void
    @Environment(ThemeManager.self) var themeManager
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered && !disabled ? themeManager.current.borderSubtle : Color.clear)
            )
            .foregroundColor(
                disabled
                    ? themeManager.current.textDisabled
                    : (isHovered ? themeManager.current.textPrimary : themeManager.current.textSecondary)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct CodeEditorContainer: View {
    @Binding var text: String
    var accessibilityLabel: String = "Editor de código"
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        CodeEditorView(text: $text, accessibilityLabel: accessibilityLabel)
    }
}

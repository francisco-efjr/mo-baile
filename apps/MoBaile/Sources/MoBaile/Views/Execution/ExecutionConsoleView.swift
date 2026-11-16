import AppKit
import SwiftUI

/// Console da execução: as linhas de `run.log`, com teto de 5.000.
///
/// `NSTextView`, e não `LazyVStack` (D-F3): o console recebe rajadas de
/// centenas de linhas por segundo, e cada linha nova numa lista do SwiftUI
/// refaz a diferença de até 5.000 itens identificados. O texto do AppKit só
/// acrescenta no fim e corta no começo, faz o layout só do que está à vista,
/// e de graça dá seleção de várias linhas, ⌘C, ⌘F (barra de busca) e leitor
/// de tela.
struct ExecutionConsolePanel: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    /// Rolagem automática: pausa quando a pessoa sobe e volta pelo botão (ou
    /// rolando até o fim).
    @State private var seguindo = true

    var body: some View {
        let theme = themeManager.current
        let ex = appState.execution
        let revisao = ex.consoleRevision
        VStack(spacing: 0) {
            PaneHeader(title: "Console") {
                if let aviso = ex.console.droppedNotice {
                    Text(aviso)
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelTertiary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                        .help("O console guarda as últimas \(ex.console.limit.formatted()) linhas; o console.log da pasta da execução tem tudo")
                }
                if !seguindo {
                    Button {
                        seguindo = true
                    } label: {
                        Label("Ir para o Fim", systemImage: "arrow.down.to.line")
                    }
                    .controlSize(.small)
                    .help("Volta a acompanhar as linhas novas")
                    .transition(.opacity)
                }
                BarIconButton(icon: "doc.on.doc", label: "Copiar Tudo") {
                    Exporters.copy(ex.console.text)
                    appState.statusMessage = "Console copiado"
                }
                .disabled(ex.console.isEmpty)
                BarIconButton(icon: "trash", label: "Limpar Console") {
                    ex.clearConsole()
                }
                .disabled(ex.console.isEmpty)
            }
            Rectangle().fill(theme.separator).frame(height: 1)
            ExecutionConsoleTextView(console: ex.console, revision: revisao, following: $seguindo,
                                     background: NSColor(theme.bgTerminal), findRequest: appState.consoleFindRequest)
                .overlay {
                    if ex.console.isEmpty {
                        Text(ex.isRunning ? "Esperando a primeira linha…" : "A saída do main aparece aqui ao rodar.")
                            .font(DSFont.mono(11))
                            .foregroundStyle(TerminalPalette.muted)
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.crossfade, value: seguindo)
    }
}

/// O `NSTextView` do console. Aplica só a diferença desde a última vez.
struct ExecutionConsoleTextView: NSViewRepresentable {
    let console: ExecutionConsole
    /// Só para o SwiftUI chamar `updateNSView` a cada linha nova.
    let revision: Int
    @Binding var following: Bool
    let background: NSColor
    /// ⌘F na Execução: muda a cada pedido, e o texto abre a barra de busca.
    var findRequest: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(following: $following) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = true
        scroll.backgroundColor = background
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        if let texto = scroll.documentView as? NSTextView {
            texto.isEditable = false
            texto.isSelectable = true
            texto.isRichText = false
            texto.importsGraphics = false
            texto.usesFindBar = true
            texto.isIncrementalSearchingEnabled = true
            texto.drawsBackground = true
            texto.backgroundColor = background
            texto.textContainerInset = NSSize(width: 8, height: 6)
            texto.font = Coordinator.font
            texto.textColor = Coordinator.color(.normal)
            texto.setAccessibilityLabel("Console da execução")
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )
        context.coordinator.scroll = scroll
        context.coordinator.lastFindRequest = findRequest
        context.coordinator.sync(console, following: following)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.following = $following
        if scroll.backgroundColor != background {
            scroll.backgroundColor = background
            (scroll.documentView as? NSTextView)?.backgroundColor = background
        }
        context.coordinator.sync(console, following: following)
        if findRequest != context.coordinator.lastFindRequest {
            context.coordinator.lastFindRequest = findRequest
            context.coordinator.showFindBar()
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        static func color(_ tone: ExecutionConsole.Tone) -> NSColor {
            switch tone {
            case .normal: return NSColor(TerminalPalette.text)
            case .fail: return NSColor(TerminalPalette.fail)
            case .pass: return NSColor(TerminalPalette.pass)
            case .dim: return NSColor(TerminalPalette.muted)
            }
        }

        var following: Binding<Bool>
        weak var scroll: NSScrollView?
        var lastFindRequest = 0

        func showFindBar() {
            guard let texto = scroll?.documentView as? NSTextView else { return }
            texto.window?.makeFirstResponder(texto)
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            texto.performTextFinderAction(item)
        }
        /// O que já está no texto: linhas globais `aplicadasDescartadas..<aplicadas`.
        private var geracao = -1
        private var aplicadas = 0
        private var aplicadasDescartadas = 0
        private var seguiaAntes = true
        /// Rolagem feita por aqui não conta como a pessoa subindo.
        private var rolandoSozinho = false

        init(following: Binding<Bool>) {
            self.following = following
        }

        func sync(_ console: ExecutionConsole, following seguir: Bool) {
            guard let scroll, let texto = scroll.documentView as? NSTextView, let storage = texto.textStorage else { return }
            var mudou = false
            let lacuna = console.dropped > aplicadas
            if console.generation != geracao || lacuna || console.appended < aplicadas {
                storage.setAttributedString(Self.render(console.lines, comecaComQuebra: false))
                geracao = console.generation
                aplicadas = console.appended
                aplicadasDescartadas = console.dropped
                mudou = true
            } else {
                let cortar = console.dropped - aplicadasDescartadas
                if console.appended > aplicadas || cortar > 0 {
                    storage.beginEditing()
                    if console.appended > aplicadas {
                        let inicio = aplicadas - console.dropped
                        let novas = Array(console.lines[inicio...])
                        storage.append(Self.render(novas, comecaComQuebra: storage.length > 0))
                        aplicadas = console.appended
                    }
                    if cortar > 0 {
                        let corte = Self.offset(afterLines: cortar, in: storage.string as NSString)
                        storage.deleteCharacters(in: NSRange(location: 0, length: corte))
                        aplicadasDescartadas = console.dropped
                    }
                    storage.endEditing()
                    mudou = true
                }
            }
            let voltouASeguir = seguir && !seguiaAntes
            seguiaAntes = seguir
            if seguir && (mudou || voltouASeguir) {
                rolandoSozinho = true
                texto.scrollToEndOfDocument(nil)
                rolandoSozinho = false
            }
        }

        @objc func boundsChanged(_ notification: Notification) {
            guard !rolandoSozinho, let scroll, let documento = scroll.documentView else { return }
            let visivel = scroll.contentView.bounds
            let noFim = visivel.maxY >= documento.frame.height - 8
            guard noFim != following.wrappedValue else { return }
            let binding = following
            // Fora da atualização da view: mudar estado no meio dela é proibido.
            DispatchQueue.main.async { binding.wrappedValue = noFim }
        }

        /// Posição logo depois da `n`-ésima quebra de linha (o começo da linha
        /// `n`), ou o fim do texto.
        static func offset(afterLines n: Int, in texto: NSString) -> Int {
            var posicao = 0
            for _ in 0..<n {
                let achado = texto.range(of: "\n", options: .literal,
                                         range: NSRange(location: posicao, length: texto.length - posicao))
                guard achado.location != NSNotFound else { return texto.length }
                posicao = achado.location + 1
            }
            return posicao
        }

        static func render(_ linhas: [String], comecaComQuebra: Bool) -> NSAttributedString {
            let saida = NSMutableAttributedString()
            for (i, linha) in linhas.enumerated() {
                let texto = (comecaComQuebra || i > 0) ? "\n" + linha : linha
                saida.append(NSAttributedString(string: texto, attributes: [
                    .font: font, .foregroundColor: color(ExecutionConsole.tone(of: linha)),
                ]))
            }
            return saida
        }
    }
}

import AppKit

/// Componente de numeração de linha (gutter) no padrão de IDEs profissionais.
///
/// É desacoplado do `NSTextView` para evitar os problemas clássicos do AppKit:
/// 1. Clipping incorreto quando apenas o texto é redesenhado.
/// 2. Sobrescrita de fundo causada pelo preenchimento nativo do `NSTextView`.
/// 3. Invasão de seleção ou cliques do cursor na margem de numeração.
///
/// Sincroniza a rolagem com o `NSScrollView` via `boundsDidChangeNotification`.
final class IDEGutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    var gutterBackgroundColor: NSColor = .clear
    var textColor: NSColor = .secondaryLabelColor
    var separatorColor: NSColor = .separatorColor
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func attach(to scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView

        NotificationCenter.default.removeObserver(self)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @objc private func contentViewDidScroll(_ notification: Notification) {
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        scrollView?.scrollWheel(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        gutterBackgroundColor.setFill()
        bounds.fill()

        separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        guard let tv = textView, let sv = scrollView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }

        lm.ensureLayout(for: tc)
        let str = tv.string as NSString
        let scrollY = sv.contentView.bounds.origin.y
        let topInset = tv.textContainerInset.height

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        if str.length == 0 {
            let label = NSAttributedString(string: "1", attributes: attrs)
            let x = bounds.width - label.size().width - 8
            label.draw(at: NSPoint(x: max(4, x), y: topInset - scrollY))
            return
        }

        var lineNum = 1
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, _, _, glyphRange, _ in
            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let isLineStart = charRange.location == 0 || str.character(at: charRange.location - 1) == 0x0a
            if isLineStart {
                let y = rect.minY + topInset - scrollY
                if y + rect.height >= 0 && y <= self.bounds.height {
                    let label = NSAttributedString(string: "\(lineNum)", attributes: attrs)
                    let x = self.bounds.width - label.size().width - 8
                    label.draw(at: NSPoint(x: max(4, x), y: y))
                }
                lineNum += 1
            }
        }

        if lm.extraLineFragmentRect.height > 0 {
            let y = lm.extraLineFragmentRect.minY + topInset - scrollY
            if y + lm.extraLineFragmentRect.height >= 0 && y <= self.bounds.height {
                let label = NSAttributedString(string: "\(lineNum)", attributes: attrs)
                let x = bounds.width - label.size().width - 8
                label.draw(at: NSPoint(x: max(4, x), y: y))
            }
        }
    }
}

/// Contêiner que une o Gutter lateral à área de texto com rolagem.
final class IDEEditorContainerView: NSView {
    let gutterView = IDEGutterView()
    let scrollView = NSScrollView()
    /// Pilha do TextKit 1 montada à mão: gutter, linha atual e etiquetas de
    /// caractere especial falam com o `NSLayoutManager`. Montada assim, a
    /// pilha não é dona do armazenamento, então ele fica guardado aqui.
    let armazenamento = NSTextStorage()
    let layoutManager = CodeLayoutManager()
    let textView: CodeTextView

    private var gutterWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        textView = Self.montarTextView(armazenamento, layoutManager)
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        textView = Self.montarTextView(armazenamento, layoutManager)
        super.init(coder: coder)
        setup()
    }

    private static func montarTextView(_ armazenamento: NSTextStorage, _ layout: NSLayoutManager) -> CodeTextView {
        armazenamento.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        return CodeTextView(frame: .zero, textContainer: container)
    }

    private func setup() {
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        // Sem soft wrap, como o PyCharm em `.py`: cada linha lógica é uma linha
        // visual, e o recuo nunca fica sozinho numa linha numerada.
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let infinito = CGFloat.greatestFiniteMagnitude
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: infinito, height: infinito)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: infinito, height: infinito)
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.configurarEntradaLiteral()
        scrollView.documentView = textView

        gutterView.attach(to: scrollView, textView: textView)

        gutterView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gutterView)
        addSubview(scrollView)

        let widthConstraint = gutterView.widthAnchor.constraint(equalToConstant: 38)
        self.gutterWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint,

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func updateGutterWidth(forLineCount count: Int) {
        let digits = max(2, String(count).count)
        let neededWidth = CGFloat(digits) * 7.5 + 20
        if gutterWidthConstraint?.constant != neededWidth {
            gutterWidthConstraint?.constant = neededWidth
            needsLayout = true
        }
    }
}

/// Layout do editor. As etiquetas de caractere especial (PO-2) moram aqui.
final class CodeLayoutManager: NSLayoutManager {}

/// `NSTextView` do editor de Page Objects: recebe e devolve os caracteres
/// como o PyCharm (PO-1).
///
/// O editor do PyCharm é desenhado pela JetBrains Runtime, fora do sistema de
/// texto do Cocoa, então nenhuma substituição do macOS acontece lá. Aqui elas
/// são todas desligadas, a colagem normaliza CR e CRLF para `\n` e o Tab
/// insere espaços até a próxima parada de 4 colunas.
class CodeTextView: NSTextView {
    /// Histórico próprio de desfazer: o da janela mistura edições dos dois
    /// editores e de outros campos, e trocar o texto inteiro (Limpar) precisa
    /// zerar só este.
    let historico = UndoManager()

    override var undoManager: UndoManager? { historico }

    // ⌘Z e ⇧⌘Z do menu Editar descem pelo responder chain até a janela, que
    // usaria o histórico dela. O editor responde antes, com o próprio.
    @objc func undo(_ sender: Any?) { historico.undo() }
    @objc func redo(_ sender: Any?) { historico.redo() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return historico.canUndo
        case #selector(redo(_:)): return historico.canRedo
        default: return super.validateUserInterfaceItem(item)
        }
    }

    /// Desliga tudo que mexe no que a pessoa digita ou cola.
    func configurarEntradaLiteral() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        enabledTextCheckingTypes = 0
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false
        inlinePredictionType = .no
        if #available(macOS 15.0, *) {
            writingToolsBehavior = .none
        }
    }

    /// Colar, soltar e Serviços passam por aqui. Texto simples entra literal,
    /// só com as quebras de linha normalizadas; o resto segue o padrão.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let bruto = pboard.string(forType: .string) else {
            return super.readSelection(from: pboard, type: type)
        }
        inserirLiteral(EditorText.normalizarQuebras(bruto))
        return true
    }

    /// Tab insere espaços até a próxima parada (4 espaços no começo da linha).
    override func insertTab(_ sender: Any?) {
        let texto = string as NSString
        let coluna = EditorText.linhaEColuna(em: texto, posicao: selectedRange().location).coluna - 1
        let faltam = EditorText.recuo - coluna % EditorText.recuo
        inserirLiteral(String(repeating: " ", count: faltam))
    }

    /// Troca a seleção pelo texto, com desfazer e aviso ao delegate, sem
    /// passar pelas correções do `insertText`.
    private func inserirLiteral(_ texto: String) {
        let faixa = selectedRange()
        guard shouldChangeText(in: faixa, replacementString: texto) else { return }
        textStorage?.replaceCharacters(in: faixa, with: NSAttributedString(string: texto, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(NSRange(location: faixa.location + (texto as NSString).length, length: 0))
    }
}

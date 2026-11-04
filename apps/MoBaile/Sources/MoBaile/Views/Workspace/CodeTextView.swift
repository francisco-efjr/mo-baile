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
    /// Número da linha do cursor, mais claro (`#A1A3AB` no PyCharm escuro).
    var currentLineTextColor: NSColor = .labelColor
    var separatorColor: NSColor = .separatorColor
    /// Mesma família do texto, 1 pt menor (diretriz da JetBrains para o gutter).
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

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
        let deslocamento = tv.textContainerOrigin.y - sv.contentView.bounds.origin.y
        let linhaDoCursor = EditorText.linhaEColuna(em: str, posicao: tv.selectedRange().location).linha
        let semSelecao = tv.selectedRange().length == 0
        // Linha de base do texto dentro do fragmento: o número fica na mesma
        // linha de base do código, como no PyCharm (P0-6).
        let fonteDoTexto = tv.font ?? EditorFont.fonte()
        let alturaDoFragmento = EditorFont.alturaDaLinha(fonteDoTexto)
        let linhaDeBase = alturaDoFragmento + fonteDoTexto.descender - EditorFont.deslocamentoDaLinhaDeBase(fonteDoTexto)

        func numero(_ n: Int, topo: CGFloat, altura: CGFloat) {
            let y = topo + deslocamento
            guard y + altura >= 0, y <= bounds.height else { return }
            let atual = semSelecao && n == linhaDoCursor
            let label = NSAttributedString(string: "\(n)", attributes: [
                .font: font, .foregroundColor: atual ? currentLineTextColor : textColor,
            ])
            let x = bounds.width - label.size().width - 10
            label.draw(at: NSPoint(x: max(4, x), y: y + linhaDeBase - font.ascender))
        }

        if str.length == 0 {
            numero(1, topo: 0, altura: alturaDoFragmento)
            return
        }

        var lineNum = 1
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, _, _, glyphRange, _ in
            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if charRange.location == 0 || str.character(at: charRange.location - 1) == 0x0a {
                numero(lineNum, topo: rect.minY, altura: rect.height)
                lineNum += 1
            }
        }
        if lm.extraLineFragmentRect.height > 0 {
            numero(lineNum, topo: lm.extraLineFragmentRect.minY, altura: lm.extraLineFragmentRect.height)
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

    /// Põe `texto` no editor (PO-3). Se for o texto atual mais um trecho no fim
    /// (passo novo gravado), só acrescenta: o cursor e o desfazer da pessoa
    /// ficam. Qualquer outra troca recria o texto e zera o histórico, que
    /// apontaria para faixas que não existem mais.
    /// Devolve `true` quando recriou o texto inteiro.
    @discardableResult
    func carregar(_ texto: String) -> Bool {
        let atual = textView.string as NSString
        guard atual as String != texto else { return false }
        var recriou = false
        let novo = texto as NSString
        let atributos = textView.typingAttributes
        if atual.length > 0, novo.hasPrefix(atual as String) {
            // `atual` pode ser a string viva do armazenamento: o tamanho é
            // lido antes de mexer nele.
            let fim = atual.length
            textView.breakUndoCoalescing()
            let resto = novo.substring(from: fim)
            armazenamento.replaceCharacters(in: NSRange(location: fim, length: 0),
                                            with: NSAttributedString(string: resto, attributes: atributos))
            textView.recolorir(NSRange(location: fim, length: (resto as NSString).length))
        } else {
            let selecao = textView.selectedRange()
            armazenamento.setAttributedString(NSAttributedString(string: texto, attributes: atributos))
            textView.historico.removeAllActions()
            textView.setSelectedRange(NSRange(location: min(selecao.location, novo.length), length: 0))
            textView.recolorir(nil)
            recriou = true
        }
        updateGutterWidth(forLineCount: EditorText.linhasDoGutter(texto))
        gutterView.needsDisplay = true
        return recriou
    }
}

/// Layout do editor. Desenha as etiquetas de caractere especial (PO-2): a
/// abreviação num retângulo de 1 pt, como o PyCharm. A largura vem do
/// delegate (`CaracteresEspeciais.swift`); aqui só se pinta.
final class CodeLayoutManager: NSLayoutManager {
    var corDaEtiqueta: NSColor = .tertiaryLabelColor
    var fonteDaEtiqueta: NSFont = .monospacedSystemFont(ofSize: 9, weight: .regular)

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func larguraDaEtiqueta(_ nome: String) -> CGFloat {
        ceil((nome as NSString).size(withAttributes: [.font: fonteDaEtiqueta]).width) + 6
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let texto = textStorage?.string as NSString? else { return }
        let caracteres = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let atributos: [NSAttributedString.Key: Any] = [.font: fonteDaEtiqueta, .foregroundColor: corDaEtiqueta]
        for indice in caracteres.location..<NSMaxRange(caracteres) {
            guard let nome = CaracteresEspeciais.abreviacao(em: texto, indice: indice) else { continue }
            let glifo = glyphIndexForCharacter(at: indice)
            let linha = lineFragmentRect(forGlyphAt: glifo, effectiveRange: nil)
            let x = location(forGlyphAt: glifo).x
            let caixa = NSRect(
                x: origin.x + linha.minX + x + 1, y: origin.y + linha.minY + 2,
                width: larguraDaEtiqueta(nome) - 2, height: max(linha.height - 4, 8)
            )
            corDaEtiqueta.setStroke()
            let moldura = NSBezierPath(roundedRect: caixa.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            moldura.lineWidth = 1
            moldura.stroke()
            let rotulo = NSAttributedString(string: nome, attributes: atributos)
            let tamanho = rotulo.size()
            rotulo.draw(at: NSPoint(x: caixa.midX - tamanho.width / 2, y: caixa.midY - tamanho.height / 2))
        }
    }
}

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

    /// Cores do editor. `nil` deixa o texto como está (sem esquema ainda).
    var esquema: EditorScheme?
    /// Falso para YAML e texto simples: tudo na cor do texto.
    var python = true
    /// Faixa trocada na edição em curso, para recolorir só o parágrafo.
    private var faixaEditada: NSRange?

    override func shouldChangeText(in faixa: NSRange, replacementString texto: String?) -> Bool {
        guard super.shouldChangeText(in: faixa, replacementString: texto) else { return false }
        faixaEditada = NSRange(location: faixa.location, length: (texto as NSString?)?.length ?? 0)
        return true
    }

    override func didChangeText() {
        if let faixa = faixaEditada { recolorir(faixa) }
        faixaEditada = nil
        super.didChangeText()
    }

    /// Recolore o parágrafo editado (ou tudo, com `nil`). Muda só atributos
    /// do armazenamento, sem passar pelo desfazer.
    func recolorir(_ editada: NSRange?) {
        guard let esquema, let armazenamento = textStorage else { return }
        let texto = armazenamento.string as NSString
        let tudo = NSRange(location: 0, length: texto.length)
        if !python {
            armazenamento.addAttribute(.foregroundColor, value: esquema.texto, range: tudo)
            return
        }
        let faixa = editada.map { PythonHighlighter.faixaParaRecolorir(texto, editada: $0) } ?? tudo
        PythonHighlighter.colorir(armazenamento, faixa: faixa, esquema: esquema)
    }

    // MARK: Linha atual

    /// Retângulo da linha do cursor, em coordenadas do editor.
    func retanguloDaLinhaAtual() -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let texto = string as NSString
        let cursor = selectedRange().location
        var linha: NSRect
        if texto.length == 0 || (cursor >= texto.length && texto.character(at: texto.length - 1) == 0x0A) {
            linha = lm.extraLineFragmentRect
        } else {
            lm.ensureLayout(for: tc)
            linha = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: min(cursor, texto.length - 1)), effectiveRange: nil)
        }
        if linha.height == 0 { linha.size.height = EditorFont.alturaDaLinha(font ?? EditorFont.fonte()) }
        return NSRect(x: 0, y: linha.minY + textContainerOrigin.y, width: bounds.width, height: linha.height)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        // Como o PyCharm: realce da linha do cursor só sem seleção.
        guard let cor = esquema?.linhaAtual, selectedRange().length == 0,
              let linha = retanguloDaLinhaAtual(), linha.intersects(rect) else { return }
        cor.setFill()
        linha.fill()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
        (enclosingScrollView?.superview as? IDEEditorContainerView)?.gutterView.needsDisplay = true
    }

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

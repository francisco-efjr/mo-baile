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

        guard let tv = textView as? CodeTextView, let sv = scrollView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }

        let str = tv.string as NSString
        let deslocamento = tv.textContainerOrigin.y - sv.contentView.bounds.origin.y
        let semSelecao = tv.selectedRange().length == 0
        let linhaDoCursor = semSelecao ? tv.linhaEColunaDoCursor().linha : 0
        // Linha de base do texto dentro do fragmento: o número fica na mesma
        // linha de base do código, como no PyCharm (P0-6).
        let fonteDoTexto = tv.font ?? EditorFont.fonte()
        let alturaDoFragmento = EditorFont.alturaDaLinha(fonteDoTexto)
        let linhaDeBase = alturaDoFragmento + fonteDoTexto.descender - EditorFont.deslocamentoDaLinhaDeBase(fonteDoTexto)

        func numero(_ n: Int, topo: CGFloat, altura: CGFloat) {
            let y = topo + deslocamento
            guard y + altura >= 0, y <= bounds.height else { return }
            let atual = n == linhaDoCursor
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

        // Só os fragmentos visíveis (R-06): o número da primeira linha vem do
        // contador incremental, e não de percorrer o arquivo do começo.
        var visivel = sv.contentView.bounds
        visivel.origin.y -= tv.textContainerOrigin.y
        visivel.origin.x = 0
        let glifos = lm.glyphRange(forBoundingRect: visivel, in: tc)
        if glifos.length > 0 {
            let primeiro = lm.characterIndexForGlyph(at: glifos.location)
            var lineNum = tv.numeroDaLinha(em: primeiro, contador: \.contadorDoGutter)
            lm.enumerateLineFragments(forGlyphRange: glifos) { rect, _, _, glyphRange, _ in
                let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                if charRange.location == 0 || str.character(at: charRange.location - 1) == 0x0a {
                    numero(lineNum, topo: rect.minY, altura: rect.height)
                    lineNum += 1
                }
            }
        }
        let extra = lm.extraLineFragmentRect
        if extra.height > 0, extra.intersects(visivel) {
            numero(tv.totalDeLinhas, topo: extra.minY, altura: extra.height)
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
        // Layout só do que aparece (R-06): sem isto, abrir ou rolar um arquivo
        // de 1 MB calcula o layout do arquivo inteiro.
        layout.allowsNonContiguousLayout = true
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
            textView.registrarTroca(em: NSRange(location: fim, length: 0), por: resto)
            armazenamento.replaceCharacters(in: NSRange(location: fim, length: 0),
                                            with: NSAttributedString(string: resto, attributes: atributos))
            textView.recolorir(NSRange(location: fim, length: (resto as NSString).length), mexeuEmAspas: true)
        } else {
            let selecao = textView.selectedRange()
            armazenamento.setAttributedString(NSAttributedString(string: texto, attributes: atributos))
            textView.recontarLinhas()
            textView.breakUndoCoalescing()
            textView.historico.removeAllActions()
            textView.setSelectedRange(NSRange(location: min(selecao.location, novo.length), length: 0))
            textView.recolorir(nil)
            recriou = true
        }
        updateGutterWidth(forLineCount: textView.totalDeLinhas)
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
    /// A edição em curso pôs ou tirou aspas, `\\` ou `#`: pode abrir ou fechar
    /// uma docstring e mudar a cor até o fim do arquivo.
    private var edicaoMexeuEmAspas = false

    // MARK: Contagem incremental (R-06)

    /// Posição e linha já conhecidas: a próxima consulta conta só a diferença.
    struct ContadorDeLinhas {
        var posicao = 0
        var linha = 1
    }
    var contadorDoCursor = ContadorDeLinhas()
    var contadorDoGutter = ContadorDeLinhas()
    /// Linhas do texto (quebras + 1), mantido a cada troca.
    private(set) var totalDeLinhas = 1

    /// Uma troca em `faixa` por `novo` vai acontecer: ajusta o total de linhas
    /// e esquece o que os contadores sabiam depois do ponto trocado.
    func registrarTroca(em faixa: NSRange, por novo: String) {
        let texto = string as NSString
        let removidas = EditorText.quebras(em: texto, faixa: faixa)
        let inseridas = EditorText.quebras(em: novo as NSString, faixa: NSRange(location: 0, length: (novo as NSString).length))
        totalDeLinhas = max(1, totalDeLinhas + inseridas - removidas)
        if faixa.location < contadorDoCursor.posicao { contadorDoCursor = ContadorDeLinhas() }
        if faixa.location < contadorDoGutter.posicao { contadorDoGutter = ContadorDeLinhas() }
    }

    func recontarLinhas() {
        let texto = string as NSString
        totalDeLinhas = EditorText.quebras(em: texto, faixa: NSRange(location: 0, length: texto.length)) + 1
        contadorDoCursor = ContadorDeLinhas()
        contadorDoGutter = ContadorDeLinhas()
    }

    /// Número da linha (a partir de 1) da posição UTF-16, contando a partir do
    /// que o contador já sabia.
    func numeroDaLinha(em posicao: Int, contador caminho: ReferenceWritableKeyPath<CodeTextView, ContadorDeLinhas>) -> Int {
        let texto = string as NSString
        let alvo = min(max(posicao, 0), texto.length)
        var contador = self[keyPath: caminho]
        if contador.posicao > texto.length { contador = ContadorDeLinhas() }
        if alvo >= contador.posicao {
            contador.linha += EditorText.quebras(em: texto, faixa: NSRange(location: contador.posicao, length: alvo - contador.posicao))
        } else {
            contador.linha -= EditorText.quebras(em: texto, faixa: NSRange(location: alvo, length: contador.posicao - alvo))
        }
        contador.posicao = alvo
        self[keyPath: caminho] = contador
        return contador.linha
    }

    /// Linha e coluna do cursor para o rodapé: a linha pelo contador, a coluna
    /// só dentro da linha (grafemas, tab até a parada).
    func linhaEColunaDoCursor() -> (linha: Int, coluna: Int) {
        let texto = string as NSString
        let posicao = min(selectedRange().location, texto.length)
        let linha = numeroDaLinha(em: posicao, contador: \.contadorDoCursor)
        let inicio = texto.lineRange(for: NSRange(location: posicao, length: 0)).location
        let trecho = texto.substring(with: NSRange(location: inicio, length: posicao - inicio)) as NSString
        return (linha, EditorText.linhaEColuna(em: trecho, posicao: trecho.length).coluna)
    }

    override func shouldChangeText(in faixa: NSRange, replacementString texto: String?) -> Bool {
        guard super.shouldChangeText(in: faixa, replacementString: texto) else { return false }
        let novo = texto ?? ""
        faixaEditada = NSRange(location: faixa.location, length: (novo as NSString).length)
        let removido = (string as NSString).substring(with: faixa)
        edicaoMexeuEmAspas = PythonHighlighter.mexeEmLiteral(removido) || PythonHighlighter.mexeEmLiteral(novo)
        registrarTroca(em: faixa, por: novo)
        return true
    }

    override func didChangeText() {
        if let faixa = faixaEditada { recolorir(faixa, mexeuEmAspas: edicaoMexeuEmAspas) }
        faixaEditada = nil
        edicaoMexeuEmAspas = false
        super.didChangeText()
    }

    /// Recolore a faixa editada (ou tudo, com `nil`). Muda só atributos do
    /// armazenamento, sem passar pelo desfazer.
    func recolorir(_ editada: NSRange?, mexeuEmAspas: Bool = false) {
        guard let esquema, let armazenamento = textStorage else { return }
        let texto = armazenamento.string as NSString
        let tudo = NSRange(location: 0, length: texto.length)
        if !python {
            armazenamento.addAttribute(.foregroundColor, value: esquema.texto, range: tudo)
            return
        }
        let faixa = editada.map {
            PythonHighlighter.faixaParaRecolorir(armazenamento, editada: $0, mexeuEmAspas: mexeuEmAspas)
        } ?? tudo
        PythonHighlighter.colorir(armazenamento, faixa: faixa, esquema: esquema)
    }

    // MARK: Linha atual

    /// Retângulo da linha do cursor, em coordenadas do editor.
    func retanguloDaLinhaAtual() -> NSRect? {
        guard let lm = layoutManager else { return nil }
        let texto = string as NSString
        let cursor = selectedRange().location
        var linha: NSRect
        if texto.length == 0 || (cursor >= texto.length && texto.character(at: texto.length - 1) == 0x0A) {
            lm.ensureLayout(forCharacterRange: NSRange(location: texto.length, length: 0))
            linha = lm.extraLineFragmentRect
        } else {
            // Sem `ensureLayout` do contêiner inteiro: o layout não contíguo
            // calcula só a linha pedida (R-06).
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

    /// Última linha realçada, para redesenhar só ela e a nova (R-06).
    private var linhaRealcada: NSRect?

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if let antiga = linhaRealcada { setNeedsDisplay(antiga) }
        linhaRealcada = retanguloDaLinhaAtual()
        if let nova = linhaRealcada { setNeedsDisplay(nova) }
        (enclosingScrollView?.superview as? IDEEditorContainerView)?.gutterView.needsDisplay = true
    }

    // ⌘Z e ⇧⌘Z do menu Editar descem pelo responder chain até a janela, que
    // usaria o histórico dela. O editor responde antes, com o próprio.
    // Depois de desfazer, o total de linhas é recontado: não dá para garantir
    // que toda troca do desfazer passe por `shouldChangeText`.
    @objc func undo(_ sender: Any?) { historico.undo(); recontarLinhas() }
    @objc func redo(_ sender: Any?) { historico.redo(); recontarLinhas() }

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
        let coluna = linhaEColunaDoCursor().coluna - 1
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

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
    let textView = CodeTextView()

    private var gutterWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 12)
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

/// `NSTextView` especializado para edição de código no MoBaile.
class CodeTextView: NSTextView {
    // Mantém compatibilidade com referências existentes.
}

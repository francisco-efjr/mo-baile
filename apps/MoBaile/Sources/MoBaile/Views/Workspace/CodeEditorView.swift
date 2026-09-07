import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Environment(ThemeManager.self) var themeManager
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.backgroundColor = NSColor.clear
        textView.textContainerInset = NSSize(width: 10, height: 12)
        
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.85
        textView.defaultParagraphStyle = style
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        
        let bgColor = themeManager.current.bgContent
        textView.backgroundColor = NSColor(bgColor)
        nsView.backgroundColor = NSColor(bgColor)
        
        let plainColor = themeManager.current.syntaxPlain
        textView.textColor = NSColor(plainColor)
        
        // Very basic implementation, real one would need tokens passed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        
        init(_ parent: CodeEditorView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

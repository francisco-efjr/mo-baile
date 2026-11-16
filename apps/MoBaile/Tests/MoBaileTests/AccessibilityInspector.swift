import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// Um nó da árvore de acessibilidade que o macOS entrega ao VoiceOver.
///
/// Ler esta árvore é a única forma de conferir, sem tecnologia assistiva
/// ligada, o que um leitor de tela realmente anuncia: o que está no código
/// (`.accessibilityLabel` num contêiner, por exemplo) nem sempre é o que chega
/// ao leitor.
struct AXNode {
    let role: String
    let label: String
    let value: String
    let help: String
    let isSelected: Bool
    let children: [AXNode]

    /// Este nó e todos os descendentes, em ordem de leitura.
    var all: [AXNode] { [self] + children.flatMap(\.all) }

    /// Controles que o leitor trata como botão, incluindo botão de rádio e
    /// caixa de seleção, que é como o SwiftUI expõe alguns toggles.
    var buttons: [AXNode] {
        all.filter { ["AXButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXMenuButton"].contains($0.role) }
    }

    func node(label: String) -> AXNode? {
        all.first { $0.label == label }
    }

    func nodes(label: String) -> [AXNode] {
        all.filter { $0.label == label }
    }

    var dump: String {
        var linhas: [String] = []
        func escreve(_ no: AXNode, _ nivel: Int) {
            let sel = no.isSelected ? " [selecionado]" : ""
            linhas.append("\(String(repeating: "  ", count: nivel))\(no.role) label='\(no.label)' value='\(no.value)' help='\(no.help)'\(sel)")
            no.children.forEach { escreve($0, nivel + 1) }
        }
        escreve(self, 0)
        return linhas.joined(separator: "\n")
    }
}

/// Hospeda uma View numa janela fora da tela e lê a árvore de acessibilidade.
@MainActor
enum AccessibilityInspector {
    private static func texto(_ objeto: NSObject, _ seletor: String) -> String {
        if objeto.responds(to: Selector(seletor)),
           let valor = objeto.perform(Selector(seletor))?.takeUnretainedValue() {
            if let s = valor as? String { return s }
            if let n = valor as? NSNumber { return n.stringValue }
            // `accessibilityRole` devolve um NSAccessibility.Role, que é um NSString.
            return "\(valor)"
        }
        return legado(objeto, seletor).map(descrever) ?? ""
    }

    /// Linhas de `Table` e de `List` chegam como elementos do protocolo antigo
    /// do AppKit (`accessibilityAttributeValue:`), sem os métodos novos. O
    /// VoiceOver lê pelos dois caminhos; o inspetor também precisa.
    private static let atributosLegados: [String: String] = [
        "accessibilityRole": "AXRole",
        "accessibilityLabel": "AXDescription",
        "accessibilityValue": "AXValue",
        "accessibilityHelp": "AXHelp",
        "accessibilityChildren": "AXChildren",
        "accessibilityTitle": "AXTitle",
        "accessibilitySelected": "AXSelected",
    ]

    static func legado(_ objeto: NSObject, _ seletor: String) -> Any? {
        guard let nome = atributosLegados[seletor] else { return nil }
        let nomes = objeto.accessibilityAttributeNames()
        guard nomes.contains(NSAccessibility.Attribute(rawValue: nome)) else { return nil }
        return objeto.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: nome))
    }

    private static func descrever(_ valor: Any) -> String {
        if let s = valor as? String { return s }
        if let n = valor as? NSNumber { return n.stringValue }
        return "\(valor)"
    }

    private static func no(_ objeto: NSObject, nivel: Int) -> AXNode {
        var filhos: [AXNode] = []
        if nivel < 40 {
            if objeto.responds(to: Selector("accessibilityChildren")),
               let lista = objeto.perform(Selector("accessibilityChildren"))?.takeUnretainedValue() as? [Any] {
                filhos = lista.compactMap { ($0 as? NSObject).map { no($0, nivel: nivel + 1) } }
            } else if let lista = legado(objeto, "accessibilityChildren") as? [Any] {
                filhos = lista.compactMap { ($0 as? NSObject).map { no($0, nivel: nivel + 1) } }
            }
        }
        var selecionado = false
        if objeto.responds(to: Selector("isAccessibilitySelected")) {
            // `BOOL` devolvido por performSelector chega como ponteiro: o
            // `NSObject` não oferece leitura segura de escalar, então se
            // consulta pelo atributo, que devolve NSNumber.
            selecionado = (objeto.value(forKey: "accessibilitySelected") as? Bool) ?? false
        } else if let valor = legado(objeto, "accessibilitySelected") as? Bool {
            selecionado = valor
        }
        var rotulo = texto(objeto, "accessibilityLabel")
        if rotulo.isEmpty { rotulo = legado(objeto, "accessibilityTitle").map(descrever) ?? "" }
        return AXNode(
            role: texto(objeto, "accessibilityRole"),
            label: rotulo,
            value: texto(objeto, "accessibilityValue"),
            help: texto(objeto, "accessibilityHelp"),
            isSelected: selecionado,
            children: filhos
        )
    }

    /// Lê a árvore da View. Sem janela/serviço de acessibilidade no ambiente
    /// (por exemplo, runner sem sessão gráfica), o SwiftUI não monta a árvore
    /// e o teste é pulado em vez de aprovar sem ter verificado nada.
    static func arvore<V: View>(
        de view: V,
        largura: CGFloat = 520,
        altura: CGFloat = 400,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AXNode {
        let host = NSHostingView(rootView: view.frame(width: largura, height: altura))
        host.frame = NSRect(x: 0, y: 0, width: largura, height: altura)
        let janela = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        // Sem isto o `close()` libera a janela uma segunda vez (o padrão de
        // `NSWindow` criada em código é `isReleasedWhenClosed = true`) e o
        // processo de teste termina com SIGSEGV depois de passar.
        janela.isReleasedWhenClosed = false
        janela.contentView = host
        defer { janela.close() }

        _ = NSApplication.shared
        // O SwiftUI só monta a árvore de acessibilidade quando há cliente de
        // acessibilidade; estes atributos fazem o processo de teste se declarar um.
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        janela.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()

        let raiz = no(host, nivel: 0)
        if raiz.children.isEmpty {
            throw XCTSkip("O SwiftUI não montou a árvore de acessibilidade neste ambiente (sem sessão gráfica?)")
        }
        return raiz
    }
}

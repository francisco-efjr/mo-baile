import AppKit
import SwiftUI

/// Bug a partir de uma validação divergente ou não disparada.
///
/// Copia de uma vez o texto no modelo de bug do time e duas imagens: o painel
/// Validação (parâmetro, obtido e esperado com ✓/✗) e o print do card do
/// Figma. O clipboard leva três formas do mesmo conteúdo, e cada destino
/// escolhe a que entende: RTFD (Notes, Mail, Pages), HTML com as imagens
/// embutidas (navegador: Jira, Azure DevOps, Confluence, Google Docs) e texto
/// puro (terminal, chat). "Copiar Imagens do Bug" põe só as duas imagens lado a
/// lado, para quem cola imagem e texto separados.
enum ReportBug {
    /// O modelo de bug do time, com o que o relatório sabe preenchido. Usuário,
    /// base e versão o app não conhece: ficam para a pessoa.
    static func text(for result: ReportResult, printName: String? = nil) -> String {
        var linhas: [String] = []
        linhas.append("Resultado Obtido *: \(resumo(result))")
        linhas += detalhes(result)
        linhas.append("")
        linhas.append("Usuário, Conta e Cooperativa *: ")
        linhas.append("")
        linhas.append("Base *: ")
        linhas.append("")
        linhas.append("Passos para reproduzir problema *: ")
        for (i, passo) in passos(result).enumerated() { linhas.append("\(i + 1). \(passo)") }
        linhas.append("")
        let anexos = printName.map { "a validação do Mo baile e o card do Figma (\($0))" } ?? "a validação do Mo baile"
        linhas.append("Possui imagem/vídeo para similar problema: Sim, em anexo: \(anexos).")
        linhas.append("")
        linhas.append("Versão: ")
        linhas.append("")
        linhas.append("Tag: automacao")
        return linhas.joined(separator: "\n")
    }

    static func canCreate(for result: ReportResult) -> Bool { result.status != .ok }

    private static func contexto(_ result: ReportResult) -> String {
        var partes = [result.section]
        if let flowLabel = result.flowLabel { partes.append("fluxo \(flowLabel)") }
        if !result.variation.isEmpty { partes.append("variação \(result.variation)") }
        return partes.joined(separator: ", ")
    }

    private static func resumo(_ result: ReportResult) -> String {
        switch result.status {
        case .missing:
            return "O evento \(result.event) não foi disparado (\(contexto(result))). Nenhum disparo com esse fluxo, tela e detail entre os eventos auditados."
        case .error, .ok:
            let hora = result.matched?.time.map { ", log \($0)" } ?? ""
            return "O evento \(result.event) disparou com valores diferentes da spec (\(contexto(result))\(hora))."
        }
    }

    private static func detalhes(_ result: ReportResult) -> [String] {
        if result.status == .missing {
            guard !result.expected.isEmpty else { return [] }
            return ["Esperado:"] + result.expected.map { "- \($0.key): \($0.value)" }
        }
        var linhas = result.checks.filter { !$0.ok }.map { check in
            "- \(check.field): obtido \(check.obtained.map { "\"\($0)\"" } ?? "ausente"), esperado \"\(check.expected)\""
        }
        if let gaScreen = result.gaScreen {
            linhas.append("- ga_screen do disparo: \(gaScreen)")
        }
        return linhas
    }

    private static func valorEsperado(_ result: ReportResult, _ campos: [String]) -> String? {
        for campo in campos {
            if let valor = result.expected.first(where: { $0.key == campo })?.value, !valor.isEmpty { return valor }
            if let valor = result.checks.first(where: { $0.field == campo })?.expected, !valor.isEmpty { return valor }
        }
        return nil
    }

    private static func passos(_ result: ReportResult) -> [String] {
        var passos: [String] = []
        passos.append(result.flowLabel.map { "Abrir o app no fluxo \($0)." } ?? "Abrir o app.")
        if let tela = valorEsperado(result, ["screen_name", "firebase_screen"]) {
            passos.append("Ir até a tela \(tela).")
        }
        if let acao = valorEsperado(result, ["detail"]) ?? (result.variation.isEmpty ? nil : result.variation) {
            passos.append("Executar a ação \(acao).")
        }
        passos.append("Conferir no Firebase Analytics o disparo de \(result.event).")
        return passos
    }

    // MARK: - Clipboard

    struct Attachment {
        let name: String
        let png: Data
        let size: CGSize
    }

    /// Texto e imagens nas três formas, num item só do clipboard.
    static func write(text: String, attachments: [Attachment], to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        if let rtfd = rtfd(text: text, attachments: attachments) {
            item.setData(rtfd, forType: .rtfd)
        }
        item.setString(html(text: text, attachments: attachments), forType: .html)
        item.setString(text, forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Só as imagens, lado a lado numa só, para colar à parte.
    static func writeImage(_ attachments: [Attachment], to pasteboard: NSPasteboard) -> Bool {
        guard let imagem = sideBySide(attachments), let png = pngData(imagem) else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = imagem.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return true
    }

    static func html(text: String, attachments: [Attachment]) -> String {
        let corpo = text.split(separator: "\n", omittingEmptySubsequences: false).map { linha -> String in
            let escapada = escape(String(linha))
            // Rótulo do modelo em negrito, como no formulário do time.
            if let fim = escapada.range(of: ":"), !escapada.hasPrefix("- "), !escapada.first!.isNumber {
                return "<b>\(escapada[..<fim.upperBound])</b>\(escapada[fim.upperBound...])"
            }
            return escapada
        }.joined(separator: "<br>\n")
        let imagens = attachments.map { anexo in
            let largura = Int(min(anexo.size.width, 720))
            return "<p><img src=\"data:image/png;base64,\(anexo.png.base64EncodedString())\" alt=\"\(escape(anexo.name))\" width=\"\(largura)\"></p>"
        }.joined(separator: "\n")
        return "<meta charset=\"utf-8\"><div>\(corpo)</div>\n\(imagens)"
    }

    private static func escape(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func rtfd(text: String, attachments: [Attachment]) -> Data? {
        let documento = NSMutableAttributedString(
            string: text + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        )
        for anexo in attachments {
            let arquivo = FileWrapper(regularFileWithContents: anexo.png)
            arquivo.preferredFilename = anexo.name
            documento.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: arquivo)))
            documento.append(NSAttributedString(string: "\n"))
        }
        return documento.rtfd(from: NSRange(location: 0, length: documento.length), documentAttributes: [:])
    }

    static func pngData(_ imagem: NSImage) -> Data? {
        guard let tiff = imagem.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func sideBySide(_ attachments: [Attachment]) -> NSImage? {
        let imagens = attachments.compactMap { NSImage(data: $0.png) }
        guard !imagens.isEmpty else { return nil }
        let altura = imagens.map(\.size.height).max() ?? 0
        let espaco: CGFloat = 16
        let largura = imagens.map(\.size.width).reduce(0, +) + espaco * CGFloat(imagens.count - 1)
        return NSImage(size: NSSize(width: largura, height: altura), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: largura, height: altura).fill()
            var x: CGFloat = 0
            for imagem in imagens {
                imagem.draw(in: NSRect(x: x, y: altura - imagem.size.height, width: imagem.size.width, height: imagem.size.height))
                x += imagem.size.width + espaco
            }
            return true
        }
    }

    // MARK: - Montagem

    /// As duas imagens do bug: a validação desenhada agora e o print do card.
    @MainActor
    static func attachments(for result: ReportResult) -> [Attachment] {
        var anexos: [Attachment] = []
        let renderer = ImageRenderer(content: ReportBugValidationImage(result: result))
        renderer.scale = 2
        if let imagem = renderer.nsImage, let png = pngData(imagem) {
            anexos.append(Attachment(name: "validacao.png", png: png, size: imagem.size))
        }
        if let caminho = result.printPath, let imagem = NSImage(contentsOfFile: caminho), let png = pngData(imagem) {
            // Print muito grande vira uma imagem que o destino reduz: a largura
            // de exibição fica no HTML; o arquivo segue inteiro.
            anexos.append(Attachment(name: (caminho as NSString).lastPathComponent, png: png, size: imagem.size))
        }
        return anexos
    }

    /// Copia o bug da validação. Devolve o que foi para o clipboard, para a
    /// barra de status dizer.
    @MainActor
    @discardableResult
    static func copy(_ result: ReportResult, to pasteboard: NSPasteboard = .general) -> String {
        let anexos = attachments(for: result)
        let printName = result.printPath.map { ($0 as NSString).lastPathComponent }
        write(text: text(for: result, printName: printName), attachments: anexos, to: pasteboard)
        return anexos.count == 2 ? "Bug copiado com a validação e o print do Figma"
            : "Bug copiado com a validação (o card não tem print)"
    }

    @MainActor
    @discardableResult
    static func copyImages(_ result: ReportResult, to pasteboard: NSPasteboard = .general) -> String {
        writeImage(attachments(for: result), to: pasteboard)
            ? "Imagens do bug copiadas" : "Não foi possível desenhar as imagens do bug"
    }
}

/// O painel Validação como imagem para o bug: sempre claro, largura fixa, sem
/// rolagem nem controles. Cor nunca sozinha: ✓ e ✗ vêm com o texto.
struct ReportBugValidationImage: View {
    let result: ReportResult

    private let tinta = Color(red: 0.08, green: 0.08, blue: 0.26)
    private let secundario = Color(red: 0.35, green: 0.36, blue: 0.47)
    private let vermelho = Color(red: 0.75, green: 0.13, blue: 0.16)
    private let verde = Color(red: 0.13, green: 0.5, blue: 0.24)
    private let ambar = Color(red: 0.62, green: 0.4, blue: 0.0)
    private let linha = Color(red: 0.86, green: 0.87, blue: 0.9)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Validação")
                    .font(.system(size: 15, weight: .bold))
                Text(result.status == .missing ? "⚠︎ Não disparado" : "✗ Divergente")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(result.status == .missing ? ambar : vermelho)
            }
            Text(cabecalho)
                .font(.system(size: 12))
                .foregroundStyle(secundario)
                .fixedSize(horizontal: false, vertical: true)

            if result.status == .missing {
                Text("Nenhum disparo com esse fluxo, tela e detail no log. Esperado:")
                    .font(.system(size: 12))
                grade(result.expected.map { ($0.key, nil, $0.value, nil) })
            } else {
                grade(result.checks.map { ($0.field, $0.obtained ?? "ausente", $0.expected, $0.ok) })
            }
        }
        .foregroundStyle(tinta)
        .padding(18)
        .frame(width: 640, alignment: .leading)
        .background(Color.white)
    }

    private var cabecalho: String {
        var partes = [result.section, result.cardTitle]
        if let flowLabel = result.flowLabel { partes.append(flowLabel) }
        if !result.variation.isEmpty { partes.append(result.variation) }
        if let hora = result.matched?.time { partes.append("log \(hora)") }
        return partes.joined(separator: " · ")
    }

    private func grade(_ linhas: [(String, String?, String, Bool?)]) -> some View {
        let comObtido = linhas.contains { $0.1 != nil }
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text("")
                Text("Parâmetro")
                if comObtido { Text("Obtido") }
                Text("Esperado")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(secundario)
            .padding(.vertical, 4)
            Rectangle().fill(linha).frame(height: 1).gridCellUnsizedAxes(.horizontal)
            ForEach(Array(linhas.enumerated()), id: \.offset) { _, item in
                GridRow {
                    Text(item.3.map { $0 ? "✓" : "✗" } ?? "•")
                        .foregroundStyle(item.3.map { $0 ? verde : vermelho } ?? secundario)
                        .fontWeight(.bold)
                    Text(item.0).foregroundStyle(item.3 == false ? vermelho : tinta)
                    if comObtido { Text(item.1 ?? "") }
                    Text(item.2).foregroundStyle(item.3 == false ? tinta : secundario)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.vertical, 5)
                Rectangle().fill(linha).frame(height: 1).gridCellUnsizedAxes(.horizontal)
            }
        }
    }
}

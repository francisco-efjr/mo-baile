import AppKit
import SwiftUI

/// Tópico pedido à janela de Ajuda (⌘?, botão da toolbar, links internos).
@MainActor
@Observable
final class HelpNavigator {
    var topic: String = "comecando"
}

/// Janela "Ajuda do Mo baile" (LIB-2): guias por área à esquerda, o guia à
/// direita. Sem vidro próprio: a janela e a barra lateral já são do sistema.
struct HelpWindow: View {
    @Environment(HelpNavigator.self) private var navigator
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openWindow) private var openWindow

    @State private var busca = ""

    private var theme: any ThemeTokens { themeManager.current }

    private var documentos: [String: HelpDocument] {
        Dictionary(uniqueKeysWithValues: HelpLibrary.topics.compactMap { t in HelpLibrary.load(t).map { (t, $0) } })
    }

    var body: some View {
        @Bindable var navigator = navigator
        let docs = documentos
        NavigationSplitView {
            List(selection: Binding(get: { navigator.topic }, set: { if let t = $0 { navigator.topic = t } })) {
                Section("Começar") { linha("comecando", docs, icone: "flag", cor: theme.accent) }
                Section("Áreas") {
                    ForEach(WorkspaceTab.allCases) { area in
                        if visivel(area.rawValue, docs) {
                            linha(area.rawValue, docs, icone: area.symbolName, cor: area.categoryColor(theme))
                        }
                    }
                }
                Section("Suporte") { linha("relatar-problema", docs, icone: "ladybug", cor: theme.warning) }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            if let doc = docs[navigator.topic] {
                ScrollView {
                    HelpArticle(doc: doc, onGoTo: irPara)
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(DesignMetrics.Spacing.windowMargin)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.bgContent)
            } else {
                EmptyState(icon: "questionmark.circle", title: "Esta ajuda não veio no app",
                           text: "Reinstale o Mo baile ou leia os guias em github.com/francisco-efjr/mo-baile/tree/main/docs/ajuda.")
            }
        }
        .searchable(text: $busca, placement: .sidebar, prompt: "Buscar na Ajuda")
        .environment(\.openURL, OpenURLAction { url in
            if let topico = HelpLibrary.topic(from: url) { navigator.topic = topico; return .handled }
            if url.absoluteString == "mobaile://relato" { openWindow(id: "relato"); return .handled }
            return url.scheme == "https" ? .systemAction : .discarded
        })
        .frame(minWidth: 560, idealWidth: 760, minHeight: 420, idealHeight: 560)
    }

    private func visivel(_ topico: String, _ docs: [String: HelpDocument]) -> Bool {
        let termo = busca.trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty, let doc = docs[topico] else { return true }
        return doc.title.localizedCaseInsensitiveContains(termo) || doc.plainText.localizedCaseInsensitiveContains(termo)
    }

    @ViewBuilder
    private func linha(_ topico: String, _ docs: [String: HelpDocument], icone: String, cor: Color) -> some View {
        if visivel(topico, docs) {
            Label {
                Text(docs[topico]?.title ?? topico)
            } icon: {
                Image(systemName: icone).foregroundStyle(cor)
            }
            .tag(topico)
        }
    }

    private func irPara(_ area: WorkspaceTab) {
        appState.workspaceTab = area
        appState.selectedStepID = nil
        // `Window` de instância única: traz a janela principal à frente.
        openWindow(id: "main")
    }
}

/// O guia renderizado: cabeçalho, "Precisa de", e os blocos.
struct HelpArticle: View {
    @Environment(ThemeManager.self) private var themeManager
    let doc: HelpDocument
    var onGoTo: (WorkspaceTab) -> Void = { _ in }

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
                Text(doc.title).font(DSFont.title1).foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !doc.summary.isEmpty {
                    Text(doc.summary).font(DSFont.body).foregroundStyle(theme.labelSecondary)
                }
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    if !doc.needs.isEmpty {
                        Text("Precisa de: \(doc.needs)")
                            .font(DSFont.callout)
                            .foregroundStyle(theme.labelSecondary)
                    }
                    Spacer()
                    if let area = WorkspaceTab(rawValue: doc.area) {
                        Button("Ir para \(area.displayName)") { onGoTo(area) }
                    }
                }
            }
            ForEach(Array(doc.blocks.enumerated()), id: \.offset) { _, bloco in
                bloco_(bloco)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func bloco_(_ bloco: HelpDocument.Block) -> some View {
        switch bloco {
        case .heading(let t):
            Text(t).font(DSFont.title3).foregroundStyle(theme.labelPrimary)
                .padding(.top, DesignMetrics.Spacing.s3)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let t):
            inline(t).font(DSFont.body).foregroundStyle(theme.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let itens):
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
                ForEach(Array(itens.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s2) {
                        Text("•").foregroundStyle(theme.labelSecondary).accessibilityHidden(true)
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(DSFont.body).foregroundStyle(theme.labelPrimary)
        case .steps(let itens):
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
                ForEach(Array(itens.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s2) {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(theme.labelSecondary)
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(DSFont.body).foregroundStyle(theme.labelPrimary)
        case .code(let t):
            CodeBlock(text: t)
        case .note(let tipo, let t):
            HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s2) {
                Image(systemName: tipo == .warning ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                    .foregroundStyle(tipo == .warning ? theme.warning : theme.success)
                    .accessibilityHidden(true)
                inline(t).font(DSFont.body).foregroundStyle(theme.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
        }
    }

    /// Negrito, itálico, código e links; se o Markdown falhar, o texto cru.
    private func inline(_ texto: String) -> Text {
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var atributo = try? AttributedString(markdown: texto, options: opcoes) else { return Text(texto) }
        for run in atributo.runs where run.inlinePresentationIntent?.contains(.code) == true {
            atributo[run.range].font = DSFont.mono(12)
        }
        return Text(atributo)
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Estado da janela Relatar um Problema. Vive no app (não na janela): fechar
/// e reabrir durante a sessão não perde o rascunho.
@MainActor
@Observable
final class BugReportModel {
    enum Status: Equatable {
        case editing
        case waitingGitHub(folder: URL, truncated: Bool, attachments: Int)
        case failed(String)
    }

    var draft = BugReport.Draft()
    var errors: [BugReport.Draft.Field: String] = [:]
    var attachmentError: String?
    var status: Status = .editing
    /// Aparelho em uso quando a janela abriu, para o toggle "Aparelho e plataforma".
    var device: String?

    var environment: BugReport.Environment { .current(device: device) }

    /// Ao abrir a janela: a área ativa vira o valor inicial, se o rascunho está vazio.
    func prepare(area: WorkspaceTab, device: String?) {
        self.device = device
        if draft.isEmpty { draft.area = BugReport.Area(area) }
        if case .waitingGitHub = status {} else { status = .editing }
    }

    func add(_ urls: [URL]) {
        attachmentError = nil
        for url in urls {
            switch BugReport.validate(url, against: draft.attachments) {
            case .success(let anexo): draft.attachments.append(anexo)
            case .failure(let erro): attachmentError = erro.message
            }
        }
    }

    func remove(_ anexo: BugReport.Attachment) {
        draft.attachments.removeAll { $0 == anexo }
        attachmentError = nil
    }

    /// Valida; com erro, devolve o primeiro campo inválido para o foco.
    func validate() -> BugReport.Draft.Field? {
        let lista = draft.validationErrors()
        errors = Dictionary(lista.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        if let primeiro = lista.first {
            AccessibilityNotification.Announcement(primeiro.1).post()
            return primeiro.0
        }
        return nil
    }

    func copyMarkdown() {
        let texto = "# " + draft.title + "\n\n" + draft.markdown(environment)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }

    /// Caminho (a): grava a pasta do relato, abre o GitHub e revela a pasta.
    func openOnGitHub() -> BugReport.Draft.Field? {
        if let campo = validate() { return campo }
        let env = environment
        do {
            let pasta = try BugReport.saveFolder(draft, env: env)
            let (url, cortou) = draft.issueURL(env)
            if cortou { copyMarkdown() }
            guard NSWorkspace.shared.open(url) else {
                status = .failed("Não consegui abrir o navegador. Use Copiar Relato e abra github.com/francisco-efjr/mo-baile/issues/new.")
                return nil
            }
            if !draft.attachments.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([pasta]) }
            status = .waitingGitHub(folder: pasta, truncated: cortou, attachments: draft.attachments.count)
        } catch {
            status = .failed("Não consegui salvar o relato em Documentos › Mo baile › Relatos. Use Copiar Relato e abra github.com/francisco-efjr/mo-baile/issues/new.")
        }
        return nil
    }

    func reset() {
        draft = BugReport.Draft()
        errors = [:]
        attachmentError = nil
        status = .editing
    }
}

/// Janela Relatar um Problema (não modal, instância única).
struct BugReportWindow: View {
    @Environment(BugReportModel.self) private var model
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismissWindow) private var dismissWindow

    @FocusState private var foco: BugReport.Draft.Field?
    @State private var arrastando = false
    @State private var confirmarDescarte = false
    @State private var mostrarPrevia = false

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        VStack(spacing: 0) {
            switch model.status {
            case .waitingGitHub(let pasta, let cortou, let anexos):
                aguardando(pasta: pasta, cortou: cortou, anexos: anexos)
            default:
                formulario
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 520, idealHeight: 680)
        .background(theme.bgContent)
        .confirmationDialog("Descartar este relato?", isPresented: $confirmarDescarte) {
            Button("Descartar", role: .destructive) { model.reset(); dismissWindow(id: "relato") }
            Button("Continuar Editando", role: .cancel) {}
        } message: {
            Text("O texto e os anexos escolhidos serão perdidos.")
        }
    }

    // MARK: Formulário

    private var formulario: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s6) {
                    Text("Conte o que aconteceu. O relato vira uma issue no GitHub e entra na fila de correção.")
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    avisoPrivacidade

                    campo("Título", erro: model.errors[.title]) {
                        TextField("Resumo em uma frase. Ex.: A Rede HTTP fica vazia no Android", text: $model.draft.title)
                            .textFieldStyle(.roundedBorder)
                            .focused($foco, equals: .title)
                            .accessibilityLabel("Título, obrigatório")
                    }

                    campo("Em que parte aconteceu?", erro: nil) {
                        Picker("Em que parte aconteceu?", selection: $model.draft.area) {
                            ForEach(BugReport.Area.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    editor("O que você fez", texto: $model.draft.didWhat,
                           placeholder: "1. Conectei o aparelho\n2. Abri a Rede HTTP\n3. Cliquei em Configurar Proxy", erro: nil)
                    editor("O que você esperava", texto: $model.draft.expected,
                           placeholder: "Ex.: A tabela mostrar as requisições do app.", erro: nil)
                    editor("O que aconteceu", texto: $model.draft.happened,
                           placeholder: "Ex.: A tabela ficou vazia e a barra mostrou Proxy inativo.",
                           erro: model.errors[.happened], campoFoco: .happened)

                    anexos
                    informacoes
                }
                .padding(DesignMetrics.Spacing.windowMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            rodape
        }
    }

    private var avisoPrivacidade: some View {
        HStack(alignment: .top, spacing: DesignMetrics.Spacing.s3) {
            Image(systemName: "eye")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Este relato será público").font(DSFont.headline).foregroundStyle(theme.labelPrimary)
                Text("Qualquer pessoa pode ler o que você enviar, inclusive os anexos. Não inclua senhas, tokens, CPF, e-mails, dados de clientes nem tráfego de produção. Troque por valores fictícios ou cubra a informação antes de anexar.")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous).strokeBorder(theme.warning, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func campo(_ rotulo: String, erro: String?, @ViewBuilder _ conteudo: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            Text(rotulo).font(DSFont.headline).foregroundStyle(theme.labelPrimary)
            conteudo()
            if let erro { InlineError(title: erro) }
        }
    }

    private func editor(_ rotulo: String, texto: Binding<String>, placeholder: String, erro: String?,
                        campoFoco: BugReport.Draft.Field? = nil) -> some View {
        campo(rotulo, erro: erro) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: texto)
                    .font(DSFont.body)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(minHeight: 64)
                    .background(theme.bgGroup, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                    .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.field).strokeBorder(theme.separator))
                    .focused($foco, equals: campoFoco ?? .title)
                    .accessibilityLabel(campoFoco == .happened ? "\(rotulo), obrigatório" : rotulo)
                if texto.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var anexos: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            Text("Anexos (opcional)").font(DSFont.headline).foregroundStyle(theme.labelPrimary)
            VStack(spacing: DesignMetrics.Spacing.s2) {
                Text(arrastando ? "Solte para anexar" : "Arraste capturas, vídeos ou logs aqui")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                Button("Adicionar Arquivo…", action: escolherArquivos)
            }
            .frame(maxWidth: .infinity)
            .padding(DesignMetrics.Spacing.s5)
            .background(theme.bgGroup, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.card)
                    .strokeBorder(arrastando ? theme.selection : theme.separator, style: StrokeStyle(lineWidth: arrastando ? 2 : 1, dash: arrastando ? [] : [4]))
            )
            .dropDestination(for: URL.self) { urls, _ in
                model.add(urls)
                return true
            } isTargeted: { arrastando = $0 }

            ForEach(model.draft.attachments) { anexo in
                HStack {
                    Image(systemName: "doc").foregroundStyle(theme.labelSecondary).accessibilityHidden(true)
                    Text(anexo.name).lineLimit(1).truncationMode(.middle).help(anexo.name)
                    Text(ByteCountFormatter.string(fromByteCount: anexo.size, countStyle: .file))
                        .font(DSFont.callout).foregroundStyle(theme.labelSecondary)
                    Spacer()
                    Button("Remover") { model.remove(anexo) }
                        .controlSize(.small)
                        .accessibilityLabel("Remover \(anexo.name)")
                }
            }
            if let erro = model.attachmentError { InlineError(title: erro) }
            Text("Até 5 arquivos, 10 MB cada, 25 MB no total. Aceitamos png, jpg, gif, mp4, mov, txt, log, json, pdf e zip. Capturas e vídeos podem mostrar dados pessoais. Confira antes de anexar.")
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var informacoes: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            Text("Informações para ajudar a reproduzir (opcional)").font(DSFont.headline).foregroundStyle(theme.labelPrimary)
            Text("Nada é incluído sem a sua permissão. Marque o que quiser compartilhar e confira em Ver o que será enviado.")
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Versão do Mo baile e do macOS", isOn: $model.draft.includeVersion)
            Toggle("Modelo do Mac", isOn: $model.draft.includeMac)
            Toggle("Aparelho e plataforma em uso", isOn: $model.draft.includeDevice)
                .disabled(model.device == nil)
                .help(model.device == nil ? "Nenhum aparelho conectado agora." : "")
            DisclosureGroup("Ver o que será enviado", isExpanded: $mostrarPrevia) {
                CodeBlock(text: model.draft.markdown(model.environment))
            }
        }
    }

    private var rodape: some View {
        HStack(spacing: DesignMetrics.Spacing.s3) {
            if case .failed(let mensagem) = model.status {
                InlineError(title: "Não foi possível abrir o relato.", text: mensagem)
            } else {
                Spacer()
            }
            Button("Cancelar") {
                if model.draft.isEmpty { dismissWindow(id: "relato") } else { confirmarDescarte = true }
            }
            .keyboardShortcut(.cancelAction)
            Button("Copiar Relato") {
                model.copyMarkdown()
                AccessibilityNotification.Announcement("Relato copiado").post()
            }
            Button("Abrir no GitHub…") {
                if let campo = model.openOnGitHub() { foco = campo }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .mbProminentGlassButton()
            .help("Abre a issue preenchida no navegador. Precisa de uma conta gratuita no GitHub.")
        }
        .padding(.horizontal, DesignMetrics.Spacing.windowMargin)
        .padding(.vertical, DesignMetrics.Spacing.s4)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline) }
    }

    // MARK: Aguardando no GitHub

    private func aguardando(pasta: URL, cortou: Bool, anexos: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
            Label("Falta só enviar no GitHub", systemImage: "safari")
                .font(DSFont.title3)
                .foregroundStyle(theme.labelPrimary)
            Text("Abri a página com o texto preenchido. Revise e clique no botão verde para criar a issue.")
                .font(DSFont.body).foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if anexos > 0 {
                Text("Seus \(anexos) anexos estão na pasta do relato. Arraste os arquivos da janela do Finder para o campo de descrição no GitHub, depois envie.")
                    .font(DSFont.body).foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if cortou {
                Text("O relato é longo demais para ir no link. Copiei o texto completo: cole no campo de descrição no GitHub.")
                    .font(DSFont.body).foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Mostrar Pasta no Finder") { NSWorkspace.shared.activateFileViewerSelecting([pasta]) }
                Button("Abrir de Novo") { NSWorkspace.shared.open(model.draft.issueURL(model.environment).url) }
                Button("Copiar Relato") { model.copyMarkdown() }
                Spacer()
                Button("Concluir") { model.reset(); dismissWindow(id: "relato") }
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .padding(DesignMetrics.Spacing.windowMargin)
        .onAppear { AccessibilityNotification.Announcement("Falta só enviar no GitHub").post() }
    }

    private func escolherArquivos() {
        let painel = NSOpenPanel()
        painel.allowsMultipleSelection = true
        painel.canChooseDirectories = false
        painel.allowedContentTypes = BugReport.Limits.extensions.compactMap { UTType(filenameExtension: $0) }
        painel.message = "Escolha capturas, vídeos ou logs para anexar"
        if painel.runModal() == .OK { model.add(painel.urls) }
    }
}

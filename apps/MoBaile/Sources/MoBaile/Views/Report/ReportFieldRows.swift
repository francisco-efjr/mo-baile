import SwiftUI

/// Linhas chave e valor de um card, com adicionar, remover, regras e o
/// problema de cada campo ao lado dele. Usado no formulário do inspector e no
/// Quadro do editor de spec.
///
/// - Largura da chave pelo conteúdo; o valor quebra em até 4 linhas em vez de
///   cortar. Sem espaço para chave e valor lado a lado (~25 caracteres de
///   valor), a linha empilha (RE-05).
/// - Foco: "Adicionar" leva à linha nova, Return passa da chave ao valor e do
///   valor à próxima chave, Esc só termina o campo (RE-06).
/// - O erro só aparece depois que a pessoa sai do campo (ou tenta gravar) e
///   some assim que o valor fica válido (RE-02).
/// - Valor JSON (`items`) vira um resumo que abre a folha de JSON (RE-03).
struct ReportFieldRows: View {
    @Environment(ThemeManager.self) private var themeManager
    @Binding var fields: [ReportCardDraft.Field]
    let addLabel: String
    var issues: [UUID: ReportRowIssue] = [:]
    /// Mostra todos os problemas, tocados ou não (tentou gravar, ou o card veio
    /// assim do disco).
    var revealAll: Bool = false
    /// "card 3 · purchase": vai para o leitor de tela e para a folha de JSON.
    var context: String = ""
    /// Avisa quando um campo destas linhas ganha ou perde o foco.
    var onEditingChange: (Bool) -> Void = { _ in }

    private enum Foco: Hashable { case chave(UUID), valor(UUID) }
    @FocusState private var foco: Foco?
    @State private var tocados: Set<UUID> = []
    @State private var largura: CGFloat = 0
    @State private var jsonEmEdicao: JSONEmEdicao?

    private struct JSONEmEdicao: Identifiable { let id: UUID }

    /// Valor lado a lado só se ganhar pelo menos ~25 caracteres de SF Mono 11.
    private static let valorMinimo: CGFloat = 180
    /// Menu de regra, remover e os espaços entre eles.
    private static let acessorios: CGFloat = 24 + 24 + 3 * DesignMetrics.Spacing.s2

    /// SF Mono 11 avança ~6,6 pt por caractere; +16 do recuo do campo.
    private var larguraChave: CGFloat {
        let maior = fields.map { $0.key.count }.max() ?? 0
        return min(max(CGFloat(maior) * 6.6 + 16, 72), 168)
    }

    private var empilhado: Bool {
        largura > 0 && largura < larguraChave + Self.valorMinimo + Self.acessorios
    }

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            ForEach($fields) { $field in
                let posicao = fields.firstIndex { $0.id == field.id } ?? 0
                linha(field: $field, posicao: posicao)
                if empilhado && posicao < fields.count - 1 {
                    Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
                }
            }
            Button(action: adicionar) {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(PlainTextButtonStyle(theme: theme))
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { largura = geo.size.width }
                    .onChange(of: geo.size.width) { _, nova in largura = nova }
            }
        }
        .onChange(of: foco) { antigo, novo in
            switch antigo {
            case .chave(let id)?, .valor(let id)?: tocados.insert(id)
            case nil: break
            }
            onEditingChange(novo != nil)
        }
        .onExitCommand { foco = nil }
        .sheet(item: $jsonEmEdicao) { edicao in
            if let indice = fields.firstIndex(where: { $0.id == edicao.id }) {
                ReportJSONValueSheet(key: fields[indice].key, context: context, value: $fields[indice].value)
                    .environment(themeManager)
            }
        }
    }

    // MARK: - Linha

    @ViewBuilder
    private func linha(field: Binding<ReportCardDraft.Field>, posicao: Int) -> some View {
        let atual = field.wrappedValue
        let nome = atual.spokenName(position: posicao)
        let problema = visivel(atual.id)
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            if empilhado {
                HStack(spacing: DesignMetrics.Spacing.s2) {
                    chave(field, posicao: posicao, issue: problema?.key)
                    acessorios(field, nome: nome)
                }
                valor(field, nome: nome, issue: problema?.value, linhas: 1...6)
                    .padding(.leading, DesignMetrics.Spacing.s5)
            } else {
                HStack(alignment: .top, spacing: DesignMetrics.Spacing.s2) {
                    chave(field, posicao: posicao, issue: problema?.key)
                        .frame(width: larguraChave)
                    valor(field, nome: nome, issue: problema?.value, linhas: 1...4)
                    acessorios(field, nome: nome)
                }
            }
            ForEach(Array((problema?.messages ?? []).enumerated()), id: \.offset) { _, issue in
                FieldMessage(issue: issue)
                    .padding(.leading, DesignMetrics.Spacing.s2)
            }
        }
    }

    private func chave(_ field: Binding<ReportCardDraft.Field>, posicao: Int, issue: FieldIssue?) -> some View {
        let id = field.wrappedValue.id
        return TextField("Parâmetro", text: field.key)
            .textFieldStyle(.roundedBorder)
            .font(DSFont.mono(11))
            .controlSize(.small)
            .autocorrectionDisabled()
            .focused($foco, equals: .chave(id))
            .onSubmit { foco = .valor(id) }
            .dsFieldIssue(issue)
            .help(field.wrappedValue.key.count > 18 ? field.wrappedValue.key : "")
            .accessibilityLabel("Nome do parâmetro \(posicao + 1) de \(fields.count)\(contextoFalado)")
    }

    @ViewBuilder
    private func valor(
        _ field: Binding<ReportCardDraft.Field>, nome: String, issue: FieldIssue?, linhas: ClosedRange<Int>
    ) -> some View {
        let atual = field.wrappedValue
        if atual.isJSON {
            resumoJSON(atual, nome: nome, issue: issue)
        } else {
            TextField("Valor", text: field.value, axis: .vertical)
                .lineLimit(linhas)
                .textFieldStyle(.roundedBorder)
                .font(DSFont.mono(11))
                .controlSize(.small)
                .autocorrectionDisabled()
                .focused($foco, equals: .valor(atual.id))
                .onSubmit { foco = proximaChave(depois: atual.id).map(Foco.chave) }
                // O motor compara o texto exato: quebra de linha no valor não serve.
                .onChange(of: atual.value) { _, novo in
                    if novo.contains(where: \.isNewline) {
                        field.wrappedValue.value = novo.filter { !$0.isNewline }
                    }
                }
                .dsFieldIssue(issue)
                .help(atual.value.count > 25 ? atual.value : "")
                .accessibilityLabel("Valor de \(nome)\(contextoFalado)")
        }
    }

    private func resumoJSON(_ field: ReportCardDraft.Field, nome: String, issue: FieldIssue?) -> some View {
        let theme = themeManager.current
        let resumo = ReportJSONSummary.text(field.value)
        let invalido = ReportJSONSummary.shape(field.value) == .invalid
        return Button {
            jsonEmEdicao = JSONEmEdicao(id: field.id)
        } label: {
            HStack(spacing: DesignMetrics.Spacing.s2) {
                Image(systemName: "curlybraces")
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityHidden(true)
                Text(resumo)
                    .font(DSFont.mono(11))
                    .foregroundStyle(invalido ? theme.destructive : theme.accentText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(theme.labelTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DesignMetrics.Spacing.s3)
            .padding(.vertical, DesignMetrics.Spacing.s1)
            .frame(maxWidth: .infinity, minHeight: DesignMetrics.Heights.controlSmall, alignment: .leading)
            .background(theme.bgField, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
            .overlay {
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.field).strokeBorder(theme.separator)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFieldIssue(issue)
        .help("Editar o JSON de \(nome)")
        .accessibilityLabel("Valor JSON de \(nome)\(contextoFalado)")
        .accessibilityValue(resumo)
        .accessibilityHint("Abre o editor de JSON")
    }

    @ViewBuilder
    private func acessorios(_ field: Binding<ReportCardDraft.Field>, nome: String) -> some View {
        let id = field.wrappedValue.id
        if !field.wrappedValue.isJSON {
            ReportInsertRuleMenu(value: field.value, fieldName: nome) { foco = .valor(id) }
        }
        BarIconButton(icon: "minus.circle", label: "Remover \(nome)") {
            fields.removeAll { $0.id == id }
            tocados.remove(id)
        }
    }

    // MARK: - Estado

    private var contextoFalado: String { context.isEmpty ? "" : ", \(context)" }

    private func visivel(_ id: UUID) -> ReportRowIssue? {
        guard revealAll || tocados.contains(id) else { return nil }
        return issues[id]
    }

    private func proximaChave(depois id: UUID) -> UUID? {
        guard let i = fields.firstIndex(where: { $0.id == id }), i + 1 < fields.count else { return nil }
        return fields[i + 1].id
    }

    private func adicionar() {
        let novo = ReportCardDraft.Field(key: "", value: "")
        fields.append(novo)
        // O campo novo só existe depois deste ciclo de layout.
        DispatchQueue.main.async { foco = .chave(novo.id) }
    }
}

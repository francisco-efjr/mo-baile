import SwiftUI

/// Recaptura a tela e recarrega a hierarquia (⌘K).
///
/// Substitui o `DeviceDock`, que trazia "Voltar", "Home", "Girar" e
/// "Screenshot" — quatro botões com corpo vazio desde sempre.
///
/// Um botão de atualizar tem razão de existir enquanto o espelho depender de
/// `screencap`: cada captura leva mais de um segundo num aparelho físico, então
/// o espelho ao vivo anda perto de um quadro por segundo. Quando se quer ver o
/// estado exato de agora — e a árvore que corresponde a ele — pedir na hora é
/// mais direto que esperar a próxima volta do ciclo.
struct MirrorRefreshButton: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session

    @State private var atualizando = false

    var body: some View {
        Button {
            atualizar()
        } label: {
            Label(atualizando ? "Atualizando…" : "Atualizar", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
        .disabled(!podeAtualizar)
        .help("Recaptura a tela e recarrega a hierarquia (⌘K)")
        .accessibilityLabel("Atualizar espelho e hierarquia")
    }

    private var podeAtualizar: Bool {
        appState.isDeviceConnected && !atualizando
    }

    /// O estado de ocupado não é enfeite: a captura mais o dump passam de dois
    /// segundos, e sem ele o clique parece não ter feito nada — que foi o que
    /// levou a apertar o botão várias vezes e enfileirar capturas.
    private func atualizar() {
        guard !atualizando else { return }
        atualizando = true
        Task {
            await session.captureNow()
            atualizando = false
        }
    }
}

/// Popover de correlação: o último passo gravado e o que foi capturado.
///
/// O cartão antigo mostrava o passo com `String(describing:)` e, sem tráfego,
/// gerava a asserção para um endpoint fixo (`/v2/credito/simulacao`, status
/// 200) que não tinha nada a ver com o app em teste. Sem requisição capturada,
/// o botão agora fica desabilitado.
struct CorrelationPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let onClose: () -> Void

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.steps.isEmpty ? "Correlação" : "Correlação · passo \(appState.steps.count)")
                .font(DSFont.headline)
            Text(resumo)
                .font(DSFont.callout)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let passo = appState.steps.last {
                Text("AutomationStep(stepNum: \(passo.stepNum), actionType: \"\(passo.actionType)\", varName: \"\(passo.varName)\", strategy: \(passo.strategy.rawValue), platform: \(passo.platform.rawValue))")
                    .font(DSFont.mono(10.5))
                    .foregroundStyle(theme.labelSecondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.fillTertiary, in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Gerar Asserção de Contrato") {
                gerarAssercaoDeContrato()
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.httpRequests.isEmpty)
            .help(appState.httpRequests.isEmpty
                  ? "Capture ao menos uma requisição para gerar a asserção"
                  : "Insere no código uma asserção sobre a última requisição capturada")
        }
        .padding(14)
        .frame(width: 300)
    }

    private var resumo: String {
        let r = appState.httpRequests.count
        let e = appState.analyticsEvents.count
        let req = r == 1 ? "1 requisição" : "\(r) requisições"
        let ev = e == 1 ? "1 evento de analytics" : "\(e) eventos de analytics"
        return "Capturados até agora: \(req) e \(ev)."
    }

    private func gerarAssercaoDeContrato() {
        guard let lastReq = appState.httpRequests.last else { return }
        let path = URL(string: lastReq.url)?.path ?? lastReq.url
        let cleanPath = path.isEmpty ? "/" : path
        var snippet = """

        # Asserção de contrato de API correlacionada (MITM)
        response = self.network_interceptor.wait_for_request('\(cleanPath)', timeout=5.0)

"""
        if let status = lastReq.statusCode {
            snippet += "        assert response.status_code == \(status)\n\n"
        } else {
            snippet += "        assert response is not None\n\n"
        }
        appState.actionsCode += snippet
        appState.statusMessage = "Asserção de contrato gerada e inserida no código"
    }
}

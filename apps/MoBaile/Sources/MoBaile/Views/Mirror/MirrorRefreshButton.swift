import SwiftUI

/// Recaptura a tela e recarrega a hierarquia.
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
        FluidPillButton(
            text: atualizando ? "Atualizando…" : "Atualizar",
            icon: "arrow.clockwise",
            style: podeAtualizar ? .secondary : .disabled
        ) {
            atualizar()
        }
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

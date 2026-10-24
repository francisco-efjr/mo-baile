import Foundation

/// O que o cartão "Próximo passo" da tela Início mostra. Um passo só, como no
/// estado sem aparelho (FLU-3): dois botões em destaque não dizem por onde
/// começar.
///
/// Quem decide o que instalar primeiro é o motor (`setup.check`, campo
/// `next_step`). Aqui entram só os casos em que o motor não pode responder
/// (ele não subiu) e os que dependem do aparelho, que são da sessão.
enum HomeNextStep: Equatable {
    /// O motor não sobe por falta de um Python que sirva.
    case installPython(detail: String)
    /// O motor parou por outro motivo; Reiniciar Motor é o que resta.
    case engineStopped(detail: String)
    /// Subindo ou ainda sem a primeira checagem.
    case checking
    /// Falta instalar algo obrigatório (escolhido pelo motor).
    case install(EngineDTO.SetupNextStep)
    /// Tudo instalado, nenhum aparelho.
    case connectDevice
    /// Tudo instalado e um aparelho na sessão.
    case connected(name: String)

    static func pick(
        engineStatus: EngineStatus,
        lastError: String?,
        setup: EngineDTO.Setup?,
        deviceName: String?
    ) -> HomeNextStep {
        switch engineStatus {
        case .stopped(let motivo):
            if EngineLocator.isPythonProblem(motivo) || EngineLocator.isPythonProblem(lastError) {
                return .installPython(detail: motivo)
            }
            return .engineStopped(detail: motivo)
        case .starting, .restarting, .restartRequested:
            return .checking
        case .running:
            break
        }
        guard let setup else { return .checking }
        if let proximo = setup.nextStep { return .install(proximo) }
        if let deviceName { return .connected(name: deviceName) }
        return .connectDevice
    }
}

/// Em que área o app abre.
///
/// Na primeira vez, sempre no Início. Depois, no Início só quando ele tem o
/// que dizer: motor parado ou nenhum aparelho. Com aparelho conectado, vai
/// direto ao trabalho, em Page Objects.
enum LaunchDestination {
    static let seenKey = "mobaile.inicioVisto"

    /// `nil`: fica onde está. A pessoa que já trocou de área durante a
    /// abertura (pela paleta, por atalho) não é levada de volta.
    static func pick(firstRun: Bool, phase: LaunchPhase, deviceConnected: Bool, current: WorkspaceTab) -> WorkspaceTab? {
        guard current == .pageObjects else { return nil }
        switch phase {
        case .startingEngine, .scanning:
            return nil
        case .failed:
            return .home
        case .ready:
            if firstRun || !deviceConnected { return .home }
            return nil
        }
    }
}

/// Textos da tela Início.
enum HomeCopy {
    static let note = "Depois de instalado, tudo roda nesta máquina, sem internet."

    /// Subtítulo da janela.
    static func subtitle(setup: EngineDTO.Setup?, engineRunning: Bool) -> String {
        guard engineRunning else { return "Motor parado" }
        guard let setup else { return "Conferindo o ambiente…" }
        return pendingText(setup.pending) ?? "Tudo pronto"
    }

    static func pendingText(_ n: Int) -> String? {
        switch n {
        case ..<1: return nil
        case 1: return "Falta instalar 1 item"
        default: return "Faltam \(n) itens para instalar"
        }
    }

    /// A frase sob o título.
    static func summary(_ passo: HomeNextStep, pending: Int = 1) -> String {
        switch passo {
        case .installPython:
            return "Antes de tudo, o motor precisa de um Python. Depois dele, o Mo baile confere o resto sozinho."
        case .engineStopped:
            return "O motor parou. Sem ele, o Mo baile não consegue conferir o ambiente."
        case .checking:
            return "Conferindo o que está instalado…"
        case .install(let proximo):
            if pending <= 1 { return "Falta instalar 1 item: \(proximo.label)." }
            return "Faltam \(pending) itens para instalar. Comece por este: \(proximo.label)."
        case .connectDevice:
            return "Tudo o que é obrigatório está instalado. Conecte um aparelho ou abra um simulador."
        case .connected(let nome):
            return "Tudo pronto. \(nome) conectado."
        }
    }

    /// Uma linha sobre o que cada área faz.
    static func areaSummary(_ area: WorkspaceTab) -> String {
        switch area {
        case .home: return ""
        case .pageObjects: return "Espelho, hierarquia e o código Appium de cada toque."
        case .network: return "Tráfego HTTP do aparelho, e HTTPS do app em debug."
        case .analytics: return "Eventos do Firebase Analytics em tempo real."
        case .report: return "Audita os eventos contra a spec dos cards."
        }
    }

    static func platformName(_ id: String) -> String {
        switch id {
        case "ios": return "iOS"
        case "android": return "Android"
        default: return ""
        }
    }

    /// Botão da linha do Ambiente que leva a uma página, no verbo certo.
    static func linkTitle(_ link: String) -> String {
        link.hasPrefix("macappstore:") ? "Abrir na App Store…" : "Abrir Página…"
    }
}

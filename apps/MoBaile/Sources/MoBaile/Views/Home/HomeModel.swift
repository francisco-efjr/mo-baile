import AppKit
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

/// Textos da tela Início e da tela Ambiente.
enum HomeCopy {
    static let note = "Depois de instalado, tudo roda nesta máquina, sem internet."
    static let homeNote = "Tudo roda nesta máquina, sem internet."
    static let cableHint = "Aparelho físico: conecte pelo cabo. No iPhone, toque em Confiar; no Android, "
        + "ligue a depuração USB. Ele aparece aqui sozinho."

    /// Subtítulo da janela no Início: o estado do ambiente em poucas palavras.
    static func homeSubtitle(_ home: EngineDTO.HomeSummary?, engineRunning: Bool) -> String {
        guard engineRunning else { return "Motor parado" }
        guard let home else { return "Conferindo…" }
        if home.isFirstRun { return "Primeira vez nesta máquina" }
        return environmentPill(home.environment)
    }

    /// Texto da cápsula do ambiente: "Ambiente pronto" ou "Ambiente: 3 de 4 prontos".
    static func environmentPill(_ ambiente: EngineDTO.HomeEnvironment) -> String {
        ambiente.isReady ? "Ambiente pronto" : "Ambiente: \(ambiente.ready) de \(ambiente.total) prontos"
    }

    /// "Bom dia" até 11:59, "Boa tarde" até 17:59, "Boa noite" depois, com o
    /// primeiro nome do usuário do macOS quando há.
    static func greeting(at data: Date = Date(), fullName: String = NSFullUserName()) -> String {
        let hora = Calendar.current.component(.hour, from: data)
        let saudacao = hora < 12 ? "Bom dia" : (hora < 18 ? "Boa tarde" : "Boa noite")
        guard let nome = fullName.split(separator: " ").first, !nome.isEmpty else { return saudacao }
        return "\(saudacao), \(nome)"
    }

    /// Data de um recente: "hoje 9:40", "ontem", dia da semana, depois a data.
    static func relativeDate(_ data: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(data, inSameDayAs: now) {
            return "hoje " + data.formatted(.dateTime.hour().minute())
        }
        if let ontem = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(data, inSameDayAs: ontem) {
            return "ontem"
        }
        let dias = calendar.dateComponents([.day], from: calendar.startOfDay(for: data), to: calendar.startOfDay(for: now)).day ?? 99
        if dias < 7 {
            return data.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR")))
                .replacingOccurrences(of: ".", with: "")
        }
        return data.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Locale(identifier: "pt_BR")))
    }

    /// Segunda linha de um alvo: "Simulador iOS · desligado · tudo pronto".
    static func targetDetail(_ alvo: EngineDTO.HomeTarget) -> String {
        let tipo: String
        switch alvo.kind {
        case "simulator": tipo = "Simulador iOS"
        case "emulator": tipo = "Emulador Android"
        default: tipo = alvo.platform == "ios" ? "iPhone pelo cabo" : "Aparelho Android pelo cabo"
        }
        var partes = [tipo, alvo.connected ? "conectado" : (alvo.running ? "ligado" : "desligado")]
        if alvo.capabilities.tap && alvo.blockedBy.isEmpty { partes.append("tudo pronto") }
        return partes.joined(separator: " · ")
    }

    /// Botão de um alvo: liga o que está desligado, usa o que já está ligado.
    static func targetAction(_ alvo: EngineDTO.HomeTarget) -> String {
        if alvo.running { return "Usar Este" }
        return alvo.platform == "ios" ? "Iniciar Simulador" : "Iniciar Emulador"
    }

    /// Aviso na linha do alvo quando uma pendência o limita.
    static func limitation(_ alvo: EngineDTO.HomeTarget, pending: EngineDTO.HomePending) -> String {
        let efeito = pending.blocks.first { $0.platform == alvo.platform }?.effect ?? pending.title
        if alvo.capabilities.mirror && !alvo.capabilities.tap {
            return "Só espelho: falta \(pending.title) para \(efeito)."
        }
        return "Falta \(pending.title): \(efeito)."
    }

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
        case .home, .environment: return ""
        case .pageObjects: return "Cada toque vira locator e método Appium em Python."
        case .network: return "Tráfego do aparelho, com credenciais redigidas."
        case .analytics: return "Eventos do Firebase em tempo real."
        case .report: return "Eventos contra a spec do Figma. Sem aparelho."
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

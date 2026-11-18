import AppKit
import os
import UserNotifications

/// Notificação do macOS quando sai versão nova (ADR 0008): uma por versão, com
/// os botões Atualizar e Lembrar Amanhã. A faixa no topo da janela continua lá;
/// a notificação serve para quem está com o Mo baile atrás de outra janela.
///
/// O macOS pede permissão na primeira notificação. Sem permissão, fica só a
/// faixa.
@MainActor
final class UpdateNotifier: NSObject, UpdateNotifying {
    static let shared = UpdateNotifier()

    static let category = "mobaile.update.available"
    static let actionUpdate = "mobaile.update.install"
    static let actionSnooze = "mobaile.update.snooze"

    private static let log = Logger(subsystem: "com.qa.mobaile", category: "update")
    private let delegado = CentralDelegate()
    private weak var updates: UpdateState?
    private var configured = false
    /// Clique que chegou antes de a janela ligar o estado (app aberto pela
    /// própria notificação).
    private var pendingAction: String?

    /// Só o app empacotado tem central de notificações: no `swift run` e nos
    /// testes, `UNUserNotificationCenter.current()` derruba o processo.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    /// Liga ao estado que a janela usa e entrega o clique que estava esperando.
    func attach(_ updates: UpdateState) {
        self.updates = updates
        updates.notifier = self
        if let acao = pendingAction {
            pendingAction = nil
            handle(action: acao)
        }
    }

    /// Registra o delegado e os botões. Precisa rodar antes de o app terminar
    /// de abrir, para receber o clique que abriu o app. Chamar de novo não faz nada.
    func configure() {
        guard Self.isAvailable, !configured else { return }
        configured = true
        let central = UNUserNotificationCenter.current()
        central.delegate = delegado
        let atualizar = UNNotificationAction(identifier: Self.actionUpdate, title: "Atualizar", options: [.foreground])
        let depois = UNNotificationAction(identifier: Self.actionSnooze, title: "Lembrar Amanhã", options: [])
        central.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [atualizar, depois], intentIdentifiers: [], options: []),
        ])
    }

    static func content(_ release: ReleaseInfo, installed: String, canInstall: Bool) -> (title: String, body: String) {
        let versao = release.version?.description ?? release.tagName
        let corpo = canInstall
            ? "Você está na \(installed). Clique em Atualizar: o Mo baile baixa a versão nova e abre de novo já atualizado."
            : "Você está na \(installed). Abra o Mo baile para baixar a versão nova."
        return ("Mo baile \(versao) disponível", corpo)
    }

    func notifyAvailable(_ release: ReleaseInfo, installed: String, canInstall: Bool) {
        guard Self.isAvailable else { return }
        let (titulo, corpo) = Self.content(release, installed: installed, canInstall: canInstall)
        let tag = release.tagName
        Task {
            let central = UNUserNotificationCenter.current()
            do {
                guard try await central.requestAuthorization(options: [.alert, .sound]) else {
                    Self.log.notice("notificação de versão nova sem permissão; fica só a faixa")
                    return
                }
                let conteudo = UNMutableNotificationContent()
                conteudo.title = titulo
                conteudo.body = corpo
                conteudo.sound = .default
                conteudo.categoryIdentifier = Self.category
                conteudo.userInfo = ["tag": tag]
                try await central.add(UNNotificationRequest(identifier: "mobaile.update.\(tag)", content: conteudo, trigger: nil))
                Self.log.notice("notificação de versão nova enviada: \(tag, privacy: .public)")
            } catch {
                Self.log.error("notificação de versão nova falhou: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    fileprivate func handle(action: String) {
        guard updates != nil || action == UNNotificationDefaultActionIdentifier else {
            pendingAction = action
            return
        }
        switch action {
        case Self.actionUpdate:
            NSApp.activate()
            updates?.update()
        case Self.actionSnooze:
            updates?.snooze()
        case UNNotificationDefaultActionIdentifier:
            NSApp.activate()
        default:
            break
        }
    }
}

/// Delegado da central. Ela chama fora da main thread; a ação volta para o
/// `UpdateNotifier` no MainActor.
private final class CentralDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let acao = response.actionIdentifier
        completionHandler()
        Task { @MainActor in UpdateNotifier.shared.handle(action: acao) }
    }

    /// Com o app na frente, mostra também: a notificação sai uma vez por versão.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

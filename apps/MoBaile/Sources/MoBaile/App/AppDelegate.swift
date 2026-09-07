import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Preenchido pela cena ao aparecer. Serve so para o encerramento ordenado.
    var session: EngineSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app name in menu bar and dock
        NSApp.setActivationPolicy(.regular)
        
        // Set dock icon from assets
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
        
        // Customize main menu
        configureMainMenu()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    
    /// Encerramento ordenado.
    ///
    /// Importa mais do que parece: ao sair, o motor desfaz a configuracao de
    /// proxy do aparelho. Sem isso o Android fica apontando para uma porta
    /// morta e perde acesso a rede, que e o efeito colateral mais reclamado
    /// nesse tipo de ferramenta.
    ///
    /// A limpeza e assincrona, entao a saida e adiada com `.terminateLater` e
    /// liberada quando terminar. Bloquear a main thread com semaforo aqui seria
    /// deadlock garantido: a tarefa de limpeza precisa exatamente da thread que
    /// o semaforo estaria segurando.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }

        Task { @MainActor in
            await session.disconnect()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        // Rede de seguranca: se a limpeza travar, a aplicacao sai assim mesmo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
    
    private func configureMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        
        // Update the app menu title from default to "Mo baile"
        if let appMenu = mainMenu.items.first {
            appMenu.title = "Mo baile"
            if let submenu = appMenu.submenu {
                submenu.title = "Mo baile"
                for item in submenu.items {
                    if item.title.contains("Hide") && !item.title.contains("Others") {
                        item.title = "Ocultar Mo baile"
                    } else if item.title.contains("Quit") {
                        item.title = "Encerrar Mo baile"
                    } else if item.title.contains("About") {
                        item.title = "Sobre o Mo baile"
                    }
                }
            }
        }
    }
}

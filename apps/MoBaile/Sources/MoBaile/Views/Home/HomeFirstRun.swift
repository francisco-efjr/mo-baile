import AppKit
import SwiftUI

/// Início numa máquina zerada (`maquete/PrimeiraVez.dc.html`): três passos.
/// Aparece enquanto o motor diz `first_run` (nenhuma plataforma serve) e troca
/// sozinha para o uso diário quando a primeira fica pronta.
struct HomeFirstRunContent: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    let home: EngineDTO.HomeSummary

    @State private var erroInstalacao: String?

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: DesignMetrics.Spacing.s9) {
            VStack(spacing: DesignMetrics.Spacing.s5) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("Boas-vindas ao Mo baile")
                    .font(DSFont.largeTitle.weight(.bold))
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Espelho, Page Objects, rede, analytics e relatório de tagueamento num lugar só. "
                     + "Vamos deixar esta máquina pronta em três passos.")
                    .font(DSFont.title3.weight(.regular))
                    .foregroundStyle(theme.labelSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                passo(1, feito: true, titulo: "Motor pronto") {
                    Text("Python \(home.python.version) encontrado, com Pillow e requests.")
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelSecondary)
                }
                divisoria(theme)
                passo(2, feito: false, titulo: "Para qual plataforma você testa?") {
                    VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                        Text("Instalamos só o que ela precisa. Dá para adicionar a outra depois.")
                            .font(DSFont.body)
                            .foregroundStyle(theme.labelSecondary)
                        if home.platforms.count == 2 {
                            HomePairLayout(trailingFraction: 0.5, minSideBySide: 520, spacing: DesignMetrics.Spacing.s5) {
                                cartoes
                            }
                        } else {
                            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) { cartoes }
                        }
                        if let erroInstalacao {
                            InlineError(title: "Não deu para abrir o Terminal.", text: erroInstalacao)
                        }
                    }
                }
                divisoria(theme)
                passo(3, feito: false, titulo: "Conectar um aparelho") {
                    Text("Um simulador, um emulador ou um aparelho pelo cabo. Ele aparece na barra de cima.")
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelSecondary)
                }
                .opacity(0.42)
                .accessibilityHint("Disponível depois do passo 2")
            }
            .dsCard(padding: 0)

            HStack(spacing: DesignMetrics.Spacing.s5) {
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                    Text("Quer explorar antes?")
                        .font(DSFont.headline)
                        .foregroundStyle(theme.labelPrimary)
                    Text("O Relatório funciona agora, sem instalar nada e sem aparelho.")
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                }
                Spacer(minLength: DesignMetrics.Spacing.s4)
                Button("Abrir Relatório…") { ir(.report) }
            }
            .padding(DesignMetrics.Spacing.s7)
            .overlay {
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.card)
                    .strokeBorder(theme.separatorStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .accessibilityHidden(true)
            }

            HStack(spacing: DesignMetrics.Spacing.s2) {
                Text("Tudo roda nesta máquina, sem internet. Os detalhes de cada componente ficam em")
                    .foregroundStyle(theme.labelSecondary)
                Button("Ambiente") { ir(.environment) }
                    .buttonStyle(PlainTextButtonStyle(theme: theme))
            }
            .font(DSFont.callout)
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, DesignMetrics.Spacing.s10)
        .padding(.top, 40)
        .padding(.bottom, DesignMetrics.Spacing.s10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var cartoes: some View {
        ForEach(home.platforms) { plataforma in
            HomePlatformCard(plataforma: plataforma, sugerida: plataforma.platform == home.suggestedPlatform,
                             install: instalar)
        }
    }

    private func passo<Conteudo: View>(
        _ numero: Int, feito: Bool, titulo: String, @ViewBuilder conteudo: () -> Conteudo
    ) -> some View {
        let theme = themeManager.current
        return HStack(alignment: .top, spacing: DesignMetrics.Spacing.s6) {
            ZStack {
                Circle().fill(feito ? theme.success : theme.fillSecondary)
                if feito {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                } else {
                    Text("\(numero)")
                        .font(DSFont.callout.weight(.semibold))
                        .foregroundStyle(theme.labelPrimary)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
                Text(titulo)
                    .font(DSFont.title3)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                conteudo()
            }
            Spacer(minLength: 0)
        }
        .padding(DesignMetrics.Spacing.s7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Passo \(numero)\(feito ? ", pronto" : "")")
    }

    private func divisoria(_ theme: any ThemeTokens) -> some View {
        Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
    }

    private func ir(_ area: WorkspaceTab) {
        appState.selectedStepID = nil
        appState.workspaceTab = area
    }

    private func instalar(_ alvo: String) {
        do {
            try SetupInstaller.openInTerminal(target: alvo, python: home.python.path)
            erroInstalacao = nil
            appState.statusMessage = "Instalação aberta no Terminal"
        } catch {
            erroInstalacao = error.localizedDescription
        }
    }
}

/// Uma plataforma na Primeira vez: o que já foi achado, o que falta e o
/// botão que roda o mesmo instalador do Ambiente. A sugerida pelo motor (a
/// mais perto de pronta) vem com a borda do destaque.
struct HomePlatformCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let plataforma: EngineDTO.HomePlatform
    let sugerida: Bool
    let install: (String) -> Void

    private var nome: String { plataforma.platform == "ios" ? "iOS" : "Android" }

    var body: some View {
        let theme = themeManager.current
        let cor = PlatformIdentity.color(plataforma.platform == "ios" ? .ios : .android)
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            HStack(spacing: DesignMetrics.Spacing.s3) {
                Image(systemName: plataforma.platform == "ios" ? "iphone.gen3" : "candybarphone")
                    .foregroundStyle(cor)
                    .accessibilityHidden(true)
                Text(nome)
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
            }
            if !plataforma.found.isEmpty {
                HStack(spacing: DesignMetrics.Spacing.s2) {
                    ForEach(plataforma.found, id: \.self) { achado in
                        Text(achado)
                            .font(DSFont.footnote.weight(.semibold))
                            .foregroundStyle(theme.success)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.successTint, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.chip))
                    }
                }
            }
            Text(plataforma.missing.isEmpty
                 ? "Tudo pronto para \(nome)."
                 : "Falta: \(plataforma.missing.joined(separator: ", ")).")
                .font(DSFont.callout)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let link = plataforma.link, let url = URL(string: link) {
                Button(HomeCopy.linkTitle(link)) { NSWorkspace.shared.open(url) }
                    .modifier(DestaqueSe(sugerida))
            } else if !plataforma.ready {
                Button("Preparar \(nome)…") { install(plataforma.install) }
                    .modifier(DestaqueSe(sugerida))
                    .help("Abre o instalador no Terminal (instalar-mac.sh \(plataforma.install))")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DesignMetrics.Spacing.s6)
        .background(theme.fillQuaternary, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous)
                .strokeBorder(sugerida ? theme.accent : theme.separator,
                              lineWidth: sugerida ? DesignMetrics.DiagnosticCard.recommendedStroke : DesignMetrics.hairline)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(nome)\(sugerida ? ", sugerida" : "")")
    }
}

/// Botão padrão (preenchido) só no cartão sugerido.
private struct DestaqueSe: ViewModifier {
    let ativo: Bool
    init(_ ativo: Bool) { self.ativo = ativo }

    func body(content: Content) -> some View {
        if ativo {
            content.buttonStyle(.borderedProminent)
        } else {
            content
        }
    }
}

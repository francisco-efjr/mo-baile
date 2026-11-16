import SwiftUI

/// Ajustes › Paletas: a galeria de `docs/design/paletas/Paletas Alternativas.dc.html`.
///
/// Um cartão por paleta: a mini-janela de prévia, desenhada com os componentes
/// de verdade nas cores da paleta, o nome, o designer de referência, as 11
/// amostras e as checagens de contraste. "Usar Paleta" aplica o tema na hora.
struct PaletteGallery: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paletas")
                        .font(DSFont.title1.weight(.bold))
                    Text("Oito temas para o Mo baile, quatro claros e quatro escuros, inspirados em designers de interiores, mais um extra. Cada paleta troca as mesmas cores da interface, tem variação de alto contraste e passa nas checagens de contraste e de distância entre o destaque e as cores de estado. Uma paleta clara ou escura define a aparência do app.")
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                grupo("Padrão", [PaletteSpec.praiaDisplay])
                grupo("Claros", PaletteSpec.all.filter { $0.mode == .light && !$0.extra })
                grupo("Escuros", PaletteSpec.all.filter { $0.mode == .dark && !$0.extra })
                grupo("Extra", PaletteSpec.all.filter(\.extra))
            }
            .padding(24)
        }
        .background(theme.bgContentAlt)
    }

    private func grupo(_ titulo: String, _ paletas: [PaletteSpec]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(titulo)
                .font(DSFont.title2)
                .accessibilityAddTraits(.isHeader)
            ForEach(paletas) { PaletteCard(spec: $0) }
        }
    }
}

/// Cartão de uma paleta.
struct PaletteCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let spec: PaletteSpec

    private var emUso: Bool { themeManager.paletteID == spec.id }

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            PalettePreview(spec: spec)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(spec.name).font(DSFont.title3)
                            Text(spec.designer).font(DSFont.callout).foregroundStyle(theme.labelSecondary)
                        }
                        Text(spec.ref)
                            .font(DSFont.callout)
                            .foregroundStyle(theme.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(Motion.crossfade) { themeManager.setPalette(spec.id) }
                    } label: {
                        Label(emUso ? "Em Uso" : "Usar Paleta", systemImage: emUso ? "checkmark" : "paintpalette")
                    }
                    .controlSize(.small)
                    .disabled(emUso)
                    .help(emUso ? "Esta é a paleta em uso" : "Aplica a paleta \(spec.name) no app")
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 11), spacing: 4) {
                    ForEach(spec.swatches, id: \.name) { amostra in
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: amostra.hex))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
                                .frame(height: 28)
                            Text(amostra.name)
                                .font(.system(size: 9))
                                .foregroundStyle(theme.labelSecondary)
                                .lineLimit(1)
                            Text(amostra.hex)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(theme.labelTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(amostra.name), \(amostra.hex)")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], alignment: .leading, spacing: 4) {
                    ForEach(spec.checks) { check in
                        HStack(spacing: 6) {
                            Image(systemName: check.ok ? "checkmark" : "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(check.ok ? theme.success : theme.destructive)
                            Text(check.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(check.label)
                                .font(DSFont.mono(11).monospacedDigit())
                        }
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(check.ok ? "passa" : "não passa")
                    }
                }
            }
            .padding(16)
        }
        .background(theme.bgContent)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous)
                .strokeBorder(emUso ? theme.accent : theme.separatorStrong, lineWidth: emUso ? 2 : 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paleta \(spec.name), \(spec.designer)")
        .accessibilityValue(emUso ? "em uso" : "")
    }
}

/// A mini-janela do cartão, nas cores da paleta: sidebar com o item escolhido,
/// toolbar com segmentado e Rodar, três requisições, chips e a barra de status.
struct PalettePreview: View {
    let spec: PaletteSpec

    private var tema: any ThemeTokens {
        spec.id == PaletteSpec.praiaID ? PraiaLightTheme() : PaletteTheme(spec: spec)
    }

    var body: some View {
        let tema = self.tema
        let gerente = ThemeManager(preview: tema)
        Conteudo(spec: spec)
            .environment(gerente)
            .environment(\.colorScheme, tema.isDark ? .dark : .light)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color(hex: spec.desk))
            .accessibilityHidden(true)
    }

    private struct Conteudo: View {
        @Environment(ThemeManager.self) private var themeManager
        let spec: PaletteSpec

        var body: some View {
            let t = themeManager.current
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        ForEach(["#FF5F57", "#FEBC2E", "#28C840"], id: \.self) { cor in
                            Circle().fill(Color(hex: cor)).frame(width: 10, height: 10)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)
                    Text("Sessão")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.labelTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    item("Espelho", "hand.tap", t.cat1, selecionado: false, t)
                    item("Page Objects", "chevron.left.forwardslash.chevron.right", t.cat2, selecionado: false, t)
                    item("Rede HTTP", "network", t.onAccent, selecionado: true, t)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .frame(width: 140, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(t.bgSidebar)
                .overlay(alignment: .trailing) { Rectangle().fill(t.separator).frame(width: 0.5) }

                // Conteúdo
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Rede HTTP").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        segmentado(t)
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill").font(.system(size: 9))
                            Text("Rodar")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(t.onAccent)
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(Capsule().fill(t.accent))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .overlay(alignment: .bottom) { Rectangle().fill(t.separator).frame(height: 0.5) }

                    VStack(spacing: 0) {
                        linha("GET", t.httpGet, "/api/v2/user", "200", t.success, destaque: false, t)
                        linha("POST", t.httpPost, "/collect/events", "302", t.warning, destaque: true, t)
                        linha("DELETE", t.destructive, "/cart/items/42", "404", t.destructive, destaque: false, t)
                        HStack(spacing: 6) {
                            TypeChip(type: .view)
                            TypeChip(type: .button)
                            Text("XCUIElementTypeButton")
                        }
                        .foregroundStyle(t.labelSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxHeight: .infinity)
                    .background(t.bgContent)

                    HStack {
                        StatusIndicator(status: .ok, label: "WDA 8100")
                        Spacer()
                        Text("Exportar HAR…").foregroundStyle(t.accentText)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator).frame(height: 0.5) }
                }
                .frame(maxWidth: .infinity)
            }
            .font(.system(size: 12))
            .foregroundStyle(t.labelPrimary)
            .frame(height: 236)
            .background(t.bgWindow)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separatorStrong, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 12)
        }

        private func item(_ titulo: String, _ icone: String, _ cor: Color, selecionado: Bool, _ t: any ThemeTokens) -> some View {
            HStack(spacing: 7) {
                Image(systemName: icone).font(.system(size: 11)).foregroundStyle(cor).frame(width: 14)
                Text(titulo).lineLimit(1)
            }
            .foregroundStyle(selecionado ? t.onAccent : t.labelPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(selecionado ? t.selection : .clear))
        }

        private func segmentado(_ t: any ThemeTokens) -> some View {
            HStack(spacing: 0) {
                Text("iOS")
                    .padding(.horizontal, 8)
                    .frame(height: 16)
                    .background(Capsule().fill(t.bgControl).shadow(color: .black.opacity(0.12), radius: 1, y: 0.5))
                Text("Android").padding(.horizontal, 8).frame(height: 16)
            }
            .font(.system(size: 11))
            .padding(2)
            .background(Capsule().fill(t.fillSecondary))
        }

        private func linha(_ metodo: String, _ corMetodo: Color, _ caminho: String, _ status: String, _ corStatus: Color,
                           destaque: Bool, _ t: any ThemeTokens) -> some View {
            HStack(spacing: 8) {
                Text(metodo).fontWeight(.semibold).foregroundStyle(corMetodo).frame(width: 52, alignment: .leading)
                Text(caminho).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                Text(status).foregroundStyle(corStatus).frame(width: 36, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(destaque ? t.selectionContent : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator).frame(height: 0.5) }
        }
    }
}

extension PaletteSpec {
    /// A Praia no formato de paleta, só para o cartão "Padrão" da galeria
    /// (amostras e checagens da versão clara). O tema em si continua sendo
    /// `PraiaLightTheme`/`PraiaDarkTheme`, que segue a aparência.
    static let praiaDisplay = PaletteSpec(
        id: praiaID, name: "Praia", designer: "Padrão do Mo baile",
        ref: "Flamingo e alien numa piscina, as cores do ícone. Tem versão clara e escura e segue Ajustes › Geral › Aparência.",
        mode: .light, ink: [20, 21, 67], window: "#ECECF1", content: "#FFFFFF", alt: "#F6F6F9", side: "#E6E7EE",
        desk: "#C9E9F5", accent: "#C2456E", accentText: "#B23A63", destructive: "#D70015", success: "#3E7A45",
        warning: "#8A5A00", info: "#1F6F92", cats: ["#C94C75", "#4A8550", "#2878A3"]
    )
}

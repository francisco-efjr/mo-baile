import SwiftUI

/// Moldura do aparelho, dimensionada pelo espaço disponível e pela proporção
/// real do alvo.
///
/// Era 258x540 fixos, escritos no código. Dois efeitos ruins: a coluna podia
/// crescer sem que o espelho crescesse junto, sobrando faixa vazia embaixo; e
/// qualquer aparelho fora de 19.5:9 aparecia na proporção errada — um iPad
/// desenhado como se fosse um iPhone.
///
/// Agora a proporção vem de `deviceSize`, medida pelo motor, e o tamanho é o
/// maior que cabe no espaço oferecido.
struct DeviceBezel: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var isCompact: Bool = false

    /// Proporção do alvo. O padrão só vale antes da primeira leitura de tela.
    private var proporcao: CGFloat {
        let tamanho = appState.deviceSize
        guard tamanho.width > 0, tamanho.height > 0 else { return 9.0 / 19.5 }
        return tamanho.width / tamanho.height
    }

    var body: some View {
        GeometryReader { geo in
            let cabe = tamanhoQueCabe(em: geo.size)
            corpo(largura: cabe.width, altura: cabe.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: isCompact ? 300 : 380)
    }

    /// O maior retângulo com a proporção do aparelho que cabe no espaço dado.
    private func tamanhoQueCabe(em espaco: CGSize) -> CGSize {
        let porAltura = CGSize(width: espaco.height * proporcao, height: espaco.height)
        guard porAltura.width > espaco.width else { return porAltura }
        return CGSize(width: espaco.width, height: espaco.width / proporcao)
    }

    @ViewBuilder
    private func corpo(largura: CGFloat, altura: CGFloat) -> some View {
        let theme = themeManager.current
        // Os arredondamentos acompanham a largura para a moldura não parecer
        // grossa demais num aparelho pequeno nem fina demais num tablet.
        let raioExterno = largura * 0.155
        let raioInterno = largura * 0.128
        let respiro = max(4, largura * 0.027)
        let notchLargura = largura * 0.295
        let notchAltura = max(12, largura * 0.078)

        ZStack {
            RoundedRectangle(cornerRadius: raioExterno, style: .continuous)
                .fill(theme.deviceBezel)
                .shadow(color: .black.opacity(0.45), radius: 15, x: 0, y: 12)

            RoundedRectangle(cornerRadius: raioInterno, style: .continuous)
                .fill(theme.bgDeviceScreen)
                .padding(respiro)
                .overlay {
                    ScreenCanvas()
                        .clipShape(RoundedRectangle(cornerRadius: raioInterno, style: .continuous))
                        .padding(respiro)
                }

            VStack {
                RoundedRectangle(cornerRadius: notchAltura / 2, style: .continuous)
                    .fill(theme.deviceBezel)
                    .frame(width: notchLargura, height: notchAltura)
                    .padding(.top, respiro)
                Spacer()
            }

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color(red: 69 / 255, green: 71 / 255, blue: 90 / 255))
                    .frame(width: largura * 0.147, height: 5)
                    .padding(.bottom, respiro + largura * 0.031)
            }
        }
        .frame(width: largura, height: altura)
    }
}

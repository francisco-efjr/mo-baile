import SwiftUI

/// Moldura do aparelho, dimensionada pelo espaço disponível e pela proporção
/// real do alvo.
///
/// Era 258x540 fixos, escritos no código. Dois efeitos ruins: a coluna podia
/// crescer sem que o espelho crescesse junto, sobrando faixa vazia embaixo; e
/// qualquer aparelho fora de 19.5:9 aparecia na proporção errada — um iPad
/// desenhado como se fosse um iPhone.
///
/// A proporção vem de `deviceSize`, medida pelo motor, e o tamanho é o maior
/// que cabe no espaço oferecido. Os raios são os do design system, concêntricos
/// e escalados pela largura: moldura 40, tela 33, respiro 7 (para 258 pt).
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
        .frame(minHeight: isCompact ? 280 : 360)
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
        let escala = largura / DesignMetrics.DeviceMirror.referenceWidth
        let raioExterno = DesignMetrics.Radius.deviceOuter * escala
        let raioInterno = DesignMetrics.Radius.deviceScreen * escala
        let respiro = DesignMetrics.DeviceMirror.bezelPadding * escala
        let notch = CGSize(
            width: DesignMetrics.DeviceMirror.notchSize.width * escala,
            height: DesignMetrics.DeviceMirror.notchSize.height * escala
        )

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: raioExterno, style: .continuous)
                .fill(theme.deviceBezel)
                .overlay(
                    RoundedRectangle(cornerRadius: raioExterno, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color(r: 10, g: 12, b: 40, 0.22), radius: 20, x: 0, y: 18)

            RoundedRectangle(cornerRadius: raioInterno, style: .continuous)
                .fill(theme.bgDeviceScreen)
                .overlay {
                    ScreenCanvas()
                        .clipShape(RoundedRectangle(cornerRadius: raioInterno, style: .continuous))
                }
                .padding(respiro)

            RoundedRectangle(cornerRadius: DesignMetrics.Radius.notch * escala, style: .continuous)
                .fill(theme.deviceBezel)
                .frame(width: notch.width, height: notch.height)
                .padding(.top, respiro + DesignMetrics.DeviceMirror.notchTop * escala)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: largura, height: altura)
    }
}

import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// UX-1: texto terciário legível em todas as aparências e paletas.
///
/// O `labelTertiary` da Praia clara era o marinho `#141543` a 0,40: 2,53:1
/// sobre branco, abaixo dos 4,5:1 da WCAG 1.4.3. Ele aparece em texto
/// informativo ("ausente" no relatório, "motor não conectado" em Ajustes,
/// tempo sem valor na Rede). Este teste compõe a cor com opacidade sobre cada
/// fundo opaco de texto e mede o contraste, sem estimar pela imagem.
final class ContrastTests: XCTestCase {

    /// Componentes sRGB 0–255 e opacidade de uma cor dos tokens.
    private func rgba(_ cor: Color, _ contexto: String) throws -> (rgb: [Double], alpha: Double) {
        let ns = try XCTUnwrap(NSColor(cor).usingColorSpace(.sRGB), "\(contexto): cor fora do sRGB")
        return ([ns.redComponent * 255, ns.greenComponent * 255, ns.blueComponent * 255], ns.alphaComponent)
    }

    private func contraste(_ texto: Color, sobre fundo: Color, _ contexto: String) throws -> Double {
        let t = try rgba(texto, contexto)
        let f = try rgba(fundo, contexto)
        XCTAssertEqual(f.alpha, 1, accuracy: 0.001, "\(contexto): fundo deveria ser opaco")
        return PaletteMath.contrast(PaletteMath.over(t.rgb, t.alpha, f.rgb), f.rgb)
    }

    /// Todos os temas que o ThemeManager pode entregar.
    private var temas: [(String, any ThemeTokens)] {
        var lista: [(String, any ThemeTokens)] = []
        for alto in [false, true] {
            let sufixo = alto ? " (Aumentar contraste)" : ""
            lista.append(("Praia clara" + sufixo, PraiaLightTheme(highContrast: alto)))
            lista.append(("Praia escura" + sufixo, PraiaDarkTheme(highContrast: alto)))
            for spec in PaletteSpec.all {
                lista.append((spec.name + sufixo, PaletteTheme(spec: spec, highContrast: alto)))
            }
        }
        return lista
    }

    func testRotuloTerciarioTem45Para1EmTodosOsFundosDeTexto() throws {
        XCTAssertEqual(temas.count, 22, "2 Praias e 9 paletas, cada uma com Aumentar contraste")
        for (nome, tema) in temas {
            let fundos: [(String, Color)] = [
                ("conteúdo", tema.bgContent), ("conteúdo alternativo", tema.bgContentAlt),
                ("janela", tema.bgWindow), ("sidebar", tema.bgSidebar),
            ]
            for (rotulo, fundo) in fundos {
                let valor = try contraste(tema.labelTertiary, sobre: fundo, "\(nome) · \(rotulo)")
                XCTAssertGreaterThanOrEqual(valor, 4.5, "\(nome): terciário sobre \(rotulo) = \(String(format: "%.2f", valor)):1")
            }
        }
    }

    /// O secundário nunca fica mais claro que o terciário: a hierarquia pode
    /// encurtar, mas não inverte.
    func testSecundarioNaoFicaMaisFracoQueOTerciario() throws {
        for (nome, tema) in temas {
            let secundario = try rgba(tema.labelSecondary, nome).alpha
            let terciario = try rgba(tema.labelTertiary, nome).alpha
            XCTAssertGreaterThanOrEqual(secundario + 0.0001, terciario, nome)
        }
    }

    /// O número que a contraprova calculou para o valor antigo, para o teste
    /// provar que mede o que diz medir.
    func testValorAntigoFalhavaComoAContraprovaCalculou() {
        let navy = [20.0, 21, 67]
        let branco = [255.0, 255, 255]
        XCTAssertEqual(PaletteMath.contrast(PaletteMath.over(navy, 0.40, branco), branco), 2.53, accuracy: 0.01)
        XCTAssertEqual(PaletteMath.minimumAlpha(navy, over: [branco], ratio: 4.5), 0.60, "a contraprova pedia 0,60 a 0,62")
    }
}

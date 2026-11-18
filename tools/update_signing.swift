// Assinatura Ed25519 do zip do release. O app só instala uma atualização
// sozinho quando a assinatura bate com uma das chaves públicas embutidas em
// apps/MoBaile/Sources/MoBaile/App/UpdateSignature.swift (docs/RELEASE.md,
// seção "Atualização dentro do app"; ADR 0008).
//
// Uso (roda com o Swift do Xcode ou das Command Line Tools):
//   swift tools/update_signing.swift keygen .privado/update-signing-key.b64
//   swift tools/update_signing.swift public-key --key-file .privado/update-signing-key.b64
//   swift tools/update_signing.swift sign MoBaile-X.Y.Z-macOS.zip MoBaile-X.Y.Z-macOS.zip.sig
//   swift tools/update_signing.swift verify MoBaile-X.Y.Z-macOS.zip MoBaile-X.Y.Z-macOS.zip.sig \
//       --app-keys apps/MoBaile/Sources/MoBaile/App/UpdateSignature.swift
//
// A chave privada vem de --key-file ou da variável MOBAILE_UPDATE_SIGNING_KEY
// (base64 dos 32 bytes). No CI ela é o secret de mesmo nome.

import CryptoKit
import Foundation

func falhar(_ mensagem: String) -> Never {
    FileHandle.standardError.write(Data("erro: \(mensagem)\n".utf8))
    exit(1)
}

func uso() -> Never {
    falhar("""
    uso:
      keygen <arquivo-da-chave-privada>
      public-key [--key-file <arquivo>]
      sign <zip> <saida.sig> [--key-file <arquivo>]
      verify <zip> <assinatura.sig> (--key <base64> | --app-keys <UpdateSignature.swift>)
    """)
}

var argumentos = Array(CommandLine.arguments.dropFirst())

func opcao(_ nome: String) -> String? {
    guard let i = argumentos.firstIndex(of: nome) else { return nil }
    guard i + 1 < argumentos.count else { falhar("\(nome) precisa de um valor") }
    let valor = argumentos[i + 1]
    argumentos.removeSubrange(i...(i + 1))
    return valor
}

func lerTexto(_ caminho: String) -> String {
    guard let texto = try? String(contentsOfFile: caminho, encoding: .utf8) else { falhar("não consegui ler \(caminho)") }
    return texto.trimmingCharacters(in: .whitespacesAndNewlines)
}

func chavePrivada(arquivo: String?) -> Curve25519.Signing.PrivateKey {
    let base64: String
    if let arquivo {
        base64 = lerTexto(arquivo)
    } else if let env = ProcessInfo.processInfo.environment["MOBAILE_UPDATE_SIGNING_KEY"], !env.isEmpty {
        base64 = env.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        falhar("sem chave: use --key-file ou a variável MOBAILE_UPDATE_SIGNING_KEY")
    }
    guard let dados = Data(base64Encoded: base64), let chave = try? Curve25519.Signing.PrivateKey(rawRepresentation: dados) else {
        falhar("a chave privada não é base64 de 32 bytes Ed25519")
    }
    return chave
}

/// As chaves públicas entre os marcadores `chaves-publicas:inicio` e `:fim`.
func chavesDoApp(_ caminho: String) -> [String] {
    let texto = lerTexto(caminho)
    guard let inicio = texto.range(of: "chaves-publicas:inicio"),
          let fim = texto.range(of: "chaves-publicas:fim", range: inicio.upperBound..<texto.endIndex) else {
        falhar("\(caminho) não tem os marcadores chaves-publicas:inicio/fim")
    }
    let trecho = String(texto[inicio.upperBound..<fim.lowerBound])
    let regex = try! NSRegularExpression(pattern: "\"([A-Za-z0-9+/]{43}=)\"")
    let achados = regex.matches(in: trecho, range: NSRange(trecho.startIndex..., in: trecho))
    let chaves = achados.compactMap { Range($0.range(at: 1), in: trecho).map { String(trecho[$0]) } }
    guard !chaves.isEmpty else { falhar("nenhuma chave pública em \(caminho)") }
    return chaves
}

func gravar(_ texto: String, em caminho: String, privado: Bool) {
    let url = URL(fileURLWithPath: caminho)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let atributos: [FileAttributeKey: Any]? = privado ? [.posixPermissions: 0o600] : nil
    guard FileManager.default.createFile(atPath: caminho, contents: Data((texto + "\n").utf8), attributes: atributos) else {
        falhar("não consegui gravar \(caminho)")
    }
}

guard let comando = argumentos.first else { uso() }
argumentos.removeFirst()

switch comando {
case "keygen":
    guard argumentos.count == 1 else { uso() }
    let destino = argumentos[0]
    if FileManager.default.fileExists(atPath: destino) {
        falhar("\(destino) já existe; não sobrescrevo uma chave")
    }
    let chave = Curve25519.Signing.PrivateKey()
    gravar(chave.rawRepresentation.base64EncodedString(), em: destino, privado: true)
    print("chave privada: \(destino) (permissão 600; guarde uma cópia fora desta máquina)")
    print("chave pública: \(chave.publicKey.rawRepresentation.base64EncodedString())")

case "public-key":
    let arquivo = opcao("--key-file")
    guard argumentos.isEmpty else { uso() }
    print(chavePrivada(arquivo: arquivo).publicKey.rawRepresentation.base64EncodedString())

case "sign":
    let arquivo = opcao("--key-file")
    guard argumentos.count == 2 else { uso() }
    let chave = chavePrivada(arquivo: arquivo)
    guard let zip = try? Data(contentsOf: URL(fileURLWithPath: argumentos[0]), options: .mappedIfSafe) else {
        falhar("não consegui ler \(argumentos[0])")
    }
    guard let assinatura = try? chave.signature(for: zip) else { falhar("a assinatura falhou") }
    gravar(assinatura.base64EncodedString(), em: argumentos[1], privado: false)
    print("assinado: \(argumentos[1])")

case "verify":
    let uma = opcao("--key")
    let doApp = opcao("--app-keys")
    guard argumentos.count == 2, (uma == nil) != (doApp == nil) else { uso() }
    let chaves = uma.map { [$0] } ?? chavesDoApp(doApp!)
    guard let zip = try? Data(contentsOf: URL(fileURLWithPath: argumentos[0]), options: .mappedIfSafe) else {
        falhar("não consegui ler \(argumentos[0])")
    }
    guard let assinatura = Data(base64Encoded: lerTexto(argumentos[1])), assinatura.count == 64 else {
        falhar("\(argumentos[1]) não é uma assinatura Ed25519 em base64")
    }
    let confere = chaves.contains { texto in
        guard let dados = Data(base64Encoded: texto), let publica = try? Curve25519.Signing.PublicKey(rawRepresentation: dados) else {
            return false
        }
        return publica.isValidSignature(assinatura, for: zip)
    }
    guard confere else { falhar("a assinatura não confere com nenhuma das \(chaves.count) chave(s)") }
    print("assinatura confere (\(chaves.count) chave(s) aceita(s))")

default:
    uso()
}

import CryptoKit
import Foundation

/// Autenticidade do zip de atualização (ADR 0008).
///
/// O app é assinado ad-hoc, sem Developer ID, então a assinatura de código não
/// diz quem fez o app. Quem garante que o zip baixado saiu do release oficial é
/// esta assinatura Ed25519: o workflow de release assina o zip com a chave
/// privada (secret `MOBAILE_UPDATE_SIGNING_KEY`) e publica `<zip>.sig`; o app só
/// instala se a assinatura bater com uma das chaves públicas abaixo. O `.sha256`
/// ao lado do zip não serve para isso: quem controla o release controla os dois.
enum UpdateSignature {
    /// Chaves públicas aceitas (base64 dos 32 bytes). Mais de uma permite trocar
    /// a chave: a versão nova passa a aceitar as duas, e o release seguinte já
    /// pode sair assinado só com a nova. `tools/update_signing.swift verify
    /// --app-keys` lê esta lista entre os marcadores.
    // chaves-publicas:inicio
    static let publicKeys: [String] = [
        "ExKWgT5m36F0N4Z449pexHLVZohS3THyCxIwCmk5fwU=", // 2026-11-18
    ]
    // chaves-publicas:fim

    /// O conteúdo do `.sig`: base64 de 64 bytes, com ou sem quebra de linha.
    static func parse(_ texto: String) -> Data? {
        guard let dados = Data(base64Encoded: texto.trimmingCharacters(in: .whitespacesAndNewlines)), dados.count == 64 else {
            return nil
        }
        return dados
    }

    static func isValid(signature: Data, for dados: Data, keys: [String] = publicKeys) -> Bool {
        keys.contains { texto in
            guard let bruto = Data(base64Encoded: texto),
                  let chave = try? Curve25519.Signing.PublicKey(rawRepresentation: bruto) else { return false }
            return chave.isValidSignature(signature, for: dados)
        }
    }
}

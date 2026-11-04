import Foundation

/// `workspace.*`: a árvore Projeto da aba Page Objects (PO-5). Contrato em
/// `docs/PROTOCOLO_RPC.md`, seção "Árvore Projeto".
extension EngineDTO {

    struct WorkspaceTree: Decodable, Equatable {
        let root: String
        let name: String
        let exists: Bool
        let nodes: [WorkspaceNode]
        let truncated: Bool
    }

    struct WorkspaceNode: Decodable, Equatable, Identifiable {
        let name: String
        /// Relativo à pasta de trabalho (`pages/tela.py`). Também é o id.
        let path: String
        let kind: String
        let children: [WorkspaceNode]?

        var id: String { path }
        var isDirectory: Bool { kind == "dir" }
    }

    struct WorkspaceFile: Decodable, Equatable {
        let path: String
        /// Sempre com `\n`; o separador do arquivo vem em `lineSeparator`.
        /// Depois de salvar, vira o texto gravado (a linha de base do "sujo").
        var text: String
        let encoding: String
        let lineSeparator: String
        let bom: Bool
        let readOnly: Bool
        let size: Int
        /// Hora de modificação lida (R-04): o `write` recusa se o disco mudou.
        var mtimeNs: Int?

        enum CodingKeys: String, CodingKey {
            case path, text, encoding, bom, size
            case lineSeparator = "line_separator"
            case readOnly = "read_only"
            case mtimeNs = "mtime_ns"
        }
    }

    struct WorkspaceWrite: Decodable, Equatable {
        let path: String
        let saved: Bool
        let bytes: Int
        let mtimeNs: Int?

        enum CodingKeys: String, CodingKey {
            case path, saved, bytes
            case mtimeNs = "mtime_ns"
        }
    }
}

extension EngineSession {
    func workspaceTree() async throws -> EngineDTO.WorkspaceTree {
        try await chamarMotor("workspace.tree")
    }

    func readWorkspaceFile(_ path: String) async throws -> EngineDTO.WorkspaceFile {
        try await chamarMotor("workspace.read", params: ["path": .string(path)])
    }

    /// Grava com o separador e o BOM que o arquivo tinha, como o PyCharm. Sem
    /// `sobrescrever`, manda o `mtime_ns` lido: se outro editor gravou no meio,
    /// o motor recusa com `file_changed` (R-04).
    func writeWorkspaceFile(
        _ arquivo: EngineDTO.WorkspaceFile, text: String, sobrescrever: Bool = false
    ) async throws -> EngineDTO.WorkspaceWrite {
        var params: [String: JSONValue] = [
            "path": .string(arquivo.path), "text": .string(text),
            "line_separator": .string(arquivo.lineSeparator), "bom": .bool(arquivo.bom),
        ]
        if !sobrescrever, let mtime = arquivo.mtimeNs { params["expected_mtime_ns"] = .int(mtime) }
        return try await chamarMotor("workspace.write", params: params)
    }
}

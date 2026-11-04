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
        let text: String
        let encoding: String
        let lineSeparator: String
        let bom: Bool
        let readOnly: Bool
        let size: Int

        enum CodingKeys: String, CodingKey {
            case path, text, encoding, bom, size
            case lineSeparator = "line_separator"
            case readOnly = "read_only"
        }
    }

    struct WorkspaceWrite: Decodable, Equatable {
        let path: String
        let saved: Bool
        let bytes: Int
    }
}

extension EngineSession {
    func workspaceTree() async throws -> EngineDTO.WorkspaceTree {
        try await chamarMotor("workspace.tree")
    }

    func readWorkspaceFile(_ path: String) async throws -> EngineDTO.WorkspaceFile {
        try await chamarMotor("workspace.read", params: ["path": .string(path)])
    }

    /// Grava com o separador e o BOM que o arquivo tinha, como o PyCharm.
    func writeWorkspaceFile(_ arquivo: EngineDTO.WorkspaceFile, text: String) async throws -> EngineDTO.WorkspaceWrite {
        try await chamarMotor("workspace.write", params: [
            "path": .string(arquivo.path), "text": .string(text),
            "line_separator": .string(arquivo.lineSeparator), "bom": .bool(arquivo.bom),
        ])
    }
}

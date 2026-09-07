// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MoBaile",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MoBaile",
            path: "Sources/MoBaile",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Prepara a migracao para Swift 6 sem quebrar a compilacao hoje:
                // os problemas de isolamento aparecem como aviso, e nao como
                // erro, e podem ser resolvidos aos poucos.
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MoBaileTests",
            dependencies: ["MoBaile"],
            path: "Tests/MoBaileTests",
            resources: [
                // Payloads reais gerados pelo motor Python (`make fixtures`).
                // Sao a especificacao executavel do contrato entre as duas
                // linguagens: renomear um campo no Python quebra a suite Swift.
                .process("Fixtures")
            ]
        )
    ]
)

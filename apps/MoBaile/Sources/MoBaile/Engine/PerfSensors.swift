import Foundation

/// Sinais do Mac que o motor usa para escolher o perfil (PERF-4).
///
/// O Python do motor não enxerga nada disso sem PyObjC: estado térmico,
/// Economia de Energia e pressão de memória vêm do Foundation e do Dispatch.
/// O front lê e manda por `perf.signals`; a decisão fica no motor.
struct PerfSignals: Equatable, Sendable {
    var thermal: String
    var lowPower: Bool
    var memoryPressure: String
    var physicalMemoryGB: Double
    var arch: String
    var translated: Bool

    var params: [String: JSONValue] {
        [
            "thermal": .string(thermal),
            "low_power": .bool(lowPower),
            "memory_pressure": .string(memoryPressure),
            "physical_memory_gb": .double(physicalMemoryGB),
            "arch": .string(arch),
            "translated": .bool(translated),
        ]
    }

    static func thermalName(_ estado: ProcessInfo.ThermalState) -> String {
        switch estado {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }

    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// O app roda traduzido pelo Rosetta.
    static var translatedByRosetta: Bool {
        var valor: Int32 = 0
        var tamanho = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &valor, &tamanho, nil, 0) == 0 && valor == 1
    }
}

/// Lê os sinais e avisa quando um deles muda.
@MainActor
final class PerfSensors {
    private var memoryPressure = "normal"
    private var observers: [NSObjectProtocol] = []
    private var memorySource: DispatchSourceMemoryPressure?

    var current: PerfSignals {
        let info = ProcessInfo.processInfo
        let gb = Double(info.physicalMemory) / 1_073_741_824
        return PerfSignals(
            thermal: PerfSignals.thermalName(info.thermalState),
            lowPower: info.isLowPowerModeEnabled,
            memoryPressure: memoryPressure,
            physicalMemoryGB: (gb * 10).rounded() / 10,
            arch: PerfSignals.arch,
            translated: PerfSignals.translatedByRosetta
        )
    }

    /// Começa a observar. `onChange` roda na main thread a cada mudança.
    func start(onChange: @escaping @MainActor () -> Void) {
        guard observers.isEmpty else { return }
        for nome in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: nome, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange() }
            })
        }
        let fonte = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        fonte.setEventHandler { [weak self, weak fonte] in
            MainActor.assumeIsolated {
                guard let self, let evento = fonte?.data else { return }
                self.memoryPressure = evento.contains(.critical) ? "critical"
                    : evento.contains(.warning) ? "warning" : "normal"
                onChange()
            }
        }
        fonte.resume()
        memorySource = fonte
    }
}

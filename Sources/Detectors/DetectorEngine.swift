import Foundation
import ProcessKit

public struct HotProcess: Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
    }
}

public struct EngineResult: Sendable, Equatable {
    /// Actionable. Every one of these has a stop target.
    public let findings: [Finding]
    /// Informational only. Deliberately has no target, so the UI cannot offer
    /// to stop WindowServer.
    public let alsoHot: [HotProcess]

    public static let empty = EngineResult(findings: [], alsoHot: [])

    public init(findings: [Finding], alsoHot: [HotProcess]) {
        self.findings = findings
        self.alsoHot = alsoHot
    }
}

public struct DetectorEngine: Sendable {
    private let detectors: [any Detector]
    private let hotThreshold: Double
    private let hotLimit: Int

    public init(detectors: [any Detector] = DetectorEngine.defaultDetectors,
                hotThreshold: Double = 20, hotLimit: Int = 5) {
        self.detectors = detectors
        self.hotThreshold = hotThreshold
        self.hotLimit = hotLimit
    }

    /// Order matters: the first detector to claim a pid owns it.
    public static var defaultDetectors: [any Detector] {
        [IsolatedBrowserDetector(), ContainerDetector(), SimulatorDetector(),
         DevServerDetector(), OrphanDetector()]
    }

    public func evaluate(snapshot: Snapshot, history: History,
                         settings: Settings, excluded: Set<String>) -> EngineResult {
        var claimed = Set<Int32>()
        var findings: [Finding] = []

        for detector in detectors {
            for finding in detector.findings(in: snapshot, history: history, settings: settings) {
                guard !excluded.contains(finding.identity) else { continue }
                if case .processes(let pids) = finding.target {
                    guard claimed.isDisjoint(with: pids) else { continue }
                    claimed.formUnion(pids)
                }
                findings.append(finding)
            }
        }

        findings.sort {
            $0.severity == $1.severity ? $0.cpuPercent > $1.cpuPercent : $0.severity > $1.severity
        }

        let hot = snapshot.processes
            .filter { !claimed.contains($0.pid) }
            .compactMap { process -> HotProcess? in
                guard let cpu = history.cpuPercent(pid: process.pid), cpu >= hotThreshold else { return nil }
                return HotProcess(pid: process.pid, name: process.name, cpuPercent: cpu)
            }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(hotLimit)

        return EngineResult(findings: findings, alsoHot: Array(hot))
    }

    /// Convenience for callers with default settings and no exclusions.
    public func evaluate(in snapshot: Snapshot, history: History) -> EngineResult {
        evaluate(snapshot: snapshot, history: history, settings: Settings(), excluded: [])
    }
}

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
    /// Things holding the machine awake that are named rather than offered up:
    /// an app playing audio is worth knowing about and is nobody's business to
    /// quit. The ones that are safe to stop are findings instead.
    public let keepingAwake: [AwakeHolder]

    public static let empty = EngineResult(findings: [], alsoHot: [], keepingAwake: [])

    public init(findings: [Finding], alsoHot: [HotProcess], keepingAwake: [AwakeHolder] = []) {
        self.findings = findings
        self.alsoHot = alsoHot
        self.keepingAwake = keepingAwake
    }
}

public struct DetectorEngine: Sendable {
    private let detectors: [any Detector]
    private let hotThreshold: Double
    private let hotLimit: Int
    private let hotWindow: TimeInterval

    public init(detectors: [any Detector] = DetectorEngine.defaultDetectors,
                hotThreshold: Double = 20, hotLimit: Int = 5,
                hotWindow: TimeInterval = 30) {
        self.detectors = detectors
        self.hotThreshold = hotThreshold
        self.hotLimit = hotLimit
        self.hotWindow = hotWindow
    }

    /// Order matters: the first detector to claim a pid owns it.
    public static var defaultDetectors: [any Detector] {
        // AwakeDetector comes before OrphanDetector on purpose: a `caffeinate`
        // whose terminal closed is an orphan, but "keeping this Mac awake" is
        // the more specific thing to be told, and the only one that explains
        // the battery.
        [TunnelDetector(), IsolatedBrowserDetector(), ContainerDetector(), SimulatorDetector(),
         AndroidEmulatorDetector(), DevServerDetector(), AwakeDetector(), OrphanDetector()]
    }

    public func evaluate(snapshot: Snapshot, history: History,
                         settings: Settings, excluded: Set<String>) -> EngineResult {
        var claimed = Set<Int32>()
        var findings: [Finding] = []
        // Dismissed pids are remembered separately from claimed ones. They must
        // not be claimed — another detector may still have something true to
        // say about them — but "never list this again" has to mean it, and
        // naming one in an informational list would move the row down the panel
        // rather than take it away.
        var dismissed = Set<Int32>()

        for detector in detectors {
            for finding in detector.findings(in: snapshot, history: history, settings: settings) {
                guard !excluded.contains(finding.identity) else {
                    if case .processes(let pids) = finding.target { dismissed.formUnion(pids) }
                    continue
                }
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
            .filter { Self.canBeBusyButYours($0, in: snapshot, claimed: claimed) }
            .compactMap { process -> HotProcess? in
                // Sustained, not a spike. Anything that flares for one interval
                // and settles would otherwise appear and vanish for no reason
                // the user can see.
                guard let cpu = history.sustainedCPU(pid: process.pid, over: hotWindow),
                      cpu >= hotThreshold else { return nil }
                return HotProcess(pid: process.pid, name: process.name, cpuPercent: cpu)
            }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(hotLimit)

        // Anything already listed as a finding says so in its own row; naming
        // it again below would read as two problems where there is one.
        let awake = AwakeDetector.holders(in: snapshot, settings: settings)
            .filter { !claimed.contains($0.pid) && !dismissed.contains($0.pid) }

        return EngineResult(findings: findings, alsoHot: Array(hot), keepingAwake: awake)
    }

    /// "Busy, but yours" means exactly that: something of the user's own that
    /// has been busy for a while. Not a system daemon they cannot act on, and
    /// not a piece of a simulator that is already listed as one row.
    static func canBeBusyButYours(_ process: ProcessSample, in snapshot: Snapshot,
                                  claimed: Set<Int32>) -> Bool {
        guard !claimed.contains(process.pid),
              process.pid != snapshot.ownPID,          // its own cost is its own problem
              process.uid == snapshot.currentUID,
              !isSimulatorInternal(process)
        else { return false }
        return true
    }

    /// Everything a booted device runs lives under its own data directory.
    static func isSimulatorInternal(_ process: ProcessSample) -> Bool {
        process.name == "launchd_sim"
            || process.executablePath.contains("/CoreSimulator/")
            || process.arguments.contains { $0.contains("/CoreSimulator/Devices/") }
    }

    /// Convenience for callers with default settings and no exclusions.
    public func evaluate(in snapshot: Snapshot, history: History) -> EngineResult {
        evaluate(snapshot: snapshot, history: history, settings: Settings(), excluded: [])
    }
}

import Foundation
import ProcessKit

/// A booted simulator holds a lot of memory and keeps a device's worth of
/// daemons alive long after the build you were testing.
public struct SimulatorDetector: Detector {
    public let kind: FindingKind = .simulator

    public init() {}

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.simulators.compactMap { simulator -> Finding? in
            let age = simulator.bootedAt.map { snapshot.takenAt.timeIntervalSince($0) }
            if let age, age < settings.minimumAge { return nil }

            return Finding(
                identity: "simulator:\(simulator.id)",
                kind: .simulator,
                title: simulator.name,
                detail: age == nil ? "\(simulator.runtime) · booted, start time unknown" : simulator.runtime,
                cpuPercent: 0,
                memoryBytes: 0,
                age: age ?? 0,
                target: .simulator(simulator.id),
                severity: .notable,
                explanation: "\(FindingKind.simulator.plainDescription) This one is running \(simulator.runtime). Shutting it down is undoable — it boots again from the panel.",
                revealPath: nil,
                details: """
                    Simulator: \(simulator.name) (\(simulator.runtime))
                    UDID: \(simulator.id)

                    xcrun simctl shutdown \(simulator.id)
                    xcrun simctl boot \(simulator.id)
                    """)
        }
        .sorted { $0.age > $1.age }
    }
}

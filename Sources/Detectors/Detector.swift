import Foundation
import ProcessKit

public protocol Detector: Sendable {
    var kind: FindingKind { get }
    func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding]
}

extension Detector {
    /// Sums the latest rate across a process group, treating unknown rates as zero.
    func totalCPU(_ processes: [ProcessSample], _ history: History) -> Double {
        processes.reduce(0) { $0 + (history.cpuPercent(pid: $1.pid) ?? 0) }
    }

    /// The group's sustained load: the sum of each member's weakest interval.
    /// Nil when no member has enough history to judge.
    func groupSustainedCPU(_ processes: [ProcessSample], _ history: History,
                           over window: TimeInterval) -> Double? {
        let rates = processes.compactMap { history.sustainedCPU(pid: $0.pid, over: window) }
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }
}

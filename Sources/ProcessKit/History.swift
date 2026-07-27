import Foundation

/// A bounded ring of recent snapshots. Detection reads rates from here rather
/// than from a single sample, so a momentary spike never surfaces a finding.
public struct History: Sendable, Equatable {
    public private(set) var snapshots: [Snapshot] = []
    private let capacity: Int

    /// 60 samples at the 5 second foreground cadence is five minutes of history.
    public init(capacity: Int = 60) {
        self.capacity = max(2, capacity)
    }

    public var count: Int { snapshots.count }
    public var latest: Snapshot? { snapshots.last }

    public mutating func record(_ snapshot: Snapshot) {
        snapshots.append(snapshot)
        if snapshots.count > capacity { snapshots.removeFirst(snapshots.count - capacity) }
    }

    /// CPU percentage over the most recent interval. 100 means one full core.
    public func cpuPercent(pid: Int32) -> Double? {
        guard snapshots.count >= 2 else { return nil }
        return interval(from: snapshots[snapshots.count - 2], to: snapshots[snapshots.count - 1], pid: pid)
    }

    /// The lowest CPU percentage seen across every interval covering `window`.
    /// Nil when recorded history is shorter than the window.
    public func sustainedCPU(pid: Int32, over window: TimeInterval) -> Double? {
        guard let newest = snapshots.last, let oldest = snapshots.first,
              newest.takenAt.timeIntervalSince(oldest.takenAt) >= window else { return nil }
        let cutoff = newest.takenAt.addingTimeInterval(-window)

        var lowest: Double?
        for index in 1..<snapshots.count {
            let earlier = snapshots[index - 1], later = snapshots[index]
            guard later.takenAt > cutoff else { continue }
            guard let value = interval(from: earlier, to: later, pid: pid) else { return nil }
            lowest = min(lowest ?? value, value)
        }
        return lowest
    }

    /// How long CPU has continuously stayed below `threshold`, walking backwards.
    public func idleDuration(pid: Int32, below threshold: Double) -> TimeInterval? {
        guard let newest = snapshots.last, snapshots.count >= 2 else { return nil }
        var idleSince = newest.takenAt
        for index in stride(from: snapshots.count - 1, through: 1, by: -1) {
            let earlier = snapshots[index - 1], later = snapshots[index]
            guard let value = interval(from: earlier, to: later, pid: pid), value < threshold else { break }
            idleSince = earlier.takenAt
        }
        let duration = newest.takenAt.timeIntervalSince(idleSince)
        return duration > 0 ? duration : nil
    }

    private func interval(from earlier: Snapshot, to later: Snapshot, pid: Int32) -> Double? {
        guard let before = earlier.process(pid: pid), let after = later.process(pid: pid),
              after.cpuTimeNanos >= before.cpuTimeNanos else { return nil }
        let elapsed = later.takenAt.timeIntervalSince(earlier.takenAt)
        guard elapsed > 0 else { return nil }
        let burned = Double(after.cpuTimeNanos - before.cpuTimeNanos) / 1_000_000_000
        return burned / elapsed * 100
    }
}

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

    /// CPU percentage over the most recent stretch covering at least `minimum`
    /// seconds of running time. 100 means one full core.
    ///
    /// Samples are not evenly spaced. Opening the panel takes one immediately,
    /// which can land a second after the one the background timer just took,
    /// and a rate measured across that second describes an instant rather than
    /// a process: a burst that reads as several hundred percent. That reading
    /// would be the number on screen at the exact moment someone looks, so a
    /// gap too short to mean anything is widened until it does.
    public func cpuPercent(pid: Int32, measuredOver minimum: TimeInterval = 5) -> Double? {
        guard let newest = snapshots.last, snapshots.count >= 2 else { return nil }

        var widest: Double?
        for index in stride(from: snapshots.count - 2, through: 0, by: -1) {
            let earlier = snapshots[index]
            // Walking back past the process's own first sample ends the search:
            // whatever has been measured so far is all there is.
            guard let value = interval(from: earlier, to: newest, pid: pid) else { break }
            widest = value
            if elapsed(from: earlier, to: newest) >= minimum { break }
        }
        return widest
    }

    /// The lowest CPU percentage seen across every interval covering `window`.
    /// Nil when recorded history is shorter than the window.
    ///
    /// Every window here is measured in running time, for the same reason the
    /// rates are: an hour in which the machine was awake for two minutes holds
    /// two minutes of evidence, and claiming three minutes of sustained load
    /// from one waking minute is a finding invented out of a nap.
    public func sustainedCPU(pid: Int32, over window: TimeInterval) -> Double? {
        guard let newest = snapshots.last, let oldest = snapshots.first,
              elapsed(from: oldest, to: newest) >= window else { return nil }

        var lowest: Double?
        for index in 1..<snapshots.count {
            let earlier = snapshots[index - 1], later = snapshots[index]
            guard elapsed(from: later, to: newest) < window else { continue }
            guard let value = interval(from: earlier, to: later, pid: pid) else { return nil }
            lowest = min(lowest ?? value, value)
        }
        return lowest
    }

    /// The busiest interval within `window`, or nil when nothing is recorded
    /// for it. Evidence that something has been used recently, as opposed to
    /// merely being old.
    public func peakCPU(pid: Int32, over window: TimeInterval) -> Double? {
        guard let newest = snapshots.last, snapshots.count >= 2 else { return nil }

        var highest: Double?
        for index in 1..<snapshots.count {
            let earlier = snapshots[index - 1], later = snapshots[index]
            guard elapsed(from: later, to: newest) < window,
                  let value = interval(from: earlier, to: later, pid: pid) else { continue }
            highest = max(highest ?? value, value)
        }
        return highest
    }

    /// How long CPU has continuously stayed below `threshold`, walking
    /// backwards. Counted in running time: a process that did nothing while the
    /// lid was shut has not been idle for the length of the nap, because
    /// nothing had the chance to be busy. Counting the nap would let a night's
    /// sleep make every large process look abandoned by morning.
    public func idleDuration(pid: Int32, below threshold: Double) -> TimeInterval? {
        guard snapshots.count >= 2 else { return nil }
        var duration: TimeInterval = 0
        for index in stride(from: snapshots.count - 1, through: 1, by: -1) {
            let earlier = snapshots[index - 1], later = snapshots[index]
            guard let value = interval(from: earlier, to: later, pid: pid), value < threshold else { break }
            duration += elapsed(from: earlier, to: later)
        }
        return duration > 0 ? duration : nil
    }

    private func interval(from earlier: Snapshot, to later: Snapshot, pid: Int32) -> Double? {
        guard let before = earlier.process(pid: pid), let after = later.process(pid: pid),
              after.cpuTimeNanos >= before.cpuTimeNanos else { return nil }
        let seconds = elapsed(from: earlier, to: later)
        guard seconds > 0 else { return nil }
        let burned = Double(after.cpuTimeNanos - before.cpuTimeNanos) / 1_000_000_000
        return burned / seconds * 100
    }

    /// Running time between two samples: the wall clock minus whatever the
    /// machine spent asleep. CPU time only accrues while it is awake, so
    /// dividing by the nap turns something pinning three cores into three
    /// percent — the difference between a finding and silence, every morning.
    /// Samples taken before uptime was recorded fall back to the wall clock,
    /// as does a reading from before a reboot reset it.
    private func elapsed(from earlier: Snapshot, to later: Snapshot) -> TimeInterval {
        if earlier.awakeUptime > 0, later.awakeUptime > earlier.awakeUptime {
            return later.awakeUptime - earlier.awakeUptime
        }
        return later.takenAt.timeIntervalSince(earlier.takenAt)
    }
}

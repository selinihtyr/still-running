import Testing
import Foundation
@testable import ProcessKit

private func snapshot(at seconds: TimeInterval, pid: Int32, cpuNanos: UInt64, rss: UInt64 = 0) -> Snapshot {
    Snapshot(
        takenAt: Date(timeIntervalSince1970: seconds),
        processes: [ProcessSample(
            pid: pid, ppid: 1, uid: 501, executablePath: "/bin/x", arguments: ["x"],
            startedAt: Date(timeIntervalSince1970: 0), hasControllingTTY: false,
            cpuTimeNanos: cpuNanos, residentBytes: rss)],
        containers: [], simulators: [], currentUID: 501, ownPID: 1)
}

@Test func cpuPercentIsADeltaBetweenTwoSamples() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    // One full second of CPU burned across ten seconds of wall clock = 10%.
    history.record(snapshot(at: 10, pid: 7, cpuNanos: 1_000_000_000))

    #expect(history.cpuPercent(pid: 7)! == 10.0)
}

@Test func cpuPercentIsNilWithASingleSample() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))

    #expect(history.cpuPercent(pid: 7) == nil)
}

@Test func sustainedCPUReportsTheWeakestIntervalInTheWindow() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 60, pid: 7, cpuNanos: 60_000_000_000))    // 100%
    history.record(snapshot(at: 120, pid: 7, cpuNanos: 78_000_000_000))   // 30%
    history.record(snapshot(at: 180, pid: 7, cpuNanos: 138_000_000_000))  // 100%

    #expect(history.sustainedCPU(pid: 7, over: 180)! == 30.0)
}

@Test func sustainedCPUIsNilWhenHistoryIsShorterThanTheWindow() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 30, pid: 7, cpuNanos: 30_000_000_000))

    #expect(history.sustainedCPU(pid: 7, over: 180) == nil)
}

@Test func idleDurationMeasuresHowLongCPUStayedBelowAThreshold() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 600, pid: 7, cpuNanos: 1_000_000_000))    // ~0.17%
    history.record(snapshot(at: 1200, pid: 7, cpuNanos: 2_000_000_000))   // ~0.17%

    #expect(history.idleDuration(pid: 7, below: 2)! == 1200)
}

@Test func idleDurationStopsAtTheLastBusyInterval() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 60, pid: 7, cpuNanos: 60_000_000_000))    // 100%, busy
    history.record(snapshot(at: 660, pid: 7, cpuNanos: 60_100_000_000))   // idle

    #expect(history.idleDuration(pid: 7, below: 2)! == 600)
}

@Test func historyDropsSamplesBeyondCapacity() {
    var history = History(capacity: 3)
    for step in 0..<5 {
        history.record(snapshot(at: Double(step) * 10, pid: 7, cpuNanos: UInt64(step) * 1_000_000_000))
    }

    #expect(history.count == 3)
}

@Test func ratesAreNilForAProcessThatIsNotInBothSamples() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 10, pid: 8, cpuNanos: 1_000_000_000))

    #expect(history.cpuPercent(pid: 7) == nil)
    #expect(history.cpuPercent(pid: 8) == nil)
}

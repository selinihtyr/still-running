import Testing
import Foundation
@testable import ProcessKit

private func snapshot(at seconds: TimeInterval, awake: TimeInterval = 0,
                      pid: Int32, cpuNanos: UInt64, rss: UInt64 = 0) -> Snapshot {
    Snapshot(
        takenAt: Date(timeIntervalSince1970: seconds),
        processes: [ProcessSample(
            pid: pid, ppid: 1, uid: 501, executablePath: "/bin/x", arguments: ["x"],
            startedAt: Date(timeIntervalSince1970: 0), hasControllingTTY: false,
            cpuTimeNanos: cpuNanos, residentBytes: rss)],
        containers: [], simulators: [], currentUID: 501, ownPID: 1, awakeUptime: awake)
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

@Test func sleepBetweenTwoSamplesIsNotTimeAnythingCouldHaveBurned() {
    // Fifteen minutes apart on the wall clock with only a minute of the machine
    // awake between them: one maintenance wake in the middle of a night's
    // sleep. Thirty seconds of CPU burned inside that minute is half a core,
    // not the three percent that dividing by the whole nap would report.
    var history = History()
    history.record(snapshot(at: 0, awake: 1_000, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 900, awake: 1_060, pid: 7, cpuNanos: 30_000_000_000))

    #expect(history.cpuPercent(pid: 7)! == 50.0)
}

@Test func idleDurationCountsWakingTimeOnly() {
    // Eight hours on the wall clock, ten minutes of them awake. Something that
    // did nothing while the lid was shut has not been idle for eight hours:
    // nothing had the chance to be busy, so the nap is not evidence.
    var history = History()
    history.record(snapshot(at: 0, awake: 100, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 28_800, awake: 700, pid: 7, cpuNanos: 0))

    #expect(history.idleDuration(pid: 7, below: 2)! == 600)
}

@Test func aRateIsNotReadFromASecondLongGap() {
    // Opening the panel samples immediately, which can land a moment after the
    // background timer took its own. Two CPU-seconds burned in the one second
    // between the two is a burst, not a process using two hundred percent —
    // and that reading would be the number on screen the moment someone looks.
    var history = History()
    history.record(snapshot(at: 0, awake: 100, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 60, awake: 160, pid: 7, cpuNanos: 6_000_000_000))
    history.record(snapshot(at: 61, awake: 161, pid: 7, cpuNanos: 8_000_000_000))

    let measured = history.cpuPercent(pid: 7)!
    #expect(measured < 100)
    #expect(abs(measured - 8.0 / 61.0 * 100) < 0.0001)
}

@Test func aGapThatIsAlreadyLongEnoughIsMeasuredOnItsOwn() {
    // Widening only happens when the newest gap is too short to trust. A full
    // minute stands by itself, so an idle minute before it is not averaged in.
    var history = History()
    history.record(snapshot(at: 0, awake: 100, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 60, awake: 160, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 120, awake: 220, pid: 7, cpuNanos: 60_000_000_000))

    #expect(history.cpuPercent(pid: 7)! == 100.0)
}

@Test func recentActivityIsMeasuredInWakingTimeToo() {
    // The dev server someone was typing against when they shut the lid. An
    // hour of wall clock later the machine has been awake for two minutes of
    // it, and that work is still the most recent thing the server did — which
    // is the whole question "have you been using this?" is asking.
    var history = History()
    history.record(snapshot(at: 0, awake: 100, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 60, awake: 160, pid: 7, cpuNanos: 60_000_000_000))   // busy
    history.record(snapshot(at: 3_600, awake: 220, pid: 7, cpuNanos: 60_000_000_000))

    #expect(history.peakCPU(pid: 7, over: 600)! == 100.0)
}

@Test func sustainedIsNotClaimedFromASingleWakingMinute() {
    // Fifteen minutes apart on the wall clock, one minute of them awake. One
    // minute of evidence cannot answer a question about three.
    var history = History()
    history.record(snapshot(at: 0, awake: 100, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 900, awake: 160, pid: 7, cpuNanos: 60_000_000_000))

    #expect(history.sustainedCPU(pid: 7, over: 180) == nil)
}

@Test func ratesAreNilForAProcessThatIsNotInBothSamples() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 10, pid: 8, cpuNanos: 1_000_000_000))

    #expect(history.cpuPercent(pid: 7) == nil)
    #expect(history.cpuPercent(pid: 8) == nil)
}

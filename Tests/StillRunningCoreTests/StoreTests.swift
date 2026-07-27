import Testing
import Foundation
import Synchronization
@testable import StillRunningCore
import Actions
import Detectors
import ProcessKit

/// Replays a fixed list of snapshots, holding the last one once exhausted.
private final class ScriptedSource: SnapshotSource {
    let snapshots: [Snapshot]
    private let cursor = Mutex<Int>(0)

    init(snapshots: [Snapshot]) { self.snapshots = snapshots }

    func sample() async -> Snapshot {
        cursor.withLock { index in
            let snapshot = snapshots[min(index, snapshots.count - 1)]
            index += 1
            return snapshot
        }
    }
}

private final class SpyStopper: Stopping, Sendable {
    private let calls = Mutex<(stopped: [String], forced: [String])>((stopped: [], forced: []))
    private let concurrency = Mutex<(current: Int, peak: Int)>((current: 0, peak: 0))
    private let plannedOutcome: StopOutcome
    private let delay: Duration

    init(outcome: StopOutcome = .stopped, delay: Duration = .zero) {
        self.plannedOutcome = outcome
        self.delay = delay
    }

    var stopped: [String] { calls.withLock { $0.stopped } }
    var forced: [String] { calls.withLock { $0.forced } }
    /// How many stops were ever in flight at the same time.
    var peakConcurrency: Int { concurrency.withLock { $0.peak } }

    func stop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome {
        calls.withLock { $0.stopped.append(finding.identity) }
        concurrency.withLock { $0.current += 1; $0.peak = max($0.peak, $0.current) }
        if delay > .zero { try? await Task.sleep(for: delay) }
        concurrency.withLock { $0.current -= 1 }
        return plannedOutcome
    }

    func forceStop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome {
        calls.withLock { $0.forced.append(finding.identity) }
        return .stopped
    }
}

/// Two samples a minute apart, so History can compute a rate.
private func automationSnapshots(cpuPercent: Double = 60) -> [Snapshot] {
    let base = Fixtures.automationChrome()
    let burned = UInt64(cpuPercent / 100 * 60 * 1_000_000_000)
    let advanced = base.map {
        ProcessSample(pid: $0.pid, ppid: $0.ppid, uid: $0.uid, executablePath: $0.executablePath,
                      arguments: $0.arguments, startedAt: $0.startedAt,
                      hasControllingTTY: $0.hasControllingTTY,
                      cpuTimeNanos: $0.cpuTimeNanos + burned, residentBytes: $0.residentBytes)
    }
    return [Fixtures.snapshot(processes: base, at: Fixtures.now.addingTimeInterval(-60)),
            Fixtures.snapshot(processes: advanced, at: Fixtures.now)]
}

private func cleanDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
private func makeStore(_ name: String, stopper: any Stopping = SpyStopper()) -> Store {
    Store(source: ScriptedSource(snapshots: automationSnapshots()),
          stopper: stopper, defaults: cleanDefaults(name))
}

@MainActor
@Test func refreshPopulatesFindings() async {
    let store = makeStore("store-1")

    await store.refresh()
    await store.refresh()

    #expect(store.findings.count == 1)
    #expect(store.findings[0].kind == .isolatedBrowser)
}

@MainActor
@Test func stopDelegatesToTheStopper() async {
    let spy = SpyStopper()
    let store = makeStore("store-2", stopper: spy)
    await store.refresh(); await store.refresh()

    await store.stop(store.findings[0])

    #expect(spy.stopped.count == 1)
    #expect(store.lastError == nil)
}

@MainActor
@Test func aStillRunningOutcomeMarksTheFindingAsForceable() async {
    let store = makeStore("store-3", stopper: SpyStopper(outcome: .stillRunning))
    await store.refresh(); await store.refresh()
    let identity = store.findings[0].identity

    await store.stop(store.findings[0])

    #expect(store.forceableIdentities.contains(identity))
}

@MainActor
@Test func aRefusalSurfacesAsAReadableError() async {
    let store = makeStore("store-4", stopper: SpyStopper(outcome: .refused(reason: "your browser, with your tabs")))
    await store.refresh(); await store.refresh()

    await store.stop(store.findings[0])

    #expect(store.lastError == "Not stopped — your browser, with your tabs.")
}

@MainActor
@Test func forceStopClearsTheForceableFlag() async {
    let spy = SpyStopper(outcome: .stillRunning)
    let store = makeStore("store-5", stopper: spy)
    await store.refresh(); await store.refresh()
    await store.stop(store.findings[0])

    await store.forceStop(store.findings[0])

    #expect(spy.forced.count == 1)
    #expect(store.forceableIdentities.isEmpty)
}

@MainActor
@Test func keepExcludesAFindingFromLaterRefreshes() async {
    let store = makeStore("store-6")
    await store.refresh(); await store.refresh()

    store.keep(store.findings[0])
    await store.refresh()

    #expect(store.findings.isEmpty)
}

@MainActor
@Test func keepSurvivesANewStoreOnTheSameDefaults() async {
    let defaults = cleanDefaults("store-7")
    let first = Store(source: ScriptedSource(snapshots: automationSnapshots()),
                      stopper: SpyStopper(), defaults: defaults)
    await first.refresh(); await first.refresh()
    first.keep(first.findings[0])

    let second = Store(source: ScriptedSource(snapshots: automationSnapshots()),
                       stopper: SpyStopper(), defaults: defaults)
    await second.refresh(); await second.refresh()

    #expect(second.findings.isEmpty)
}

@MainActor
@Test func onlyTheRowBeingStoppedIsMarkedInFlight() async {
    let store = makeStore("store-10", stopper: SpyStopper(delay: .milliseconds(120)))
    await store.refresh(); await store.refresh()
    let finding = store.findings[0]

    let task = Task { await store.stop(finding) }
    try? await Task.sleep(for: .milliseconds(40))
    #expect(store.isStopping(finding))

    await task.value
    #expect(!store.isStopping(finding))
    #expect(store.inFlight.isEmpty)
}

@MainActor
@Test func stopAllRunsConcurrentlyRatherThanOneAfterAnother() async {
    // Sequentially a stack of containers would take the sum of every grace
    // period; Docker waits ten seconds for anything that ignores SIGTERM.
    let spy = SpyStopper(delay: .milliseconds(120))
    let store = Store(source: ScriptedSource(snapshots: manyContainerSnapshots()),
                      stopper: spy, defaults: cleanDefaults("store-11"))
    await store.refresh(); await store.refresh()
    #expect(store.findings.count == 4)

    await store.stopAll()

    #expect(spy.stopped.count == 4)
    #expect(spy.peakConcurrency == 4)
}

@MainActor
@Test func aSecondStopOfTheSameRowIsIgnoredWhileTheFirstIsInFlight() async {
    let spy = SpyStopper(delay: .milliseconds(120))
    let store = makeStore("store-12", stopper: spy)
    await store.refresh(); await store.refresh()
    let finding = store.findings[0]

    async let first: Void = store.stop(finding)
    try? await Task.sleep(for: .milliseconds(30))
    await store.stop(finding)
    await first

    #expect(spy.stopped.count == 1)
}

private func manyContainerSnapshots() -> [Snapshot] {
    let containers = (1...4).map {
        ContainerSample(id: "c\($0)", name: "svc-\($0)", image: "img:latest",
                        startedAt: Fixtures.now.addingTimeInterval(-20 * 3600))
    }
    return [Fixtures.snapshot(processes: [], containers: containers,
                              at: Fixtures.now.addingTimeInterval(-60)),
            Fixtures.snapshot(processes: [], containers: containers, at: Fixtures.now)]
}

@MainActor
@Test func cadenceIsFiveSecondsOpenAndSixtyClosed() {
    let store = makeStore("store-8")

    store.setPanelOpen(true)
    #expect(store.currentInterval == 5)

    store.setPanelOpen(false)
    #expect(store.currentInterval == 60)
}

@MainActor
@Test func settingsChangesPersist() {
    let defaults = cleanDefaults("store-9")
    let store = Store(source: ScriptedSource(snapshots: automationSnapshots()),
                      stopper: SpyStopper(), defaults: defaults)

    store.settings.minimumAge = 4 * 3600

    #expect(SettingsStore(defaults: defaults).settings.minimumAge == 4 * 3600)
}

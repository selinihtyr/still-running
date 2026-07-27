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
    private let plannedOutcome: StopOutcome

    init(outcome: StopOutcome = .stopped) { self.plannedOutcome = outcome }

    var stopped: [String] { calls.withLock { $0.stopped } }
    var forced: [String] { calls.withLock { $0.forced } }

    func stop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome {
        calls.withLock { $0.stopped.append(finding.identity) }
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

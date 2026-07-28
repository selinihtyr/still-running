import Testing
import Foundation
import Darwin
@testable import StillRunningCore
import Actions
import Detectors
import DockerClient
import ProcessKit
import SimulatorSource

/// Drives the real machine: creates its own targets, stops them through the
/// same code the panel uses, and puts them back.
///
/// These start containers and boot simulators, so they are off unless asked
/// for: `STILL_RUNNING_LIVE_TESTS=1 swift test`. A plain `swift test` — the one
/// CI runs, on a machine with no Docker and no Xcode devices — leaves the
/// system untouched.
private let liveTestsRequested =
    ProcessInfo.processInfo.environment["STILL_RUNNING_LIVE_TESTS"] == "1"
private func shell(_ command: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func liveSnapshot() async -> Snapshot {
    await LiveSnapshotSource().sample()
}

private var eager: Settings {
    var settings = Settings()
    settings.minimumAge = 0   // targets created seconds ago must still qualify
    return settings
}

/// Nobody is obliged to run a container runtime, and a red test for a daemon
/// that simply is not there reads as a broken app.
private var dockerIsRunning: Bool {
    shell("docker info >/dev/null 2>&1 && echo yes") == "yes"
}

@Test(.enabled(if: liveTestsRequested)) func liveContainerStopsAndStartsAgain() async {
    guard dockerIsRunning else {
        print("skipped: no container runtime is running")
        return
    }
    _ = shell("docker rm -f e2e-container 2>/dev/null; docker run -d --name e2e-container alpine sleep 600; sleep 1")
    defer { _ = shell("docker rm -f e2e-container") }

    let snapshot = await liveSnapshot()
    let findings = ContainerDetector().findings(in: snapshot, history: History(), settings: eager)
    guard let target = findings.first(where: { $0.identity == "container:e2e-container" }) else {
        Issue.record("the container was never detected")
        return
    }

    #expect(await StopCoordinator(gracePeriod: 0).stop(target, in: snapshot) == .stopped)
    #expect(shell("docker inspect -f '{{.State.Running}}' e2e-container") == "false")

    #expect(await RestartCoordinator().restart(target) == true)
    #expect(shell("docker inspect -f '{{.State.Running}}' e2e-container") == "true")
}

@Test(.enabled(if: liveTestsRequested)) func liveSimulatorShutsDownAndBootsAgain() async {
    let udid = shell("xcrun simctl list devices available -j | python3 -c \"import json,sys;d=json.load(sys.stdin);print([x['udid'] for v in d['devices'].values() for x in v if 'iPhone' in x['name']][0])\"")
    guard !udid.isEmpty else { return }   // no simulators installed: nothing to prove

    _ = shell("xcrun simctl boot \(udid) 2>/dev/null; sleep 4")
    defer { _ = shell("xcrun simctl shutdown \(udid) 2>/dev/null") }

    let snapshot = await liveSnapshot()
    let findings = SimulatorDetector().findings(in: snapshot, history: History(), settings: eager)
    guard let target = findings.first(where: { $0.target == .simulator(udid) }) else {
        Issue.record("the booted simulator was never detected")
        return
    }

    #expect(await StopCoordinator(gracePeriod: 0).stop(target, in: snapshot) == .stopped)
    #expect(shell("xcrun simctl list devices booted | grep -c \(udid)") == "0")

    #expect(await RestartCoordinator().restart(target) == true)
    #expect(shell("sleep 4; xcrun simctl list devices booted | grep -c \(udid)") == "1")
}

@Test func liveProcessTakesTheSignalAndDies() async {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["600"]
    try? child.run()
    let pid = child.processIdentifier
    #expect(pid > 0)

    let snapshot = await liveSnapshot()
    let finding = Finding(identity: "e2e", kind: .devServer, title: "sleep", detail: "test",
                          cpuPercent: 0, memoryBytes: 0, age: 10_000,
                          target: .processes([pid]), severity: .notable)

    #expect(await StopCoordinator(gracePeriod: 2).stop(finding, in: snapshot) == .stopped)
    #expect(kill(pid, 0) != 0)   // gone
}

@Test func liveGuardRefusesTheUsersOwnBrowser() async {
    let snapshot = await liveSnapshot()
    // The root browser process, not a helper: Chrome retires renderers on its
    // own schedule, and a helper can be gone before the assertion runs.
    let ownBrowser = snapshot.processes.first {
        IsolatedBrowserDetector.isBrowser($0)
            && IsolatedBrowserDetector.isolationSignature($0) == nil
            && $0.uid == snapshot.currentUID
            && !$0.executablePath.contains("Helper")
            && $0.executablePath.hasSuffix("/MacOS/\($0.name)")
    }
    guard let ownBrowser else { return }   // no browser running: nothing to prove

    let finding = Finding(identity: "e2e-browser", kind: .isolatedBrowser, title: "your browser",
                          detail: "", cpuPercent: 0, memoryBytes: 0, age: 10_000,
                          target: .processes([ownBrowser.pid]), severity: .notable)

    #expect(await StopCoordinator(gracePeriod: 0).stop(finding, in: snapshot)
            == .refused(reason: "your browser, with your tabs"))
    #expect(kill(ownBrowser.pid, 0) == 0)   // still alive
}

@Test func aProcessPinningACoreReadsAsPinningACore() async {
    // The regression this guards: proc_taskinfo reports Mach time units, and
    // reading them as nanoseconds made a busy loop read as 2%.
    let burner = Process()
    burner.executableURL = URL(fileURLWithPath: "/bin/sh")
    burner.arguments = ["-c", "while :; do :; done"]
    try? burner.run()
    defer { burner.terminate() }

    let source = LiveProcessSource()
    var history = History()
    history.record(Snapshot(takenAt: Date(), processes: source.processes(), containers: [],
                            simulators: [], currentUID: getuid(), ownPID: 0))
    try? await Task.sleep(for: .seconds(2))
    history.record(Snapshot(takenAt: Date(), processes: source.processes(), containers: [],
                            simulators: [], currentUID: getuid(), ownPID: 0))

    let measured = history.cpuPercent(pid: burner.processIdentifier)
    print("busy loop measured at \(Int(measured ?? -1))%")
    #expect(measured ?? 0 > 50)
}

@Test func openingThePanelDoesNotReadABurstAsASteadyRate() async {
    // The regression this guards: opening the panel samples immediately, which
    // can land a fraction of a second after the background timer's own sample.
    // A process that happens to be busy in that fraction used to fill the row
    // the user is looking at with a number describing an instant — and a group
    // like a browser's, whose helpers are counted together, reads in the
    // hundreds that way.
    let burner = Process()
    burner.executableURL = URL(fileURLWithPath: "/bin/sh")
    // Idle first, so the long gap has nothing in it, then pins a core.
    burner.arguments = ["-c", "sleep 8; while :; do :; done"]
    let launched = Date()
    try? burner.run()
    defer { burner.terminate() }

    let source = LiveProcessSource()
    var history = History()
    func sample() {
        history.record(Snapshot(takenAt: Date(), processes: source.processes(), containers: [],
                                simulators: [], currentUID: getuid(), ownPID: 0,
                                awakeUptime: ProcessInfo.processInfo.systemUptime))
    }
    func sleep(until seconds: TimeInterval) async {
        let remaining = seconds - Date().timeIntervalSince(launched)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
    }

    await sleep(until: 0.3);  sample()   // the timer's sample, burner idle
    await sleep(until: 8.3);  sample()   // the next one, still idle: it just woke
    await sleep(until: 8.9);  sample()   // opening the panel, mid-burst

    let pid = burner.processIdentifier
    // `measuredOver: 0` is the old behaviour: whatever the newest gap happens
    // to be, here six hundred milliseconds of a pinned core.
    let fromTheGap = history.cpuPercent(pid: pid, measuredOver: 0) ?? 0
    let measured = history.cpuPercent(pid: pid) ?? 0
    print("burst read from a 0.6s gap: \(Int(fromTheGap))%, measured over five seconds: \(Int(measured))%")

    #expect(fromTheGap > 70)
    #expect(measured < 30)
}

@Test func aRealCaffeinateIsReadOffTheRealAssertionTable() async {
    // The whole feature rests on IOKit handing an unsigned, unprivileged app
    // the system-wide assertion list. If that ever stops being true this test
    // is the one that says so.
    let held = Process()
    held.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    held.arguments = ["-i", "-t", "20"]     // times out on its own, so a crash here cannot leave the Mac awake
    try? held.run()
    defer { held.terminate() }
    try? await Task.sleep(for: .seconds(1))

    let assertions = LivePowerAssertions().assertions()
    let mine = assertions.first { $0.pid == held.processIdentifier }

    #expect(mine != nil)
    #expect(mine?.preventsSleep == true)
    // Created with -t, so the app must read it as something that releases
    // itself rather than something anybody forgot.
    #expect(mine?.expiresOnItsOwn == true)
    print("read \(assertions.count) assertions; mine: \(mine?.type ?? "none") \"\(mine?.name ?? "")\"")
}

/// Stands in for the assertion table so a test never has to create a real
/// promise with no timeout on it. A crashed test that left one behind would
/// keep the machine awake all night, which is the exact bug this app is about.
private struct StubAssertions: PowerAssertionSource {
    let held: [PowerAssertionSample]
    func assertions() -> [PowerAssertionSample] { held }
}

@Test func aForgottenPromiseBecomesARowWithAStopButton() async {
    // Everything here is real except the assertion: a real process table, the
    // real snapshot, the real engine, and a real pid to stop.
    let tool = Process()
    tool.executableURL = URL(fileURLWithPath: "/bin/sleep")
    tool.arguments = ["30"]
    try? tool.run()
    defer { tool.terminate() }

    let source = LiveSnapshotSource(power: StubAssertions(held: [
        PowerAssertionSample(pid: tool.processIdentifier, type: "PreventUserIdleSystemSleep",
                             name: "caffeinate command-line tool", processName: "sleep",
                             startedAt: Date().addingTimeInterval(-4 * 3600)),
    ]))
    let snapshot = await source.sample()
    var history = History()
    history.record(snapshot)

    let result = DetectorEngine().evaluate(snapshot: snapshot, history: history,
                                           settings: Settings(), excluded: [])
    let row = result.findings.first { $0.kind == .keepingAwake }

    #expect(row != nil)
    #expect(row?.target == .processes([tool.processIdentifier]))
    #expect(row?.age ?? 0 >= 4 * 3600)
    // A tool is safe to offer up, so it is a finding rather than a name in the
    // list below.
    #expect(!result.keepingAwake.contains { $0.pid == tool.processIdentifier })
    print("row: \(row?.title ?? "none") — \(row?.detail ?? "")")
}

@Test func arealForgottenCaffeinateBecomesARealRow() async {
    // No stubs anywhere in this one: a real assertion with no timeout on it, the
    // real IOKit table, the real process list, the real engine. The shell
    // wrapper kills it after eight seconds whatever happens here, so a test
    // that dies badly still cannot be the thing that keeps the Mac awake.
    let wrapper = Process()
    wrapper.executableURL = URL(fileURLWithPath: "/bin/sh")
    wrapper.arguments = ["-c", "caffeinate -i & CAF=$!; sleep 8; kill $CAF 2>/dev/null"]
    try? wrapper.run()
    defer { wrapper.terminate() }
    try? await Task.sleep(for: .seconds(1))

    let snapshot = await LiveSnapshotSource().sample()
    var history = History()
    history.record(snapshot)

    // Everything real about it is real; only the patience is shortened, since
    // waiting half an hour for the threshold is not a test.
    var settings = Settings()
    settings.awakeMinimumHold = 0

    let result = DetectorEngine().evaluate(snapshot: snapshot, history: history,
                                           settings: settings, excluded: [])
    let row = result.findings.first { $0.kind == .keepingAwake && $0.title.hasPrefix("caffeinate") }

    #expect(row != nil)
    #expect(row?.detail.contains("caffeinate") == true)
    print("live row: \(row?.title ?? "none") — \(row?.detail ?? "") — \(row?.explanation ?? "")")
}

@Test func liveSamplingStaysCheap() async {
    let source = LiveSnapshotSource()
    _ = await source.sample()   // warm the caches

    let start = Date()
    for _ in 0..<3 { _ = await source.sample() }
    let average = Date().timeIntervalSince(start) / 3 * 1000

    print("average sample: \(Int(average))ms")
    // Five seconds apart, 200ms would already be 4% of a core, forever. A
    // shared CI runner is not the machine this budget is about — it measured
    // 230ms there while a laptop takes 8 — so the ceiling there is only loose
    // enough to catch the regression this guards against: the sweep that read
    // every process's arguments and cost 614ms.
    let budget: Double = ProcessInfo.processInfo.environment["CI"] == nil ? 200 : 500
    #expect(average < budget)
}

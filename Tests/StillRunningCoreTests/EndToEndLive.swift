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
/// same code the panel uses, and puts them back. Temporary — it has side
/// effects and must never run in CI.
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

@Test func liveContainerStopsAndStartsAgain() async {
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

@Test func liveSimulatorShutsDownAndBootsAgain() async {
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

@Test func liveSamplingStaysCheap() async {
    let source = LiveSnapshotSource()
    _ = await source.sample()   // warm the caches

    let start = Date()
    for _ in 0..<3 { _ = await source.sample() }
    let average = Date().timeIntervalSince(start) / 3 * 1000

    print("average sample: \(Int(average))ms")
    // Five seconds apart, 200ms would already be 4% of a core, forever.
    #expect(average < 200)
}

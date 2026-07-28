import Testing
import Foundation
@testable import Detectors
import ProcessKit

// MARK: - Dev servers you are actually using

@Test func doesNotListADevServerYouAreWorkingAgainst() {
    // It is old, but it recompiled something a minute ago. That is a server in
    // use, not one you forgot.
    let process = Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node",
                                   args: ["node", "vite"], ageHours: 9)
    var history = History()
    var burned: UInt64 = 0
    for step in 0..<10 {
        // One busy interval in the middle of the window.
        burned += step == 5 ? 30_000_000_000 : 0
        let sample = ProcessSample(pid: 4100, ppid: 1, uid: 501,
                                   executablePath: process.executablePath, arguments: process.arguments,
                                   startedAt: process.startedAt, hasControllingTTY: false,
                                   cpuTimeNanos: burned, residentBytes: process.residentBytes)
        history.record(Fixtures.snapshot(processes: [sample],
                                         at: Fixtures.now.addingTimeInterval(Double(step - 9) * 60)))
    }
    let findings = DevServerDetector().findings(in: history.latest!, history: history, settings: Settings())

    #expect(findings.isEmpty)
}

@Test func stillListsADevServerThatHasDoneNothingAtAll() {
    let process = Fixtures.process(pid: 4200, path: "/opt/homebrew/bin/node",
                                   args: ["node", "vite"], ageHours: 9)
    var history = History()
    for step in 0..<10 {
        history.record(Fixtures.snapshot(processes: [process],
                                         at: Fixtures.now.addingTimeInterval(Double(step - 9) * 60)))
    }
    let findings = DevServerDetector().findings(in: history.latest!, history: history, settings: Settings())

    #expect(findings.count == 1)
}

@Test func withNoHistoryYetADevServerIsStillListed() {
    // Cold start: no evidence either way, and staying silent would mean
    // showing nothing for the first ten minutes after launch.
    let processes = [Fixtures.process(pid: 4300, path: "/opt/homebrew/bin/node",
                                      args: ["node", "vite"], ageHours: 9)]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes), history: History(), settings: Settings())

    #expect(findings.count == 1)
}

// MARK: - Android emulators

private func emulatorProcesses(ageHours: Double = 6) -> [ProcessSample] {
    [
        Fixtures.process(pid: 7000, path: "/Users/x/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64",
                         args: ["qemu-system-aarch64", "-avd", "Pixel_7_API_34", "-no-snapshot"],
                         ageHours: ageHours, rssMB: 2400),
        Fixtures.process(pid: 7001, ppid: 7000,
                         path: "/Users/x/Library/Android/sdk/emulator/emulator64-crash-service",
                         args: ["emulator64-crash-service"], ageHours: ageHours, rssMB: 20),
    ]
}

@Test func findsAnAndroidEmulatorAndNamesItAfterTheDevice() {
    let processes = emulatorProcesses()
    let findings = AndroidEmulatorDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 30), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].title == "Pixel 7 API 34")
    #expect(findings[0].memoryBytes == 2420 * 1_048_576)
    #expect(findings[0].kind == .simulator)
}

@Test func groupsAnEmulatorsHelpersIntoTheOneDevice() {
    let processes = emulatorProcesses()
    let findings = AndroidEmulatorDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 10), settings: Settings())

    guard case .processes(let pids) = findings[0].target else {
        Issue.record("expected a process target")
        return
    }
    #expect(pids == [7000, 7001])
}

@Test func ignoresAnEmulatorStartedMinutesAgo() {
    let processes = emulatorProcesses(ageHours: 0.1)
    let findings = AndroidEmulatorDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 10), settings: Settings())

    #expect(findings.isEmpty)
}

// MARK: - Tunnels

@Test func findsAnOpenTunnelAndSaysWhatItPublishes() {
    let processes = [Fixtures.process(
        pid: 8000, path: "/opt/homebrew/bin/cloudflared",
        args: ["cloudflared", "tunnel", "--url", "http://localhost:4325"], ageHours: 30)]
    let findings = TunnelDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].kind == .tunnel)
    #expect(findings[0].detail == "http://localhost:4325")
    #expect(findings[0].severity == .urgent)   // an open door is never merely notable
}

@Test func readsAPortFromAnNgrokCommand() {
    let processes = [Fixtures.process(pid: 8001, path: "/opt/homebrew/bin/ngrok",
                                      args: ["ngrok", "http", "3000"], ageHours: 5)]
    let findings = TunnelDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings[0].detail == "port 3000")
}

@Test func leavesATunnelInstalledAsAServiceAlone() {
    let process = Fixtures.process(pid: 8002, path: "/opt/homebrew/bin/cloudflared",
                                   args: ["cloudflared", "tunnel", "run"], ageHours: 40)
    let snapshot = Snapshot(takenAt: Fixtures.now, processes: [process], containers: [],
                            simulators: [], currentUID: 501, ownPID: 999, managedPIDs: [8002])
    let findings = TunnelDetector().findings(
        in: snapshot, history: Fixtures.history([process], cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresATunnelOpenedAMomentAgo() {
    let processes = [Fixtures.process(pid: 8003, path: "/opt/homebrew/bin/ngrok",
                                      args: ["ngrok", "http", "3000"], ageHours: 0.05)]
    let findings = TunnelDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

// MARK: - Rows that explain themselves

@Test func everyFindingSaysWhatItIsInPlainWords() {
    let processes = Fixtures.automationChrome() + emulatorProcesses() + [
        Fixtures.process(pid: 8000, path: "/opt/homebrew/bin/ngrok",
                         args: ["ngrok", "http", "3000"], ageHours: 5)]
    let containers = [ContainerSample(id: "c1", name: "api", image: "api:latest",
                                      startedAt: Fixtures.now.addingTimeInterval(-20 * 3600))]
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes, containers: containers),
        history: Fixtures.history(processes, cpuPercent: 10))

    #expect(result.findings.count >= 4)
    for finding in result.findings {
        #expect(finding.explanation.count > 40)          // a sentence, not a label
        #expect(!finding.explanation.contains("nil"))
        #expect(!finding.details.isEmpty)
    }
}

@Test func anAutomationBrowserSaysWhatStartedItAndWhereItLives() {
    // The path is already on the row and behind the Finder link. What the row
    // could not answer was "where did this come from".
    let processes = Fixtures.automationChrome()
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 10), settings: Settings())

    #expect(findings[0].revealPath == "/tmp/claude-cdp-prof")
    #expect(findings[0].explanation.contains("Claude Code"))
    #expect(findings[0].explanation.contains("temporary folder"))
    #expect(findings[0].command?.contains("--user-data-dir=/tmp/claude-cdp-prof") == true)
    #expect(findings[0].details.contains("pid 23947"))
}

@Test func namesTheToolFromACommandLineWhenThePathDoesNotSayIt() {
    let processes = [Fixtures.process(
        pid: 9100, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        args: ["Google Chrome", "--user-data-dir=/var/folders/x/T/run-1234",
               "--remote-debugging-pipe", "--enable-automation", "playwright"],
        ageHours: 5)]
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings[0].explanation.contains("Playwright"))
}

@Test func saysNothingAboutAToolItCannotIdentify() {
    // Better to say less than to guess at where something came from.
    let processes = [Fixtures.process(
        pid: 9200, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        args: ["Google Chrome", "--user-data-dir=/Users/x/scratch/profile"], ageHours: 5)]
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(!findings[0].explanation.contains("started it"))
}

@Test func aContainerCarriesTheCommandsYouWouldHaveTyped() {
    let containers = [ContainerSample(id: "abc123", name: "api", image: "api:latest",
                                      startedAt: Fixtures.now.addingTimeInterval(-20 * 3600))]
    let findings = ContainerDetector().findings(
        in: Fixtures.snapshot(processes: [], containers: containers),
        history: History(), settings: Settings())

    #expect(findings[0].details.contains("docker logs api"))
    #expect(findings[0].revealPath == nil)   // a container is not a folder
}

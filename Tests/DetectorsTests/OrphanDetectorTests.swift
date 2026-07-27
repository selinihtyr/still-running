import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func flagsAReparentedProcessWithNoTerminal() {
    // The classic leftover: its terminal is gone, launchd adopted it.
    let processes = [Fixtures.process(
        pid: 7100, ppid: 1, path: "/opt/homebrew/bin/ffmpeg",
        args: ["ffmpeg", "-i", "in.mov", "out.mp4"], ageHours: 3, tty: false, rssMB: 200)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 70), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].kind == .orphan)
    #expect(findings[0].severity == .urgent)
}

@Test func ignoresApplicationBundlesAdoptedByLaunchd() {
    // Every running .app has ppid 1. None of them are orphans.
    let processes = Fixtures.defaultChrome()
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 80), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresProcessesThatStillHaveATerminal() {
    let processes = [Fixtures.process(
        pid: 7200, ppid: 1, path: "/opt/homebrew/bin/ffmpeg",
        args: ["ffmpeg"], ageHours: 3, tty: true)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 70), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresSystemAgentsUnderLaunchd() {
    let processes = Fixtures.system()
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 5), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresProcessesInSystemDirectories() {
    let processes = [Fixtures.process(
        pid: 7300, ppid: 1, path: "/usr/libexec/trustd", args: ["trustd"], ageHours: 40)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresAppleXPCServicesUnderLibraryDeveloper() {
    // Observed on a real machine: CoreSimulator and CoreDevice ship XPC
    // services that launchd owns forever. They are not leftovers, and they
    // live in .xpc bundles rather than .app bundles.
    let processes = [
        Fixtures.process(
            pid: 1415,
            path: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc/Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService",
            args: ["com.apple.CoreSimulator.CoreSimulatorService"], ageHours: 52),
        Fixtures.process(
            pid: 1427,
            path: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/SimulatorTrampoline.xpc/Contents/MacOS/SimulatorTrampoline",
            args: ["SimulatorTrampoline"], ageHours: 52),
    ]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresAppExtensionsAndFrameworkHelpers() {
    let processes = [
        Fixtures.process(pid: 9100,
                         path: "/Applications/Some.app/Contents/PlugIns/Helper.appex/Contents/MacOS/Helper",
                         args: ["Helper"], ageHours: 10),
        Fixtures.process(pid: 9200,
                         path: "/Library/Frameworks/Thing.framework/Versions/A/Helper",
                         args: ["Helper"], ageHours: 10),
    ]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresServicesLaunchdManagesOnPurpose() {
    // A LaunchAgent or brew service is indistinguishable from an orphan in the
    // process table: parent 1, no terminal. Only launchd knows the difference.
    let process = Fixtures.process(
        pid: 512, path: "/Users/x/.rvmp/dist/darwin-arm64/bin/rvmp", args: ["rvmp"], ageHours: 53)
    let snapshot = Snapshot(takenAt: Fixtures.now, processes: [process], containers: [],
                            simulators: [], currentUID: 501, ownPID: 999, managedPIDs: [512])

    let findings = OrphanDetector().findings(
        in: snapshot, history: Fixtures.history([process], cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func stillFlagsAnUnmanagedProcessWhenOtherJobsAreManaged() {
    let process = Fixtures.process(
        pid: 9400, path: "/Users/x/bin/leftover", args: ["leftover"], ageHours: 6)
    let snapshot = Snapshot(takenAt: Fixtures.now, processes: [process], containers: [],
                            simulators: [], currentUID: 501, ownPID: 999, managedPIDs: [512, 504])

    let findings = OrphanDetector().findings(
        in: snapshot, history: Fixtures.history([process], cpuPercent: 0), settings: Settings())

    #expect(findings.count == 1)
}

@Test func stillFlagsAPlainBinaryInAUserDirectory() {
    let processes = [Fixtures.process(
        pid: 9300, path: "/Users/x/.bun/bin/bun", args: ["bun", "run", "worker.ts"], ageHours: 6)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.count == 1)
}

@Test func leavesAutomationBrowsersToTheBrowserDetector() {
    let processes = Fixtures.automationChrome()
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 40), settings: Settings())

    #expect(findings.isEmpty)
}

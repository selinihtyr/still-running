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

@Test func leavesAutomationBrowsersToTheBrowserDetector() {
    let processes = Fixtures.automationChrome()
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 40), settings: Settings())

    #expect(findings.isEmpty)
}

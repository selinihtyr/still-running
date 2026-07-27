import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func flagsAnAutomationProfileBrowser() {
    let processes = Fixtures.automationChrome() + Fixtures.defaultChrome() + Fixtures.system()
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 60), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].kind == .isolatedBrowser)
    #expect(findings[0].detail.contains("/tmp/claude-cdp-prof"))
}

@Test func neverFlagsTheUsersOwnBrowser() {
    // The regression that matters: the user's real tabs must never be offered.
    let processes = Fixtures.defaultChrome() + Fixtures.system()
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 95), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func groupsTheWholeProfileTreeIntoOneFinding() {
    let processes = Fixtures.automationChrome()
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 40), settings: Settings())

    #expect(findings.count == 1)
    guard case .processes(let pids) = findings[0].target else {
        Issue.record("expected a process target")
        return
    }
    #expect(pids.count == 3)
    #expect(pids.first == 23947)                          // root first, so SIGTERM tears down the tree
    #expect(findings[0].memoryBytes == 750 * 1_048_576)   // aggregated across the tree
    #expect(findings[0].cpuPercent == 120)                // three processes at 40%
}

@Test func ignoresAYoungQuietAutomationBrowser() {
    // Started two minutes ago and idle: probably a tool run in progress.
    let processes = Fixtures.automationChrome(ageHours: 0.03)
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func treatsAProfileInsideTheStandardLocationAsTheUsersOwn() {
    let home = NSHomeDirectory()
    let processes = [Fixtures.process(
        pid: 5000, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        args: ["Google Chrome", "--user-data-dir=\(home)/Library/Application Support/Google/Chrome"],
        ageHours: 20)]
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 90), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func flagsAHeadlessBrowserEvenWithoutAProfileFlag() {
    let processes = [Fixtures.process(
        pid: 6000, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        args: ["Google Chrome", "--headless=new"], ageHours: 5)]
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    #expect(findings.count == 1)
}

@Test func aBusyAutomationBrowserIsUrgent() {
    let processes = Fixtures.automationChrome()
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 60), settings: Settings())

    #expect(findings[0].severity == .urgent)
}

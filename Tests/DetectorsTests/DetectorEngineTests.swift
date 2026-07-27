import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func collectsFindingsFromEveryDetector() {
    let processes = Fixtures.automationChrome() + Fixtures.defaultChrome() + Fixtures.system() + [
        Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node",
                         args: ["node", "vite"], ageHours: 9)]
    let containers = [ContainerSample(id: "c1", name: "selene-api", image: "api:latest",
                                      startedAt: Fixtures.now.addingTimeInterval(-22 * 3600))]
    let result = DetectorEngine().evaluate(
        snapshot: Fixtures.snapshot(processes: processes, containers: containers),
        history: Fixtures.history(processes, cpuPercent: 30),
        settings: Settings(), excluded: [])

    #expect(result.findings.contains { $0.kind == .isolatedBrowser })
    #expect(result.findings.contains { $0.kind == .devServer })
    #expect(result.findings.contains { $0.kind == .container })
}

@Test func sortsBySeverityThenCPU() {
    let processes = Fixtures.automationChrome() + [
        Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node", args: ["node", "vite"], ageHours: 9)]
    let result = DetectorEngine().evaluate(
        snapshot: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 30),
        settings: Settings(), excluded: [])

    let severities = result.findings.map(\.severity)
    #expect(severities == severities.sorted(by: >))
}

@Test func dropsExcludedIdentities() {
    let processes = Fixtures.automationChrome()
    let snapshot = Fixtures.snapshot(processes: processes)
    let history = Fixtures.history(processes, cpuPercent: 30)
    let all = DetectorEngine().evaluate(snapshot: snapshot, history: history,
                                        settings: Settings(), excluded: [])

    let filtered = DetectorEngine().evaluate(snapshot: snapshot, history: history,
                                             settings: Settings(),
                                             excluded: [all.findings[0].identity])

    #expect(filtered.findings.isEmpty)
}

@Test func neverEmitsTwoFindingsForTheSameProcess() {
    // An automation browser is both isolated and parented by launchd.
    let processes = Fixtures.automationChrome()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 30))

    let pids = result.findings.flatMap { finding -> [Int32] in
        if case .processes(let list) = finding.target { return list }
        return []
    }
    #expect(pids.count == Set(pids).count)
}

@Test func alsoHotListsHeavyProcessesThatAreNotFindings() {
    let processes = Fixtures.defaultChrome() + Fixtures.system()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 45))

    #expect(result.findings.isEmpty)
    #expect(result.alsoHot.contains { $0.name.contains("Google Chrome") })
    #expect(result.alsoHot.allSatisfy { $0.cpuPercent >= 20 })
    #expect(result.alsoHot.count <= 5)
}

@Test func alsoHotExcludesProcessesAlreadySurfacedAsFindings() {
    let processes = Fixtures.automationChrome()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 60))

    #expect(!result.findings.isEmpty)
    #expect(result.alsoHot.isEmpty)
}

@Test func neverReportsItselfAsBusy() {
    let itself = Fixtures.process(pid: 999, path: "/Applications/Still Running.app/Contents/MacOS/StillRunning",
                                  args: ["StillRunning"], ageHours: 1, rssMB: 60)
    let processes = [itself] + Fixtures.system()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 60))

    #expect(!result.alsoHot.contains { $0.pid == 999 })
}

@Test func aQuietMachineProducesNothing() {
    let processes = Fixtures.system()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0))

    #expect(result == .empty)
}

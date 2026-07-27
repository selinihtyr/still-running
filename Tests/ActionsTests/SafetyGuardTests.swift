import Testing
import Foundation
@testable import Actions
import Detectors
import ProcessKit

private func finding(target: StopTarget, kind: FindingKind = .devServer) -> Finding {
    Finding(identity: "test", kind: kind, title: "t", detail: "d", cpuPercent: 10,
            memoryBytes: 0, age: 10_000, target: target, severity: .notable)
}

@Test func allowsAnOrdinaryUserProcess() throws {
    let process = Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node", args: ["node"], ageHours: 5)

    try SafetyGuard().vet(finding(target: .processes([4100])), in: Fixtures.snapshot(processes: [process]))
}

@Test func refusesProtectedSystemProcessesByName() {
    let snapshot = Fixtures.snapshot(processes: Fixtures.system())

    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([164])), in: snapshot)   // WindowServer
    }
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([418])), in: snapshot)   // Finder
    }
}

@Test func refusesLowPIDs() {
    let process = Fixtures.process(pid: 42, path: "/opt/homebrew/bin/node", args: ["node"], ageHours: 5)

    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([42])), in: Fixtures.snapshot(processes: [process]))
    }
}

@Test func refusesProcessesOwnedByAnotherUser() {
    let process = Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node", args: ["node"],
                                   ageHours: 5, uid: 0)

    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([4100])), in: Fixtures.snapshot(processes: [process]))
    }
}

@Test func refusesToStopItself() {
    let process = Fixtures.process(
        pid: 5100, path: "/Applications/Still Running.app/Contents/MacOS/StillRunning",
        args: ["StillRunning"], ageHours: 1)

    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([5100])), in: Fixtures.snapshot(processes: [process]))
    }
}

@Test func refusesTheProcessMatchingOwnPID() {
    let process = Fixtures.process(pid: 999, path: "/opt/homebrew/bin/node", args: ["node"], ageHours: 1)

    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([999])), in: Fixtures.snapshot(processes: [process]))
    }
}

@Test func refusesTheUsersDefaultProfileBrowser() {
    // Defence in depth: even if a detector produced this, the guard stops it.
    let snapshot = Fixtures.snapshot(processes: Fixtures.defaultChrome())

    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([14914]), kind: .isolatedBrowser), in: snapshot)
    }
}

@Test func allowsAnAutomationProfileBrowser() throws {
    let snapshot = Fixtures.snapshot(processes: Fixtures.automationChrome())

    try SafetyGuard().vet(finding(target: .processes([23947]), kind: .isolatedBrowser), in: snapshot)
}

@Test func refusesTheWholeGroupWhenOneMemberIsProtected() {
    let snapshot = Fixtures.snapshot(processes: Fixtures.automationChrome() + Fixtures.system())

    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([23947, 164])), in: snapshot)
    }
}

@Test func refusesAnUnknownPID() {
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([12345])), in: Fixtures.snapshot(processes: []))
    }
}

@Test func allowsContainerAndSimulatorTargets() throws {
    let snapshot = Fixtures.snapshot(processes: [])

    try SafetyGuard().vet(finding(target: .container("abc"), kind: .container), in: snapshot)
    try SafetyGuard().vet(finding(target: .simulator("A1B2"), kind: .simulator), in: snapshot)
}

@Test func noDetectorOnARealisticMachineEverProducesAProtectedTarget() {
    // The whole pipeline, end to end: nothing the engine emits may be refused.
    let processes = Fixtures.automationChrome() + Fixtures.defaultChrome() + Fixtures.system() + [
        Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node", args: ["node", "vite"], ageHours: 9),
        Fixtures.process(pid: 7100, path: "/opt/homebrew/bin/ffmpeg", args: ["ffmpeg"], ageHours: 3),
    ]
    let snapshot = Fixtures.snapshot(processes: processes)
    let result = DetectorEngine().evaluate(
        in: snapshot, history: Fixtures.history(processes, cpuPercent: 40))

    #expect(!result.findings.isEmpty)
    for found in result.findings {
        #expect(throws: Never.self) { try SafetyGuard().vet(found, in: snapshot) }
    }
}

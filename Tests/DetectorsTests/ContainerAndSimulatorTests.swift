import Testing
import Foundation
@testable import Detectors
import ProcessKit

private func container(name: String, hoursUp: Double) -> ContainerSample {
    ContainerSample(id: "id-\(name)", name: name, image: "\(name):latest",
                    startedAt: Fixtures.now.addingTimeInterval(-hoursUp * 3600))
}

@Test func flagsEachLongRunningContainer() {
    let snapshot = Fixtures.snapshot(
        processes: [],
        containers: [container(name: "selene-api", hoursUp: 22),
                     container(name: "selene-postgres", hoursUp: 22)])
    let findings = ContainerDetector().findings(in: snapshot, history: History(), settings: Settings())

    #expect(findings.count == 2)
    #expect(findings.allSatisfy { $0.kind == .container })
    #expect(findings.allSatisfy {
        if case .container = $0.target { return true } else { return false }
    })
}

@Test func ignoresContainersStartedMinutesAgo() {
    let snapshot = Fixtures.snapshot(processes: [], containers: [container(name: "fresh", hoursUp: 0.1)])

    #expect(ContainerDetector().findings(in: snapshot, history: History(), settings: Settings()).isEmpty)
}

@Test func containerIdentityUsesTheNameSoItSurvivesRecreation() {
    let snapshot = Fixtures.snapshot(processes: [], containers: [container(name: "selene-api", hoursUp: 22)])
    let findings = ContainerDetector().findings(in: snapshot, history: History(), settings: Settings())

    #expect(findings[0].identity == "container:selene-api")
}

@Test func flagsASimulatorBootedHoursAgo() {
    let simulator = SimulatorSample(id: "A1B2", name: "iPhone 17 Pro", runtime: "iOS 26.5",
                                    bootedAt: Fixtures.now.addingTimeInterval(-5 * 3600))
    let findings = SimulatorDetector().findings(
        in: Fixtures.snapshot(processes: [], simulators: [simulator]),
        history: History(), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].target == .simulator("A1B2"))
    #expect(findings[0].title.contains("iPhone 17 Pro"))
}

@Test func ignoresASimulatorBootedMinutesAgo() {
    let simulator = SimulatorSample(id: "A1B2", name: "iPhone 17 Pro", runtime: "iOS 26.5",
                                    bootedAt: Fixtures.now.addingTimeInterval(-120))

    #expect(SimulatorDetector().findings(
        in: Fixtures.snapshot(processes: [], simulators: [simulator]),
        history: History(), settings: Settings()).isEmpty)
}

@Test func flagsASimulatorWithAnUnknownBootTime() {
    // Boot time could not be resolved; being booted at all is still worth showing.
    let simulator = SimulatorSample(id: "A1B2", name: "iPhone 17 Pro", runtime: "iOS 26.5", bootedAt: nil)
    let findings = SimulatorDetector().findings(
        in: Fixtures.snapshot(processes: [], simulators: [simulator]),
        history: History(), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].detail.contains("booted"))
}

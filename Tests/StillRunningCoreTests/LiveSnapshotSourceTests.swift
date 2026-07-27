import Testing
import Foundation
@testable import StillRunningCore
import ProcessKit
import SimulatorSource

private struct StubSimulators: SimulatorControl {
    let devices: [BootedSimulator]
    func booted() async throws -> [BootedSimulator] { devices }
    func shutdown(udid: String) async throws {}
    func boot(udid: String) async throws {}
}

@Test func resolvesSimulatorBootTimeFromItsLaunchdProcess() {
    let udid = "A1B2-C3D4"
    let bootTime = Date(timeIntervalSince1970: 1_785_000_000)
    let launchdSim = ProcessSample(
        pid: 8100, ppid: 1, uid: 501,
        executablePath: "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/sbin/launchd_sim",
        arguments: ["launchd_sim", "/Users/x/Library/Developer/CoreSimulator/Devices/\(udid)/data"],
        startedAt: bootTime, hasControllingTTY: false, cpuTimeNanos: 0, residentBytes: 0)

    #expect(LiveSnapshotSource.bootTime(forSimulator: udid, in: [launchdSim]) == bootTime)
}

@Test func returnsNilBootTimeWhenNoLaunchdProcessMatches() {
    #expect(LiveSnapshotSource.bootTime(forSimulator: "A1B2", in: []) == nil)
}

@Test func liveSampleIncludesTheCurrentProcessAndIsInternallyConsistent() async {
    let source = LiveSnapshotSource(simulators: StubSimulators(devices: []))
    let snapshot = await source.sample()

    #expect(snapshot.ownPID == ProcessInfo.processInfo.processIdentifier)
    #expect(snapshot.currentUID == getuid())
    #expect(snapshot.processes.contains { $0.pid == snapshot.ownPID })
    #expect(snapshot.takenAt.timeIntervalSinceNow > -5)
}

@Test func aMissingDockerDaemonDoesNotBreakTheSnapshot() async {
    let source = LiveSnapshotSource(docker: nil, simulators: StubSimulators(devices: []))
    let snapshot = await source.sample()

    #expect(snapshot.containers.isEmpty)
    #expect(!snapshot.processes.isEmpty)
}

@Test func simulatorsWithoutALaunchdProcessStillAppear() async {
    let source = LiveSnapshotSource(
        docker: nil,
        simulators: StubSimulators(devices: [
            BootedSimulator(udid: "NOT-RUNNING", name: "iPhone 17", runtime: "iOS 26.5")]))
    let snapshot = await source.sample()

    #expect(snapshot.simulators.count == 1)
    #expect(snapshot.simulators[0].bootedAt == nil)
}

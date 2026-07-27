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

@Test func simctlIsOnlyConsultedWhenADeviceIsActuallyBooted() {
    // Spawning simctl is the most expensive part of a sample, and a booted
    // device always leaves a launchd_sim behind.
    let ordinary = ProcessSample(
        pid: 100, ppid: 1, uid: 501, executablePath: "/usr/bin/thing", arguments: ["thing"],
        startedAt: Date(), hasControllingTTY: false, cpuTimeNanos: 0, residentBytes: 0)
    let launchdSim = ProcessSample(
        pid: 200, ppid: 1, uid: 501,
        executablePath: "/Library/Developer/CoreSimulator/…/sbin/launchd_sim",
        arguments: ["launchd_sim"], startedAt: Date(), hasControllingTTY: false,
        cpuTimeNanos: 0, residentBytes: 0)

    #expect(LiveSnapshotSource.hasBootedSimulator(in: [ordinary]) == false)
    #expect(LiveSnapshotSource.hasBootedSimulator(in: [ordinary, launchdSim]) == true)
    #expect(LiveSnapshotSource.hasBootedSimulator(in: []) == false)
}

import Darwin
import Foundation
import DockerClient
import ProcessKit
import SimulatorSource

/// Assembles one `Snapshot` from all three sources. Every source failure
/// degrades to an empty list: a missing Docker daemon must never stop the app
/// from reporting processes.
public struct LiveSnapshotSource: SnapshotSource {
    private let processes: LiveProcessSource
    private let docker: DockerClient?
    private let simulators: any SimulatorControl
    private let launchd: any LaunchdJobSource

    public init(processes: LiveProcessSource = LiveProcessSource(),
                docker: DockerClient? = DockerClient.discover(),
                simulators: any SimulatorControl = SimctlSource(),
                launchd: any LaunchdJobSource = LaunchctlJobs()) {
        self.processes = processes
        self.docker = docker
        self.simulators = simulators
        self.launchd = launchd
    }

    public func sample() async -> Snapshot {
        let samples = processes.processes()
        let containers = await containerSamples()
        let devices = await simulatorSamples(processes: samples)

        return Snapshot(
            takenAt: Date(),
            processes: samples,
            containers: containers,
            simulators: devices,
            currentUID: getuid(),
            ownPID: ProcessInfo.processInfo.processIdentifier,
            managedPIDs: launchd.managedPIDs(),
            // Uptime excludes sleep, which is what makes it the right divisor
            // for a rate. This machine had been up eleven hours and awake for
            // under seven of them when that mattered.
            awakeUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func containerSamples() async -> [ContainerSample] {
        guard let docker, let running = try? await docker.containers() else { return [] }
        return running.map {
            ContainerSample(id: $0.id, name: $0.displayName, image: $0.image, startedAt: $0.runningSince)
        }
    }

    private func simulatorSamples(processes samples: [ProcessSample]) async -> [SimulatorSample] {
        guard Self.hasBootedSimulator(in: samples) else { return [] }
        guard let devices = try? await simulators.booted() else { return [] }
        return devices.map {
            SimulatorSample(id: $0.udid, name: $0.name, runtime: $0.runtime,
                            bootedAt: Self.bootTime(forSimulator: $0.udid, in: samples))
        }
    }

    /// Spawning simctl costs about eighty milliseconds, every few seconds,
    /// forever. A booted device always runs a launchd_sim, so when there is
    /// none there is nothing to ask about — which is the common case.
    static func hasBootedSimulator(in processes: [ProcessSample]) -> Bool {
        processes.contains { $0.name == "launchd_sim" }
    }

    /// simctl does not report boot time, but every booted device runs a
    /// launchd_sim whose arguments carry the device's UDID.
    static func bootTime(forSimulator udid: String, in processes: [ProcessSample]) -> Date? {
        processes.first { process in
            process.name == "launchd_sim" && process.arguments.contains { $0.contains(udid) }
        }?.startedAt
    }
}

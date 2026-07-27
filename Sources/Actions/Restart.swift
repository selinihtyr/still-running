import Foundation
import Detectors
import DockerClient
import SimulatorSource

public protocol ContainerStarting: Sendable {
    func start(id: String) async throws
}

public protocol SimulatorBooting: Sendable {
    func boot(udid: String) async throws
}

public struct ContainerStarter: ContainerStarting {
    private let client: DockerClient?
    public init(client: DockerClient? = DockerClient.discover()) { self.client = client }

    public func start(id: String) async throws {
        guard let client else { throw StopError.noDockerDaemon }
        try await client.start(id: id)
    }
}

public struct SimulatorBooter: SimulatorBooting {
    private let control: any SimulatorControl
    public init(control: any SimulatorControl = SimctlSource()) { self.control = control }

    public func boot(udid: String) async throws {
        try await control.boot(udid: udid)
    }
}

/// Puts back what a stop took away, where that is honestly possible.
///
/// A container and a simulator can be started again exactly as they were, so
/// stopping them is undoable. A process cannot: re-running an argument vector
/// is not the same program in the same state, and pretending otherwise would
/// be a worse promise than offering nothing. Processes are protected by asking
/// before the signal instead.
public struct RestartCoordinator: Sendable {
    private let containers: any ContainerStarting
    private let simulators: any SimulatorBooting

    public init(containers: any ContainerStarting = ContainerStarter(),
                simulators: any SimulatorBooting = SimulatorBooter()) {
        self.containers = containers
        self.simulators = simulators
    }

    public static func canRestart(_ finding: Finding) -> Bool {
        switch finding.target {
        case .container, .simulator: true
        case .processes: false
        }
    }

    public func restart(_ finding: Finding) async -> Bool {
        do {
            switch finding.target {
            case .container(let id): try await containers.start(id: id)
            case .simulator(let udid): try await simulators.boot(udid: udid)
            case .processes: return false
            }
            return true
        } catch {
            return false
        }
    }
}

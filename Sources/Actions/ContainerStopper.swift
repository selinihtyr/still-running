import Foundation
import DockerClient

public struct ContainerStopper: ContainerStopping {
    private let client: DockerClient?

    public init(client: DockerClient? = DockerClient.discover()) { self.client = client }

    public func stop(id: String) async throws {
        guard let client else { throw StopError.noDockerDaemon }
        try await client.stop(id: id)
    }
}

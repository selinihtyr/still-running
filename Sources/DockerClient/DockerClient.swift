import Foundation

public struct DockerContainer: Sendable, Equatable, Codable {
    public let id: String
    public let names: [String]
    public let image: String
    public let created: Date
    public let state: String

    public var displayName: String {
        let raw = names.first ?? id
        return raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id", names = "Names", image = "Image", created = "Created", state = "State"
    }
}

public struct DockerClient: Sendable {
    private let http: UnixSocketHTTP
    private static let apiVersion = "v1.43"

    public init(socketPath: String) { self.http = UnixSocketHTTP(socketPath: socketPath) }

    public static func socketCandidates(home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.orbstack/run/docker.sock", "\(home)/.docker/run/docker.sock", "/var/run/docker.sock"]
    }

    /// A client for the first socket that exists, or nil when no daemon is installed.
    public static func discover() -> DockerClient? {
        socketCandidates()
            .first { FileManager.default.fileExists(atPath: $0) }
            .map(DockerClient.init)
    }

    public func containers() async throws -> [DockerContainer] {
        let response = try await http.send(method: "GET", path: "/\(Self.apiVersion)/containers/json")
        guard response.status == 200 else {
            throw HTTPError.status(response.status, String(decoding: response.body, as: UTF8.self))
        }
        return try Self.decodeContainers(response.body)
    }

    /// Graceful stop. Docker sends SIGTERM, then SIGKILL after `timeout` seconds.
    public func stop(id: String, timeout: Int = 10) async throws {
        let response = try await http.send(
            method: "POST",
            path: "/\(Self.apiVersion)/containers/\(id)/stop?t=\(timeout)",
            timeout: TimeInterval(timeout) + 10)
        // 204 stopped, 304 already stopped. Both are success here.
        guard response.status == 204 || response.status == 304 else {
            throw HTTPError.status(response.status, String(decoding: response.body, as: UTF8.self))
        }
    }

    static func decodeContainers(_ data: Data) throws -> [DockerContainer] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([DockerContainer].self, from: data)
    }
}

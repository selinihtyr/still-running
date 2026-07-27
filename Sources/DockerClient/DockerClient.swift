import Foundation

public struct DockerContainer: Sendable, Equatable, Codable {
    public let id: String
    public let names: [String]
    public let image: String
    /// When the container was created, which may predate its current run.
    public let created: Date
    public let state: String
    /// When the current run began. Falls back to `created` when the daemon
    /// cannot be inspected.
    public private(set) var started: Date?

    public var runningSince: Date { started ?? created }

    public var displayName: String {
        let raw = names.first ?? id
        return raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
    }

    func startedAt(_ date: Date) -> DockerContainer {
        var copy = self
        copy.started = date
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id", names = "Names", image = "Image", created = "Created", state = "State"
    }
}

/// Start times keyed by container id. A running container's start time does
/// not change, so inspecting it once per container is enough — otherwise every
/// sample costs one extra round trip per container, forever.
private final class StartTimeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Date] = [:]

    func value(for id: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return entries[id]
    }

    func store(_ date: Date, for id: String) {
        lock.lock(); entries[id] = date; lock.unlock()
    }

    func keepOnly(_ ids: Set<String>) {
        lock.lock(); entries = entries.filter { ids.contains($0.key) }; lock.unlock()
    }
}

public struct DockerClient: Sendable {
    private let http: UnixSocketHTTP
    private let startTimes = StartTimeCache()
    private static let apiVersion = "v1.43"

    public init(socketPath: String) { self.http = UnixSocketHTTP(socketPath: socketPath) }

    /// Every engine that speaks the Docker API, in the order they are most
    /// likely to be the one in use. Podman, Colima and Rancher all serve the
    /// same protocol, so supporting them is a matter of knowing where they put
    /// their socket.
    public static func socketCandidates(home: String = NSHomeDirectory()) -> [String] {
        [
            "\(home)/.orbstack/run/docker.sock",                              // OrbStack
            "\(home)/.docker/run/docker.sock",                                // Docker Desktop
            "\(home)/.colima/default/docker.sock",                            // Colima
            "\(home)/.rd/docker.sock",                                        // Rancher Desktop
            "\(home)/.local/share/containers/podman/machine/podman.sock",     // Podman
            "/var/run/docker.sock",
        ]
    }

    /// A client for the first socket that exists, or nil when no daemon is installed.
    public static func discover() -> DockerClient? {
        socketCandidates()
            .first { FileManager.default.fileExists(atPath: $0) }
            .map(DockerClient.init)
    }

    /// Running containers, each with the time it was last *started*. The list
    /// endpoint only reports `Created`, which for a restarted container can be
    /// weeks older than its current run, so start times come from inspect.
    public func containers() async throws -> [DockerContainer] {
        let response = try await http.send(method: "GET", path: "/\(Self.apiVersion)/containers/json")
        guard response.status == 200 else {
            throw HTTPError.status(response.status, String(decoding: response.body, as: UTF8.self))
        }
        let listed = try Self.decodeContainers(response.body)

        startTimes.keepOnly(Set(listed.map(\.id)))

        var result: [DockerContainer] = []
        result.reserveCapacity(listed.count)
        for container in listed {
            if let known = startTimes.value(for: container.id) {
                result.append(container.startedAt(known))
                continue
            }
            let started = (try? await startedAt(id: container.id)) ?? container.created
            startTimes.store(started, for: container.id)
            result.append(container.startedAt(started))
        }
        return result
    }

    private func startedAt(id: String) async throws -> Date {
        let response = try await http.send(method: "GET", path: "/\(Self.apiVersion)/containers/\(id)/json")
        guard response.status == 200 else {
            throw HTTPError.status(response.status, String(decoding: response.body, as: UTF8.self))
        }
        return try Self.decodeStartedAt(response.body)
    }

    static func decodeStartedAt(_ data: Data) throws -> Date {
        struct Payload: Decodable {
            struct State: Decodable { let startedAt: String
                enum CodingKeys: String, CodingKey { case startedAt = "StartedAt" } }
            let state: State
            enum CodingKeys: String, CodingKey { case state = "State" }
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let date = parseDockerTimestamp(payload.state.startedAt) else {
            throw HTTPError.malformedResponse
        }
        return date
    }

    /// Docker stamps nanoseconds ("2026-07-26T20:55:13.045630605Z"), which is
    /// more precision than ISO8601DateFormatter accepts, so the fraction is
    /// dropped before parsing.
    static func parseDockerTimestamp(_ raw: String) -> Date? {
        let whole = raw.split(separator: ".").first.map(String.init) ?? raw
        let normalised = whole.hasSuffix("Z") ? whole : whole + "Z"
        return ISO8601DateFormatter().date(from: normalised)
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

    /// Starts a stopped container again. This is what makes stopping a
    /// container genuinely undoable rather than merely reversible in principle.
    public func start(id: String) async throws {
        let response = try await http.send(method: "POST", path: "/\(Self.apiVersion)/containers/\(id)/start")
        // 204 started, 304 already running.
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

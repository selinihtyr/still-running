import Foundation

/// A released version, compared the way versions mean to be compared. Text
/// comparison would put 0.10 behind 0.9 and quietly stop offering updates.
public struct ReleaseVersion: Sendable, Comparable, CustomStringConvertible {
    private let parts: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !fields.isEmpty else { return nil }
        var parsed: [Int] = []
        for field in fields {
            guard let number = Int(field), number >= 0 else { return nil }
            parsed.append(number)
        }
        self.parts = parsed
    }

    private func part(_ index: Int) -> Int { index < parts.count ? parts[index] : 0 }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let (a, b) = (lhs.part(index), rhs.part(index))
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count)
        where lhs.part(index) != rhs.part(index) { return false }
        return true
    }

    /// Three components, so 0.4 and 0.4.0 read the same in the panel.
    public var description: String {
        (0..<max(3, parts.count)).map { String(part($0)) }.joined(separator: ".")
    }
}

public struct AvailableUpdate: Sendable, Equatable {
    public let version: ReleaseVersion
    public let pageURL: URL
}

public enum UpdateStatus: Sendable, Equatable {
    case upToDate
    case available(AvailableUpdate)
    /// No answer worth showing: offline, rate limited, or a tag that is not a
    /// version. Saying nothing is better than claiming to be up to date.
    case unknown
}

/// Asks GitHub, once a day, for the latest release tag. It sends no identifiers
/// and reads nothing but the tag and its page; a request to a public API is the
/// only thing that leaves the machine.
public struct UpdateChecker: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public static let releasesAPI = URL(string:
        "https://api.github.com/repos/selinihtyr/still-running/releases/latest")!

    private let currentVersion: String
    private let fetch: Fetch

    public init(currentVersion: String = Self.bundledVersion, fetch: @escaping Fetch = Self.get) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    public static var bundledVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private struct Payload: Decodable {
        let tag_name: String
        let html_url: String
    }

    public func check() async -> UpdateStatus {
        guard let running = ReleaseVersion(currentVersion) else { return .unknown }
        guard let data = try? await fetch(Self.releasesAPI),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let latest = ReleaseVersion(payload.tag_name),
              let page = URL(string: payload.html_url)
        else { return .unknown }

        guard latest > running else { return .upToDate }
        return .available(AvailableUpdate(version: latest, pageURL: page))
    }

    /// A clock that went backwards must not park the next check in the future.
    public static func isDue(lastChecked: Date?, now: Date, every interval: TimeInterval) -> Bool {
        guard let lastChecked else { return true }
        let elapsed = now.timeIntervalSince(lastChecked)
        return elapsed >= interval || elapsed < 0
    }

    public static let get: Fetch = { url in
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Still Running", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

import Foundation

public enum FindingKind: String, Sendable, Codable, CaseIterable {
    case isolatedBrowser, container, simulator, devServer, orphan

    public var label: String {
        switch self {
        case .isolatedBrowser: "Automation browser"
        case .container: "Container"
        case .simulator: "Simulator"
        case .devServer: "Dev server"
        case .orphan: "Orphaned process"
        }
    }
}

public enum StopTarget: Sendable, Equatable, Hashable {
    /// Root process first. Stopping the root is expected to tear down the tree.
    case processes([Int32])
    case container(String)
    case simulator(String)
}

public enum Severity: Int, Sendable, Comparable {
    case informational = 0, notable = 1, urgent = 2

    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

public struct Finding: Sendable, Identifiable, Equatable {
    /// Stable across restarts and pid changes. Exclusions match on this.
    public let identity: String
    public let kind: FindingKind
    public let title: String
    public let detail: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let age: TimeInterval
    public let target: StopTarget
    public let severity: Severity

    public var id: String { identity }

    public init(identity: String, kind: FindingKind, title: String, detail: String,
                cpuPercent: Double, memoryBytes: UInt64, age: TimeInterval,
                target: StopTarget, severity: Severity) {
        self.identity = identity
        self.kind = kind
        self.title = title
        self.detail = detail
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.age = age
        self.target = target
        self.severity = severity
    }
}

public enum Formatting {
    /// "45m", "18h 43m", "1d 46m", "2d 5h".
    ///
    /// At most two units, and a zero unit is never one of them: a day-old
    /// container reads "1d 46m" rather than "1d 0h", which looked frozen when
    /// a whole stack of them showed the same thing.
    public static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 {
            if hours > 0 { return "\(days)d \(hours)h" }
            if minutes > 0 { return "\(days)d \(minutes)m" }
            return "\(days)d"
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func memory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        return megabytes >= 1024
            ? String(format: "%.1f GB", megabytes / 1024)
            : String(format: "%.0f MB", megabytes)
    }
}

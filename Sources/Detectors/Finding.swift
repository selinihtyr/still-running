import Foundation

public enum FindingKind: String, Sendable, Codable, CaseIterable {
    case isolatedBrowser, container, simulator, devServer, orphan, tunnel, keepingAwake

    public var label: String {
        switch self {
        case .keepingAwake: "Keeping this Mac awake"
        case .isolatedBrowser: "Automation browser"
        case .container: "Container"
        case .simulator: "Simulator"
        case .devServer: "Dev server"
        case .orphan: "Orphaned process"
        case .tunnel: "Tunnel"
        }
    }

    /// What this is, for someone who does not already know. A profile path or
    /// a container name is an identifier, not an explanation.
    public var plainDescription: String {
        switch self {
        case .keepingAwake:
            "A process holding this Mac awake. macOS will not idle-sleep while a promise like this is out, which is how a laptop spends a night awake in a closed bag."
        case .isolatedBrowser:
            "A browser running on its own throwaway profile — started by a script or a tool, not by you. None of your tabs are in it."
        case .container:
            "A container that is still running from something you were working on earlier."
        case .simulator:
            "A booted simulator. It holds memory and runs a whole device's worth of background processes."
        case .devServer:
            "A development server you started and left running, along with everything it started in turn."
        case .orphan:
            "Its terminal is gone but it kept running, so launchd adopted it. Nothing will ever clean it up."
        case .tunnel:
            "A tunnel publishing something on this machine to the internet, still open long after whoever needed it stopped looking."
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
    /// One plain sentence saying what this thing is, for anyone who does not
    /// recognise a profile path or a container name on sight.
    public let explanation: String
    /// Somewhere on disk this belongs to, if there is one, so the row can take
    /// you to it rather than only naming it.
    public let revealPath: String?
    /// Everything worth pasting into an issue or a terminal.
    public let details: String
    /// The command that started this, as it was typed or generated. The most
    /// direct answer there is to "what is this thing".
    public let command: String?

    public var id: String { identity }

    public init(identity: String, kind: FindingKind, title: String, detail: String,
                cpuPercent: Double, memoryBytes: UInt64, age: TimeInterval,
                target: StopTarget, severity: Severity,
                explanation: String = "", revealPath: String? = nil, details: String = "",
                command: String? = nil) {
        self.explanation = explanation.isEmpty ? kind.plainDescription : explanation
        self.revealPath = revealPath
        self.details = details
        self.command = command
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

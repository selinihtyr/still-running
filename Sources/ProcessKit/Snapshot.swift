import Foundation

public struct ProcessSample: Codable, Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let uid: UInt32
    public let executablePath: String
    public let arguments: [String]
    public let startedAt: Date
    public let hasControllingTTY: Bool
    /// Cumulative user + system CPU time. Rates must be derived from deltas.
    public let cpuTimeNanos: UInt64
    public let residentBytes: UInt64

    public var id: Int32 { pid }

    /// Last path component of the executable, e.g. "Google Chrome Helper".
    public var name: String { (executablePath as NSString).lastPathComponent }

    public init(pid: Int32, ppid: Int32, uid: UInt32, executablePath: String,
                arguments: [String], startedAt: Date, hasControllingTTY: Bool,
                cpuTimeNanos: UInt64, residentBytes: UInt64) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.executablePath = executablePath
        self.arguments = arguments
        self.startedAt = startedAt
        self.hasControllingTTY = hasControllingTTY
        self.cpuTimeNanos = cpuTimeNanos
        self.residentBytes = residentBytes
    }
}

public struct ContainerSample: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let image: String
    public let startedAt: Date

    public init(id: String, name: String, image: String, startedAt: Date) {
        self.id = id
        self.name = name
        self.image = image
        self.startedAt = startedAt
    }
}

public struct SimulatorSample: Codable, Sendable, Identifiable, Equatable {
    public let id: String        // UDID
    public let name: String
    public let runtime: String
    /// Derived from the device's launchd_sim process, nil when it cannot be resolved.
    public let bootedAt: Date?

    public init(id: String, name: String, runtime: String, bootedAt: Date?) {
        self.id = id
        self.name = name
        self.runtime = runtime
        self.bootedAt = bootedAt
    }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public let takenAt: Date
    public let processes: [ProcessSample]
    public let containers: [ContainerSample]
    public let simulators: [SimulatorSample]
    public let currentUID: UInt32
    public let ownPID: Int32
    /// Pids launchd manages through a plist. They look like orphans but are not.
    public let managedPIDs: Set<Int32>

    public init(takenAt: Date, processes: [ProcessSample], containers: [ContainerSample],
                simulators: [SimulatorSample], currentUID: UInt32, ownPID: Int32,
                managedPIDs: Set<Int32> = []) {
        self.takenAt = takenAt
        self.processes = processes
        self.containers = containers
        self.simulators = simulators
        self.currentUID = currentUID
        self.ownPID = ownPID
        self.managedPIDs = managedPIDs
    }

    public func process(pid: Int32) -> ProcessSample? { processes.first { $0.pid == pid } }
}

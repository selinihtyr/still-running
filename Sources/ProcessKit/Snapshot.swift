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
    /// Seconds the machine has been awake, which is `takenAt` minus every nap
    /// it has taken. Rates are per second of running time, not per second on
    /// the wall: nothing burns CPU while the lid is shut. Zero means unknown,
    /// and rates fall back to the wall clock.
    public let awakeUptime: TimeInterval

    public init(takenAt: Date, processes: [ProcessSample], containers: [ContainerSample],
                simulators: [SimulatorSample], currentUID: UInt32, ownPID: Int32,
                managedPIDs: Set<Int32> = [], awakeUptime: TimeInterval = 0) {
        self.takenAt = takenAt
        self.processes = processes
        self.containers = containers
        self.simulators = simulators
        self.currentUID = currentUID
        self.ownPID = ownPID
        self.managedPIDs = managedPIDs
        self.awakeUptime = awakeUptime
    }

    /// Adding a stored property to a synthesised decoder makes it throw on
    /// every payload written before the property existed, so this one is
    /// optional on the way in. Nothing persists a snapshot today; the cost of
    /// keeping that true is four lines.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takenAt = try container.decode(Date.self, forKey: .takenAt)
        processes = try container.decode([ProcessSample].self, forKey: .processes)
        containers = try container.decode([ContainerSample].self, forKey: .containers)
        simulators = try container.decode([SimulatorSample].self, forKey: .simulators)
        currentUID = try container.decode(UInt32.self, forKey: .currentUID)
        ownPID = try container.decode(Int32.self, forKey: .ownPID)
        managedPIDs = try container.decodeIfPresent(Set<Int32>.self, forKey: .managedPIDs) ?? []
        awakeUptime = try container.decodeIfPresent(TimeInterval.self, forKey: .awakeUptime) ?? 0
    }

    public func process(pid: Int32) -> ProcessSample? { processes.first { $0.pid == pid } }
}

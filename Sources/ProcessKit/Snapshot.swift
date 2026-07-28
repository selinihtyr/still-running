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
    /// Every live promise that the machine will not fall asleep, from any
    /// process on it. Reading them is what lets one row answer "why was this
    /// thing awake all night".
    public let assertions: [PowerAssertionSample]
    /// Seconds the machine has been awake, which is `takenAt` minus every nap
    /// it has taken. Rates are per second of running time, not per second on
    /// the wall: nothing burns CPU while the lid is shut. Zero means unknown,
    /// and rates fall back to the wall clock.
    public let awakeUptime: TimeInterval
    /// Where each pid sits in `processes`. Built once per snapshot because
    /// every rate in the app is two lookups, and a rate is asked for per
    /// process per interval: on a machine with five hundred processes, scanning
    /// the array each time is millions of comparisons per refresh, on the main
    /// thread, while the panel is open. Derived, so it is not part of equality
    /// and never encoded.
    private let indexByPID: [Int32: Int]

    public init(takenAt: Date, processes: [ProcessSample], containers: [ContainerSample],
                simulators: [SimulatorSample], currentUID: UInt32, ownPID: Int32,
                managedPIDs: Set<Int32> = [], awakeUptime: TimeInterval = 0,
                assertions: [PowerAssertionSample] = []) {
        self.takenAt = takenAt
        self.processes = processes
        self.containers = containers
        self.simulators = simulators
        self.currentUID = currentUID
        self.ownPID = ownPID
        self.managedPIDs = managedPIDs
        self.awakeUptime = awakeUptime
        self.assertions = assertions
        self.indexByPID = Self.index(processes)
    }

    /// A pid appears once in a process table, but a snapshot is only ever as
    /// honest as what it was handed: first one wins, so a duplicate cannot
    /// silently displace the entry the rest of the app already matched.
    private static func index(_ processes: [ProcessSample]) -> [Int32: Int] {
        var index: [Int32: Int] = [:]
        index.reserveCapacity(processes.count)
        for (position, process) in processes.enumerated() where index[process.pid] == nil {
            index[process.pid] = position
        }
        return index
    }

    /// Derived state is not identity: two snapshots holding the same processes
    /// are the same snapshot, whatever their lookup tables contain.
    public static func == (a: Snapshot, b: Snapshot) -> Bool {
        a.takenAt == b.takenAt && a.processes == b.processes && a.containers == b.containers
            && a.simulators == b.simulators && a.currentUID == b.currentUID && a.ownPID == b.ownPID
            && a.managedPIDs == b.managedPIDs && a.assertions == b.assertions
            && a.awakeUptime == b.awakeUptime
    }

    /// The index is rebuilt on the way in rather than carried, so it can never
    /// disagree with the list it points into.
    private enum CodingKeys: String, CodingKey {
        case takenAt, processes, containers, simulators, currentUID, ownPID
        case managedPIDs, awakeUptime, assertions
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
        assertions = try container.decodeIfPresent([PowerAssertionSample].self, forKey: .assertions) ?? []
        indexByPID = Self.index(processes)
    }

    public func process(pid: Int32) -> ProcessSample? { indexByPID[pid].map { processes[$0] } }
}

import Foundation

public struct Settings: Codable, Sendable, Equatable {
    /// Nothing younger than this is surfaced on age alone.
    public var minimumAge: TimeInterval = 2 * 3600
    public var sustainedCPUPercent: Double = 25
    public var sustainedCPUWindow: TimeInterval = 180
    public var idleCPUPercent: Double = 2
    public var idleWindow: TimeInterval = 1800
    public var idleMemoryBytes: UInt64 = 500 * 1_048_576
    /// A dev server that did any real work this recently is one you are using,
    /// not one you forgot. Age alone would list the server you are typing
    /// against right now.
    public var activeCPUPercent: Double = 5
    public var activityWindow: TimeInterval = 600
    /// Opt-in. Nil means no notifications.
    public var notifyAfter: TimeInterval?

    public init() {}

    /// True when something this old, this busy, and this large is worth surfacing.
    public func crossesThreshold(age: TimeInterval, sustainedCPU: Double?,
                                 idleFor: TimeInterval?, memoryBytes: UInt64,
                                 isOrphan: Bool = false) -> Bool {
        if isOrphan { return true }
        if age >= minimumAge { return true }
        if let cpu = sustainedCPU, cpu >= sustainedCPUPercent { return true }
        if let idle = idleFor, idle >= idleWindow, memoryBytes >= idleMemoryBytes { return true }
        return false
    }
}

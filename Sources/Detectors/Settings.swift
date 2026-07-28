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
    /// How long something must have been holding this Mac awake before it is
    /// worth a row. A video call holds one for as long as the call, and saying
    /// so while you are on it is noise; half an hour is long enough that the
    /// answer is usually "I did not know that was still running".
    public var awakeMinimumHold: TimeInterval = 1800
    /// Opt-in. Nil means no notifications.
    public var notifyAfter: TimeInterval?
    /// One request a day to GitHub's public releases API. Off means the app
    /// never touches the network at all.
    public var checksForUpdates: Bool = true

    public init() {}

    /// Decoded field by field, each falling back to its default. The synthesised
    /// decoder throws on a key it has never seen, which would mean every
    /// settings file written by an older version failed to load and silently
    /// reset — so adding a setting would quietly undo the user's choices.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let blank = Settings()
        minimumAge = value(.minimumAge, blank.minimumAge)
        sustainedCPUPercent = value(.sustainedCPUPercent, blank.sustainedCPUPercent)
        sustainedCPUWindow = value(.sustainedCPUWindow, blank.sustainedCPUWindow)
        idleCPUPercent = value(.idleCPUPercent, blank.idleCPUPercent)
        idleWindow = value(.idleWindow, blank.idleWindow)
        idleMemoryBytes = value(.idleMemoryBytes, blank.idleMemoryBytes)
        activeCPUPercent = value(.activeCPUPercent, blank.activeCPUPercent)
        activityWindow = value(.activityWindow, blank.activityWindow)
        awakeMinimumHold = value(.awakeMinimumHold, blank.awakeMinimumHold)
        notifyAfter = try? container.decodeIfPresent(TimeInterval.self, forKey: .notifyAfter)
        checksForUpdates = value(.checksForUpdates, blank.checksForUpdates)
    }

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

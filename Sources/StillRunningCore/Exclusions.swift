import Foundation

/// The "Keep this" list. Matches on finding identity, which is derived from
/// stable attributes (profile path, container name, simulator UDID) rather
/// than pids, so an exclusion survives a restart of the excluded thing.
public struct Exclusions {
    private let defaults: UserDefaults
    private let key = "excludedIdentities"
    private var cache: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cache = Set(defaults.stringArray(forKey: key) ?? [])
    }

    public var identities: Set<String> { cache }

    public func contains(_ identity: String) -> Bool { cache.contains(identity) }

    public mutating func add(_ identity: String) {
        cache.insert(identity)
        defaults.set(Array(cache), forKey: key)
    }

    public mutating func remove(_ identity: String) {
        cache.remove(identity)
        defaults.set(Array(cache), forKey: key)
    }
}

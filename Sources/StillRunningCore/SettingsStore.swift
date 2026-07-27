import Foundation
import Detectors

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "settings"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var settings: Settings {
        get {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode(Settings.self, from: data)
            else { return Settings() }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }
}

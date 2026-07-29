import Foundation
import ServiceManagement

/// An app that watches for things you forgot hours ago is worthless if it dies
/// at every restart. This is the one login item Still Running registers, and
/// the Settings switch turns it off.
public enum LoginItem {
    public enum State: Sendable, Equatable {
        case enabled
        case disabled
        /// macOS is holding it off — the user switched it off in System
        /// Settings › General › Login Items, and only they can switch it back.
        case blockedByUser
        case unavailable

        public var isOn: Bool { self == .enabled }

        public var explanation: String? {
            switch self {
            case .enabled, .disabled: nil
            case .blockedByUser:
                "macOS is blocking this. Allow “Still Running” in System Settings › General › Login Items."
            case .unavailable:
                "Only available once the app is installed — run ./scripts/install.sh."
            }
        }
    }

    /// Only an installed copy may hold the login item, and "installed" means
    /// exactly one of the two Applications folders.
    ///
    /// A binary running straight out of .build has no bundle to register at
    /// all. A built one does, which is the trap: on the machine this was
    /// written on the login item pointed at the app in `build/`, because that
    /// copy ran first and registered itself, and registration happens once —
    /// so the copy in /Applications could never take it back. Every rebuild
    /// deletes that bundle, which means macOS was being told to launch a path
    /// that keeps disappearing, and the running process had its own executable
    /// pulled out from under it.
    public static func isAvailable(bundlePath: String, home: String = NSHomeDirectory()) -> Bool {
        guard bundlePath.hasSuffix(".app") else { return false }
        let parent = (bundlePath as NSString).deletingLastPathComponent
        return parent == "/Applications" || parent == (home as NSString).appendingPathComponent("Applications")
    }

    public static var isAvailable: Bool {
        isAvailable(bundlePath: Bundle.main.bundleURL.path)
    }

    public static var state: State {
        guard isAvailable else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .blockedByUser
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    @discardableResult
    public static func setEnabled(_ on: Bool) -> State {
        guard isAvailable else { return .unavailable }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return state
        }
        return state
    }
}

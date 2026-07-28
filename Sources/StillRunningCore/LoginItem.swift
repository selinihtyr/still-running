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

    /// A binary running straight out of .build has no bundle to register, so
    /// offering the switch there would be a lie.
    public static func isAvailable(bundlePath: String) -> Bool {
        bundlePath.hasSuffix(".app")
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

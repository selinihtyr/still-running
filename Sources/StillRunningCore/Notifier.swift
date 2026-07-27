import Foundation
import UserNotifications
import Detectors

public protocol NotificationPresenting: Sendable {
    func present(title: String, body: String)
}

public struct SystemNotificationPresenter: NotificationPresenting {
    public init() {}

    public func present(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The point of the reminder is that you did not notice. Silence would
        // defeat it; macOS still has the final say per app.
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Opt-in, and at most one notification per identity per launch. The failure
/// this app exists for is not noticing for eighteen hours; the fix is one
/// quiet nudge, not a stream of them.
public struct Notifier: Sendable {
    private let presenter: any NotificationPresenting
    private var notified: Set<String> = []

    public init(presenter: any NotificationPresenting = SystemNotificationPresenter()) {
        self.presenter = presenter
    }

    public mutating func consider(_ findings: [Finding], settings: Settings) {
        guard let threshold = settings.notifyAfter else { return }
        for finding in findings where finding.age >= threshold && !notified.contains(finding.identity) {
            notified.insert(finding.identity)
            presenter.present(
                title: "Still running",
                body: "\(finding.title) has been running for \(Formatting.duration(finding.age)).")
        }
    }

    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// What macOS currently allows, in words the settings window can show.
    public enum Permission: Sendable, Equatable {
        case allowed
        case notAskedYet
        case blocked
        case unavailable(String)

        public var message: String {
            switch self {
            case .allowed: "Notifications are allowed."
            case .notAskedYet: "macOS has not been asked yet. Send a test to ask."
            case .blocked: "macOS is blocking notifications for Still Running. Turn them on in System Settings › Notifications."
            case .unavailable(let why): "Notifications are unavailable: \(why)"
            }
        }
    }

    public static func permission() async -> Permission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .notAskedYet
        case .denied: return .blocked
        @unknown default: return .unavailable("unknown status")
        }
    }

    /// macOS keeps sound as its own per-app switch, separate from permission,
    /// and it is off by default for some apps.
    public static func soundIsOn() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().soundSetting == .enabled
    }

    /// Asks for permission if needed, then sends one notification so the user
    /// can see for themselves whether it arrives.
    public static func sendTest() async -> Permission {
        let center = UNUserNotificationCenter.current()
        if await permission() == .notAskedYet {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let current = await permission()
        guard current == .allowed else { return current }

        let content = UNMutableNotificationContent()
        content.title = "Still Running"
        content.body = "This is what a reminder looks like."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                                       content: content, trigger: nil))
            return .allowed
        } catch {
            return .unavailable("\(error.localizedDescription)")
        }
    }
}

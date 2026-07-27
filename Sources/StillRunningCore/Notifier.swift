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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
}

import Foundation
import UserNotifications
import Detectors

/// Everything that touches UNUserNotificationCenter goes through here.
/// `UNUserNotificationCenter.current()` aborts outright in a process without an
/// app bundle, so tests must never reach the real one.
public protocol NotificationPresenting: Sendable {
    func present(title: String, body: String)
    func requestAuthorization()
}

public struct SystemNotificationPresenter: NotificationPresenting {
    public init() {}

    /// `UNUserNotificationCenter.current()` does not fail when there is no app
    /// bundle around it — it aborts the process, which no caller can defend
    /// against. Every path here was reachable only from code that happened to
    /// be switched off in tests, until one that was not: a whole run died with
    /// signal 6. Asking first is what makes this type safe to hold anywhere.
    private var insideAnApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    public func requestAuthorization() {
        guard insideAnApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func present(title: String, body: String) {
        guard insideAnApp else { return }
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

    public mutating func consider(_ findings: [Finding], settings: Settings,
                                  thermal: Thermal = .nominal) {
        guard let threshold = settings.notifyAfter else { return }
        for finding in findings where !notified.contains(finding.identity) {
            let due = finding.age >= threshold
            let early = !due && Self.isCooking(finding, settings: settings, thermal: thermal)
            guard due || early else { continue }
            notified.insert(finding.identity)
            presenter.present(
                title: "Still running",
                body: early
                    ? Self.hotBody(finding, thermal: thermal)
                    // A wake lock's age is how long it has been held, not how long
                    // the process has been up, so "running for" would be the wrong
                    // sentence about the right number.
                    : finding.kind == .keepingAwake
                        ? "\(finding.title), for \(Formatting.duration(finding.age))."
                        : "\(finding.title) has been running for \(Formatting.duration(finding.age)).")
        }
    }

    /// Something eating this much of the machine is its own reason to speak, with
    /// or without a word from macOS about temperature.
    static let runawayCPUPercent: Double = 50

    /// `notifyAfter` answers "how long before you would want to know?", and eight
    /// hours is the right answer for something sitting idle. It is the wrong
    /// answer for something with a core pinned: by the time the timer agrees, it
    /// has been cooking the machine for most of a working day. So for that case
    /// the bar drops to the age at which the panel already calls something
    /// forgotten.
    ///
    /// What counts as cooking depends on whether macOS is corroborating. Its
    /// `thermalState` is the reading that makes fans spin, so when it says the
    /// Mac is hot the ordinary "sustained" bar is enough. It cannot be *required*
    /// though: it is conservative, it has never been seen above nominal on the
    /// machine this was written on, and a feature that waits for it may simply
    /// never fire. So without it the bar is a runaway — half the machine — which
    /// is not a temperature claim but an observation the app makes itself.
    ///
    /// Age guards both paths. It keeps this from naming the build started a
    /// minute ago: a busy process is not a forgotten one, and the whole promise
    /// of the app is that it talks about things you left behind.
    static func isCooking(_ finding: Finding, settings: Settings, thermal: Thermal) -> Bool {
        guard finding.age >= settings.minimumAge else { return false }
        let bar = thermal == .serious || thermal == .critical
            ? settings.sustainedCPUPercent
            : runawayCPUPercent
        return finding.cpuPercent >= bar
    }

    /// Leads with the heat when macOS reported some, because that is the part
    /// that is not obvious. When it did not, the CPU figure carries the sentence
    /// alone — claiming a temperature nobody measured would be putting words in
    /// the system's mouth.
    static func hotBody(_ finding: Finding, thermal: Thermal) -> String {
        let fact = "\(finding.title) has been up for \(Formatting.duration(finding.age)) "
            + "and is using \(Int(finding.cpuPercent))% CPU."
        guard thermal == .serious || thermal == .critical else { return fact }
        return "This Mac is running \(thermal.label). \(fact)"
    }

    /// Said once per version, by the caller. Deliberately not gated on
    /// `notifyAfter`: that setting is about things you left running, while this
    /// is the answer to the question the update check exists to ask. The switch
    /// that governs it is the one for checking at all.
    public func announce(release version: String, running current: String) {
        presenter.present(
            title: "Still Running \(version) is out",
            body: "You are on \(current). Open the panel to update — it builds from source in a Terminal window.")
    }

    public func requestAuthorization() {
        presenter.requestAuthorization()
    }

    /// For callers that only have the type, such as the settings window.
    public static func requestAuthorization() {
        SystemNotificationPresenter().requestAuthorization()
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

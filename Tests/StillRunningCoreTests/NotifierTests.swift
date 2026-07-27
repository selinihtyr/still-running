import Testing
import Foundation
import Synchronization
@testable import StillRunningCore
import Detectors

final class RecordingPresenter: NotificationPresenting, Sendable {
    private let storage = Mutex<[String]>([])
    private let authorizationRequests = Mutex<Int>(0)

    var messages: [String] { storage.withLock { $0 } }
    var timesAsked: Int { authorizationRequests.withLock { $0 } }

    func present(title: String, body: String) { storage.withLock { $0.append(body) } }
    func requestAuthorization() { authorizationRequests.withLock { $0 += 1 } }
}

private func finding(identity: String, age: TimeInterval) -> Finding {
    Finding(identity: identity, kind: .devServer, title: "vite", detail: "d",
            cpuPercent: 5, memoryBytes: 0, age: age, target: .processes([1000]), severity: .notable)
}

@Test func notifiesOnceForSomethingPastTheThreshold() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 9 * 3600)], settings: settings)
    notifier.consider([finding(identity: "a", age: 10 * 3600)], settings: settings)

    #expect(presenter.messages.count == 1)
    #expect(presenter.messages[0].contains("vite"))
}

@Test func staysSilentWhenNotificationsAreOff() {
    let presenter = RecordingPresenter()
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 40 * 3600)], settings: Settings())

    #expect(presenter.messages.isEmpty)
}

@Test func staysSilentBelowTheThreshold() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 3 * 3600)], settings: settings)

    #expect(presenter.messages.isEmpty)
}

@Test func notifiesAgainForADifferentIdentity() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 9 * 3600)], settings: settings)
    notifier.consider([finding(identity: "b", age: 9 * 3600)], settings: settings)

    #expect(presenter.messages.count == 2)
}

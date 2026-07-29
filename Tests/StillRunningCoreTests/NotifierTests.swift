import Testing
import Foundation
import ProcessKit
@testable import StillRunningCore
import Detectors

final class RecordingPresenter: NotificationPresenting, Sendable {
    private let storage = Locked<[String]>([])
    private let headlines = Locked<[String]>([])
    private let authorizationRequests = Locked<Int>(0)

    var messages: [String] { storage.withLock { $0 } }
    var titles: [String] { headlines.withLock { $0 } }
    var timesAsked: Int { authorizationRequests.withLock { $0 } }

    func present(title: String, body: String) {
        storage.withLock { $0.append(body) }
        headlines.withLock { $0.append(title) }
    }
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

// MARK: - Speaking up early while the machine is hot

private func burning(identity: String, age: TimeInterval, cpu: Double) -> Finding {
    Finding(identity: identity, kind: .isolatedBrowser, title: "Chrome · automation",
            detail: "d", cpuPercent: cpu, memoryBytes: 0, age: age,
            target: .processes([1000]), severity: .urgent)
}

@Test func notifiesBeforeTheThresholdWhenTheMachineIsHot() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([burning(identity: "a", age: 2.5 * 3600, cpu: 88)],
                      settings: settings, thermal: .serious)

    #expect(presenter.messages.count == 1)
    #expect(presenter.messages[0].contains("Chrome · automation"))
}

@Test func saysTheHeatIsWhyItSpokeEarly() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([burning(identity: "a", age: 2.5 * 3600, cpu: 88)],
                      settings: settings, thermal: .critical)

    #expect(presenter.messages[0].lowercased().contains("hot")
            || presenter.messages[0].lowercased().contains("throttling"))
}

@Test func staysQuietWhenHotIfTheFindingIsNotBurningCPU() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([burning(identity: "a", age: 2.5 * 3600, cpu: 1)],
                      settings: settings, thermal: .serious)

    #expect(presenter.messages.isEmpty)
}

/// Heat is not a reason to name something started a minute ago: the panel does
/// not call it forgotten yet, and neither should a notification.
@Test func staysQuietWhenHotBelowTheForgottenAge() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([burning(identity: "a", age: 600, cpu: 88)],
                      settings: settings, thermal: .serious)

    #expect(presenter.messages.isEmpty)
}

/// Off means off. A hot machine is not consent to start notifying.
@Test func staysSilentWhenHotAndNotificationsAreOff() {
    let presenter = RecordingPresenter()
    var notifier = Notifier(presenter: presenter)

    notifier.consider([burning(identity: "a", age: 2.5 * 3600, cpu: 88)],
                      settings: Settings(), thermal: .critical)

    #expect(presenter.messages.isEmpty)
}

@Test func aWarmMachineIsNotHotEnoughToSpeakEarly() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([burning(identity: "a", age: 2.5 * 3600, cpu: 88)],
                      settings: settings, thermal: .fair)

    #expect(presenter.messages.isEmpty)
}

/// The early nudge is still one nudge. Every sample while the Mac is hot must
/// not be another notification for the same thing.
@Test func notifiesOnlyOnceWhileTheMachineStaysHot() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([burning(identity: "a", age: 2.5 * 3600, cpu: 88)],
                      settings: settings, thermal: .serious)
    notifier.consider([burning(identity: "a", age: 3 * 3600, cpu: 90)],
                      settings: settings, thermal: .serious)

    #expect(presenter.messages.count == 1)
}

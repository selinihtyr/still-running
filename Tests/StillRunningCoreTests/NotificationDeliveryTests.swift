import Testing
import Foundation
import ProcessKit
@testable import StillRunningCore

private final class NoProcesses: SnapshotSource {
    func sample() async -> Snapshot {
        Snapshot(takenAt: Date(), processes: [], containers: [], simulators: [],
                 currentUID: 501, ownPID: 1)
    }
}

/// A version is announced once, ever. That promise is only worth keeping if the
/// one chance is spent on something that actually arrives — otherwise the app
/// records having said what nobody heard, and the release is never mentioned
/// again. Found on a real machine: 0.5.1 and 0.5.2 were both marked announced
/// to someone macOS had never been asked for permission about.
@MainActor
@Test func doesNotSpendAVersionsOneChanceOnANotificationMacOSWillNotShow() async {
    let defaults = UserDefaults(suiteName: "undeliverable-\(UUID().uuidString)")!
    defaults.set("9.9.9", forKey: "lastKnownRelease")
    defaults.set("https://example.com/r", forKey: "lastKnownReleasePage")
    defaults.set(Date(), forKey: "lastUpdateCheck")
    let presenter = RecordingPresenter()
    presenter.macOSWillShowNotifications(false)

    let store = Store(source: NoProcesses(), defaults: defaults,
                      notifier: Notifier(presenter: presenter))
    await store.checkForUpdate()

    #expect(presenter.titles.isEmpty)
    #expect(defaults.string(forKey: "announcedRelease") == nil)
}

/// The other half of the same promise: once macOS is willing, the version that
/// could not be delivered before is still owed.
@MainActor
@Test func stillOwesYouTheVersionOncePermissionArrives() async {
    let defaults = UserDefaults(suiteName: "owed-\(UUID().uuidString)")!
    defaults.set("9.9.9", forKey: "lastKnownRelease")
    defaults.set("https://example.com/r", forKey: "lastKnownReleasePage")
    defaults.set(Date(), forKey: "lastUpdateCheck")
    let presenter = RecordingPresenter()
    presenter.macOSWillShowNotifications(false)

    let store = Store(source: NoProcesses(), defaults: defaults,
                      notifier: Notifier(presenter: presenter))
    await store.checkForUpdate()
    presenter.macOSWillShowNotifications(true)
    await store.checkForUpdate()

    #expect(presenter.titles.count == 1)
    #expect(presenter.titles[0].contains("9.9.9"))
}

/// macOS is asked for permission on the first launch and never again, so a
/// prompt that was dismissed that once leaves notifications switched on in
/// Settings and impossible in fact — with nothing anywhere saying so.
@MainActor
@Test func asksMacOSAgainWhenNotificationsAreOnButNotPermitted() async {
    let defaults = UserDefaults(suiteName: "reask-\(UUID().uuidString)")!
    defaults.set(true, forKey: "hasLaunchedBefore")
    let presenter = RecordingPresenter()
    presenter.macOSWillShowNotifications(false)

    let store = Store(source: NoProcesses(), defaults: defaults,
                      notifier: Notifier(presenter: presenter))
    store.settings.notifyAfter = 8 * 3600
    await store.ensureNotificationsCanArrive()

    #expect(presenter.timesAsked == 1)
}

@MainActor
@Test func doesNotPesterWhenMacOSIsAlreadyWilling() async {
    let defaults = UserDefaults(suiteName: "willing-\(UUID().uuidString)")!
    defaults.set(true, forKey: "hasLaunchedBefore")
    let presenter = RecordingPresenter()

    let store = Store(source: NoProcesses(), defaults: defaults,
                      notifier: Notifier(presenter: presenter))
    store.settings.notifyAfter = 8 * 3600
    await store.ensureNotificationsCanArrive()

    #expect(presenter.timesAsked == 0)
    #expect(!store.notificationsSilenced)
}

/// Nothing to ask about when the user has said they do not want notifying.
@MainActor
@Test func doesNotAskAboutNotificationsNobodyWanted() async {
    let defaults = UserDefaults(suiteName: "unwanted-\(UUID().uuidString)")!
    defaults.set(true, forKey: "hasLaunchedBefore")
    let presenter = RecordingPresenter()
    presenter.macOSWillShowNotifications(false)

    let store = Store(source: NoProcesses(), defaults: defaults,
                      notifier: Notifier(presenter: presenter))
    store.settings.notifyAfter = nil
    await store.ensureNotificationsCanArrive()

    #expect(presenter.timesAsked == 0)
    #expect(!store.notificationsSilenced)
}

/// The state worth showing: switched on, and going nowhere.
@MainActor
@Test func saysSoWhenNotificationsAreOnAndGoingNowhere() async {
    let defaults = UserDefaults(suiteName: "silenced-\(UUID().uuidString)")!
    defaults.set(true, forKey: "hasLaunchedBefore")
    let presenter = RecordingPresenter()
    presenter.macOSWillShowNotifications(false)

    let store = Store(source: NoProcesses(), defaults: defaults,
                      notifier: Notifier(presenter: presenter))
    store.settings.notifyAfter = 8 * 3600
    await store.ensureNotificationsCanArrive()

    #expect(store.notificationsSilenced)
}

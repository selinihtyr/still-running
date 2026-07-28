import Testing
import Foundation
import ProcessKit
@testable import StillRunningCore

private func release(tag: String, url: String = "https://example.com/r") -> Data {
    Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)","draft":false}"#.utf8)
}

private func checker(current: String, returning data: Data) -> UpdateChecker {
    UpdateChecker(currentVersion: current, fetch: { _ in data })
}

// MARK: - Reading a version

@Test func readsAVersionWithOrWithoutItsLeadingV() {
    #expect(ReleaseVersion("v0.4.0") == ReleaseVersion("0.4.0"))
    #expect(ReleaseVersion("0.4.0")?.description == "0.4.0")
}

@Test func refusesSomethingThatIsNotAVersion() {
    #expect(ReleaseVersion("nightly") == nil)
    #expect(ReleaseVersion("") == nil)
    #expect(ReleaseVersion("v") == nil)
}

@Test func comparesVersionsAsNumbersNotAsText() {
    // The string comparison every version checker gets wrong: "0.10" < "0.9".
    #expect(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.0")!)
    #expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
    #expect(ReleaseVersion("0.4.1")! > ReleaseVersion("0.4.0")!)
}

@Test func treatsMissingComponentsAsZero() {
    #expect(ReleaseVersion("1.0")! == ReleaseVersion("1.0.0")!)
    #expect(ReleaseVersion("1.0.1")! > ReleaseVersion("1.0")!)
}

// MARK: - Deciding whether there is an update

@Test func offersAnUpdateWhenTheReleaseIsNewer() async {
    let status = await checker(current: "0.3.0", returning: release(tag: "v0.4.0")).check()

    guard case .available(let found) = status else {
        Issue.record("expected an update, got \(status)")
        return
    }
    #expect(found.version == ReleaseVersion("0.4.0")!)
    #expect(found.pageURL.absoluteString == "https://example.com/r")
}

@Test func staysQuietWhenTheReleaseIsTheVersionYouAreRunning() async {
    let status = await checker(current: "0.4.0", returning: release(tag: "v0.4.0")).check()
    #expect(status == .upToDate)
}

@Test func staysQuietWhenYouAreAheadOfTheRelease() async {
    // Someone building from main is ahead of the last tag; that is not an update.
    let status = await checker(current: "0.5.0", returning: release(tag: "v0.4.0")).check()
    #expect(status == .upToDate)
}

@Test func saysNothingRatherThanGuessingWhenTheNetworkFails() async {
    let checker = UpdateChecker(currentVersion: "0.3.0",
                                fetch: { _ in throw URLError(.notConnectedToInternet) })
    #expect(await checker.check() == .unknown)
}

@Test func saysNothingWhenTheAnswerIsNotAReleaseItUnderstands() async {
    let status = await checker(current: "0.3.0", returning: Data("<html>rate limited</html>".utf8)).check()
    #expect(status == .unknown)
}

@Test func saysNothingWhenTheTagIsNotAVersion() async {
    let status = await checker(current: "0.3.0", returning: release(tag: "nightly")).check()
    #expect(status == .unknown)
}

// MARK: - Not asking GitHub more often than it is worth

@Test func waitsADayBetweenChecks() {
    let day: TimeInterval = 86_400
    #expect(UpdateChecker.isDue(lastChecked: nil, now: Date(), every: day))
    #expect(UpdateChecker.isDue(lastChecked: Date(timeIntervalSince1970: 0),
                                now: Date(timeIntervalSince1970: day + 1), every: day))
    #expect(!UpdateChecker.isDue(lastChecked: Date(timeIntervalSince1970: 0),
                                 now: Date(timeIntervalSince1970: 60), every: day))
}

@Test func checksAgainIfTheClockWentBackwards() {
    // A machine that slept across a time change must not stop checking forever.
    #expect(UpdateChecker.isDue(lastChecked: Date(timeIntervalSince1970: 5_000),
                                now: Date(timeIntervalSince1970: 100), every: 86_400))
}

// MARK: - Installing it

@Test func findsTheCheckoutItWasBuiltFrom() {
    let root = Updater.sourceRoot(recordedPath: "/Users/x/still-running",
                                 exists: { $0 == "/Users/x/still-running/scripts/install.sh" })
    #expect(root?.path == "/Users/x/still-running")
}

@Test func refusesACheckoutThatIsNoLongerThere() {
    // Someone moved or deleted the clone. Running an installer from a path that
    // no longer holds one is worse than sending them to the release page.
    #expect(Updater.sourceRoot(recordedPath: "/Users/x/moved", exists: { _ in false }) == nil)
    #expect(Updater.sourceRoot(recordedPath: nil, exists: { _ in true }) == nil)
    #expect(Updater.sourceRoot(recordedPath: "", exists: { _ in true }) == nil)
}

@Test func theUpdateScriptPullsThenRunsTheInstallerItAlreadyDocuments() {
    let script = Updater.script(sourceRoot: URL(fileURLWithPath: "/Users/x/still running"))

    #expect(script.contains("cd \"/Users/x/still running\""))
    #expect(script.contains("git pull"))
    #expect(script.contains("./scripts/install.sh"))
    #expect(script.hasPrefix("#!/bin/bash\n"))
}

@Test func theUpdateScriptStopsIfThePullFails() {
    let script = Updater.script(sourceRoot: URL(fileURLWithPath: "/tmp/x"))
    let pull = script.split(separator: "\n").first { $0.contains("git pull") }

    #expect(pull?.contains("|| exit 1") == true)
}

// MARK: - Against the real GitHub, only when asked

@Test(.enabled(if: ProcessInfo.processInfo.environment["STILL_RUNNING_LIVE_TESTS"] == "1"))
func readsTheRealReleaseFromGitHub() async {
    // Pretending to be ancient, so the answer must be an offer to update.
    let status = await UpdateChecker(currentVersion: "0.0.1").check()

    guard case .available(let found) = status else {
        Issue.record("GitHub gave no usable release: \(status)")
        return
    }
    print("live: latest release is \(found.version) at \(found.pageURL)")
    #expect(found.pageURL.absoluteString.contains("still-running"))
}

// MARK: - Remembering the answer across a relaunch

/// The update strip does not care what is on the machine, so one empty
/// snapshot is enough for these.
private final class EmptySource: SnapshotSource {
    func sample() async -> Snapshot {
        Snapshot(takenAt: Date(), processes: [], containers: [], simulators: [],
                 currentUID: 501, ownPID: 1)
    }
}

@MainActor
@Test func remembersTheLastAnswerSoARelaunchIsNotBlank() async {
    let defaults = UserDefaults(suiteName: "remembers-\(UUID().uuidString)")!
    defaults.set("9.9.9", forKey: "lastKnownRelease")
    defaults.set("https://example.com/r", forKey: "lastKnownReleasePage")
    // Checked minutes ago, so no request goes out — only the remembered answer.
    defaults.set(Date(), forKey: "lastUpdateCheck")

    let store = Store(source: EmptySource(), defaults: defaults)
    await store.checkForUpdate()

    guard case .available(let found) = store.update else {
        Issue.record("expected the remembered release, got \(store.update)")
        return
    }
    #expect(found.version == ReleaseVersion("9.9.9")!)
}

@MainActor
@Test func stopsOfferingAReleaseOnceYouAreRunningIt() async {
    let defaults = UserDefaults(suiteName: "installed-\(UUID().uuidString)")!
    defaults.set("0.0.0", forKey: "lastKnownRelease")
    defaults.set(Date(), forKey: "lastUpdateCheck")

    let store = Store(source: EmptySource(), defaults: defaults)
    await store.checkForUpdate()

    #expect(store.update == .upToDate)
}

@MainActor
@Test func saysNothingAboutVersionsWhenTheCheckIsSwitchedOff() async {
    let defaults = UserDefaults(suiteName: "off-\(UUID().uuidString)")!
    defaults.set("9.9.9", forKey: "lastKnownRelease")

    let store = Store(source: EmptySource(), defaults: defaults)
    store.settings.checksForUpdates = false
    await store.checkForUpdate()

    #expect(store.update == .unknown)
}

@MainActor
@Test func asksOnceOnTheDayItIsInstalledRatherThanWaitingOutTheThrottle() async {
    let defaults = UserDefaults(suiteName: "first-day-\(UUID().uuidString)")!
    // Checked a moment ago, but no answer was ever kept — the state an upgrade
    // from a version that had no update check leaves behind.
    defaults.set(Date(), forKey: "lastUpdateCheck")

    let store = Store(source: EmptySource(), defaults: defaults,
                      updateChecker: UpdateChecker(currentVersion: "0.1.0",
                                                   fetch: { _ in release(tag: "v9.9.9") }))
    await store.checkForUpdate()

    // It asked, rather than staying silent about versions for a day.
    #expect(store.update != .unknown)
}

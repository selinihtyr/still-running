import Testing
import Foundation
@testable import StillRunningCore
import Detectors

private func cleanDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func storesAndRecallsExclusions() {
    let defaults = cleanDefaults("exclusions-test-1")
    var exclusions = Exclusions(defaults: defaults)

    exclusions.add("browser:/tmp/claude-cdp-prof")

    #expect(exclusions.contains("browser:/tmp/claude-cdp-prof"))
    #expect(Exclusions(defaults: defaults).contains("browser:/tmp/claude-cdp-prof"))
}

@Test func removesAnExclusion() {
    let defaults = cleanDefaults("exclusions-test-2")
    var exclusions = Exclusions(defaults: defaults)

    exclusions.add("container:selene-api")
    exclusions.remove("container:selene-api")

    #expect(!exclusions.contains("container:selene-api"))
    #expect(!Exclusions(defaults: defaults).contains("container:selene-api"))
}

@Test func settingsRoundTripThroughDefaults() {
    let defaults = cleanDefaults("settings-test-1")
    let store = SettingsStore(defaults: defaults)

    var settings = store.settings
    settings.minimumAge = 4 * 3600
    settings.notifyAfter = 8 * 3600
    store.settings = settings

    #expect(SettingsStore(defaults: defaults).settings.minimumAge == 4 * 3600)
    // The literal must be spelled as a Double: comparing an Optional<Double>
    // against an integer expression bridges through AnyHashable and is always
    // false, even when the values match.
    #expect(SettingsStore(defaults: defaults).settings.notifyAfter == 28_800.0)
}

@Test func settingsFallBackToDefaultsWhenStorageIsEmpty() {
    #expect(SettingsStore(defaults: cleanDefaults("settings-test-2")).settings == Settings())
}

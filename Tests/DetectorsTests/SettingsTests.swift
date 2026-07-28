import Testing
import Foundation
@testable import Detectors

// MARK: - Surviving an upgrade

@Test func keepsYourChoicesWhenANewerVersionAddsASetting() throws {
    // Written by 0.3.0, which had never heard of checksForUpdates. The
    // synthesised decoder throws on the missing key, which would reset every
    // choice the user had made.
    let old = Data(#"{"minimumAge":900,"sustainedCPUPercent":25,"sustainedCPUWindow":180,"idleCPUPercent":2,"idleWindow":1800,"idleMemoryBytes":524288000,"activeCPUPercent":5,"activityWindow":600,"notifyAfter":3600}"#.utf8)

    let settings = try JSONDecoder().decode(Settings.self, from: old)

    #expect(settings.minimumAge == 900)
    #expect(settings.notifyAfter == 3600)
    #expect(settings.checksForUpdates == true)
}

@Test func anEmptySettingsFileDecodesToTheDefaults() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
    #expect(settings == Settings())
}

@Test func remembersThatUpdateChecksWereSwitchedOff() throws {
    var settings = Settings()
    settings.checksForUpdates = false
    let round = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(round.checksForUpdates == false)
}

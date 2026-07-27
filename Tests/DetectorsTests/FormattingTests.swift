import Testing
import Foundation
@testable import Detectors

@Test func showsMinutesUnderAnHour() {
    #expect(Formatting.duration(0) == "0m")
    #expect(Formatting.duration(45 * 60) == "45m")
}

@Test func showsHoursAndMinutesUpToTwoDays() {
    #expect(Formatting.duration(3600) == "1h 0m")
    #expect(Formatting.duration(18 * 3600 + 43 * 60) == "18h 43m")
}

@Test func keepsMinutesVisibleOnTheFirstDay() {
    // A stack of containers started together would otherwise all read "1d 0h"
    // and look frozen.
    #expect(Formatting.duration(24 * 3600 + 46 * 60) == "1d 46m")
    #expect(Formatting.duration(24 * 3600 + 3 * 60) == "1d 3m")
}

@Test func prefersHoursOverMinutesOnceThereAreAny() {
    #expect(Formatting.duration(29 * 3600 + 5 * 60) == "1d 5h")
    #expect(Formatting.duration(76 * 3600) == "3d 4h")
}

@Test func dropsAZeroSecondUnitEntirely() {
    #expect(Formatting.duration(48 * 3600) == "2d")
    #expect(Formatting.duration(24 * 3600) == "1d")
}

@Test func neverShowsANegativeDuration() {
    #expect(Formatting.duration(-500) == "0m")
}

@Test func memoryReadsInMegabytesThenGigabytes() {
    #expect(Formatting.memory(340 * 1_048_576) == "340 MB")
    #expect(Formatting.memory(2 * 1024 * 1_048_576) == "2.0 GB")
}

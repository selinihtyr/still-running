import Testing
import Foundation
@testable import StillRunningCore

@Test func explainsEachLoginItemStateInWordsAUserCanActOn() {
    #expect(LoginItem.State.enabled.isOn)
    #expect(!LoginItem.State.disabled.isOn)
    #expect(!LoginItem.State.blockedByUser.isOn)
    // The one state a toggle cannot fix: macOS is holding it off, and only
    // System Settings can let it back on. Saying so beats a switch that
    // silently flips back.
    #expect(LoginItem.State.blockedByUser.explanation != nil)
    #expect(LoginItem.State.enabled.explanation == nil)
    #expect(LoginItem.State.disabled.explanation == nil)
}

@Test func aLoginItemIsOnlyPossibleForAnInstalledApp() {
    // Running from a .build directory during development, there is no bundle to
    // register, and offering the switch would be a lie.
    #expect(!LoginItem.isAvailable(bundlePath: "/Users/x/still-running/.build/release/StillRunning"))
    #expect(LoginItem.isAvailable(bundlePath: "/Applications/Still Running.app"))
    #expect(LoginItem.isAvailable(bundlePath: "/Users/x/Applications/Still Running.app"))
}

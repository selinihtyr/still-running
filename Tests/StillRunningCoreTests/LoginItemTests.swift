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
    #expect(LoginItem.isAvailable(bundlePath: "/Users/x/Applications/Still Running.app", home: "/Users/x"))
}

@Test func aBuiltCopyNeverTakesTheLoginItem() {
    // What this guards, found on the machine this was written on: the login
    // item pointed at ~/StudioProjects/still-running/build/Still Running.app.
    // A built copy is a bundle like any other, so it registered itself the
    // first time it ran — and registration happens once, so the copy in
    // /Applications could never take it back. Every rebuild then deleted the
    // bundle macOS had been told to launch, out from under the running process.
    #expect(!LoginItem.isAvailable(bundlePath: "/Users/x/still-running/build/Still Running.app", home: "/Users/x"))
    #expect(!LoginItem.isAvailable(bundlePath: "/Users/x/Desktop/Still Running.app", home: "/Users/x"))
    #expect(!LoginItem.isAvailable(bundlePath: "/Volumes/Downloads/Still Running.app"))
}

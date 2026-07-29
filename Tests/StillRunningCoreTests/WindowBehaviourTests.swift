import Testing
import AppKit
@testable import StillRunningCore

/// Opening Settings from the menu bar could slide the whole screen to another
/// desktop: a menu bar app has no Dock icon to go back to, so being thrown out
/// of a full-screen window to look at a picker is the entire interruption.
@Test func settingsWindowComesToYouRatherThanTakingYouToIt() {
    let behaviour = WindowBehaviour.followingTheActiveSpace(from: [])

    #expect(behaviour.contains(.moveToActiveSpace))
}

/// A window opened while a full-screen app is frontmost has to be allowed to
/// sit on top of it. Without this it has nowhere to appear but its own Space,
/// which is the jump all over again.
@Test func settingsWindowIsAllowedOverAFullScreenApp() {
    let behaviour = WindowBehaviour.followingTheActiveSpace(from: [])

    #expect(behaviour.contains(.fullScreenAuxiliary))
}

/// Whatever AppKit set up for the window is still wanted; this adds to it.
@Test func keepsTheBehaviourTheWindowAlreadyHad() {
    let behaviour = WindowBehaviour.followingTheActiveSpace(from: [.managed])

    #expect(behaviour.contains(.managed))
}

/// The one that actually caused the jump. A window carrying `fullScreenNone`
/// is banned from full-screen Spaces, so when the Space you are on is a
/// full-screen app, macOS cannot bring the window to you and moves you to it
/// instead — and `moveToActiveSpace` sits there looking correct while being
/// powerless. AppKit enforces the ban by quietly stripping `fullScreenAuxiliary`
/// back off, which is how this was finally caught.
@Test func liftsTheBanThatKeepsItOffFullScreenSpaces() {
    let behaviour = WindowBehaviour.followingTheActiveSpace(from: [.fullScreenNone])

    #expect(!behaviour.contains(.fullScreenNone))
    #expect(behaviour.contains(.fullScreenAuxiliary))
}

/// Following the active Space and being pinned to every Space are contradictory
/// requests, and AppKit resolves the pair by ignoring the one we depend on.
@Test func dropsTheAllSpacesPinThatWouldCancelIt() {
    let behaviour = WindowBehaviour.followingTheActiveSpace(from: [.canJoinAllSpaces])

    #expect(!behaviour.contains(.canJoinAllSpaces))
    #expect(behaviour.contains(.moveToActiveSpace))
}

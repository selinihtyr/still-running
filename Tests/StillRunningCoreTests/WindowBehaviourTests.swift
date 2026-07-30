import Testing
import AppKit
@testable import StillRunningCore

/// Opening Settings from the menu bar could slide the whole screen to another
/// desktop: a menu bar app has no Dock icon to go back to, so being thrown out
/// of a full-screen window to look at a picker is the entire interruption.
///
/// The window it happened to was a SwiftUI `Window` scene, and no order of
/// operations fixed it: AppKit re-imposes `fullScreenNone` as part of showing
/// such a window — measured as 131330 immediately before the show and 131586
/// immediately after. Settings is a panel this app creates instead, and these
/// are the terms it is created on.
@Test func settingsPanelIsOnEverySpaceSoItNeverTakesYouToAnother() {
    #expect(WindowBehaviour.settingsPanelBehaviour.contains(.canJoinAllSpaces))
}

/// The Mac this was written on spends most of its time in a full-screen or tiled
/// Space. A settings panel that cannot appear over one is a settings panel that
/// moves you somewhere else to be read.
@Test func settingsPanelIsAllowedOverAFullScreenApp() {
    #expect(WindowBehaviour.settingsPanelBehaviour.contains(.fullScreenAuxiliary))
}

/// The ban that caused all of it, gone by construction rather than by stripping
/// it back off after AppKit has put it on.
@Test func settingsPanelCarriesNoBanOnFullScreenSpaces() {
    #expect(!WindowBehaviour.settingsPanelBehaviour.contains(.fullScreenNone))
    #expect(!WindowBehaviour.settingsPanelBehaviour.contains(.fullScreenPrimary))
}

/// `moveToActiveSpace` and `canJoinAllSpaces` are contradictory instructions and
/// AppKit settles the argument by disregarding one of them. A panel that is on
/// every Space has no need to be moved to the active one.
@Test func settingsPanelDoesNotAlsoAskToBeMoved() {
    #expect(!WindowBehaviour.settingsPanelBehaviour.contains(.moveToActiveSpace))
}

/// Settings appears where the panel was hanging, not in the middle of the
/// screen: the menu bar is the only place a menu bar app is ever looked at.
@Test func settingsHangsFromWhereThePanelWas() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let panel = CGRect(x: 900, y: 500, width: 390, height: 420)

    let placed = WindowBehaviour.placement(size: CGSize(width: 480, height: 640),
                                           anchor: panel, visibleFrame: screen)

    #expect(placed.maxX == panel.maxX)
    #expect(placed.maxY == panel.maxY)
}

/// With nothing to hang from — the window reopened without the panel, say — it
/// still belongs under the menu bar rather than wherever it was last left.
@Test func withoutAPanelItGoesToTheTopRight() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)

    let placed = WindowBehaviour.placement(size: CGSize(width: 480, height: 640),
                                           anchor: nil, visibleFrame: screen)

    #expect(placed.maxX == screen.maxX - 8)
    #expect(placed.maxY == screen.maxY)
}

/// A panel hanging from an icon near the left edge would put a wider window off
/// the side of the screen. Half a settings window is no use to anyone.
@Test func neverPushesItselfOffTheScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let panel = CGRect(x: 40, y: 500, width: 390, height: 420)

    let placed = WindowBehaviour.placement(size: CGSize(width: 480, height: 640),
                                           anchor: panel, visibleFrame: screen)

    #expect(placed.minX >= screen.minX)
    #expect(placed.maxX <= screen.maxX)
}

/// The screen the panel is on is the screen Settings belongs on, even when it is
/// not the one holding the pointer.
@Test func staysOnTheScreenThePanelWasOn() {
    let left = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    let panel = CGRect(x: 1600, y: 600, width: 390, height: 420)

    let placed = WindowBehaviour.placement(size: CGSize(width: 480, height: 640),
                                           anchor: panel, visibleFrame: right)

    #expect(placed.minX >= right.minX)
    #expect(!left.intersects(placed))
}

/// A second display can be shorter than the window is tall; the window has to
/// end up somewhere on it rather than hanging off the bottom.
@Test func fitsOnAScreenShorterThanTheWindow() {
    let small = CGRect(x: 0, y: 0, width: 800, height: 500)

    let placed = WindowBehaviour.placement(size: CGSize(width: 480, height: 640),
                                           anchor: nil, visibleFrame: small)

    #expect(placed.minY >= small.minY)
    #expect(placed.minX >= small.minX)
}

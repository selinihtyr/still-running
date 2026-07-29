import AppKit

/// How the settings window behaves around Spaces.
///
/// A menu bar app is reached from the menu bar, which is on every Space. Its
/// window is not. Left to AppKit's defaults, opening Settings while a
/// full-screen app is frontmost activates a window that lives on some other
/// desktop, and macOS obliges by sliding the entire screen over to it — so
/// asking to change a picker throws you out of whatever you were looking at,
/// with no Dock icon to click your way back from.
public enum WindowBehaviour {
    /// The window should come to the Space you are on, and be allowed to sit
    /// over a full-screen app once it gets there. `canJoinAllSpaces` is dropped
    /// because it and `moveToActiveSpace` are contradictory instructions, and
    /// AppKit settles the argument by disregarding the one this depends on.
    public static func followingTheActiveSpace(
        from existing: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var behaviour = existing
        behaviour.remove(.canJoinAllSpaces)
        behaviour.insert(.moveToActiveSpace)
        behaviour.insert(.fullScreenAuxiliary)
        return behaviour
    }
}

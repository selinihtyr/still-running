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
    /// over a full-screen app once it gets there.
    ///
    /// `fullScreenNone` is the one that mattered, and it is the one a SwiftUI
    /// `Window` of fixed size arrives with. It bans the window from full-screen
    /// Spaces outright — so when the Space you are on *is* a full-screen app,
    /// there is nowhere for the window to go and macOS moves you to where it can
    /// live instead. `moveToActiveSpace` cannot help: the active Space is
    /// precisely the one the window is forbidden to enter. AppKit enforces the
    /// ban by stripping `fullScreenAuxiliary` straight back off, so both have to
    /// be settled in the same breath.
    ///
    /// `canJoinAllSpaces` goes for a smaller version of the same reason: it and
    /// `moveToActiveSpace` are contradictory instructions, and AppKit settles
    /// that argument by disregarding the one this depends on.
    public static func followingTheActiveSpace(
        from existing: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var behaviour = existing
        behaviour.remove(.canJoinAllSpaces)
        behaviour.remove(.fullScreenNone)
        behaviour.insert(.moveToActiveSpace)
        behaviour.insert(.fullScreenAuxiliary)
        return behaviour
    }

    /// Applied to the window *after* it has been shown, which is the only moment
    /// that sticks. AppKit re-imposes `fullScreenNone` on a window that cannot be
    /// resized as it puts it on screen, so anything set while the view is being
    /// attached is overwritten a moment later — measured, not guessed: the
    /// behaviour read back as 131330 at attach and 131586 once visible.
    public static func followTheActiveSpace(_ window: NSWindow) {
        window.collectionBehavior = followingTheActiveSpace(from: window.collectionBehavior)
    }

    /// The settings window among the app's windows, by the id its scene was
    /// given. Matching on identifier rather than title keeps this working in
    /// whatever language the window is titled in.
    public static func window(withIdentifier id: String, among windows: [NSWindow]) -> NSWindow? {
        windows.first { $0.identifier?.rawValue == id }
    }
}

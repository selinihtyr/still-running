import AppKit

/// Where the settings panel sits and how it behaves around Spaces.
///
/// A menu bar app is reached from the menu bar, which is on every Space. Its
/// window is not, and a window that cannot appear where you are is one macOS
/// takes you to instead — throwing you out of a full-screen app to look at a
/// picker, with no Dock icon to find your way back from. `SettingsPanel` has the
/// long version of that story; this is the geometry and the terms.
public enum WindowBehaviour {
    /// What the settings panel is called among the app's windows.
    public static let settingsIdentifier = "settings"

    /// A panel we create ourselves can be told this once and it stays told.
    ///
    /// `canJoinAllSpaces` rather than `moveToActiveSpace`: a window that is on
    /// every Space is already on the one you are looking at, so there is no
    /// moment where macOS has to decide whether to bring the window to you or
    /// take you to the window. `fullScreenAuxiliary` lets it sit over a
    /// full-screen or tiled Space, which is where this Mac usually is — and with
    /// no `fullScreenNone` in sight, since we are not asking AppKit to guess.
    public static let settingsPanelBehaviour: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .fullScreenAuxiliary]

    /// Everything the panel needs to be told, applied on every show.
    @MainActor public static func prepareSettingsPanel(_ window: NSWindow, size: CGSize) {
        pinTheSize(window, size: size)
        window.collectionBehavior = settingsPanelBehaviour
        // Settings that stay put while you look at something else, and a close
        // button that hides the panel rather than throwing away what it holds.
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
    }

    /// One size, and no memory of where it has been.
    ///
    /// The window is allowed to be resizable — AppKit bans windows that are not
    /// from full-screen Spaces — and then pinned so that nothing can actually
    /// resize it. Without the pin it opens 900 points wide, measured.
    ///
    /// Restoration is switched off deliberately: it remembers which Space a
    /// window was on and puts it back there, which is the jump arriving by
    /// another route.
    @MainActor public static func pinTheSize(_ window: NSWindow, size: CGSize) {
        window.styleMask.insert(.resizable)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isRestorable = false
    }

    /// The menu bar panel itself: where Settings should appear, and the window
    /// that should get out of the way once it has. Anything else on screen
    /// belongs to the app itself — with no Dock icon and no document windows,
    /// the only other window of any size is the panel hanging from the menu bar.
    public static func menuBarPanel(among windows: [NSWindow], excluding id: String) -> NSWindow? {
        windows.first {
            $0.isVisible
                && $0.identifier?.rawValue != id
                && $0.frame.width >= 200
                && $0.frame.height >= 200
        }
    }

    /// Under the menu bar, right edge lined up with the panel it came from. A
    /// menu bar app has one place the user is already looking at, and it is not
    /// the middle of the screen. Pure geometry, so the rules can be tested
    /// without a window or a second display.
    public static func placement(size: CGSize, anchor: CGRect?, visibleFrame: CGRect) -> CGRect {
        let inset: CGFloat = 8
        let rightEdge = anchor?.maxX ?? visibleFrame.maxX - inset
        let topEdge = anchor?.maxY ?? visibleFrame.maxY
        // Never off the screen it is meant to be on: a narrow display, or a
        // panel hanging from an icon near the left edge, must not push the
        // window's left side out of view.
        let x = min(max(rightEdge - size.width, visibleFrame.minX + inset),
                    max(visibleFrame.maxX - size.width - inset, visibleFrame.minX + inset))
        let y = min(max(topEdge - size.height, visibleFrame.minY + inset),
                    max(visibleFrame.maxY - size.height, visibleFrame.minY + inset))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The screen the user is on: the one holding the panel they just clicked,
    /// or failing that the one under the pointer.
    public static func screen(holding anchor: CGRect?, or pointer: NSPoint,
                              among screens: [NSScreen]) -> NSScreen? {
        if let anchor, let found = screens.first(where: { $0.frame.intersects(anchor) }) {
            return found
        }
        return screens.first { $0.frame.contains(pointer) } ?? screens.first
    }

    /// Put Settings where the panel was. Called after the window is on screen,
    /// which is the only moment the behaviour sticks; moving it afterwards is a
    /// move within the Space it has just been brought to, not another jump.
    /// The size is dictated rather than read off the window: allowing the window
    /// to be resizable is what keeps the full-screen ban off it, and a window
    /// that is allowed to grow opens 900 points wide unless told otherwise —
    /// measured on the machine. Asking the window to convert a content size into
    /// a frame keeps the title bar out of the arithmetic.
    @MainActor public static func place(_ window: NSWindow, anchor: CGRect?,
                                       contentSize: CGSize,
                                       screens: [NSScreen] = NSScreen.screens,
                                       pointer: NSPoint = NSEvent.mouseLocation) {
        guard let screen = screen(holding: anchor, or: pointer, among: screens) else { return }
        let frameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        window.setFrame(placement(size: frameSize, anchor: anchor, visibleFrame: screen.visibleFrame),
                        display: true)
    }

}

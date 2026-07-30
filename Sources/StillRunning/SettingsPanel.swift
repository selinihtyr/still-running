import AppKit
import SwiftUI
import Detectors
import StillRunningCore

/// Settings as a panel this app owns, rather than a SwiftUI `Window` scene.
///
/// The scene had to go, and the reason was measured rather than guessed. A
/// `Window` of fixed size arrives banned from full-screen Spaces
/// (`fullScreenNone`), and AppKit re-imposes that ban as part of putting the
/// window on screen: the collection behaviour reads 131330 the instant before
/// the window is shown and 131586 the instant after, whether it was set while
/// the view was attaching, straight after the open, or both. So when the Space
/// you are on is a full-screen or tiled one — which is where this Mac spends
/// most of its time — there is nowhere for the window to appear, and macOS
/// slides the whole screen to the desktop where it can live. Asking a picker
/// about notifications should not throw you out of what you were doing, and a
/// menu bar app has no Dock icon to find your way back with.
///
/// A panel we create ourselves keeps what it is told. It can join every Space,
/// so it is already on the one you are looking at, and it does not activate the
/// app when it is shown, so nothing else can decide to take you elsewhere.
@MainActor final class SettingsPanel {
    static let shared = SettingsPanel()

    /// The panel is kept rather than rebuilt: it holds what you were in the
    /// middle of reading, and a window recreated on every click loses the
    /// scroll position along with the result of the last test notification.
    private var panel: NSPanel?

    private static let size = CGSize(width: Theme.settingsWidth, height: Theme.settingsHeight)

    private init() {}

    /// - Parameter anchor: where the menu bar panel was hanging, so Settings can
    ///   appear in the same place rather than in the middle of the screen.
    func show(store: Store, anchor: CGRect?) {
        let panel = self.panel ?? make(store: store)
        self.panel = panel

        // Reapplied on every show. Nothing else is fighting us here, but a panel
        // dragged to another screen and reopened should still come back to the
        // menu bar it was opened from.
        WindowBehaviour.prepareSettingsPanel(panel, size: Self.size)
        WindowBehaviour.place(panel, anchor: anchor, contentSize: Self.size)

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func make(store: Store) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            // `nonactivatingPanel` is the one that matters: the panel takes key
            // focus without the app becoming active. `resizable` is in the mask
            // because AppKit bans windows that cannot be resized from
            // full-screen Spaces; the content size is pinned right afterwards,
            // so nothing can actually be dragged out of shape.
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = "Still Running"
        panel.identifier = NSUserInterfaceItemIdentifier(WindowBehaviour.settingsIdentifier)
        // Dark whatever the system is set to, title bar included: the rows and
        // the one orange warning were tuned against a dark window, and SwiftUI's
        // `preferredColorScheme` inside a hosting view does not reach the frame.
        panel.appearance = NSAppearance(named: .darkAqua)
        // Floating, because a Space belonging to a full-screen app puts that
        // app's window above every ordinary one. Measured on the machine: at the
        // ordinary level the panel was on the active Space and reported visible,
        // and was still nowhere to be seen — Chrome's full-screen window was in
        // front of it. Activating the app does not help; a level does.
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: SettingsView(store: store))
        return panel
    }
}

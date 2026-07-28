import Foundation
import AppKit

/// Installing an update means running the same two commands the README gives
/// you — a pull and the installer — in the checkout the app was built from.
/// Doing it in a Terminal window rather than silently in the background is
/// deliberate: a build takes a minute, and you should be able to watch it and
/// see it fail.
public enum Updater {
    /// The build records where it came from, because an installed app has no
    /// other way of knowing. Nothing is run unless that path still holds an
    /// installer.
    public static let sourceRootKey = "SRSourceRoot"

    public static func sourceRoot(recordedPath: String?,
                                  exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> URL? {
        guard let recordedPath, !recordedPath.isEmpty else { return nil }
        let root = URL(fileURLWithPath: recordedPath)
        guard exists(root.appendingPathComponent("scripts/install.sh").path) else { return nil }
        return root
    }

    public static func recordedSourceRoot() -> URL? {
        sourceRoot(recordedPath: Bundle.main.object(forInfoDictionaryKey: sourceRootKey) as? String)
    }

    public static func script(sourceRoot: URL) -> String {
        """
        #!/bin/bash
        cd "\(sourceRoot.path)" || exit 1
        echo "Updating Still Running…"
        git pull --ff-only || exit 1
        ./scripts/install.sh
        echo
        echo "Done. You can close this window."
        """
    }

    /// Runs the update in Terminal, or falls back to the release page when the
    /// checkout is gone. A `.command` file opens Terminal without asking for
    /// permission to control it.
    @MainActor
    @discardableResult
    public static func install(fallbackPage: URL) -> Bool {
        guard let root = recordedSourceRoot() else {
            NSWorkspace.shared.open(fallbackPage)
            return false
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-still-running.command")
        do {
            try script(sourceRoot: root).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch {
            NSWorkspace.shared.open(fallbackPage)
            return false
        }
        NSWorkspace.shared.open(file)
        return true
    }
}

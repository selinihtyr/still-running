import Foundation
import ProcessKit

/// A command-line process whose parent died and whose terminal is gone. macOS
/// reparents it to launchd, where nothing will ever clean it up.
public struct OrphanDetector: Detector {
    public let kind: FindingKind = .orphan

    public init() {}

    /// macOS's own, always skipped. Nothing here is ever a stray command
    /// somebody left behind, and Spotlight's workers alone would otherwise
    /// raise a false alarm every time the machine indexes anything.
    private static let systemPrefixes = ["/System/", "/Library/", "/usr/libexec/",
                                         "/usr/sbin/", "/sbin/"]
    /// Apple's core tools live here and so do a person's own: `sh`, `sleep`,
    /// the shell a closed terminal leaves reparented to launchd. Skipped while
    /// quiet, because nobody wants to be told about a sleeping `-zsh` — but not
    /// while burning a core. Two `/bin/sh -c 'while :; do :; done'` orphaned by
    /// an interrupted test run pinned a core each here for eight minutes, and
    /// this list is why nothing said so.
    private static let sharedPrefixes = ["/usr/bin/", "/bin/"]
    /// Anything shipped inside a bundle is managed by whatever launched it.
    private static let bundleMarkers = [".app/Contents/", ".xpc/Contents/",
                                        ".appex/Contents/", ".framework/"]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.processes.compactMap { process -> Finding? in
            // Sustained, not a spike: a command that flares for one interval on
            // its way out must not turn a skipped directory into a finding.
            let busy = (history.sustainedCPU(pid: process.pid, over: settings.sustainedCPUWindow) ?? 0)
                >= settings.sustainedCPUPercent

            guard process.uid == snapshot.currentUID,
                  process.pid != snapshot.ownPID,
                  process.ppid == 1,
                  !process.hasControllingTTY,
                  !snapshot.managedPIDs.contains(process.pid),   // a service, not a stray
                  !Self.isBundled(process),
                  !Self.isSystemPath(process.executablePath),
                  !Self.isSharedPath(process.executablePath) || busy,
                  !IsolatedBrowserDetector.isBrowser(process)   // the browser detector owns those
            else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(process.startedAt)
            let cpu = history.cpuPercent(pid: process.pid) ?? 0
            return Finding(
                identity: "orphan:\(process.executablePath)",
                kind: .orphan,
                title: process.name,
                detail: "no terminal, adopted by launchd",
                cpuPercent: cpu,
                memoryBytes: process.residentBytes,
                age: age,
                target: .processes([process.pid]),
                severity: cpu >= 50 ? .urgent : .notable,
                explanation: "\(FindingKind.orphan.plainDescription) It came from \(process.executablePath).",
                revealPath: (process.executablePath as NSString).deletingLastPathComponent,
                details: """
                    Orphaned process: \(process.name)
                    pid \(process.pid)
                    \(process.executablePath)
                    \(process.arguments.joined(separator: " "))
                    """,
                command: process.arguments.joined(separator: " "))
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// Anything inside a bundle — an app, an XPC service, an extension, a
    /// framework helper — is a managed component, not a stray command.
    static func isBundled(_ process: ProcessSample) -> Bool {
        bundleMarkers.contains { process.executablePath.contains($0) }
    }

    static func isSystemPath(_ path: String) -> Bool {
        systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// Shared ground: Apple's core tools and yours, in the same directory.
    static func isSharedPath(_ path: String) -> Bool {
        sharedPrefixes.contains { path.hasPrefix($0) }
    }
}

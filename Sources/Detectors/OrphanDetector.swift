import Foundation
import ProcessKit

/// A command-line process whose parent died and whose terminal is gone. macOS
/// reparents it to launchd, where nothing will ever clean it up.
public struct OrphanDetector: Detector {
    public let kind: FindingKind = .orphan

    public init() {}

    private static let systemPrefixes = ["/System/", "/Library/", "/usr/libexec/",
                                         "/usr/sbin/", "/sbin/", "/usr/bin/"]
    /// Anything shipped inside a bundle is managed by whatever launched it.
    private static let bundleMarkers = [".app/Contents/", ".xpc/Contents/",
                                        ".appex/Contents/", ".framework/"]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.processes.compactMap { process -> Finding? in
            guard process.uid == snapshot.currentUID,
                  process.pid != snapshot.ownPID,
                  process.ppid == 1,
                  !process.hasControllingTTY,
                  !snapshot.managedPIDs.contains(process.pid),   // a service, not a stray
                  !Self.isBundled(process),
                  !Self.isSystemPath(process.executablePath),
                  !IsolatedBrowserDetector.isBrowser(process)   // the browser detector owns those
            else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(process.startedAt)
            let cpu = history.cpuPercent(pid: process.pid) ?? 0
            return Finding(
                identity: "orphan:\(process.executablePath)",
                kind: .orphan,
                title: "\(process.name) · no terminal",
                detail: "\(Formatting.duration(age)) · adopted by launchd",
                cpuPercent: cpu,
                memoryBytes: process.residentBytes,
                age: age,
                target: .processes([process.pid]),
                severity: cpu >= 50 ? .urgent : .notable)
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
}

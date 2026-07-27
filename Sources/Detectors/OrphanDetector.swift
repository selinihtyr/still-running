import Foundation
import ProcessKit

/// A command-line process whose parent died and whose terminal is gone. macOS
/// reparents it to launchd, where nothing will ever clean it up.
public struct OrphanDetector: Detector {
    public let kind: FindingKind = .orphan

    public init() {}

    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/usr/bin/"]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.processes.compactMap { process -> Finding? in
            guard process.uid == snapshot.currentUID,
                  process.pid != snapshot.ownPID,
                  process.ppid == 1,
                  !process.hasControllingTTY,
                  !Self.isApplicationBundle(process),
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

    /// Anything inside a .app is a normal application, not a stray command.
    static func isApplicationBundle(_ process: ProcessSample) -> Bool {
        process.executablePath.contains(".app/Contents/")
    }

    static func isSystemPath(_ path: String) -> Bool {
        systemPrefixes.contains { path.hasPrefix($0) }
    }
}

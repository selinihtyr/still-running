import Foundation
import Detectors
import ProcessKit

public enum SafetyError: Error, Equatable {
    case protectedProcess(pid: Int32, reason: String)
    case unknownProcess(pid: Int32)
}

/// The last check before a signal is sent. It deliberately repeats work the
/// detectors already do: a bug in a detector must not be able to end the
/// user's session.
public struct SafetyGuard: Sendable {
    public static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Finder", "Dock",
        "SystemUIServer", "coreaudiod", "logind", "securityd", "opendirectoryd",
        "distnoted", "cfprefsd", "mds", "mds_stores", "Spotlight",
    ]
    public static let minimumPID: Int32 = 100

    public init() {}

    public func vet(_ finding: Finding, in snapshot: Snapshot) throws {
        // Containers and simulators have their own lifecycle APIs and cannot
        // name a system process, so there is nothing to vet for them.
        guard case .processes(let pids) = finding.target else { return }

        for pid in pids {
            guard let process = snapshot.process(pid: pid) else { throw SafetyError.unknownProcess(pid: pid) }
            if let reason = protectionReason(for: process, in: snapshot) {
                throw SafetyError.protectedProcess(pid: pid, reason: reason)
            }
        }
    }

    /// Why this process may never be stopped, or nil when it may.
    public func protectionReason(for process: ProcessSample, in snapshot: Snapshot) -> String? {
        if process.pid < Self.minimumPID { return "system process" }
        if process.pid == snapshot.ownPID { return "Still Running itself" }
        if process.executablePath.contains("Still Running.app") { return "Still Running itself" }
        // Named checks come before the uid check purely for the message: most
        // of these run as a system user, and "critical to the session" tells
        // the user more than "owned by another user".
        if Self.protectedNames.contains(process.name) { return "critical to the session" }
        if process.uid != snapshot.currentUID { return "owned by another user" }
        if IsolatedBrowserDetector.isBrowser(process),
           IsolatedBrowserDetector.isolationSignature(process) == nil {
            return "your browser, with your tabs"
        }
        return nil
    }
}

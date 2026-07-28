import Foundation
import ProcessKit

/// Tunnels: cloudflared, ngrok and friends. You start one to show someone a
/// local thing for five minutes, and it stays up for days — still exposing
/// whatever port you pointed it at, long after you stopped thinking about it.
///
/// This is the one kind here where being forgotten is a security matter and
/// not only a wasted core, so a tunnel is listed on age alone.
public struct TunnelDetector: Detector {
    public let kind: FindingKind = .tunnel

    public init() {}

    public static let knownTunnels: Set<String> = [
        "cloudflared", "ngrok", "localtunnel", "lt", "bore", "frpc", "pagekite",
    ]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.processes.compactMap { process -> Finding? in
            guard process.uid == snapshot.currentUID,
                  process.pid != snapshot.ownPID,
                  !snapshot.managedPIDs.contains(process.pid),   // a service, installed on purpose
                  Self.knownTunnels.contains(process.name)
            else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(process.startedAt)
            guard age >= settings.minimumAge else { return nil }

            let target = Self.exposedTarget(process)
            return Finding(
                identity: "tunnel:\(process.name)|\(target ?? "")",
                kind: .tunnel,
                title: process.name,
                detail: target ?? "tunnel",
                cpuPercent: history.cpuPercent(pid: process.pid) ?? 0,
                memoryBytes: process.residentBytes,
                age: age,
                target: .processes([process.pid]),
                severity: .urgent,
                explanation: "A tunnel that has been open for \(Formatting.duration(age)), publishing something on this machine to the internet. Tunnels are usually started for a few minutes and then forgotten, which is why this one is listed on age alone.",
                revealPath: nil,
                details: """
                    Tunnel: \(process.name)
                    pid \(process.pid)
                    \(process.executablePath) \(process.arguments.dropFirst().joined(separator: " "))
                    """,
                command: process.arguments.joined(separator: " "))
        }
        .sorted { $0.age > $1.age }
    }

    /// What it is publishing, when the command line says so.
    static func exposedTarget(_ process: ProcessSample) -> String? {
        let arguments = process.arguments
        if let index = arguments.firstIndex(of: "--url"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        if let flag = arguments.first(where: { $0.hasPrefix("--url=") }) {
            return String(flag.dropFirst("--url=".count))
        }
        // `ngrok http 3000` and the like.
        if let last = arguments.last, Int(last) != nil { return "port \(last)" }
        return nil
    }
}

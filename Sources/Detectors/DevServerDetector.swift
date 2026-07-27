import Foundation
import ProcessKit

/// Development servers, bundlers, and watchers. These are the things people
/// start in a terminal, walk away from, and never stop.
public struct DevServerDetector: Detector {
    public let kind: FindingKind = .devServer

    public init() {}

    /// Matched against the executable name.
    public static let knownExecutables: Set<String> = [
        "node", "bun", "deno", "watchman", "watchmand", "esbuild", "rollup",
    ]

    /// Matched against the joined argument vector, so "node .../vite" is
    /// recognised as vite.
    public static let knownArgumentMarkers: [String] = [
        "vite", "next dev", "webpack", "nodemon", "turbopack", "metro",
        "uvicorn", "gunicorn", "flask run", "rails server", "puma",
        "GradleDaemon", "KotlinCompileDaemon", "dart:frontend_server",
    ]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.processes.compactMap { process -> Finding? in
            guard process.uid == snapshot.currentUID, process.pid != snapshot.ownPID,
                  let label = Self.label(for: process) else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(process.startedAt)
            let sustained = history.sustainedCPU(pid: process.pid, over: settings.sustainedCPUWindow)
            let idle = history.idleDuration(pid: process.pid, below: settings.idleCPUPercent)
            guard settings.crossesThreshold(age: age, sustainedCPU: sustained,
                                            idleFor: idle, memoryBytes: process.residentBytes)
            else { return nil }

            let cpu = history.cpuPercent(pid: process.pid) ?? 0
            return Finding(
                identity: "devserver:\(process.executablePath)|\(Self.signature(process))",
                kind: .devServer,
                title: label,
                detail: "\(Formatting.duration(age)) · \(Formatting.memory(process.residentBytes))",
                cpuPercent: cpu,
                memoryBytes: process.residentBytes,
                age: age,
                target: .processes([process.pid]),
                severity: cpu >= 50 ? .urgent : .notable)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// A human label like "vite" or "node · server.js", or nil when unrecognised.
    static func label(for process: ProcessSample) -> String? {
        let joined = process.arguments.joined(separator: " ")
        if let marker = knownArgumentMarkers.first(where: { joined.contains($0) }) {
            return marker.split(separator: " ").first.map(String.init) ?? marker
        }
        guard knownExecutables.contains(process.name) else { return nil }
        guard let script = process.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
            return process.name
        }
        return "\(process.name) · \((script as NSString).lastPathComponent)"
    }

    /// Arguments minus volatile parts, so identity survives a restart.
    static func signature(_ process: ProcessSample) -> String {
        process.arguments.dropFirst()
            .filter { !$0.hasPrefix("--port") && Int($0) == nil }
            .joined(separator: " ")
    }
}

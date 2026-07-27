import Foundation
import ProcessKit

/// Finds browsers running on a throwaway profile: automation, scraping, or a
/// tool run that was never cleaned up. A browser on its normal profile holds
/// the user's tabs and is never a candidate.
public struct IsolatedBrowserDetector: Detector {
    public let kind: FindingKind = .isolatedBrowser

    public init() {}

    private static let browserMarkers = ["Google Chrome", "Chromium", "Microsoft Edge",
                                         "Brave Browser", "Firefox", "Safari"]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        let candidates = snapshot.processes.filter {
            $0.uid == snapshot.currentUID && $0.pid != snapshot.ownPID && Self.isBrowser($0)
        }

        // Group by profile directory, so a fifteen-process Chrome tree is one row.
        var groups: [String: [ProcessSample]] = [:]
        for process in candidates {
            guard let signature = Self.isolationSignature(process) else { continue }
            groups[signature, default: []].append(process)
        }

        return groups.compactMap { signature, group -> Finding? in
            let sorted = group.sorted { $0.startedAt < $1.startedAt }
            guard let root = sorted.first else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(root.startedAt)
            let memory = group.reduce(UInt64(0)) { $0 + $1.residentBytes }
            let sustained = groupSustainedCPU(group, history, over: settings.sustainedCPUWindow)
            let idle = history.idleDuration(pid: root.pid, below: settings.idleCPUPercent)

            guard settings.crossesThreshold(age: age, sustainedCPU: sustained,
                                            idleFor: idle, memoryBytes: memory) else { return nil }

            let cpu = totalCPU(group, history)
            return Finding(
                identity: "browser:\(signature)",
                kind: .isolatedBrowser,
                title: "\(Self.browserName(root)) · automation profile",
                detail: "\(Formatting.duration(age)) · \(signature)",
                cpuPercent: cpu,
                memoryBytes: memory,
                age: age,
                target: .processes(Self.rootFirst(sorted)),
                severity: cpu >= 50 ? .urgent : .notable)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    public static func isBrowser(_ process: ProcessSample) -> Bool {
        browserMarkers.contains { process.executablePath.contains($0) }
    }

    static func browserName(_ process: ProcessSample) -> String {
        browserMarkers.first { process.executablePath.contains($0) } ?? process.name
    }

    /// The profile path when it is outside the standard location, a marker when
    /// the browser is headless or debuggable, nil when this is the user's own
    /// browsing.
    public static func isolationSignature(_ process: ProcessSample) -> String? {
        if let flag = process.arguments.first(where: { $0.hasPrefix("--user-data-dir=") }) {
            let path = String(flag.dropFirst("--user-data-dir=".count))
            return isStandardProfileLocation(path) ? nil : path
        }
        if process.arguments.contains(where: { $0.hasPrefix("--headless") }) { return "headless" }
        if process.arguments.contains(where: { $0.hasPrefix("--remote-debugging-port") }) { return "remote-debugging" }
        return nil
    }

    /// Profiles under Application Support belong to the user, whatever the flag says.
    static func isStandardProfileLocation(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        path.hasPrefix("\(home)/Library/Application Support")
    }

    /// Root first: whoever has no parent inside the group leads the list.
    static func rootFirst(_ group: [ProcessSample]) -> [Int32] {
        let pids = Set(group.map(\.pid))
        let roots = group.filter { !pids.contains($0.ppid) }
        let rest = group.filter { pids.contains($0.ppid) }
        return roots.map(\.pid) + rest.map(\.pid)
    }
}

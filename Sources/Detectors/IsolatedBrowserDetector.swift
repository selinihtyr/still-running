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
        Self.isolatedGroups(in: snapshot).compactMap { signature, group -> Finding? in
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
                // The profile path in the detail line says the rest; a longer
                // title only gets truncated in the middle, which reads worse
                // than saying less.
                title: "\(Self.shortBrowserName(root)) · automation",
                detail: signature,
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

    /// Profile signature to every process belonging to that profile.
    ///
    /// Grouping cannot go by the `--user-data-dir` flag alone: Chrome omits it
    /// from some helper types, so a flag-only grouping under-reports memory and
    /// would leave those helpers looking like the user's own browser. The tree
    /// is the truth — whatever descends from an isolated root is isolated.
    public static func isolatedGroups(in snapshot: Snapshot) -> [String: [ProcessSample]] {
        let browsers = snapshot.processes.filter {
            Self.isBrowser($0) && $0.uid == snapshot.currentUID && $0.pid != snapshot.ownPID
        }
        var childrenOf: [Int32: [ProcessSample]] = [:]
        for process in browsers { childrenOf[process.ppid, default: []].append(process) }

        let seeds = browsers
            .compactMap { process in isolationSignature(process).map { (process, $0) } }
            .sorted { $0.0.startedAt < $1.0.startedAt }   // outermost root first

        var groups: [String: [ProcessSample]] = [:]
        var assigned: Set<Int32> = []
        for (seed, signature) in seeds {
            guard !assigned.contains(seed.pid) else { continue }
            var stack = [seed]
            while let current = stack.popLast() {
                guard !assigned.contains(current.pid) else { continue }
                assigned.insert(current.pid)
                groups[signature, default: []].append(current)
                stack.append(contentsOf: childrenOf[current.pid] ?? [])
            }
        }
        return groups
    }

    /// Every pid that belongs to an isolated profile. The safety guard uses
    /// this to tell a helper of an automation browser apart from the user's own.
    public static func isolatedPIDs(in snapshot: Snapshot) -> Set<Int32> {
        Set(isolatedGroups(in: snapshot).values.flatMap { $0.map(\.pid) })
    }

    static func browserName(_ process: ProcessSample) -> String {
        browserMarkers.first { process.executablePath.contains($0) } ?? process.name
    }

    /// "Google Chrome" reads as "Chrome" in a narrow row; the vendor adds
    /// nothing the user needs.
    static func shortBrowserName(_ process: ProcessSample) -> String {
        let full = browserName(process)
        return full.hasPrefix("Google ") ? String(full.dropFirst("Google ".count)) : full
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

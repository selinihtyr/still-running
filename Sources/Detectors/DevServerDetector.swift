import Foundation
import ProcessKit

/// Development servers, bundlers, and watchers. These are the things people
/// start in a terminal, walk away from, and never stop.
///
/// One dev server is usually several processes — `npm run dev` launches the
/// framework, which launches a bundler — so a match is reported as the whole
/// tree beneath its root, the way it is actually started and stopped.
public struct DevServerDetector: Detector {
    public let kind: FindingKind = .devServer

    public init() {}

    /// Matched against the executable name.
    public static let knownExecutables: Set<String> = [
        "node", "bun", "deno", "watchman", "watchmand", "esbuild", "rollup",
    ]

    /// Matched against argument *basenames*, never whole paths: an esbuild
    /// binary living under `node_modules/vite/…` is not vite.
    public static let knownCommands: Set<String> = [
        "vite", "webpack", "nodemon", "turbopack", "metro", "astro", "next",
        "uvicorn", "gunicorn", "puma", "rails", "flask",
    ]

    /// Package runners: their own name is the useful part of the label.
    private static let runners: Set<String> = ["npm", "pnpm", "yarn", "npx", "bunx"]

    /// Matched against the whole argument vector, for things that identify
    /// themselves by a class name rather than a command.
    public static let knownArgumentMarkers: [String] = [
        "GradleDaemon", "KotlinCompileDaemon", "dart:frontend_server",
    ]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        let tree = ProcessTree(snapshot.processes)
        let seeds = snapshot.processes
            .filter {
                $0.uid == snapshot.currentUID && $0.pid != snapshot.ownPID
                && !snapshot.managedPIDs.contains($0.pid)   // a daemon someone installed on purpose
                && Self.label(for: $0) != nil
            }
            .sorted { $0.startedAt < $1.startedAt }          // outermost root first

        var claimed = Set<Int32>()
        return seeds.compactMap { seed -> Finding? in
            let group = tree.group(from: seed, claimed: &claimed)
            guard !group.isEmpty, let label = Self.label(for: seed) else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(seed.startedAt)
            let memory = group.totalResidentBytes
            let sustained = groupSustainedCPU(group, history, over: settings.sustainedCPUWindow)
            let idle = history.idleDuration(pid: seed.pid, below: settings.idleCPUPercent)
            guard settings.crossesThreshold(age: age, sustainedCPU: sustained,
                                            idleFor: idle, memoryBytes: memory) else { return nil }

            // A dev server that has done real work recently is one you are
            // using. Age alone would list the server you are typing against.
            let recentPeak = group
                .compactMap { history.peakCPU(pid: $0.pid, over: settings.activityWindow) }
                .max()
            if let recentPeak, recentPeak >= settings.activeCPUPercent { return nil }

            let cpu = totalCPU(group, history)
            return Finding(
                identity: "devserver:\(seed.executablePath)|\(Self.signature(seed))",
                kind: .devServer,
                title: label,
                detail: Self.describe(group),
                cpuPercent: cpu,
                memoryBytes: memory,
                age: age,
                target: .processes(group.pidsRootFirst),
                severity: cpu >= 50 ? .urgent : .notable,
                explanation: Self.explain(group: group, label: label,
                                          window: settings.activityWindow),
                revealPath: Self.projectDirectory(in: group),
                details: Self.details(label: label, group: group),
                command: seed.arguments.joined(separator: " "))
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// What to call this, or nil when it is not a dev server at all.
    /// "npm run dev", "astro dev", "node · server.js".
    static func label(for process: ProcessSample) -> String? {
        let joined = process.arguments.joined(separator: " ")
        if let marker = knownArgumentMarkers.first(where: { joined.contains($0) }) { return marker }

        let tokens = meaningfulTokens(process)
        if let first = tokens.first, runners.contains(first) {
            return tokens.prefix(3).joined(separator: " ")
        }
        if let command = tokens.first(where: { knownCommands.contains($0) }) {
            let rest = tokens.drop { $0 != command }.dropFirst().first { !$0.hasPrefix("-") }
            return rest.map { "\(command) \($0)" } ?? command
        }
        guard knownExecutables.contains(process.name) else { return nil }
        guard let script = tokens.first(where: { !$0.hasPrefix("-") }),
              looksLikeAScript(script)
        else { return process.name }
        return "\(process.name) · \(script)"
    }

    /// `node -e "…"` has no script file, so the first non-flag token is source
    /// code. Pasting it into the row gives a title nobody can read.
    private static func looksLikeAScript(_ token: String) -> Bool {
        token.rangeOfCharacter(from: CharacterSet(charactersIn: "()=;{}'\"`&|<>")) == nil
    }

    static func explain(group: [ProcessSample], label: String, window: TimeInterval) -> String {
        let minutes = Int(window / 60)
        let tree = group.count == 1
            ? "It is a single process."
            : "It is \(group.count) processes: the command you ran and everything it started."
        return "\(FindingKind.devServer.plainDescription) \(tree) "
            + "It has done nothing for at least \(minutes) minutes, which is why it is here — a server you are working against would not be listed."
    }

    static func details(label: String, group: [ProcessSample]) -> String {
        var lines = ["Dev server: \(label)"]
        for process in group {
            lines.append("pid \(process.pid) — \(process.executablePath) \(process.arguments.dropFirst().joined(separator: " "))")
        }
        return lines.joined(separator: "\n")
    }

    /// The project folder this belongs to, for opening in Finder.
    static func projectDirectory(in group: [ProcessSample]) -> String? {
        for process in group {
            for argument in process.arguments where argument.contains("/node_modules/") {
                return argument.components(separatedBy: "/node_modules/")[0]
            }
        }
        return nil
    }

    /// Which project this belongs to, plus how many processes it spans — the
    /// two things you need to decide whether you still want it.
    static func describe(_ group: [ProcessSample]) -> String {
        let count = group.count > 1 ? "\(group.count) processes" : "1 process"
        guard let project = projectName(in: group) else { return count }
        return "\(project) · \(count)"
    }

    /// Derived from any member's paths: the two directories above node_modules
    /// name the project far better than an absolute path does.
    static func projectName(in group: [ProcessSample]) -> String? {
        for process in group {
            for argument in process.arguments where argument.contains("/node_modules/") {
                let root = argument.components(separatedBy: "/node_modules/")[0]
                let parts = root.split(separator: "/").suffix(2)
                if !parts.isEmpty { return parts.joined(separator: "/") }
            }
        }
        return nil
    }

    /// Argument basenames, without the leading repeat of the executable name.
    ///
    /// Arguments are split on spaces first: npm rewrites its process title and
    /// lands its whole command line in a single argv slot, so "npm run dev
    /// --port 4325" arrives as one string rather than five.
    private static func meaningfulTokens(_ process: ProcessSample) -> [String] {
        var tokens = process.arguments
            .flatMap { $0.split(separator: " ").map(String.init) }
            .map { ($0 as NSString).lastPathComponent }
            .filter { !$0.isEmpty }
        if tokens.first == process.name { tokens.removeFirst() }
        return tokens
    }

    /// Arguments minus volatile parts, so identity survives a restart.
    static func signature(_ process: ProcessSample) -> String {
        process.arguments.dropFirst()
            .filter { !$0.hasPrefix("--port") && Int($0) == nil }
            .joined(separator: " ")
    }
}

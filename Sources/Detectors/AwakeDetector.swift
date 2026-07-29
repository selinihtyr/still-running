import Foundation
import ProcessKit

/// Something holding this Mac awake, named. The row exists because macOS will
/// not tell you: the battery is flat by morning, the fans ran in a closed bag,
/// and the only answer anywhere is a table of assertions no one reads.
public struct AwakeHolder: Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    /// The holder's own words for it: "Playing audio", "Video Wake Lock".
    public let reason: String
    public let heldFor: TimeInterval
    public let keepsScreenOn: Bool

    public var id: String { "\(pid):\(reason)" }

    public init(pid: Int32, name: String, reason: String,
                heldFor: TimeInterval, keepsScreenOn: Bool) {
        self.pid = pid
        self.name = name
        self.reason = reason
        self.heldFor = heldFor
        self.keepsScreenOn = keepsScreenOn
    }
}

/// Finds the processes preventing sleep. Only some of them are things to stop:
/// a `caffeinate` nobody released is exactly that, while an app playing audio
/// is a thing to be told about and nothing more.
public struct AwakeDetector: Detector {
    public let kind: FindingKind = .keepingAwake

    public init() {}

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        let tools = Self.holders(in: snapshot, settings: settings)
            .compactMap { holder -> (holder: AwakeHolder, process: ProcessSample)? in
                guard let process = snapshot.process(pid: holder.pid),
                      Self.isATool(process, in: snapshot) else { return nil }
                return (holder, process)
            }

        // This machine had two caffeinate processes at once, started the same
        // way. They are one thing to be told about and one thing to stop, and
        // two rows sharing an identity is a list that cannot be keyed.
        return Dictionary(grouping: tools, by: { Self.signature($0.process) })
            .map { signature, group -> Finding in
                let sorted = group.sorted { $0.holder.heldFor > $1.holder.heldFor }
                let oldest = sorted[0].holder
                let process = sorted[0].process

                return Finding(
                    identity: "awake:\(signature)",
                    kind: .keepingAwake,
                    // Terse on purpose. "keeping this Mac awake" is the true
                    // sentence and it truncated in the middle of the row on a
                    // real panel — "caffeinate · k…his Mac awake" — so the row
                    // says it the way the other kinds do, in two words next to
                    // an icon, and the explanation underneath says the rest.
                    title: "\(process.name) · \(oldest.keepsScreenOn ? "screen on" : "no sleep")",
                    detail: sorted.count == 1
                        ? oldest.reason
                        : "\(sorted.count) processes · \(oldest.reason)",
                    cpuPercent: sorted.reduce(0) { $0 + (history.cpuPercent(pid: $1.process.pid) ?? 0) },
                    memoryBytes: sorted.reduce(0) { $0 + $1.process.residentBytes },
                    // The assertion's age, not the process's: something that ran
                    // all day and only asked for wakefulness an hour ago has
                    // been costing you an hour.
                    age: oldest.heldFor,
                    // Longest-held first, so the one that has cost the most is
                    // the one the countdown names.
                    target: .processes(sorted.map(\.process.pid)),
                    // A whole night of it is a different thing from a long meeting.
                    severity: oldest.heldFor >= 8 * 3600 ? .urgent : .notable,
                    explanation: Self.explain(oldest, count: sorted.count),
                    details: Self.details(oldest, process: process),
                    command: process.arguments.joined(separator: " "))
            }
            // Grouping hands back an arbitrary order, so ties have to break on
            // something stable or two rows held for the same time swap places
            // every five seconds.
            .sorted { $0.age == $1.age ? $0.identity < $1.identity : $0.age > $1.age }
    }

    /// What makes two of these the same thing: the same binary started the same
    /// way. `caffeinate -d` holds the screen on and `caffeinate -i` does not,
    /// so they are never one row.
    static func signature(_ process: ProcessSample) -> String {
        "\(process.executablePath)|\(process.arguments.joined(separator: " "))"
    }

    /// Everything keeping the machine awake that its owner could do something
    /// about, newest promise last. One row per process: a browser holding both
    /// "Playing audio" and a video wake lock is one thing to know about.
    public static func holders(in snapshot: Snapshot, settings: Settings) -> [AwakeHolder] {
        let live = snapshot.assertions.filter { assertion in
            guard assertion.preventsSleep, !assertion.expiresOnItsOwn,
                  let process = snapshot.process(pid: assertion.pid),
                  isTheUsers(process, in: snapshot) else { return false }
            return snapshot.takenAt.timeIntervalSince(assertion.startedAt) >= settings.awakeMinimumHold
        }

        return Dictionary(grouping: live, by: \.pid).compactMap { pid, held -> AwakeHolder? in
            // The oldest promise is the one worth naming: it is the one that
            // has been costing something for longest.
            guard let oldest = held.min(by: { $0.startedAt < $1.startedAt }),
                  let process = snapshot.process(pid: pid) else { return nil }
            return AwakeHolder(
                pid: pid,
                name: process.name,
                reason: oldest.name.isEmpty ? oldest.type : oldest.name,
                heldFor: snapshot.takenAt.timeIntervalSince(oldest.startedAt),
                keepsScreenOn: held.contains(where: \.keepsScreenOn))
        }
        .sorted { $0.heldFor == $1.heldFor ? $0.pid < $1.pid : $0.heldFor > $1.heldFor }
    }

    /// `sharingd` holding "Handoff" and `powerd` holding "Prevent sleep while
    /// the display is on" are macOS explaining itself to itself. They run as
    /// the user and can never be stopped, and listing them would bury the one
    /// line that matters under three that never change.
    /// `/System/Applications` is the exception, and it matters: Music, TV and
    /// Podcasts live there, and music left playing overnight is one of the most
    /// ordinary ways there is to meet a flat battery in the morning. Skipping
    /// all of `/System` made that the one case that could never be named.
    static func isPartOfMacOS(_ process: ProcessSample) -> Bool {
        let path = process.executablePath
        if path.hasPrefix("/System/Applications/") { return false }
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/")
            || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/Library/Apple/")
    }

    static func isTheUsers(_ process: ProcessSample, in snapshot: Snapshot) -> Bool {
        process.uid == snapshot.currentUID
            && process.pid != snapshot.ownPID
            && !isPartOfMacOS(process)
    }

    /// A stop is only ever offered for a command line tool: no window, started
    /// by a person or a script, and holding an assertion is usually its entire
    /// job. Quitting an app because it is playing audio would be a worse bug
    /// than the one this row exists to fix, so apps are named and left alone —
    /// and so is anything launchd manages, because a button that stops
    /// something launchd starts again is a button that does nothing twice.
    static func isATool(_ process: ProcessSample, in snapshot: Snapshot) -> Bool {
        !process.executablePath.contains(".app/")
            && !snapshot.managedPIDs.contains(process.pid)
    }

    static func explain(_ holder: AwakeHolder, count: Int = 1) -> String {
        var sentences = [FindingKind.keepingAwake.plainDescription]
        sentences.append(holder.keepsScreenOn
            ? "It is holding the screen on, and macOS will not idle-sleep a Mac whose display is lit."
            : "It asked macOS not to idle-sleep, and nothing will release that but the process ending.")
        sentences.append("Held for \(Formatting.duration(holder.heldFor)), under the name “\(holder.reason)”.")
        if count > 1 {
            sentences.append("\(count) processes were started the same way and are counted as one.")
        }
        return sentences.joined(separator: " ")
    }

    static func details(_ holder: AwakeHolder, process: ProcessSample) -> String {
        """
        pid \(holder.pid) · \(process.executablePath)
        assertion: \(holder.reason)\(holder.keepsScreenOn ? " (holds the display on)" : "")
        held for: \(Formatting.duration(holder.heldFor))
        """
    }
}

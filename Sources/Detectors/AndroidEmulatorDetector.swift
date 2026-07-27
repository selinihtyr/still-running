import Foundation
import ProcessKit

/// Android emulators, which are QEMU under a friendlier name. They hold more
/// memory than almost anything else a developer leaves running, and nothing in
/// Android Studio mentions one that has been up since yesterday.
///
/// Reported alongside iOS simulators, because to the person looking at the
/// panel they are the same thing: a device that is switched on for no reason.
public struct AndroidEmulatorDetector: Detector {
    public let kind: FindingKind = .simulator

    public init() {}

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        let tree = ProcessTree(snapshot.processes)
        var claimed = Set<Int32>()

        return snapshot.processes
            .filter { $0.uid == snapshot.currentUID && Self.isEmulator($0) }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { seed -> Finding? in
                let group = tree.group(from: seed, claimed: &claimed)
                guard !group.isEmpty else { return nil }

                let age = snapshot.takenAt.timeIntervalSince(seed.startedAt)
                let memory = group.totalResidentBytes
                guard age >= settings.minimumAge else { return nil }

                let device = Self.deviceName(seed) ?? "Android emulator"
                let cpu = totalCPU(group, history)
                return Finding(
                    identity: "android:\(device)",
                    kind: .simulator,
                    title: device,
                    detail: "Android emulator",
                    cpuPercent: cpu,
                    memoryBytes: memory,
                    age: age,
                    target: .processes(group.pidsRootFirst),
                    severity: cpu >= 50 ? .urgent : .notable,
                    explanation: "An Android emulator that has been switched on for \(Formatting.duration(age)). It is a whole virtual phone: it holds \(Formatting.memory(memory)) and keeps running whether or not anything is looking at it. Quitting it is like closing the emulator window — the device's data stays on disk.",
                    revealPath: nil,
                    details: """
                        Android emulator: \(device)
                        \(group.count) processes, \(Formatting.memory(memory))
                        \(group.map { "pid \($0.pid) — \($0.executablePath)" }.joined(separator: "\n"))
                        """)
            }
    }

    static func isEmulator(_ process: ProcessSample) -> Bool {
        let name = process.name
        if name.hasPrefix("qemu-system-") { return true }
        if name == "emulator" || name == "emulator64-crash-service" { return true }
        return process.executablePath.contains("/Android/sdk/emulator/")
    }

    /// Emulators are launched with `-avd Pixel_7`, which is the name a person
    /// would recognise.
    static func deviceName(_ process: ProcessSample) -> String? {
        guard let index = process.arguments.firstIndex(of: "-avd"),
              index + 1 < process.arguments.count else { return nil }
        return process.arguments[index + 1].replacingOccurrences(of: "_", with: " ")
    }
}

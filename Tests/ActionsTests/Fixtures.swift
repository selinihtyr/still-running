import Foundation
@testable import Detectors
import ProcessKit

/// Reproduces the situation actually observed on the machine this app was
/// written for: a Chrome tree on the user's own profile, a second Chrome tree
/// on /tmp/claude-cdp-prof left behind by a tool run, and system processes.
enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_785_000_000)
    static let chromeFramework =
        "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/150.0.7871.186/Helpers"

    static func process(pid: Int32, ppid: Int32 = 1, path: String, args: [String],
                        ageHours: Double = 0.1, uid: UInt32 = 501, tty: Bool = false,
                        cpuNanos: UInt64 = 0, rssMB: UInt64 = 50) -> ProcessSample {
        ProcessSample(
            pid: pid, ppid: ppid, uid: uid, executablePath: path, arguments: args,
            startedAt: now.addingTimeInterval(-ageHours * 3600), hasControllingTTY: tty,
            cpuTimeNanos: cpuNanos, residentBytes: rssMB * 1_048_576)
    }

    /// Chrome's own tabs: a browser process with no --user-data-dir, plus helpers.
    static func defaultChrome() -> [ProcessSample] {
        [
            process(pid: 14914, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                    args: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"],
                    ageHours: 20, rssMB: 200),
            process(pid: 14920, ppid: 14914,
                    path: "\(chromeFramework)/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)",
                    args: ["Google Chrome Helper (GPU)", "--type=gpu-process"],
                    ageHours: 20, rssMB: 300),
            process(pid: 15205, ppid: 14914,
                    path: "\(chromeFramework)/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                    args: ["Google Chrome Helper (Renderer)", "--type=renderer"],
                    ageHours: 20, rssMB: 400),
        ]
    }

    /// An automation profile left behind by a tool run.
    static func automationChrome(ageHours: Double = 18.7) -> [ProcessSample] {
        [
            process(pid: 23947, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                    args: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                           "--user-data-dir=/tmp/claude-cdp-prof", "--remote-debugging-port=9222"],
                    ageHours: ageHours, rssMB: 200),
            process(pid: 23953, ppid: 23947,
                    path: "\(chromeFramework)/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)",
                    args: ["Google Chrome Helper (GPU)", "--type=gpu-process",
                           "--user-data-dir=/tmp/claude-cdp-prof"],
                    ageHours: ageHours, rssMB: 250),
            process(pid: 35770, ppid: 23947,
                    path: "\(chromeFramework)/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                    args: ["Google Chrome Helper (Renderer)", "--type=renderer",
                           "--user-data-dir=/tmp/claude-cdp-prof"],
                    ageHours: ageHours, rssMB: 300),
            // Observed on a real machine: Chrome omits --user-data-dir from
            // some helper types. Only the tree says who this belongs to.
            process(pid: 35771, ppid: 23947,
                    path: "\(chromeFramework)/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper",
                    args: ["Google Chrome Helper", "--type=utility"],
                    ageHours: ageHours, rssMB: 100),
        ]
    }

    static func system() -> [ProcessSample] {
        [
            process(pid: 1, path: "/sbin/launchd", args: ["/sbin/launchd"], ageHours: 52, uid: 0),
            process(pid: 164,
                    path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer",
                    args: ["WindowServer", "-daemon"], ageHours: 52, uid: 88),
            process(pid: 418, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                    args: ["/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"], ageHours: 52),
        ]
    }

    static func snapshot(processes: [ProcessSample], containers: [ContainerSample] = [],
                         simulators: [SimulatorSample] = [], at: Date = now) -> Snapshot {
        Snapshot(takenAt: at, processes: processes, containers: containers,
                 simulators: simulators, currentUID: 501, ownPID: 999)
    }

    /// A history whose samples end at `now`, in which every process burned
    /// `cpuPercent` of a core throughout, so rates and sustained queries are real.
    static func history(_ processes: [ProcessSample], cpuPercent: Double,
                        apart: TimeInterval = 60, samples: Int = 6) -> History {
        var history = History()
        let span = Double(samples - 1) * apart
        for step in 0..<samples {
            let elapsed = Double(step) * apart
            let burned = UInt64(cpuPercent / 100 * elapsed * 1_000_000_000)
            let advanced = processes.map {
                ProcessSample(pid: $0.pid, ppid: $0.ppid, uid: $0.uid,
                              executablePath: $0.executablePath, arguments: $0.arguments,
                              startedAt: $0.startedAt, hasControllingTTY: $0.hasControllingTTY,
                              cpuTimeNanos: $0.cpuTimeNanos + burned, residentBytes: $0.residentBytes)
            }
            history.record(snapshot(processes: advanced, at: now.addingTimeInterval(elapsed - span)))
        }
        return history
    }
}

import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func flagsAReparentedProcessWithNoTerminal() {
    // The classic leftover: its terminal is gone, launchd adopted it.
    let processes = [Fixtures.process(
        pid: 7100, ppid: 1, path: "/opt/homebrew/bin/ffmpeg",
        args: ["ffmpeg", "-i", "in.mov", "out.mp4"], ageHours: 3, tty: false, rssMB: 200)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 70), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].kind == .orphan)
    #expect(findings[0].severity == .urgent)
}

@Test func ignoresApplicationBundlesAdoptedByLaunchd() {
    // Every running .app has ppid 1. None of them are orphans.
    let processes = Fixtures.defaultChrome()
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 80), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresProcessesThatStillHaveATerminal() {
    let processes = [Fixtures.process(
        pid: 7200, ppid: 1, path: "/opt/homebrew/bin/ffmpeg",
        args: ["ffmpeg"], ageHours: 3, tty: true)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 70), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresSystemAgentsUnderLaunchd() {
    let processes = Fixtures.system()
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 5), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresProcessesInSystemDirectories() {
    let processes = [Fixtures.process(
        pid: 7300, ppid: 1, path: "/usr/libexec/trustd", args: ["trustd"], ageHours: 40)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresAppleXPCServicesUnderLibraryDeveloper() {
    // Observed on a real machine: CoreSimulator and CoreDevice ship XPC
    // services that launchd owns forever. They are not leftovers, and they
    // live in .xpc bundles rather than .app bundles.
    let processes = [
        Fixtures.process(
            pid: 1415,
            path: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc/Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService",
            args: ["com.apple.CoreSimulator.CoreSimulatorService"], ageHours: 52),
        Fixtures.process(
            pid: 1427,
            path: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/SimulatorTrampoline.xpc/Contents/MacOS/SimulatorTrampoline",
            args: ["SimulatorTrampoline"], ageHours: 52),
    ]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresAppExtensionsAndFrameworkHelpers() {
    let processes = [
        Fixtures.process(pid: 9100,
                         path: "/Applications/Some.app/Contents/PlugIns/Helper.appex/Contents/MacOS/Helper",
                         args: ["Helper"], ageHours: 10),
        Fixtures.process(pid: 9200,
                         path: "/Library/Frameworks/Thing.framework/Versions/A/Helper",
                         args: ["Helper"], ageHours: 10),
    ]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresShellsAndCoreBinariesLeftInBin() {
    // Closing a terminal leaves its shell reparented to launchd. Nobody wants
    // to be told about that, and /bin holds nothing but Apple's core tools.
    let processes = [
        Fixtures.process(pid: 9500, path: "/bin/zsh", args: ["-zsh"], ageHours: 8),
        Fixtures.process(pid: 9600, path: "/bin/sleep", args: ["sleep", "9999"], ageHours: 8),
    ]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func aShellPinningACoreIsNotACoreBinary() {
    // Found live, and the reason this exists: two `/bin/sh -c 'while :; do :;
    // done'` left behind by an interrupted test run, reparented to launchd,
    // burning a core each for eight minutes — and nothing in the app said a
    // word, because /bin is skipped. Skipping it is right for the shell a
    // closed terminal leaves behind, which is asleep. It is exactly wrong for
    // the one that is eating the machine.
    let runaway = Fixtures.process(pid: 23070, ppid: 1, path: "/bin/sh",
                                   args: ["/bin/sh", "-c", "while :; do :; done"], ageHours: 0.13)
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: [runaway]),
        history: Fixtures.history([runaway], cpuPercent: 99), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].title == "sh")
    #expect(findings[0].severity == .urgent)
}

@Test func aRunawayIsVisibleBeforeItIsMinutesOld() {
    // Observed on the machine, after the first attempt at this shipped: an
    // orphaned /bin/sh at 97% for three and a half minutes still did not
    // appear. The gate asked for sustained load over the long window, and that
    // answer is nil until the process has existed for the whole of it — one
    // interval reaching back past its birth is enough. So the first minutes of
    // a runaway were exactly the minutes it stayed hidden, which is when
    // somebody is staring at a hot laptop wondering what is going on.
    let quiet = Fixtures.process(pid: 900, ppid: 1, path: "/usr/bin/python3",
                                 args: ["python3", "idle.py"], ageHours: 5)
    func burning(_ seconds: Double) -> ProcessSample {
        ProcessSample(pid: 23070, ppid: 1, uid: 501, executablePath: "/bin/sh",
                      arguments: ["/bin/sh", "-c", "while :; do :; done"],
                      startedAt: Fixtures.now.addingTimeInterval(-130), hasControllingTTY: false,
                      cpuTimeNanos: UInt64(seconds * 1_000_000_000), residentBytes: 1_048_576)
    }

    var history = History()
    // Two samples from before it existed, then three with it pinning a core.
    history.record(Fixtures.snapshot(processes: [quiet], at: Fixtures.now.addingTimeInterval(-240)))
    history.record(Fixtures.snapshot(processes: [quiet], at: Fixtures.now.addingTimeInterval(-180)))
    history.record(Fixtures.snapshot(processes: [quiet, burning(0)], at: Fixtures.now.addingTimeInterval(-120)))
    history.record(Fixtures.snapshot(processes: [quiet, burning(60)], at: Fixtures.now.addingTimeInterval(-60)))
    let latest = Fixtures.snapshot(processes: [quiet, burning(120)], at: Fixtures.now)
    history.record(latest)

    let findings = OrphanDetector().findings(in: latest, history: history, settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].title == "sh")
    // The idle one in the same directory is still nobody's business.
    #expect(!findings.contains { $0.title == "python3" })
}

@Test func macOSsOwnBusyHelpersAreStillNotOrphans() {
    // The exception is only for the two directories that hold a person's own
    // tools. Spotlight's workers run as you, hang off launchd and are busy by
    // design; calling one an orphan would be a false alarm every time the
    // machine indexes anything.
    let worker = Fixtures.process(
        pid: 9700, ppid: 1,
        path: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mdworker_shared",
        args: ["mdworker_shared"], ageHours: 1)
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: [worker]),
        history: Fixtures.history([worker], cpuPercent: 90), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresServicesLaunchdManagesOnPurpose() {
    // A LaunchAgent or brew service is indistinguishable from an orphan in the
    // process table: parent 1, no terminal. Only launchd knows the difference.
    let process = Fixtures.process(
        pid: 512, path: "/Users/x/.rvmp/dist/darwin-arm64/bin/rvmp", args: ["rvmp"], ageHours: 53)
    let snapshot = Snapshot(takenAt: Fixtures.now, processes: [process], containers: [],
                            simulators: [], currentUID: 501, ownPID: 999, managedPIDs: [512])

    let findings = OrphanDetector().findings(
        in: snapshot, history: Fixtures.history([process], cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func stillFlagsAnUnmanagedProcessWhenOtherJobsAreManaged() {
    let process = Fixtures.process(
        pid: 9400, path: "/Users/x/bin/leftover", args: ["leftover"], ageHours: 6)
    let snapshot = Snapshot(takenAt: Fixtures.now, processes: [process], containers: [],
                            simulators: [], currentUID: 501, ownPID: 999, managedPIDs: [512, 504])

    let findings = OrphanDetector().findings(
        in: snapshot, history: Fixtures.history([process], cpuPercent: 0), settings: Settings())

    #expect(findings.count == 1)
}

@Test func stillFlagsAPlainBinaryInAUserDirectory() {
    let processes = [Fixtures.process(
        pid: 9300, path: "/Users/x/.bun/bin/bun", args: ["bun", "run", "worker.ts"], ageHours: 6)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.count == 1)
}

@Test func leavesAutomationBrowsersToTheBrowserDetector() {
    let processes = Fixtures.automationChrome()
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 40), settings: Settings())

    #expect(findings.isEmpty)
}

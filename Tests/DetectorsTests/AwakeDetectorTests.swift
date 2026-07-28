import Testing
import Foundation
@testable import Detectors
import ProcessKit

/// The situations these cover were all read off a real machine: two
/// `caffeinate -t 300` processes a tool had wrapped a command in, `sharingd`
/// holding "Handoff" forever as the user, `powerd` holding one because the
/// display was on, and Chrome holding "Playing audio" and a video wake lock at
/// the same time.
private func caffeinate(pid: Int32 = 4242, args: [String] = ["caffeinate", "-i"]) -> ProcessSample {
    Fixtures.process(pid: pid, path: "/usr/bin/caffeinate", args: args, ageHours: 4)
}

private let settings = Settings()

@Test func aForgottenCaffeinateIsSomethingToStop() {
    let tool = caffeinate()
    let snapshot = Fixtures.snapshot(processes: [tool],
                                     assertions: [Fixtures.assertion(pid: tool.pid, heldHours: 3)])

    let findings = AwakeDetector().findings(in: snapshot, history: History(), settings: settings)

    #expect(findings.count == 1)
    #expect(findings[0].kind == .keepingAwake)
    #expect(findings[0].target == .processes([tool.pid]))
    #expect(findings[0].title.contains("keeping this Mac awake"))
    #expect(findings[0].age == 3 * 3600)
}

@Test func twoOfTheSameToolAreOneRow() {
    // This machine had two caffeinate processes at once. They are one thing to
    // be told about and one thing to stop — and two rows carrying the same
    // identity is a list SwiftUI cannot key and exclusions cannot match.
    let first = caffeinate(pid: 4242)
    let second = caffeinate(pid: 4243)
    let snapshot = Fixtures.snapshot(processes: [first, second], assertions: [
        Fixtures.assertion(pid: 4242, heldHours: 3),
        Fixtures.assertion(pid: 4243, heldHours: 5),
    ])

    let findings = AwakeDetector().findings(in: snapshot, history: History(), settings: settings)

    #expect(findings.count == 1)
    #expect(Set(findings.map(\.identity)).count == findings.count)
    #expect(findings[0].target == .processes([4243, 4242]))   // the older promise first
    #expect(findings[0].age == 5 * 3600)
    #expect(findings[0].detail.contains("2 processes"))
}

@Test func toolsStartedDifferentlyStayApart() {
    // `caffeinate -d` holds the screen on and `caffeinate -i` does not. Rolling
    // them together would put one explanation on two different situations.
    let display = caffeinate(pid: 4242, args: ["caffeinate", "-d"])
    let idle = caffeinate(pid: 4243, args: ["caffeinate", "-i"])
    let snapshot = Fixtures.snapshot(processes: [display, idle], assertions: [
        Fixtures.assertion(pid: 4242, type: "PreventUserIdleDisplaySleep", heldHours: 3),
        Fixtures.assertion(pid: 4243, heldHours: 3),
    ])

    let findings = AwakeDetector().findings(in: snapshot, history: History(), settings: settings)
    #expect(findings.count == 2)
    #expect(Set(findings.map(\.identity)).count == 2)
}

@Test func anAssertionThatExpiresOnItsOwnIsNobodysMistake() {
    // `caffeinate -t 300` is how tools wrap a command that must not be
    // interrupted. It releases itself, so nobody forgot it.
    let tool = caffeinate(args: ["caffeinate", "-i", "-t", "300"])
    let snapshot = Fixtures.snapshot(
        processes: [tool],
        assertions: [Fixtures.assertion(pid: tool.pid, heldHours: 3, timeoutSeconds: 300)])

    #expect(AwakeDetector().findings(in: snapshot, history: History(), settings: settings).isEmpty)
    #expect(AwakeDetector.holders(in: snapshot, settings: settings).isEmpty)
}

@Test func macOSHoldingItsOwnAssertionsIsNotAFinding() {
    // Both of these run as the user and hold an assertion that never expires.
    // Neither can be stopped, and listing them buries the row that matters.
    let sharingd = Fixtures.process(pid: 443, path: "/usr/libexec/sharingd",
                                    args: ["/usr/libexec/sharingd"], ageHours: 11)
    let powerd = Fixtures.process(pid: 106, path: "/System/Library/CoreServices/powerd.bundle/powerd",
                                  args: ["powerd"], ageHours: 11)
    let snapshot = Fixtures.snapshot(processes: [sharingd, powerd], assertions: [
        Fixtures.assertion(pid: 443, name: "Handoff", heldHours: 10),
        Fixtures.assertion(pid: 106, name: "Powerd - Prevent sleep while display is on", heldHours: 10),
    ])

    #expect(AwakeDetector.holders(in: snapshot, settings: settings).isEmpty)
}

@Test func anAppIsNamedButNeverOfferedUp() {
    // Chrome playing audio is worth knowing about. Quitting someone's browser
    // because of it would be a worse bug than the one this row exists to fix.
    let chrome = Fixtures.defaultChrome()
    let snapshot = Fixtures.snapshot(processes: chrome, assertions: [
        Fixtures.assertion(pid: chrome[0].pid, type: "NoIdleSleepAssertion",
                           name: "Playing audio", heldHours: 5),
    ])

    #expect(AwakeDetector().findings(in: snapshot, history: History(), settings: settings).isEmpty)

    let holders = AwakeDetector.holders(in: snapshot, settings: settings)
    #expect(holders.count == 1)
    #expect(holders[0].reason == "Playing audio")
    #expect(holders[0].name == "Google Chrome")
}

@Test func aPromiseMadeAMomentAgoIsNotAHabit() {
    // Being on a video call is not a thing to be told about.
    let tool = caffeinate()
    let snapshot = Fixtures.snapshot(processes: [tool],
                                     assertions: [Fixtures.assertion(pid: tool.pid, heldHours: 0.2)])

    #expect(AwakeDetector.holders(in: snapshot, settings: settings).isEmpty)
}

@Test func oneProcessHoldingTwoPromisesIsOneRow() {
    // Chrome holds "Playing audio" and "Video Wake Lock" together. The screen
    // one is the reason the display never dimmed, and both are one thing.
    let chrome = Fixtures.defaultChrome()
    let snapshot = Fixtures.snapshot(processes: chrome, assertions: [
        Fixtures.assertion(pid: chrome[0].pid, type: "NoIdleSleepAssertion",
                           name: "Playing audio", heldHours: 2),
        Fixtures.assertion(pid: chrome[0].pid, type: "NoDisplaySleepAssertion",
                           name: "Video Wake Lock", heldHours: 5),
    ])

    let holders = AwakeDetector.holders(in: snapshot, settings: settings)
    #expect(holders.count == 1)
    #expect(holders[0].keepsScreenOn)
    #expect(holders[0].reason == "Video Wake Lock")   // the older promise
    #expect(holders[0].heldFor == 5 * 3600)
}

@Test func somethingLaunchdManagesIsNamedNotOffered() {
    // launchd restarts what it manages, so a stop button on one is a button
    // that does nothing twice. Knowing it is holding the machine awake is
    // still worth a line.
    let agent = Fixtures.process(pid: 7788, path: "/opt/homebrew/opt/syncthing/bin/syncthing",
                                 args: ["syncthing"], ageHours: 9)
    let snapshot = Snapshot(takenAt: Fixtures.now, processes: [agent], containers: [],
                            simulators: [], currentUID: 501, ownPID: 999,
                            managedPIDs: [7788],
                            assertions: [Fixtures.assertion(pid: 7788, heldHours: 8)])

    #expect(AwakeDetector().findings(in: snapshot, history: History(), settings: settings).isEmpty)
    #expect(AwakeDetector.holders(in: snapshot, settings: settings).count == 1)
}

@Test func dismissingARowDoesNotMoveItToTheListBelow() {
    // "Never list this again" has to mean it. Skipping the finding without
    // skipping the name below would move the row down the panel instead of
    // taking it away, which reads as the button not working.
    let tool = caffeinate()
    let snapshot = Fixtures.snapshot(processes: [tool],
                                     assertions: [Fixtures.assertion(pid: tool.pid, heldHours: 3)])
    let identity = AwakeDetector().findings(in: snapshot, history: History(),
                                            settings: settings)[0].identity

    let result = DetectorEngine().evaluate(snapshot: snapshot, history: History(),
                                           settings: settings, excluded: [identity])

    #expect(result.findings.isEmpty)
    #expect(result.keepingAwake.isEmpty)
}

@Test func aWholeNightOfItIsUrgent() {
    let tool = caffeinate()
    let snapshot = Fixtures.snapshot(processes: [tool],
                                     assertions: [Fixtures.assertion(pid: tool.pid, heldHours: 9)])

    let findings = AwakeDetector().findings(in: snapshot, history: History(), settings: settings)
    #expect(findings[0].severity == .urgent)
}

@Test func somethingAlreadyListedIsNotNamedTwice() {
    // A dev server holding a wake lock is already a row with a stop button.
    // Repeating it below reads as two problems where there is one.
    let node = Fixtures.process(pid: 5150, path: "/opt/homebrew/bin/node",
                                args: ["node", "/Users/x/app/server.js"], ageHours: 6)
    let snapshot = Fixtures.snapshot(processes: [node],
                                     assertions: [Fixtures.assertion(pid: 5150, heldHours: 6)])

    let result = DetectorEngine().evaluate(snapshot: snapshot,
                                           history: Fixtures.history([node], cpuPercent: 0),
                                           settings: settings, excluded: [])

    #expect(result.findings.contains { $0.kind == .devServer })
    #expect(result.keepingAwake.isEmpty)
}

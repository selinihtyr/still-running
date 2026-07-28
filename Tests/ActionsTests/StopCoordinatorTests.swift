import Testing
import Foundation
import Darwin
@testable import Actions
import Detectors
import ProcessKit

private struct SentSignal: Sendable, Equatable {
    let pid: Int32
    let signal: Int32
}

private final class RecordingSignaller: ProcessSignalling, Sendable {
    private let storage = Locked<[SentSignal]>([])
    private let alive: Bool

    init(aliveAfterSignal: Bool = false) { self.alive = aliveAfterSignal }

    var sent: [SentSignal] { storage.withLock { $0 } }
    func send(_ signal: Int32, to pid: Int32) throws {
        storage.withLock { $0.append(SentSignal(pid: pid, signal: signal)) }
    }
    func isAlive(_ pid: Int32) -> Bool { alive }
}

private final class RecordingContainers: ContainerStopping, Sendable {
    private let storage = Locked<[String]>([])
    var stopped: [String] { storage.withLock { $0 } }
    func stop(id: String) async throws { storage.withLock { $0.append(id) } }
}

private final class RecordingSimulators: SimulatorStopping, Sendable {
    private let storage = Locked<[String]>([])
    var shutdown: [String] { storage.withLock { $0 } }
    func shutdown(udid: String) async throws { storage.withLock { $0.append(udid) } }
}

private func makeCoordinator(aliveAfterSignal: Bool = false)
    -> (StopCoordinator, RecordingSignaller, RecordingContainers, RecordingSimulators) {
    let signaller = RecordingSignaller(aliveAfterSignal: aliveAfterSignal)
    let containers = RecordingContainers()
    let simulators = RecordingSimulators()
    let coordinator = StopCoordinator(signaller: signaller, containers: containers,
                                      simulators: simulators, gracePeriod: 0)
    return (coordinator, signaller, containers, simulators)
}

private func finding(_ target: StopTarget, kind: FindingKind = .devServer) -> Finding {
    Finding(identity: "t", kind: kind, title: "t", detail: "d", cpuPercent: 1,
            memoryBytes: 0, age: 10_000, target: target, severity: .notable)
}

@Test func sendsSIGTERMToTheRootFirst() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    let outcome = await coordinator.stop(
        finding(.processes([23947, 23953, 35770])),
        in: Fixtures.snapshot(processes: Fixtures.automationChrome()))

    #expect(outcome == .stopped)
    #expect(signaller.sent.first?.pid == 23947)
    #expect(signaller.sent.allSatisfy { $0.signal == SIGTERM })
    #expect(signaller.sent.count == 3)
}

@Test func neverSendsSIGKILLOnAPlainStop() async {
    let (coordinator, signaller, _, _) = makeCoordinator(aliveAfterSignal: true)
    let outcome = await coordinator.stop(
        finding(.processes([23947])), in: Fixtures.snapshot(processes: Fixtures.automationChrome()))

    #expect(outcome == .stillRunning)
    #expect(!signaller.sent.contains { $0.signal == SIGKILL })
}

@Test func forceStopSendsSIGKILL() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    _ = await coordinator.forceStop(
        finding(.processes([23947])), in: Fixtures.snapshot(processes: Fixtures.automationChrome()))

    #expect(signaller.sent.contains { $0.signal == SIGKILL })
}

@Test func refusesToSignalAProtectedProcess() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    let outcome = await coordinator.stop(
        finding(.processes([164])), in: Fixtures.snapshot(processes: Fixtures.system()))

    #expect(outcome == .refused(reason: "critical to the session"))
    #expect(signaller.sent.isEmpty)
}

@Test func forceStopAlsoRefusesProtectedProcesses() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    let outcome = await coordinator.forceStop(
        finding(.processes([164])), in: Fixtures.snapshot(processes: Fixtures.system()))

    #expect(outcome == .refused(reason: "critical to the session"))
    #expect(signaller.sent.isEmpty)
}

@Test func refusesTheUsersBrowserEvenWhenAskedDirectly() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    let outcome = await coordinator.stop(
        finding(.processes([14914]), kind: .isolatedBrowser),
        in: Fixtures.snapshot(processes: Fixtures.defaultChrome()))

    #expect(outcome == .refused(reason: "your browser, with your tabs"))
    #expect(signaller.sent.isEmpty)
}

@Test func routesContainerTargetsToDocker() async {
    let (coordinator, signaller, containers, _) = makeCoordinator()
    let outcome = await coordinator.stop(finding(.container("c1"), kind: .container),
                                         in: Fixtures.snapshot(processes: []))

    #expect(outcome == .stopped)
    #expect(containers.stopped == ["c1"])
    #expect(signaller.sent.isEmpty)
}

@Test func routesSimulatorTargetsToSimctl() async {
    let (coordinator, _, _, simulators) = makeCoordinator()
    let outcome = await coordinator.stop(finding(.simulator("A1B2"), kind: .simulator),
                                         in: Fixtures.snapshot(processes: []))

    #expect(outcome == .stopped)
    #expect(simulators.shutdown == ["A1B2"])
}

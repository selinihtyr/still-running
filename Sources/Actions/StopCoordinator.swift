import Darwin
import Foundation
import Detectors
import ProcessKit

/// Routes a finding to the right mechanism and enforces the guard on the way.
/// Every stop in the app goes through here; there is no other path to a signal.
public struct StopCoordinator: Sendable {
    private let signaller: any ProcessSignalling
    private let containers: any ContainerStopping
    private let simulators: any SimulatorStopping
    private let guardian = SafetyGuard()
    private let gracePeriod: TimeInterval

    public init(signaller: any ProcessSignalling = SignalStopper(),
                containers: any ContainerStopping = ContainerStopper(),
                simulators: any SimulatorStopping = SimulatorStopper(),
                gracePeriod: TimeInterval = 5) {
        self.signaller = signaller
        self.containers = containers
        self.simulators = simulators
        self.gracePeriod = gracePeriod
    }

    /// Graceful. Never escalates on its own.
    public func stop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome {
        await perform(finding, in: snapshot, signal: SIGTERM)
    }

    /// Only reachable from an explicit second click in the UI.
    public func forceStop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome {
        await perform(finding, in: snapshot, signal: SIGKILL)
    }

    private func perform(_ finding: Finding, in snapshot: Snapshot, signal: Int32) async -> StopOutcome {
        do {
            try guardian.vet(finding, in: snapshot)
        } catch SafetyError.protectedProcess(_, let reason) {
            return .refused(reason: reason)
        } catch {
            return .refused(reason: "unknown process")
        }

        do {
            switch finding.target {
            case .processes(let pids):
                for pid in pids { try signaller.send(signal, to: pid) }
                if gracePeriod > 0 { try? await Task.sleep(for: .seconds(gracePeriod)) }
                return pids.contains(where: { signaller.isAlive($0) }) ? .stillRunning : .stopped
            case .container(let id):
                try await containers.stop(id: id)
                return .stopped
            case .simulator(let udid):
                try await simulators.shutdown(udid: udid)
                return .stopped
            }
        } catch {
            return .failed("\(error)")
        }
    }
}

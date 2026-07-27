import Foundation

public enum StopOutcome: Sendable, Equatable {
    case stopped
    /// Signalled, but still alive after the grace period. The UI offers force quit.
    case stillRunning
    case refused(reason: String)
    case failed(String)
}

public enum StopError: Error, Equatable {
    case signalFailed(pid: Int32, code: Int32)
    case noDockerDaemon
}

public protocol ProcessSignalling: Sendable {
    func send(_ signal: Int32, to pid: Int32) throws
    func isAlive(_ pid: Int32) -> Bool
}

public protocol ContainerStopping: Sendable {
    func stop(id: String) async throws
}

public protocol SimulatorStopping: Sendable {
    func shutdown(udid: String) async throws
}

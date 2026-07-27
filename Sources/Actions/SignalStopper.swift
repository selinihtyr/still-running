import Darwin
import Foundation

public struct SignalStopper: ProcessSignalling {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) throws {
        // ESRCH means it exited between the snapshot and the signal, which is
        // exactly the outcome we wanted.
        guard kill(pid, signal) == 0 || errno == ESRCH else {
            throw StopError.signalFailed(pid: pid, code: errno)
        }
    }

    /// Signal 0 tests for existence without delivering anything.
    public func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}

import Foundation
import SimulatorSource

public struct SimulatorStopper: SimulatorStopping {
    private let control: any SimulatorControl

    public init(control: any SimulatorControl = SimctlSource()) { self.control = control }

    public func shutdown(udid: String) async throws {
        try await control.shutdown(udid: udid)
    }
}

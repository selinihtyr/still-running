import Foundation

/// How hard the machine is being pushed, in the terms macOS itself uses.
///
/// A temperature in degrees needs private sensor APIs and means little without
/// context. `thermalState` is the reading macOS acts on — it is what makes the
/// fans spin and the clocks drop — so it is what the panel reports.
public enum Thermal: Sendable, Equatable {
    case nominal, fair, serious, critical

    public static var current: Thermal {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    public var label: String {
        switch self {
        case .nominal: "cool"
        case .fair: "warm"
        case .serious: "hot"
        case .critical: "throttling"
        }
    }

    public var symbol: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious: "thermometer.high"
        case .critical: "thermometer.sun.fill"
        }
    }

    /// Nothing to say when the machine is comfortable.
    public var isWorthShowing: Bool { self != .nominal }
}

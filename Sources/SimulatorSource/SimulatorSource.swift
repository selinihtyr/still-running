import Foundation

public struct BootedSimulator: Sendable, Equatable {
    public let udid: String
    public let name: String
    public let runtime: String

    public init(udid: String, name: String, runtime: String) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
    }
}

public protocol SimulatorControl: Sendable {
    func booted() async throws -> [BootedSimulator]
    func shutdown(udid: String) async throws
    func boot(udid: String) async throws
}

/// simctl is the only supported interface to CoreSimulator, so this is the one
/// place the app shells out.
public struct SimctlSource: SimulatorControl {
    private let xcrunPath: String

    public init(xcrunPath: String = "/usr/bin/xcrun") { self.xcrunPath = xcrunPath }

    public func booted() async throws -> [BootedSimulator] {
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else { return [] }
        let output = try run(["simctl", "list", "devices", "booted", "-j"])
        return (try? Self.decodeBooted(output)) ?? []
    }

    public func shutdown(udid: String) async throws {
        _ = try run(["simctl", "shutdown", udid])
    }

    /// Boots a device again, so shutting one down can be taken back.
    public func boot(udid: String) async throws {
        _ = try run(["simctl", "boot", udid])
    }

    static func decodeBooted(_ data: Data) throws -> [BootedSimulator] {
        struct Payload: Decodable {
            struct Device: Decodable { let udid: String; let name: String; let state: String }
            let devices: [String: [Device]]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.devices.flatMap { runtime, devices in
            devices
                .filter { $0.state == "Booted" }
                .map { BootedSimulator(udid: $0.udid, name: $0.name,
                                       runtime: Self.friendlyRuntime(runtime)) }
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> "iOS 26.5"
    static func friendlyRuntime(_ identifier: String) -> String {
        let tail = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = tail.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return tail }
        return parts[0] + " " + parts.dropFirst().joined(separator: ".")
    }

    private func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

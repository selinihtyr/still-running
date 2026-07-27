import Foundation

/// launchd both *adopts* orphans and *manages* real services. A managed job —
/// a LaunchAgent, a brew service, anything with a plist — looks exactly like an
/// orphan from the process table: parent 1, no controlling terminal. Asking
/// launchd which pids it manages is the only way to tell them apart.
public protocol LaunchdJobSource: Sendable {
    func managedPIDs() -> Set<Int32>
}

public struct LaunchctlJobs: LaunchdJobSource {
    private let launchctlPath: String

    public init(launchctlPath: String = "/bin/launchctl") { self.launchctlPath = launchctlPath }

    public func managedPIDs() -> Set<Int32> {
        guard FileManager.default.isExecutableFile(atPath: launchctlPath),
              let output = run() else { return [] }
        return Self.parse(output)
    }

    /// `launchctl list` prints "PID\tStatus\tLabel", with "-" for jobs that are
    /// registered but not currently running.
    static func parse(_ output: String) -> Set<Int32> {
        var pids: Set<Int32> = []
        for line in output.split(separator: "\n").dropFirst() {
            guard let field = line.split(separator: "\t").first, let pid = Int32(field) else { continue }
            pids.insert(pid)
        }
        return pids
    }

    private func run() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchctlPath)
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

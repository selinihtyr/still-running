import Testing
import Foundation
@testable import ProcessKit

@Test func snapshotRoundTripsThroughJSON() throws {
    let sample = ProcessSample(
        pid: 42, ppid: 1, uid: 501,
        executablePath: "/usr/bin/thing",
        arguments: ["thing", "--flag"],
        startedAt: Date(timeIntervalSince1970: 1_000_000),
        hasControllingTTY: false,
        cpuTimeNanos: 1_500_000_000,
        residentBytes: 64 * 1_048_576
    )
    let snapshot = Snapshot(
        takenAt: Date(timeIntervalSince1970: 1_000_100),
        processes: [sample], containers: [], simulators: [],
        currentUID: 501, ownPID: 7
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(Snapshot.self, from: data)

    #expect(decoded.processes.count == 1)
    #expect(decoded.processes[0].arguments == ["thing", "--flag"])
    #expect(decoded.processes[0].residentBytes == 64 * 1_048_576)
    #expect(decoded.ownPID == 7)
}

@Test func processNameIsTheLastPathComponent() {
    let sample = ProcessSample(
        pid: 1, ppid: 0, uid: 501,
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        arguments: [], startedAt: Date(), hasControllingTTY: false,
        cpuTimeNanos: 0, residentBytes: 0)

    #expect(sample.name == "Google Chrome")
}

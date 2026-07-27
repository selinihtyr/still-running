import Testing
import Foundation
@testable import StillRunningCore
import Detectors
import ProcessKit

/// Runs the whole pipeline against this machine and prints what it found.
/// It asserts only invariants that must hold anywhere, so it is safe in CI.
@Test func detectsSomethingSensibleOnTheRealMachine() async {
    let source = LiveSnapshotSource()
    var history = History()
    history.record(await source.sample())
    try? await Task.sleep(for: .seconds(2))
    let latest = await source.sample()
    history.record(latest)

    let result = DetectorEngine().evaluate(in: latest, history: history)

    print("--- findings ---")
    for finding in result.findings {
        print("  [\(finding.kind.rawValue)] \(finding.title) | \(finding.detail) | \(Int(finding.cpuPercent))% | \(finding.target)")
        if case .processes(let pids) = finding.target {
            for pid in pids { print("        pid \(pid): \(latest.process(pid: pid)?.executablePath ?? "?") \((latest.process(pid: pid)?.arguments ?? []).joined(separator: " ").prefix(120))") }
        }
    }
    print("--- also hot ---")
    for hot in result.alsoHot { print("  \(hot.name) \(Int(hot.cpuPercent))%") }

    // Whatever it found, nothing protected may ever be a target.
    for finding in result.findings {
        guard case .processes(let pids) = finding.target else { continue }
        for pid in pids {
            let process = latest.process(pid: pid)
            #expect(process != nil)
            #expect(process!.uid == latest.currentUID)
            #expect(pid >= 100)
        }
    }
}

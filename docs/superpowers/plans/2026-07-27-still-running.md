# Still Running Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that finds processes, containers, and simulators the user forgot were running, and stops them in one click.

**Architecture:** A Swift package with focused library targets — `ProcessKit` samples the machine into a `Snapshot`, `DockerClient` and `SimulatorSource` add containers and simulators, `Detectors` turns a snapshot plus rolling history into `Finding` values, `Actions` stops them behind a safety guard, and the `StillRunning` executable renders a `MenuBarExtra`. Detection is a pure function over serialisable snapshots, so every rule is tested against recorded fixtures without touching the live system.

**Tech Stack:** Swift 6.2 tools, SwiftUI `MenuBarExtra`, `libproc`/`sysctl` via `import Darwin`, `Network.framework` `NWConnection` over a unix socket for the Docker Engine API, `xcrun simctl` for simulators, Swift Testing (`import Testing`) for tests.

## Global Constraints

- Deployment target: macOS 26. `platforms: [.macOS(.v26)]`, swift-tools-version 6.2.
- Distribution is a SwiftPM build plus a bundling script that assembles `Still Running.app`. There is no `.xcodeproj`. (This refines the spec's "StillRunning.xcodeproj" sketch: SwiftPM keeps every library independently testable from the command line and makes CI trivial. The module layout from the spec is unchanged.)
- The app is unsandboxed and requires no root, Accessibility, or Full Disk Access.
- `LSUIElement` is `true`. No Dock icon, no main window.
- English only. No localisation files.
- Nothing is ever deleted. Actions stop things and nothing else.
- The never-touch list is enforced in `Actions`, not in the UI: no code path may pass a protected target to a `Stopper`.
- Stopping is graceful first. `SIGKILL` is only reachable through a separate, explicit force-quit call after a grace period.
- Every task ends with `swift test` passing and a commit.
- License MIT, repository `github.com/selinihtyr/still-running`.

## Verified Environment Facts

These were confirmed on the target machine before this plan was written. Do not re-litigate them.

- `import Darwin` exposes `sysctl`, `proc_pidinfo`, `proc_pidpath`, `kinfo_proc`, `proc_taskinfo`. No C shim target is needed.
- `sysctl(KERN_PROC, KERN_PROC_ALL)` returns every process with `kp_proc.p_pid`, `kp_eproc.e_ppid`, `kp_eproc.e_tdev` (`-1` means no controlling tty), `kp_eproc.e_ucred.cr_uid`, and `kp_proc.p_starttime`.
- `sysctl(KERN_PROCARGS2, pid)` returns the argument vector of another same-uid process without elevated privileges. This is how `--user-data-dir` is read.
- `proc_pidinfo(pid, PROC_PIDTASKINFO, ...)` returns `pti_total_user` and `pti_total_system` as **cumulative** nanoseconds, plus `pti_resident_size`. CPU percentage must therefore be a delta between two samples.
- The Docker socket is `~/.orbstack/run/docker.sock`, with `/var/run/docker.sock` symlinked to it. Plain unauthenticated HTTP/1.1 over the unix socket works.
- `xcrun simctl list devices booted -j` returns `{"devices": {"<runtime>": [ ... ]}}`.

## File Structure

```
still-running/
  Package.swift
  Sources/
    ProcessKit/
      ProcessSample.swift        Snapshot value types, Codable
      Snapshot.swift             Snapshot + SnapshotSource protocol
      LiveProcessSource.swift    sysctl + libproc implementation
      History.swift              ring buffer, CPU rates, sustained queries
    DockerClient/
      UnixSocketHTTP.swift       NWConnection request/response over UDS
      DockerClient.swift         list + stop, socket discovery
    SimulatorSource/
      SimulatorSource.swift      simctl list/shutdown behind a protocol
    Detectors/
      Finding.swift              Finding, FindingKind, StopTarget, Severity
      Settings.swift             thresholds
      Detector.swift             protocol
      IsolatedBrowserDetector.swift
      OrphanDetector.swift
      DevServerDetector.swift
      ContainerDetector.swift
      SimulatorDetector.swift
      DetectorEngine.swift       runs detectors, groups, applies exclusions
    Actions/
      SafetyGuard.swift          never-touch enforcement
      Stopper.swift              protocol + StopOutcome
      SignalStopper.swift        SIGTERM / SIGKILL
      ContainerStopper.swift     docker stop
      SimulatorStopper.swift     simctl shutdown
      StopCoordinator.swift      routing + guard + grace period
    StillRunningCore/
      Store.swift                observable state, sampling cadence
      Exclusions.swift           "Keep this" persistence
      SettingsStore.swift        UserDefaults-backed Settings
      Notifier.swift             opt-in notification
    StillRunning/
      StillRunningApp.swift      @main, MenuBarExtra
      PanelView.swift            the popover
      FindingRow.swift           one row + its actions
      AlsoHotSection.swift       informational list
      SettingsView.swift
  Tests/
    ProcessKitTests/ DockerClientTests/ DetectorsTests/ ActionsTests/ StillRunningCoreTests/
  Fixtures/
    hot-machine.json             recorded real snapshot, the regression anchor
  scripts/
    bundle.sh                    assembles Still Running.app
    record-fixture.swift         dumps a live Snapshot to JSON
  .github/workflows/ci.yml
  README.md  LICENSE
```

---

### Task 1: Package skeleton and CI

**Files:**
- Create: `Package.swift`, `Sources/ProcessKit/Snapshot.swift`, `Tests/ProcessKitTests/SnapshotTests.swift`, `.github/workflows/ci.yml`, `LICENSE`

**Interfaces:**
- Consumes: nothing.
- Produces: the package graph every later task adds to, and `Snapshot`/`ProcessSample`/`ContainerSample`/`SimulatorSample` value types.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StillRunning",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "StillRunning", targets: ["StillRunning"])
    ],
    targets: [
        .target(name: "ProcessKit"),
        .target(name: "DockerClient"),
        .target(name: "SimulatorSource"),
        .target(name: "Detectors", dependencies: ["ProcessKit"]),
        .target(name: "Actions", dependencies: ["Detectors", "DockerClient", "SimulatorSource"]),
        .target(name: "StillRunningCore", dependencies: ["Actions", "ProcessKit", "DockerClient", "SimulatorSource"]),
        .executableTarget(name: "StillRunning", dependencies: ["StillRunningCore"]),
        .testTarget(name: "ProcessKitTests", dependencies: ["ProcessKit"]),
        .testTarget(name: "DockerClientTests", dependencies: ["DockerClient"]),
        .testTarget(name: "DetectorsTests", dependencies: ["Detectors"]),
        .testTarget(name: "ActionsTests", dependencies: ["Actions"]),
        .testTarget(name: "StillRunningCoreTests", dependencies: ["StillRunningCore"]),
    ]
)
```

Create an empty placeholder file in each target directory that has no code yet, so SwiftPM does not fail on missing sources. A single-line `// intentionally empty for now` comment file named after the target is fine; later tasks replace it.

- [ ] **Step 2: Write the failing test**

`Tests/ProcessKitTests/SnapshotTests.swift`:

```swift
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
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `swift test --filter snapshotRoundTripsThroughJSON`
Expected: compile failure, `cannot find 'ProcessSample' in scope`.

- [ ] **Step 4: Write `Sources/ProcessKit/Snapshot.swift`**

```swift
import Foundation

public struct ProcessSample: Codable, Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let uid: UInt32
    public let executablePath: String
    public let arguments: [String]
    public let startedAt: Date
    public let hasControllingTTY: Bool
    /// Cumulative user + system CPU time. Rates must be derived from deltas.
    public let cpuTimeNanos: UInt64
    public let residentBytes: UInt64

    public var id: Int32 { pid }

    /// Last path component of the executable, e.g. "Google Chrome Helper".
    public var name: String { (executablePath as NSString).lastPathComponent }

    public init(pid: Int32, ppid: Int32, uid: UInt32, executablePath: String,
                arguments: [String], startedAt: Date, hasControllingTTY: Bool,
                cpuTimeNanos: UInt64, residentBytes: UInt64) {
        self.pid = pid; self.ppid = ppid; self.uid = uid
        self.executablePath = executablePath; self.arguments = arguments
        self.startedAt = startedAt; self.hasControllingTTY = hasControllingTTY
        self.cpuTimeNanos = cpuTimeNanos; self.residentBytes = residentBytes
    }
}

public struct ContainerSample: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let image: String
    public let startedAt: Date
    public init(id: String, name: String, image: String, startedAt: Date) {
        self.id = id; self.name = name; self.image = image; self.startedAt = startedAt
    }
}

public struct SimulatorSample: Codable, Sendable, Identifiable, Equatable {
    public let id: String        // UDID
    public let name: String
    public let runtime: String
    /// Derived from the device's launchd_sim process, nil when it cannot be resolved.
    public let bootedAt: Date?
    public init(id: String, name: String, runtime: String, bootedAt: Date?) {
        self.id = id; self.name = name; self.runtime = runtime; self.bootedAt = bootedAt
    }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public let takenAt: Date
    public let processes: [ProcessSample]
    public let containers: [ContainerSample]
    public let simulators: [SimulatorSample]
    public let currentUID: UInt32
    public let ownPID: Int32

    public init(takenAt: Date, processes: [ProcessSample], containers: [ContainerSample],
                simulators: [SimulatorSample], currentUID: UInt32, ownPID: Int32) {
        self.takenAt = takenAt; self.processes = processes; self.containers = containers
        self.simulators = simulators; self.currentUID = currentUID; self.ownPID = ownPID
    }

    public func process(pid: Int32) -> ProcessSample? { processes.first { $0.pid == pid } }
}
```

- [ ] **Step 5: Run the test and confirm it passes**

Run: `swift test --filter snapshotRoundTripsThroughJSON`
Expected: PASS.

- [ ] **Step 6: Add CI**

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
jobs:
  test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Show toolchain
        run: swift --version
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

- [ ] **Step 7: Add the MIT LICENSE file**

Standard MIT text, copyright holder `Selin Goncu`, year 2026.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources Tests .github LICENSE
git commit -m "Add package skeleton, snapshot value types, and CI"
```

---

### Task 2: Live process sampling

**Files:**
- Create: `Sources/ProcessKit/LiveProcessSource.swift`, `Tests/ProcessKitTests/LiveProcessSourceTests.swift`

**Interfaces:**
- Consumes: `ProcessSample`, `Snapshot` from Task 1.
- Produces: `protocol SnapshotSource { func sample() async -> Snapshot }`, and `LiveProcessSource.processes() -> [ProcessSample]`, used by Task 6's fixture recorder and Task 12's sampler.

- [ ] **Step 1: Write the failing test**

`Tests/ProcessKitTests/LiveProcessSourceTests.swift`:

```swift
import Testing
import Foundation
import Darwin
@testable import ProcessKit

@Test func liveSourceSeesTheTestProcessItself() {
    let source = LiveProcessSource()
    let processes = source.processes()
    let me = processes.first { $0.pid == getpid() }

    #expect(processes.count > 20)
    #expect(me != nil)
    #expect(me?.uid == getuid())
    #expect(me?.executablePath.isEmpty == false)
    #expect(me?.arguments.isEmpty == false)
    #expect(me!.startedAt < Date())
}

@Test func liveSourceReadsArgumentsOfOtherProcesses() {
    // Every macOS session has a loginwindow; the point is that argv of a
    // process we did not spawn is readable without elevated privileges.
    let processes = LiveProcessSource().processes()
    let others = processes.filter { $0.pid != getpid() && !$0.arguments.isEmpty }
    #expect(others.count > 5)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter LiveProcessSource`
Expected: `cannot find 'LiveProcessSource' in scope`.

- [ ] **Step 3: Write `Sources/ProcessKit/LiveProcessSource.swift`**

```swift
import Darwin
import Foundation

public protocol SnapshotSource: Sendable {
    func sample() async -> Snapshot
}

public struct LiveProcessSource: Sendable {
    public init() {}

    public func processes() -> [ProcessSample] {
        kinfoProcs().compactMap { sample(from: $0) }
    }

    private func kinfoProcs() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return Array(procs.prefix(size / stride))
    }

    private func sample(from kp: kinfo_proc) -> ProcessSample? {
        let pid = kp.kp_proc.p_pid
        guard pid > 0 else { return nil }

        var info = proc_taskinfo()
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let gotInfo = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize

        let started = Date(timeIntervalSince1970:
            Double(kp.kp_proc.p_starttime.tv_sec) +
            Double(kp.kp_proc.p_starttime.tv_usec) / 1_000_000)

        return ProcessSample(
            pid: pid,
            ppid: kp.kp_eproc.e_ppid,
            uid: kp.kp_eproc.e_ucred.cr_uid,
            executablePath: executablePath(pid),
            arguments: arguments(pid),
            startedAt: started,
            hasControllingTTY: kp.kp_eproc.e_tdev != -1,
            cpuTimeNanos: gotInfo ? info.pti_total_user + info.pti_total_system : 0,
            residentBytes: gotInfo ? info.pti_resident_size : 0
        )
    }

    private func executablePath(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// Reads argv via KERN_PROCARGS2. Returns [] for processes we may not inspect.
    private func arguments(_ pid: Int32) -> [String] {
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        var argmaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxMIB, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: Int(argmax))
        var bufferSize = Int(argmax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &bufferSize, nil, 0) == 0,
              bufferSize > MemoryLayout<Int32>.size else { return [] }

        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)
        guard argc > 0 else { return [] }

        var result: [String] = []
        buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            let end = base + bufferSize
            var cursor = base + MemoryLayout<Int32>.size
            while cursor < end, cursor.pointee != 0 { cursor += 1 }   // skip exec path
            while cursor < end, cursor.pointee == 0 { cursor += 1 }   // skip padding
            var read: Int32 = 0
            while cursor < end, read < argc {
                let argument = String(cString: cursor)
                result.append(argument)
                cursor += argument.utf8.count + 1
                read += 1
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter LiveProcessSource`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ProcessKit/LiveProcessSource.swift Tests/ProcessKitTests/LiveProcessSourceTests.swift
git commit -m "Sample the process table via sysctl and libproc"
```

---

### Task 3: History, CPU rates, and sustained queries

**Files:**
- Create: `Sources/ProcessKit/History.swift`, `Tests/ProcessKitTests/HistoryTests.swift`

**Interfaces:**
- Consumes: `Snapshot` from Task 1.
- Produces: `History` with `record(_:)`, `cpuPercent(pid:)`, `sustainedCPU(pid:over:)`, `idleDuration(pid:below:)`. Every detector from Task 6 onward takes a `History`.

`sustainedCPU(pid:over:)` returns the **minimum** CPU percentage observed across all samples covering the window, or `nil` when history does not yet span it. "At least 25% for 3 minutes" is therefore `sustainedCPU(pid:over: 180) ?? 0 >= 25`.

- [ ] **Step 1: Write the failing test**

`Tests/ProcessKitTests/HistoryTests.swift`:

```swift
import Testing
import Foundation
@testable import ProcessKit

private func snapshot(at seconds: TimeInterval, pid: Int32, cpuNanos: UInt64, rss: UInt64 = 0) -> Snapshot {
    Snapshot(
        takenAt: Date(timeIntervalSince1970: seconds),
        processes: [ProcessSample(
            pid: pid, ppid: 1, uid: 501, executablePath: "/bin/x", arguments: ["x"],
            startedAt: Date(timeIntervalSince1970: 0), hasControllingTTY: false,
            cpuTimeNanos: cpuNanos, residentBytes: rss)],
        containers: [], simulators: [], currentUID: 501, ownPID: 1)
}

@Test func cpuPercentIsADeltaBetweenTwoSamples() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    // One full second of CPU burned across ten seconds of wall clock = 10%.
    history.record(snapshot(at: 10, pid: 7, cpuNanos: 1_000_000_000))

    #expect(history.cpuPercent(pid: 7)! == 10.0)
}

@Test func cpuPercentIsNilWithASingleSample() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    #expect(history.cpuPercent(pid: 7) == nil)
}

@Test func sustainedCPUReportsTheWeakestIntervalInTheWindow() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 60, pid: 7, cpuNanos: 60_000_000_000))    // 100%
    history.record(snapshot(at: 120, pid: 7, cpuNanos: 78_000_000_000))   // 30%
    history.record(snapshot(at: 180, pid: 7, cpuNanos: 138_000_000_000))  // 100%

    #expect(history.sustainedCPU(pid: 7, over: 180)! == 30.0)
}

@Test func sustainedCPUIsNilWhenHistoryIsShorterThanTheWindow() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 30, pid: 7, cpuNanos: 30_000_000_000))
    #expect(history.sustainedCPU(pid: 7, over: 180) == nil)
}

@Test func idleDurationMeasuresHowLongCPUStayedBelowAThreshold() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 600, pid: 7, cpuNanos: 1_000_000_000))    // ~0.17%
    history.record(snapshot(at: 1200, pid: 7, cpuNanos: 2_000_000_000))   // ~0.17%

    #expect(history.idleDuration(pid: 7, below: 2)! == 1200)
}

@Test func idleDurationStopsAtTheLastBusyInterval() {
    var history = History()
    history.record(snapshot(at: 0, pid: 7, cpuNanos: 0))
    history.record(snapshot(at: 60, pid: 7, cpuNanos: 60_000_000_000))    // 100%, busy
    history.record(snapshot(at: 660, pid: 7, cpuNanos: 60_100_000_000))   // idle

    #expect(history.idleDuration(pid: 7, below: 2)! == 600)
}

@Test func historyDropsSamplesBeyondCapacity() {
    var history = History(capacity: 3)
    for step in 0..<5 {
        history.record(snapshot(at: Double(step) * 10, pid: 7, cpuNanos: UInt64(step) * 1_000_000_000))
    }
    #expect(history.count == 3)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter HistoryTests`
Expected: `cannot find 'History' in scope`.

- [ ] **Step 3: Write `Sources/ProcessKit/History.swift`**

```swift
import Foundation

/// A bounded ring of recent snapshots. Detection reads rates from here rather
/// than from a single sample, so a momentary spike never surfaces a finding.
public struct History: Sendable {
    public private(set) var snapshots: [Snapshot] = []
    private let capacity: Int

    /// 60 samples at the 5 second foreground cadence is five minutes of history.
    public init(capacity: Int = 60) {
        self.capacity = max(2, capacity)
    }

    public var count: Int { snapshots.count }
    public var latest: Snapshot? { snapshots.last }

    public mutating func record(_ snapshot: Snapshot) {
        snapshots.append(snapshot)
        if snapshots.count > capacity { snapshots.removeFirst(snapshots.count - capacity) }
    }

    /// CPU percentage over the most recent interval. 100 means one full core.
    public func cpuPercent(pid: Int32) -> Double? {
        guard snapshots.count >= 2 else { return nil }
        return interval(from: snapshots[snapshots.count - 2], to: snapshots[snapshots.count - 1], pid: pid)
    }

    /// The lowest CPU percentage seen across every interval covering `window`.
    /// Nil when recorded history is shorter than the window.
    public func sustainedCPU(pid: Int32, over window: TimeInterval) -> Double? {
        guard let newest = snapshots.last, let oldest = snapshots.first,
              newest.takenAt.timeIntervalSince(oldest.takenAt) >= window else { return nil }
        let cutoff = newest.takenAt.addingTimeInterval(-window)

        var lowest: Double?
        for index in 1..<snapshots.count {
            let earlier = snapshots[index - 1], later = snapshots[index]
            guard later.takenAt > cutoff else { continue }
            guard let value = interval(from: earlier, to: later, pid: pid) else { return nil }
            lowest = min(lowest ?? value, value)
        }
        return lowest
    }

    /// How long CPU has continuously stayed below `threshold`, walking backwards.
    public func idleDuration(pid: Int32, below threshold: Double) -> TimeInterval? {
        guard let newest = snapshots.last, snapshots.count >= 2 else { return nil }
        var idleSince = newest.takenAt
        for index in stride(from: snapshots.count - 1, through: 1, by: -1) {
            let earlier = snapshots[index - 1], later = snapshots[index]
            guard let value = interval(from: earlier, to: later, pid: pid), value < threshold else { break }
            idleSince = earlier.takenAt
        }
        let duration = newest.takenAt.timeIntervalSince(idleSince)
        return duration > 0 ? duration : nil
    }

    private func interval(from earlier: Snapshot, to later: Snapshot, pid: Int32) -> Double? {
        guard let before = earlier.process(pid: pid), let after = later.process(pid: pid),
              after.cpuTimeNanos >= before.cpuTimeNanos else { return nil }
        let elapsed = later.takenAt.timeIntervalSince(earlier.takenAt)
        guard elapsed > 0 else { return nil }
        let burned = Double(after.cpuTimeNanos - before.cpuTimeNanos) / 1_000_000_000
        return burned / elapsed * 100
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter HistoryTests`
Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ProcessKit/History.swift Tests/ProcessKitTests/HistoryTests.swift
git commit -m "Derive CPU rates and sustained load from snapshot history"
```

---

### Task 4: Docker Engine client over the unix socket

**Files:**
- Create: `Sources/DockerClient/UnixSocketHTTP.swift`, `Sources/DockerClient/DockerClient.swift`, `Tests/DockerClientTests/HTTPResponseTests.swift`, `Tests/DockerClientTests/DockerClientTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `DockerClient.containers() async throws -> [DockerContainer]` and `DockerClient.stop(id:timeout:) async throws`, consumed by Task 8's detector and Task 11's stopper. `DockerContainer` has `id`, `names: [String]`, `image`, `created: Date`, `state`.

The client sends `Connection: close` and reads until the peer closes, so neither chunked encoding nor `Content-Length` parsing is needed.

- [ ] **Step 1: Write the failing response-parser test**

`Tests/DockerClientTests/HTTPResponseTests.swift`:

```swift
import Testing
import Foundation
@testable import DockerClient

@Test func parsesStatusAndBody() throws {
    let raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n[{\"Id\":\"abc\"}]"
    let response = try HTTPResponse(raw: Data(raw.utf8))

    #expect(response.status == 200)
    #expect(String(decoding: response.body, as: UTF8.self) == "[{\"Id\":\"abc\"}]")
}

@Test func parsesAnEmptyBody() throws {
    let raw = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
    let response = try HTTPResponse(raw: Data(raw.utf8))

    #expect(response.status == 204)
    #expect(response.body.isEmpty)
}

@Test func rejectsAResponseWithoutAHeaderTerminator() {
    #expect(throws: HTTPError.self) {
        _ = try HTTPResponse(raw: Data("HTTP/1.1 200 OK\r\nContent-Type: x".utf8))
    }
}

@Test func rejectsAMalformedStatusLine() {
    #expect(throws: HTTPError.self) {
        _ = try HTTPResponse(raw: Data("GARBAGE\r\n\r\n".utf8))
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter HTTPResponseTests`
Expected: `cannot find 'HTTPResponse' in scope`.

- [ ] **Step 3: Write `Sources/DockerClient/UnixSocketHTTP.swift`**

```swift
import Foundation
import Network

public enum HTTPError: Error, Equatable {
    case malformedResponse
    case socketUnavailable
    case transport(String)
    case status(Int, String)
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(raw: Data) throws {
        let terminator = Data("\r\n\r\n".utf8)
        guard let range = raw.range(of: terminator) else { throw HTTPError.malformedResponse }
        let head = String(decoding: raw[..<range.lowerBound], as: UTF8.self)
        guard let statusLine = head.split(separator: "\r\n", omittingEmptySubsequences: false).first,
              statusLine.hasPrefix("HTTP/"),
              let code = Int(statusLine.split(separator: " ").dropFirst().first.map(String.init) ?? "")
        else { throw HTTPError.malformedResponse }

        self.status = code
        self.body = Data(raw[range.upperBound...])
    }
}

/// Minimal HTTP/1.1 over a unix domain socket. One request per connection,
/// always with `Connection: close`, so the body is simply everything received
/// before the peer hangs up.
public struct UnixSocketHTTP: Sendable {
    public let socketPath: String
    public init(socketPath: String) { self.socketPath = socketPath }

    public func send(method: String, path: String, timeout: TimeInterval = 10) async throws -> HTTPResponse {
        let request = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
        let raw = try await exchange(Data(request.utf8), timeout: timeout)
        return try HTTPResponse(raw: raw)
    }

    private func exchange(_ request: Data, timeout: TimeInterval) async throws -> Data {
        let endpoint = NWEndpoint.unix(path: socketPath)
        let connection = NWConnection(to: endpoint, using: .tcp)
        let collector = ResponseCollector()

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            connection.send(content: request, completion: .contentProcessed { error in
                                if let error { continuation.resume(throwing: HTTPError.transport("\(error)")) }
                            })
                            receive(on: connection, into: collector, continuation: continuation)
                        case .failed(let error):
                            continuation.resume(throwing: HTTPError.transport("\(error)"))
                        case .cancelled:
                            continuation.resume(throwing: HTTPError.transport("cancelled"))
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw HTTPError.transport("timed out after \(timeout)s")
            }
            defer { group.cancelAll(); connection.cancel() }
            guard let first = try await group.next() else { throw HTTPError.transport("no result") }
            return first
        }
    }

    private func receive(on connection: NWConnection, into collector: ResponseCollector,
                         continuation: CheckedContinuation<Data, Error>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { chunk, _, isComplete, error in
            if let error { continuation.resume(throwing: HTTPError.transport("\(error)")); return }
            if let chunk { collector.append(chunk) }
            if isComplete { continuation.resume(returning: collector.data); return }
            receive(on: connection, into: collector, continuation: continuation)
        }
    }
}

private final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    var data: Data { lock.withLock { buffer } }
    func append(_ chunk: Data) { lock.withLock { buffer.append(chunk) } }
}
```

- [ ] **Step 4: Run the parser tests and confirm they pass**

Run: `swift test --filter HTTPResponseTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Write the failing client test**

`Tests/DockerClientTests/DockerClientTests.swift`:

```swift
import Testing
import Foundation
@testable import DockerClient

@Test func decodesTheContainerListPayload() throws {
    let payload = """
    [{"Id":"09ac719c3957","Names":["/selene-web"],"Image":"selene-backend-web",
      "Created":1785000000,"State":"running","Status":"Up 20 hours"}]
    """
    let containers = try DockerClient.decodeContainers(Data(payload.utf8))

    #expect(containers.count == 1)
    #expect(containers[0].id == "09ac719c3957")
    #expect(containers[0].displayName == "selene-web")   // leading slash stripped
    #expect(containers[0].state == "running")
    #expect(containers[0].created == Date(timeIntervalSince1970: 1_785_000_000))
}

@Test func prefersTheOrbStackSocketWhenBothExist() {
    let candidates = DockerClient.socketCandidates(home: "/Users/x")
    #expect(candidates.first == "/Users/x/.orbstack/run/docker.sock")
    #expect(candidates.contains("/var/run/docker.sock"))
}

@Test func liveDaemonListsContainersWhenASocketIsPresent() async throws {
    guard let client = DockerClient.discover() else { return }   // skip when no daemon
    let containers = try await client.containers()
    #expect(containers.allSatisfy { !$0.id.isEmpty })
}
```

- [ ] **Step 6: Run it and confirm it fails**

Run: `swift test --filter DockerClientTests`
Expected: `cannot find 'DockerClient' in scope`.

- [ ] **Step 7: Write `Sources/DockerClient/DockerClient.swift`**

```swift
import Foundation

public struct DockerContainer: Sendable, Equatable, Codable {
    public let id: String
    public let names: [String]
    public let image: String
    public let created: Date
    public let state: String

    public var displayName: String {
        (names.first ?? id).hasPrefix("/") ? String((names.first ?? id).dropFirst()) : (names.first ?? id)
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id", names = "Names", image = "Image", created = "Created", state = "State"
    }
}

public struct DockerClient: Sendable {
    private let http: UnixSocketHTTP
    private static let apiVersion = "v1.43"

    public init(socketPath: String) { self.http = UnixSocketHTTP(socketPath: socketPath) }

    public static func socketCandidates(home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.orbstack/run/docker.sock", "\(home)/.docker/run/docker.sock", "/var/run/docker.sock"]
    }

    /// Returns a client for the first socket that exists, or nil when no daemon is installed.
    public static func discover() -> DockerClient? {
        socketCandidates().first { FileManager.default.fileExists(atPath: $0) }.map(DockerClient.init)
    }

    public func containers() async throws -> [DockerContainer] {
        let response = try await http.send(method: "GET", path: "/\(Self.apiVersion)/containers/json")
        guard response.status == 200 else {
            throw HTTPError.status(response.status, String(decoding: response.body, as: UTF8.self))
        }
        return try Self.decodeContainers(response.body)
    }

    /// Graceful stop. Docker sends SIGTERM, then SIGKILL after `timeout` seconds.
    public func stop(id: String, timeout: Int = 10) async throws {
        let response = try await http.send(
            method: "POST", path: "/\(Self.apiVersion)/containers/\(id)/stop?t=\(timeout)",
            timeout: TimeInterval(timeout) + 10)
        // 204 stopped, 304 already stopped. Both are success for our purposes.
        guard response.status == 204 || response.status == 304 else {
            throw HTTPError.status(response.status, String(decoding: response.body, as: UTF8.self))
        }
    }

    static func decodeContainers(_ data: Data) throws -> [DockerContainer] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([DockerContainer].self, from: data)
    }
}
```

- [ ] **Step 8: Run the client tests and confirm they pass**

Run: `swift test --filter DockerClientTests`
Expected: 3 tests PASS. The live test exercises the real daemon on this machine; it silently returns when no socket exists so CI stays green.

- [ ] **Step 9: Commit**

```bash
git add Sources/DockerClient Tests/DockerClientTests
git commit -m "Talk to the Docker Engine API over the unix socket"
```

---

### Task 5: Simulator source

**Files:**
- Create: `Sources/SimulatorSource/SimulatorSource.swift`, `Tests/SimulatorSourceTests/SimulatorSourceTests.swift`
- Modify: `Package.swift` — add the `SimulatorSourceTests` test target

**Interfaces:**
- Consumes: nothing.
- Produces: `protocol SimulatorControl { func booted() async throws -> [BootedSimulator]; func shutdown(udid: String) async throws }`, `SimctlSource` conforming to it, and `BootedSimulator` with `udid`, `name`, `runtime`. Task 8 detects them and Task 11 shuts them down.

- [ ] **Step 1: Add the test target to `Package.swift`**

```swift
.testTarget(name: "SimulatorSourceTests", dependencies: ["SimulatorSource"]),
```

- [ ] **Step 2: Write the failing test**

`Tests/SimulatorSourceTests/SimulatorSourceTests.swift`:

```swift
import Testing
import Foundation
@testable import SimulatorSource

@Test func parsesBootedDevicesFromSimctlJSON() throws {
    let payload = """
    {"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
        {"udid":"A1B2","name":"iPhone 17 Pro","state":"Booted","isAvailable":true}],
      "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[]
    }}
    """
    let devices = try SimctlSource.decodeBooted(Data(payload.utf8))

    #expect(devices.count == 1)
    #expect(devices[0].udid == "A1B2")
    #expect(devices[0].name == "iPhone 17 Pro")
    #expect(devices[0].runtime == "iOS 26.5")
}

@Test func ignoresDevicesThatAreNotBooted() throws {
    let payload = """
    {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
      {"udid":"A1B2","name":"iPhone 17 Pro","state":"Shutdown","isAvailable":true}]}}
    """
    #expect(try SimctlSource.decodeBooted(Data(payload.utf8)).isEmpty)
}

@Test func returnsNoDevicesWhenXcodeIsMissing() async {
    let source = SimctlSource(xcrunPath: "/nonexistent/xcrun")
    let devices = try? await source.booted()
    #expect(devices?.isEmpty ?? true)
}
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `swift test --filter SimulatorSourceTests`
Expected: `cannot find 'SimctlSource' in scope`.

- [ ] **Step 4: Write `Sources/SimulatorSource/SimulatorSource.swift`**

```swift
import Foundation

public struct BootedSimulator: Sendable, Equatable {
    public let udid: String
    public let name: String
    public let runtime: String
    public init(udid: String, name: String, runtime: String) {
        self.udid = udid; self.name = name; self.runtime = runtime
    }
}

public protocol SimulatorControl: Sendable {
    func booted() async throws -> [BootedSimulator]
    func shutdown(udid: String) async throws
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

    static func decodeBooted(_ data: Data) throws -> [BootedSimulator] {
        struct Payload: Decodable {
            struct Device: Decodable { let udid: String; let name: String; let state: String }
            let devices: [String: [Device]]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.devices.flatMap { runtime, devices in
            devices.filter { $0.state == "Booted" }
                .map { BootedSimulator(udid: $0.udid, name: $0.name, runtime: Self.friendlyRuntime(runtime)) }
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
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --filter SimulatorSourceTests`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SimulatorSource Tests/SimulatorSourceTests
git commit -m "List and shut down booted simulators through simctl"
```

---

### Task 6: Finding types, settings, and the isolated-browser detector

This is the safety-critical task: it is the one that decides which browser processes may be offered for stopping. The negative test matters more than the positive one.

**Files:**
- Create: `Sources/Detectors/Finding.swift`, `Sources/Detectors/Settings.swift`, `Sources/Detectors/Detector.swift`, `Sources/Detectors/IsolatedBrowserDetector.swift`, `Tests/DetectorsTests/Fixtures.swift`, `Tests/DetectorsTests/IsolatedBrowserDetectorTests.swift`
- Modify: `Package.swift` — give `DetectorsTests` a `resources: [.copy("../../Fixtures")]`-free setup; fixtures are built in code, see Step 1.

**Interfaces:**
- Consumes: `Snapshot`, `ProcessSample`, `History` from ProcessKit.
- Produces: `Finding`, `FindingKind`, `StopTarget`, `Settings`, `protocol Detector`. Tasks 7 through 11 all build on these exact names.

- [ ] **Step 1: Write the fixture builder**

Fixtures are constructed in Swift rather than loaded from JSON so the tests stay readable and need no bundle resources. `Fixtures.swift` reproduces the real situation observed on the target machine: a Chrome tree on the default profile, a second Chrome tree on `/tmp/claude-cdp-prof`, and system processes.

`Tests/DetectorsTests/Fixtures.swift`:

```swift
import Foundation
@testable import Detectors
import ProcessKit

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_785_000_000)
    static let chromeFramework =
        "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/150.0.7871.186/Helpers"

    static func process(pid: Int32, ppid: Int32 = 1, path: String, args: [String],
                        ageHours: Double = 0.1, uid: UInt32 = 501, tty: Bool = false,
                        cpuNanos: UInt64 = 0, rssMB: UInt64 = 50) -> ProcessSample {
        ProcessSample(
            pid: pid, ppid: ppid, uid: uid, executablePath: path, arguments: args,
            startedAt: now.addingTimeInterval(-ageHours * 3600), hasControllingTTY: tty,
            cpuTimeNanos: cpuNanos, residentBytes: rssMB * 1_048_576)
    }

    /// Chrome's own tabs: a browser process with no --user-data-dir, plus helpers.
    static func defaultChrome() -> [ProcessSample] {
        [
            process(pid: 14914, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                    args: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"], ageHours: 20),
            process(pid: 14920, ppid: 14914, path: "\(chromeFramework)/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)",
                    args: ["Google Chrome Helper (GPU)", "--type=gpu-process"], ageHours: 20, rssMB: 300),
            process(pid: 15205, ppid: 14914, path: "\(chromeFramework)/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                    args: ["Google Chrome Helper (Renderer)", "--type=renderer"], ageHours: 20, rssMB: 400),
        ]
    }

    /// An automation profile left behind by a tool run.
    static func automationChrome(ageHours: Double = 18.7) -> [ProcessSample] {
        [
            process(pid: 23947, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                    args: ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                           "--user-data-dir=/tmp/claude-cdp-prof", "--remote-debugging-port=9222"],
                    ageHours: ageHours, rssMB: 200),
            process(pid: 23953, ppid: 23947, path: "\(chromeFramework)/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)",
                    args: ["Google Chrome Helper (GPU)", "--type=gpu-process", "--user-data-dir=/tmp/claude-cdp-prof"],
                    ageHours: ageHours, rssMB: 250),
            process(pid: 35770, ppid: 23947, path: "\(chromeFramework)/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                    args: ["Google Chrome Helper (Renderer)", "--type=renderer", "--user-data-dir=/tmp/claude-cdp-prof"],
                    ageHours: ageHours, rssMB: 300),
        ]
    }

    static func system() -> [ProcessSample] {
        [
            process(pid: 1, path: "/sbin/launchd", args: ["/sbin/launchd"], ageHours: 52, uid: 0),
            process(pid: 164, path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer",
                    args: ["WindowServer", "-daemon"], ageHours: 52, uid: 88),
            process(pid: 418, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                    args: ["/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"], ageHours: 52),
        ]
    }

    static func snapshot(processes: [ProcessSample], containers: [ContainerSample] = [],
                         simulators: [SimulatorSample] = [], at: Date = now) -> Snapshot {
        Snapshot(takenAt: at, processes: processes, containers: containers,
                 simulators: simulators, currentUID: 501, ownPID: 999)
    }

    /// Two snapshots `apart` seconds apart, the second having burned `cpuPercent`
    /// of a core for every process, so History reports a real rate.
    static func history(_ processes: [ProcessSample], cpuPercent: Double, apart: TimeInterval = 60,
                        samples: Int = 6) -> History {
        var history = History()
        for step in 0..<samples {
            let elapsed = Double(step) * apart
            let burned = UInt64(cpuPercent / 100 * elapsed * 1_000_000_000)
            let advanced = processes.map {
                ProcessSample(pid: $0.pid, ppid: $0.ppid, uid: $0.uid, executablePath: $0.executablePath,
                              arguments: $0.arguments, startedAt: $0.startedAt,
                              hasControllingTTY: $0.hasControllingTTY,
                              cpuTimeNanos: $0.cpuTimeNanos + burned, residentBytes: $0.residentBytes)
            }
            history.record(snapshot(processes: advanced, at: now.addingTimeInterval(elapsed - Double(samples - 1) * apart)))
        }
        return history
    }
}
```

- [ ] **Step 2: Write the failing test**

`Tests/DetectorsTests/IsolatedBrowserDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func flagsAnAutomationProfileBrowser() {
    let processes = Fixtures.automationChrome() + Fixtures.defaultChrome() + Fixtures.system()
    let snapshot = Fixtures.snapshot(processes: processes)
    let findings = IsolatedBrowserDetector().findings(
        in: snapshot, history: Fixtures.history(processes, cpuPercent: 60), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].kind == .isolatedBrowser)
    #expect(findings[0].detail.contains("/tmp/claude-cdp-prof"))
}

@Test func neverFlagsTheUsersOwnBrowser() {
    // The regression that matters: the user's real tabs must never be offered.
    let processes = Fixtures.defaultChrome() + Fixtures.system()
    let snapshot = Fixtures.snapshot(processes: processes)
    let findings = IsolatedBrowserDetector().findings(
        in: snapshot, history: Fixtures.history(processes, cpuPercent: 95), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func groupsTheWholeProfileTreeIntoOneFinding() {
    let processes = Fixtures.automationChrome()
    let snapshot = Fixtures.snapshot(processes: processes)
    let findings = IsolatedBrowserDetector().findings(
        in: snapshot, history: Fixtures.history(processes, cpuPercent: 40), settings: Settings())

    #expect(findings.count == 1)
    guard case .processes(let pids) = findings[0].target else { Issue.record("wrong target"); return }
    #expect(pids.count == 3)
    #expect(pids.first == 23947)                      // root first, so SIGTERM tears down the tree
    #expect(findings[0].memoryBytes == 750 * 1_048_576)  // aggregated across the tree
    #expect(findings[0].cpuPercent == 120)               // 3 processes at 40%
}

@Test func ignoresAYoungQuietAutomationBrowser() {
    // Started two minutes ago and idle: probably a tool run in progress.
    let processes = Fixtures.automationChrome(ageHours: 0.03)
    let snapshot = Fixtures.snapshot(processes: processes)
    let findings = IsolatedBrowserDetector().findings(
        in: snapshot, history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func treatsAProfileInsideTheStandardLocationAsTheUsersOwn() {
    let home = NSHomeDirectory()
    let processes = [Fixtures.process(
        pid: 5000, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        args: ["Google Chrome", "--user-data-dir=\(home)/Library/Application Support/Google/Chrome"],
        ageHours: 20)]
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 90), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func flagsAHeadlessBrowserEvenWithoutAProfileFlag() {
    let processes = [Fixtures.process(
        pid: 6000, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        args: ["Google Chrome", "--headless=new"], ageHours: 5)]
    let findings = IsolatedBrowserDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    #expect(findings.count == 1)
}
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `swift test --filter IsolatedBrowserDetectorTests`
Expected: `cannot find 'IsolatedBrowserDetector' in scope`.

- [ ] **Step 4: Write `Sources/Detectors/Finding.swift`**

```swift
import Foundation

public enum FindingKind: String, Sendable, Codable, CaseIterable {
    case isolatedBrowser, container, simulator, devServer, orphan

    public var label: String {
        switch self {
        case .isolatedBrowser: "Automation browser"
        case .container: "Container"
        case .simulator: "Simulator"
        case .devServer: "Dev server"
        case .orphan: "Orphaned process"
        }
    }
}

public enum StopTarget: Sendable, Equatable, Hashable {
    /// Root process first. Stopping the root is expected to tear down the tree.
    case processes([Int32])
    case container(String)
    case simulator(String)
}

public enum Severity: Int, Sendable, Comparable {
    case informational = 0, notable = 1, urgent = 2
    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

public struct Finding: Sendable, Identifiable, Equatable {
    /// Stable across restarts and pid changes. Exclusions match on this.
    public let identity: String
    public let kind: FindingKind
    public let title: String
    public let detail: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let age: TimeInterval
    public let target: StopTarget
    public let severity: Severity

    public var id: String { identity }

    public init(identity: String, kind: FindingKind, title: String, detail: String,
                cpuPercent: Double, memoryBytes: UInt64, age: TimeInterval,
                target: StopTarget, severity: Severity) {
        self.identity = identity; self.kind = kind; self.title = title; self.detail = detail
        self.cpuPercent = cpuPercent; self.memoryBytes = memoryBytes; self.age = age
        self.target = target; self.severity = severity
    }
}

public enum Formatting {
    /// "18h 43m", "45m", "2d 3h"
    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86_400, hours = (total % 86_400) / 3600, minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func memory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
```

- [ ] **Step 5: Write `Sources/Detectors/Settings.swift`**

```swift
import Foundation

public struct Settings: Codable, Sendable, Equatable {
    /// Nothing younger than this is surfaced on age alone.
    public var minimumAge: TimeInterval = 2 * 3600
    public var sustainedCPUPercent: Double = 25
    public var sustainedCPUWindow: TimeInterval = 180
    public var idleCPUPercent: Double = 2
    public var idleWindow: TimeInterval = 1800
    public var idleMemoryBytes: UInt64 = 500 * 1_048_576
    /// Opt-in. Nil means no notifications.
    public var notifyAfter: TimeInterval? = nil

    public init() {}

    /// True when a thing this old, this busy, and this large is worth surfacing.
    public func crossesThreshold(age: TimeInterval, sustainedCPU: Double?,
                                 idleFor: TimeInterval?, memoryBytes: UInt64,
                                 isOrphan: Bool = false) -> Bool {
        if isOrphan { return true }
        if age >= minimumAge { return true }
        if let cpu = sustainedCPU, cpu >= sustainedCPUPercent { return true }
        if let idle = idleFor, idle >= idleWindow, memoryBytes >= idleMemoryBytes { return true }
        return false
    }
}
```

- [ ] **Step 6: Write `Sources/Detectors/Detector.swift`**

```swift
import Foundation
import ProcessKit

public protocol Detector: Sendable {
    var kind: FindingKind { get }
    func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding]
}

extension Detector {
    /// Sums a rate across a process group, treating unknown rates as zero.
    func totalCPU(_ processes: [ProcessSample], _ history: History) -> Double {
        processes.reduce(0) { $0 + (history.cpuPercent(pid: $1.pid) ?? 0) }
    }

    /// The weakest sustained rate in the group, used for threshold decisions.
    func groupSustainedCPU(_ processes: [ProcessSample], _ history: History,
                           over window: TimeInterval) -> Double? {
        let rates = processes.compactMap { history.sustainedCPU(pid: $0.pid, over: window) }
        return rates.isEmpty ? nil : rates.reduce(0, +)
    }
}
```

- [ ] **Step 7: Write `Sources/Detectors/IsolatedBrowserDetector.swift`**

```swift
import Foundation
import ProcessKit

/// Finds browsers running on a throwaway profile: automation, scraping, or a
/// tool run that was never cleaned up. A browser on its normal profile holds
/// the user's tabs and is never a candidate.
public struct IsolatedBrowserDetector: Detector {
    public let kind: FindingKind = .isolatedBrowser
    public init() {}

    private static let browserMarkers = ["Google Chrome", "Chromium", "Microsoft Edge",
                                         "Brave Browser", "Firefox", "Safari"]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        let candidates = snapshot.processes.filter {
            $0.uid == snapshot.currentUID && $0.pid != snapshot.ownPID && Self.isBrowser($0)
        }

        // Group by profile directory so a fifteen-process Chrome tree is one row.
        var groups: [String: [ProcessSample]] = [:]
        for process in candidates {
            guard let signature = Self.isolationSignature(process) else { continue }
            groups[signature, default: []].append(process)
        }

        return groups.compactMap { signature, group -> Finding? in
            let sorted = group.sorted { $0.startedAt < $1.startedAt }
            guard let root = sorted.first else { return nil }
            let age = snapshot.takenAt.timeIntervalSince(root.startedAt)
            let memory = group.reduce(UInt64(0)) { $0 + $1.residentBytes }
            let sustained = groupSustainedCPU(group, history, over: settings.sustainedCPUWindow)
            let idle = history.idleDuration(pid: root.pid, below: settings.idleCPUPercent)

            guard settings.crossesThreshold(age: age, sustainedCPU: sustained,
                                            idleFor: idle, memoryBytes: memory) else { return nil }

            let cpu = totalCPU(group, history)
            return Finding(
                identity: "browser:\(signature)",
                kind: .isolatedBrowser,
                title: "\(Self.browserName(root)) · automation profile",
                detail: "\(Formatting.duration(age)) · \(signature)",
                cpuPercent: cpu,
                memoryBytes: memory,
                age: age,
                target: .processes(Self.rootFirst(sorted)),
                severity: cpu >= 50 ? .urgent : .notable)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    static func isBrowser(_ process: ProcessSample) -> Bool {
        browserMarkers.contains { process.executablePath.contains($0) }
    }

    static func browserName(_ process: ProcessSample) -> String {
        browserMarkers.first { process.executablePath.contains($0) } ?? process.name
    }

    /// The profile path when it is outside the standard location, "headless"
    /// when the browser is headless with a normal profile, nil when this is the
    /// user's own browsing.
    static func isolationSignature(_ process: ProcessSample) -> String? {
        if let flag = process.arguments.first(where: { $0.hasPrefix("--user-data-dir=") }) {
            let path = String(flag.dropFirst("--user-data-dir=".count))
            return isStandardProfileLocation(path) ? nil : path
        }
        if process.arguments.contains(where: { $0.hasPrefix("--headless") }) { return "headless" }
        if process.arguments.contains(where: { $0.hasPrefix("--remote-debugging-port") }) { return "remote-debugging" }
        return nil
    }

    /// Profiles under Application Support belong to the user, whatever the flag says.
    static func isStandardProfileLocation(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let standard = "\(home)/Library/Application Support"
        return path.hasPrefix(standard)
    }

    /// Root first: whoever has no parent inside the group leads the list.
    static func rootFirst(_ group: [ProcessSample]) -> [Int32] {
        let pids = Set(group.map(\.pid))
        let roots = group.filter { !pids.contains($0.ppid) }
        let rest = group.filter { pids.contains($0.ppid) }
        return roots.map(\.pid) + rest.map(\.pid)
    }
}
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `swift test --filter IsolatedBrowserDetectorTests`
Expected: 6 tests PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/Detectors Tests/DetectorsTests
git commit -m "Detect automation browser profiles, never the user's own tabs"
```

---

### Task 7: Orphan and dev-server detectors

**Files:**
- Create: `Sources/Detectors/OrphanDetector.swift`, `Sources/Detectors/DevServerDetector.swift`, `Tests/DetectorsTests/OrphanDetectorTests.swift`, `Tests/DetectorsTests/DevServerDetectorTests.swift`

**Interfaces:**
- Consumes: `Detector`, `Finding`, `Settings`, `Fixtures` from Task 6.
- Produces: `OrphanDetector`, `DevServerDetector`, and `DevServerDetector.knownCommands`, referenced by the engine in Task 9.

- [ ] **Step 1: Write the failing dev-server test**

`Tests/DetectorsTests/DevServerDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func flagsALongRunningViteServer() {
    let processes = [Fixtures.process(
        pid: 4100, path: "/opt/homebrew/bin/node",
        args: ["node", "/Users/x/app/node_modules/.bin/vite", "--port", "5173"],
        ageHours: 9, rssMB: 380)]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].kind == .devServer)
    #expect(findings[0].title.contains("vite"))
}

@Test func flagsABunServerAndAGradleDaemon() {
    let processes = [
        Fixtures.process(pid: 4200, path: "/opt/homebrew/bin/bun",
                         args: ["bun", "run", "dev"], ageHours: 6),
        Fixtures.process(pid: 4300, path: "/opt/homebrew/opt/openjdk/bin/java",
                         args: ["java", "-Xmx2g", "org.gradle.launcher.daemon.bootstrap.GradleDaemon"],
                         ageHours: 30, rssMB: 900),
    ]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0.5), settings: Settings())

    #expect(findings.count == 2)
}

@Test func ignoresAFreshDevServer() {
    let processes = [Fixtures.process(
        pid: 4400, path: "/opt/homebrew/bin/node", args: ["node", "server.js"], ageHours: 0.2)]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 3), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresUnrelatedBinariesNamedLikeNothingWeKnow() {
    let processes = [Fixtures.process(
        pid: 4500, path: "/usr/bin/pbcopy", args: ["pbcopy"], ageHours: 30)]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresProcessesOwnedByAnotherUser() {
    let processes = [Fixtures.process(
        pid: 4600, path: "/opt/homebrew/bin/node", args: ["node", "daemon.js"],
        ageHours: 30, uid: 0)]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter DevServerDetectorTests`
Expected: `cannot find 'DevServerDetector' in scope`.

- [ ] **Step 3: Write `Sources/Detectors/DevServerDetector.swift`**

```swift
import Foundation
import ProcessKit

/// Development servers, bundlers, and watchers. These are the things people
/// start in a terminal, walk away from, and never stop.
public struct DevServerDetector: Detector {
    public let kind: FindingKind = .devServer
    public init() {}

    /// Matched against the executable name.
    public static let knownExecutables: Set<String> = [
        "node", "bun", "deno", "watchman", "watchmand", "esbuild", "rollup",
    ]

    /// Matched against any argument, so "node .../vite" is recognised as vite.
    public static let knownArgumentMarkers: [String] = [
        "vite", "next dev", "webpack", "nodemon", "turbopack", "metro",
        "uvicorn", "gunicorn", "flask run", "rails server", "puma",
        "GradleDaemon", "KotlinCompileDaemon", "dart:frontend_server",
    ]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.processes.compactMap { process -> Finding? in
            guard process.uid == snapshot.currentUID, process.pid != snapshot.ownPID,
                  let label = Self.label(for: process) else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(process.startedAt)
            let sustained = history.sustainedCPU(pid: process.pid, over: settings.sustainedCPUWindow)
            let idle = history.idleDuration(pid: process.pid, below: settings.idleCPUPercent)
            guard settings.crossesThreshold(age: age, sustainedCPU: sustained,
                                            idleFor: idle, memoryBytes: process.residentBytes) else { return nil }

            let cpu = history.cpuPercent(pid: process.pid) ?? 0
            return Finding(
                identity: "devserver:\(process.executablePath)|\(Self.signature(process))",
                kind: .devServer,
                title: label,
                detail: "\(Formatting.duration(age)) · \(Formatting.memory(process.residentBytes))",
                cpuPercent: cpu,
                memoryBytes: process.residentBytes,
                age: age,
                target: .processes([process.pid]),
                severity: cpu >= 50 ? .urgent : .notable)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// A human label like "vite" or "node · server.js", or nil when unrecognised.
    static func label(for process: ProcessSample) -> String? {
        let joined = process.arguments.joined(separator: " ")
        if let marker = knownArgumentMarkers.first(where: { joined.contains($0) }) {
            return marker.split(separator: " ").first.map(String.init) ?? marker
        }
        guard knownExecutables.contains(process.name) else { return nil }
        let script = process.arguments.dropFirst().first { !$0.hasPrefix("-") }
        guard let script else { return process.name }
        return "\(process.name) · \((script as NSString).lastPathComponent)"
    }

    /// Arguments minus volatile parts, so identity survives a restart.
    static func signature(_ process: ProcessSample) -> String {
        process.arguments.dropFirst()
            .filter { !$0.hasPrefix("--port") && Int($0) == nil }
            .joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run the dev-server tests and confirm they pass**

Run: `swift test --filter DevServerDetectorTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Write the failing orphan test**

`Tests/DetectorsTests/OrphanDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func flagsAReparentedProcessWithNoTerminal() {
    // The classic leftover: its terminal is gone, launchd adopted it.
    let processes = [Fixtures.process(
        pid: 7100, ppid: 1, path: "/opt/homebrew/bin/ffmpeg",
        args: ["ffmpeg", "-i", "in.mov", "out.mp4"], ageHours: 3, tty: false, rssMB: 200)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 70), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].kind == .orphan)
}

@Test func ignoresApplicationBundlesAdoptedByLaunchd() {
    // Every running .app has ppid 1. None of them are orphans.
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: Fixtures.defaultChrome()),
        history: Fixtures.history(Fixtures.defaultChrome(), cpuPercent: 80), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresProcessesThatStillHaveATerminal() {
    let processes = [Fixtures.process(
        pid: 7200, ppid: 1, path: "/opt/homebrew/bin/ffmpeg",
        args: ["ffmpeg"], ageHours: 3, tty: true)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 70), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresSystemAgentsUnderLaunchd() {
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: Fixtures.system()),
        history: Fixtures.history(Fixtures.system(), cpuPercent: 5), settings: Settings())

    #expect(findings.isEmpty)
}

@Test func ignoresProcessesInSystemDirectories() {
    let processes = [Fixtures.process(
        pid: 7300, ppid: 1, path: "/usr/libexec/trustd", args: ["trustd"], ageHours: 40)]
    let findings = OrphanDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 0), settings: Settings())

    #expect(findings.isEmpty)
}
```

- [ ] **Step 6: Run it and confirm it fails**

Run: `swift test --filter OrphanDetectorTests`
Expected: `cannot find 'OrphanDetector' in scope`.

- [ ] **Step 7: Write `Sources/Detectors/OrphanDetector.swift`**

```swift
import Foundation
import ProcessKit

/// A command-line process whose parent died and whose terminal is gone. macOS
/// reparents it to launchd, where nothing will ever clean it up.
public struct OrphanDetector: Detector {
    public let kind: FindingKind = .orphan
    public init() {}

    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/usr/bin/"]

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.processes.compactMap { process -> Finding? in
            guard process.uid == snapshot.currentUID,
                  process.pid != snapshot.ownPID,
                  process.ppid == 1,
                  !process.hasControllingTTY,
                  !Self.isApplicationBundle(process),
                  !Self.isSystemPath(process.executablePath),
                  !IsolatedBrowserDetector.isBrowser(process)   // the browser detector owns those
            else { return nil }

            let age = snapshot.takenAt.timeIntervalSince(process.startedAt)
            let cpu = history.cpuPercent(pid: process.pid) ?? 0
            return Finding(
                identity: "orphan:\(process.executablePath)",
                kind: .orphan,
                title: "\(process.name) · no terminal",
                detail: "\(Formatting.duration(age)) · adopted by launchd",
                cpuPercent: cpu,
                memoryBytes: process.residentBytes,
                age: age,
                target: .processes([process.pid]),
                severity: cpu >= 50 ? .urgent : .notable)
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// Anything inside a .app is a normal application, not a stray command.
    static func isApplicationBundle(_ process: ProcessSample) -> Bool {
        process.executablePath.contains(".app/Contents/")
    }

    static func isSystemPath(_ path: String) -> Bool {
        systemPrefixes.contains { path.hasPrefix($0) }
    }
}
```

- [ ] **Step 8: Run the orphan tests and confirm they pass**

Run: `swift test --filter OrphanDetectorTests`
Expected: 5 tests PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/Detectors/OrphanDetector.swift Sources/Detectors/DevServerDetector.swift Tests/DetectorsTests
git commit -m "Detect orphaned processes and forgotten dev servers"
```

---

### Task 8: Container and simulator detectors

**Files:**
- Create: `Sources/Detectors/ContainerDetector.swift`, `Sources/Detectors/SimulatorDetector.swift`, `Tests/DetectorsTests/ContainerDetectorTests.swift`, `Tests/DetectorsTests/SimulatorDetectorTests.swift`

**Interfaces:**
- Consumes: `ContainerSample` and `SimulatorSample` on `Snapshot`, plus the Task 6 types.
- Produces: `ContainerDetector`, `SimulatorDetector`, emitting `.container(id)` and `.simulator(udid)` targets for Task 11.

Containers and simulators have no per-process CPU attribution in the snapshot, so age is their only threshold. That is the right rule for them: a container that has been up for a day is exactly what the app is for.

- [ ] **Step 1: Write the failing container test**

`Tests/DetectorsTests/ContainerDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import Detectors
import ProcessKit

private func container(name: String, hoursUp: Double) -> ContainerSample {
    ContainerSample(id: "id-\(name)", name: name, image: "\(name):latest",
                    startedAt: Fixtures.now.addingTimeInterval(-hoursUp * 3600))
}

@Test func flagsEachLongRunningContainer() {
    let snapshot = Fixtures.snapshot(
        processes: [], containers: [container(name: "selene-api", hoursUp: 22),
                                    container(name: "selene-postgres", hoursUp: 22)])
    let findings = ContainerDetector().findings(in: snapshot, history: History(), settings: Settings())

    #expect(findings.count == 2)
    #expect(findings.allSatisfy { $0.kind == .container })
    #expect(findings[0].target == .container("id-selene-api") || findings[0].target == .container("id-selene-postgres"))
}

@Test func ignoresContainersStartedMinutesAgo() {
    let snapshot = Fixtures.snapshot(processes: [], containers: [container(name: "fresh", hoursUp: 0.1)])
    #expect(ContainerDetector().findings(in: snapshot, history: History(), settings: Settings()).isEmpty)
}

@Test func containerIdentityUsesTheNameSoItSurvivesRecreation() {
    let snapshot = Fixtures.snapshot(processes: [], containers: [container(name: "selene-api", hoursUp: 22)])
    let findings = ContainerDetector().findings(in: snapshot, history: History(), settings: Settings())
    #expect(findings[0].identity == "container:selene-api")
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter ContainerDetectorTests`
Expected: `cannot find 'ContainerDetector' in scope`.

- [ ] **Step 3: Write `Sources/Detectors/ContainerDetector.swift`**

```swift
import Foundation
import ProcessKit

/// Containers left up from a project you stopped working on. The Engine API has
/// no cheap per-container CPU reading, so age carries the decision.
public struct ContainerDetector: Detector {
    public let kind: FindingKind = .container
    public init() {}

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.containers.compactMap { container -> Finding? in
            let age = snapshot.takenAt.timeIntervalSince(container.startedAt)
            guard age >= settings.minimumAge else { return nil }

            return Finding(
                identity: "container:\(container.name)",
                kind: .container,
                title: "\(container.name) · container",
                detail: "up \(Formatting.duration(age)) · \(container.image)",
                cpuPercent: 0,
                memoryBytes: 0,
                age: age,
                target: .container(container.id),
                severity: .notable)
        }
        .sorted { $0.age > $1.age }
    }
}
```

- [ ] **Step 4: Run the container tests and confirm they pass**

Run: `swift test --filter ContainerDetectorTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Write the failing simulator test**

`Tests/DetectorsTests/SimulatorDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func flagsASimulatorBootedHoursAgo() {
    let simulator = SimulatorSample(id: "A1B2", name: "iPhone 17 Pro", runtime: "iOS 26.5",
                                    bootedAt: Fixtures.now.addingTimeInterval(-5 * 3600))
    let findings = SimulatorDetector().findings(
        in: Fixtures.snapshot(processes: [], simulators: [simulator]),
        history: History(), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].target == .simulator("A1B2"))
    #expect(findings[0].title.contains("iPhone 17 Pro"))
}

@Test func ignoresASimulatorBootedMinutesAgo() {
    let simulator = SimulatorSample(id: "A1B2", name: "iPhone 17 Pro", runtime: "iOS 26.5",
                                    bootedAt: Fixtures.now.addingTimeInterval(-120))
    #expect(SimulatorDetector().findings(
        in: Fixtures.snapshot(processes: [], simulators: [simulator]),
        history: History(), settings: Settings()).isEmpty)
}

@Test func flagsASimulatorWithAnUnknownBootTime() {
    // Boot time could not be resolved; being booted at all is still worth showing.
    let simulator = SimulatorSample(id: "A1B2", name: "iPhone 17 Pro", runtime: "iOS 26.5", bootedAt: nil)
    let findings = SimulatorDetector().findings(
        in: Fixtures.snapshot(processes: [], simulators: [simulator]),
        history: History(), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].detail.contains("booted"))
}
```

- [ ] **Step 6: Run it and confirm it fails**

Run: `swift test --filter SimulatorDetectorTests`
Expected: `cannot find 'SimulatorDetector' in scope`.

- [ ] **Step 7: Write `Sources/Detectors/SimulatorDetector.swift`**

```swift
import Foundation
import ProcessKit

/// A booted simulator holds a lot of memory and keeps a device's worth of
/// daemons alive. Long after the build you were testing, it is still there.
public struct SimulatorDetector: Detector {
    public let kind: FindingKind = .simulator
    public init() {}

    public func findings(in snapshot: Snapshot, history: History, settings: Settings) -> [Finding] {
        snapshot.simulators.compactMap { simulator -> Finding? in
            let age = simulator.bootedAt.map { snapshot.takenAt.timeIntervalSince($0) }
            if let age, age < settings.minimumAge { return nil }

            return Finding(
                identity: "simulator:\(simulator.id)",
                kind: .simulator,
                title: "\(simulator.name) · simulator",
                detail: age.map { "booted \(Formatting.duration($0)) ago · \(simulator.runtime)" }
                    ?? "booted · \(simulator.runtime)",
                cpuPercent: 0,
                memoryBytes: 0,
                age: age ?? 0,
                target: .simulator(simulator.id),
                severity: .notable)
        }
        .sorted { $0.age > $1.age }
    }
}
```

- [ ] **Step 8: Run the simulator tests and confirm they pass**

Run: `swift test --filter SimulatorDetectorTests`
Expected: 3 tests PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/Detectors/ContainerDetector.swift Sources/Detectors/SimulatorDetector.swift Tests/DetectorsTests
git commit -m "Detect long-running containers and booted simulators"
```

---

### Task 9: Detector engine

**Files:**
- Create: `Sources/Detectors/DetectorEngine.swift`, `Tests/DetectorsTests/DetectorEngineTests.swift`

**Interfaces:**
- Consumes: every detector from Tasks 6 to 8.
- Produces: `DetectorEngine.evaluate(snapshot:history:settings:excluded:) -> EngineResult`, where `EngineResult` has `findings: [Finding]` and `alsoHot: [HotProcess]`. Task 12's store calls exactly this.

- [ ] **Step 1: Write the failing test**

`Tests/DetectorsTests/DetectorEngineTests.swift`:

```swift
import Testing
import Foundation
@testable import Detectors
import ProcessKit

@Test func collectsFindingsFromEveryDetectorSortedBySeverityThenCPU() {
    let processes = Fixtures.automationChrome() + Fixtures.defaultChrome() + Fixtures.system() + [
        Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node",
                         args: ["node", "vite"], ageHours: 9)]
    let containers = [ContainerSample(id: "c1", name: "selene-api", image: "api:latest",
                                      startedAt: Fixtures.now.addingTimeInterval(-22 * 3600))]
    let snapshot = Fixtures.snapshot(processes: processes, containers: containers)
    let result = DetectorEngine().evaluate(
        snapshot: snapshot, history: Fixtures.history(processes, cpuPercent: 30),
        settings: Settings(), excluded: [])

    #expect(result.findings.contains { $0.kind == .isolatedBrowser })
    #expect(result.findings.contains { $0.kind == .devServer })
    #expect(result.findings.contains { $0.kind == .container })
    #expect(result.findings.first!.severity >= result.findings.last!.severity)
}

@Test func dropsExcludedIdentities() {
    let processes = Fixtures.automationChrome()
    let snapshot = Fixtures.snapshot(processes: processes)
    let history = Fixtures.history(processes, cpuPercent: 30)
    let all = DetectorEngine().evaluate(snapshot: snapshot, history: history, settings: Settings(), excluded: [])
    let excludedIdentity = all.findings[0].identity

    let filtered = DetectorEngine().evaluate(
        snapshot: snapshot, history: history, settings: Settings(), excluded: [excludedIdentity])

    #expect(filtered.findings.isEmpty)
}

@Test func neverEmitsTwoFindingsForTheSameProcess() {
    // An automation browser is orphaned AND isolated. It must appear once.
    let processes = Fixtures.automationChrome()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 30))

    let pids = result.findings.flatMap { finding -> [Int32] in
        if case .processes(let list) = finding.target { return list }
        return []
    }
    #expect(pids.count == Set(pids).count)
}

@Test func alsoHotListsHeavyProcessesThatAreNotFindings() {
    let processes = Fixtures.defaultChrome() + Fixtures.system()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 45))

    #expect(result.findings.isEmpty)
    #expect(result.alsoHot.contains { $0.name.contains("Google Chrome") })
    #expect(result.alsoHot.allSatisfy { $0.cpuPercent >= 20 })
    #expect(result.alsoHot.count <= 5)
}

@Test func alsoHotExcludesProcessesAlreadySurfacedAsFindings() {
    let processes = Fixtures.automationChrome()
    let result = DetectorEngine().evaluate(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 60))

    #expect(!result.findings.isEmpty)
    #expect(result.alsoHot.isEmpty)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter DetectorEngineTests`
Expected: `cannot find 'DetectorEngine' in scope`.

- [ ] **Step 3: Write `Sources/Detectors/DetectorEngine.swift`**

```swift
import Foundation
import ProcessKit

public struct HotProcess: Sendable, Identifiable, Equatable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public var id: Int32 { pid }
}

public struct EngineResult: Sendable, Equatable {
    /// Actionable. Every one of these has a stop target.
    public let findings: [Finding]
    /// Informational only. Deliberately has no target, so the UI cannot offer
    /// to stop WindowServer.
    public let alsoHot: [HotProcess]

    public static let empty = EngineResult(findings: [], alsoHot: [])
}

public struct DetectorEngine: Sendable {
    private let detectors: [any Detector]
    private let hotThreshold: Double
    private let hotLimit: Int

    public init(detectors: [any Detector] = DetectorEngine.defaultDetectors,
                hotThreshold: Double = 20, hotLimit: Int = 5) {
        self.detectors = detectors
        self.hotThreshold = hotThreshold
        self.hotLimit = hotLimit
    }

    /// Order matters: the first detector to claim a pid owns it.
    public static var defaultDetectors: [any Detector] {
        [IsolatedBrowserDetector(), ContainerDetector(), SimulatorDetector(),
         DevServerDetector(), OrphanDetector()]
    }

    public func evaluate(snapshot: Snapshot, history: History,
                         settings: Settings, excluded: Set<String>) -> EngineResult {
        var claimed = Set<Int32>()
        var findings: [Finding] = []

        for detector in detectors {
            for finding in detector.findings(in: snapshot, history: history, settings: settings) {
                guard !excluded.contains(finding.identity) else { continue }
                if case .processes(let pids) = finding.target {
                    guard claimed.isDisjoint(with: pids) else { continue }
                    claimed.formUnion(pids)
                }
                findings.append(finding)
            }
        }

        findings.sort {
            $0.severity == $1.severity ? $0.cpuPercent > $1.cpuPercent : $0.severity > $1.severity
        }

        let hot = snapshot.processes
            .filter { !claimed.contains($0.pid) }
            .compactMap { process -> HotProcess? in
                guard let cpu = history.cpuPercent(pid: process.pid), cpu >= hotThreshold else { return nil }
                return HotProcess(pid: process.pid, name: process.name, cpuPercent: cpu)
            }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(hotLimit)

        return EngineResult(findings: findings, alsoHot: Array(hot))
    }

    /// Convenience for tests and callers with default settings.
    public func evaluate(in snapshot: Snapshot, history: History) -> EngineResult {
        evaluate(snapshot: snapshot, history: history, settings: Settings(), excluded: [])
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter DetectorEngineTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: every test from Tasks 1 to 9 PASSES.

- [ ] **Step 6: Commit**

```bash
git add Sources/Detectors/DetectorEngine.swift Tests/DetectorsTests/DetectorEngineTests.swift
git commit -m "Run all detectors, deduplicate claims, and collect also-hot processes"
```

---

### Task 10: Safety guard

The guard is the last line before a signal is sent. It repeats checks the detectors already make, on purpose: a bug in a detector must not become a killed WindowServer.

**Files:**
- Create: `Sources/Actions/SafetyGuard.swift`, `Tests/ActionsTests/SafetyGuardTests.swift`, `Tests/ActionsTests/Fixtures.swift`

**Interfaces:**
- Consumes: `Finding`, `StopTarget`, `Snapshot`, `ProcessSample`.
- Produces: `SafetyGuard.vet(_:in:) throws`, throwing `SafetyError`. Task 11's coordinator calls it before every stop.

- [ ] **Step 1: Copy the fixture helper into the Actions test target**

`Tests/ActionsTests/Fixtures.swift` — the same content as `Tests/DetectorsTests/Fixtures.swift` from Task 6, with `@testable import Detectors` kept and the `history` helper removed (Actions tests do not need it). Duplicating a few dozen lines of test data across two test targets is cheaper than a shared fixture target and keeps each suite readable on its own.

- [ ] **Step 2: Write the failing test**

`Tests/ActionsTests/SafetyGuardTests.swift`:

```swift
import Testing
import Foundation
@testable import Actions
import Detectors
import ProcessKit

private func finding(target: StopTarget, kind: FindingKind = .devServer) -> Finding {
    Finding(identity: "test", kind: kind, title: "t", detail: "d", cpuPercent: 10,
            memoryBytes: 0, age: 10_000, target: target, severity: .notable)
}

@Test func allowsAnOrdinaryUserProcess() throws {
    let process = Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node", args: ["node"], ageHours: 5)
    let snapshot = Fixtures.snapshot(processes: [process])
    try SafetyGuard().vet(finding(target: .processes([4100])), in: snapshot)
}

@Test func refusesProtectedSystemProcessesByName() {
    let snapshot = Fixtures.snapshot(processes: Fixtures.system())
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([164])), in: snapshot)   // WindowServer
    }
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([418])), in: snapshot)   // Finder
    }
}

@Test func refusesLowPIDs() {
    let process = Fixtures.process(pid: 42, path: "/opt/homebrew/bin/node", args: ["node"], ageHours: 5)
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([42])), in: Fixtures.snapshot(processes: [process]))
    }
}

@Test func refusesProcessesOwnedByAnotherUser() {
    let process = Fixtures.process(pid: 4100, path: "/opt/homebrew/bin/node", args: ["node"],
                                   ageHours: 5, uid: 0)
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([4100])), in: Fixtures.snapshot(processes: [process]))
    }
}

@Test func refusesToStopItself() {
    let process = Fixtures.process(pid: 999, path: "/Applications/Still Running.app/Contents/MacOS/StillRunning",
                                   args: ["StillRunning"], ageHours: 1)
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([999])), in: Fixtures.snapshot(processes: [process]))
    }
}

@Test func refusesTheUsersDefaultProfileBrowser() {
    // Defence in depth: even if a detector produced this, the guard stops it.
    let snapshot = Fixtures.snapshot(processes: Fixtures.defaultChrome())
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([14914]), kind: .isolatedBrowser), in: snapshot)
    }
}

@Test func allowsAnAutomationProfileBrowser() throws {
    let snapshot = Fixtures.snapshot(processes: Fixtures.automationChrome())
    try SafetyGuard().vet(finding(target: .processes([23947]), kind: .isolatedBrowser), in: snapshot)
}

@Test func refusesTheWholeGroupWhenOneMemberIsProtected() {
    let snapshot = Fixtures.snapshot(processes: Fixtures.automationChrome() + Fixtures.system())
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([23947, 164])), in: snapshot)
    }
}

@Test func refusesAnUnknownPID() {
    #expect(throws: SafetyError.self) {
        try SafetyGuard().vet(finding(target: .processes([12345])), in: Fixtures.snapshot(processes: []))
    }
}

@Test func allowsContainerAndSimulatorTargets() throws {
    let snapshot = Fixtures.snapshot(processes: [])
    try SafetyGuard().vet(finding(target: .container("abc"), kind: .container), in: snapshot)
    try SafetyGuard().vet(finding(target: .simulator("A1B2"), kind: .simulator), in: snapshot)
}
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `swift test --filter SafetyGuardTests`
Expected: `cannot find 'SafetyGuard' in scope`.

- [ ] **Step 4: Write `Sources/Actions/SafetyGuard.swift`**

```swift
import Foundation
import Detectors
import ProcessKit

public enum SafetyError: Error, Equatable {
    case protectedProcess(pid: Int32, reason: String)
    case unknownProcess(pid: Int32)
}

/// The last check before a signal is sent. It deliberately repeats work the
/// detectors already do: a detector bug must not be able to kill the session.
public struct SafetyGuard: Sendable {
    public static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Finder", "Dock",
        "SystemUIServer", "coreaudiod", "logind", "securityd", "opendirectoryd",
        "distnoted", "cfprefsd", "mds", "mds_stores", "Spotlight",
    ]
    public static let minimumPID: Int32 = 100

    public init() {}

    public func vet(_ finding: Finding, in snapshot: Snapshot) throws {
        guard case .processes(let pids) = finding.target else { return }   // containers and simulators are safe by construction
        for pid in pids {
            guard let process = snapshot.process(pid: pid) else { throw SafetyError.unknownProcess(pid: pid) }
            if let reason = protectionReason(for: process, in: snapshot) {
                throw SafetyError.protectedProcess(pid: pid, reason: reason)
            }
        }
    }

    /// Why this process may never be stopped, or nil when it may.
    public func protectionReason(for process: ProcessSample, in snapshot: Snapshot) -> String? {
        if process.pid < Self.minimumPID { return "system process" }
        if process.pid == snapshot.ownPID { return "Still Running itself" }
        if process.uid != snapshot.currentUID { return "owned by another user" }
        if Self.protectedNames.contains(process.name) { return "critical to the session" }
        if process.executablePath.contains("Still Running.app") { return "Still Running itself" }
        if IsolatedBrowserDetector.isBrowser(process),
           IsolatedBrowserDetector.isolationSignature(process) == nil {
            return "your browser, with your tabs"
        }
        return nil
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --filter SafetyGuardTests`
Expected: 10 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Actions/SafetyGuard.swift Tests/ActionsTests
git commit -m "Guard every stop against protected processes"
```

---

### Task 11: Stoppers and the stop coordinator

**Files:**
- Create: `Sources/Actions/Stopper.swift`, `Sources/Actions/SignalStopper.swift`, `Sources/Actions/ContainerStopper.swift`, `Sources/Actions/SimulatorStopper.swift`, `Sources/Actions/StopCoordinator.swift`, `Tests/ActionsTests/StopCoordinatorTests.swift`

**Interfaces:**
- Consumes: `SafetyGuard`, `DockerClient`, `SimulatorControl`, `Finding`.
- Produces: `StopCoordinator.stop(_:in:) async -> StopOutcome` and `.forceStop(_:in:) async -> StopOutcome`. Task 12's store is the only caller.

- [ ] **Step 1: Write the failing test**

`Tests/ActionsTests/StopCoordinatorTests.swift`:

```swift
import Testing
import Foundation
@testable import Actions
import Detectors
import ProcessKit

final class RecordingSignaller: ProcessSignalling, @unchecked Sendable {
    var sent: [(pid: Int32, signal: Int32)] = []
    var aliveAfterTerm = false
    func send(_ signal: Int32, to pid: Int32) throws { sent.append((pid, signal)) }
    func isAlive(_ pid: Int32) -> Bool { aliveAfterTerm }
}

final class RecordingContainers: ContainerStopping, @unchecked Sendable {
    var stopped: [String] = []
    func stop(id: String) async throws { stopped.append(id) }
}

final class RecordingSimulators: SimulatorStopping, @unchecked Sendable {
    var shutdown: [String] = []
    func shutdown(udid: String) async throws { self.shutdown.append(udid) }
}

private func makeCoordinator() -> (StopCoordinator, RecordingSignaller, RecordingContainers, RecordingSimulators) {
    let signaller = RecordingSignaller(), containers = RecordingContainers(), simulators = RecordingSimulators()
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
    let processes = Fixtures.automationChrome()
    let outcome = await coordinator.stop(finding(.processes([23947, 23953, 35770])),
                                         in: Fixtures.snapshot(processes: processes))

    #expect(outcome == .stopped)
    #expect(signaller.sent.first?.pid == 23947)
    #expect(signaller.sent.allSatisfy { $0.signal == SIGTERM })
}

@Test func neverSendsSIGKILLOnAPlainStop() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    signaller.aliveAfterTerm = true
    let processes = Fixtures.automationChrome()
    let outcome = await coordinator.stop(finding(.processes([23947])),
                                         in: Fixtures.snapshot(processes: processes))

    #expect(outcome == .stillRunning)
    #expect(!signaller.sent.contains { $0.signal == SIGKILL })
}

@Test func forceStopSendsSIGKILL() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    let processes = Fixtures.automationChrome()
    _ = await coordinator.forceStop(finding(.processes([23947])),
                                    in: Fixtures.snapshot(processes: processes))

    #expect(signaller.sent.contains { $0.signal == SIGKILL })
}

@Test func refusesToSignalAProtectedProcess() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    let outcome = await coordinator.stop(finding(.processes([164])),
                                         in: Fixtures.snapshot(processes: Fixtures.system()))

    #expect(outcome == .refused(reason: "critical to the session"))
    #expect(signaller.sent.isEmpty)
}

@Test func forceStopAlsoRefusesProtectedProcesses() async {
    let (coordinator, signaller, _, _) = makeCoordinator()
    let outcome = await coordinator.forceStop(finding(.processes([164])),
                                              in: Fixtures.snapshot(processes: Fixtures.system()))

    #expect(outcome == .refused(reason: "critical to the session"))
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
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter StopCoordinatorTests`
Expected: `cannot find 'StopCoordinator' in scope`.

- [ ] **Step 3: Write `Sources/Actions/Stopper.swift`**

```swift
import Foundation

public enum StopOutcome: Sendable, Equatable {
    case stopped
    /// Signalled, but still alive after the grace period. The UI offers force quit.
    case stillRunning
    case refused(reason: String)
    case failed(String)
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
```

- [ ] **Step 4: Write `Sources/Actions/SignalStopper.swift`**

```swift
import Darwin
import Foundation

public struct SignalStopper: ProcessSignalling {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) throws {
        guard kill(pid, signal) == 0 || errno == ESRCH else {
            throw StopError.signalFailed(pid: pid, code: errno)
        }
    }

    /// signal 0 tests for existence without delivering anything.
    public func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}

public enum StopError: Error, Equatable {
    case signalFailed(pid: Int32, code: Int32)
}
```

- [ ] **Step 5: Write `Sources/Actions/ContainerStopper.swift` and `Sources/Actions/SimulatorStopper.swift`**

```swift
// ContainerStopper.swift
import Foundation
import DockerClient

public struct ContainerStopper: ContainerStopping {
    private let client: DockerClient?
    public init(client: DockerClient? = DockerClient.discover()) { self.client = client }

    public func stop(id: String) async throws {
        guard let client else { throw StopError.signalFailed(pid: 0, code: ENOENT) }
        try await client.stop(id: id)
    }
}
```

```swift
// SimulatorStopper.swift
import Foundation
import SimulatorSource

public struct SimulatorStopper: SimulatorStopping {
    private let control: any SimulatorControl
    public init(control: any SimulatorControl = SimctlSource()) { self.control = control }

    public func shutdown(udid: String) async throws {
        try await control.shutdown(udid: udid)
    }
}
```

- [ ] **Step 6: Write `Sources/Actions/StopCoordinator.swift`**

```swift
import Darwin
import Foundation
import Detectors
import ProcessKit

/// Routes a finding to the right mechanism, and enforces the guard on the way.
/// Every stop in the app goes through here — there is no other path to a signal.
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
        self.signaller = signaller; self.containers = containers
        self.simulators = simulators; self.gracePeriod = gracePeriod
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
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `swift test --filter StopCoordinatorTests`
Expected: 7 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/Actions Tests/ActionsTests/StopCoordinatorTests.swift
git commit -m "Route stops through a coordinator that enforces the safety guard"
```

---

### Task 12: Live snapshot assembly

**Files:**
- Create: `Sources/StillRunningCore/LiveSnapshotSource.swift`, `Tests/StillRunningCoreTests/LiveSnapshotSourceTests.swift`

**Interfaces:**
- Consumes: `LiveProcessSource`, `DockerClient`, `SimulatorControl`.
- Produces: `LiveSnapshotSource: SnapshotSource`, whose `sample()` merges processes, containers, and simulators, resolving each simulator's boot time from its `launchd_sim` process. Task 13's store owns one.

- [ ] **Step 1: Write the failing test**

`Tests/StillRunningCoreTests/LiveSnapshotSourceTests.swift`:

```swift
import Testing
import Foundation
@testable import StillRunningCore
import ProcessKit
import SimulatorSource

private struct StubSimulators: SimulatorControl {
    let devices: [BootedSimulator]
    func booted() async throws -> [BootedSimulator] { devices }
    func shutdown(udid: String) async throws {}
}

@Test func resolvesSimulatorBootTimeFromItsLaunchdProcess() {
    let udid = "A1B2-C3D4"
    let bootTime = Date(timeIntervalSince1970: 1_785_000_000)
    let launchdSim = ProcessSample(
        pid: 8100, ppid: 1, uid: 501,
        executablePath: "/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/sbin/launchd_sim",
        arguments: ["launchd_sim", "/Users/x/Library/Developer/CoreSimulator/Devices/\(udid)/data"],
        startedAt: bootTime, hasControllingTTY: false, cpuTimeNanos: 0, residentBytes: 0)

    let resolved = LiveSnapshotSource.bootTime(
        forSimulator: udid, in: [launchdSim])

    #expect(resolved == bootTime)
}

@Test func returnsNilBootTimeWhenNoLaunchdProcessMatches() {
    #expect(LiveSnapshotSource.bootTime(forSimulator: "A1B2", in: []) == nil)
}

@Test func liveSampleIncludesTheCurrentProcessAndIsInternallyConsistent() async {
    let source = LiveSnapshotSource(simulators: StubSimulators(devices: []))
    let snapshot = await source.sample()

    #expect(snapshot.ownPID == ProcessInfo.processInfo.processIdentifier)
    #expect(snapshot.currentUID == getuid())
    #expect(snapshot.processes.contains { $0.pid == snapshot.ownPID })
    #expect(snapshot.takenAt.timeIntervalSinceNow > -5)
}

@Test func aFailingDockerDaemonDoesNotBreakTheSnapshot() async {
    // No socket at this path: containers must come back empty, not throw.
    let source = LiveSnapshotSource(docker: nil, simulators: StubSimulators(devices: []))
    let snapshot = await source.sample()

    #expect(snapshot.containers.isEmpty)
    #expect(!snapshot.processes.isEmpty)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter LiveSnapshotSourceTests`
Expected: `cannot find 'LiveSnapshotSource' in scope`.

- [ ] **Step 3: Write `Sources/StillRunningCore/LiveSnapshotSource.swift`**

```swift
import Darwin
import Foundation
import DockerClient
import ProcessKit
import SimulatorSource

/// Assembles one `Snapshot` from all three sources. Every source failure
/// degrades to an empty list: a missing Docker daemon must never stop the app
/// from reporting processes.
public struct LiveSnapshotSource: SnapshotSource {
    private let processes: LiveProcessSource
    private let docker: DockerClient?
    private let simulators: any SimulatorControl

    public init(processes: LiveProcessSource = LiveProcessSource(),
                docker: DockerClient? = DockerClient.discover(),
                simulators: any SimulatorControl = SimctlSource()) {
        self.processes = processes; self.docker = docker; self.simulators = simulators
    }

    public func sample() async -> Snapshot {
        let samples = processes.processes()

        async let containersTask = (try? await docker?.containers()) ?? []
        async let devicesTask = (try? await simulators.booted()) ?? []
        let (containers, devices) = await (containersTask, devicesTask)

        return Snapshot(
            takenAt: Date(),
            processes: samples,
            containers: containers.map {
                ContainerSample(id: $0.id, name: $0.displayName, image: $0.image, startedAt: $0.created)
            },
            simulators: devices.map {
                SimulatorSample(id: $0.udid, name: $0.name, runtime: $0.runtime,
                                bootedAt: Self.bootTime(forSimulator: $0.udid, in: samples))
            },
            currentUID: getuid(),
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    /// simctl does not report boot time, but every booted device runs a
    /// launchd_sim whose arguments carry the device's UDID.
    static func bootTime(forSimulator udid: String, in processes: [ProcessSample]) -> Date? {
        processes.first { process in
            process.name == "launchd_sim" && process.arguments.contains { $0.contains(udid) }
        }?.startedAt
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter LiveSnapshotSourceTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StillRunningCore/LiveSnapshotSource.swift Tests/StillRunningCoreTests
git commit -m "Assemble live snapshots from processes, containers, and simulators"
```

---

### Task 13: Exclusions, settings persistence, and the store

**Files:**
- Create: `Sources/StillRunningCore/Exclusions.swift`, `Sources/StillRunningCore/SettingsStore.swift`, `Sources/StillRunningCore/Store.swift`, `Tests/StillRunningCoreTests/ExclusionsTests.swift`, `Tests/StillRunningCoreTests/StoreTests.swift`

**Interfaces:**
- Consumes: `LiveSnapshotSource`, `DetectorEngine`, `StopCoordinator`, `History`, `Settings`.
- Produces: `@MainActor @Observable final class Store` with `findings`, `alsoHot`, `isBusy`, `refresh()`, `stop(_:)`, `forceStop(_:)`, `keep(_:)`, `setCadence(_:)`. The UI in Task 14 binds to exactly these.

- [ ] **Step 1: Write the failing exclusions test**

`Tests/StillRunningCoreTests/ExclusionsTests.swift`:

```swift
import Testing
import Foundation
@testable import StillRunningCore

@Test func storesAndRecallsExclusions() {
    let defaults = UserDefaults(suiteName: "exclusions-test-1")!
    defaults.removePersistentDomain(forName: "exclusions-test-1")
    var exclusions = Exclusions(defaults: defaults)

    exclusions.add("browser:/tmp/claude-cdp-prof")

    #expect(exclusions.contains("browser:/tmp/claude-cdp-prof"))
    #expect(Exclusions(defaults: defaults).contains("browser:/tmp/claude-cdp-prof"))
}

@Test func removesAnExclusion() {
    let defaults = UserDefaults(suiteName: "exclusions-test-2")!
    defaults.removePersistentDomain(forName: "exclusions-test-2")
    var exclusions = Exclusions(defaults: defaults)

    exclusions.add("container:selene-api")
    exclusions.remove("container:selene-api")

    #expect(!exclusions.contains("container:selene-api"))
}

@Test func settingsRoundTripThroughDefaults() {
    let defaults = UserDefaults(suiteName: "settings-test-1")!
    defaults.removePersistentDomain(forName: "settings-test-1")
    let store = SettingsStore(defaults: defaults)

    var settings = store.settings
    settings.minimumAge = 4 * 3600
    settings.notifyAfter = 8 * 3600
    store.settings = settings

    #expect(SettingsStore(defaults: defaults).settings.minimumAge == 4 * 3600)
    #expect(SettingsStore(defaults: defaults).settings.notifyAfter == 8 * 3600)
}

@Test func settingsFallBackToDefaultsWhenStorageIsEmpty() {
    let defaults = UserDefaults(suiteName: "settings-test-2")!
    defaults.removePersistentDomain(forName: "settings-test-2")

    #expect(SettingsStore(defaults: defaults).settings == Settings())
}
```

Note: `Settings` comes from `Detectors`; add `import Detectors` at the top of this test file.

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter ExclusionsTests`
Expected: `cannot find 'Exclusions' in scope`.

- [ ] **Step 3: Write `Sources/StillRunningCore/Exclusions.swift` and `SettingsStore.swift`**

```swift
// Exclusions.swift
import Foundation

/// "Keep this" list. Matches on finding identity, which is derived from stable
/// attributes (profile path, container name, simulator UDID) rather than pids,
/// so an exclusion survives a restart of the excluded thing.
public struct Exclusions: Sendable {
    private let defaults: UserDefaults
    private let key = "excludedIdentities"
    private var cache: Set<String>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cache = Set(defaults.stringArray(forKey: key) ?? [])
    }

    public var identities: Set<String> { cache }
    public func contains(_ identity: String) -> Bool { cache.contains(identity) }

    public mutating func add(_ identity: String) {
        cache.insert(identity)
        defaults.set(Array(cache), forKey: key)
    }

    public mutating func remove(_ identity: String) {
        cache.remove(identity)
        defaults.set(Array(cache), forKey: key)
    }
}
```

```swift
// SettingsStore.swift
import Foundation
import Detectors

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "settings"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var settings: Settings {
        get {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode(Settings.self, from: data)
            else { return Settings() }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 4: Run the exclusions tests and confirm they pass**

Run: `swift test --filter ExclusionsTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Write the failing store test**

`Tests/StillRunningCoreTests/StoreTests.swift`:

```swift
import Testing
import Foundation
@testable import StillRunningCore
import Actions
import Detectors
import ProcessKit

private struct ScriptedSource: SnapshotSource {
    let snapshots: [Snapshot]
    let index: Counter
    final class Counter: @unchecked Sendable { var value = 0 }
    func sample() async -> Snapshot {
        let snapshot = snapshots[min(index.value, snapshots.count - 1)]
        index.value += 1
        return snapshot
    }
}

private final class SpyStopper: Stopping, @unchecked Sendable {
    var stopped: [String] = []
    var forced: [String] = []
    var outcome: StopOutcome = .stopped
    func stop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome {
        stopped.append(finding.identity); return outcome
    }
    func forceStop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome {
        forced.append(finding.identity); return .stopped
    }
}

private func automationSnapshots() -> [Snapshot] {
    // Two samples one minute apart so History can compute a rate.
    let base = TestFixtures.automationChrome()
    return [TestFixtures.snapshot(processes: base, at: TestFixtures.now),
            TestFixtures.snapshot(processes: TestFixtures.advance(base, cpuPercent: 60, seconds: 60),
                                  at: TestFixtures.now.addingTimeInterval(60))]
}

@MainActor
@Test func refreshPopulatesFindings() async {
    let store = Store(source: ScriptedSource(snapshots: automationSnapshots(), index: .init()),
                      stopper: SpyStopper(), defaults: makeCleanDefaults("store-1"))
    await store.refresh()
    await store.refresh()

    #expect(store.findings.count == 1)
    #expect(store.findings[0].kind == .isolatedBrowser)
}

@MainActor
@Test func stopDelegatesToTheStopperAndRefreshes() async {
    let spy = SpyStopper()
    let store = Store(source: ScriptedSource(snapshots: automationSnapshots(), index: .init()),
                      stopper: spy, defaults: makeCleanDefaults("store-2"))
    await store.refresh(); await store.refresh()
    await store.stop(store.findings[0])

    #expect(spy.stopped.count == 1)
}

@MainActor
@Test func aStillRunningOutcomeMarksTheFindingAsForceable() async {
    let spy = SpyStopper()
    spy.outcome = .stillRunning
    let store = Store(source: ScriptedSource(snapshots: automationSnapshots(), index: .init()),
                      stopper: spy, defaults: makeCleanDefaults("store-3"))
    await store.refresh(); await store.refresh()
    let identity = store.findings[0].identity
    await store.stop(store.findings[0])

    #expect(store.forceableIdentities.contains(identity))
}

@MainActor
@Test func keepExcludesAFindingFromLaterRefreshes() async {
    let store = Store(source: ScriptedSource(snapshots: automationSnapshots(), index: .init()),
                      stopper: SpyStopper(), defaults: makeCleanDefaults("store-4"))
    await store.refresh(); await store.refresh()
    store.keep(store.findings[0])
    await store.refresh()

    #expect(store.findings.isEmpty)
}

@MainActor
@Test func cadenceIsFiveSecondsOpenAndSixtyClosed() {
    let store = Store(source: ScriptedSource(snapshots: automationSnapshots(), index: .init()),
                      stopper: SpyStopper(), defaults: makeCleanDefaults("store-5"))
    store.setPanelOpen(true)
    #expect(store.currentInterval == 5)
    store.setPanelOpen(false)
    #expect(store.currentInterval == 60)
}

private func makeCleanDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
```

This test file needs `TestFixtures` — add `Tests/StillRunningCoreTests/TestFixtures.swift` with the same process builders as Task 6's `Fixtures`, plus:

```swift
static func advance(_ processes: [ProcessSample], cpuPercent: Double, seconds: TimeInterval) -> [ProcessSample] {
    let burned = UInt64(cpuPercent / 100 * seconds * 1_000_000_000)
    return processes.map {
        ProcessSample(pid: $0.pid, ppid: $0.ppid, uid: $0.uid, executablePath: $0.executablePath,
                      arguments: $0.arguments, startedAt: $0.startedAt,
                      hasControllingTTY: $0.hasControllingTTY,
                      cpuTimeNanos: $0.cpuTimeNanos + burned, residentBytes: $0.residentBytes)
    }
}
```

- [ ] **Step 6: Run it and confirm it fails**

Run: `swift test --filter StoreTests`
Expected: `cannot find 'Store' in scope`.

- [ ] **Step 7: Write `Sources/StillRunningCore/Store.swift`**

```swift
import Foundation
import Observation
import Actions
import Detectors
import ProcessKit

/// Lets tests substitute the coordinator without a real signaller.
public protocol Stopping: Sendable {
    func stop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome
    func forceStop(_ finding: Finding, in snapshot: Snapshot) async -> StopOutcome
}

extension StopCoordinator: Stopping {}

@MainActor
@Observable
public final class Store {
    public private(set) var findings: [Finding] = []
    public private(set) var alsoHot: [HotProcess] = []
    public private(set) var isBusy = false
    /// Findings that survived a graceful stop and may be force quit.
    public private(set) var forceableIdentities: Set<String> = []
    public private(set) var lastError: String?

    public var settings: Settings {
        didSet { settingsStore.settings = settings }
    }

    private let source: any SnapshotSource
    private let stopper: any Stopping
    private let engine = DetectorEngine()
    private let settingsStore: SettingsStore
    private var exclusions: Exclusions
    private var history = History()
    private var latest: Snapshot?
    private var panelOpen = false
    private var task: Task<Void, Never>?

    public var currentInterval: TimeInterval { panelOpen ? 5 : 60 }

    public init(source: any SnapshotSource = LiveSnapshotSource(),
                stopper: any Stopping = StopCoordinator(),
                defaults: UserDefaults = .standard) {
        self.source = source
        self.stopper = stopper
        self.settingsStore = SettingsStore(defaults: defaults)
        self.exclusions = Exclusions(defaults: defaults)
        self.settings = SettingsStore(defaults: defaults).settings
    }

    public func refresh() async {
        let snapshot = await source.sample()
        latest = snapshot
        history.record(snapshot)
        let result = engine.evaluate(snapshot: snapshot, history: history,
                                     settings: settings, excluded: exclusions.identities)
        findings = result.findings
        alsoHot = result.alsoHot
        // A finding that vanished cannot still be forceable.
        forceableIdentities.formIntersection(Set(findings.map(\.identity)))
    }

    public func stop(_ finding: Finding) async {
        guard let snapshot = latest else { return }
        isBusy = true
        defer { isBusy = false }

        switch await stopper.stop(finding, in: snapshot) {
        case .stopped:
            forceableIdentities.remove(finding.identity)
            lastError = nil
        case .stillRunning:
            forceableIdentities.insert(finding.identity)
        case .refused(let reason):
            lastError = "Not stopped — \(reason)."
        case .failed(let message):
            lastError = "Could not stop: \(message)"
        }
        await refresh()
    }

    public func forceStop(_ finding: Finding) async {
        guard let snapshot = latest else { return }
        isBusy = true
        defer { isBusy = false }
        _ = await stopper.forceStop(finding, in: snapshot)
        forceableIdentities.remove(finding.identity)
        await refresh()
    }

    public func keep(_ finding: Finding) {
        exclusions.add(finding.identity)
        findings.removeAll { $0.identity == finding.identity }
    }

    public func setPanelOpen(_ open: Bool) {
        panelOpen = open
        startSampling()
    }

    public func startSampling() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = await MainActor.run { self.currentInterval }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stopSampling() {
        task?.cancel()
        task = nil
    }
}
```

- [ ] **Step 8: Run the store tests and confirm they pass**

Run: `swift test --filter StoreTests`
Expected: 5 tests PASS.

- [ ] **Step 9: Run the whole suite**

Run: `swift test`
Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add Sources/StillRunningCore Tests/StillRunningCoreTests
git commit -m "Add the observable store, exclusions, and settings persistence"
```

---

### Task 14: Menu bar app and panel

**Files:**
- Create: `Sources/StillRunning/StillRunningApp.swift`, `Sources/StillRunning/PanelView.swift`, `Sources/StillRunning/FindingRow.swift`, `Sources/StillRunning/AlsoHotSection.swift`

**Interfaces:**
- Consumes: `Store` from Task 13, and `Formatting` from Task 6.
- Produces: the running app. No new API for later tasks.

- [ ] **Step 1: Write `Sources/StillRunning/StillRunningApp.swift`**

```swift
import SwiftUI
import StillRunningCore

@main
struct StillRunningApp: App {
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            Label {
                Text("Still Running")
            } icon: {
                Image(systemName: store.findings.isEmpty ? "circle" : "circle.dotted.circle")
            }
            if !store.findings.isEmpty {
                Text("\(store.findings.count)")
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: store.findings.count) { _, _ in }
    }
}
```

The label builder shows the count next to the icon only when there is something to report, so a clean machine gets a quiet menu bar.

- [ ] **Step 2: Write `Sources/StillRunning/PanelView.swift`**

```swift
import SwiftUI
import Detectors
import StillRunningCore

struct PanelView: View {
    @Bindable var store: Store
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.findings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.findings) { finding in
                            FindingRow(finding: finding, store: store)
                            if finding.identity != store.findings.last?.identity { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 320)

                footer
            }

            AlsoHotSection(processes: store.alsoHot)

            Divider()
            controls
        }
        .frame(width: 340)
        .task { store.startSampling() }
        .onAppear { store.setPanelOpen(true) }
        .onDisappear { store.setPanelOpen(false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.findings.isEmpty ? "Nothing left running" : summary)
                .font(.headline)
            if !store.findings.isEmpty {
                Text("Stopping is reversible. Nothing is deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var summary: String {
        let cpu = store.findings.reduce(0) { $0 + $1.cpuPercent }
        let memory = store.findings.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        return "\(Int(cpu))% CPU · \(Formatting.memory(memory)) forgotten"
    }

    private var emptyState: some View {
        Text("No containers, simulators, or stray processes from earlier.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }

    private var footer: some View {
        Button("Stop all \(store.findings.count)") {
            Task { for finding in store.findings { await store.stop(finding) } }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isBusy)
        .padding(12)
    }

    private var controls: some View {
        HStack {
            if let error = store.lastError {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            Spacer()
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.plain).font(.caption)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingSettings) { SettingsView(store: store) }
    }
}
```

- [ ] **Step 3: Write `Sources/StillRunning/FindingRow.swift`**

```swift
import SwiftUI
import Detectors
import StillRunningCore

struct FindingRow: View {
    let finding: Finding
    @Bindable var store: Store
    @State private var hovering = false

    private var canForce: Bool { store.forceableIdentities.contains(finding.identity) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(finding.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if canForce {
                    Text("Still running after asking politely.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                if finding.cpuPercent >= 1 {
                    Text("\(Int(finding.cpuPercent))%").font(.callout.monospacedDigit())
                }
                actions
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 6) {
            if hovering || canForce {
                Button("Keep") { store.keep(finding) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            if canForce {
                Button("Force quit") { Task { await store.forceStop(finding) } }
                    .buttonStyle(.bordered).tint(.orange).font(.caption)
            } else {
                Button(finding.kind == .container ? "Stop" : "Quit") {
                    Task { await store.stop(finding) }
                }
                .buttonStyle(.bordered).font(.caption)
                .disabled(store.isBusy)
            }
        }
    }
}
```

- [ ] **Step 4: Write `Sources/StillRunning/AlsoHotSection.swift`**

```swift
import SwiftUI
import Detectors

/// Informational only. These rows have no buttons by design: the app does not
/// invite anyone to kill a process it has not vouched for.
struct AlsoHotSection: View {
    let processes: [HotProcess]

    var body: some View {
        if !processes.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Also busy, but yours")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(processes) { process in
                    HStack {
                        Text(process.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(Int(process.cpuPercent))%").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!`. `SettingsView` does not exist yet, so temporarily stub it at the bottom of `PanelView.swift` with `struct SettingsView: View { @Bindable var store: Store; var body: some View { Text("Settings") } }` and delete the stub in Task 15.

- [ ] **Step 6: Commit**

```bash
git add Sources/StillRunning
git commit -m "Add the menu bar panel, finding rows, and also-busy section"
```

---

### Task 15: Settings, notifications, and the app bundle

**Files:**
- Create: `Sources/StillRunning/SettingsView.swift`, `Sources/StillRunningCore/Notifier.swift`, `scripts/bundle.sh`, `Sources/StillRunning/Info.plist`
- Modify: `Sources/StillRunning/PanelView.swift` (remove the `SettingsView` stub), `Sources/StillRunningCore/Store.swift` (call the notifier from `refresh()`)

**Interfaces:**
- Consumes: `Settings`, `Store`.
- Produces: `Still Running.app` on disk, built by `scripts/bundle.sh`.

- [ ] **Step 1: Write the failing notifier test**

`Tests/StillRunningCoreTests/NotifierTests.swift`:

```swift
import Testing
import Foundation
@testable import StillRunningCore
import Detectors

private final class RecordingPresenter: NotificationPresenting, @unchecked Sendable {
    var messages: [String] = []
    func present(title: String, body: String) { messages.append(body) }
}

private func finding(identity: String, age: TimeInterval) -> Finding {
    Finding(identity: identity, kind: .devServer, title: "vite", detail: "d",
            cpuPercent: 5, memoryBytes: 0, age: age, target: .processes([1000]), severity: .notable)
}

@Test func notifiesOnceForSomethingPastTheThreshold() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 9 * 3600)], settings: settings)
    notifier.consider([finding(identity: "a", age: 10 * 3600)], settings: settings)

    #expect(presenter.messages.count == 1)
}

@Test func staysSilentWhenNotificationsAreOff() {
    let presenter = RecordingPresenter()
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 40 * 3600)], settings: Settings())

    #expect(presenter.messages.isEmpty)
}

@Test func staysSilentBelowTheThreshold() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 3 * 3600)], settings: settings)

    #expect(presenter.messages.isEmpty)
}

@Test func notifiesAgainForADifferentIdentity() {
    let presenter = RecordingPresenter()
    var settings = Settings()
    settings.notifyAfter = 8 * 3600
    var notifier = Notifier(presenter: presenter)

    notifier.consider([finding(identity: "a", age: 9 * 3600)], settings: settings)
    notifier.consider([finding(identity: "b", age: 9 * 3600)], settings: settings)

    #expect(presenter.messages.count == 2)
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift test --filter NotifierTests`
Expected: `cannot find 'Notifier' in scope`.

- [ ] **Step 3: Write `Sources/StillRunningCore/Notifier.swift`**

```swift
import Foundation
import UserNotifications
import Detectors

public protocol NotificationPresenting: Sendable {
    func present(title: String, body: String)
}

public struct SystemNotificationPresenter: NotificationPresenting {
    public init() {}

    public func present(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Opt-in, and at most one notification per identity per launch. The original
/// failure this app exists for is not noticing for eighteen hours; the fix is
/// one quiet nudge, not a stream of them.
public struct Notifier: Sendable {
    private let presenter: any NotificationPresenting
    private var notified: Set<String> = []

    public init(presenter: any NotificationPresenting = SystemNotificationPresenter()) {
        self.presenter = presenter
    }

    public mutating func consider(_ findings: [Finding], settings: Settings) {
        guard let threshold = settings.notifyAfter else { return }
        for finding in findings where finding.age >= threshold && !notified.contains(finding.identity) {
            notified.insert(finding.identity)
            presenter.present(
                title: "Still running",
                body: "\(finding.title) has been running for \(Formatting.duration(finding.age)).")
        }
    }

    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }
}
```

- [ ] **Step 4: Wire the notifier into `Store.refresh()`**

In `Sources/StillRunningCore/Store.swift`, add `private var notifier = Notifier()` and, at the end of `refresh()`, after `findings` is assigned:

```swift
notifier.consider(findings, settings: settings)
```

- [ ] **Step 5: Run the notifier tests and confirm they pass**

Run: `swift test --filter NotifierTests`
Expected: 4 tests PASS.

- [ ] **Step 6: Write `Sources/StillRunning/SettingsView.swift` and delete the stub from `PanelView.swift`**

```swift
import SwiftUI
import Detectors
import StillRunningCore

struct SettingsView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss

    private let ageChoices: [(String, TimeInterval)] = [
        ("30 minutes", 1800), ("1 hour", 3600), ("2 hours", 7200),
        ("4 hours", 14_400), ("8 hours", 28_800),
    ]
    private let notifyChoices: [(String, TimeInterval?)] = [
        ("Never", nil), ("After 4 hours", 14_400), ("After 8 hours", 28_800),
        ("After a day", 86_400),
    ]

    var body: some View {
        Form {
            Picker("Consider forgotten after", selection: ageBinding) {
                ForEach(ageChoices, id: \.1) { Text($0.0).tag($0.1) }
            }
            Picker("Notify me", selection: notifyBinding) {
                ForEach(notifyChoices, id: \.0) { Text($0.0).tag($0.1) }
            }
            Text("Still Running never deletes anything. Every action here stops a process, container, or simulator that you can start again.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onChange(of: store.settings.notifyAfter) { _, new in
            if new != nil { Notifier.requestAuthorization() }
        }
    }

    private var ageBinding: Binding<TimeInterval> {
        Binding(get: { store.settings.minimumAge }, set: { store.settings.minimumAge = $0 })
    }

    private var notifyBinding: Binding<TimeInterval?> {
        Binding(get: { store.settings.notifyAfter }, set: { store.settings.notifyAfter = $0 })
    }
}
```

- [ ] **Step 7: Write `Sources/StillRunning/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Still Running</string>
  <key>CFBundleDisplayName</key><string>Still Running</string>
  <key>CFBundleIdentifier</key><string>social.selin.stillrunning</string>
  <key>CFBundleExecutable</key><string>StillRunning</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licensed</string>
</dict>
</plist>
```

- [ ] **Step 8: Write `scripts/bundle.sh`**

```bash
#!/usr/bin/env bash
# Builds Still Running.app from the SwiftPM executable.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Still Running.app"

swift build -c "$CONFIG" --package-path "$ROOT"
BINARY="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/StillRunning"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/StillRunning"
cp "$ROOT/Sources/StillRunning/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature. Users right-click and Open the first time; see the README.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
```

- [ ] **Step 9: Build and launch it**

```bash
chmod +x scripts/bundle.sh
./scripts/bundle.sh debug
open "build/Still Running.app"
```

Expected: an icon appears in the menu bar with no Dock icon. Clicking it opens the panel. Verify by hand, in this order:

1. The panel lists at least one real finding on this machine (there is a `/tmp/claude-cdp-prof` Chrome and a set of `selene-*` containers running right now).
2. The user's own Chrome appears in "Also busy, but yours" with no button, never as a finding.
3. Clicking Quit on a finding removes it within one refresh.
4. Clicking Keep makes it stay gone across a panel close and reopen.

- [ ] **Step 10: Commit**

```bash
git add Sources/StillRunning Sources/StillRunningCore/Notifier.swift Tests/StillRunningCoreTests/NotifierTests.swift scripts/bundle.sh
git commit -m "Add settings, opt-in notifications, and app bundling"
```

---

### Task 16: README, release workflow, and publish

**Files:**
- Create: `README.md`, `.github/workflows/release.yml`
- Modify: `.github/workflows/ci.yml` — also run `./scripts/bundle.sh`

**Interfaces:**
- Consumes: everything.
- Produces: the public repository.

- [ ] **Step 1: Write `README.md`**

Sections, in this order:

1. Title, one-line description: "The containers, simulators, and stray processes you forgot are still running." A screenshot of the panel in dark mode.
2. **Why** — three sentences on the eighteen-hour headless Chrome that cooked a laptop.
3. **What it finds** — the detector table from the spec.
4. **What it will never do** — never deletes; never touches your browser's own tabs; never sends SIGKILL without a second, explicit click; needs no root, Accessibility, or Full Disk Access.
5. **Install** — download the DMG, drag to Applications, right-click and Open the first time because the build is ad-hoc signed rather than notarised.
6. **Build from source** — `swift test && ./scripts/bundle.sh`.
7. **How detection works** — snapshots, rolling history, thresholds, and where to change them.
8. License.

- [ ] **Step 2: Extend CI to build the bundle**

Append to the `test` job in `.github/workflows/ci.yml`:

```yaml
      - name: Bundle
        run: ./scripts/bundle.sh release
```

- [ ] **Step 3: Write `.github/workflows/release.yml`**

```yaml
name: Release
on:
  push:
    tags: ['v*']
jobs:
  release:
    runs-on: macos-26
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Test
        run: swift test
      - name: Bundle
        run: ./scripts/bundle.sh release
      - name: Create DMG
        run: |
          mkdir -p dmg
          cp -R "build/Still Running.app" dmg/
          ln -s /Applications dmg/Applications
          hdiutil create -volname "Still Running" -srcfolder dmg \
            -ov -format UDZO "Still-Running.dmg"
      - name: Publish
        uses: softprops/action-gh-release@v2
        with:
          files: Still-Running.dmg
          generate_release_notes: true
```

- [ ] **Step 4: Verify the release path locally**

```bash
swift test && ./scripts/bundle.sh release
```

Expected: all tests pass and the bundle builds. Do not push a tag yet — publishing is Selin's call.

- [ ] **Step 5: Commit**

```bash
git add README.md .github/workflows
git commit -m "Add README and release workflow"
```

- [ ] **Step 6: Create the GitHub repository and push**

```bash
gh repo create selinihtyr/still-running --public --source=. --remote=origin \
  --description "The containers, simulators, and stray processes you forgot are still running."
git push -u origin main
```

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task: detection sources (2, 4, 5, 12), the five detectors (6, 7, 8), thresholds and rolling history (3, 6), the two-list panel structure (9, 14), the never-touch list and graceful-first stopping and "Keep this" (10, 11, 13), architecture and module layout (1), data flow (13), testing approach (6 onward), publishing (16), and the out-of-scope list, which no task implements.

**Deviation to flag.** The spec sketched a `.xcodeproj`. The plan uses SwiftPM plus a bundling script instead, recorded under Global Constraints. The module boundaries are unchanged.

**Type consistency.** `Finding`, `FindingKind`, `StopTarget`, `Settings`, `Snapshot`, `ProcessSample`, `History`, `EngineResult`, `HotProcess`, `StopOutcome`, and the `Detector`/`Stopper`/`Stopping` protocols are each defined in exactly one task and used with the same signatures afterwards. `IsolatedBrowserDetector.isolationSignature` and `.isBrowser` are defined in Task 6 and reused by Tasks 7 and 10.

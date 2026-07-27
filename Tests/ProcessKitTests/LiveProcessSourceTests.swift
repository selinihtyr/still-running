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
    // The point is that argv of a process we did not spawn is readable
    // without elevated privileges.
    let processes = LiveProcessSource().processes()
    let others = processes.filter { $0.pid != getpid() && !$0.arguments.isEmpty }

    #expect(others.count > 5)
}

@Test func liveSourceReportsPlausibleResourceNumbers() {
    let processes = LiveProcessSource().processes()
    let me = processes.first { $0.pid == getpid() }

    #expect(me!.residentBytes > 1_048_576)          // a running test process holds at least a MB
    #expect(me!.cpuTimeNanos > 0)
    #expect(me!.ppid > 0)
}

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

@Test func ignoresUnrelatedBinaries() {
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

@Test func devServerIdentityIgnoresTheChosenPort() {
    // Restarting on another port must not read as a different thing.
    let first = [Fixtures.process(pid: 4700, path: "/opt/homebrew/bin/node",
                                  args: ["node", "server.js", "--port", "3000"], ageHours: 5)]
    let second = [Fixtures.process(pid: 4800, path: "/opt/homebrew/bin/node",
                                   args: ["node", "server.js", "--port", "3001"], ageHours: 5)]

    let a = DevServerDetector().findings(in: Fixtures.snapshot(processes: first),
                                         history: Fixtures.history(first, cpuPercent: 1),
                                         settings: Settings())
    let b = DevServerDetector().findings(in: Fixtures.snapshot(processes: second),
                                         history: Fixtures.history(second, cpuPercent: 1),
                                         settings: Settings())

    #expect(a[0].identity == b[0].identity)
}

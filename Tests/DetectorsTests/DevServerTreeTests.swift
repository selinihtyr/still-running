import Testing
import Foundation
@testable import Detectors
import ProcessKit

/// The exact tree observed on a real machine: npm launches astro, astro
/// launches esbuild. One dev server, three processes.
private func astroStack() -> [ProcessSample] {
    [
        Fixtures.process(pid: 36268, ppid: 30000, path: "/opt/homebrew/Cellar/node/26.0.0/bin/node",
                         args: ["npm", "run", "dev", "--port", "4325", "--host"],
                         ageHours: 2.1, rssMB: 40),
        Fixtures.process(pid: 36287, ppid: 36268, path: "/opt/homebrew/Cellar/node/26.0.0/bin/node",
                         args: ["node", "/Users/x/app/frontend/node_modules/.bin/astro",
                                "dev", "--port", "4325", "--host"],
                         ageHours: 2.1, rssMB: 282),
        Fixtures.process(pid: 36290, ppid: 36287,
                         path: "/Users/x/app/frontend/node_modules/vite/node_modules/@esbuild/darwin-arm64/bin/esbuild",
                         args: ["/Users/x/app/frontend/node_modules/vite/node_modules/@esbuild/darwin-arm64/bin/esbuild",
                                "--service=0.25.12", "--ping"],
                         ageHours: 2.1, rssMB: 19),
    ]
}

@Test func reportsOneDevServerForAWholeProcessTree() {
    let processes = astroStack()
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    #expect(findings.count == 1)
    #expect(findings[0].title == "npm run dev")
    #expect(findings[0].memoryBytes == 341 * 1_048_576)   // 40 + 282 + 19
    #expect(findings[0].detail.contains("3 processes"))

    guard case .processes(let pids) = findings[0].target else {
        Issue.record("expected a process target")
        return
    }
    #expect(pids == [36268, 36287, 36290])                // root first
}

@Test func doesNotNameABundlerAfterADirectoryInItsPath() {
    // esbuild living under node_modules/vite is not vite.
    let esbuild = astroStack()[2]

    #expect(DevServerDetector.label(for: esbuild) == "esbuild · --service=0.25.12"
            || DevServerDetector.label(for: esbuild) == "esbuild")
    #expect(DevServerDetector.label(for: esbuild)?.contains("vite") == false)
}

@Test func namesAFrameworkByItsCommand() {
    #expect(DevServerDetector.label(for: astroStack()[1]) == "astro dev")
}

@Test func namesAPackageRunnerByWhatWasRun() {
    #expect(DevServerDetector.label(for: astroStack()[0]) == "npm run dev")
}

@Test func readsACommandLineThatArrivedInASingleArgument() {
    // npm rewrites its own process title, so the whole command line lands in
    // argv[0] as one string. Observed on a real machine.
    let process = Fixtures.process(
        pid: 36268, path: "/opt/homebrew/Cellar/node/26.0.0/bin/node",
        args: ["npm run dev --port 4325 --host"], ageHours: 2.1, rssMB: 40)

    #expect(DevServerDetector.label(for: process) == "npm run dev")
}

@Test func aStandaloneBundlerIsStillItsOwnFinding() {
    // Nothing above it in the tree, so it stands alone rather than vanishing.
    let processes = [astroStack()[2]]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    #expect(findings.count == 1)
}

@Test func unrelatedChildrenOfANonDevProcessAreNotSwallowed() {
    // A shell that happens to be the parent must not be dragged in, and the
    // group must stop at what the dev server itself started.
    let processes = astroStack() + [
        Fixtures.process(pid: 30000, path: "/bin/zsh", args: ["-zsh"], ageHours: 3, tty: true),
        Fixtures.process(pid: 30001, ppid: 30000, path: "/usr/bin/vim", args: ["vim"], ageHours: 3, tty: true),
    ]
    let findings = DevServerDetector().findings(
        in: Fixtures.snapshot(processes: processes),
        history: Fixtures.history(processes, cpuPercent: 1), settings: Settings())

    guard case .processes(let pids) = findings[0].target else {
        Issue.record("expected a process target")
        return
    }
    #expect(!pids.contains(30000))
    #expect(!pids.contains(30001))
}

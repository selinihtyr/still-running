import Testing
import Foundation
@testable import ProcessKit

@Test func parsesRunningJobsAndSkipsTheHeader() {
    let output = """
    PID\tStatus\tLabel
    -\t0\tio.tailscale.ipn.macsys.login-item-helper
    512\t0\tio.rvmp.daemon
    504\t0\tcom.selene.adminbot
    -\t0\tcom.apple.enhancedloggingd
    """

    let pids = LaunchctlJobs.parse(output)

    #expect(pids == [512, 504])
}

@Test func parsesAnEmptyListing() {
    #expect(LaunchctlJobs.parse("PID\tStatus\tLabel").isEmpty)
    #expect(LaunchctlJobs.parse("").isEmpty)
}

@Test func returnsNothingWhenLaunchctlIsMissing() {
    #expect(LaunchctlJobs(launchctlPath: "/nonexistent/launchctl").managedPIDs().isEmpty)
}

@Test func theRealLaunchdManagesAtLeastOneJob() {
    // Any live macOS session has managed jobs; zero would mean the parse broke.
    #expect(!LaunchctlJobs().managedPIDs().isEmpty)
}

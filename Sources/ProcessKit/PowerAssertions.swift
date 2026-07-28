import Foundation
import IOKit.pwr_mgt

/// One power assertion: a process telling macOS not to fall asleep. Holding one
/// is normal — a video call, a copy that must finish, a build. Forgetting to
/// release one is how a laptop spends the night awake in a bag, and nothing on
/// the machine says which process did it.
public struct PowerAssertionSample: Codable, Sendable, Equatable {
    public let pid: Int32
    /// IOKit's type string, e.g. "PreventUserIdleSystemSleep".
    public let type: String
    /// What the holder called it: "caffeinate command-line tool", "Playing
    /// audio", "Video Wake Lock". Written for a person, by the process that
    /// wanted the machine awake, which makes it the most useful thing here.
    public let name: String
    /// The name IOKit reports for the holder.
    public let processName: String
    public let startedAt: Date
    /// What it was created to expire after. Zero means it never does: nothing
    /// releases it but the process ending.
    public let timeoutSeconds: Int

    public init(pid: Int32, type: String, name: String, processName: String,
                startedAt: Date, timeoutSeconds: Int = 0) {
        self.pid = pid
        self.type = type
        self.name = name
        self.processName = processName
        self.startedAt = startedAt
        self.timeoutSeconds = timeoutSeconds
    }

    /// The types that stop a Mac going to sleep on its own. Everything else
    /// IOKit reports — `UserIsActive` from a keystroke, a background task, a
    /// push notification — is macOS narrating itself, and expires on its own.
    public static let sleepPreventingTypes: Set<String> = [
        "PreventUserIdleSystemSleep",   // kIOPMAssertionTypePreventUserIdleSystemSleep
        "PreventSystemSleep",           // kIOPMAssertionTypePreventSystemSleep
        "NoIdleSleepAssertion",         // kIOPMAssertionTypeNoIdleSleep, the older spelling
        "PreventUserIdleDisplaySleep",  // kIOPMAssertionTypePreventUserIdleDisplaySleep
        "NoDisplaySleepAssertion",      // kIOPMAssertionTypeNoDisplaySleep
    ]

    public var preventsSleep: Bool { Self.sleepPreventingTypes.contains(type) }

    /// Display assertions keep the screen lit, and macOS will not idle-sleep a
    /// machine whose display is on — so these keep the whole Mac awake too.
    /// Saying "keeping the screen on" is still the more useful sentence.
    public var keepsScreenOn: Bool { type.contains("Display") }

    /// An assertion made with a timeout releases itself. Tools that wrap a
    /// command in `caffeinate -t 300` make these by the dozen, and none of them
    /// is a thing anybody forgot.
    public var expiresOnItsOwn: Bool { timeoutSeconds > 0 }
}

public protocol PowerAssertionSource: Sendable {
    func assertions() -> [PowerAssertionSample]
}

/// Reads the live assertion table. No entitlement and no privileges: the list
/// is system-wide and readable by anyone, which is the only reason this feature
/// can exist in an unsigned app.
public struct LivePowerAssertions: PowerAssertionSource {
    public init() {}

    public func assertions() -> [PowerAssertionSample] {
        var copied: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&copied) == kIOReturnSuccess,
              let byProcess = copied?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        return byProcess.flatMap { pid, held in
            held.compactMap { entry -> PowerAssertionSample? in
                guard let type = entry["AssertType"] as? String else { return nil }
                return PowerAssertionSample(
                    pid: pid.int32Value,
                    type: type,
                    name: entry["AssertName"] as? String ?? "",
                    processName: entry["Process Name"] as? String ?? "",
                    // A missing start time would read as "held since the epoch"
                    // and clear every age threshold there is, so it counts as
                    // just created instead.
                    startedAt: entry["AssertStartWhen"] as? Date ?? Date(),
                    timeoutSeconds: entry["TimeoutSeconds"] as? Int ?? 0)
            }
        }
    }
}

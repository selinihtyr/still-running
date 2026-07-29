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

public protocol Restarting: Sendable {
    func restart(_ finding: Finding) async -> Bool
}

extension RestartCoordinator: Restarting {}

/// Something stopped a moment ago that can be put back.
public struct UndoableStop: Sendable, Identifiable, Equatable {
    public let finding: Finding
    public let stoppedAt: Date
    public var id: String { finding.identity }
}

/// A stop that has not happened yet. Processes get this instead of an undo,
/// because a signal cannot be taken back.
public struct PendingStop: Sendable, Identifiable, Equatable {
    public let finding: Finding
    public let firesAt: Date
    public var id: String { finding.identity }
}

@MainActor
@Observable
public final class Store {
    public private(set) var findings: [Finding] = []
    public private(set) var alsoHot: [HotProcess] = []
    /// Named, not offered up: the things holding this Mac awake that are not
    /// this app's business to quit.
    public private(set) var keepingAwake: [AwakeHolder] = []
    /// Identities with a stop in flight. Stopping is per row, not global: a
    /// container that ignores SIGTERM keeps Docker waiting out its ten second
    /// grace period, and that must not freeze every other button.
    public private(set) var inFlight: Set<String> = []
    /// Findings that survived a graceful stop and may be force quit.
    public private(set) var forceableIdentities: Set<String> = []
    public private(set) var lastError: String?
    /// When the machine was last looked at, for the panel's footer.
    public private(set) var lastSampledAt: Date?
    /// True while a sample is being taken, so the panel can show it happening.
    public private(set) var isRefreshing = false

    public var settings: Settings {
        didSet { settingsStore.settings = settings }
    }

    /// Stops that can still be taken back, newest last.
    public private(set) var undoable: [UndoableStop] = []
    /// Process stops counting down, which can still be called off.
    public private(set) var pendingStops: [PendingStop] = []

    /// How long a process stop waits before the signal goes out, and how long
    /// an undo stays offered afterwards.
    public let cancellationWindow: TimeInterval
    public let undoWindow: TimeInterval

    private var countdowns: [String: Task<Void, Never>] = [:]

    private let source: any SnapshotSource
    private let stopper: any Stopping
    private let restarter: any Restarting
    private let engine = DetectorEngine()
    private let settingsStore: SettingsStore
    private let defaults: UserDefaults
    private var exclusions: Exclusions
    private var notifier: Notifier
    private let updateChecker: UpdateChecker
    private var history = History()
    private var latest: Snapshot?
    private var panelOpen = false
    private var samplingTask: Task<Void, Never>?
    /// Counts samples so a refresh that took longer cannot land its answer on
    /// top of a newer one. Stopping something triggers its own refresh, so two
    /// are genuinely in flight at once whenever anyone clicks.
    private var generation = 0

    /// Five seconds while the user is looking, a minute while they are not.
    public var currentInterval: TimeInterval { panelOpen ? 5 : 60 }

    /// How much CPU the forgotten things are eating between them. 100 is a
    /// whole core.
    public var wastedCPUPercent: Double {
        findings.reduce(0) { $0 + $1.cpuPercent }
    }

    /// How hard the machine is being pushed right now, refreshed with each sample.
    public private(set) var thermal: Thermal = .current

    /// The version this build is, for the panel's footer.
    public static let version = UpdateChecker.bundledVersion

    /// Whether a newer release exists. `.unknown` until the first answer comes
    /// back, and the panel shows nothing at all until it is `.available`.
    public private(set) var update: UpdateStatus = .unknown
    /// True while the Settings button is waiting on GitHub, so a manual check
    /// visibly does something.
    public private(set) var isCheckingForUpdate = false

    public init(source: any SnapshotSource = LiveSnapshotSource(),
                stopper: any Stopping = StopCoordinator(),
                restarter: any Restarting = RestartCoordinator(),
                defaults: UserDefaults = .standard,
                notifier: Notifier = Notifier(),
                updateChecker: UpdateChecker = UpdateChecker(),
                cancellationWindow: TimeInterval = 3,
                undoWindow: TimeInterval = 120) {
        let settingsStore = SettingsStore(defaults: defaults)
        self.source = source
        self.stopper = stopper
        self.restarter = restarter
        self.settingsStore = settingsStore
        self.defaults = defaults
        self.exclusions = Exclusions(defaults: defaults)
        self.notifier = notifier
        self.updateChecker = updateChecker
        self.cancellationWindow = cancellationWindow
        self.undoWindow = undoWindow
        self.settings = settingsStore.settings
    }

    /// First launch after install: ask macOS for notification permission, and
    /// turn reminders on so that permission is worth something. Asking for a
    /// permission the app then never uses would be a worse first impression
    /// than not asking at all.
    public func prepareFirstRun() {
        ensureItSurvivesARestart()

        let key = "hasLaunchedBefore"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)

        var updated = settings
        updated.notifyAfter = 8 * 3600
        settings = updated

        notifier.requestAuthorization()
    }

    /// Registered once — on a fresh install, or on the first launch of a version
    /// that has this — and never again, so switching it off in Settings sticks.
    private func ensureItSurvivesARestart() {
        // First, give back what this copy should not be holding. A build that
        // ran before it was installed took the login item and kept it, and the
        // installed copy has no way to reach another bundle's registration —
        // only the bundle that has it can let go.
        LoginItem.releaseIfNotAllowed()

        let key = "hasRegisteredLoginItem"
        guard !defaults.bool(forKey: key), LoginItem.isAvailable else { return }
        defaults.set(true, forKey: key)
        LoginItem.setEnabled(true)
    }

    /// Asks GitHub for the latest release tag: on launch, then once a day, and
    /// on demand from Settings. Nothing is sent but the request itself, and it
    /// only happens while the setting is on.
    public func checkForUpdate(force: Bool = false) async {
        let key = "lastUpdateCheck"
        guard settings.checksForUpdates || force else {
            update = .unknown
            return
        }
        // The last answer, held against this build's version. Without it a
        // relaunch inside the daily window would know nothing at all, and the
        // panel would go back to saying nothing until tomorrow.
        applyRememberedRelease()
        // Before the throttle, because the remembered answer is the one most
        // launches ever see: the check that found it may have been days ago.
        announceRelease(silently: force)

        // The daily throttle only makes sense once there is an answer to hold
        // on to. Having never had one, waiting out the day would leave the
        // panel saying nothing about versions on the day it was installed.
        let neverAnswered = defaults.string(forKey: Self.rememberedReleaseKey) == nil
        let last = defaults.object(forKey: key) as? Date
        guard force || neverAnswered
                || UpdateChecker.isDue(lastChecked: last, now: .now, every: 86_400) else { return }

        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }
        let result = await updateChecker.check()
        // A failed check must not park the next one a day away.
        if result != .unknown { defaults.set(Date(), forKey: key) }
        if case .available(let found) = result {
            defaults.set(found.version.description, forKey: Self.rememberedReleaseKey)
            defaults.set(found.pageURL.absoluteString, forKey: Self.rememberedPageKey)
        } else if result == .upToDate {
            defaults.set(Store.version, forKey: Self.rememberedReleaseKey)
        }
        update = result
        announceRelease(silently: force)
    }

    /// One notification per version, ever. The strip in the panel says it too,
    /// but only to someone who opens the panel — and this app has no window and
    /// no Dock icon, so months can pass without anyone opening anything. The
    /// people worth telling about a release are exactly the ones not looking.
    private func announceRelease(silently: Bool) {
        guard case .available(let found) = update else { return }
        let key = "announcedRelease"
        let version = found.version.description
        guard defaults.string(forKey: key) != version else { return }
        defaults.set(version, forKey: key)

        // Asking for the check yourself and then being told by a banner is
        // being told what is already on the screen. It still counts as said.
        guard !silently else { return }
        notifier.announce(release: version, running: Store.version)
    }

    private static let rememberedReleaseKey = "lastKnownRelease"
    private static let rememberedPageKey = "lastKnownReleasePage"

    /// Compares the newest release we have ever heard of against this build.
    /// Updating makes it match, which is exactly when the strip should go away.
    private func applyRememberedRelease() {
        guard let remembered = defaults.string(forKey: Self.rememberedReleaseKey),
              let latest = ReleaseVersion(remembered),
              let running = ReleaseVersion(Store.version)
        else { return }

        if latest > running,
           let page = URL(string: defaults.string(forKey: Self.rememberedPageKey) ?? "") {
            update = .available(AvailableUpdate(version: latest, pageURL: page))
        } else {
            update = .upToDate
        }
    }

    /// Runs the pull and the installer in a Terminal window, or opens the
    /// release page if the checkout it was built from has moved.
    public func installUpdate() {
        guard case .available(let found) = update else { return }
        Updater.install(fallbackPage: found.pageURL)
    }

    private func expireUndo(_ identity: String) {
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.undoWindow))
            self.undoable.removeAll { $0.id == identity }
        }
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = await source.sample()
        generation += 1
        let mine = generation
        latest = snapshot
        lastSampledAt = snapshot.takenAt
        thermal = .current
        history.record(snapshot)

        // Detection is twenty milliseconds of string matching across every
        // process on the machine, and this method runs on the main actor every
        // five seconds while the panel is open. Nothing about it needs to be
        // there: every input is a value type and the result is Sendable, so it
        // runs off the main thread and only the assignments come back.
        let engine = self.engine
        let excluded = exclusions.identities
        let current = settings
        let recorded = history
        let result = await Task.detached(priority: .userInitiated) {
            engine.evaluate(snapshot: snapshot, history: recorded,
                            settings: current, excluded: excluded)
        }.value

        guard mine == generation else { return }
        findings = result.findings
        alsoHot = result.alsoHot
        keepingAwake = result.keepingAwake
        // A finding that vanished cannot still be forceable.
        forceableIdentities.formIntersection(Set(findings.map(\.identity)))
        notifier.consider(findings, settings: settings, thermal: thermal)
    }

    public func isStopping(_ finding: Finding) -> Bool { inFlight.contains(finding.identity) }

    public func pending(_ finding: Finding) -> PendingStop? {
        pendingStops.first { $0.finding.identity == finding.identity }
    }

    /// Containers and simulators go straight down and can be brought back.
    /// Processes wait out a short cancellable window first, because once the
    /// signal is sent there is no way back.
    public func stop(_ finding: Finding) async {
        guard RestartCoordinator.canRestart(finding) else {
            schedule(finding)
            return
        }
        await stop(finding, thenRefresh: true)
    }

    /// Starts the countdown for a process. A second call is ignored, so
    /// double-clicking does not stack two stops.
    private func schedule(_ finding: Finding) {
        guard pending(finding) == nil, !inFlight.contains(finding.identity) else { return }
        let deadline = Date().addingTimeInterval(cancellationWindow)
        pendingStops.append(PendingStop(finding: finding, firesAt: deadline))

        let window = cancellationWindow
        countdowns[finding.identity] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard let self, !Task.isCancelled else { return }
            self.pendingStops.removeAll { $0.finding.identity == finding.identity }
            self.countdowns[finding.identity] = nil
            await self.stop(finding, thenRefresh: true)
        }
    }

    /// Takes back a stop that has not fired yet.
    public func cancelPending(_ finding: Finding) {
        countdowns[finding.identity]?.cancel()
        countdowns[finding.identity] = nil
        pendingStops.removeAll { $0.finding.identity == finding.identity }
    }

    /// Starts a stopped container or simulator again.
    public func undo(_ stop: UndoableStop) async {
        undoable.removeAll { $0.id == stop.id }
        if await restarter.restart(stop.finding) {
            lastError = nil
        } else {
            lastError = "Could not start \(stop.finding.title) again."
        }
        await refresh()
    }

    public func dismissUndo(_ stop: UndoableStop) {
        undoable.removeAll { $0.id == stop.id }
    }

    private func stop(_ finding: Finding, thenRefresh: Bool) async {
        guard let snapshot = latest, !inFlight.contains(finding.identity) else { return }
        inFlight.insert(finding.identity)
        defer { inFlight.remove(finding.identity) }

        // The row goes as soon as the stop is under way. Docker can spend ten
        // seconds waiting out a container's grace period, and leaving the row
        // sitting there for that long makes a click feel like it missed.
        // Anything that turns out to still be running comes back on the next
        // sample.
        findings.removeAll { $0.identity == finding.identity }

        switch await stopper.stop(finding, in: snapshot) {
        case .stopped:
            forceableIdentities.remove(finding.identity)
            lastError = nil
            if RestartCoordinator.canRestart(finding) {
                undoable.append(UndoableStop(finding: finding, stoppedAt: Date()))
                expireUndo(finding.identity)
            }
        case .stillRunning:
            forceableIdentities.insert(finding.identity)
        case .refused(let reason):
            lastError = "Not stopped — \(reason)."
        case .failed(let message):
            lastError = "Could not stop: \(message)"
        }
        if thenRefresh { await refresh() }
    }

    /// Stops everything at once. Sequentially this would be the sum of every
    /// grace period, which for a stack of containers is over a minute.
    public func stopAll() async {
        let running = findings.map { finding in
            Task { await self.stop(finding, thenRefresh: false) }
        }
        for task in running { await task.value }
        await refresh()
    }

    public func forceStop(_ finding: Finding) async {
        guard let snapshot = latest, !inFlight.contains(finding.identity) else { return }
        inFlight.insert(finding.identity)
        defer { inFlight.remove(finding.identity) }

        _ = await stopper.forceStop(finding, in: snapshot)
        forceableIdentities.remove(finding.identity)
        await refresh()
    }

    public func keep(_ finding: Finding) {
        exclusions.add(finding.identity)
        findings.removeAll { $0.identity == finding.identity }
    }

    public func setPanelOpen(_ open: Bool) {
        let changed = panelOpen != open
        panelOpen = open
        guard changed, open, samplingTask != nil else { return }

        // Opening must show something current. Otherwise the panel waits out
        // whatever remains of the minute-long sleep it started while closed,
        // and until a second sample lands there are no rates to show at all.
        stopSampling()
        startSampling()
    }

    public func startSampling() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.currentInterval))
            }
        }
    }

    public func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }
}

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
    private var notifier: Notifier
    private var history = History()
    private var latest: Snapshot?
    private var panelOpen = false
    private var samplingTask: Task<Void, Never>?

    /// Five seconds while the user is looking, a minute while they are not.
    public var currentInterval: TimeInterval { panelOpen ? 5 : 60 }

    public init(source: any SnapshotSource = LiveSnapshotSource(),
                stopper: any Stopping = StopCoordinator(),
                defaults: UserDefaults = .standard,
                notifier: Notifier = Notifier()) {
        let settingsStore = SettingsStore(defaults: defaults)
        self.source = source
        self.stopper = stopper
        self.settingsStore = settingsStore
        self.exclusions = Exclusions(defaults: defaults)
        self.notifier = notifier
        self.settings = settingsStore.settings
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
        notifier.consider(findings, settings: settings)
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

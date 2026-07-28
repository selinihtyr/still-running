import SwiftUI
import AppKit
import Detectors
import StillRunningCore

struct PanelView: View {
    @Bindable var store: Store
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingStopAll = false

    private var grouped: [(section: String, findings: [Finding])] {
        Dictionary(grouping: store.findings) { Theme.section(for: $0.kind) }
            .sorted { a, b in
                let order = Theme.sectionOrder
                return (order.firstIndex(of: a.key) ?? 99) < (order.firstIndex(of: b.key) ?? 99)
            }
            .map { ($0.key, $0.value.sorted { $0.age > $1.age }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.findings.isEmpty {
                emptyState
            } else {
                content
                stopAll
            }

            undoStrip
            AlsoHotSection(processes: store.alsoHot)
            updateStrip

            Divider()
            footer
        }
        .frame(width: Theme.panelWidth)
        .onAppear { store.setPanelOpen(true) }
        .onDisappear { store.setPanelOpen(false) }
        .animation(.smooth(duration: 0.25), value: store.findings.map(\.identity))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                Text(subhead)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            thermalBadge
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    /// macOS reports how hard it is being pushed rather than a temperature in
    /// degrees; this is the reading it acts on when it spins the fans.
    @ViewBuilder private var thermalBadge: some View {
        if store.thermal.isWorthShowing {
            HStack(spacing: 4) {
                Image(systemName: store.thermal.symbol)
                Text(store.thermal.label)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(thermalColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(thermalColor.opacity(0.14), in: Capsule())
            .help("How hard macOS says the machine is being pushed right now.")
        }
    }

    private var thermalColor: Color {
        switch store.thermal {
        case .nominal: .secondary
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        }
    }

    private var headline: String {
        store.findings.isEmpty ? "Nothing left over" : "\(store.findings.count) still running"
    }

    private var subhead: String {
        if store.findings.isEmpty {
            return "Everything alive was started recently or is doing work."
        }
        let memory = store.findings.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let held = memory > 0 ? "\(Formatting.memory(memory)) held · " : ""
        return held + "stopping is reversible, nothing is deleted"
    }

    private var emptyState: some View {
        EmptyView()
    }

    /// Up to six rows are laid out plainly. Beyond that they scroll at a fixed
    /// height: a menu bar window sizes itself to its content and a ScrollView
    /// has no intrinsic height, so an unbounded one collapses to nothing.
    private static let rowsBeforeScrolling = 6
    private static let scrollHeight: CGFloat = 420

    @ViewBuilder private var content: some View {
        if store.findings.count <= Self.rowsBeforeScrolling {
            sections
        } else {
            ScrollView { sections }
                .frame(height: Self.scrollHeight)
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(grouped, id: \.section) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(group.section.uppercased())
                            .font(.eyebrow)
                            .tracking(0.8)
                        Text("\(group.findings.count)")
                            .font(.eyebrow)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(group.findings) { finding in
                            FindingRow(finding: finding, store: store)
                            if finding.identity != group.findings.last?.identity {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .padding(.horizontal, 8)
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// Bulk stopping asks first, and asks in place. A confirmation dialog
    /// presented from a menu bar window dies with the window the moment focus
    /// moves, so the button becomes the question and waits for a second press.
    private var stopAll: some View {
        VStack(spacing: 6) {
            Button {
                if confirmingStopAll {
                    confirmingStopAll = false
                    Task { await store.stopAll() }
                } else {
                    confirmingStopAll = true
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        confirmingStopAll = false
                    }
                }
            } label: {
                Text(stopAllLabel).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(confirmingStopAll ? .orange : .accentColor)
            .disabled(!store.inFlight.isEmpty)

            if confirmingStopAll {
                Text(stopAllConsequence)
                    .font(.rowDetail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var stopAllLabel: String {
        if !store.inFlight.isEmpty { return "Stopping \(store.inFlight.count)…" }
        return confirmingStopAll
            ? "Yes, stop all \(store.findings.count)"
            : "Stop all \(store.findings.count)"
    }

    private var stopAllConsequence: String {
        let counts = Dictionary(grouping: store.findings, by: \.kind).mapValues(\.count)
        let parts = counts
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { kind, count in "\(count) \(kind.label.lowercased())\(count == 1 ? "" : "s")" }
        return parts.joined(separator: ", ") + " will be stopped."
    }

    /// Stopped containers and simulators linger here for a moment so a wrong
    /// click can be taken back. Processes never appear: they cannot be started
    /// again as the same thing, so they get a countdown before the signal.
    @ViewBuilder private var undoStrip: some View {
        if !store.undoable.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("JUST STOPPED")
                    .font(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                ForEach(store.undoable) { stopped in
                    HStack(spacing: 8) {
                        Image(systemName: Theme.icon(for: stopped.finding.kind))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tint(for: stopped.finding.kind))
                        Text(stopped.finding.title)
                            .font(.rowDetail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Start again") { Task { await store.undo(stopped) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button {
                            store.dismissUndo(stopped)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                        .help("Dismiss")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    /// Only ever appears when there is genuinely a newer release. An update
    /// runs the same pull and installer the README documents, in a Terminal
    /// window you can watch.
    @ViewBuilder private var updateStrip: some View {
        if case .available(let found) = store.update {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Version \(found.version.description) is out")
                        .font(.system(size: 12, weight: .medium))
                    Text("Opens a Terminal window and builds it")
                        .font(.rowDetail)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Update") { store.installUpdate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = store.lastError {
                Text(error)
                    .font(.rowDetail)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                // A live counter is the cheapest possible proof that the app is
                // still watching, and that pressing refresh did something.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(checkedLabel(at: context.date))
                        .font(.rowDetail)
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
            // Fixed frames, and no spinning: a sample takes about a tenth of a
            // second, so an animation only ever got interrupted — leaving the
            // glyph at a random angle and nudging its neighbours as its bounding
            // box changed. The footer text already says "Checking…".
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 16, height: 16)
                    .opacity(store.isRefreshing ? 0.4 : 1)
            }
            .disabled(store.isRefreshing)
            .help("Check again")
            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 16, height: 16)
            }
            .help("Settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 16, height: 16)
            }
            .help("Quit Still Running")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func checkedLabel(at now: Date) -> String {
        if store.isRefreshing { return "Checking…" }
        guard let checked = store.lastSampledAt else { return "Checking…" }
        let seconds = max(0, Int(now.timeIntervalSince(checked)))
        return seconds < 1 ? "Checked just now" : "Checked \(seconds)s ago"
    }
}

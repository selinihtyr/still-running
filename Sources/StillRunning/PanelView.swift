import SwiftUI
import AppKit
import Detectors
import StillRunningCore

struct PanelView: View {
    @Bindable var store: Store
    @Environment(\.openWindow) private var openWindow

    private var longestAge: TimeInterval { store.findings.map(\.age).max() ?? 0 }

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

            AlsoHotSection(processes: store.alsoHot)

            Divider()
            footer
        }
        .frame(width: Theme.panelWidth)
        .onAppear { store.setPanelOpen(true) }
        .onDisappear { store.setPanelOpen(false) }
        .animation(.smooth(duration: 0.25), value: store.findings.map(\.identity))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold))
                Text(subhead)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
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
                            FindingRow(finding: finding, longestAge: longestAge, store: store)
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

    private var stopAll: some View {
        Button {
            Task { for finding in store.findings { await store.stop(finding) } }
        } label: {
            Text("Stop all \(store.findings.count)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(store.isBusy)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let error = store.lastError {
                Text(error)
                    .font(.rowDetail)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                Text(checkedLabel)
                    .font(.rowDetail)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Check again")
            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Still Running")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var checkedLabel: String {
        guard let checked = store.lastSampledAt else { return "Checking…" }
        let seconds = Int(Date().timeIntervalSince(checked))
        return seconds < 5 ? "Checked just now" : "Checked \(seconds)s ago"
    }
}

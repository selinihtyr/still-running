import SwiftUI
import AppKit
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
                findingsList
                stopAllButton
            }

            AlsoHotSection(processes: store.alsoHot)

            Divider()
            controls
        }
        .frame(width: 340)
        .task { store.startSampling() }
        .onAppear { store.setPanelOpen(true) }
        .onDisappear { store.setPanelOpen(false) }
        .sheet(isPresented: $showingSettings) { SettingsView(store: store) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.findings.isEmpty ? "Nothing left running" : summary)
                .font(.headline)
            Text(store.findings.isEmpty
                 ? "No containers, simulators, or stray processes from earlier."
                 : "Stopping is reversible. Nothing is deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private var summary: String {
        let cpu = store.findings.reduce(0) { $0 + $1.cpuPercent }
        let memory = store.findings.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        if memory == 0 { return "\(store.findings.count) left running" }
        return "\(Int(cpu))% CPU · \(Formatting.memory(memory)) still held"
    }

    private var emptyState: some View {
        EmptyView()
    }

    private var findingsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.findings) { finding in
                    FindingRow(finding: finding, store: store)
                    if finding.identity != store.findings.last?.identity { Divider() }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private var stopAllButton: some View {
        Button("Stop all \(store.findings.count)") {
            Task {
                for finding in store.findings { await store.stop(finding) }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isBusy)
        .padding(12)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.plain)
                .font(.caption)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

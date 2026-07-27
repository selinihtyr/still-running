import SwiftUI
import Detectors
import StillRunningCore

struct FindingRow: View {
    let finding: Finding
    @Bindable var store: Store
    @State private var hovering = false

    private var canForce: Bool { store.forceableIdentities.contains(finding.identity) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if canForce {
                    Text("Still running after asking politely.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                if finding.cpuPercent >= 1 {
                    Text("\(Int(finding.cpuPercent))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(finding.severity == .urgent ? .orange : .primary)
                }
                actions
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if hovering || canForce {
                Button("Keep") { store.keep(finding) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if canForce {
                Button("Force quit") { Task { await store.forceStop(finding) } }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .font(.caption)
            } else {
                Button(stopVerb) { Task { await store.stop(finding) } }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    .disabled(store.isBusy)
            }
        }
    }

    private var stopVerb: String {
        switch finding.kind {
        case .container: "Stop"
        case .simulator: "Shut down"
        default: "Quit"
        }
    }
}

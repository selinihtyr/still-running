import SwiftUI
import Detectors
import StillRunningCore

struct FindingRow: View {
    let finding: Finding
    /// The age of the oldest thing on the list, so every rail is drawn to the
    /// same scale and the longest-lived row reads as full width.
    let longestAge: TimeInterval
    @Bindable var store: Store

    @State private var hovering = false

    private var canForce: Bool { store.forceableIdentities.contains(finding.identity) }
    private var accent: Color { Theme.accent(for: finding) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                icon
                titles
                Spacer(minLength: 8)
                figures
                action
            }
            durationRail
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }

    private var icon: some View {
        Image(systemName: Theme.icon(for: finding.kind))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(finding.title)
                .font(.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(finding.detail)
                .font(.rowDetail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if canForce {
                Text("Asked politely. It stayed.")
                    .font(.rowDetail)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Age leads, because age is what makes something a leftover. CPU only
    /// appears when there is any, so a quiet list stays quiet.
    private var figures: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(Formatting.duration(finding.age))
                .font(.figureLarge)
            if finding.cpuPercent >= 1 {
                Text("\(Int(finding.cpuPercent))% CPU")
                    .font(.figure)
                    .foregroundStyle(.orange)
            } else if finding.memoryBytes > 0 {
                Text(Formatting.memory(finding.memoryBytes))
                    .font(.figure)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var action: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if canForce {
                Button("Force quit") { Task { await store.forceStop(finding) } }
                    .tint(.orange)
            } else {
                Button(stopVerb) { Task { await store.stop(finding) } }
                    .disabled(store.isBusy)
            }
            if hovering {
                Button("Keep") { store.keep(finding) }
                    .buttonStyle(.plain)
                    .font(.rowDetail)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// The signature of the panel: how long this has been alive, drawn against
    /// the oldest thing on the list. The list becomes a picture of who has been
    /// here longest, which is the decision being made.
    private var durationRail: some View {
        GeometryReader { proxy in
            let fraction = longestAge > 0 ? min(1, finding.age / longestAge) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.85)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, proxy.size.width * fraction))
            }
        }
        .frame(height: 3)
        .padding(.leading, 34)
        .animation(.smooth(duration: 0.4), value: finding.age)
    }

    private var stopVerb: String {
        switch finding.kind {
        case .container: "Stop"
        case .simulator: "Shut down"
        default: "Quit"
        }
    }
}

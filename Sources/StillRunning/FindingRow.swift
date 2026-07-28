import SwiftUI
import AppKit
import Detectors
import StillRunningCore

struct FindingRow: View {
    let finding: Finding
    @Bindable var store: Store

    @State private var hovering = false
    private var canForce: Bool { store.forceableIdentities.contains(finding.identity) }
    private var accent: Color { Theme.accent(for: finding) }

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                icon
                titles
                Spacer(minLength: 8)
                figures
                action
                more
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(hovering ? Color.primary.opacity(0.06) : .clear)
            .contentShape(.rect)
            .onHover { hovering = $0 }
            // A path is an identifier, not an explanation, and a tooltip only
            // helps someone who already suspects there is one. The answer to
            // "what is this" is one click away, in the panel.
            .onTapGesture { withAnimation(.smooth(duration: 0.2)) { expanded.toggle() } }

            if expanded { expansion }
        }
    }

    private var expansion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(finding.explanation)
                .font(.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let command = finding.command, !command.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("STARTED BY")
                        .font(.eyebrow)
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    Text(command)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let path = finding.revealPath {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                } label: {
                    Label(path, systemImage: "folder")
                        .font(.rowDetail)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.leading, 34)
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
            if let pending = store.pending(finding) {
                // A signal cannot be recalled, so the way back comes before it
                // rather than after.
                HStack(spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let left = max(0, Int(pending.firesAt.timeIntervalSince(context.date).rounded(.up)))
                        Text("in \(left)s")
                            .font(.figure)
                            .foregroundStyle(.orange)
                    }
                    Button("Cancel") { store.cancelPending(finding) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if store.isStopping(finding) {
                // Only this row waits. A container that ignores SIGTERM keeps
                // Docker busy for ten seconds; the rest of the panel stays live.
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Stopping")
                        .font(.rowDetail)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 20)
            } else if canForce {
                Button("Force quit") { Task { await store.forceStop(finding) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
            } else {
                Button(stopVerb) { Task { await store.stop(finding) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    /// Secondary actions live behind the ellipsis, where they read as actions
    /// rather than as another line of text in the row.
    private var more: some View {
        Menu {
            if let path = finding.revealPath {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }
            Button("Copy details") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finding.details, forType: .string)
            }
            Divider()
            Button("Never list this again") { store.keep(finding) }
            if canForce {
                Button("Force quit now") { Task { await store.forceStop(finding) } }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 16)
        .opacity(hovering ? 1 : 0.4)
        .disabled(store.isStopping(finding))
        .help("More for \(finding.title)")
    }

    private var stopVerb: String {
        switch finding.kind {
        case .container: "Stop"
        case .simulator: "Shut down"
        default: "Quit"
        }
    }
}

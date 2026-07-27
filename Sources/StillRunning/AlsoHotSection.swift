import SwiftUI
import Detectors

/// Informational only. These rows have no buttons by design: the app does not
/// invite anyone to kill a process it has not vouched for.
struct AlsoHotSection: View {
    let processes: [HotProcess]

    var body: some View {
        if !processes.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Also busy, but yours")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(processes) { process in
                    HStack {
                        Text(process.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(Int(process.cpuPercent))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

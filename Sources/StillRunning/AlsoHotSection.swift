import SwiftUI
import Detectors

/// Informational only. These rows have no buttons by design: the app does not
/// invite anyone to stop something it has not vouched for.
struct AlsoHotSection: View {
    let processes: [HotProcess]

    var body: some View {
        if !processes.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("BUSY, BUT YOURS")
                    .font(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                ForEach(processes) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .font(.rowDetail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(Int(process.cpuPercent))%")
                            .font(.figure)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

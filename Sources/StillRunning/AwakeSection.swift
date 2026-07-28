import SwiftUI
import Detectors

/// Named, never offered up. Everything in this list is holding the Mac awake,
/// and none of it is something this app should quit on anyone's behalf: an app
/// playing audio is doing its job, and the person reading the row is the only
/// one who knows whether they still want it. The ones that are safe to stop —
/// a `caffeinate` nobody released — are findings with a button instead.
struct AwakeSection: View {
    let holders: [AwakeHolder]

    var body: some View {
        if !holders.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("KEEPING THIS MAC AWAKE")
                    .font(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                ForEach(holders) { holder in
                    HStack(spacing: 7) {
                        Image(systemName: holder.keepsScreenOn ? "sun.max.fill" : "eye.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(holder.name)
                                .font(.rowDetail)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            // The holder's own words for why. "Playing audio"
                            // is the sentence that finds the tab.
                            Text(holder.reason)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(Formatting.duration(holder.heldFor))
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

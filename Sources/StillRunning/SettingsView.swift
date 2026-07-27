import SwiftUI
import Detectors
import StillRunningCore

struct SettingsView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss

    private let ageChoices: [(label: String, value: TimeInterval)] = [
        ("30 minutes", 1800), ("1 hour", 3600), ("2 hours", 7200),
        ("4 hours", 14_400), ("8 hours", 28_800),
    ]
    private let notifyChoices: [(label: String, value: TimeInterval?)] = [
        ("Never", nil), ("After 4 hours", 14_400), ("After 8 hours", 28_800),
        ("After a day", 86_400),
    ]

    var body: some View {
        Form {
            Picker("Consider forgotten after", selection: ageBinding) {
                ForEach(ageChoices, id: \.value) { Text($0.label).tag($0.value) }
            }
            Picker("Notify me", selection: notifyBinding) {
                ForEach(notifyChoices, id: \.label) { Text($0.label).tag($0.value) }
            }
            Text("Still Running never deletes anything. Every action stops a process, container, or simulator that you can start again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onChange(of: store.settings.notifyAfter) { _, new in
            if new != nil { Notifier.requestAuthorization() }
        }
    }

    private var ageBinding: Binding<TimeInterval> {
        Binding(get: { store.settings.minimumAge }, set: { store.settings.minimumAge = $0 })
    }

    private var notifyBinding: Binding<TimeInterval?> {
        Binding(get: { store.settings.notifyAfter }, set: { store.settings.notifyAfter = $0 })
    }
}

import SwiftUI
import Detectors
import StillRunningCore

struct SettingsView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss

    private let ageChoices: [(label: String, value: TimeInterval)] = [
        ("5 minutes", 300), ("15 minutes", 900), ("30 minutes", 1800),
        ("1 hour", 3600), ("2 hours", 7200), ("4 hours", 14_400), ("8 hours", 28_800),
    ]
    private let notifyChoices: [(label: String, value: TimeInterval?)] = [
        ("Never", nil), ("After 15 minutes", 900), ("After 1 hour", 3600),
        ("After 4 hours", 14_400), ("After 8 hours", 28_800), ("After a day", 86_400),
    ]

    @State private var permission: Notifier.Permission?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Text("Still Running watches for things you started earlier and never stopped.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Picker("Consider forgotten after", selection: ageBinding) {
                ForEach(ageChoices, id: \.value) { Text($0.label).tag($0.value) }
            }
            Picker("Notify me", selection: notifyBinding) {
                ForEach(notifyChoices, id: \.label) { Text($0.label).tag($0.value) }
            }

            Section {
                HStack {
                    Button(testing ? "Sending…" : "Send a test notification") {
                        testing = true
                        Task {
                            permission = await Notifier.sendTest()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    Spacer()
                }
                if let permission {
                    Text(permission == .allowed
                         ? "Sent. If nothing appeared, check Notification Centre."
                         : permission.message)
                        .font(.system(size: 11))
                        .foregroundStyle(permission == .allowed ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Still Running never deletes anything. Every action stops a process, container, or simulator that you can start again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 300)
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

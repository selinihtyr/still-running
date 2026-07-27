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
    @State private var soundIsOn = true
    @State private var testing = false

    /// Sound is a separate per-app switch in macOS, so a silent notification is
    /// worth explaining rather than leaving the user to wonder.
    private func resultMessage(_ permission: Notifier.Permission) -> String {
        guard permission == .allowed else { return permission.message }
        return soundIsOn
            ? "Sent. If nothing appeared, check Notification Centre."
            : "Sent, silently: macOS has sound switched off for Still Running. Turn on “Play sound for notifications” in System Settings › Notifications › Still Running."
    }

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
                            soundIsOn = await Notifier.soundIsOn()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    Spacer()
                }
                if let permission {
                    Text(resultMessage(permission))
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

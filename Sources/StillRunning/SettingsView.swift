import SwiftUI
import Detectors
import StillRunningCore

/// A group of settings under an eyebrow, on the same card the panel lists
/// findings on. Nothing here is tinted: in this app colour carries what kind of
/// thing a row is about, and amber only ever means "burning CPU right now", so
/// Settings stays monochrome and spends orange on warnings alone.
private struct SettingsGroup<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title.uppercased())
                    .font(.eyebrow)
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
            .padding(.bottom, 7)

            VStack(spacing: 0) { content }
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.cardEdge)
                )
        }
    }
}

/// One setting: what it is on the left, what it means underneath it, and the
/// control that changes it on the right. The explanation belongs to the row it
/// explains rather than to a paragraph further down the window.
private struct SettingRow<Control: View>: View {
    let label: String
    var note: String?
    var isWarning = false
    /// A live figure, when the setting has a visible consequence right now.
    var readout: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.rowTitle)
                if let note {
                    Text(note)
                        .font(.rowDetail)
                        .foregroundStyle(isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let readout {
                    Text(readout)
                        .font(.readout)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

/// A setting that reads "notify me" while macOS shows nothing is off and
/// claiming to be on. That gets a row of its own rather than a note, because it
/// is the one thing on this window that means a choice above it does nothing.
private struct WarningRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(message)
                .font(.rowDetail)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 12) }
}

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

    /// Both menus are the same width so their edges line up down the window,
    /// rather than ending wherever "After 15 minutes" happens to end.
    private static let controlWidth: CGFloat = 138

    @State private var permission: Notifier.Permission?
    @State private var soundIsOn = true
    @State private var testing = false
    @State private var loginItem = LoginItem.state
    @State private var checkedForUpdates = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    forgotten
                    telling
                    thisApp
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Divider()
            footer
        }
        .frame(width: Theme.settingsWidth, height: Theme.settingsHeight)
        // Dark whatever the system is set to. The rows, the cards and the one
        // orange warning were tuned against a dark window, and this is the only
        // window the app has: it reads as one piece rather than as whichever
        // half of the palette macOS happens to be in.
        .preferredColorScheme(.dark)
        .onAppear { loginItem = LoginItem.state }
        .onChange(of: store.settings.notifyAfter) { _, new in
            if new != nil { Notifier.requestAuthorization() }
        }
        // The readout under the threshold is only true if the machine is looked
        // at again with the new number, and a closed panel is sampled once a
        // minute — too slow to be an answer to a click.
        .onChange(of: store.settings.minimumAge) { _, _ in
            Task { await store.refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 20, weight: .semibold))
            Text("Still Running watches for the things you started earlier and never stopped.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var forgotten: some View {
        SettingsGroup(symbol: "clock.arrow.circlepath", title: "What counts as forgotten") {
            SettingRow(
                label: "Consider forgotten after",
                note: "Anything older than this is listed, even while idle.",
                readout: listedNow
            ) {
                Picker("", selection: ageBinding) {
                    ForEach(ageChoices, id: \.value) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
                .frame(width: Self.controlWidth)
            }
        }
    }

    /// Settings should say what it changes, and the panel's count is the change.
    private var listedNow: String {
        switch store.findings.count {
        case 0: "Nothing is listed right now."
        case 1: "1 thing is listed right now."
        case let count: "\(count) things are listed right now."
        }
    }

    private var telling: some View {
        SettingsGroup(symbol: "bell", title: "Telling you") {
            SettingRow(
                label: "Notify me",
                // The one case where the chosen wait is not honoured, said where
                // the choice is made rather than left to be discovered as a
                // broken promise.
                note: store.settings.notifyAfter == nil
                    ? "Nothing is sent. The menu bar icon still changes."
                    : "Sooner than this for anything running away with the machine."
            ) {
                Picker("", selection: notifyBinding) {
                    ForEach(notifyChoices, id: \.label) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
                .frame(width: Self.controlWidth)
            }

            if store.notificationsSilenced {
                RowDivider()
                WarningRow(message: "macOS is not showing notifications for Still Running, so this "
                           + "setting does nothing. Turn them on in System Settings › "
                           + "Notifications › Still Running.")
            }

            RowDivider()
            SettingRow(
                label: "Test notification",
                note: permission.map(resultMessage) ?? "Checks that one actually arrives.",
                isWarning: permission.map { $0 != .allowed } ?? false
            ) {
                Button(testing ? "Sending…" : "Send one") {
                    testing = true
                    Task {
                        permission = await Notifier.sendTest()
                        soundIsOn = await Notifier.soundIsOn()
                        testing = false
                    }
                }
                .controlSize(.small)
                .disabled(testing)
            }
        }
    }

    private var thisApp: some View {
        SettingsGroup(symbol: "gearshape", title: "This app") {
            SettingRow(
                label: "Start at login",
                note: loginItem.explanation
                    ?? "It watches for things left running for hours, so it has to outlive a restart.",
                isWarning: loginItem.explanation != nil
            ) {
                Toggle("", isOn: loginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(loginItem == .unavailable)
            }

            RowDivider()
            SettingRow(
                label: "Check for updates",
                note: "One request a day for the latest version number. Off means the app "
                    + "never touches the network."
            ) {
                Toggle("", isOn: updateBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            RowDivider()
            updateRow
        }
    }

    @ViewBuilder private var updateRow: some View {
        if case .available(let found) = store.update {
            SettingRow(
                label: "Version \(found.version.description) is out",
                note: "Updating runs git pull and ./scripts/install.sh in a Terminal window you can watch."
            ) {
                Button("Update") { store.installUpdate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        } else {
            SettingRow(label: "This version", note: updateMessage, readout: Store.version) {
                Button(store.isCheckingForUpdate ? "Checking…" : "Check now") {
                    Task {
                        await store.checkForUpdate(force: true)
                        checkedForUpdates = true
                    }
                }
                .controlSize(.small)
                .disabled(store.isCheckingForUpdate)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Nothing is ever deleted. Everything here can be started again.")
                .font(.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Link("Star on GitHub", destination: UpdateChecker.repository)
                .font(.rowDetail)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    /// Sound is a separate per-app switch in macOS, so a silent notification is
    /// worth explaining rather than leaving the user to wonder.
    private func resultMessage(_ permission: Notifier.Permission) -> String {
        guard permission == .allowed else { return permission.message }
        return soundIsOn
            ? "Sent. If nothing appeared, check Notification Centre."
            : "Sent, silently: macOS has sound switched off for Still Running. Turn on “Play sound for notifications” in System Settings › Notifications › Still Running."
    }

    private var updateMessage: String {
        switch store.update {
        case .available:
            "Updating runs git pull and ./scripts/install.sh in a Terminal window."
        case .upToDate:
            "You are on the newest release."
        case .unknown:
            checkedForUpdates
                ? "Could not reach GitHub. Nothing is assumed either way."
                : "Whether a newer one exists has not been established yet."
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { loginItem.isOn }, set: { loginItem = LoginItem.setEnabled($0) })
    }

    private var updateBinding: Binding<Bool> {
        Binding(get: { store.settings.checksForUpdates },
                set: { on in
                    store.settings.checksForUpdates = on
                    if on { Task { await store.checkForUpdate(force: true) } }
                })
    }

    private var ageBinding: Binding<TimeInterval> {
        Binding(get: { store.settings.minimumAge }, set: { store.settings.minimumAge = $0 })
    }

    private var notifyBinding: Binding<TimeInterval?> {
        Binding(get: { store.settings.notifyAfter }, set: { store.settings.notifyAfter = $0 })
    }
}

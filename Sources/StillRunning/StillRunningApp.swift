import SwiftUI
import StillRunningCore

@main
struct StillRunningApp: App {
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            // A clean machine gets a quiet menu bar: icon only, no number.
            Image(systemName: store.findings.isEmpty ? "circle" : "circle.dotted.circle")
            if !store.findings.isEmpty {
                Text("\(store.findings.count)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

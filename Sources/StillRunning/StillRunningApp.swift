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
            // Sampling belongs here rather than on the panel: the label is the
            // only view that always exists, so the badge is right before the
            // user has ever opened anything.
            Color.clear.frame(width: 0, height: 0)
                .task { store.startSampling() }
        }
        .menuBarExtraStyle(.window)
    }
}

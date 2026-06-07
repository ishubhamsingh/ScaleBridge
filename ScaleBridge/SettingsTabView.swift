import SwiftUI

// MARK: - SettingsTabView
//
// Placeholder for the Settings tab. Will be fully implemented in Phase 9.
// The NavigationStack is here so the nav title renders correctly and future
// NavigationLinks can push from this root.

struct SettingsTabView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Units", systemImage: "ruler")
                    Label("Apple Health", systemImage: "heart")
                    Label("Scale", systemImage: "scalemass")
                } header: {
                    Text("Coming in Phase 9")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

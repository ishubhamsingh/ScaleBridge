import SwiftUI
import SwiftData

// MARK: - HistoryTabWrapper
//
// Bridges the History tab → HistoryView, which requires a specific UserProfile.
// Resolves the active profile from AppStorage (same logic as ContentView) and
// falls back gracefully when no profiles exist yet.
// Phase 6 will replace this with the full History — Trends screen.

struct HistoryTabWrapper: View {
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @AppStorage("activeUserID") private var activeUserIDString: String = ""

    private var activeProfile: UserProfile? {
        if let uuid = UUID(uuidString: activeUserIDString),
           let match = profiles.first(where: { $0.id == uuid }) {
            return match
        }
        return profiles.first(where: { $0.isPrimary }) ?? profiles.first
    }

    var body: some View {
        NavigationStack {
            if let profile = activeProfile {
                HistoryView(profile: profile)
            } else {
                ContentUnavailableView {
                    Label("No Profile", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("Add a profile in the Profiles tab to see your history.")
                }
                .navigationTitle("History")
            }
        }
    }
}

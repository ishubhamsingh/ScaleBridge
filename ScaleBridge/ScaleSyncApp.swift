import SwiftUI
import SwiftData
import WidgetKit
import FirebaseCore
import GoogleSignIn

@main
struct ScaleSyncApp: App {

    @State private var backupManager = CloudBackupManager()

    init() {
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    // Build the ModelContainer manually so we can recover from schema mismatches
    // that happen during development (e.g. adding/renaming model properties).
    let container: ModelContainer = {
        let schema = Schema([UserProfile.self, WeighIn.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema mismatch or corrupt store — wipe the SQLite file and start fresh.
            // (Development only — for production, replace with a proper migration plan.)
            print("⚠️ SwiftData container failed (\(error.localizedDescription)). Wiping store.")
            let storeURL = config.url
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: storeURL.path + suffix)
                )
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("SwiftData: cannot create container even after store wipe: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environment(backupManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(container)
    }
}

// MARK: - AppGate
//
// Shown as the root view. Presents OnboardingView on first launch (no profile
// + flag not set); transitions to RootTabView once onboarding is complete.
// The `!profiles.isEmpty` fallback handles data-migration edge cases where
// a user already has profiles but the flag was never written.

struct AppGate: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query private var profiles: [UserProfile]

    var body: some View {
        if hasCompletedOnboarding || !profiles.isEmpty {
            RootTabView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - TabRouter

enum AppTab: String {
    case today, history, profiles, settings
}

final class TabRouter: ObservableObject {
    @Published var selectedTab: AppTab = .today
}

// MARK: - RootTabView
//
// The persistent TabView shell. Each tab gets its own NavigationStack so
// the back-stack is independent per tab (standard iOS convention).
// The glass tab bar renders automatically on iOS 26.

struct RootTabView: View {
    @StateObject private var router = TabRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Today", systemImage: "house", value: AppTab.today) {
                HomeView()
            }
            Tab("History", systemImage: "chart.bar", value: AppTab.history) {
                HistoryTabWrapper()
            }
            Tab("Profiles", systemImage: "person.2", value: AppTab.profiles) {
                ProfilesView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsTabView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environmentObject(router)
    }
}

struct ContentView: View {
    @StateObject private var ble = ScaleBLEManager(
        parser: QNScaleParser(),
        user: ScaleUser(isMale: true, age: 30, heightCm: 175, usePounds: false)
    )
    private let healthKit = HealthKitWriter()

    @Environment(\.modelContext) private var context

    // All profiles, so we can find/show the active one.
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    // Persisted ID of the chosen user; falls back to primary / first profile.
    @AppStorage("activeUserID") private var activeUserIDString: String = ""

    @State private var showingProfiles   = false
    @State private var showingUserPicker = false
    @State private var showingHistory    = false
    @State private var historyProfile: UserProfile? = nil

    // MARK: Active user

    private var activeUser: UserProfile? {
        if let uuid = UUID(uuidString: activeUserIDString),
           let match = profiles.first(where: { $0.id == uuid }) {
            return match
        }
        // Fall back to primary, then first
        return profiles.first(where: { $0.isPrimary }) ?? profiles.first
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                activeUserSection
                statusSection
                if let m = ble.lastMeasurement { readingSection(m) }
                logSection
            }
            .navigationTitle("ScaleBridge")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingProfiles = true }
                        label: { Image(systemName: "person.2") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(ble.status == .scanning ? "Stop" : "Weigh in") {
                        if ble.status == .scanning {
                            ble.stop()
                        } else {
                            // Wire the selected user's real biometrics in before scanning.
                            if let u = activeUser { ble.user = u.scaleUser }
                            ble.start()
                        }
                    }
                    .disabled(profiles.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showingHistory) {
                if let p = historyProfile {
                    HistoryView(profile: p)
                }
            }
            .sheet(isPresented: $showingProfiles) { ProfilesView() }
            .sheet(isPresented: $showingUserPicker) { userPickerSheet }
            .task { try? await healthKit.requestAuthorization() }
            .onChange(of: ble.status) { _, newStatus in
                if case .done = newStatus, let measurement = ble.lastMeasurement {
                    persistMeasurement(measurement)
                }
            }
        }
    }

    // MARK: List sections

    private var activeUserSection: some View {
        Section {
            if let user = activeUser {
                Button {
                    guard profiles.count > 1 else { return }
                    showingUserPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Text(user.avatar)
                            .font(.system(size: 30))
                            .frame(width: 44, height: 44)
                            .background(.quaternary, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(user.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profiles.count > 1 {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button("Add a profile to get started") { showingProfiles = true }
                    .foregroundStyle(Color.accentColor)
            }

            if let user = activeUser {
                Button {
                    historyProfile = user
                    showingHistory = true
                } label: {
                    Label("View history", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Weighing for")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            Text(statusText).font(.headline)
            // Only show BLE details when they contain useful info.
            // Many scales don't advertise a name or service UUIDs in their
            // advertisement packets — that's normal and doesn't affect operation.
            let knownName = ble.discoveredName.isEmpty || ble.discoveredName == "(no name)"
                ? nil : ble.discoveredName
            let knownSvcs = ble.discoveredServices.filter { !$0.isEmpty }
            if let name = knownName {
                LabeledContent("Scale", value: name)
            }
            if !knownSvcs.isEmpty {
                LabeledContent("Services", value: knownSvcs.joined(separator: ", "))
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func readingSection(_ m: ScaleMeasurement) -> some View {
        Section("Last reading") {
            LabeledContent("Weight",     value: String(format: "%.2f kg", m.weightKg))
            if let f  = m.fatPercent    { LabeledContent("Body fat",  value: String(format: "%.1f %%", f))  }
            if let w  = m.waterPercent  { LabeledContent("Water",     value: String(format: "%.1f %%", w))  }
            if let mu = m.musclePercent { LabeledContent("Muscle",    value: String(format: "%.1f %%", mu)) }
            if let l  = m.leanMassKg   { LabeledContent("Lean mass", value: String(format: "%.2f kg", l))  }
            LabeledContent("Impedance (raw)", value: String(format: "%.0f", m.impedance))
        }
    }

    private var logSection: some View {
        Section("Diagnostic log") {
            ForEach(ble.logLines.suffix(40), id: \.self) {
                Text($0).font(.system(.caption2, design: .monospaced))
            }
        }
    }

    // MARK: User picker sheet

    private var userPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(profiles, id: \.id) { profile in
                    Button {
                        activeUserIDString = profile.id.uuidString
                        showingUserPicker  = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(profile.avatar)
                                .font(.system(size: 28))
                                .frame(width: 40, height: 40)
                                .background(.quaternary, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(profile.name).font(.headline).foregroundStyle(.primary)
                                    if profile.isPrimary {
                                        Image(systemName: "star.fill")
                                            .font(.caption2).foregroundStyle(.yellow)
                                    }
                                }
                                Text(profile.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.id == activeUser?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Who's weighing in?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingUserPicker = false }
                }
            }
        }
    }

    // MARK: Measurement persistence

    /// Called once per stable reading (when BLE status transitions to .done).
    /// Saves to SwiftData for all users; syncs to Apple Health only for the primary user.
    private func persistMeasurement(_ measurement: ScaleMeasurement) {
        guard let user = activeUser else {
            ble.log("No active profile — reading not saved.")
            return
        }

        // Always save to local SwiftData store.
        let weighIn = WeighIn(from: measurement, user: user)
        context.insert(weighIn)

        SharedStore.write(weighIn: weighIn)
        SharedStore.writeHistory(weighIns: user.sortedWeighIns)
        if user.isPrimary {
            // Primary user: write to Apple Health asynchronously.
            Task {
                do {
                    try await healthKit.save(measurement)
                    weighIn.syncedToHealthKit = true
                    try? context.save()
                    ble.log("Saved to Apple Health ✓")
                } catch {
                    try? context.save()   // still keep the local record
                    ble.log("HealthKit save failed: \(error.localizedDescription)")
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
        } else {
            // Non-primary user: local only.
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
            ble.log("Reading saved locally (Health sync is for the primary profile only).")
        }
    }

    // MARK: Helpers

    private var statusText: String {
        switch ble.status {
        case .idle:         return profiles.isEmpty
                                ? "Add a profile first"
                                : "Tap 'Weigh in', then step on the scale"
        case .scanning:     return "Scanning for scale…"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .reading:      return "Waiting for a stable reading…"
        case .done:         return "Done ✓"
        case .error(let e): return "Error: \(e)"
        }
    }
}

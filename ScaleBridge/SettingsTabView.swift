import SwiftUI
import SwiftData
import UIKit

struct SettingsTabView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.openURL)      private var openURL
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @AppStorage("activeUserID")    private var activeUserIDString: String = ""
    @AppStorage("weightUnit")      private var weightUnitRaw: String = "kg"
    @AppStorage("heightUnit")      private var heightUnitRaw: String = HeightUnit.cm.rawValue
    @AppStorage("syncToHealthKit") private var syncToHealthKit: Bool = true

    @Environment(CloudBackupManager.self) private var backup
    private let healthKit = HealthKitWriter.shared

    @State private var showingEraseAlert   = false
    @State private var editTarget: UserProfile? = nil
    @State private var showingLicenses     = false
    @State private var showingPrivacy      = false
    @State private var showingCloudBackup  = false
    @State private var showingDiagnostics  = false

    // MARK: Derived

    private var activeProfile: UserProfile? {
        if let uuid = UUID(uuidString: activeUserIDString),
           let match = profiles.first(where: { $0.id == uuid }) { return match }
        return profiles.first(where: { $0.isPrimary }) ?? profiles.first
    }

    private var lastConnectedLabel: String {
        guard let date = activeProfile?.latestWeighIn?.date else { return "Never" }
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today, \(date.formatted(.dateTime.hour().minute()))" }
        if cal.isDateInYesterday(date) { return "Yesterday, \(date.formatted(.dateTime.hour().minute()))" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (build \(b))"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    navHeader

                    if let profile = activeProfile {
                        activeProfileCard(profile)
                    }

                    scaleSection
                    unitsSection
                    if activeProfile?.isPrimary == true {
                        appleHealthSection
                    } else {
                        nonPrimaryHealthNote
                    }
                    backupSection
                    dataSection
                    aboutSection
                }
                .padding(.horizontal, DS.Space.screenGutter)
                .padding(.top, DS.Space.m)
                .padding(.bottom, 100)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingCloudBackup) {
                CloudBackupView()
            }
            .navigationDestination(isPresented: $showingDiagnostics) {
                DiagnosticLogView()
            }
            .task { healthKit.refreshStatus() }
        }
        .sheet(item: $editTarget) { profile in
            ProfileEditView(existingProfile: profile, isFirstProfile: false) { data in
                commitProfileSave(data: data, updating: profile)
            }
        }
        .sheet(isPresented: $showingLicenses) { OpenSourceView() }
        .sheet(isPresented: $showingPrivacy)  { PrivacyPolicyView() }
        .alert("Erase all data?", isPresented: $showingEraseAlert) {
            Button("Erase", role: .destructive) { eraseAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all weigh-in readings for every profile. Profile details are kept. This cannot be undone.")
        }
    }

    // MARK: - Nav header

    private var navHeader: some View {
        Text("Settings")
            .font(DS.Typeface.largeTitle)
            .foregroundStyle(DS.Palette.label)
    }

    // MARK: - Active profile card

    private func activeProfileCard(_ profile: UserProfile) -> some View {
        Button { editTarget = profile } label: {
            HStack(spacing: DS.Space.m) {
                Text(profile.avatar)
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(DS.Palette.ground, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DS.Space.xs) {
                        Text(profile.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(DS.Palette.label)
                        if profile.isPrimary {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                        }
                    }
                    let count = profile.weighIns.count
                    Text("\(profile.isPrimary ? "Primary profile" : "Family member") · \(count) reading\(count == 1 ? "" : "s")")
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 68)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scale section

    private var scaleSection: some View {
        settingsSection("SCALE") {
            // Connected scale
            HStack(spacing: DS.Space.m) {
                iconBox("scalemass", color: .indigo)
                Text("Connected scale")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Text("QN Scale")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 50)

            rowDivider()

            // Last connected
            HStack(spacing: DS.Space.m) {
                iconBox("bolt.fill", color: .green)
                Text("Last connected")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Text(lastConnectedLabel)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 50)

        }
    }

    // MARK: - Units section

    private var unitsSection: some View {
        settingsSection("UNITS") {
            HStack {
                Text("Weight")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Picker("", selection: $weightUnitRaw) {
                    Text("kg").tag("kg")
                    Text("lb").tag("lb")
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 52)

            rowDivider()

            HStack {
                Text("Height")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Picker("", selection: $heightUnitRaw) {
                    Text("cm").tag(HeightUnit.cm.rawValue)
                    Text("ft · in").tag(HeightUnit.ftIn.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 52)
        }
    }

    // MARK: - Apple Health status

    private var healthStatusLabel: String {
        switch healthKit.status {
        case .unknown:       return "Checking…"
        case .unavailable:   return "Unavailable"
        case .notDetermined: return "Not asked"
        case .authorized:    return "Allowed"
        case .partial:       return "Partial"
        case .denied:        return "Denied"
        }
    }

    private var healthStatusColor: Color {
        switch healthKit.status {
        case .authorized:              return DS.Palette.positive
        case .partial:                 return DS.Palette.bodyFat
        case .denied, .unavailable:    return DS.Palette.muscle
        case .unknown, .notDetermined: return DS.Palette.secondaryLabel
        }
    }

    private var healthStatusIcon: String {
        switch healthKit.status {
        case .authorized:              return "checkmark.circle.fill"
        case .partial:                 return "exclamationmark.circle.fill"
        case .denied, .unavailable:    return "xmark.circle.fill"
        case .unknown, .notDetermined: return "questionmark.circle.fill"
        }
    }

    // MARK: - Apple Health section

    private var appleHealthSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("APPLE HEALTH")

            VStack(spacing: 0) {
                // Sync toggle
                HStack(spacing: DS.Space.m) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("Sync to Apple Health")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Toggle("", isOn: $syncToHealthKit)
                        .labelsHidden()
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 52)
                .onChange(of: syncToHealthKit) { _, isOn in
                    // Turning the switch on is the user asking for Health access —
                    // it has to actually request it, not just record a preference.
                    guard isOn else { return }
                    Task { await healthKit.requestAuthorization() }
                }

                rowDivider()

                // Permission status
                HStack(spacing: DS.Space.m) {
                    Image(systemName: healthStatusIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(healthStatusColor)
                        .frame(width: 32, height: 32)
                        .background(DS.Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permission")
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.label)
                        if let err = healthKit.lastError {
                            Text(err)
                                .font(DS.Typeface.caption)
                                .foregroundStyle(DS.Palette.muscle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Text(healthStatusLabel)
                        .font(DS.Typeface.subheadline)
                        .foregroundStyle(healthStatusColor)
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 52)

                rowDivider()

                // Manage permissions
                Button {
                    if let url = URL(string: "x-apple-health://") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                            .frame(width: 32, height: 32)
                            .background(DS.Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text("Manage permissions in Health app")
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.weight)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.weight)
                    }
                    .padding(.horizontal, DS.Space.l)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Only the primary profile's readings sync. ScaleBridge writes Weight, Body Fat, Lean Body Mass, and BMI to Apple Health.")
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .padding(.leading, DS.Space.xs)
        }
    }

    // MARK: - Non-primary Health note

    private var nonPrimaryHealthNote: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("APPLE HEALTH")
            HStack(spacing: DS.Space.m) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .frame(width: 32, height: 32)
                    .background(DS.Palette.ground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Apple Health sync is only available for the primary profile.")
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 56)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Backup section

    private var backupSection: some View {
        settingsSection("BACKUP") {
            Button { showingCloudBackup = true } label: {
                HStack(spacing: DS.Space.m) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.indigo,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("Cloud Backup")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Text(backup.isSignedIn ? backup.userEmail : "Not set up")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data section

    private var diagnosticsRow: some View {
        Button { showingDiagnostics = true } label: {
            HStack {
                Text("Scale diagnostic log")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.weight)
                Spacer()
                Text("\(ScaleDiagnosticsLog.shared.lines.count)")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dataSection: some View {
        settingsSection("DATA") {
            // Export CSV — temp .csv URL so share sheet offers CSV, not plain text
            ShareLink(item: csvExportURL) {
                HStack {
                    Text("Export readings as CSV")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.weight)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            rowDivider()

            diagnosticsRow

            rowDivider()

            // Erase all data
            Button { showingEraseAlert = true } label: {
                HStack {
                    Text("Erase all data…")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.muscle)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("ABOUT")

            VStack(spacing: 0) {
                // Version
                HStack {
                    Text("Version")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Text(appVersion)
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 50)

                rowDivider()

                // Open-source acknowledgments
                Button { showingLicenses = true } label: {
                    HStack {
                        Text("Open-source acknowledgments")
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.weight)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.tertiaryLabel)
                    }
                    .padding(.horizontal, DS.Space.l)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                rowDivider()

                // Privacy policy
                Button { showingPrivacy = true } label: {
                    HStack {
                        Text("Privacy policy")
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.weight)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.weight)
                    }
                    .padding(.horizontal, DS.Space.l)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Body composition formulas ported from openScale's TrisaBodyAnalyzeLib (GPLv3).")
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .padding(.leading, DS.Space.xs)
        }
    }

    // MARK: - Reusable building blocks

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel(title)
            VStack(spacing: 0) { content() }
                .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typeface.dateCaps)
            .tracking(0.04 * 13)
            .foregroundStyle(DS.Palette.secondaryLabel)
    }

    private func iconBox(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func rowDivider() -> some View {
        Divider().padding(.leading, DS.Space.l)
    }

    // MARK: - Data operations

    private var csvExportURL: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScaleBridge_Readings.csv")
        try? generateCSV().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func generateCSV() -> String {
        var lines = ["Date,Profile,Weight (kg),Body Fat (%),Muscle (%),Water (%),BMI,Lean Mass (kg),Bone (%)"]
        for profile in profiles {
            for w in profile.sortedWeighIns {
                let row: [String] = [
                    ISO8601DateFormatter().string(from: w.date),
                    profile.name,
                    String(format: "%.2f", w.weightKg),
                    w.fatPercent.map    { String(format: "%.1f", $0) } ?? "",
                    w.musclePercent.map { String(format: "%.1f", $0) } ?? "",
                    w.waterPercent.map  { String(format: "%.1f", $0) } ?? "",
                    w.bmi.map           { String(format: "%.1f", $0) } ?? "",
                    w.leanMassKg.map    { String(format: "%.2f", $0) } ?? "",
                    w.bonePercent.map   { String(format: "%.1f", $0) } ?? ""
                ]
                lines.append(row.joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n")
    }

    private func eraseAllData() {
        let doomed = profiles.flatMap(\.weighIns)
        // Capture before deletion — these objects are about to leave the store.
        let ids = doomed.map(\.id)
        let healthDates = doomed.filter(\.syncedToHealthKit).map(\.date)

        for w in doomed { context.delete(w) }
        try? context.save()

        // The alert promises this can't be undone, so the cloud copy has to go too —
        // otherwise a later restore brings every reading back.
        Task {
            for date in healthDates { await healthKit.deleteSamples(around: date) }
            await backup.deleteWeighIns(ids: ids)
        }
    }

    private func commitProfileSave(data: ProfileFormData, updating profile: UserProfile) {
        if data.isPrimary { profiles.forEach { $0.isPrimary = false } }
        profile.name        = data.name
        profile.isMale      = data.isMale
        profile.dateOfBirth = data.dateOfBirth
        profile.heightCm    = data.heightCm
        profile.isPrimary   = data.isPrimary
        profile.avatar      = data.avatar
        try? context.save()
    }
}

// MARK: - OpenSourceView

private struct OpenSourceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    licenseCard(
                        name: "openScale — TrisaBodyAnalyzeLib",
                        license: "GPLv3",
                        url: "https://github.com/oliexdev/openScale",
                        description: "Body composition formulas (body fat, muscle, water, bone, lean mass) are ported from openScale's TrisaBodyAnalyzeLib. ScaleBridge is a derivative work and is also distributed under GPLv3."
                    )
                    licenseCard(
                        name: "Swift / SwiftUI / SwiftData",
                        license: "Apple Frameworks",
                        url: nil,
                        description: "UI, persistence, and Combine reactivity built with Apple's first-party frameworks. CoreBluetooth powers the BLE scale connection."
                    )
                }
                .padding(DS.Space.screenGutter)
                .padding(.bottom, 40)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .navigationTitle("Open-Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func licenseCard(name: String, license: String, url: String?, description: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(DS.Typeface.bodyMedium)
                        .foregroundStyle(DS.Palette.label)
                    if let url {
                        Text(url)
                            .font(DS.Typeface.caption)
                            .foregroundStyle(DS.Palette.weight)
                    }
                }
                Spacer()
                Text(license)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.muscle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.Palette.muscle.opacity(0.12),
                                in: Capsule())
            }
            Text(description)
                .font(DS.Typeface.subheadline)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - PrivacyPolicyView

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    privacyCard(
                        icon: "iphone",
                        title: "All data stays on your device",
                        body: "ScaleBridge stores every weigh-in reading in SwiftData — a local, on-device database. No data is uploaded to any server, cloud service, or third party at any point."
                    )
                    privacyCard(
                        icon: "heart.fill",
                        title: "Apple Health (optional)",
                        body: "If you enable Apple Health sync, weight, body fat percentage, lean body mass, and BMI are written to HealthKit for the primary profile only. This data stays within Apple's Health framework and is subject to Apple's privacy policy. You can disable sync in Settings at any time."
                    )
                    privacyCard(
                        icon: "person.2",
                        title: "Multiple profiles",
                        body: "Secondary profiles are stored locally only and are never synced to Apple Health. All profile data (name, age, height, sex) is kept on device."
                    )
                    privacyCard(
                        icon: "trash",
                        title: "Deleting your data",
                        body: "All readings can be permanently deleted from Settings → Erase all data. Individual readings can be deleted from Reading Detail. Deleting the app removes all local data immediately."
                    )
                }
                .padding(DS.Space.screenGutter)
                .padding(.bottom, 40)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func privacyCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Palette.weight)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title)
                    .font(DS.Typeface.bodyMedium)
                    .foregroundStyle(DS.Palette.label)
                Text(body)
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Diagnostic log
//
// Frame-level view of the last BLE session. This is what distinguishes a protocol
// problem from a genuine reading — without it, a silent misparse looks identical
// to a scale that simply measured you wrong.

struct DiagnosticLogView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var log: ScaleDiagnosticsLog { ScaleDiagnosticsLog.shared }

    var body: some View {
        ScrollView {
            if log.lines.isEmpty {
                VStack(spacing: DS.Space.s) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                    Text("No entries yet")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    Text("Weigh in once, then come back here to see the frames the scale sent.")
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
                .padding(.horizontal, DS.Space.xl)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DS.Palette.label)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.l)
                .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, DS.Space.screenGutter)
                .padding(.vertical, DS.Space.m)
            }
        }
        .background(DS.Palette.ground.ignoresSafeArea())
        .navigationTitle("Diagnostic Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        UIPasteboard.general.string = log.exportText
                        copied = true
                    } label: {
                        Label("Copy log", systemImage: "doc.on.doc")
                    }
                    .disabled(log.lines.isEmpty)

                    Button(role: .destructive) {
                        log.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(log.lines.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Copied", isPresented: $copied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The diagnostic log is on your clipboard.")
        }
    }
}

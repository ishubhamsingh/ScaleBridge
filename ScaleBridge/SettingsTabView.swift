import SwiftUI
import SwiftData

struct SettingsTabView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.openURL)      private var openURL
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @AppStorage("activeUserID")    private var activeUserIDString: String = ""
    @AppStorage("weightUnit")      private var weightUnitRaw: String = "kg"
    @AppStorage("heightUnit")      private var heightUnitRaw: String = HeightUnit.cm.rawValue
    @AppStorage("syncToHealthKit") private var syncToHealthKit: Bool = true

    @State private var showingEraseAlert = false
    @State private var editTarget: UserProfile? = nil

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
                dataSection
                aboutSection
            }
            .padding(.horizontal, DS.Space.screenGutter)
            .padding(.top, DS.Space.m)
            .padding(.bottom, 100)
        }
        .background(DS.Palette.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editTarget) { profile in
            ProfileEditView(existingProfile: profile, isFirstProfile: false) { data in
                commitProfileSave(data: data, updating: profile)
            }
        }
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

    // MARK: - Data section

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

                // Open-source acknowledgments (Phase 12)
                Button { } label: {
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

                // Privacy policy (Phase 12)
                Button { } label: {
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
        for profile in profiles {
            for w in profile.weighIns { context.delete(w) }
        }
        try? context.save()
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

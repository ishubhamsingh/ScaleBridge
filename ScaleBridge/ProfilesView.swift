import SwiftUI
import SwiftData

// MARK: - ProfileFormData
// Plain value type that ProfileEditView hands back to ProfilesView.
// ProfilesView owns the model context and performs the actual insert/update.

struct ProfileFormData {
    var name:        String
    var isMale:      Bool
    var dateOfBirth: Date
    var heightCm:    Float
    var isPrimary:   Bool
    var avatar:      String
}

// MARK: - ProfilesView

struct ProfilesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var showingAdd  = false
    @State private var editTarget: UserProfile?

    var body: some View {
        NavigationStack {
            Group {
                if profiles.isEmpty { emptyState } else { profileList }
            }
            .navigationTitle("Family Members")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            // Add — ProfileEditView gets no context; ProfilesView handles the insert
            .sheet(isPresented: $showingAdd) {
                ProfileEditView(
                    existingProfile: nil,
                    isFirstProfile: profiles.isEmpty
                ) { data in
                    commitSave(data: data, updating: nil)
                }
            }
            // Edit
            .sheet(item: $editTarget) { profile in
                ProfileEditView(
                    existingProfile: profile,
                    isFirstProfile: false
                ) { data in
                    commitSave(data: data, updating: profile)
                }
            }
        }
    }

    // MARK: Subviews

    private var profileList: some View {
        List {
            ForEach(profiles) { profile in
                ProfileRow(profile: profile)
                    .contentShape(Rectangle())
                    .onTapGesture { editTarget = profile }
            }
            .onDelete(perform: deleteProfiles)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("No profiles yet")
                .font(.title3).bold()
            Text("Add yourself first, then other family members.\nThe first profile becomes the primary user.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add Profile") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: SwiftData writes (all happen here — one sheet level deep, valid context)

    private func commitSave(data: ProfileFormData, updating existing: UserProfile?) {
        // Demote current primary if the new/edited profile is taking the crown
        if data.isPrimary {
            profiles.forEach { $0.isPrimary = false }
        }

        if let profile = existing {
            profile.name        = data.name
            profile.isMale      = data.isMale
            profile.dateOfBirth = data.dateOfBirth
            profile.heightCm    = data.heightCm
            profile.isPrimary   = data.isPrimary
            profile.avatar      = data.avatar
        } else {
            context.insert(UserProfile(
                name:        data.name,
                isMale:      data.isMale,
                dateOfBirth: data.dateOfBirth,
                heightCm:    data.heightCm,
                isPrimary:   data.isPrimary,
                avatar:      data.avatar
            ))
        }
        try? context.save()
    }

    private func deleteProfiles(at offsets: IndexSet) {
        for index in offsets {
            let profile = profiles[index]
            let wasPrimary = profile.isPrimary
            let remaining  = profiles.filter { $0.id != profile.id }
            context.delete(profile)
            if wasPrimary, let next = remaining.first { next.isPrimary = true }
        }
        try? context.save()
    }
}

// MARK: - ProfileRow

private struct ProfileRow: View {
    let profile: UserProfile
    @AppStorage("heightUnit") private var heightUnitRaw: String = HeightUnit.cm.rawValue

    var body: some View {
        HStack(spacing: 14) {
            Text(profile.avatar)
                .font(.system(size: 34))
                .frame(width: 48, height: 48)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name).font(.headline)
                    if profile.isPrimary {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                let unit = HeightUnit(rawValue: heightUnitRaw) ?? .cm
                Text("\(profile.isMale ? "♂" : "♀") · \(profile.age) y · \(profile.heightCm.heightString(unit: unit))")
                    .font(.caption).foregroundStyle(.secondary)
                if let latest = profile.latestWeighIn {
                    Text("Last: \(latest.weightString) · \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ProfileEditView
// Pure UI: collects values, fires onSave closure. No SwiftData dependency.

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("heightUnit") private var heightUnitRaw: String = HeightUnit.cm.rawValue

    let existingProfile: UserProfile?
    let isFirstProfile:  Bool
    let onSave: (ProfileFormData) -> Void

    @State private var name:        String
    @State private var isMale:      Bool
    @State private var dateOfBirth: Date
    @State private var heightCm:    Double
    @State private var isPrimary:   Bool
    @State private var avatar:      String

    init(existingProfile: UserProfile?, isFirstProfile: Bool, onSave: @escaping (ProfileFormData) -> Void) {
        self.existingProfile = existingProfile
        self.isFirstProfile  = isFirstProfile
        self.onSave          = onSave
        _name        = State(initialValue: existingProfile?.name ?? "")
        _isMale      = State(initialValue: existingProfile?.isMale ?? true)
        _dateOfBirth = State(initialValue: existingProfile?.dateOfBirth
                             ?? Calendar.current.date(byAdding: .year, value: -28, to: .now)!)
        _heightCm    = State(initialValue: Double(existingProfile?.heightCm ?? 170))
        _isPrimary   = State(initialValue: existingProfile?.isPrimary ?? false)
        _avatar      = State(initialValue: existingProfile?.avatar ?? "👤")
    }

    // MARK: Derived

    private var heightUnit: HeightUnit { HeightUnit(rawValue: heightUnitRaw) ?? .cm }

    private var primaryLocked: Bool {
        isFirstProfile || existingProfile?.isPrimary == true
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var dobRange: ClosedRange<Date> {
        let cal  = Calendar.current
        let old  = cal.date(byAdding: .year, value: -120, to: .now)!
        let young = cal.date(byAdding: .year, value: -5,   to: .now)!
        return old...young
    }

    // MARK: Height bindings

    private var feetBinding: Binding<Int> {
        Binding(
            get: { Int(round(heightCm / 2.54)) / 12 },
            set: { ft in heightCm = Double(ft * 12 + Int(round(heightCm / 2.54)) % 12) * 2.54 }
        )
    }

    private var inchesBinding: Binding<Int> {
        Binding(
            get: { Int(round(heightCm / 2.54)) % 12 },
            set: { inches in heightCm = Double(Int(round(heightCm / 2.54)) / 12 * 12 + inches) * 2.54 }
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                detailsSection
                heightSection
                primarySection
            }
            .navigationTitle(existingProfile == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear { if isFirstProfile { isPrimary = true } }
        }
    }

    // MARK: Sections

    private var avatarSection: some View {
        Section("Avatar") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                ForEach(UserProfile.avatarOptions, id: \.self) { emoji in
                    Button { avatar = emoji } label: {
                        Text(emoji).font(.title2)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .background(
                                avatar == emoji ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $name).autocorrectionDisabled()
            Picker("Sex", selection: $isMale) {
                Text("Male").tag(true)
                Text("Female").tag(false)
            }
            .pickerStyle(.segmented)
            DatePicker("Date of birth", selection: $dateOfBirth,
                       in: dobRange, displayedComponents: .date)
        }
    }

    private var heightSection: some View {
        Section {
            Picker("Unit", selection: $heightUnitRaw) {
                Text("cm").tag(HeightUnit.cm.rawValue)
                Text("ft · in").tag(HeightUnit.ftIn.rawValue)
            }
            .pickerStyle(.segmented)

            if heightUnit == .cm {
                Stepper("\(Int(heightCm)) cm", value: $heightCm, in: 100...220, step: 1)
            } else {
                Stepper("\(feetBinding.wrappedValue) ft",   value: feetBinding,   in: 3...7)
                Stepper("\(inchesBinding.wrappedValue) in", value: inchesBinding, in: 0...11)
            }
        } header: {
            Text("Height")
        } footer: {
            let mirror = heightUnit == .cm
                ? "\(feetBinding.wrappedValue) ft \(inchesBinding.wrappedValue) in"
                : "\(Int(heightCm)) cm"
            Text("≈ \(mirror)").foregroundStyle(.secondary)
        }
    }

    private var primarySection: some View {
        Section {
            Toggle(isOn: primaryLocked ? .constant(true) : $isPrimary) {
                Label("Primary user", systemImage: "star.fill")
                    .foregroundStyle(isPrimary || primaryLocked ? .yellow : .secondary)
            }
            .disabled(primaryLocked)
        } footer: {
            Text(primaryLocked
                 ? "This is your primary profile — readings sync to Apple Health."
                 : "Only the primary user's readings are written to Apple Health. Others are stored locally.")
        }
    }

    // MARK: Save — just calls the closure; no SwiftData here

    private func save() {
        let shouldBePrimary = isPrimary || isFirstProfile
        onSave(ProfileFormData(
            name:        name.trimmingCharacters(in: .whitespaces),
            isMale:      isMale,
            dateOfBirth: dateOfBirth,
            heightCm:    Float(heightCm),
            isPrimary:   shouldBePrimary,
            avatar:      avatar
        ))
        dismiss()
    }
}

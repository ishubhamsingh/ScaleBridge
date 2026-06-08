import SwiftUI
import SwiftData

// MARK: - ProfileFormData

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
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @AppStorage("activeUserID") private var activeUserIDString: String = ""
    @AppStorage("weightUnit")   private var weightUnitRaw: String = "kg"

    @State private var showingAdd  = false
    @State private var editTarget: UserProfile? = nil

    // MARK: Derived

    private var activeProfile: UserProfile? {
        if let uuid = UUID(uuidString: activeUserIDString),
           let match = profiles.first(where: { $0.id == uuid }) { return match }
        return profiles.first(where: { $0.isPrimary }) ?? profiles.first
    }

    // MARK: Body

    var body: some View {
        Group {
            if profiles.isEmpty { emptyState } else { scrollContent }
        }
        .background(DS.Palette.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAdd) {
            ProfileEditView(existingProfile: nil, isFirstProfile: profiles.isEmpty) { data in
                commitSave(data: data, updating: nil)
            }
        }
        .sheet(item: $editTarget) { profile in
            ProfileEditView(existingProfile: profile, isFirstProfile: false) { data in
                commitSave(data: data, updating: profile)
            }
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                navHeader
                profileCard
                footerNote
            }
            .padding(.horizontal, DS.Space.screenGutter)
            .padding(.top, DS.Space.m)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Nav header

    private var navHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("FAMILY · \(profiles.count) \(profiles.count == 1 ? "MEMBER" : "MEMBERS")")
                .font(DS.Typeface.dateCaps)
                .tracking(0.04 * 13)
                .foregroundStyle(DS.Palette.secondaryLabel)

            HStack(alignment: .center) {
                Text("Profiles")
                    .font(DS.Typeface.largeTitle)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Palette.weight)
                        .frame(width: 38, height: 38)
                        .background(DS.Palette.card, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { idx, profile in
                profileRow(profile)
                if idx < profiles.count - 1 {
                    Divider().padding(.leading, 76)
                }
            }
        }
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func profileRow(_ profile: UserProfile) -> some View {
        let isActive = profile.id == activeProfile?.id
        return HStack(spacing: DS.Space.m) {
            // Avatar
            Text(profile.avatar)
                .font(.system(size: 28))
                .frame(width: 52, height: 52)
                .background(DS.Palette.ground, in: Circle())

            // Info column
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
                    if isActive {
                        Text("• ACTIVE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.weight)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DS.Palette.weight.opacity(0.12), in: Capsule())
                    }
                }
                Text(profile.subtitle)
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                if let latest = profile.latestWeighIn {
                    let wStr = weightUnitRaw == "lb"
                        ? String(format: "%.1f lb", latest.weightKg * 2.20462)
                        : latest.weightString
                    Text("Last weigh-in: \(wStr) · \(latestDateLabel(latest.date))")
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.tertiaryLabel)
        }
        .padding(.horizontal, DS.Space.l)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = profile }
    }

    private func latestDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today, \(date.formatted(.dateTime.hour().minute()))" }
        if cal.isDateInYesterday(date) { return "Yesterday, \(date.formatted(.dateTime.hour().minute()))" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Tap a profile to edit. The starred profile is your primary user — only their readings sync to Apple Health.")
            .font(DS.Typeface.subheadline)
            .foregroundStyle(DS.Palette.secondaryLabel)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "person.2")
                .font(.system(size: 54, weight: .thin))
                .foregroundStyle(DS.Palette.secondaryLabel)
            VStack(spacing: DS.Space.s) {
                Text("No profiles yet")
                    .font(DS.Typeface.title3)
                    .foregroundStyle(DS.Palette.label)
                Text("Add yourself first, then other family members.\nThe first profile becomes the primary user.")
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            Button("Add Profile") { showingAdd = true }
                .font(DS.Typeface.bodyMedium)
                .foregroundStyle(DS.Palette.weight)
                .padding(.horizontal, DS.Space.xl)
                .frame(height: 48)
                .background(DS.Palette.weight.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.xxl)
    }

    // MARK: - SwiftData writes

    func commitSave(data: ProfileFormData, updating existing: UserProfile?) {
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
}

// MARK: - ProfileEditView
// Pure UI: collects values, fires onSave closure. No SwiftData dependency.

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("heightUnit") private var heightUnitRaw: String = HeightUnit.cm.rawValue
    @Query(sort: \UserProfile.createdAt) private var allProfiles: [UserProfile]

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
    // Only lock for the very first profile — it must be primary and can't be changed.
    // All other profiles (including the current primary) can freely toggle.
    private var primaryLocked: Bool { isFirstProfile }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // The profile that currently holds primary (excluding the one being edited).
    private var otherPrimary: UserProfile? {
        allProfiles.first { $0.isPrimary && $0.id != existingProfile?.id }
    }

    private var primaryFooterNote: String {
        if primaryLocked {
            return "The first profile is always primary — only their readings sync to Apple Health."
        }
        if isPrimary {
            if let other = otherPrimary {
                return "Saving will move Apple Health sync from \(other.name) to this profile."
            }
            return "This profile's readings will sync to Apple Health."
        }
        if let other = otherPrimary {
            return "\(other.name)'s readings sync to Apple Health. Toggle on to move sync to this profile."
        }
        return "Only the primary user's readings are written to Apple Health. Others are stored locally."
    }

    private var dobRange: ClosedRange<Date> {
        let cal   = Calendar.current
        let old   = cal.date(byAdding: .year, value: -120, to: .now)!
        let young = cal.date(byAdding: .year, value:   -5, to: .now)!
        return old...young
    }

    private var heightDisplayString: String {
        if heightUnit == .cm { return "\(Int(heightCm)) cm" }
        let totalIn = Int(round(heightCm / 2.54))
        return "\(totalIn / 12) ft \(totalIn % 12) in"
    }

    private var heightConversionHint: String {
        if heightUnit == .cm {
            let totalIn = Int(round(heightCm / 2.54))
            return "\(totalIn / 12) ft \(totalIn % 12) in"
        }
        return "\(Int(heightCm)) cm"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    avatarSection
                    detailsSection
                    heightSection
                    primarySection
                }
                .padding(.horizontal, DS.Space.screenGutter)
                .padding(.vertical, DS.Space.l)
                .padding(.bottom, 40)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .navigationTitle(existingProfile == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Palette.weight)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? DS.Palette.weight : DS.Palette.tertiaryLabel)
                        .disabled(!canSave)
                }
            }
            .onAppear { if isFirstProfile { isPrimary = true } }
        }
    }

    // MARK: - Avatar section

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("AVATAR")
            VStack(spacing: DS.Space.m) {
                // Large selected display
                Text(avatar)
                    .font(.system(size: 48))
                    .frame(width: 84, height: 84)
                    .background(DS.Palette.ground, in: Circle())
                    .overlay(Circle().stroke(DS.Palette.weight, lineWidth: 2.5))
                    .frame(maxWidth: .infinity)

                // Emoji grid
                let cols = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: 6)
                LazyVGrid(columns: cols, spacing: DS.Space.s) {
                    ForEach(UserProfile.avatarOptions, id: \.self) { emoji in
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) { avatar = emoji }
                        } label: {
                            Text(emoji)
                                .font(.system(size: 26))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    avatar == emoji
                                        ? DS.Palette.weight.opacity(0.12)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(DS.Space.cardPaddingHero)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Details section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("DETAILS")
            VStack(spacing: 0) {
                // Name
                HStack {
                    Text("Name")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    TextField("Required", text: $name)
                        .multilineTextAlignment(.trailing)
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 52)

                Divider().padding(.leading, DS.Space.l)

                // Sex
                HStack {
                    Text("Sex")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Picker("", selection: $isMale) {
                        Text("Male").tag(true)
                        Text("Female").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 52)

                Divider().padding(.leading, DS.Space.l)

                // Date of birth
                HStack {
                    Text("Date of birth")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    DatePicker("", selection: $dateOfBirth, in: dobRange, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 52)
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Height section

    private var heightSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("HEIGHT")
            VStack(spacing: 0) {
                // Unit picker
                HStack {
                    Text("Unit")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Picker("", selection: $heightUnitRaw) {
                        Text("cm").tag(HeightUnit.cm.rawValue)
                        Text("ft · in").tag(HeightUnit.ftIn.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 52)

                Divider().padding(.leading, DS.Space.l)

                // Value + stepper
                HStack {
                    Text("Value")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Text(heightDisplayString)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(DS.Palette.label)
                        .padding(.trailing, DS.Space.s)

                    // − + buttons
                    HStack(spacing: 1) {
                        Button {
                            let step = heightUnit == .cm ? 1.0 : 2.54
                            heightCm = max(100, heightCm - step)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Palette.label)
                                .frame(width: 34, height: 34)
                                .background(DS.Palette.ground,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            let step = heightUnit == .cm ? 1.0 : 2.54
                            heightCm = min(220, heightCm + step)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Palette.label)
                                .frame(width: 34, height: 34)
                                .background(DS.Palette.ground,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(DS.Palette.hairline, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 52)
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("≈ \(heightConversionHint)")
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.tertiaryLabel)
                .padding(.leading, DS.Space.xs)
        }
    }

    // MARK: - Primary section

    private var primarySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Primary user")
                    .font(DS.Typeface.bodyMedium)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Toggle("", isOn: primaryLocked ? .constant(true) : $isPrimary)
                    .labelsHidden()
                    .disabled(primaryLocked)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 52)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(primaryFooterNote)
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .padding(.leading, DS.Space.xs)
                .animation(.easeInOut(duration: 0.2), value: isPrimary)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(DS.Typeface.dateCaps)
            .tracking(0.04 * 13)
            .foregroundStyle(DS.Palette.secondaryLabel)
    }

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

// MARK: - UserSwitcherSheet
// Presented from the Home avatar button. Lets the active user switch and
// provides a shortcut to add a new family member.

struct UserSwitcherSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @AppStorage("activeUserID") private var activeUserIDString: String = ""

    @State private var showingAdd = false

    // MARK: Derived

    private var activeProfile: UserProfile? {
        if let uuid = UUID(uuidString: activeUserIDString),
           let match = profiles.first(where: { $0.id == uuid }) { return match }
        return profiles.first(where: { $0.isPrimary }) ?? profiles.first
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    profileListCard
                    addFamilyCard
                }
                .padding(DS.Space.screenGutter)
                .padding(.bottom, 40)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .navigationTitle("Switch Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Palette.weight)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            ProfileEditView(existingProfile: nil, isFirstProfile: profiles.isEmpty) { data in
                commitAdd(data: data)
            }
        }
    }

    // MARK: - Profile list card

    private var profileListCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { idx, profile in
                switcherRow(profile)
                if idx < profiles.count - 1 {
                    Divider().padding(.leading, 72)
                }
            }
        }
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func switcherRow(_ profile: UserProfile) -> some View {
        let isActive = profile.id == activeProfile?.id
        return Button {
            activeUserIDString = profile.id.uuidString
            dismiss()
        } label: {
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
                    Text(profile.subtitle + (profile.isPrimary ? " · Primary" : ""))
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.weight)
                }
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add family member card

    private var addFamilyCard: some View {
        Button { showingAdd = true } label: {
            HStack(spacing: DS.Space.m) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.weight)
                    .frame(width: 44, height: 44)
                    .background(DS.Palette.weight.opacity(0.12), in: Circle())

                Text("Add family member")
                    .font(DS.Typeface.bodyMedium)
                    .foregroundStyle(DS.Palette.weight)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 64)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - SwiftData write

    private func commitAdd(data: ProfileFormData) {
        if data.isPrimary {
            profiles.forEach { $0.isPrimary = false }
        }
        context.insert(UserProfile(
            name:        data.name,
            isMale:      data.isMale,
            dateOfBirth: data.dateOfBirth,
            heightCm:    data.heightCm,
            isPrimary:   data.isPrimary,
            avatar:      data.avatar
        ))
        try? context.save()
    }
}

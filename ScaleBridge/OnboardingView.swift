import SwiftUI
import SwiftData

struct OnboardingView: View {

    @Environment(\.modelContext) private var context
    @Environment(CloudBackupManager.self) private var backup
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showProfileSheet = false
    @State private var isRestoring = false
    @State private var restoreError: String? = nil
    private let healthKit = HealthKitWriter()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                appIcon
                titleBlock
                featureList
            }
            .padding(.top, 60)
            .padding(.horizontal, DS.Space.screenGutter)
            .padding(.bottom, DS.Space.xl)
        }
        .background(DS.Palette.ground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert("Restore Failed", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK") { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileEditView(existingProfile: nil, isFirstProfile: true) { data in
                commitProfile(data)
            }
        }
    }

    // MARK: - App icon

    private var appIcon: some View {
        Image("AppIconImage")
            .resizable()
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.indigo.opacity(0.3), radius: 24, x: 0, y: 12)
            .padding(.bottom, 36)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(spacing: 12) {
            Text("Welcome to\nScaleBridge.")
                .font(.system(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Palette.label)
            Text("A bridge between your body-composition scale and the rest of your health data.")
                .font(DS.Typeface.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.bottom, 48)
    }

    // MARK: - Feature list

    private var featureList: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            featureRow(
                icon: "antenna.radiowaves.left.and.right",
                color: .indigo,
                title: "Pair once, forget about it",
                body: "Step on your QN/Yolanda scale and ScaleBridge captures weight, fat, muscle, water, BMI, and bone — all in one shot."
            )
            featureRow(
                icon: "person.2.fill",
                color: .orange,
                title: "Everyone in the family",
                body: "Add a profile for each person — kids, partners, parents. The app picks who to log based on weight."
            )
            featureRow(
                icon: "heart.fill",
                color: .red,
                title: "Synced to Apple Health",
                body: "Your primary profile's readings flow into Apple Health automatically. Other family members stay local."
            )
        }
    }

    private func featureRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.Typeface.bodyMedium)
                    .foregroundStyle(DS.Palette.label)
                Text(body)
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: DS.Space.s) {
            if isRestoring {
                restoringState
            } else {
                Button {
                    showProfileSheet = true
                } label: {
                    Text("Create your profile")
                        .font(DS.Typeface.bodyMedium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DS.Palette.weight)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    startRestore()
                } label: {
                    HStack(spacing: 12) {
                        GoogleGLogo(size: 22)
                        Text("Restore from backup")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(red: 0.235, green: 0.255, blue: 0.263))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                }
                .buttonStyle(.plain)

                Text("Sign in with your Google account to restore all your profiles and readings from a previous device.")
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, DS.Space.screenGutter)
        .padding(.top, DS.Space.m)
        .padding(.bottom, DS.Space.l)
        .background(DS.Palette.ground.ignoresSafeArea(edges: .bottom))
    }

    private var restoringState: some View {
        VStack(spacing: DS.Space.m) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Restoring your data…")
                .font(DS.Typeface.bodyMedium)
                .foregroundStyle(DS.Palette.label)
            Text("This may take a moment.")
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.l)
    }

    // MARK: - Restore

    private func startRestore() {
        Task {
            isRestoring = true
            defer { isRestoring = false }
            do {
                if !backup.isSignedIn {
                    await backup.signIn()
                }
                guard backup.isSignedIn else { return }
                try await backup.restore(into: context)
                hasCompletedOnboarding = true
            } catch {
                restoreError = error.localizedDescription
            }
        }
    }

    // MARK: - Save

    private func commitProfile(_ data: ProfileFormData) {
        context.insert(UserProfile(
            name:        data.name,
            isMale:      data.isMale,
            dateOfBirth: data.dateOfBirth,
            heightCm:    data.heightCm,
            isPrimary:   true,
            avatar:      data.avatar
        ))
        try? context.save()
        Task {
            try? await healthKit.requestAuthorization()
            hasCompletedOnboarding = true
        }
    }
}

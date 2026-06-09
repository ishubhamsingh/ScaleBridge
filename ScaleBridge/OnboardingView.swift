import SwiftUI
import SwiftData

struct OnboardingView: View {

    @Environment(\.modelContext) private var context
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showProfileSheet = false
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
        .sheet(isPresented: $showProfileSheet) {
            ProfileEditView(existingProfile: nil, isFirstProfile: true) { data in
                commitProfile(data)
            }
        }
    }

    // MARK: - App icon

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.42, green: 0.25, blue: 0.82), Color.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .shadow(color: Color.indigo.opacity(0.3), radius: 24, x: 0, y: 12)
            Image(systemName: "scalemass")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(.white)
        }
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

            Text("Step 1 of 2 · We'll request Apple Health access next.")
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, DS.Space.screenGutter)
        .padding(.top, DS.Space.m)
        .padding(.bottom, DS.Space.l)
        .background(DS.Palette.ground.ignoresSafeArea(edges: .bottom))
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

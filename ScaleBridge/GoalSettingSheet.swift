import SwiftUI

// MARK: - GoalSettingSheet
//
// Unified goal editor for weight and body fat %. Both goals live here so the
// user has one place to manage targets. Opened from MetricDetailView (weight
// or body fat). Toggle each goal on/off; values snap to nearest 0.5 so steps
// always land on round numbers.

struct GoalSettingSheet: View {

    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("weightUnit") private var weightUnitRaw: String = "kg"

    @State private var weightEnabled: Bool
    @State private var fatEnabled: Bool
    @State private var draftWeight: Float   // display unit (kg or lb)
    @State private var draftFat: Float      // always %

    init(profile: UserProfile) {
        self.profile = profile
        let storedUnit = UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"

        let wKg = profile.goalWeightKg ?? profile.latestWeighIn?.weightKg ?? 70
        let wDisplay = storedUnit == "lb" ? wKg * 2.20462 : wKg
        _draftWeight    = State(initialValue: Self.snap(wDisplay))
        _weightEnabled  = State(initialValue: profile.goalWeightKg != nil)

        let f = profile.goalBodyFatPercent ?? profile.latestWeighIn?.fatPercent ?? 20
        _draftFat   = State(initialValue: Self.snap(f))
        _fatEnabled = State(initialValue: profile.goalBodyFatPercent != nil)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    goalCard(
                        title: "WEIGHT GOAL",
                        color: DS.Palette.weight,
                        enabled: $weightEnabled,
                        value: $draftWeight,
                        unit: weightUnitRaw == "lb" ? "lb" : "kg",
                        minVal: weightUnitRaw == "lb" ? 66 : 30,
                        maxVal: weightUnitRaw == "lb" ? 440 : 200
                    )
                    goalCard(
                        title: "BODY FAT GOAL",
                        color: DS.Palette.bodyFat,
                        enabled: $fatEnabled,
                        value: $draftFat,
                        unit: "%",
                        minVal: 3,
                        maxVal: 60
                    )
                }
                .padding(.horizontal, DS.Space.screenGutter)
                .padding(.vertical, DS.Space.l)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveGoals(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Goal card

    private func goalCard(
        title: String,
        color: Color,
        enabled: Binding<Bool>,
        value: Binding<Float>,
        unit: String,
        minVal: Float,
        maxVal: Float
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            // Header row: title + toggle
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Spacer()
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .tint(color)
            }

            // Stepper row — only shown when enabled
            if enabled.wrappedValue {
                HStack {
                    Button {
                        let next = value.wrappedValue - 0.5
                        value.wrappedValue = Swift.max(minVal, Self.snap(next))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", value.wrappedValue))
                            .font(.system(size: 48, weight: .bold).monospacedDigit())
                            .foregroundStyle(DS.Palette.label)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: value.wrappedValue)
                        Text(unit)
                            .font(DS.Typeface.title2)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }

                    Spacer()

                    Button {
                        let next = value.wrappedValue + 0.5
                        value.wrappedValue = Swift.min(maxVal, Self.snap(next))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, DS.Space.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DS.Space.m)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: enabled.wrappedValue)
    }

    // MARK: - Save

    private func saveGoals() {
        let lb = weightUnitRaw == "lb"
        profile.goalWeightKg       = weightEnabled ? (lb ? draftWeight / 2.20462 : draftWeight) : nil
        profile.goalBodyFatPercent = fatEnabled    ? draftFat : nil
        try? context.save()
    }

    // Rounds to nearest 0.5 so stepping always lands on round values.
    private static func snap(_ v: Float) -> Float {
        (v * 2).rounded() / 2
    }
}

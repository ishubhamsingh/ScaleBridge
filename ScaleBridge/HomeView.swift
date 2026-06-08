import SwiftUI
import SwiftData
import Charts

// MARK: - HomeView
//
// Home — Today: hero weight card, 2×2 body-comp grid, mini sparklines.
// The "Weigh in" glass pill drives BLE scanning directly for now;
// Phase 4 will replace this with the three-screen modal sequence.

struct HomeView: View {

    // MARK: State

    @StateObject private var ble = ScaleBLEManager(
        parser: QNScaleParser(),
        user: ScaleUser(isMale: true, age: 30, heightCm: 175, usePounds: false)
    )
    private let healthKit = HealthKitWriter()

    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @AppStorage("activeUserID")    private var activeUserIDString: String = ""
    @AppStorage("syncToHealthKit") private var syncToHealthKit: Bool = true
    @AppStorage("weightUnit")      private var weightUnitRaw: String = "kg"

    @State private var showingWeighIn      = false
    @State private var selectedMetric: BodyMetric? = nil
    @State private var showingUserSwitcher = false

    // MARK: Derived

    private var activeProfile: UserProfile? {
        if let uuid = UUID(uuidString: activeUserIDString),
           let match = profiles.first(where: { $0.id == uuid }) { return match }
        return profiles.first(where: { $0.isPrimary }) ?? profiles.first
    }

    private var sortedWeighIns: [WeighIn] { activeProfile?.sortedWeighIns ?? [] }
    private var latestWeighIn: WeighIn?   { sortedWeighIns.first }
    private var previousWeighIn: WeighIn? { sortedWeighIns.dropFirst().first }
    // Oldest → newest for chart x-axis
    private var chartReadings: [WeighIn]  { Array(sortedWeighIns.prefix(14).reversed()) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    navHeader
                        .padding(.horizontal, DS.Space.screenGutter)
                        .padding(.top, DS.Space.xs)

                    weightCard
                        .padding(.horizontal, DS.Space.screenGutter)

                    if latestWeighIn != nil {
                        compGrid
                            .padding(.horizontal, DS.Space.screenGutter)

                        Button("Show All Health Data") { /* Phase 10 */ }
                            .font(DS.Typeface.bodyMedium)
                            .foregroundStyle(BodyMetric.weight.color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.s)
                    }
                }
                .padding(.bottom, 100)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedMetric) { metric in
                if let profile = activeProfile {
                    MetricDetailView(metric: metric, profile: profile)
                }
            }
        }
        .sheet(isPresented: $showingUserSwitcher) {
            UserSwitcherSheet()
                .presentationDetents([.medium, .large])
        }
        .task { try? await healthKit.requestAuthorization() }
        .onChange(of: ble.status) { _, newStatus in
            if case .done = newStatus, let m = ble.lastMeasurement {
                persistMeasurement(m)
            }
        }
        .fullScreenCover(isPresented: $showingWeighIn) {
            WeighInFlowView(
                profile: activeProfile,
                previousWeighIn: previousWeighIn,
                onDone: {
                    showingWeighIn = false
                    ble.stop()
                },
                onWeighAgain: {
                    ble.stop()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard let profile = activeProfile else { return }
                        ble.user = profile.scaleUser
                        ble.start()
                    }
                }
            )
            .environmentObject(ble)
        }
    }

    // MARK: - Nav Header

    private var navHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .textCase(.uppercase)
                    .font(DS.Typeface.dateCaps)
                    .tracking(0.04 * 13)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Spacer()
                GlassCircleButton(size: 34, action: { showingUserSwitcher = true }) {
                    Text(activeProfile?.avatar ?? "👤")
                        .font(.system(size: 18))
                }
            }

            HStack(alignment: .center) {
                Text("Today")
                    .font(DS.Typeface.largeTitle)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                GlassPillButton(
                    title: bleLabel,
                    systemImage: bleIcon,
                    tint: bleIsActive ? DS.Palette.muscle : DS.Palette.label,
                    action: weighInTapped
                )
                .disabled(profiles.isEmpty)
            }
        }
    }

    private var bleIsActive: Bool {
        switch ble.status {
        case .scanning, .connecting, .connected, .reading: return true
        default: return false
        }
    }
    private var bleLabel: String { "Weigh in" }
    private var bleIcon: String  { "scalemass" }

    private func weighInTapped() {
        guard let profile = activeProfile else { return }
        ble.user = profile.scaleUser
        ble.start()
        showingWeighIn = true
    }

    // MARK: - Weight Card

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            // Title row
            HStack {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: BodyMetric.weight.symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(BodyMetric.weight.label)
                        .font(DS.Typeface.cardTitle)
                }
                .foregroundStyle(BodyMetric.weight.color)

                Spacer()

                if let w = latestWeighIn {
                    Button { selectedMetric = .weight } label: {
                        HStack(spacing: DS.Space.xs) {
                            Text(w.date, format: .dateTime.hour().minute())
                                .font(DS.Typeface.footnote)
                                .foregroundStyle(DS.Palette.secondaryLabel)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Palette.secondaryLabel)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let w = latestWeighIn {
                weightHeroRow(w)
                weightDeltaRow(w)
                if chartReadings.count >= 2 {
                    sparkline(data: chartReadings.map { Double($0.weightKg) },
                              color: BodyMetric.weight.color)
                        .frame(height: 36)
                        .padding(.top, DS.Space.xs)
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("No readings yet")
                        .font(DS.Typeface.bodyMedium)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    Text("Step on the scale to begin.")
                        .font(DS.Typeface.subheadline)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
                .frame(height: 72, alignment: .topLeading)
            }
        }
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func weightHeroRow(_ w: WeighIn) -> some View {
        let isLb = weightUnitRaw == "lb"
        let val: Float = isLb ? w.weightKg * 2.20462 : w.weightKg
        return HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(String(format: "%.1f", val))
                .font(.system(size: 52, weight: .bold).monospacedDigit())
                .tracking(-0.035 * 52)
                .foregroundStyle(DS.Palette.label)
            Text(isLb ? "lb" : "kg")
                .font(DS.Typeface.title3)
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
    }

    private func weightDeltaRow(_ w: WeighIn) -> some View {
        HStack(spacing: DS.Space.xs) {
            if let prev = previousWeighIn {
                let delta       = w.weightKg - prev.weightKg
                let isLb        = weightUnitRaw == "lb"
                let displayDelta: Float = isLb ? abs(delta) * 2.20462 : abs(delta)
                let unitLabel   = isLb ? "lb" : "kg"
                let accentColor = delta <= 0 ? DS.Palette.positive : DS.Palette.bodyFat
                Image(systemName: delta <= 0 ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(String(format: "%.1f \(unitLabel)", displayDelta))
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(accentColor)
                Text("from \(daysSince(prev.date))")
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            } else {
                Text("First reading")
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            Spacer()
            if w.syncedToHealthKit {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.muscle)
                Text("Synced")
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
    }

    // MARK: - Comp Grid

    private var compGrid: some View {
        let isMale = activeProfile?.isMale ?? true
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: DS.Space.m),
                      GridItem(.flexible(), spacing: DS.Space.m)],
            spacing: DS.Space.m
        ) {
            compTile(.bodyFat, isMale: isMale)
            compTile(.muscle,  isMale: isMale)
            compTile(.water,   isMale: isMale)
            compTile(.bmi,     isMale: isMale)
        }
    }

    @ViewBuilder
    private func compTile(_ metric: BodyMetric, isMale: Bool) -> some View {
        let value   = tileValue(metric, from: latestWeighIn)
        let prev    = tileValue(metric, from: previousWeighIn)
        let cl      = HomeClassify.classify(metric, value: value, isMale: isMale)
        let data    = chartReadings.compactMap { tileValue(metric, from: $0) }

        VStack(alignment: .leading, spacing: DS.Space.s) {
            // Metric title
            HStack(spacing: DS.Space.xs) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(metric.label)
                    .font(DS.Typeface.cardTitle)
            }
            .foregroundStyle(metric.color)

            // Value row — value + unit + classification inline
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                if let v = value {
                    Text(String(format: "%.\(metric.decimals)f", v))
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(DS.Palette.label)
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    if let cl {
                        Text(cl.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(cl.color)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                Spacer(minLength: 0)
            }

            // Delta row
            if let v = value, let p = prev {
                let delta       = v - p
                let accentColor = HomeClassify.isImprovement(metric, delta: delta)
                                    ? DS.Palette.positive : DS.Palette.bodyFat
                HStack(spacing: 3) {
                    Image(systemName: delta > 0 ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%.\(metric.decimals)f", abs(delta)))
                        .font(DS.Typeface.footnote)
                    Text("vs last")
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                .foregroundStyle(accentColor)
            } else {
                Text("—")
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }

            // Sparkline
            if data.count >= 2 {
                sparkline(data: data.map { Double($0) }, color: metric.color)
                    .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.Palette.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { selectedMetric = metric }
    }

    // MARK: - Sparkline

    private func sparkline(data: [Double], color: Color) -> some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                LineMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }

    // MARK: - Helpers

    private func tileValue(_ metric: BodyMetric, from w: WeighIn?) -> Float? {
        switch metric {
        case .bodyFat: return w?.fatPercent
        case .muscle:  return w?.musclePercent
        case .water:   return w?.waterPercent
        case .bmi:     return w?.bmi
        case .lean:    return w?.leanMassKg
        case .weight:  return w?.weightKg
        case .bone:    return w?.bonePercent
        }
    }

    private func daysSince(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }

    // MARK: - Measurement Persistence

    private func persistMeasurement(_ measurement: ScaleMeasurement) {
        guard let user = activeProfile else { return }
        let weighIn = WeighIn(from: measurement, user: user)
        context.insert(weighIn)
        if user.isPrimary && syncToHealthKit {
            Task {
                do {
                    try await healthKit.save(measurement)
                    weighIn.syncedToHealthKit = true
                    try? context.save()
                } catch {
                    try? context.save()
                }
            }
        } else {
            try? context.save()
        }
    }
}

// MARK: - HomeClassify
//
// Classification ranges for the Home tiles. Phase 7 will promote these to the
// full banded-range system used by Metric Detail; kept local here to avoid
// premature abstraction.

enum HomeClassify {
    static func classify(_ metric: BodyMetric, value: Float?, isMale: Bool) -> Classification? {
        guard let v = value else { return nil }
        switch metric {
        case .bmi:
            if v < 18.5 { return .low }
            if v < 25.0 { return .normal }
            if v < 30.0 { return .high }
            return .veryHigh
        case .bodyFat:
            let (lo, hi, vhi): (Float, Float, Float) = isMale ? (6, 20, 25) : (14, 28, 33)
            if v < lo  { return .low }
            if v < hi  { return .normal }
            if v < vhi { return .high }
            return .veryHigh
        case .muscle:
            let (lo, hi, vhi): (Float, Float, Float) = isMale ? (30, 44, 55) : (22, 35, 44)
            if v < lo  { return .low }
            if v < hi  { return .normal }
            if v < vhi { return .high }
            return .veryHigh
        case .water:
            if v < 45 { return .low }
            if v < 65 { return .normal }
            if v < 75 { return .high }
            return .veryHigh
        default:
            return nil
        }
    }

    /// True when the direction of `delta` is a health improvement for this metric.
    static func isImprovement(_ metric: BodyMetric, delta: Float) -> Bool {
        switch metric {
        case .muscle, .water, .lean: return delta > 0
        default:                     return delta < 0
        }
    }
}

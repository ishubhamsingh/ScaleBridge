import SwiftUI
import SwiftData
import Charts

// MARK: - HistoryView
//
// History tab: time-range filter, metric chips, chart card with inline stats,
// month-grouped reading list. Edit mode uses multi-select + bottom batch delete.

struct HistoryView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(CloudBackupManager.self) private var backup
    private let healthKit = HealthKitWriter.shared
    @State private var selectedWeighIn: WeighIn? = nil
    @State private var isEditing = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var timeRange: HistoryTimeRange = .month
    @State private var chartMetric: HistoryMetric  = .weight
    @AppStorage("weightUnit") private var weightUnitRaw: String = "kg"

    // MARK: Derived

    private var allWeighIns: [WeighIn] { profile.sortedWeighIns }       // newest first

    private var filteredWeighIns: [WeighIn] {
        guard let cutoff = timeRange.cutoff else { return allWeighIns }
        return allWeighIns.filter { $0.date >= cutoff }
    }

    private var chartPoints: [(date: Date, value: Double)] {
        let raw = filteredWeighIns.reversed().compactMap { w in
            chartMetric.value(from: w, profile: profile).map { (date: w.date, value: Double($0)) }
        }
        guard chartMetric == .weight, weightUnitRaw == "lb" else { return raw }
        return raw.map { (date: $0.date, value: $0.value * 2.20462) }
    }

    private var chartDisplayUnit: String {
        chartMetric == .weight && weightUnitRaw == "lb" ? "lb" : chartMetric.unit
    }

    private var groupedReadings: [(month: Date, readings: [WeighIn])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filteredWeighIns) { w in
            cal.date(from: cal.dateComponents([.year, .month], from: w.date))!
        }
        return dict.sorted { $0.key > $1.key }.map { (month: $0.key, readings: $0.value) }
    }

    // MARK: Body

    var body: some View {
        Group {
            if allWeighIns.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
        .background(DS.Palette.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedWeighIn) { w in
            ReadingDetailSheet(
                weighIn: w,
                previousWeighIn: allWeighIns.first(where: { $0.date < w.date })
            )
            .presentationDetents([.large])
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing && !selectedIDs.isEmpty {
                batchDeleteBar
            }
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                navHeader

                timeRangePicker
                metricChips
                if chartPoints.count >= 1 {
                    chartCard
                }

                ForEach(groupedReadings, id: \.month) { group in
                    monthSection(month: group.month, readings: group.readings)
                }
            }
            .padding(.horizontal, DS.Space.screenGutter)
            .padding(.top, DS.Space.m)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Nav header

    private var navHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            // Row 1: subtitle + avatar
            HStack {
                Text(isEditing
                     ? "EDITING · \(selectedIDs.count) SELECTED"
                     : "\(profile.name.uppercased()) · \(allWeighIns.count) \(allWeighIns.count == 1 ? "READING" : "READINGS")")
                    .font(DS.Typeface.dateCaps)
                    .tracking(0.04 * 13)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .animation(.easeInOut(duration: 0.2), value: isEditing)
                Spacer()
                Text(profile.avatar)
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
                    .background(DS.Palette.card, in: Circle())
            }
            // Row 2: title + Edit/Done
            HStack(alignment: .center) {
                Text("History")
                    .font(DS.Typeface.largeTitle)
                    .foregroundStyle(DS.Palette.label)
                Spacer()
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing.toggle()
                        if !isEditing { selectedIDs.removeAll() }
                    }
                }
                .font(.system(size: 17, weight: isEditing ? .semibold : .regular))
                .foregroundStyle(DS.Palette.weight)
            }
        }
    }

    // MARK: - Time range picker

    private var timeRangePicker: some View {
        HStack(spacing: 4) {
            ForEach(HistoryTimeRange.allCases) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { timeRange = range }
                } label: {
                    Text(range.rawValue)
                        .font(DS.Typeface.bodyMedium)
                        .foregroundStyle(timeRange == range ? .white : DS.Palette.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            timeRange == range ? DS.Palette.weight : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Metric chips

    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                ForEach(HistoryMetric.allCases) { metric in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { chartMetric = metric }
                    } label: {
                        HStack(spacing: 6) {
                            if chartMetric != metric {
                                Circle()
                                    .fill(metric.color)
                                    .frame(width: 7, height: 7)
                            }
                            Text(metric.rawValue)
                                .font(DS.Typeface.bodyMedium)
                                .foregroundStyle(chartMetric == metric ? .white : DS.Palette.label)
                        }
                        .padding(.horizontal, DS.Space.m)
                        .frame(height: 34)
                        .background(
                            chartMetric == metric ? metric.color : DS.Palette.card,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            // Header
            HStack {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: chartMetric.symbol)
                        .font(.system(size: 13))
                    Text(chartMetric.rawValue)
                        .font(DS.Typeface.cardTitle)
                }
                .foregroundStyle(chartMetric.color)
                Spacer()
                Text(chartDateRange)
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }

            // Stats row
            HStack(spacing: 0) {
                chartStat(label: "AVERAGE", value: chartAverage, unit: chartDisplayUnit)
                Divider().frame(height: 36)
                chartStat(label: "RANGE",   value: chartRange,   unit: "")
                if let ch = chartChange {
                    Divider().frame(height: 36)
                    chartChangeStat(ch)
                }
            }

            // Chart
            TrendChart(data: chartPoints, color: chartMetric.color)
                .frame(height: 140)
        }
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chartStat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.06 * 10)
                .foregroundStyle(DS.Palette.tertiaryLabel)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(DS.Palette.label)
                if !unit.isEmpty {
                    Text(unit)
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s)
    }

    private func chartChangeStat(_ change: (delta: Double, good: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CHANGE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.06 * 10)
                .foregroundStyle(DS.Palette.tertiaryLabel)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Image(systemName: change.delta < 0 ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                Text(String(format: "%.1f", abs(change.delta)) + (chartDisplayUnit.isEmpty ? "" : " \(chartDisplayUnit)"))
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(change.good ? DS.Palette.positive : DS.Palette.bodyFat)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s)
    }

    // chart stat helpers
    private var chartAverage: String {
        guard !chartPoints.isEmpty else { return "—" }
        let avg = chartPoints.map(\.value).reduce(0, +) / Double(chartPoints.count)
        return String(format: "%.1f", avg)
    }
    private var chartRange: String {
        guard let lo = chartPoints.map(\.value).min(),
              let hi = chartPoints.map(\.value).max() else { return "—" }
        if abs(hi - lo) < 1e-6 { return String(format: "%.1f", lo) }
        return String(format: "%.1f–%.1f", lo, hi)
    }
    private var chartChange: (delta: Double, good: Bool)? {
        guard let first = chartPoints.first?.value,
              let last  = chartPoints.last?.value else { return nil }
        let delta = last - first
        guard abs(delta) > 1e-6 else { return nil }
        let good  = chartMetric.lowerIsBetter ? delta < 0 : delta > 0
        return (delta, good)
    }
    private var chartDateRange: String {
        guard let first = chartPoints.first?.date,
              let last  = chartPoints.last?.date  else { return "" }
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        return "\(first.formatted(fmt)) — \(last.formatted(fmt))"
    }

    // MARK: - Month section

    private func monthSection(month: Date, readings: [WeighIn]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(DS.Typeface.dateCaps)
                    .tracking(0.04 * 13)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                Spacer()
                Text("\(readings.count) reading\(readings.count == 1 ? "" : "s")")
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }

            VStack(spacing: 0) {
                ForEach(Array(readings.enumerated()), id: \.element.id) { idx, w in
                    historyRow(w)
                    if idx < readings.count - 1 {
                        Divider().padding(.leading, isEditing ? 68 : DS.Space.l)
                    }
                }
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: isEditing)
        }
    }

    // MARK: - History row

    private func historyRow(_ w: WeighIn) -> some View {
        let isSelected = selectedIDs.contains(w.id)
        return HStack(spacing: DS.Space.m) {
            // Edit-mode circle
            if isEditing {
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        if isSelected { selectedIDs.remove(w.id) }
                        else          { selectedIDs.insert(w.id) }
                    }
                } label: {
                    Image(systemName: isSelected ? "minus.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? DS.Palette.muscle : DS.Palette.tertiaryLabel)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Date + time/weekday
            VStack(alignment: .leading, spacing: 3) {
                Text(dayLabel(w.date))
                    .font(DS.Typeface.bodyMedium)
                    .foregroundStyle(DS.Palette.label)
                Text(timeSublabel(w.date))
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }

            Spacer()

            // Weight + fat stacked right-aligned
            VStack(alignment: .trailing, spacing: 2) {
                let displayWeight: Float = weightUnitRaw == "lb" ? w.weightKg * 2.20462 : w.weightKg
                Text(String(format: "%.1f", displayWeight))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DS.Palette.label)
                Text(w.fatPercent.map { String(format: "%.1f%%", $0) } ?? "—")
                    .font(DS.Typeface.footnote.monospacedDigit())
                    .foregroundStyle(w.fatPercent != nil ? DS.Palette.bodyFat : DS.Palette.tertiaryLabel)
            }

            // Heart + chevron
            HStack(spacing: DS.Space.xs) {
                if profile.isPrimary && w.syncedToHealthKit {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.muscle)
                }
                if !isEditing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                }
            }
        }
        .padding(.horizontal, DS.Space.l)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                withAnimation(.spring(duration: 0.2)) {
                    if isSelected { selectedIDs.remove(w.id) }
                    else          { selectedIDs.insert(w.id) }
                }
            } else {
                selectedWeighIn = w
            }
        }
    }

    // MARK: - Batch delete bar

    private var batchDeleteBar: some View {
        HStack {
            Text("\(selectedIDs.count) reading\(selectedIDs.count == 1 ? "" : "s") selected")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Button {
                let doomed = allWeighIns.filter { selectedIDs.contains($0.id) }
                // Capture before deletion — these objects are about to leave the store.
                let ids = doomed.map(\.id)
                let healthDates = doomed.filter(\.syncedToHealthKit).map(\.date)

                withAnimation {
                    for w in doomed { context.delete(w) }
                    try? context.save()
                    selectedIDs.removeAll()
                    isEditing = false
                }

                Task {
                    for date in healthDates { await healthKit.deleteSamples(around: date) }
                    await backup.deleteWeighIns(ids: ids)
                }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                    Text("Delete")
                        .font(DS.Typeface.bodyMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.l)
                .frame(height: 38)
                .background(DS.Palette.muscle, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
        .background(.thinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "scalemass")
                .font(.system(size: 54, weight: .thin))
                .foregroundStyle(DS.Palette.secondaryLabel)
            VStack(spacing: DS.Space.s) {
                Text("No readings yet")
                    .font(DS.Typeface.title3)
                    .foregroundStyle(DS.Palette.label)
                Text("Your weigh-ins will appear here\nafter your first measurement.")
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(DS.Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.xxl)
    }

    // MARK: - Date helpers

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func timeSublabel(_ date: Date) -> String {
        let cal  = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) { return time }
        return "\(time) · \(date.formatted(.dateTime.weekday(.abbreviated)))"
    }
}

// MARK: - WeighInRow (legacy — no longer used by HistoryView directly)

struct WeighInRow: View {
    let weighIn: WeighIn
    let showHealthBadge: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(weighIn.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(DS.Typeface.footnote).foregroundStyle(DS.Palette.secondaryLabel)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", weighIn.weightKg))
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(DS.Palette.label)
                    Text("kg").font(DS.Typeface.footnote).foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            Spacer()
            if showHealthBadge && weighIn.syncedToHealthKit {
                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(DS.Palette.muscle)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - TrendChart

private struct TrendChart: View {
    let data: [(date: Date, value: Double)]
    let color: Color

    private var minY: Double { (data.map(\.value).min() ?? 0) - 1 }
    private var maxY: Double { (data.map(\.value).max() ?? 1) + 1 }

    var body: some View {
        Chart {
            if data.count == 1, let pt = data.first {
                PointMark(x: .value("Date", pt.date), y: .value("Value", pt.value))
                    .foregroundStyle(color)
                    .symbolSize(64)
            } else {
                ForEach(Array(data.enumerated()), id: \.offset) { _, pt in
                    AreaMark(
                        x: .value("Date", pt.date),
                        yStart: .value("Min",   minY),
                        yEnd:   .value("Value", pt.value)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [color.opacity(0.20), color.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(x: .value("Date", pt.date), y: .value("Value", pt.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                    PointMark(x: .value("Date", pt.date), y: .value("Value", pt.value))
                        .foregroundStyle(color)
                        .symbolSize(20)
                }
            }
        }
        .chartYScale(domain: minY...maxY)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(DS.Palette.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(DS.Palette.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(DS.Typeface.caption)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting types

enum HistoryTimeRange: String, CaseIterable, Identifiable {
    case week = "W", month = "M", sixMonths = "6M", year = "Y", all = "All"
    var id: String { rawValue }

    var cutoff: Date? {
        switch self {
        case .week:      return Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now)
        case .month:     return Calendar.current.date(byAdding: .month,      value: -1, to: .now)
        case .sixMonths: return Calendar.current.date(byAdding: .month,      value: -6, to: .now)
        case .year:      return Calendar.current.date(byAdding: .year,       value: -1, to: .now)
        case .all:       return nil
        }
    }
}

enum HistoryMetric: String, CaseIterable, Identifiable {
    case weight       = "Weight"
    case bodyFat      = "Body Fat"
    case muscle       = "Muscle"
    case water        = "Water"
    case bmi          = "BMI"
    case lean         = "Lean Mass"
    case bone         = "Bone"
    case protein      = "Protein"
    case skeletalMuscle = "Skeletal Muscle"
    case subcutaneousFat = "Subcut. Fat"
    case visceralFat  = "Visceral Fat"
    case muscleMassKg = "Muscle Mass"
    case bmr          = "BMR"
    case metabolicAge = "Metabolic Age"
    case healthScore  = "Health Score"
    case obesityDegree = "Obesity Degree"

    var id: String { rawValue }

    var bodyMetric: BodyMetric {
        switch self {
        case .weight:         return .weight
        case .bodyFat:        return .bodyFat
        case .muscle:         return .muscle
        case .water:          return .water
        case .bmi:            return .bmi
        case .lean:           return .lean
        case .bone:           return .bone
        case .protein:        return .protein
        case .skeletalMuscle: return .skeletalMuscle
        case .subcutaneousFat: return .subcutaneousFat
        case .visceralFat:    return .visceralFat
        case .muscleMassKg:   return .muscleMassKg
        case .bmr:            return .bmr
        case .metabolicAge:   return .metabolicAge
        case .healthScore:    return .healthScore
        case .obesityDegree:  return .obesityDegree
        }
    }

    var color:  Color  { bodyMetric.color }
    var symbol: String { bodyMetric.symbol }

    var unit: String {
        switch self {
        case .weight, .lean, .muscleMassKg: return "kg"
        case .bmr:          return "kcal"
        case .metabolicAge: return "yrs"
        case .bmi, .visceralFat, .healthScore, .obesityDegree: return ""
        default:            return "%"
        }
    }

    var lowerIsBetter: Bool {
        switch self {
        case .bodyFat, .weight, .subcutaneousFat, .visceralFat,
             .obesityDegree, .metabolicAge, .bmi:
            return true
        default:
            return false
        }
    }

    func value(from w: WeighIn, profile: UserProfile) -> Float? {
        let trisa = TrisaBodyComposition(
            isMale:    profile.isMale,
            ageYears:  max(profile.age, 1),
            heightCm:  profile.heightCm
        )
        switch self {
        case .weight:         return w.weightKg
        case .bodyFat:        return w.fatPercent
        case .muscle:         return w.musclePercent
        case .water:          return w.waterPercent
        case .bmi:            return w.bmi
        case .lean:           return w.leanMassKg
        case .bone:           return w.bonePercent
        case .protein:        return w.proteinPercent
        case .skeletalMuscle: return w.skeletalMusclePercent
        case .subcutaneousFat: return w.subcutaneousFatPercent
        case .muscleMassKg:   return w.muscleMassKg
        case .visceralFat:
            guard let fat = w.fatPercent, let bmi = w.bmi else { return nil }
            return profile.isMale ? fat * bmi / 82 : fat * bmi / 96
        case .bmr:
            guard let fat = w.fatPercent else { return nil }
            return trisa.bmr(w.weightKg, fat)
        case .metabolicAge:
            guard let fat = w.fatPercent else { return nil }
            return trisa.metabolicAge(w.weightKg, fat)
        case .healthScore:
            guard let fat = w.fatPercent else { return nil }
            return trisa.healthScore(w.weightKg, fat)
        case .obesityDegree:
            guard let fat = w.fatPercent else { return nil }
            return trisa.obesityDegree(fat)
        }
    }
}

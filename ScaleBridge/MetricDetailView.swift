import SwiftUI
import SwiftData
import Charts

// MARK: - MetricDetailView
//
// One template, six metrics. Pushed from HomeView (weight card chevron / comp tiles).
// Accent color, icon, unit, value format, and educational copy all derive from
// the injected BodyMetric; the layout never changes.

struct MetricDetailView: View {
    let metric: BodyMetric
    let profile: UserProfile

    @State private var timeRange: MetricTimeRange = .month
    @State private var selectedWeighIn: WeighIn? = nil
    @AppStorage("weightUnit") private var weightUnitRaw: String = "kg"

    // MARK: Derived

    private var allWeighIns: [WeighIn] { profile.sortedWeighIns }

    private var filteredWeighIns: [WeighIn] {
        guard let cutoff = timeRange.cutoff else { return allWeighIns }
        return allWeighIns.filter { $0.date >= cutoff }
    }

    private var chartPoints: [(date: Date, value: Double)] {
        filteredWeighIns.reversed().compactMap { w in
            value(from: w).map { (date: w.date, value: Double($0)) }
        }
    }

    private func value(from w: WeighIn) -> Float? {
        let lb = weightUnitRaw == "lb"
        switch metric {
        case .weight:  return lb ? w.weightKg * 2.20462 : w.weightKg
        case .bodyFat: return w.fatPercent
        case .muscle:  return w.musclePercent
        case .water:   return w.waterPercent
        case .bmi:     return w.bmi
        case .lean:    return w.leanMassKg.map { lb ? $0 * 2.20462 : $0 }
        case .bone:    return w.bonePercent
        }
    }

    private var displayUnit: String {
        switch metric {
        case .weight, .lean: return weightUnitRaw == "lb" ? "lb" : "kg"
        default: return metric.unit
        }
    }

    private var latestValue:   Float? { allWeighIns.first.flatMap    { value(from: $0) } }
    private var previousValue: Float? { allWeighIns.dropFirst().first.flatMap { value(from: $0) } }

    private var avgValue: Double? {
        guard !chartPoints.isEmpty else { return nil }
        return chartPoints.map(\.value).reduce(0, +) / Double(chartPoints.count)
    }
    private var minPoint: (value: Double, date: Date)? {
        chartPoints.min(by: { $0.value < $1.value }).map { ($0.value, $0.date) }
    }
    private var maxPoint: (value: Double, date: Date)? {
        chartPoints.max(by: { $0.value < $1.value }).map { ($0.value, $0.date) }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                heroSection
                timeRangePicker
                if chartPoints.count >= 1 {
                    chartCard
                    statsGrid
                }
                aboutCard
                recentReadingsSection
            }
            .padding(.horizontal, DS.Space.screenGutter)
            .padding(.vertical, DS.Space.l)
            .padding(.bottom, 100)
        }
        .background(DS.Palette.ground.ignoresSafeArea())
        .navigationTitle(metric.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $selectedWeighIn) { w in
            ReadingDetailSheet(
                weighIn: w,
                previousWeighIn: allWeighIns.first(where: { $0.date < w.date })
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            // Icon + name
            HStack(spacing: DS.Space.s) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(metric.color)
                Text(metric.label)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(metric.color)
            }

            // Hero value
            if let v = latestValue {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.\(metric.decimals)f", v))
                        .font(.system(size: 64, weight: .bold).monospacedDigit())
                        .tracking(-0.035 * 64)
                        .foregroundStyle(DS.Palette.label)
                    if !displayUnit.isEmpty {
                        Text(displayUnit)
                            .font(DS.Typeface.title2)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }

            // Delta + last reading time
            if let v = latestValue, let prev = previousValue,
               let prevEntry = allWeighIns.dropFirst().first,
               let latestEntry = allWeighIns.first {
                let delta    = Double(v) - Double(prev)
                let good     = metric.lowerIsBetter ? delta <= 0 : delta >= 0
                let accent   = good ? DS.Palette.positive : DS.Palette.bodyFat

                HStack(spacing: 4) {
                    Image(systemName: delta <= 0 ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                    Text(String(format: "%.\(metric.decimals)f \(displayUnit)", abs(delta)))
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(accent)
                    Text("from \(daysSince(prevEntry.date)) · Last reading \(latestEntry.date.formatted(.dateTime.hour().minute()))")
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
        }
    }

    // MARK: - Time range picker

    private var timeRangePicker: some View {
        HStack(spacing: 4) {
            ForEach(MetricTimeRange.allCases) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { timeRange = range }
                } label: {
                    Text(range.rawValue)
                        .font(DS.Typeface.bodyMedium)
                        .foregroundStyle(timeRange == range ? DS.Palette.label : DS.Palette.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            timeRange == range ? DS.Palette.card : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Chart card

    private var chartCard: some View {
        let avg  = avgValue ?? 0
        let minV = minPoint?.value ?? 0
        let maxV = maxPoint?.value ?? 0

        return VStack(alignment: .leading, spacing: DS.Space.m) {
            // Header: AVERAGE label + date range
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVERAGE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.06 * 10)
                        .foregroundStyle(DS.Palette.tertiaryLabel)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(String(format: "%.\(metric.decimals)f", avg))
                            .font(.system(size: 28, weight: .bold).monospacedDigit())
                            .foregroundStyle(DS.Palette.label)
                        if !displayUnit.isEmpty {
                            Text(displayUnit)
                                .font(DS.Typeface.subheadline)
                                .foregroundStyle(DS.Palette.secondaryLabel)
                        }
                    }
                }
                Spacer()
                Text(chartDateRange)
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }

            // Chart with reference lines
            MetricChart(
                data: chartPoints,
                color: metric.color,
                avg: avg, minV: minV, maxV: maxV
            )
            .frame(height: 180)
        }
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chartDateRange: String {
        guard let first = chartPoints.first?.date,
              let last  = chartPoints.last?.date else { return "" }
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        return "\(first.formatted(fmt)) — \(last.formatted(fmt))"
    }

    // MARK: - Stats grid (2×2)

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: DS.Space.m),
                      GridItem(.flexible(), spacing: DS.Space.m)],
            spacing: DS.Space.m
        ) {
            if let mn = minPoint { statsCard(label: "MIN",  value: mn.value, sub: relDate(mn.date)) }
            if let mx = maxPoint { statsCard(label: "MAX",  value: mx.value, sub: relDate(mx.date)) }
            changeCard
            readingsCard
        }
    }

    private func statsCard(label: String, value: Double, sub: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            statLabel(label)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(String(format: "%.\(metric.decimals)f", value))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(DS.Palette.label)
                if !displayUnit.isEmpty {
                    Text(displayUnit)
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            Text(sub)
                .font(DS.Typeface.footnote)
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var changeCard: some View {
        let delta = (chartPoints.last?.value ?? 0) - (chartPoints.first?.value ?? 0)
        let good  = abs(delta) < 1e-6 ? true : (metric.lowerIsBetter ? delta <= 0 : delta >= 0)
        let color = good ? DS.Palette.positive : DS.Palette.bodyFat
        let sub   = chartPoints.first.map { "vs \(relDate($0.date))" } ?? ""

        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            statLabel("CHANGE")
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Image(systemName: delta <= 0 ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text(String(format: "%.\(metric.decimals)f", abs(delta)))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                if !displayUnit.isEmpty {
                    Text(displayUnit)
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            Text(sub)
                .font(DS.Typeface.footnote)
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var readingsCard: some View {
        let count = filteredWeighIns.count
        let freqStr: String = {
            guard count >= 2,
                  let first = chartPoints.first?.date,
                  let last  = chartPoints.last?.date else { return "" }
            let days = max(Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0, 1)
            let freq = Double(days) / Double(count)
            return String(format: "~ every %.1f day\(freq == 1.0 ? "" : "s")", freq)
        }()

        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            statLabel("READINGS")
            Text("\(count)")
                .font(.system(size: 24, weight: .bold).monospacedDigit())
                .foregroundStyle(DS.Palette.label)
            if !freqStr.isEmpty {
                Text(freqStr)
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.06 * 10)
            .foregroundStyle(DS.Palette.tertiaryLabel)
    }

    // MARK: - About card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("ABOUT \(metric.label.uppercased())")
                .font(DS.Typeface.dateCaps)
                .tracking(0.04 * 13)
                .foregroundStyle(DS.Palette.secondaryLabel)

            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(metric.aboutCopy)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                    .fixedSize(horizontal: false, vertical: true)

                if profile.isPrimary, let note = metric.healthKitNote {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Palette.muscle)
                        Text(note)
                            .font(DS.Typeface.subheadline)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !profile.isPrimary {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Palette.secondaryLabel)
                        Text("This profile's readings are stored in ScaleBridge only.")
                            .font(DS.Typeface.subheadline)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(DS.Space.cardPaddingHero)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Recent readings

    private var recentReadingsSection: some View {
        let recent = Array(allWeighIns.prefix(5))
        guard !recent.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("RECENT READINGS")
                        .font(DS.Typeface.dateCaps)
                        .tracking(0.04 * 13)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                    Spacer()
                    Button("Open History") { /* Phase 8: switch to History tab */ }
                        .font(DS.Typeface.subheadline)
                        .foregroundStyle(DS.Palette.weight)
                }

                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, w in
                        recentRow(w)
                        if idx < recent.count - 1 {
                            Divider().padding(.leading, DS.Space.l)
                        }
                    }
                }
                .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        )
    }

    private func recentRow(_ w: WeighIn) -> some View {
        let val = value(from: w)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(dayLabel(w.date))
                    .font(DS.Typeface.bodyMedium)
                    .foregroundStyle(DS.Palette.label)
                Text(w.date.formatted(.dateTime.hour().minute()))
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(val.map { String(format: "%.\(metric.decimals)f", $0) } ?? "—")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DS.Palette.label)
                if val != nil && !displayUnit.isEmpty {
                    Text(displayUnit)
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            HStack(spacing: DS.Space.xs) {
                if profile.isPrimary && w.syncedToHealthKit {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.muscle)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.tertiaryLabel)
            }
        }
        .padding(.horizontal, DS.Space.l)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture { selectedWeighIn = w }
    }

    // MARK: - Helpers

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func relDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func daysSince(_ date: Date) -> String {
        let d = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if d == 0 { return "today" }
        if d == 1 { return "yesterday" }
        return "\(d) days ago"
    }
}

// MARK: - MetricChart

private struct MetricChart: View {
    let data: [(date: Date, value: Double)]
    let color: Color
    let avg: Double
    let minV: Double
    let maxV: Double

    private var yPad: Double {
        let range = maxV - minV
        guard range > 1e-6 else { return max(abs(minV) * 0.05, 0.5) }
        return range * 0.15
    }
    private var yMin: Double { minV - yPad }
    private var yMax: Double { maxV + yPad }

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
                        yStart: .value("Min",   yMin),
                        yEnd:   .value("Value", pt.value)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [color.opacity(0.20), color.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(x: .value("Date", pt.date), y: .value("Value", pt.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }

                // Average dashed rule — only meaningful with multiple points
                RuleMark(y: .value("Avg", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(color.opacity(0.45))
            }
        }
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(DS.Palette.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(DS.Typeface.caption)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
        .chartYAxis {
            AxisMarks(values: [minV, avg, maxV]) { value in
                AxisGridLine().foregroundStyle(DS.Palette.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.1f", v))
                            .font(DS.Typeface.caption)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                }
            }
        }
    }
}

// MARK: - MetricTimeRange

enum MetricTimeRange: String, CaseIterable, Identifiable {
    case day = "D", week = "W", month = "M", sixMonths = "6M", year = "Y"
    var id: String { rawValue }

    var cutoff: Date? {
        switch self {
        case .day:       return Calendar.current.startOfDay(for: .now)
        case .week:      return Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now)
        case .month:     return Calendar.current.date(byAdding: .month,      value: -1, to: .now)
        case .sixMonths: return Calendar.current.date(byAdding: .month,      value: -6, to: .now)
        case .year:      return Calendar.current.date(byAdding: .year,       value: -1, to: .now)
        }
    }
}

// MARK: - BodyMetric content extensions

private extension BodyMetric {
    var aboutCopy: String {
        switch self {
        case .weight:
            return "Weight reflects total body mass. Daily fluctuations of 1–2 kg are normal — caused by hydration, meals, and time of day. Watch the 7-day trend for the truer signal."
        case .bodyFat:
            return "Body fat percentage is the proportion of fat relative to total body weight. Healthy ranges vary by age and sex. Trend direction matters more than any single reading."
        case .muscle:
            return "Skeletal muscle mass indicates the amount of muscle in your body. Building muscle supports metabolism, strength, and long-term health outcomes."
        case .water:
            return "Total body water reflects hydration status. Values fluctuate throughout the day. Consistent readings over time give the most meaningful picture."
        case .bmi:
            return "BMI (Body Mass Index) is a ratio of weight to height. It is a general screening tool, not a direct measure of body fat or health. Use it alongside other metrics."
        case .lean:
            return "Lean mass is your total weight minus body fat — it includes muscle, bone, organs, and water. A rising lean mass trend alongside stable weight signals positive body composition."
        case .bone:
            return "Bone mass reflects the mineral content of your skeleton. It is relatively stable day-to-day and changes slowly with exercise and nutrition over months."
        }
    }

    var healthKitNote: String? {
        switch self {
        case .weight:  return "Syncs to Apple Health under Weight."
        case .bodyFat: return "Syncs to Apple Health under Body Fat Percentage."
        case .lean:    return "Syncs to Apple Health under Lean Body Mass. Computed as weight × (1 − body fat %) — only available when body fat data is present."
        case .bmi:     return "Syncs to Apple Health under Body Mass Index."
        case .muscle, .water, .bone:
            return "Apple Health has no native type for this metric — it is stored in ScaleBridge only."
        }
    }
}

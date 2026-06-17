import WidgetKit
import SwiftUI
import Charts

// MARK: - Classification

private enum BodyFatClass {
    case low, normal, high, veryHigh

    var color: Color {
        switch self {
        case .low:      return .blue
        case .normal:   return .green
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }

    var label: String {
        switch self {
        case .low:      return "Low"
        case .normal:   return "Normal"
        case .high:     return "High"
        case .veryHigh: return "Very High"
        }
    }
}

private func bodyFatClass(_ fat: Float, isMale: Bool) -> BodyFatClass {
    if isMale {
        if fat < 6  { return .low }
        if fat < 20 { return .normal }
        if fat < 25 { return .high }
        return .veryHigh
    } else {
        if fat < 14 { return .low }
        if fat < 28 { return .normal }
        if fat < 33 { return .high }
        return .veryHigh
    }
}

// MARK: - Timeline Entry

struct ScaleEntry: TimelineEntry {
    let date: Date
    let weightKg: Float?
    let fatPercent: Float?
    let readingDate: Date?
    let isMale: Bool
    let history: [WeightPoint]   // sorted oldest → newest

    // Trend delta from second-to-last → last reading
    var trendDeltaKg: Float? {
        guard history.count >= 2 else { return nil }
        let delta = history.last!.weightKg - history[history.count - 2].weightKg
        return abs(delta) > 0.05 ? delta : nil
    }

    var trendDeltaFat: Float? {
        guard history.count >= 2,
              let last = history.last?.fatPercent,
              let prev = history[history.count - 2].fatPercent else { return nil }
        let delta = last - prev
        return abs(delta) > 0.05 ? delta : nil
    }

    // Net change across the whole history window
    var netDeltaKg: Float? {
        guard history.count >= 2 else { return nil }
        return history.last!.weightKg - history.first!.weightKg
    }

    var netDeltaFat: Float? {
        guard history.count >= 2,
              let last = history.last?.fatPercent,
              let first = history.first?.fatPercent else { return nil }
        return last - first
    }

    var readingLabel: String? {
        guard let d = readingDate else { return nil }
        return Self.fmt.string(from: d)
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Helpers

private func deltaLabel(_ delta: Float, unit: String) -> String {
    let sign = delta < 0 ? "−" : "+"
    return "\(sign)\(String(format: "%.1f", abs(delta)))\(unit)"
}

private func deltaColor(_ delta: Float, lowerIsBetter: Bool = true) -> Color {
    if lowerIsBetter { return delta < 0 ? .green : .orange }
    return delta > 0 ? .green : .orange
}

// MARK: - Timeline Provider

struct ScaleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScaleEntry {
        let weights: [Float] = [73.2, 72.8, 73.5, 72.9, 73.1, 72.7, 73.8]
        let fats:    [Float] = [22.5, 22.3, 22.6, 22.2, 22.4, 22.1, 22.3]
        let fakeHistory = (0..<7).map { i in
            WeightPoint(date: Calendar.current.date(byAdding: .day, value: -(6 - i), to: .now)!,
                        weightKg: weights[i], fatPercent: fats[i])
        }
        return ScaleEntry(date: .now, weightKg: 73.8, fatPercent: 22.3,
                          readingDate: .now, isMale: true, history: fakeHistory)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScaleEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScaleEntry>) -> Void) {
        let entry = makeEntry()
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> ScaleEntry {
        ScaleEntry(
            date: .now,
            weightKg: SharedStore.readWeightKg(),
            fatPercent: SharedStore.readFatPercent(),
            readingDate: SharedStore.readDate(),
            isMale: SharedStore.readIsMale(),
            history: SharedStore.readHistory()
        )
    }
}

// MARK: - Sparkline

private struct SparklineChart: View {
    let points: [(date: Date, value: Double)]
    let color: Color

    var body: some View {
        Chart(points, id: \.date) { p in
            LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.25), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
        }
        .foregroundStyle(color)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - Small widget (systemSmall)

private struct SmallView: View {
    let entry: ScaleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Weight", systemImage: "scalemass.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.indigo)
            Spacer()
            if let w = entry.weightKg {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", w))
                        .font(.system(size: 38, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("kg")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data yet").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            // Trend delta replaces date on small widget (space constrained)
            if let delta = entry.trendDeltaKg {
                Text(deltaLabel(delta, unit: " kg"))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(deltaColor(delta))
                    .padding(.top, 6)
            } else if let label = entry.readingLabel {
                Text(label).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium widget (systemMedium)

private struct MediumView: View {
    let entry: ScaleEntry

    private var fatClass: BodyFatClass? {
        entry.fatPercent.map { bodyFatClass($0, isMale: entry.isMale) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 0) {
                metricColumn(
                    label: "Weight", icon: "scalemass.fill", headerColor: .indigo,
                    value: entry.weightKg.map { String(format: "%.1f", $0) } ?? "--",
                    valueColor: .primary, unit: "kg",
                    badge: nil, delta: entry.trendDeltaKg, unit2: "kg"
                )
                Divider().padding(.vertical, 4).padding(.horizontal, 8)
                metricColumn(
                    label: "Body Fat", icon: "flame.fill", headerColor: .orange,
                    value: entry.fatPercent.map { String(format: "%.1f", $0) } ?? "--",
                    valueColor: fatClass?.color ?? .primary, unit: "%",
                    badge: fatClass?.label, delta: entry.trendDeltaFat, unit2: "%"
                )
            }
            if let label = entry.readingLabel {
                Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func metricColumn(
        label: String, icon: String, headerColor: Color,
        value: String, valueColor: Color, unit: String,
        badge: String?, delta: Float?, unit2: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(headerColor)
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(valueColor)
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                if let delta {
                    Text(deltaLabel(delta, unit: unit2))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(deltaColor(delta))
                }
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(valueColor)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(valueColor.opacity(0.15), in: Capsule())
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Medium chart widget (systemMedium)

private struct ChartMediumView: View {
    let entry: ScaleEntry

    private var weightPoints: [(date: Date, value: Double)] {
        entry.history.map { (date: $0.date, value: Double($0.weightKg)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Weight", systemImage: "scalemass.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                if let w = entry.weightKg {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", w))
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                        Text("kg").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        if let delta = entry.netDeltaKg {
                            Text(deltaLabel(delta, unit: ""))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(deltaColor(delta))
                        }
                    }
                }
            }
            if weightPoints.count > 1 {
                SparklineChart(points: weightPoints, color: .indigo)
            } else {
                Text("Weigh in a few more times to see a chart")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let label = entry.readingLabel {
                Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large chart widget (systemLarge)

private struct ChartLargeView: View {
    let entry: ScaleEntry

    private var weightPoints: [(date: Date, value: Double)] {
        entry.history.map { (date: $0.date, value: Double($0.weightKg)) }
    }

    private var fatPoints: [(date: Date, value: Double)] {
        entry.history.compactMap { p in p.fatPercent.map { (date: p.date, value: Double($0)) } }
    }

    private var fatClass: BodyFatClass? {
        entry.fatPercent.map { bodyFatClass($0, isMale: entry.isMale) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartSection(
                label: "Weight", icon: "scalemass.fill", color: .indigo,
                value: entry.weightKg.map { String(format: "%.1f", $0) }, unit: "kg",
                netDelta: entry.netDeltaKg, deltaUnit: "", points: weightPoints
            )
            Divider()
            chartSection(
                label: "Body Fat", icon: "flame.fill", color: fatClass?.color ?? .orange,
                value: entry.fatPercent.map { String(format: "%.1f", $0) }, unit: "%",
                netDelta: entry.netDeltaFat, deltaUnit: "", points: fatPoints
            )
            if let label = entry.readingLabel {
                Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func chartSection(
        label: String, icon: String, color: Color,
        value: String?, unit: String, netDelta: Float?, deltaUnit: String,
        points: [(date: Date, value: Double)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(label, systemImage: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                if let v = value {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(v).font(.system(size: 20, weight: .bold).monospacedDigit())
                        Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        if let delta = netDelta {
                            Text(deltaLabel(delta, unit: deltaUnit))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(deltaColor(delta))
                        }
                    }
                }
            }
            if points.count > 1 {
                SparklineChart(points: points, color: color)
            } else {
                Text("Not enough data").font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Lock screen circular

private struct CircularView: View {
    let entry: ScaleEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let w = entry.weightKg {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", w))
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                    Text("kg").font(.system(size: 9, weight: .medium))
                }
            } else {
                Image(systemName: "scalemass").font(.system(size: 20))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Lock screen rectangular

private struct RectangularView: View {
    let entry: ScaleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(icon: "scalemass.fill", text: entry.weightKg.map { String(format: "%.1f kg", $0) } ?? "-- kg")
            row(icon: "flame.fill",     text: entry.fatPercent.map { String(format: "%.1f%%", $0) } ?? "--%")
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func row(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).frame(width: 14, alignment: .center)
            Text(text)
        }
    }
}

// MARK: - Widget declarations

struct ScaleBridgeWeightWidget: Widget {
    let kind = "SB_Weight"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScaleProvider()) { SmallView(entry: $0) }
            .configurationDisplayName("Weight")
            .description("Your latest weight reading.")
            .supportedFamilies([.systemSmall])
    }
}

struct ScaleBridgeOverviewWidget: Widget {
    let kind = "SB_Overview"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScaleProvider()) { MediumView(entry: $0) }
            .configurationDisplayName("Body Overview")
            .description("Weight and body fat from your latest reading.")
            .supportedFamilies([.systemMedium])
    }
}

struct ScaleBridgeChartWidget: Widget {
    let kind = "SB_Chart"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScaleProvider()) { ChartMediumView(entry: $0) }
            .configurationDisplayName("Weight Chart")
            .description("Your weight trend over recent readings.")
            .supportedFamilies([.systemMedium])
    }
}

struct ScaleBridgeLargeChartWidget: Widget {
    let kind = "SB_LargeChart"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScaleProvider()) { ChartLargeView(entry: $0) }
            .configurationDisplayName("Body Chart")
            .description("Weight and body fat trends over recent readings.")
            .supportedFamilies([.systemLarge])
    }
}

struct ScaleBridgeLockCircleWidget: Widget {
    let kind = "SB_LockCircle"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScaleProvider()) { CircularView(entry: $0) }
            .configurationDisplayName("Weight (Lock Screen)")
            .description("Weight on your lock screen.")
            .supportedFamilies([.accessoryCircular])
    }
}

struct ScaleBridgeLockRectWidget: Widget {
    let kind = "SB_LockRect"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScaleProvider()) { RectangularView(entry: $0) }
            .configurationDisplayName("Reading (Lock Screen)")
            .description("Weight and body fat on your lock screen.")
            .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Previews

private let previewEntry: ScaleEntry = {
    let weights: [Float] = [73.2, 72.8, 73.5, 72.9, 73.1, 72.7, 73.8]
    let fats:    [Float] = [22.5, 22.3, 22.6, 22.2, 22.4, 22.1, 22.3]
    let history = (0..<7).map { i in
        WeightPoint(date: Calendar.current.date(byAdding: .day, value: -(6 - i), to: .now)!,
                    weightKg: weights[i], fatPercent: fats[i])
    }
    return ScaleEntry(date: .now, weightKg: 73.8, fatPercent: 22.3,
                      readingDate: .now, isMale: true, history: history)
}()

#Preview(as: .systemSmall)  { ScaleBridgeWeightWidget()    } timeline: { previewEntry }
#Preview(as: .systemMedium) { ScaleBridgeOverviewWidget()  } timeline: { previewEntry }
#Preview(as: .systemMedium) { ScaleBridgeChartWidget()     } timeline: { previewEntry }
#Preview(as: .systemLarge)  { ScaleBridgeLargeChartWidget()} timeline: { previewEntry }

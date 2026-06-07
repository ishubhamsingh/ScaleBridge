import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context

    var body: some View {
        let weighIns = profile.sortedWeighIns          // newest first
        let chartData = Array(weighIns.reversed())      // oldest first for charts
        Group {
            if weighIns.isEmpty {
                emptyState
            } else {
                list(weighIns: weighIns, chartData: chartData)
            }
        }
        .navigationTitle("\(profile.avatar) \(profile.name)")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "scalemass")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("No readings yet")
                .font(.title3).bold()
            Text("Weigh-ins will appear here after your first measurement.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - List

    private func list(weighIns: [WeighIn], chartData: [WeighIn]) -> some View {
        List {
            // Summary bar
            Section {
                summaryRow(weighIns)
            }

            // Charts — only when there are enough points
            if chartData.count >= 2 {
                Section("Weight trend") {
                    WeightChart(data: chartData)
                        .frame(height: 180)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                let fatData = chartData.filter { $0.fatPercent != nil }
                if fatData.count >= 2 {
                    Section("Body fat trend") {
                        BodyFatChart(data: fatData)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }
            }

            // Full reading list
            Section("All readings") {
                ForEach(weighIns, id: \.id) { weighIn in
                    WeighInRow(weighIn: weighIn, showHealthBadge: profile.isPrimary)
                }
                .onDelete { offsets in deleteWeighIns(at: offsets, from: weighIns) }
            }
        }
    }

    // MARK: - Summary row

    private func summaryRow(_ weighIns: [WeighIn]) -> some View {
        let recent    = Array(weighIns.prefix(30))
        let avgWeight = recent.map(\.weightKg).reduce(0, +) / Float(recent.count)
        let latestFat = weighIns.first?.fatPercent

        return HStack(spacing: 0) {
            statCell(label: "Readings", value: "\(weighIns.count)", unit: "")
            Divider().frame(height: 40)
            statCell(label: "Avg weight", value: String(format: "%.1f", avgWeight), unit: " kg")
            if let fat = latestFat {
                Divider().frame(height: 40)
                statCell(label: "Latest fat", value: String(format: "%.1f", fat), unit: "%")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func statCell(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value).font(.title2).fontWeight(.semibold)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Delete

    private func deleteWeighIns(at offsets: IndexSet, from weighIns: [WeighIn]) {
        for index in offsets { context.delete(weighIns[index]) }
        try? context.save()
    }
}

// MARK: - Weight chart

private struct WeightChart: View {
    let data: [WeighIn]   // oldest first

    private var minY: Double {
        (data.map { Double($0.weightKg) }.min() ?? 60) - 2
    }
    private var maxY: Double {
        (data.map { Double($0.weightKg) }.max() ?? 100) + 2
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.id) { entry in
                AreaMark(
                    x: .value("Date", entry.date),
                    yStart: .value("Min", minY),
                    yEnd:   .value("Weight", Double(entry.weightKg))
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", Double(entry.weightKg))
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", Double(entry.weightKg))
                )
                .foregroundStyle(Color.blue)
                .symbolSize(30)
            }

        }
        .chartYScale(domain: minY...maxY)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))") } }
            }
        }
    }
}

// MARK: - Body fat chart

private struct BodyFatChart: View {
    let data: [WeighIn]   // oldest first, all have fatPercent != nil

    private var minY: Double {
        (data.compactMap { $0.fatPercent.map(Double.init) }.min() ?? 10) - 2
    }
    private var maxY: Double {
        (data.compactMap { $0.fatPercent.map(Double.init) }.max() ?? 40) + 2
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.id) { entry in
                if let fat = entry.fatPercent {
                    AreaMark(
                        x: .value("Date", entry.date),
                        yStart: .value("Min", minY),
                        yEnd:   .value("Fat", Double(fat))
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.orange.opacity(0.25), Color.orange.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Fat", Double(fat))
                    )
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Fat", Double(fat))
                    )
                    .foregroundStyle(Color.orange)
                    .symbolSize(30)
                }
            }

        }
        .chartYScale(domain: minY...maxY)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(String(format: "%.0f%%", v)) } }
            }
        }
    }
}

// MARK: - WeighInRow

struct WeighInRow: View {
    let weighIn: WeighIn
    let showHealthBadge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(weighIn.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if showHealthBadge && weighIn.syncedToHealthKit {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(weighIn.weightString)
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                metricPill(label: "Fat",    value: weighIn.fatString)
                metricPill(label: "Water",  value: weighIn.waterString)
                metricPill(label: "Muscle", value: weighIn.muscleString)
            }
        }
        .padding(.vertical, 2)
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption).fontWeight(.medium)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(minWidth: 44)
    }
}

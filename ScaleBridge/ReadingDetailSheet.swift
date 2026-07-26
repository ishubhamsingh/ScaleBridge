import SwiftUI
import SwiftData

// MARK: - ReadingDetailSheet
//
// Informational sheet for a single WeighIn record.
// Entry points: weight card chevron on Home, History rows (Phase 6),
// and optionally the Done screen (Phase 4 polish).
// Owns delete: tapping "Delete reading" confirms and removes from SwiftData.

struct ReadingDetailSheet: View {
    let weighIn: WeighIn
    let previousWeighIn: WeighIn?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Environment(CloudBackupManager.self) private var backup
    private let healthKit = HealthKitWriter.shared

    @State private var showingDeleteConfirm = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    heroCard
                    compositionSection
                    diagnosticsSection
                    deleteSection
                }
                .padding(.horizontal, DS.Space.screenGutter)
                .padding(.vertical, DS.Space.l)
                .padding(.bottom, DS.Space.xxxl)
            }
            .background(DS.Palette.ground.ignoresSafeArea())
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .alert("Delete this reading?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteReading() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will also remove it from Apple Health if it was synced.")
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            // Profile chip + date
            HStack {
                if let profile = weighIn.user {
                    HStack(spacing: DS.Space.s) {
                        Text(profile.avatar)
                            .font(.system(size: 15))
                            .frame(width: 26, height: 26)
                            .background(DS.Palette.ground, in: Circle())
                        Text(profile.name)
                            .font(DS.Typeface.bodyMedium)
                            .foregroundStyle(DS.Palette.label)
                        if profile.isPrimary {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                Spacer()
                Text(weighIn.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }

            // Hero weight
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", weighIn.weightKg))
                    .font(.system(size: 64, weight: .bold).monospacedDigit())
                    .tracking(-0.035 * 64)
                    .foregroundStyle(DS.Palette.label)
                Text("kg")
                    .font(DS.Typeface.title3)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }

            // Delta vs previous
            if let prev = previousWeighIn {
                let delta = weighIn.weightKg - prev.weightKg
                let good  = delta <= 0
                HStack(spacing: 4) {
                    Image(systemName: delta <= 0 ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.1f kg", abs(delta)))
                        .font(DS.Typeface.footnote)
                    Text("from \(daysSince(prev.date))")
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                .foregroundStyle(good ? DS.Palette.positive : DS.Palette.bodyFat)
            }

            // Sync row
            if weighIn.syncedToHealthKit {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Palette.muscle)
                    Text("Synced to Apple Health")
                        .font(DS.Typeface.footnote)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
        }
        .padding(DS.Space.cardPaddingHero)
        .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Body Composition

    private var isMale: Bool { weighIn.user?.isMale ?? true }

    private var compositionSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: "Body Composition")

            VStack(spacing: 0) {
                compRow(.bodyFat,
                        value: weighIn.fatPercent.map    { String(format: "%.1f%%", $0) },
                        classification: HomeClassify.classify(.bodyFat, value: weighIn.fatPercent, isMale: isMale))
                Divider().padding(.leading, 52)
                compRow(.muscle,
                        value: weighIn.musclePercent.map { String(format: "%.1f%%", $0) },
                        classification: HomeClassify.classify(.muscle, value: weighIn.musclePercent, isMale: isMale))
                Divider().padding(.leading, 52)
                compRow(.water,
                        value: weighIn.waterPercent.map  { String(format: "%.1f%%", $0) },
                        classification: HomeClassify.classify(.water, value: weighIn.waterPercent, isMale: isMale))
                Divider().padding(.leading, 52)
                compRow(.bmi,
                        value: weighIn.bmi.map           { String(format: "%.1f", $0) },
                        classification: HomeClassify.classify(.bmi, value: weighIn.bmi, isMale: isMale))
                Divider().padding(.leading, 52)
                compRow(.bone,
                        value: weighIn.bonePercent.map   { String(format: "%.1f%%", $0) })
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func compRow(_ metric: BodyMetric, value: String?, classification: Classification? = nil) -> some View {
        HStack(alignment: .center) {
            Image(systemName: metric.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(metric.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.label)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                if let cl = classification {
                    ClassificationPill(classification: cl)
                }
            }
            Spacer()
            Text(value ?? "—")
                .font(DS.Typeface.bodyMedium.monospacedDigit())
                .foregroundStyle(value != nil ? DS.Palette.label : DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, DS.Space.l)
        .frame(minHeight: 48)
        .padding(.vertical, DS.Space.s)
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: "Diagnostics")

            VStack(spacing: 0) {
                diagRow(label: "Impedance",
                        value: String(format: "%.0f Ω", weighIn.impedance))
                Divider().padding(.leading, DS.Space.l)
                diagRow(label: "Scale", value: "QN Scale")
                Divider().padding(.leading, DS.Space.l)
                healthSourceRow
            }
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func diagRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Text(value)
                .font(DS.Typeface.bodyMedium.monospacedDigit())
                .foregroundStyle(DS.Palette.secondaryLabel)
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: 48)
    }

    private var healthSourceRow: some View {
        HStack {
            Text("Health source")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            if weighIn.syncedToHealthKit {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.muscle)
                    Text("Synced \(relativeDate(weighIn.date))")
                        .font(DS.Typeface.subheadline)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            } else {
                Text("Not synced")
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: 48)
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Button {
            showingDeleteConfirm = true
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                Text("Delete reading")
                    .font(DS.Typeface.body)
            }
            .foregroundStyle(DS.Palette.muscle)   // systemRed
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func daysSince(_ date: Date) -> String {
        let d = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if d == 0 { return "today" }
        if d == 1 { return "yesterday" }
        return "\(d) days ago"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func deleteReading() {
        // Capture what the async cleanup needs before the object leaves the store.
        let id = weighIn.id
        let date = weighIn.date
        let wasSynced = weighIn.syncedToHealthKit

        context.delete(weighIn)
        try? context.save()

        // Local delete is the source of truth; the copies follow. Detached so the
        // sheet dismisses immediately and network latency isn't in the user's way.
        Task {
            if wasSynced { await healthKit.deleteSamples(around: date) }
            await backup.deleteWeighIns(ids: [id])
        }

        dismiss()
    }
}

import Foundation
import SwiftData

// MARK: - WeighIn
//
// One persisted measurement record. Only the raw + Trisa-computed fields are
// stored as SwiftData columns. Extended body-comp metrics (BMR, skeletal muscle,
// visceral fat, etc.) are derived on-the-fly from these stored values + the
// linked UserProfile, so no schema migration is needed when the metric set grows.

@Model
final class WeighIn {

    // MARK: Stored properties (schema-stable)

    @Attribute(.unique) var id: UUID
    var date: Date

    var weightKg: Float
    var impedance: Float        // raw resistance (Ω-ish, vendor units)

    var fatPercent:    Float?
    var waterPercent:  Float?
    var musclePercent: Float?
    var bonePercent:   Float?
    var bmi:           Float?

    /// True once this reading has been successfully written to Apple Health.
    /// Only ever true for the primary user's readings.
    var syncedToHealthKit: Bool

    // MARK: Relationship

    var user: UserProfile?

    // MARK: Init

    init(from measurement: ScaleMeasurement, user: UserProfile) {
        self.id            = UUID()
        self.date          = measurement.date
        self.weightKg      = measurement.weightKg
        self.impedance     = measurement.impedance
        self.fatPercent    = measurement.fatPercent
        self.waterPercent  = measurement.waterPercent
        self.musclePercent = measurement.musclePercent
        self.bonePercent   = measurement.bonePercent
        self.bmi           = measurement.bmi
        self.syncedToHealthKit = false
        self.user          = user
    }
}

// MARK: - Core derived metrics (no profile needed)

extension WeighIn {
    var leanMassKg: Float? {
        guard let f = fatPercent else { return nil }
        return weightKg * (1 - f / 100)
    }
    var fatMassKg: Float? {
        guard let f = fatPercent else { return nil }
        return weightKg * (f / 100)
    }

    // Simple single-field derivatives
    var proteinPercent:         Float? { fatPercent.map         { (100 - $0) * 0.204 } }
    var skeletalMusclePercent:  Float? { musclePercent.map      { $0 * 0.679 } }
    var subcutaneousFatPercent: Float? { fatPercent.map         { $0 * 0.9 } }
    var muscleMassKg:           Float? { musclePercent.map      { weightKg * $0 / 100 } }
    var mineralSaltKg:          Float? { leanMassKg.map         { $0 * 0.016 } }
    // visceralFatPercent also accesses user?.isMale; compute at call site with a known profile.
}

// Profile-dependent metrics (bmr, metabolicAge, standardWeight, bestVisualWeight,
// weightControl, fatControl, muscleControl, obesityDegree, healthScore) are NOT
// computed here to avoid cross-@Observable access on iOS 27+, which can trigger
// infinite view re-render cycles. Callers that have a UserProfile in scope should
// use TrisaBodyComposition directly. See HomeView.tileValue / MetricDetailView.value.

// MARK: - Formatted strings (list rows and chart tooltips)

extension WeighIn {
    var weightString:             String { String(format: "%.1f kg",  weightKg) }
    var fatString:                String { fatPercent.map    { String(format: "%.1f%%",   $0) } ?? "—" }
    var waterString:              String { waterPercent.map  { String(format: "%.1f%%",   $0) } ?? "—" }
    var muscleString:             String { musclePercent.map { String(format: "%.1f%%",   $0) } ?? "—" }
    var boneString:               String { bonePercent.map   { String(format: "%.1f%%",   $0) } ?? "—" }
    var bmiString:                String { bmi.map           { String(format: "%.1f",     $0) } ?? "—" }
    var leanString:               String { leanMassKg.map    { String(format: "%.1f kg",  $0) } ?? "—" }

    var proteinString:            String { proteinPercent.map         { String(format: "%.1f%%",  $0) } ?? "—" }
    var skeletalMuscleString:     String { skeletalMusclePercent.map  { String(format: "%.1f%%",  $0) } ?? "—" }
    var subcutaneousFatString:    String { subcutaneousFatPercent.map { String(format: "%.1f%%",  $0) } ?? "—" }
    var muscleMassKgString:       String { muscleMassKg.map           { String(format: "%.1f kg", $0) } ?? "—" }
    var mineralSaltString:        String { mineralSaltKg.map          { String(format: "%.2f kg", $0) } ?? "—" }
}

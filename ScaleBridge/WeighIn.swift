import Foundation
import SwiftData

// MARK: - WeighIn
//
// One persisted measurement record. Weight and impedance come off the wire;
// the body-composition fields are computed by QNScaleParser / TrisaBodyComposition
// before being handed here. leanMassKg and fatMassKg are derived on-the-fly
// so they don't need their own columns.
//
// The `syncedToHealthKit` flag is set to true after a successful HealthKit
// save, so we never double-write if the app is opened again near the scale.

@Model
final class WeighIn {

    // MARK: Stored properties

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

// MARK: - Derived metrics

extension WeighIn {
    var leanMassKg: Float? {
        guard let f = fatPercent else { return nil }
        return weightKg * (1 - f / 100)
    }
    var fatMassKg: Float? {
        guard let f = fatPercent else { return nil }
        return weightKg * (f / 100)
    }

    // MARK: Formatted strings (used in list rows and chart tooltips)

    var weightString:  String { String(format: "%.1f kg", weightKg) }
    var fatString:     String { fatPercent.map    { String(format: "%.1f%%", $0) } ?? "—" }
    var waterString:   String { waterPercent.map  { String(format: "%.1f%%", $0) } ?? "—" }
    var muscleString:  String { musclePercent.map { String(format: "%.1f%%", $0) } ?? "—" }
    var boneString:    String { bonePercent.map   { String(format: "%.1f%%", $0) } ?? "—" }
    var bmiString:     String { bmi.map           { String(format: "%.1f",   $0) } ?? "—" }
    var leanString:    String { leanMassKg.map    { String(format: "%.1f kg",$0) } ?? "—" }
}

import Foundation
import HealthKit

/// Writes a finished reading into Apple Health.
///
/// HealthKit has native sample types for weight, body-fat %, lean mass and BMI.
/// It has NO native types for body-water %, muscle % or bone % — those stay in your
/// own store (add a local DB later) or you can model them as your app's own metadata.
final class HealthKitWriter {

    private let store = HKHealthStore()

    private var writeTypes: Set<HKSampleType> {
        let ids: [HKQuantityTypeIdentifier] = [.bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex]
        return Set(ids.map { HKObjectType.quantityType(forIdentifier: $0)! })
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Call once (e.g. at first launch) to request write permission.
    func requestAuthorization() async throws {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }
        try await store.requestAuthorization(toShare: writeTypes, read: [])
    }

    func save(_ m: ScaleMeasurement) async throws {
        guard isAvailable else { throw HKError(.errorHealthDataUnavailable) }

        var samples: [HKQuantitySample] = []
        let date = m.date

        func sample(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) -> HKQuantitySample {
            HKQuantitySample(type: HKQuantityType.quantityType(forIdentifier: id)!,
                             quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: date, end: date)
        }

        samples.append(sample(.bodyMass, .gramUnit(with: .kilo), Double(m.weightKg)))

        if let fat = m.fatPercent {
            // HealthKit expects a fraction (0–1) for percentage types.
            samples.append(sample(.bodyFatPercentage, .percent(), Double(fat) / 100.0))
        }
        if let lean = m.leanMassKg {
            samples.append(sample(.leanBodyMass, .gramUnit(with: .kilo), Double(lean)))
        }
        if let bmi = m.bmi {
            samples.append(sample(.bodyMassIndex, .count(), Double(bmi)))
        }

        try await store.save(samples)
    }
}

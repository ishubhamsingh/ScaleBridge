import Foundation
import HealthKit

/// Writes a finished reading into Apple Health.
///
/// HealthKit has native sample types for weight, body-fat %, lean mass and BMI.
/// It has NO native types for body-water %, muscle % or bone % — those stay in your
/// own store (add a local DB later) or you can model them as your app's own metadata.
///
/// Authorization failures are recorded rather than thrown away: iOS only ever shows
/// the permission sheet once per install, so when a request fails (missing entitlement
/// under a re-signed build, for example) the reason has to be visible somewhere.
@MainActor
@Observable
final class HealthKitWriter {

    /// Shared instance so Settings and the weigh-in flow report the same state.
    static let shared = HealthKitWriter()

    enum Status: Equatable {
        case unknown        // not checked yet
        case unavailable    // HealthKit not present on this device
        case notDetermined  // never successfully asked
        case authorized     // all write types granted
        case partial        // some granted, some not
        case denied         // at least one write type refused
    }

    private(set) var status: Status = .unknown
    /// Most recent authorization or save failure, kept for the Settings diagnostics row.
    private(set) var lastError: String?

    private let store = HKHealthStore()

    private var writeTypes: Set<HKSampleType> {
        let ids: [HKQuantityTypeIdentifier] = [.bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex]
        return Set(ids.map { HKObjectType.quantityType(forIdentifier: $0)! })
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Status

    /// Reads the current share status without prompting.
    func refreshStatus() {
        guard isAvailable else {
            status = .unavailable
            return
        }
        let statuses = writeTypes.map { store.authorizationStatus(for: $0) }
        if statuses.contains(.sharingDenied) {
            status = statuses.contains(.sharingAuthorized) ? .partial : .denied
        } else if statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            status = .authorized
        } else {
            status = .notDetermined
        }
    }

    /// Requests write permission and records the outcome.
    ///
    /// Deliberately non-throwing: the failure is the thing we need to surface, and
    /// every previous call site discarded it with `try?`.
    @discardableResult
    func requestAuthorization() async -> Status {
        guard isAvailable else {
            status = .unavailable
            lastError = "Health data is not available on this device."
            return status
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: [])
            lastError = nil
        } catch {
            // Typically a missing `com.apple.developer.healthkit` entitlement —
            // the request never reaches the system, so no permission sheet appears.
            lastError = "Health permission request failed: \(error.localizedDescription)"
        }
        // A request that returns without error still doesn't mean "granted".
        refreshStatus()
        return status
    }

    // MARK: Save

    func save(_ m: ScaleMeasurement) async throws {
        guard isAvailable else {
            let err = HKError(.errorHealthDataUnavailable)
            lastError = "Health data is not available on this device."
            throw err
        }

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

        do {
            try await store.save(samples)
            lastError = nil
        } catch {
            lastError = "Health save failed: \(error.localizedDescription)"
            refreshStatus()
            throw error
        }
    }

    // MARK: Delete

    /// Removes the samples this app wrote for a reading taken at `date`.
    ///
    /// HealthKit only permits deleting samples your own app saved, so the ±1s window
    /// can't touch data from the Health app or another source. Best-effort: a failure
    /// is recorded but never blocks the local delete.
    func deleteSamples(around date: Date) async {
        guard isAvailable else { return }

        let predicate = HKQuery.predicateForSamples(
            withStart: date.addingTimeInterval(-1),
            end:       date.addingTimeInterval(1)
        )

        for type in writeTypes {
            let failure: String? = await withCheckedContinuation { continuation in
                store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                    // "No objects found" just means nothing of ours matched.
                    if let error, (error as? HKError)?.code != .errorNoData {
                        continuation.resume(returning: error.localizedDescription)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let failure { lastError = "Health delete failed: \(failure)" }
        }
    }
}

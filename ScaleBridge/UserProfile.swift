import Foundation
import SwiftData

// MARK: - UserProfile
//
// Persisted with SwiftData. One profile is marked `isPrimary`; that user's
// readings are written to Apple Health in addition to the local store.
// All other users get local-only records.
//
// Age is derived from dateOfBirth so it stays accurate without manual updates.

@Model
final class UserProfile {

    // MARK: Stored properties

    @Attribute(.unique) var id: UUID
    var name: String
    var isMale: Bool
    /// Stored as date of birth so age auto-updates over time.
    var dateOfBirth: Date
    /// Height in centimetres (canonical storage unit regardless of display preference).
    var heightCm: Float
    /// True for exactly one profile. That profile's readings sync to Apple Health.
    var isPrimary: Bool
    /// A single emoji shown as the avatar.
    var avatar: String
    var createdAt: Date

    // MARK: Relationship

    @Relationship(deleteRule: .cascade, inverse: \WeighIn.user)
    var weighIns: [WeighIn] = []

    // MARK: Init

    init(
        name: String,
        isMale: Bool,
        dateOfBirth: Date,
        heightCm: Float,
        isPrimary: Bool = false,
        avatar: String = "👤"
    ) {
        self.id          = UUID()
        self.name        = name
        self.isMale      = isMale
        self.dateOfBirth = dateOfBirth
        self.heightCm    = heightCm
        self.isPrimary   = isPrimary
        self.avatar      = avatar
        self.createdAt   = Date()
    }
}

// MARK: - Computed helpers

extension UserProfile {

    /// Age in whole years, calculated fresh each time from dateOfBirth.
    var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now).year ?? 0
    }

    /// Bridge to the value-type used by the parser and Trisa body-comp math.
    var scaleUser: ScaleUser {
        ScaleUser(isMale: isMale, age: max(age, 1), heightCm: heightCm)
    }

    /// Sorted weigh-ins, newest first.
    var sortedWeighIns: [WeighIn] {
        weighIns.sorted { $0.date > $1.date }
    }

    var latestWeighIn: WeighIn? { sortedWeighIns.first }

    /// One-line summary shown in list rows and the active-user chip.
    var subtitle: String {
        "\(isMale ? "♂" : "♀") · \(age) y · \(Int(heightCm)) cm"
    }
}

// MARK: - Avatar palette

extension UserProfile {
    static let avatarOptions: [String] = [
        "👤","👨","👩","👦","👧","🧑","👴","👵",
        "🧔","👱","🧒","🙋","🙋‍♂️","🙋‍♀️","🏃","🏃‍♀️"
    ]
}

// MARK: - Height unit helpers (UI-facing, not stored)

enum HeightUnit: String {
    case cm   = "cm"
    case ftIn = "ft · in"
}

extension Float {
    /// Total inches from a centimetre value.
    var totalInches: Int { Int(self / 2.54) }

    /// Feet component (e.g. 175 cm → 5).
    var feet: Int { totalInches / 12 }

    /// Inches remainder (e.g. 175 cm → 8 in).
    var remainderInches: Int { totalInches % 12 }

    /// Human-readable height string, e.g. "175 cm" or "5 ft 8 in".
    func heightString(unit: HeightUnit) -> String {
        switch unit {
        case .cm:   return "\(Int(self)) cm"
        case .ftIn: return "\(feet) ft \(remainderInches) in"
        }
    }

    /// Build a cm value from feet + inches.
    static func fromFtIn(feet: Int, inches: Int) -> Float {
        Float(feet * 12 + inches) * 2.54
    }
}

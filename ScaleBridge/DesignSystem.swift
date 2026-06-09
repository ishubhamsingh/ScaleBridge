import SwiftUI

// MARK: - Palette
//
// Stock iOS system colors picked to match the Apple Health visual register.
// Each accent is paired with the body-comp metric it represents (see BodyMetric).
// The ground / card pairing is systemGroupedBackground + secondarySystemGroupedBackground,
// so cards float over a cool gray field in both light and dark mode.

enum DS {

    enum Palette {
        static let ground = Color(.systemGroupedBackground)   // #F2F2F7
        static let card   = Color(.secondarySystemGroupedBackground) // #FFF light / #2C2C2E dark
        static let label          = Color(.label)             // #000
        static let secondaryLabel = Color(.secondaryLabel)    // ~#8E8E93
        static let tertiaryLabel  = Color(.tertiaryLabel)
        static let separator      = Color(.separator)
        static let hairline       = Color(.systemGray5)

        // Metric accents (mapped via BodyMetric.color)
        static let weight   = Color(.systemIndigo)   // #5856D6
        static let bodyFat  = Color(.systemOrange)   // #FF9500
        static let muscle   = Color(.systemRed)      // #FF3B30
        static let water    = Color(.systemTeal)     // #5AC8FA
        static let bmi      = Color(.systemPurple)   // #AF52DE
        static let positive = Color(.systemGreen)    // #34C759
    }

    // MARK: - Typography
    //
    // Sizes lifted from the Design System artboard's "03 · Typography" stack.
    // Hero readouts use tabular figures so the number doesn't jitter while a
    // reading is settling.

    enum Typeface {
        static func hero(_ size: CGFloat = 44) -> Font {
            .system(size: size, weight: .bold, design: .default).monospacedDigit()
        }
        static let largeTitle  = Font.system(size: 34, weight: .bold)          // "Today"
        static let title2      = Font.system(size: 22, weight: .bold)
        static let title3      = Font.system(size: 20, weight: .semibold)
        static let cardTitle   = Font.system(size: 15, weight: .semibold)      // accent-colored card titles
        static let body        = Font.system(size: 17, weight: .regular)
        static let bodyMedium  = Font.system(size: 17, weight: .medium)
        static let callout     = Font.system(size: 16, weight: .regular)
        static let subheadline = Font.system(size: 15, weight: .regular)
        static let footnote    = Font.system(size: 13, weight: .medium)        // "3 days since last weigh-in"
        static let caption     = Font.system(size: 12, weight: .regular)
        static let dateCaps    = Font.system(size: 13, weight: .bold)          // tracked + uppercased at call site
    }

    // MARK: - Spacing
    //
    // Cards use 16/20 internal padding; screens use 16 horizontal gutters and
    // 24 vertical rhythm between groups (matching the Home and Metric Detail artboards).

    enum Space {
        static let xs:  CGFloat = 4
        static let s:   CGFloat = 8
        static let m:   CGFloat = 12
        static let l:   CGFloat = 16
        static let xl:  CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32

        static let screenGutter:  CGFloat = 16
        static let cardPadding:   CGFloat = 16
        static let cardPaddingHero: CGFloat = 20
    }

    enum Radius {
        static let small:  CGFloat = 8
        static let card:   CGFloat = 16
        static let large:  CGFloat = 22
        static let pill:   CGFloat = 999
    }

    enum Stroke {
        static let hairline: CGFloat = 0.5
    }
}

// MARK: - BodyMetric
//
// Single source of truth for "which metric is this" — color, label, SF Symbol,
// unit, decimals. Used by Home tiles, Metric Detail headers, classification
// chips, and chart accents.

enum BodyMetric: String, CaseIterable, Identifiable {
    // Core Trisa metrics
    case weight, bodyFat, muscle, water, bmi, lean, bone
    // Extended metrics
    case bmr, metabolicAge, protein, skeletalMuscle
    case subcutaneousFat, visceralFat, muscleMassKg, mineralSalt
    case bestVisualWeight, standardWeight
    case weightControl, fatControl, muscleControl
    case obesityDegree, healthScore

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight:          "Weight"
        case .bodyFat:         "Body Fat"
        case .muscle:          "Muscle"
        case .water:           "Water"
        case .bmi:             "BMI"
        case .lean:            "Lean Mass"
        case .bone:            "Bone"
        case .bmr:             "BMR"
        case .metabolicAge:    "Metabolic Age"
        case .protein:         "Protein"
        case .skeletalMuscle:  "Skeletal Muscle"
        case .subcutaneousFat: "Subcutaneous Fat"
        case .visceralFat:     "Visceral Fat"
        case .muscleMassKg:    "Muscle Mass"
        case .mineralSalt:     "Mineral Salt"
        case .bestVisualWeight:"Best Visual Weight"
        case .standardWeight:  "Standard Weight"
        case .weightControl:   "Weight Control"
        case .fatControl:      "Fat Control"
        case .muscleControl:   "Muscle Control"
        case .obesityDegree:   "Obesity Degree"
        case .healthScore:     "Health Score"
        }
    }

    var shortLabel: String {
        switch self {
        case .weight:          "Weight"
        case .bodyFat:         "Fat"
        case .muscle:          "Muscle"
        case .water:           "Water"
        case .bmi:             "BMI"
        case .lean:            "Lean"
        case .bone:            "Bone"
        case .bmr:             "BMR"
        case .metabolicAge:    "Met. Age"
        case .protein:         "Protein"
        case .skeletalMuscle:  "Skel. Muscle"
        case .subcutaneousFat: "Subcut. Fat"
        case .visceralFat:     "Visceral Fat"
        case .muscleMassKg:    "Muscle kg"
        case .mineralSalt:     "Mineral"
        case .bestVisualWeight:"Best Weight"
        case .standardWeight:  "Std. Weight"
        case .weightControl:   "Wt. Control"
        case .fatControl:      "Fat Control"
        case .muscleControl:   "Mus. Control"
        case .obesityDegree:   "Obesity"
        case .healthScore:     "Score"
        }
    }

    var color: Color {
        switch self {
        case .weight, .lean, .muscleMassKg,
             .bestVisualWeight, .standardWeight,
             .weightControl:                     DS.Palette.weight
        case .bodyFat, .subcutaneousFat,
             .visceralFat, .obesityDegree,
             .fatControl:                        DS.Palette.bodyFat
        case .muscle, .skeletalMuscle,
             .muscleControl:                     DS.Palette.muscle
        case .water:                             DS.Palette.water
        case .bmi:                               DS.Palette.bmi
        case .bone, .mineralSalt:                DS.Palette.secondaryLabel
        case .bmr, .metabolicAge, .healthScore,
             .protein:                           DS.Palette.bmi
        }
    }

    var symbol: String {
        switch self {
        case .weight:          "scalemass"
        case .bodyFat:         "drop.fill"
        case .muscle:          "figure.strengthtraining.traditional"
        case .water:           "drop"
        case .bmi:             "ruler"
        case .lean:            "figure.arms.open"
        case .bone:            "diamond"
        case .bmr:             "flame.fill"
        case .metabolicAge:    "clock.badge.checkmark"
        case .protein:         "atom"
        case .skeletalMuscle:  "figure.run"
        case .subcutaneousFat: "circle.dashed"
        case .visceralFat:     "circle.fill"
        case .muscleMassKg:    "dumbbell.fill"
        case .mineralSalt:     "sparkles"
        case .bestVisualWeight:"eye"
        case .standardWeight:  "target"
        case .weightControl:   "arrow.up.and.down"
        case .fatControl:      "minus.circle"
        case .muscleControl:   "plus.circle"
        case .obesityDegree:   "exclamationmark.circle"
        case .healthScore:     "heart.text.square.fill"
        }
    }

    var unit: String {
        switch self {
        case .weight, .lean, .muscleMassKg,
             .mineralSalt, .bestVisualWeight,
             .standardWeight, .weightControl,
             .fatControl, .muscleControl:    "kg"
        case .bodyFat, .muscle, .water,
             .bone, .protein, .skeletalMuscle,
             .subcutaneousFat, .visceralFat,
             .obesityDegree:                "%"
        case .bmi, .healthScore:            ""
        case .bmr:                          "kcal"
        case .metabolicAge:                 "yrs"
        }
    }

    var decimals: Int {
        switch self {
        case .bmr, .metabolicAge, .healthScore: 0
        case .mineralSalt:                      2
        default:                                1
        }
    }

    var lowerIsBetter: Bool {
        switch self {
        case .weight, .bodyFat, .bmi,
             .subcutaneousFat, .visceralFat,
             .obesityDegree, .metabolicAge:  return true
        case .muscle, .water, .lean, .bone,
             .protein, .skeletalMuscle,
             .muscleMassKg, .healthScore,
             .bmr:                           return false
        // reference / control metrics: neither direction is inherently better
        case .mineralSalt, .bestVisualWeight,
             .standardWeight, .weightControl,
             .fatControl, .muscleControl:    return true
        }
    }
}

// MARK: - Classification
//
// Per-metric range bands rendered in semantic colors. Used by the small chip
// under metric values and by the colored bands on Metric Detail charts.
// The actual numeric ranges live with the metric math (Phase 7); this type is
// just the visual + label vocabulary the rest of the UI consumes.

enum Classification: String {
    case low, normal, high, veryHigh

    var label: String {
        switch self {
        case .low:      "Low"
        case .normal:   "Normal"
        case .high:     "High"
        case .veryHigh: "Very High"
        }
    }

    var color: Color {
        switch self {
        case .low:      DS.Palette.water       // teal — informational, not alarming
        case .normal:   DS.Palette.positive    // green
        case .high:     DS.Palette.bodyFat     // orange — caution
        case .veryHigh: DS.Palette.muscle      // red — concern
        }
    }
}

import SwiftUI

// MARK: - Palette
//
// Stock iOS system colors picked to match the Apple Health visual register.
// Each accent is paired with the body-comp metric it represents (see BodyMetric).
// The ground / card pairing is systemGroupedBackground + systemBackground,
// so cards float over a cool gray field exactly like Health does.

enum DS {

    enum Palette {
        static let ground = Color(.systemGroupedBackground)   // #F2F2F7
        static let card   = Color(.systemBackground)          // #FFFFFF in light mode
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
    case weight, bodyFat, muscle, water, bmi, lean, bone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight:  "Weight"
        case .bodyFat: "Body Fat"
        case .muscle:  "Muscle"
        case .water:   "Water"
        case .bmi:     "BMI"
        case .lean:    "Lean Mass"
        case .bone:    "Bone"
        }
    }

    var shortLabel: String {
        switch self {
        case .weight: "Weight"
        case .bodyFat: "Fat"
        case .muscle: "Muscle"
        case .water: "Water"
        case .bmi: "BMI"
        case .lean: "Lean"
        case .bone: "Bone"
        }
    }

    var color: Color {
        switch self {
        case .weight, .lean: DS.Palette.weight
        case .bodyFat:       DS.Palette.bodyFat
        case .muscle:        DS.Palette.muscle
        case .water:         DS.Palette.water
        case .bmi:           DS.Palette.bmi
        case .bone:          DS.Palette.secondaryLabel
        }
    }

    var symbol: String {
        switch self {
        case .weight:  "scalemass"
        case .bodyFat: "drop.fill"
        case .muscle:  "figure.strengthtraining.traditional"
        case .water:   "drop"
        case .bmi:     "ruler"
        case .lean:    "figure.arms.open"
        case .bone:    "skeleton"
        }
    }

    var unit: String {
        switch self {
        case .weight, .lean: "kg"
        case .bodyFat, .muscle, .water, .bone: "%"
        case .bmi: ""
        }
    }

    var decimals: Int {
        switch self {
        case .weight, .lean: 1
        case .bodyFat, .muscle, .water, .bone, .bmi: 1
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

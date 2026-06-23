import SwiftUI

// MARK: - Card
//
// The white surface that floats on the cool-gray ground. Used for hero readout,
// metric tiles, list groups, and detail sections. Per memory: cards stay opaque —
// no Liquid Glass on cards (glass is only for floating chrome).

struct CardBackground: ViewModifier {
    var radius: CGFloat = DS.Radius.card
    var padding: CGFloat = DS.Space.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DS.Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func dsCard(radius: CGFloat = DS.Radius.card, padding: CGFloat = DS.Space.cardPadding) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }
}

// MARK: - Liquid Glass helper
//
// iOS 26 Liquid Glass is the right material for *floating chrome* only — pill
// buttons, circle buttons, the tab bar. Cards keep their opaque surface.

extension View {
    /// Wrap floating chrome (pill buttons, tab bars) in the iOS 26 Liquid Glass material.
    /// Adds the matching subtle shadow seen in the Design System artboard.
    func dsGlass<S: Shape>(in shape: S = Capsule()) -> some View {
        self
            .glassEffect(.regular, in: shape)
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Section header
//
// The small bold caps label that introduces a card section (e.g.
// "01 · PALETTE" on the Design System artboard; "TODAY" on Home).

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(DS.Typeface.dateCaps)
                .tracking(0.04 * 13)             // 0.04em at 13px
                .foregroundStyle(DS.Palette.secondaryLabel)
            Spacer(minLength: 0)
            trailing
        }
    }
}

// MARK: - Hero readout
//
// The large tabular number used on Home and at the top of Metric Detail.
// Pairs a big number (e.g. "72.4") with a unit and an optional subtitle below.

struct HeroReadout: View {
    let value: String
    var unit: String = ""
    var caption: String? = nil
    var accent: Color = DS.Palette.label

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .lastTextBaseline, spacing: DS.Space.s) {
                Text(value)
                    .font(DS.Typeface.hero(64))
                    .tracking(-0.035 * 64)        // -0.035em
                    .foregroundStyle(accent)
                if !unit.isEmpty {
                    Text(unit)
                        .font(DS.Typeface.title3)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            if let caption {
                Text(caption)
                    .font(DS.Typeface.footnote)
                    .foregroundStyle(DS.Palette.secondaryLabel)
            }
        }
    }
}

// MARK: - Metric tile
//
// One body-composition tile shown in a grid on Home. Icon + accent-colored
// title at top; bold value + unit at the bottom. Tiles are themselves cards.

struct MetricTile: View {
    let metric: BodyMetric
    let value: String?
    var classification: Classification? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(metric.label)
                    .font(DS.Typeface.cardTitle)
            }
            .foregroundStyle(metric.color)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .default).monospacedDigit())
                    .foregroundStyle(DS.Palette.label)
                if let value, value != "—", !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(DS.Typeface.subheadline)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                Spacer(minLength: 0)
            }

            if let classification {
                ClassificationPill(classification: classification)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }
}

// MARK: - Classification pill
//
// Small color chip showing Low / Normal / High / Very High under a value.
// Per memory: classification lives as a sublabel on the *left* of a row, never
// appended to the trailing value — that's why this is a standalone pill.

struct ClassificationPill: View {
    let classification: Classification

    var body: some View {
        Text(classification.label)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.02 * 11)
            .foregroundStyle(classification.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(classification.color.opacity(0.15),
                        in: Capsule())
    }
}

// MARK: - Value row
//
// One label/value row inside a card. Optional left-side sublabel carries the
// per-row classification so the trailing value column stays clean and aligned
// across rows.

struct ValueRow: View {
    let label: String
    let value: String
    var sublabel: String? = nil
    var accent: Color = DS.Palette.label

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                if let sublabel {
                    Text(sublabel)
                        .font(DS.Typeface.caption)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            }
            Spacer(minLength: DS.Space.m)
            Text(value)
                .font(DS.Typeface.bodyMedium.monospacedDigit())
                .foregroundStyle(accent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Glass pill button
//
// Floating action button that lives over content (e.g. "Weigh in" CTA on Home,
// "Show More" on Metric Detail). Uses iOS 26 Liquid Glass.

struct GlassPillButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = DS.Palette.label
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(DS.Typeface.cardTitle)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(minHeight: 44)        // ≥44pt tap target (memory: tap-affordance rule)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsGlass(in: Capsule())
    }
}

// MARK: - Glass circle button
//
// 44×44 floating circle (e.g. profile-switcher avatar in the Design System
// glass row). Same material as the pill button.

struct GlassCircleButton<Label: View>: View {
    var size: CGFloat = 44
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dsGlass(in: Circle())
    }
}

// MARK: - Screen container
//
// The cool-gray ground every full screen sits on. Drop this around a ScrollView
// or VStack and content gets the right background + standard horizontal gutter.

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DS.Palette.ground.ignoresSafeArea())
    }
}

extension View {
    func dsScreen() -> some View { modifier(ScreenBackground()) }
}

// MARK: - Google G logo

struct GoogleGLogo: View {
    var size: CGFloat = 24

    var body: some View {
        Image("google_g")
            .resizable()
            .frame(width: size, height: size)
    }
}

// MARK: - Previews

#Preview("Tokens") {
    ScrollView {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            SectionHeader(title: "Hero readout")
            VStack(alignment: .leading) {
                HeroReadout(value: "72.4", unit: "kg",
                            caption: "3 days since last weigh-in · synced to Apple Health")
            }
            .dsCard(padding: DS.Space.cardPaddingHero)

            SectionHeader(title: "Metric tiles")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Space.m) {
                MetricTile(metric: .bodyFat, value: "18.2", classification: .normal)
                MetricTile(metric: .water,   value: "57.4", classification: .normal)
                MetricTile(metric: .muscle,  value: "42.1", classification: .high)
                MetricTile(metric: .bmi,     value: "23.6", classification: .normal)
            }

            SectionHeader(title: "Value rows")
            VStack(spacing: 0) {
                ValueRow(label: "BMI", value: "23.6", sublabel: "Normal")
                Divider()
                ValueRow(label: "Lean mass", value: "59.2 kg")
                Divider()
                ValueRow(label: "Bone", value: "3.4 %")
            }
            .dsCard()

            SectionHeader(title: "Glass chrome")
            HStack(spacing: DS.Space.m) {
                GlassPillButton(title: "Weigh in", systemImage: "scalemass") {}
                GlassCircleButton(action: {}) { Text("🧑").font(.system(size: 22)) }
                GlassPillButton(title: "Show More") {}
            }
            .padding(DS.Space.l)
            .background(
                LinearGradient(colors: [.purple, .orange],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: DS.Radius.large)
            )
        }
        .padding(DS.Space.screenGutter)
    }
    .dsScreen()
}

import SwiftUI

// MARK: - RangeBand

struct RangeBand: Identifiable {
    let id = UUID()
    let classification: Classification
    let from: Float
    let to: Float

    var color: Color { classification.color }
    var label: String { classification.label }
}

// MARK: - MetricRangeSpec

struct MetricRangeSpec {
    let bands: [RangeBand]

    var displayMin: Float { bands.first?.from ?? 0 }
    var displayMax: Float { bands.last?.to  ?? 100 }
    var totalRange: Float { displayMax - displayMin }

    var normalBand: RangeBand? { bands.first { $0.classification == .normal } }

    /// Normalised position [0, 1] for `value` on the bar.
    func t(for value: Float) -> Float {
        guard totalRange > 0 else { return 0 }
        return max(0, min(1, (value - displayMin) / totalRange))
    }

    /// How far the value is outside the Normal band, if at all.
    func deltaToNormal(value: Float) -> (amount: Float, tooHigh: Bool)? {
        guard let nb = normalBand else { return nil }
        if value < nb.from { return (nb.from - value, false) }
        if value > nb.to   { return (value - nb.to,   true)  }
        return nil
    }

    func activeBand(for value: Float) -> RangeBand? {
        bands.first { $0.from <= value && value < $0.to }
            ?? (value >= displayMax ? bands.last : bands.first)
    }

    // MARK: Per-metric specs

    static func spec(for metric: BodyMetric, isMale: Bool) -> MetricRangeSpec? {
        switch metric {
        case .bmi:
            return make([(.low, 12, 18.5), (.normal, 18.5, 25), (.high, 25, 30), (.veryHigh, 30, 42)])
        case .bodyFat:
            return isMale
                ? make([(.low, 0, 6),  (.normal, 6, 20),   (.high, 20, 25), (.veryHigh, 25, 38)])
                : make([(.low, 0, 14), (.normal, 14, 28),  (.high, 28, 33), (.veryHigh, 33, 50)])
        case .muscle:
            return isMale
                ? make([(.low, 20, 30), (.normal, 30, 44), (.high, 44, 55), (.veryHigh, 55, 65)])
                : make([(.low, 15, 22), (.normal, 22, 35), (.high, 35, 44), (.veryHigh, 44, 58)])
        case .water:
            return make([(.low, 35, 45), (.normal, 45, 65), (.high, 65, 75), (.veryHigh, 75, 85)])
        case .skeletalMuscle:
            return isMale
                ? make([(.low, 25, 33), (.normal, 33, 46), (.high, 46, 56)])
                : make([(.low, 18, 25), (.normal, 25, 38), (.high, 38, 48)])
        case .subcutaneousFat:
            return isMale
                ? make([(.low, 0, 5),  (.normal, 5, 18),   (.high, 18, 23), (.veryHigh, 23, 38)])
                : make([(.low, 0, 12), (.normal, 12, 25),  (.high, 25, 30), (.veryHigh, 30, 45)])
        case .visceralFat:
            return make([(.normal, 0, 7), (.high, 7, 12), (.veryHigh, 12, 20)])
        case .obesityDegree:
            return make([(.low, -10, 0), (.normal, 0, 5), (.high, 5, 10), (.veryHigh, 10, 20)])
        case .healthScore:
            return make([(.low, 0, 65), (.high, 65, 85), (.normal, 85, 100)])
        default:
            return nil
        }
    }

    private static func make(_ tuples: [(Classification, Float, Float)]) -> MetricRangeSpec {
        MetricRangeSpec(bands: tuples.map { RangeBand(classification: $0.0, from: $0.1, to: $0.2) })
    }
}

// MARK: - MetricRangeBar

struct MetricRangeBar: View {
    let value: Float
    let spec: MetricRangeSpec
    let unit: String
    let decimals: Int
    var goalValue: Float? = nil

    private let barHeight: CGFloat = 10
    private let dotSize:   CGFloat = 18

    private var active: RangeBand? { spec.activeBand(for: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // Segmented color bar
                    HStack(spacing: 0) {
                        ForEach(spec.bands) { band in
                            band.color
                                .frame(
                                    width: w * CGFloat((band.to - band.from) / spec.totalRange),
                                    height: barHeight
                                )
                        }
                    }
                    .clipShape(Capsule())
                    .offset(y: (dotSize - barHeight) / 2)

                    // Goal tick — white vertical capsule at the goal position
                    if let gv = goalValue {
                        let gt = CGFloat(spec.t(for: gv))
                        Capsule()
                            .fill(.white.opacity(0.9))
                            .frame(width: 2.5, height: barHeight + 4)
                            .shadow(color: .black.opacity(0.25), radius: 2)
                            .offset(x: gt * w - 1.25, y: (dotSize - barHeight) / 2 - 2)
                    }

                    // Band labels centered over each segment
                    ForEach(spec.bands) { band in
                        let center = CGFloat((band.from + band.to) / 2 - spec.displayMin) / CGFloat(spec.totalRange)
                        Text(band.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(band.color.opacity(0.9))
                            .position(x: center * w, y: dotSize + 10)
                    }

                    // Value dot
                    let t = CGFloat(spec.t(for: value))
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .overlay(Circle().stroke(active?.color ?? DS.Palette.secondaryLabel, lineWidth: 2.5))
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: t * w - dotSize / 2)
                }
            }
            .frame(height: dotSize + 20)

            // Delta or in-range message
            deltaRow
        }
    }

    private var deltaRow: some View {
        Group {
            if let (amount, tooHigh) = spec.deltaToNormal(value: value),
               let nb = spec.normalBand {
                let bandColor  = active?.color ?? DS.Palette.bodyFat
                let amtStr     = fmt(amount)
                let goalStr    = tooHigh ? fmt(nb.to) : fmt(nb.from)
                let normalStr  = "\(fmt(nb.from))–\(fmt(nb.to))\(unitStr)"
                let verb       = tooHigh ? "Decrease" : "Increase"
                let icon       = tooHigh ? "arrow.down" : "arrow.up"

                hintCard(color: bandColor) {
                    HStack(spacing: DS.Space.m) {
                        iconPill(systemName: icon, color: bandColor)
                        VStack(alignment: .leading, spacing: 3) {
                            (Text("\(verb) by ")
                             + Text("\(amtStr)\(unitStr)").foregroundStyle(bandColor).bold()
                             + Text(" to reach normal"))
                                .font(DS.Typeface.bodyMedium)
                                .foregroundStyle(DS.Palette.label)
                            Text("Normal range: \(normalStr) · Your goal: \(goalStr)\(unitStr)")
                                .font(DS.Typeface.caption)
                                .foregroundStyle(DS.Palette.secondaryLabel)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else if let nb = spec.normalBand {
                hintCard(color: DS.Palette.positive) {
                    HStack(spacing: DS.Space.m) {
                        iconPill(systemName: "checkmark", color: DS.Palette.positive)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Within normal range")
                                .font(DS.Typeface.bodyMedium)
                                .foregroundStyle(DS.Palette.label)
                            Text("Normal range: \(fmt(nb.from))–\(fmt(nb.to))\(unitStr)")
                                .font(DS.Typeface.caption)
                                .foregroundStyle(DS.Palette.secondaryLabel)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Sub-components

    private func hintCard<Content: View>(color: Color, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(DS.Space.m)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func iconPill(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private var unitStr: String { unit.isEmpty ? "" : unit }

    private func fmt(_ v: Float) -> String {
        String(format: "%.\(decimals)f", v)
    }
}

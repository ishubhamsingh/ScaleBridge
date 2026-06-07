import SwiftUI

// MARK: - WeighInFlowView
//
// Full-screen modal that covers the Today tab during a weigh-in session.
// Three states driven by the shared ScaleBLEManager:
//   scanning / connecting  → ScanningPhase  ("Looking for your scale…")
//   connected / reading    → ReadingPhase   ("Hold still…")
//   done                   → DonePhase      ("All done.")
//
// HomeView injects the BLE manager via .environmentObject(ble).
// Measurement persistence happens in HomeView via onChange(of: ble.status);
// this view is pure presentation.

struct WeighInFlowView: View {
    @EnvironmentObject private var ble: ScaleBLEManager

    let profile: UserProfile?
    let previousWeighIn: WeighIn?   // for delta display on Done screen
    var onDone: () -> Void
    var onWeighAgain: () -> Void

    // MARK: Gradient — dark indigo → indigo-purple

    private let gradientTop    = Color(red: 0.29, green: 0.28, blue: 0.80)
    private let gradientBottom = Color(red: 0.43, green: 0.33, blue: 0.80)

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            // Full-bleed gradient
            LinearGradient(
                colors: [gradientTop, gradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHandle
                flowHeader
                Spacer()
                phaseContent
                Spacer()
                bottomArea
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Sheet handle + header

    private var sheetHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, DS.Space.m)
    }

    private var flowHeader: some View {
        HStack {
            Text(headerLabel.uppercased())
                .font(DS.Typeface.dateCaps)
                .tracking(0.04 * 13)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            if case .done = ble.status {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                    Text("Synced")
                        .font(DS.Typeface.footnote)
                }
                .foregroundStyle(.white.opacity(0.85))
            } else {
                Button("Cancel") {
                    ble.stop()
                    onDone()
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s)
                .background(.white.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, DS.Space.xl)
    }

    private var headerLabel: String {
        switch ble.status {
        case .done: return "Weighed \(profile?.name ?? "you")"
        default:    return "Weighing for \(profile?.name ?? "you")"
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private var phaseContent: some View {
        switch ble.status {
        case .scanning, .connecting:
            ScanningPhase()
        case .connected, .reading:
            ReadingPhase(weightKg: ble.lastMeasurement?.weightKg)
        case .done:
            DonePhase(
                measurement: ble.lastMeasurement,
                previousWeighIn: previousWeighIn,
                profile: profile
            )
        case .idle:
            ScanningPhase()     // briefly visible before scanning starts
        case .error(let msg):
            errorPhase(msg)
        }
    }

    private func errorPhase(_ message: String) -> some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text("Something went wrong")
                .font(DS.Typeface.title2)
                .foregroundStyle(.white)
            Text(message)
                .font(DS.Typeface.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.xxl)
    }

    // MARK: - Bottom area

    @ViewBuilder
    private var bottomArea: some View {
        if case .done = ble.status {
            // Done: two full-width buttons
            VStack(spacing: DS.Space.m) {
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Palette.weight)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(.white, in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
                }
                Button(action: onWeighAgain) {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                        Text("Weigh in again")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 47)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
                }
            }
            .padding(.horizontal, DS.Space.xl)
        } else {
            // Scanning / Reading: status pill
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: statusIcon)
                .font(.system(size: 13, weight: .medium))
            Text(statusText)
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.m)
        .background(.white.opacity(0.15), in: Capsule())
        .padding(.horizontal, DS.Space.xl)
    }

    private var statusIcon: String {
        switch ble.status {
        case .scanning: return "wave.3.right"
        case .connecting: return "link"
        case .connected, .reading: return "dot.radiowaves.left.and.right"
        default: return "bluetooth"
        }
    }

    private var statusText: String {
        switch ble.status {
        case .scanning:   return "Bluetooth · Scanning"
        case .connecting: return "Connecting…"
        case .connected:  return "Connected"
        case .reading:    return "Stabilizing reading…"
        default:          return "Bluetooth · Scanning"
        }
    }
}

// MARK: - Scanning Phase

private struct ScanningPhase: View {
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: DS.Space.xxl) {
            // Concentric pulse rings + icon
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(.white.opacity(pulsing ? 0.08 : 0.18), lineWidth: 1)
                        .frame(width: CGFloat(140 + i * 55))
                        .scaleEffect(pulsing ? 1.06 : 0.96)
                        .animation(
                            .easeInOut(duration: 1.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.22),
                            value: pulsing
                        )
                }
                // Center circle
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 90, height: 90)
                Image(systemName: "scalemass")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 260, height: 260)

            VStack(spacing: DS.Space.m) {
                Text("Looking for your scale…")
                    .font(DS.Typeface.title2)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Make sure your scale is on and within\nrange of your iPhone.")
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - Reading Phase

private struct ReadingPhase: View {
    let weightKg: Float?

    var body: some View {
        VStack(spacing: DS.Space.xxl) {
            // Ring dial with live weight
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 210, height: 210)
                VStack(spacing: 4) {
                    Text("LIVE")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.08 * 12)
                        .foregroundStyle(.white.opacity(0.60))
                    if let w = weightKg {
                        Text(String(format: "%.1f", w))
                            .font(.system(size: 72, weight: .bold).monospacedDigit())
                            .tracking(-0.035 * 72)
                            .foregroundStyle(.white)
                    } else {
                        Text("—")
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text("kg")
                        .font(DS.Typeface.title3)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            VStack(spacing: DS.Space.m) {
                Text("Hold still…")
                    .font(DS.Typeface.title2)
                    .foregroundStyle(.white)
                Text("Your body composition is calculated\nthe moment your weight is stable.")
                    .font(DS.Typeface.subheadline)
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Done Phase

private struct DonePhase: View {
    let measurement: ScaleMeasurement?
    let previousWeighIn: WeighIn?
    let profile: UserProfile?

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            // Checkmark
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // "All done." + hero weight
            VStack(spacing: DS.Space.s) {
                Text("All done.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                if let m = measurement {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", m.weightKg))
                            .font(.system(size: 72, weight: .bold).monospacedDigit())
                            .tracking(-0.035 * 72)
                            .foregroundStyle(.white)
                        Text("kg")
                            .font(DS.Typeface.title3)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    // Delta
                    if let prev = previousWeighIn {
                        let delta = m.weightKg - prev.weightKg
                        HStack(spacing: 4) {
                            Image(systemName: delta <= 0 ? "chevron.down" : "chevron.up")
                                .font(.system(size: 11, weight: .bold))
                            Text(String(format: "%.1f kg from %@", abs(delta), daysSince(prev.date)))
                                .font(DS.Typeface.subheadline)
                        }
                        .foregroundStyle(.white.opacity(0.80))
                    }
                }
            }

            // Results card
            if let m = measurement {
                metricsCard(m)
            }
        }
        .padding(.horizontal, DS.Space.xl)
    }

    private func metricsCard(_ m: ScaleMeasurement) -> some View {
        VStack(spacing: 0) {
            metricRow(metric: .bodyFat, value: m.fatPercent.map { String(format: "%.1f%%", $0) })
            Divider().background(.black.opacity(0.08))
            metricRow(metric: .muscle, value: m.musclePercent.map { String(format: "%.1f%%", $0) })
            Divider().background(.black.opacity(0.08))
            metricRow(metric: .water, value: m.waterPercent.map { String(format: "%.1f%%", $0) })
            Divider().background(.black.opacity(0.08))
            bmiRow(bmi: m.bmi)
        }
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricRow(metric: BodyMetric, value: String?) -> some View {
        HStack {
            Image(systemName: metric.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(metric.color)
                .frame(width: 24)
            Text(metric.label)
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
            Spacer()
            Text(value ?? "—")
                .font(DS.Typeface.bodyMedium.monospacedDigit())
                .foregroundStyle(DS.Palette.label)
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: 46)
    }

    // BMI row: classification as sublabel on the left (value-columns rule)
    private func bmiRow(bmi: Float?) -> some View {
        HStack {
            Image(systemName: BodyMetric.bmi.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BodyMetric.bmi.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("BMI")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.label)
                if let b = bmi, let cl = HomeClassify.classify(.bmi, value: b, isMale: true) {
                    Text(cl.label)
                        .font(DS.Typeface.caption)
                        .foregroundStyle(cl.color)
                }
            }
            Spacer()
            Text(bmi.map { String(format: "%.1f", $0) } ?? "—")
                .font(DS.Typeface.bodyMedium.monospacedDigit())
                .foregroundStyle(DS.Palette.label)
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: 59)
    }

    private func daysSince(_ date: Date) -> String {
        let d = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if d == 0 { return "today" }
        if d == 1 { return "yesterday" }
        return "\(d) days ago"
    }
}

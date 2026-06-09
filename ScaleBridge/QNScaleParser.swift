import Foundation
import CoreBluetooth

// MARK: - Trisa body-composition formulas
//
// Ported verbatim from openScale's TrisaBodyAnalyzeLib (GPLv3). These turn
// (weight, impedance, age, height, sex) into fat/water/muscle/bone percentages.
// openScale's QN handler uses exactly these, so your numbers will match openScale's
// (they won't match HealthifyMe to the decimal — different proprietary model — but
// they're consistent and trend-accurate, which is what matters for tracking).

struct TrisaBodyComposition {
    let isMale: Bool
    let ageYears: Int
    let heightCm: Float

    func bmi(_ weightKg: Float) -> Float { weightKg * 1e4 / (heightCm * heightCm) }

    func water(_ weightKg: Float, _ z: Float) -> Float {
        let b = bmi(weightKg)
        return isMale
            ? 87.51  + (-1.162 * b - 0.00813 * z + 0.07594 * Float(ageYears))
            : 77.721 + (-1.148 * b - 0.00573 * z + 0.06448 * Float(ageYears))
    }
    func fat(_ weightKg: Float, _ z: Float) -> Float {
        let b = bmi(weightKg)
        return isMale
            ? b * (1.479 + 4.4e-4   * z) + 0.1 * Float(ageYears) - 21.764
            : b * (1.506 + 3.908e-4 * z) + 0.1 * Float(ageYears) - 12.834
    }
    func muscle(_ weightKg: Float, _ z: Float) -> Float {
        let b = bmi(weightKg)
        return isMale
            ? 74.627 + (-0.811 * b - 0.00565 * z - 0.367 * Float(ageYears))
            : 57.0   + (-0.694 * b - 0.00344 * z - 0.255 * Float(ageYears))
    }
    func bone(_ weightKg: Float, _ z: Float) -> Float {
        let b = bmi(weightKg)
        return isMale
            ? 7.829 + (-0.0855 * b - 5.92e-4 * z - 0.0389 * Float(ageYears))
            : 7.98  + (-0.0973 * b - 4.84e-4 * z - 0.036  * Float(ageYears))
    }

    // MARK: - Derived / estimated metrics

    /// Basal Metabolic Rate in kcal/day (Katch-McArdle).
    /// LBM-based, so extra fat mass doesn't inflate the result. Matches OG app formula.
    func bmr(_ weightKg: Float, _ fatPct: Float) -> Float {
        let lbm = weightKg * (1 - fatPct / 100)
        return 370 + 21.6 * lbm
    }

    /// Ideal body weight (Lorentz formula) in kg.
    func standardWeight() -> Float {
        isMale
            ? heightCm - 100 - (heightCm - 150) / 4
            : heightCm - 100 - (heightCm - 150) / 2
    }

    /// Metabolic age: the age at which a standard-weight person would have your lean-mass-based BMR.
    /// Uses Katch-McArdle (LBM-based) so extra fat mass doesn't artificially inflate the result.
    /// At ideal body composition metabolic age ≈ actual age; high fat → older, high muscle → younger.
    func metabolicAge(_ weightKg: Float, _ fatPct: Float) -> Float {
        let lbm = weightKg * (1 - fatPct / 100)
        let lbmBMR: Float = 370 + 21.6 * lbm          // Katch-McArdle
        let sw = standardWeight()
        let offset: Float = isMale ? 5 : -161
        // Solve: 10*sw + 6.25*h - 5*age + offset = lbmBMR
        let age = (10 * sw + 6.25 * heightCm + offset - lbmBMR) / 5
        return max(5, age)
    }

    /// Protein as % of body weight (~20.4% of lean mass).
    func proteinPercent(_ fatPct: Float) -> Float {
        (100 - fatPct) * 0.204
    }

    /// Skeletal muscle is ~67.9% of total muscle mass percentage.
    func skeletalMusclePercent(_ musclePct: Float) -> Float {
        musclePct * 0.679
    }

    /// Subcutaneous fat is ~90% of total body fat percentage.
    func subcutaneousFatPercent(_ fatPct: Float) -> Float {
        fatPct * 0.9
    }

    /// Visceral fat estimated from body fat % and BMI.
    func visceralFatPercent(_ weightKg: Float, _ fatPct: Float) -> Float {
        let b = bmi(weightKg)
        return isMale ? fatPct * b / 82 : fatPct * b / 96
    }

    /// Muscle mass in kg.
    func muscleMassKg(_ weightKg: Float, _ musclePct: Float) -> Float {
        weightKg * musclePct / 100
    }

    /// Mineral salt mass in kg (~1.6% of lean mass).
    func mineralSaltKg(_ leanKg: Float) -> Float {
        leanKg * 0.016
    }

    /// Target weight at ideal body-fat percentage (male 21%, female 28%).
    func bestVisualWeight(_ leanKg: Float) -> Float {
        let idealFatFraction: Float = isMale ? 0.21 : 0.28
        return leanKg / (1 - idealFatFraction)
    }

    /// How much weight to gain/lose (kg) to reach standard weight. Negative = need to lose.
    func weightControl(_ weightKg: Float) -> Float {
        standardWeight() - weightKg
    }

    /// How much fat mass (kg) to lose to reach ideal fat% at standard weight. Negative = need to lose.
    func fatControl(_ weightKg: Float, _ fatPct: Float) -> Float {
        let idealFatFraction: Float = isMale ? 0.15 : 0.22
        let currentFatKg = weightKg * fatPct / 100
        return standardWeight() * idealFatFraction - currentFatKg
    }

    /// Lean mass delta (kg) vs ideal lean mass at standard weight. Negative = need to gain muscle.
    func muscleControl(_ weightKg: Float, _ fatPct: Float) -> Float {
        let idealFatFraction: Float = isMale ? 0.15 : 0.22
        let leanKg = weightKg * (1 - fatPct / 100)
        let idealLeanKg = standardWeight() * (1 - idealFatFraction)
        return idealLeanKg - leanKg
    }

    /// Excess body fat above ideal (male 16.5%, female 24%). Near 0 = at ideal fat level.
    func obesityDegree(_ fatPct: Float) -> Float {
        fatPct - (isMale ? 16.5 : 24.0)
    }

    /// Composite health score 0–100 derived from BMI and body fat deviation from ideal.
    func healthScore(_ weightKg: Float, _ fatPct: Float) -> Float {
        let idealFat: Float = isMale ? 16.5 : 24.0
        let score = 100 - abs(bmi(weightKg) - 22.5) * 1.5 - abs(fatPct - idealFat) * 0.9
        return max(0, min(100, score))
    }
}

// MARK: - QN / Yolanda scale parser
//
// Port of openScale's QNHandler (GPLv3). Handshake summary:
//   1. Subscribe to the notify characteristic (FFE1 type-1, or FFF1 type-2).
//   2. Wait for a 0x12 frame -> tells us the weight scale factor (/100 or /10)
//      and the "protocol type" byte we must echo back.
//   3. Send unit config (0x13) + time sync; scale ACKs (0x14) -> we reply 0x20.
//   4. 0x10 frames stream live weight; when the stable flag is set we publish.
//
// Frame layout for 0x10 (original format): bytes[3,4]=weight BE, byte[5]=stable,
// bytes[6,7]=resistance r1, bytes[8,9]=r2. ES-30M variant shifts these by one.

final class QNScaleParser: ScaleParser {

    // Type 1 service FFE0
    private let SVC_T1 = uuid16(0xFFE0)
    private let CHR_T1_NOTIFY  = uuid16(0xFFE1)
    private let CHR_T1_WRITE   = uuid16(0xFFE3)
    private let CHR_T1_TIME    = uuid16(0xFFE4)
    // Type 2 service FFF0
    private let SVC_T2 = uuid16(0xFFF0)
    private let CHR_T2_NOTIFY  = uuid16(0xFFF1)
    private let CHR_T2_WRITE   = uuid16(0xFFF2)

    // QN epoch: seconds since 2000-01-01 00:00:00 UTC
    private let SCALE_EPOCH_OFFSET: TimeInterval = 946_702_800

    var serviceUUIDs: [CBUUID] { [SVC_T1, SVC_T2] }
    var notifyCharacteristics: [CBUUID] { [CHR_T1_NOTIFY, CHR_T2_NOTIFY] }
    var onMeasurement: ((ScaleMeasurement) -> Void)?

    private var weightScaleFactor: Float = 100
    private var seenProtocolType: UInt8 = 0
    private var hasReceivedProtocolType = false
    private var hasPublished = false
    private weak var transport: ScaleTransport?

    func onConnected(user: ScaleUser, transport: ScaleTransport) {
        self.transport = transport
        hasPublished = false
        weightScaleFactor = 100
        seenProtocolType = 0
        hasReceivedProtocolType = false
        // Subscribe to whichever notify characteristics exist; missing ones are ignored.
        transport.setNotify(service: SVC_T1, characteristic: CHR_T1_NOTIFY)
        transport.setNotify(service: SVC_T2, characteristic: CHR_T2_NOTIFY)
        transport.log("QN: connected, waiting for 0x12 frame. Step on the scale.")
    }

    func onNotification(characteristic: CBUUID, data: Data, user: ScaleUser, transport: ScaleTransport) {
        let b = [UInt8](data)
        guard b.count >= 3 else { return }

        if seenProtocolType == 0 { seenProtocolType = b[2] }

        switch b[0] {
        case 0x12: handleScaleInfo(b, user: user)
        case 0x10: handleLiveWeight(b, user: user)
        case 0x14: sendTimeSync()
        default:   transport.log("QN: opcode 0x\(String(b[0], radix: 16)) \(Bytes.hexPreview(data))")
        }
    }

    // 0x12: byte[10]==1 -> /100, else /10. Then push config.
    private func handleScaleInfo(_ b: [UInt8], user: ScaleUser) {
        guard b.count > 10 else { return }
        weightScaleFactor = (b[10] == 1) ? 100 : 10
        transport?.log("QN: weightScaleFactor=\(weightScaleFactor)")
        if !hasReceivedProtocolType {
            hasReceivedProtocolType = true
            sendConfiguration(user: user)
        }
    }

    // 0x10: live/stable weight + resistances.
    private func handleLiveWeight(_ b: [UInt8], user: ScaleUser) {
        guard b.count >= 10, !hasPublished else { return }

        // ES-30M variant detection: byte[4] is a small stable flag and factor is /10.
        let isES30M = (Int(b[4]) <= 0x02) && weightScaleFactor == 10
        let stable: Bool, raw: Float, r1: Float

        if isES30M, b.count >= 11 {
            stable = b[4] == 0x01 || b[4] == 0x02
            raw = Float(Bytes.u16be(b[5], b[6]))
            r1  = Float(Bytes.u16be(b[7], b[8]))
        } else {
            stable = b[5] == 1
            raw = Float(Bytes.u16be(b[3], b[4]))
            r1  = Float(Bytes.u16be(b[6], b[7]))
        }
        guard stable else { return }

        var weightKg = raw / weightScaleFactor
        if weightKg <= 5 || weightKg >= 250 { weightKg /= 10 }   // heuristic fallback
        guard weightKg > 0 else { return }

        publish(weightKg: weightKg, r1: r1, user: user)
        hasPublished = true
    }

    private func publish(weightKg: Float, r1: Float, user: ScaleUser) {
        // QN/Yolanda scales output raw bioelectrical impedance in ohms (typically 400–600 Ω).
        // Pass it directly — the Trisa normalization (z = 0.3*(r1-400)) was for Trisa hardware
        // and compresses QN values by ~18×, causing fat% to be ~6% too low.
        let z: Float = r1
        let lib = TrisaBodyComposition(isMale: user.isMale, ageYears: user.age, heightCm: user.heightCm)

        let fatPct    = lib.fat(weightKg, z)
        let musclePct = lib.muscle(weightKg, z)
        let leanKg    = weightKg * (1 - fatPct / 100)

        var m = ScaleMeasurement(weightKg: weightKg, impedance: r1)
        m.bmi           = lib.bmi(weightKg)
        m.fatPercent    = fatPct
        m.waterPercent  = lib.water(weightKg, z)
        m.musclePercent = musclePct
        m.bonePercent   = lib.bone(weightKg, z)

        m.bmr                    = lib.bmr(weightKg, fatPct)
        m.metabolicAge           = lib.metabolicAge(weightKg, fatPct)
        m.proteinPercent         = lib.proteinPercent(fatPct)
        m.skeletalMusclePercent  = lib.skeletalMusclePercent(musclePct)
        m.subcutaneousFatPercent = lib.subcutaneousFatPercent(fatPct)
        m.visceralFatPercent     = lib.visceralFatPercent(weightKg, fatPct)
        m.muscleMassKg           = lib.muscleMassKg(weightKg, musclePct)
        m.mineralSaltKg          = lib.mineralSaltKg(leanKg)
        m.bestVisualWeightKg     = lib.bestVisualWeight(leanKg)
        m.standardWeightKg       = lib.standardWeight()
        m.weightControlKg        = lib.weightControl(weightKg)
        m.fatControlKg           = lib.fatControl(weightKg, fatPct)
        m.muscleControlKg        = lib.muscleControl(weightKg, fatPct)
        m.obesityDegree          = lib.obesityDegree(fatPct)
        m.healthScore            = lib.healthScore(weightKg, fatPct)

        transport?.log("QN: publish weight=\(weightKg)kg r1=\(r1) z=\(z) bmr=\(m.bmr ?? 0) metAge=\(m.metabolicAge ?? 0)")
        onMeasurement?(m)
    }

    // 0x13 unit config + time write, sent after 0x12.
    private func sendConfiguration(user: ScaleUser) {
        let unitByte: UInt8 = user.usePounds ? 0x02 : 0x01
        var cfg: [UInt8] = [0x13, 0x09, seenProtocolType, unitByte, 0x10, 0x00, 0x00, 0x00, 0x00]
        cfg[cfg.count - 1] = Bytes.checksum(cfg, from: 0, throughInclusive: cfg.count - 1)
        writeToScale(cfg)

        let t = scaleSeconds()
        let time: [UInt8] = [0x02, UInt8(t & 0xFF), UInt8((t >> 8) & 0xFF),
                             UInt8((t >> 16) & 0xFF), UInt8((t >> 24) & 0xFF)]
        transport?.write(service: SVC_T1, characteristic: CHR_T1_TIME, data: Data(time), withResponse: true)
        transport?.write(service: SVC_T2, characteristic: CHR_T2_WRITE, data: Data(time), withResponse: true)
    }

    private func sendTimeSync() {
        let t = scaleSeconds()
        var msg: [UInt8] = [0x20, 0x08, seenProtocolType,
                            UInt8(t & 0xFF), UInt8((t >> 8) & 0xFF),
                            UInt8((t >> 16) & 0xFF), UInt8((t >> 24) & 0xFF), 0x00]
        msg[msg.count - 1] = Bytes.checksum(msg, from: 0, throughInclusive: msg.count - 2)
        writeToScale(msg)
    }

    private func scaleSeconds() -> UInt32 {
        UInt32(Date().timeIntervalSince1970 - SCALE_EPOCH_OFFSET)
    }

    /// Write to whichever config characteristic the connected scale exposes.
    private func writeToScale(_ bytes: [UInt8]) {
        transport?.write(service: SVC_T1, characteristic: CHR_T1_WRITE, data: Data(bytes), withResponse: true)
        transport?.write(service: SVC_T2, characteristic: CHR_T2_WRITE, data: Data(bytes), withResponse: true)
    }
}

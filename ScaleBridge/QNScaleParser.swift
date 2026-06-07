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
        // openScale's impedance normalization for the Trisa model.
        let z: Float = r1 < 410 ? 3.0 : 0.3 * (r1 - 400)
        let lib = TrisaBodyComposition(isMale: user.isMale, ageYears: user.age, heightCm: user.heightCm)

        var m = ScaleMeasurement(weightKg: weightKg, impedance: r1)
        m.bmi = lib.bmi(weightKg)
        m.fatPercent = lib.fat(weightKg, z)
        m.waterPercent = lib.water(weightKg, z)
        m.musclePercent = lib.muscle(weightKg, z)
        m.bonePercent = lib.bone(weightKg, z)

        transport?.log("QN: publish weight=\(weightKg)kg r1=\(r1) z=\(z)")
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

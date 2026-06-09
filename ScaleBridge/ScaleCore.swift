import Foundation
import CoreBluetooth

// MARK: - Domain models

/// The user profile needed to compute body composition from impedance.
struct ScaleUser {
    var isMale: Bool
    var age: Int
    var heightCm: Float
    /// false = kilograms, true = pounds. The QN scale only needs this to configure its display.
    var usePounds: Bool = false
}

/// One finished reading. Weight + impedance come off the wire; the rest are computed.
struct ScaleMeasurement {
    var date: Date = Date()
    var weightKg: Float
    var impedance: Float          // raw resistance from the scale (ohms-ish, vendor units)
    var fatPercent: Float?
    var waterPercent: Float?
    var musclePercent: Float?
    var bonePercent: Float?

    var bmi: Float?

    // MARK: Derived / estimated metrics (set by parser alongside the Trisa fields)
    var bmr: Float?                    // kcal/day
    var metabolicAge: Float?           // years
    var proteinPercent: Float?         // %
    var skeletalMusclePercent: Float?  // %
    var subcutaneousFatPercent: Float? // %
    var visceralFatPercent: Float?     // %
    var muscleMassKg: Float?           // kg
    var mineralSaltKg: Float?          // kg
    var bestVisualWeightKg: Float?     // kg
    var standardWeightKg: Float?       // kg
    var weightControlKg: Float?        // kg (negative = need to lose)
    var fatControlKg: Float?           // kg (negative = need to lose fat)
    var muscleControlKg: Float?        // kg (negative = need to gain muscle)
    var obesityDegree: Float?          // % above ideal fat
    var healthScore: Float?            // 0–100

    /// Lean body mass in kg, derived from weight and fat %.
    var leanMassKg: Float? {
        guard let f = fatPercent else { return nil }
        return weightKg * (1 - f / 100)
    }
    var fatMassKg: Float? {
        guard let f = fatPercent else { return nil }
        return weightKg * (f / 100)
    }
}

// MARK: - Transport abstraction
//
// The parser never touches CoreBluetooth directly. The BLE manager implements this
// protocol and hands it to the parser, mirroring openScale's handler/adapter split.
// That keeps the protocol logic portable and unit-testable.

protocol ScaleTransport: AnyObject {
    func write(service: CBUUID, characteristic: CBUUID, data: Data, withResponse: Bool)
    func setNotify(service: CBUUID, characteristic: CBUUID)
    func log(_ message: String)
}

// MARK: - Parser abstraction
//
// Implement this once per scale protocol. Today: QNScaleParser.
// To support a different openScale handler, write a new conformer and swap it
// into ScaleBLEManager — the BLE plumbing and HealthKit sink stay identical.

protocol ScaleParser: AnyObject {
    /// Services to scan for / discover on connect.
    var serviceUUIDs: [CBUUID] { get }
    /// Notify/indicate characteristics to subscribe to once connected.
    var notifyCharacteristics: [CBUUID] { get }

    /// Called once the peripheral is connected and characteristics are discovered.
    func onConnected(user: ScaleUser, transport: ScaleTransport)
    /// Called for every notification on a subscribed characteristic.
    func onNotification(characteristic: CBUUID, data: Data, user: ScaleUser, transport: ScaleTransport)

    /// Set by the manager; the parser calls this when it has a final, stable reading.
    var onMeasurement: ((ScaleMeasurement) -> Void)? { get set }
}

// MARK: - Byte helpers (shared by parsers)

enum Bytes {
    static func u16be(_ a: UInt8, _ b: UInt8) -> Int { (Int(a) << 8) | Int(b) }
    static func u16le(_ a: UInt8, _ b: UInt8) -> Int { Int(a) | (Int(b) << 8) }
    static func u32le(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
        UInt32(a) | (UInt32(b) << 8) | (UInt32(c) << 16) | (UInt32(d) << 24)
    }
    /// Sum-of-bytes checksum, low byte (matches QN's scheme).
    static func checksum(_ bytes: [UInt8], from: Int, throughInclusive: Int) -> UInt8 {
        var s = 0
        for i in from...throughInclusive { s = (s + Int(bytes[i])) & 0xFF }
        return UInt8(s)
    }
    static func hexPreview(_ data: Data, _ max: Int = 24) -> String {
        data.prefix(max).map { String(format: "%02x", $0) }.joined()
    }
}

/// Build a 16-bit Bluetooth SIG UUID (e.g. 0xFFE0) as a full CBUUID.
func uuid16(_ short: UInt16) -> CBUUID {
    CBUUID(string: String(format: "%04X", short))
}

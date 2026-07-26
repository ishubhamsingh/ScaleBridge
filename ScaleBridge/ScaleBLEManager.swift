import Foundation
import CoreBluetooth
import Combine
import AudioToolbox
import UIKit

/// Frame-level diagnostic log, kept outside the BLE manager so Settings can read it
/// without owning the manager (they live in different tabs).
///
/// Every notification is logged as hex here — this is what identifies a protocol
/// problem from a real reading, and it's the only record of what the scale actually
/// sent once a session ends.
@MainActor
@Observable
final class ScaleDiagnosticsLog {
    static let shared = ScaleDiagnosticsLog()

    private static let maxLines = 300
    private(set) var lines: [String] = []

    func append(_ message: String) {
        let stamped = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)"
        lines.append(stamped)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        print(stamped)
    }

    func clear() { lines.removeAll() }

    var exportText: String { lines.joined(separator: "\n") }
}

/// Owns CoreBluetooth, drives the parser, and surfaces state to SwiftUI.
/// Also acts as the parser's `ScaleTransport`.
@MainActor
final class ScaleBLEManager: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle, scanning, connecting, connected, reading, done, error(String)
    }

    @Published var status: Status = .idle
    @Published var lastMeasurement: ScaleMeasurement?
    /// The advertised name + service UUIDs of the first matching device we see.
    /// THIS is your diagnostic: read it to confirm which openScale handler applies.
    @Published var discoveredName: String = ""
    @Published var discoveredServices: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]

    private let parser: ScaleParser
    /// The user whose body-composition formulas are applied to the next reading.
    /// Set this to the selected profile's `scaleUser` before calling `start()`.
    var user: ScaleUser

    init(parser: ScaleParser = QNScaleParser(), user: ScaleUser) {
        self.parser = parser
        self.user = user
        super.init()
        self.parser.onMeasurement = { [weak self] m in
            Task { @MainActor in self?.handleMeasurement(m) }
        }
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        guard central.state == .poweredOn else {
            status = .error("Bluetooth not ready")
            return
        }
        // Drop any connection left over from a previous weigh-in. A stale link means
        // the parser never sees `onConnected`, so its per-session state (including the
        // publish latch) is never reset and notifications resume mid-stream.
        teardownConnection()
        lastMeasurement = nil
        status = .scanning
        log("Scanning…")
        // Pass nil to discover ALL peripherals while diagnosing; once you've confirmed
        // the protocol, narrow to `parser.serviceUUIDs` for faster, battery-friendly scans.
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func stop() {
        central.stopScan()
        teardownConnection()
        status = .idle
    }

    /// Drops the peripheral without touching `status` — callers own the state machine.
    private func teardownConnection() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        characteristics = [:]
    }

    private func handleMeasurement(_ m: ScaleMeasurement) {
        guard status == .reading else { return }
        lastMeasurement = m
        status = .done
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1057)
        if let fat = m.fatPercent {
            log(String(format: "Reading: %.2f kg, fat %.1f%%", m.weightKg, fat))
        } else {
            log(String(format: "Reading: %.2f kg (weight only — no impedance)", m.weightKg))
        }
        central.stopScan()
        // Release the scale so the next weigh-in starts a fresh session rather than
        // resuming on a half-finished one.
        teardownConnection()
        // HealthKit write + SwiftData persistence are handled in ContentView
        // via .onChange(of: status) so they have access to the active UserProfile
        // and the SwiftData ModelContext.
    }

    func log(_ s: String) {
        ScaleDiagnosticsLog.shared.append(s)
    }
}

// MARK: - ScaleTransport

extension ScaleBLEManager: ScaleTransport {
    func write(service: CBUUID, characteristic: CBUUID, data: Data, withResponse: Bool) {
        guard let c = characteristics[characteristic] else { return }
        peripheral?.writeValue(data, for: c, type: withResponse ? .withResponse : .withoutResponse)
    }
    func setNotify(service: CBUUID, characteristic: CBUUID) {
        guard let c = characteristics[characteristic] else { return }
        peripheral?.setNotifyValue(true, for: c)
    }
    // `log` is provided above and satisfies the protocol.
}

// MARK: - CBCentralManagerDelegate

extension ScaleBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn { log("Bluetooth ready.") }
            else { status = .error("Bluetooth state: \(central.state.rawValue)") }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard status == .scanning else { return }

            let name = peripheral.name
                ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                ?? "(no name)"
            let svcs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
                .map { $0.uuidString } ?? []

            // Record the FIRST plausible scale we see, for diagnosis.
            if discoveredName.isEmpty {
                discoveredName = name
                discoveredServices = svcs
                log("Found: name=\(name) services=\(svcs)")
            }

            // Match: either advertises one of our parser's services, or name hints "scale".
            let matchesService = !svcs.filter { parser.serviceUUIDs.contains(CBUUID(string: $0)) }.isEmpty
            let looksLikeScale = name.lowercased().contains("scale")
            guard matchesService || looksLikeScale else { return }

            self.peripheral = peripheral
            peripheral.delegate = self
            status = .connecting
            log("Connecting to \(name)…")
            central.stopScan()
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard status == .connecting else { return }
            status = .connected
            log("Connected. Discovering services…")
            peripheral.discoverServices(parser.serviceUUIDs)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard status == .connecting else { return }
            status = .error(error?.localizedDescription ?? "connect failed")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ScaleBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            for svc in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(nil, for: svc)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for c in service.characteristics ?? [] { characteristics[c.uuid] = c }
            // Once we've collected characteristics, let the parser drive the handshake.
            if status == .connected {
                status = .reading
                parser.onConnected(user: user, transport: self)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            log("notify \(characteristic.uuid.uuidString): \(Bytes.hexPreview(data))")
            parser.onNotification(characteristic: characteristic.uuid, data: data, user: user, transport: self)
        }
    }
}

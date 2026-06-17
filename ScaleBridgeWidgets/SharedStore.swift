import Foundation

struct WeightPoint: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let weightKg: Float
    let fatPercent: Float?
}

enum SharedStore {
    private static let suiteName = "group.com.ishubhamsingh.ScaleBridge"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func readWeightKg() -> Float? {
        guard defaults?.object(forKey: "latestWeightKg") != nil else { return nil }
        let v = defaults?.float(forKey: "latestWeightKg") ?? 0
        return v > 0 ? v : nil
    }

    static func readFatPercent() -> Float? {
        guard defaults?.object(forKey: "latestBodyFatPct") != nil else { return nil }
        let v = defaults?.float(forKey: "latestBodyFatPct") ?? 0
        return v > 0 ? v : nil
    }

    static func readDate() -> Date? {
        guard let t = defaults?.object(forKey: "latestWeighInTimestamp") as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func readIsMale() -> Bool {
        (defaults?.object(forKey: "profileIsMale") as? Bool) ?? true
    }

    static func readHistory() -> [WeightPoint] {
        guard let data = defaults?.data(forKey: "weightHistory"),
              let points = try? JSONDecoder().decode([WeightPoint].self, from: data)
        else { return [] }
        return points.sorted { $0.date < $1.date }
    }
}

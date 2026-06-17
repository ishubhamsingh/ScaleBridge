import Foundation

struct WeightPoint: Codable {
    let date: Date
    let weightKg: Float
    let fatPercent: Float?
}

enum SharedStore {
    private static let suiteName = "group.com.ishubhamsingh.ScaleBridge"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func write(weighIn: WeighIn) {
        defaults?.set(weighIn.weightKg, forKey: "latestWeightKg")
        if let fat = weighIn.fatPercent { defaults?.set(fat, forKey: "latestBodyFatPct") }
        defaults?.set(weighIn.date.timeIntervalSince1970, forKey: "latestWeighInTimestamp")
    }

    static func writeProfileMeta(isMale: Bool) {
        defaults?.set(isMale, forKey: "profileIsMale")
    }

    static func writeHistory(weighIns: [WeighIn]) {
        let points = weighIns.prefix(14).map {
            WeightPoint(date: $0.date, weightKg: $0.weightKg, fatPercent: $0.fatPercent)
        }
        if let data = try? JSONEncoder().encode(points) {
            defaults?.set(data, forKey: "weightHistory")
        }
    }
}

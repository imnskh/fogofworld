import Foundation
import CoreLocation

struct TrackingSettings: Codable {
    var accuracy: AccuracyLevel = .high

    enum AccuracyLevel: String, Codable, CaseIterable {
        case best = "高"
        case high = "中"
        case standard = "低"

        var descriptionText: String {
            switch self {
            case .best:
                return "推定 約200km/hまで隙間なく記録可能。60km/h以上で自動補間あり。バッテリー消費多め"
            case .high:
                return "推定 約80km/hまで隙間なく記録可能。60km/h以上で自動補間あり。バッテリー消費ふつう"
            case .standard:
                return "推定 約20km/hまで隙間なく記録可能。自動補間なし。バッテリー消費少ない"
            }
        }

        var clAccuracy: CLLocationAccuracy {
            switch self {
            case .best: kCLLocationAccuracyBest
            case .high: kCLLocationAccuracyNearestTenMeters
            case .standard: kCLLocationAccuracyHundredMeters
            }
        }
    }

    static func load() -> TrackingSettings {
        guard let data = UserDefaults.standard.data(forKey: "trackingSettings"),
              let settings = try? JSONDecoder().decode(TrackingSettings.self, from: data)
        else { return TrackingSettings() }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "trackingSettings")
    }
}

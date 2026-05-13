import Foundation
import CoreLocation

struct TrackingSettings: Codable {
    var foregroundDistance: Double = 10
    var backgroundDistance: Double = 50
    var accuracy: AccuracyLevel = .high

    enum AccuracyLevel: String, Codable, CaseIterable {
        case best = "最高"
        case high = "高"
        case standard = "標準"

        var clAccuracy: CLLocationAccuracy {
            switch self {
            case .best: kCLLocationAccuracyBest
            case .high: kCLLocationAccuracyNearestTenMeters
            case .standard: kCLLocationAccuracyHundredMeters
            }
        }
    }

    static let foregroundOptions: [Double] = [5, 10, 20, 30, 50, 100]
    static let backgroundOptions: [Double] = [5, 10, 20, 30, 50, 100]

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

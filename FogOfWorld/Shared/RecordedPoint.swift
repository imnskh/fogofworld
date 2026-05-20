import Foundation
import CoreLocation

struct RecordedPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speed: Double?
    let horizontalAccuracy: Double?
    let course: Double?
    let isAutomotive: Bool?

    init(coordinate: CLLocationCoordinate2D, timestamp: Date = Date(), speed: Double? = nil, horizontalAccuracy: Double? = nil, course: Double? = nil, isAutomotive: Bool? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
        self.course = course
        self.isAutomotive = isAutomotive
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var speedKmh: Double? {
        guard let speed, speed >= 0 else { return nil }
        return speed * 3.6
    }
}

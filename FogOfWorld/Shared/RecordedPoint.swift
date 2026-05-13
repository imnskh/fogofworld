import Foundation
import CoreLocation

struct RecordedPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    init(coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

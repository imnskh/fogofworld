import Foundation
import MapKit

struct TileCoord: Hashable, Codable {
    let x: Int
    let y: Int

    static let size: Double = 0.001

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    init(from coordinate: CLLocationCoordinate2D) {
        self.x = Int(floor(coordinate.longitude / Self.size))
        self.y = Int(floor(coordinate.latitude / Self.size))
    }

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (Double(y) + 0.5) * Self.size,
            longitude: (Double(x) + 0.5) * Self.size
        )
    }

    var mapRect: MKMapRect {
        let sw = CLLocationCoordinate2D(
            latitude: Double(y) * Self.size,
            longitude: Double(x) * Self.size
        )
        let ne = CLLocationCoordinate2D(
            latitude: Double(y + 1) * Self.size,
            longitude: Double(x + 1) * Self.size
        )
        let swPoint = MKMapPoint(sw)
        let nePoint = MKMapPoint(ne)
        let origin = MKMapPoint(
            x: min(swPoint.x, nePoint.x),
            y: min(swPoint.y, nePoint.y)
        )
        let end = MKMapPoint(
            x: max(swPoint.x, nePoint.x),
            y: max(swPoint.y, nePoint.y)
        )
        return MKMapRect(
            origin: origin,
            size: MKMapSize(width: end.x - origin.x, height: end.y - origin.y)
        )
    }

    static func tileRange(for mapRect: MKMapRect) -> (xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) {
        let region = MKCoordinateRegion(mapRect)
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        return (
            Int(floor(minLon / size))...Int(floor(maxLon / size)),
            Int(floor(minLat / size))...Int(floor(maxLat / size))
        )
    }
}

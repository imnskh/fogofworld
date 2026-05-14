import MapKit

final class TrackOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect: MKMapRect = .world
}

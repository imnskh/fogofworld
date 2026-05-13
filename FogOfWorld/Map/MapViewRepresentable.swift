import SwiftUI
import MapKit
import Combine

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var explorationManager: ExplorationManager
    var zoomDelta: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(explorationManager: explorationManager)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        let config = MKStandardMapConfiguration(emphasisStyle: .muted)
        config.showsTraffic = false
        mapView.preferredConfiguration = config

        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        let fogOverlay = FogOverlay()
        mapView.addOverlay(fogOverlay, level: .aboveLabels)

        context.coordinator.setupSubscription(mapView: mapView)

        if let loc = explorationManager.currentLocation {
            let region = MKCoordinateRegion(
                center: loc,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            )
            mapView.setRegion(region, animated: false)
        }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if zoomDelta != context.coordinator.lastZoomDelta {
            context.coordinator.lastZoomDelta = zoomDelta
            var region = uiView.region
            let factor = zoomDelta > context.coordinator.previousZoomValue ? 0.5 : 2.0
            context.coordinator.previousZoomValue = zoomDelta
            region.span.latitudeDelta *= factor
            region.span.longitudeDelta *= factor
            uiView.setRegion(region, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let explorationManager: ExplorationManager
        var fogRenderer: FogOverlayRenderer?
        var hasCenteredOnUser = false
        var lastZoomDelta = 0
        var previousZoomValue = 0

        init(explorationManager: ExplorationManager) {
            self.explorationManager = explorationManager
        }

        var tilesCancellable: AnyCancellable?
        var pointsCancellable: AnyCancellable?
        weak var trackPolyline: MKPolyline?

        func setupSubscription(mapView: MKMapView) {
            tilesCancellable = explorationManager.$visitedTiles
                .receive(on: DispatchQueue.main)
                .sink { [weak self] tiles in
                    self?.fogRenderer?.updateTiles(tiles)
                }
            pointsCancellable = explorationManager.$recordedPoints
                .receive(on: DispatchQueue.main)
                .sink { [weak self] points in
                    self?.updateTrack(points: points, on: mapView)
                }
        }

        func updateTrack(points: [RecordedPoint], on mapView: MKMapView) {
            if let old = trackPolyline {
                mapView.removeOverlay(old)
            }
            guard points.count >= 2 else { return }
            var coords = points.map { $0.coordinate }
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polyline, level: .aboveRoads)
            trackPolyline = polyline
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FogOverlay {
                let renderer = FogOverlayRenderer(overlay: overlay)
                renderer.updateTiles(explorationManager.visitedTiles)
                fogRenderer = renderer
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.7)
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !hasCenteredOnUser else { return }
            let region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            )
            mapView.setRegion(region, animated: true)
            hasCenteredOnUser = true
        }
    }
}

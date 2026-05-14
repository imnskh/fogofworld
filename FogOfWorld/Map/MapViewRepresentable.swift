import SwiftUI
import MapKit
import Combine

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var explorationManager: ExplorationManager
    var zoomDelta: Int
    var showTrack: Bool

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

        let trackOverlay = TrackOverlay()
        mapView.addOverlay(trackOverlay, level: .aboveRoads)

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
        if showTrack != context.coordinator.trackVisible {
            context.coordinator.trackVisible = showTrack
            context.coordinator.trackRenderer?.visible = showTrack
            context.coordinator.trackRenderer?.setNeedsDisplay()
        }
        // ExplorationManager は @ObservedObject なので fogEffectsEnabled が変わると updateUIView が走る。
        // renderer 側の setter が値変化時のみ setNeedsDisplay() を発火するため、毎フレーム代入しても無駄ヒットはしない。
        context.coordinator.fogRenderer?.effectsEnabled = explorationManager.fogEffectsEnabled
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let explorationManager: ExplorationManager
        var fogRenderer: FogOverlayRenderer?
        var trackRenderer: TrackOverlayRenderer?
        var hasCenteredOnUser = false
        var lastZoomDelta = 0
        var previousZoomValue = 0
        var lastPointCount = 0
        var trackVisible = true

        init(explorationManager: ExplorationManager) {
            self.explorationManager = explorationManager
        }

        var tilesCancellable: AnyCancellable?
        var pointsCancellable: AnyCancellable?

        func setupSubscription(mapView: MKMapView) {
            tilesCancellable = explorationManager.$visitedTiles
                .receive(on: DispatchQueue.main)
                .sink { [weak self] tiles in
                    self?.fogRenderer?.updateTiles(tiles)
                }
            pointsCancellable = explorationManager.$recordedPoints
                .receive(on: DispatchQueue.main)
                .sink { [weak self] points in
                    guard let self else { return }
                    if self.lastPointCount == 0 {
                        self.trackRenderer?.updatePoints(points)
                    } else {
                        for point in points[self.lastPointCount...] {
                            self.trackRenderer?.appendPoint(point)
                        }
                    }
                    self.lastPointCount = points.count
                }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FogOverlay {
                let renderer = FogOverlayRenderer(overlay: overlay)
                // updateTiles 前に effectsEnabled を確定しておく。
                // (アニメ判定ロジックが effectsEnabled を参照するため順序が重要)
                renderer.effectsEnabled = explorationManager.fogEffectsEnabled
                renderer.updateTiles(explorationManager.visitedTiles)
                fogRenderer = renderer
                return renderer
            }
            if overlay is TrackOverlay {
                let renderer = TrackOverlayRenderer(overlay: overlay)
                renderer.updatePoints(explorationManager.recordedPoints)
                lastPointCount = explorationManager.recordedPoints.count
                trackRenderer = renderer
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

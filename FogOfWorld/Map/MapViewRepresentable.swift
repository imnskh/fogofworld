import SwiftUI
import MapKit
import Combine

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var explorationManager: ExplorationManager
    var zoomDelta: Int
    var showTrack: Bool
    var historyDayPoints: [RecordedPoint]?
    var historyMarkerCoordinate: CLLocationCoordinate2D?
    var historyMarkerTimeString: String?

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

        mapView.register(HistoryAnnotationView.self, forAnnotationViewWithReuseIdentifier: HistoryAnnotationView.reuseIdentifier)

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
        let coord = context.coordinator

        if zoomDelta != coord.lastZoomDelta {
            coord.lastZoomDelta = zoomDelta
            var region = uiView.region
            let factor = zoomDelta > coord.previousZoomValue ? 0.5 : 2.0
            coord.previousZoomValue = zoomDelta
            region.span.latitudeDelta *= factor
            region.span.longitudeDelta *= factor
            uiView.setRegion(region, animated: true)
        }
        if showTrack != coord.trackVisible {
            coord.trackVisible = showTrack
            coord.trackRenderer?.visible = showTrack
            coord.trackRenderer?.setNeedsDisplay()
        }
        coord.fogRenderer?.effectsEnabled = explorationManager.fogEffectsEnabled
        // 履歴モード中は「直近N時間」フィルタを無効化して指定日の全軌跡を見せる。
        // 通常モードに戻ったらユーザー設定を復元する。
        let userInterval = explorationManager.trackingSettings.trackDisplayHours.timeInterval
        let effectiveInterval: TimeInterval? = (historyDayPoints != nil) ? nil : userInterval
        if effectiveInterval != coord.lastDisplayInterval {
            coord.lastDisplayInterval = effectiveInterval
            coord.trackRenderer?.displayTimeInterval = effectiveInterval
            coord.trackRenderer?.setNeedsDisplay()
        }

        applyHistoryState(mapView: uiView, coordinator: coord)
    }

    private func applyHistoryState(mapView: MKMapView, coordinator: Coordinator) {
        switch (coordinator.isHistoryMode, historyDayPoints) {
        case (false, .some(let points)):
            // enter history
            coordinator.isHistoryMode = true
            coordinator.trackRenderer?.updatePoints(points)
            updateHistoryMarker(mapView: mapView, coordinator: coordinator)

        case (true, .some(let points)):
            // continue history — 日付が変わった or scrub
            if coordinator.lastHistoryPointsKey != HistoryPointsKey(points) {
                coordinator.trackRenderer?.updatePoints(points)
                coordinator.lastHistoryPointsKey = HistoryPointsKey(points)
            }
            updateHistoryMarker(mapView: mapView, coordinator: coordinator)

        case (true, .none):
            // exit history
            coordinator.isHistoryMode = false
            coordinator.lastHistoryPointsKey = nil
            // 個別参照経由の removeAnnotation が KVO/再エンキューと競合してビューが残ることがあるため、
            // マップ上の HistoryAnnotation インスタンスを総ざらいして除去する。
            let stale = mapView.annotations.compactMap { $0 as? HistoryAnnotation }
            if !stale.isEmpty {
                mapView.removeAnnotations(stale)
            }
            coordinator.historyAnnotation = nil
            let all = explorationManager.recordedPoints
            coordinator.trackRenderer?.updatePoints(all)
            coordinator.lastPointCount = all.count
            // 履歴で動かしたカメラを現在地に戻す。userLocation の方が新鮮なので優先。
            if let coord = mapView.userLocation.location?.coordinate ?? explorationManager.currentLocation {
                mapView.setCenter(coord, animated: true)
            }

        case (false, .none):
            break
        }
    }

    private func updateHistoryMarker(mapView: MKMapView, coordinator: Coordinator) {
        guard let coordinate = historyMarkerCoordinate, let timeString = historyMarkerTimeString else {
            // 個別参照経由の removeAnnotation は KVO/再エンキューと競合しうるため、
            // 記録のない日に切り替わった場合も総ざらいで除去する (exit 時と同じ防御)。
            let stale = mapView.annotations.compactMap { $0 as? HistoryAnnotation }
            if !stale.isEmpty {
                mapView.removeAnnotations(stale)
            }
            coordinator.historyAnnotation = nil
            return
        }

        if let ann = coordinator.historyAnnotation {
            ann.update(coordinate: coordinate, timeString: timeString)
        } else {
            let ann = HistoryAnnotation(coordinate: coordinate, timeString: timeString)
            mapView.addAnnotation(ann)
            coordinator.historyAnnotation = ann
        }
        // スライダースクラブ中に大量のアニメが積み上がるとドラッグ終了後も追従し続けるため非アニメ。
        mapView.setCenter(coordinate, animated: false)
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
        var lastDisplayInterval: TimeInterval?

        var isHistoryMode = false
        var historyAnnotation: HistoryAnnotation?
        var lastHistoryPointsKey: HistoryPointsKey?

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
                    // 履歴モード中は生 recordedPoints の追従を停止して、表示中の日付スナップショットを保つ。
                    if self.isHistoryMode { return }
                    // import.replace 等で配列が縮小した場合 points[lastPointCount...] が範囲外で trap するため
                    // 縮小・初回の両方を「全置換」経路に寄せる。
                    if self.lastPointCount == 0 || self.lastPointCount > points.count {
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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is HistoryAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: HistoryAnnotationView.reuseIdentifier, for: annotation)
                return view
            }
            return nil
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

// 履歴用ポイント配列が「同じ日付の同じスナップショット」かを判定するためのキー。
// 配列同一性ではなく内容識別 (件数 + 先頭/末尾 timestamp) で十分。
struct HistoryPointsKey: Equatable {
    let count: Int
    let firstStamp: Date?
    let lastStamp: Date?

    init(_ points: [RecordedPoint]) {
        count = points.count
        firstStamp = points.first?.timestamp
        lastStamp = points.last?.timestamp
    }
}

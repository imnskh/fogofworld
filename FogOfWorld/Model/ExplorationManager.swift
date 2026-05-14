import Foundation
import CoreLocation
import Combine
import MapKit
import WidgetKit

final class ExplorationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var visitedTiles: Set<TileCoord> = []
    @Published private(set) var recordedPoints: [RecordedPoint] = []
    @Published private(set) var currentLocation: CLLocationCoordinate2D?
    @Published private(set) var authorizationDenied = false
    @Published var backgroundTrackingEnabled: Bool {
        didSet {
            SharedSettings.backgroundTrackingEnabled = backgroundTrackingEnabled
            applyTrackingMode()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    @Published var trackingSettings: TrackingSettings {
        didSet {
            trackingSettings.save()
            applyTrackingMode()
        }
    }
    @Published var fogEffectsEnabled: Bool {
        didSet {
            SharedSettings.fogEffectsEnabled = fogEffectsEnabled
        }
    }

    var totalTiles: Int { visitedTiles.count }

    var exploredAreaKm2: Double {
        SharedTileStore.areaKm2(tileCount: visitedTiles.count)
    }

    var exploredAreaFormatted: String {
        SharedTileStore.areaFormatted(tileCount: visitedTiles.count)
    }

    private let clManager = CLLocationManager()
    private var saveTask: DispatchWorkItem?
    private var isInForeground = true
    private var lastLocation: CLLocation?
    private let interpolationSpeedThreshold: CLLocationSpeed = 60.0 / 3.6 // 60 km/h in m/s
    // 保存はこのシリアルキューに乗せて、並行書き込みによる古いスナップショット上書きを防ぐ。
    private let persistenceQueue = DispatchQueue(label: "com.twogate.fogworld.persistence")

    override init() {
        SharedSettings.migrateStandardDefaultsIfNeeded()
        self.backgroundTrackingEnabled = SharedSettings.backgroundTrackingEnabled
        self.trackingSettings = TrackingSettings.load()
        self.fogEffectsEnabled = SharedSettings.fogEffectsEnabled
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = trackingSettings.accuracy.clAccuracy
        clManager.distanceFilter = kCLDistanceFilterNone
        clManager.pausesLocationUpdatesAutomatically = false
        SharedTileStore.migrateFromDocumentsIfNeeded()
        loadTiles()
        // マイグレーション/読み込み完了直後にWidget Timelineを更新。
        // これがないと、初回起動より前にWidgetがリフレッシュした場合に最大1時間古いキャッシュを表示しうる。
        WidgetCenter.shared.reloadAllTimelines()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    // MARK: - Tracking Control

    private func applyTrackingMode() {
        let status = clManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }

        if backgroundTrackingEnabled {
            if status == .authorizedWhenInUse {
                clManager.requestAlwaysAuthorization()
            }
            clManager.allowsBackgroundLocationUpdates = true
            clManager.showsBackgroundLocationIndicator = true
            clManager.startMonitoringSignificantLocationChanges()
            clManager.startMonitoringVisits()
            if isInForeground {
                clManager.startUpdatingLocation()
            }
        } else {
            clManager.allowsBackgroundLocationUpdates = false
            clManager.showsBackgroundLocationIndicator = false
            clManager.stopMonitoringSignificantLocationChanges()
            clManager.stopMonitoringVisits()
            if isInForeground {
                clManager.startUpdatingLocation()
            } else {
                clManager.stopUpdatingLocation()
            }
        }
    }

    @objc private func appDidEnterBackground() {
        isInForeground = false
        if backgroundTrackingEnabled {
            clManager.desiredAccuracy = trackingSettings.accuracy.clAccuracy
        } else {
            clManager.stopUpdatingLocation()
        }
        // バックグラウンド遷移直前は同期で書き出さないとiOSがアプリをsuspendして書き込みが中断する。
        saveSynchronously()
    }

    @objc private func appWillEnterForeground() {
        isInForeground = true
        // ウィジェットから backgroundTrackingEnabled が変更されている可能性があるので再読込。
        let storedTracking = SharedSettings.backgroundTrackingEnabled
        if storedTracking != backgroundTrackingEnabled {
            backgroundTrackingEnabled = storedTracking
        }
        clManager.desiredAccuracy = trackingSettings.accuracy.clAccuracy
        clManager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            authorizationDenied = false
            if backgroundTrackingEnabled {
                manager.requestAlwaysAuthorization()
            }
            applyTrackingMode()
        case .authorizedAlways:
            authorizationDenied = false
            applyTrackingMode()
        case .denied, .restricted:
            authorizationDenied = true
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var didChange = false
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 else { continue }
            currentLocation = location.coordinate
            recordedPoints.append(RecordedPoint(coordinate: location.coordinate, timestamp: location.timestamp))

            if let prev = lastLocation,
               location.speed >= interpolationSpeedThreshold,
               trackingSettings.accuracy != .standard {
                let interpolated = TileCoord.interpolatedTiles(from: prev.coordinate, to: location.coordinate)
                for tile in interpolated {
                    if visitedTiles.insert(tile).inserted {
                        didChange = true
                    }
                }
            }

            let tile = TileCoord(from: location.coordinate)
            if visitedTiles.insert(tile).inserted {
                didChange = true
            }
            lastLocation = location
        }
        if didChange || !locations.isEmpty {
            scheduleSave()
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard visit.horizontalAccuracy < 100, visit.horizontalAccuracy >= 0 else { return }
        let tile = TileCoord(from: visit.coordinate)
        if visitedTiles.insert(tile).inserted {
            scheduleSave()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveTiles()
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    func saveTiles() {
        let tiles = visitedTiles
        let points = recordedPoints
        persistenceQueue.async {
            SharedTileStore.save(tiles)
            SharedTileStore.savePoints(points)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func saveSynchronously() {
        saveTask?.cancel()
        let tiles = visitedTiles
        let points = recordedPoints
        persistenceQueue.sync {
            SharedTileStore.save(tiles)
            SharedTileStore.savePoints(points)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadTiles() {
        visitedTiles = SharedTileStore.load()
        recordedPoints = SharedTileStore.loadPoints()
        SharedSettings.cachedTileCount = visitedTiles.count
    }

    // MARK: - Import / Export

    func exportDocument() -> ExplorationDocument {
        ExplorationDocument(tiles: visitedTiles)
    }

    enum ImportMode {
        case merge
        case replace
    }

    func importTiles(from url: URL, mode: ImportMode) throws -> Int {
        guard url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(ExplorationData.self, from: data)

        let newTiles = Set(imported.tiles)
        let previousCount = visitedTiles.count

        switch mode {
        case .merge:
            visitedTiles.formUnion(newTiles)
        case .replace:
            visitedTiles = newTiles
        }

        saveTiles()
        return visitedTiles.count - previousCount
    }

}

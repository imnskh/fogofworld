import Foundation
import CoreLocation
import Combine
import MapKit
import WidgetKit

final class ExplorationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var visitedTiles: Set<TileCoord> = []
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
    // 保存はこのシリアルキューに乗せて、並行書き込みによる古いスナップショット上書きを防ぐ。
    private let persistenceQueue = DispatchQueue(label: "com.twogate.FogOfWorld.persistence")

    override init() {
        SharedSettings.migrateStandardDefaultsIfNeeded()
        self.backgroundTrackingEnabled = SharedSettings.backgroundTrackingEnabled
        self.trackingSettings = TrackingSettings.load()
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = trackingSettings.accuracy.clAccuracy
        clManager.distanceFilter = trackingSettings.foregroundDistance
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
            clManager.distanceFilter = trackingSettings.backgroundDistance
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
        clManager.distanceFilter = trackingSettings.foregroundDistance
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
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 else { continue }
            currentLocation = location.coordinate
            let tile = TileCoord(from: location.coordinate)
            if visitedTiles.insert(tile).inserted {
                scheduleSave()
            }
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
        persistenceQueue.async {
            SharedTileStore.save(tiles)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // バックグラウンド遷移時に呼ぶ同期保存。iOSのsuspend猶予内に確実に書き出すために使う。
    func saveSynchronously() {
        saveTask?.cancel()
        let tiles = visitedTiles
        persistenceQueue.sync {
            SharedTileStore.save(tiles)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadTiles() {
        visitedTiles = SharedTileStore.load()
        // タイル件数をWidget用にキャッシュしておく（Widget側でJSON全件デコードを避けるため）。
        SharedSettings.cachedTileCount = visitedTiles.count
    }
}

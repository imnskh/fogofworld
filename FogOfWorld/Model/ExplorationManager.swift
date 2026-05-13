import Foundation
import CoreLocation
import Combine
import MapKit

final class ExplorationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var visitedTiles: Set<TileCoord> = []
    @Published private(set) var currentLocation: CLLocationCoordinate2D?
    @Published private(set) var authorizationDenied = false
    @Published var backgroundTrackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundTrackingEnabled, forKey: "backgroundTrackingEnabled")
            applyTrackingMode()
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
        let avgTileAreaM2 = 111.0 * 91.0
        return Double(visitedTiles.count) * avgTileAreaM2 / 1_000_000
    }

    var exploredAreaFormatted: String {
        let area = exploredAreaKm2
        if area < 1 {
            return String(format: "%.0f m²", area * 1_000_000)
        }
        return String(format: "%.2f km²", area)
    }

    private let clManager = CLLocationManager()
    private var saveTask: DispatchWorkItem?
    private var isInForeground = true

    override init() {
        self.backgroundTrackingEnabled = UserDefaults.standard.bool(forKey: "backgroundTrackingEnabled")
        self.trackingSettings = TrackingSettings.load()
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = trackingSettings.accuracy.clAccuracy
        clManager.distanceFilter = trackingSettings.foregroundDistance
        clManager.pausesLocationUpdatesAutomatically = false
        loadTiles()

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
        saveIfNeeded()
    }

    @objc private func appWillEnterForeground() {
        isInForeground = true
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

    private func fileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("visited_tiles.json")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveTiles()
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    func saveTiles() {
        let tiles = Array(visitedTiles)
        DispatchQueue.global(qos: .utility).async { [fileURL = fileURL()] in
            guard let data = try? JSONEncoder().encode(tiles) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func loadTiles() {
        guard let data = try? Data(contentsOf: fileURL()),
              let tiles = try? JSONDecoder().decode([TileCoord].self, from: data) else { return }
        visitedTiles = Set(tiles)
    }

    func saveIfNeeded() {
        saveTask?.cancel()
        saveTiles()
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

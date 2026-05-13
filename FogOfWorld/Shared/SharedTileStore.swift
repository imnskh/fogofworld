import Foundation
import os.log

enum SharedTileStore {
    static let appGroupID = "group.com.twogate.fogworld"
    private static let fileName = "visited_tiles.json"
    private static let logger = Logger(subsystem: appGroupID, category: "SharedTileStore")

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    static func load() -> Set<TileCoord> {
        guard let url = fileURL else {
            logger.error("App Group container unavailable; check entitlements & provisioning")
            return []
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let tiles = try JSONDecoder().decode([TileCoord].self, from: data)
            return Set(tiles)
        } catch {
            logger.error("Failed to decode visited tiles at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func save(_ tiles: Set<TileCoord>) {
        guard let url = fileURL else {
            logger.error("App Group container unavailable; skipping save")
            return
        }
        do {
            let data = try JSONEncoder().encode(Array(tiles))
            try data.write(to: url, options: .atomic)
            // 保存と同時に件数キャッシュも更新（Widget 用）。
            SharedSettings.cachedTileCount = tiles.count
        } catch {
            logger.error("Failed to save visited tiles: \(error.localizedDescription, privacy: .public)")
        }
    }

    // 旧バージョンのDocuments/visited_tiles.jsonからApp Groupへ移行する。
    // App Groupに既にデータがある場合は何もしない。
    static func migrateFromDocumentsIfNeeded() {
        guard let url = fileURL,
              !FileManager.default.fileExists(atPath: url.path) else { return }
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: docsURL.path),
              let data = try? Data(contentsOf: docsURL) else { return }
        try? data.write(to: url, options: .atomic)
        // 移行後、件数キャッシュも更新しておく（初回起動でWidgetが0件のままになるのを防ぐ）。
        if let tiles = try? JSONDecoder().decode([TileCoord].self, from: data) {
            SharedSettings.cachedTileCount = tiles.count
        }
    }

    // 探索面積をkm²で算出する共通関数（本体・Widget双方で使用）。
    // タイル1辺0.001°≒緯度経度それぞれ約111m/91mの近似面積。
    static func areaKm2(tileCount: Int) -> Double {
        let avgTileAreaM2 = 111.0 * 91.0
        return Double(tileCount) * avgTileAreaM2 / 1_000_000
    }

    static func areaFormatted(tileCount: Int) -> String {
        let km2 = areaKm2(tileCount: tileCount)
        if km2 < 1 {
            return String(format: "%.0f m²", km2 * 1_000_000)
        }
        return String(format: "%.2f km²", km2)
    }
}

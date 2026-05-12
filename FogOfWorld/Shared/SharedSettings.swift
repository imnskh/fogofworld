import Foundation

enum SharedSettings {
    static let appGroupID = "group.com.twogate.FogOfWorld"
    private static let backgroundTrackingKey = "backgroundTrackingEnabled"
    private static let cachedTileCountKey = "cachedTileCount"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var backgroundTrackingEnabled: Bool {
        get { defaults.bool(forKey: backgroundTrackingKey) }
        set { defaults.set(newValue, forKey: backgroundTrackingKey) }
    }

    // タイル件数の事前計算キャッシュ。Widget が JSON 全件デコードを避けるために使う。
    // 書き込みは SharedTileStore.save と ExplorationManager.loadTiles から行う。
    static var cachedTileCount: Int {
        get { defaults.integer(forKey: cachedTileCountKey) }
        set { defaults.set(newValue, forKey: cachedTileCountKey) }
    }

    // 旧バージョンが UserDefaults.standard に保存していた設定値をApp Groupへ移行する。
    // App Group側に値が無く、Standard側にだけある場合のみコピー。
    static func migrateStandardDefaultsIfNeeded() {
        if defaults.object(forKey: backgroundTrackingKey) == nil,
           UserDefaults.standard.object(forKey: backgroundTrackingKey) != nil {
            defaults.set(
                UserDefaults.standard.bool(forKey: backgroundTrackingKey),
                forKey: backgroundTrackingKey
            )
        }
    }
}

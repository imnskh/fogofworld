import Foundation

enum SharedSettings {
    static let appGroupID = "group.com.twogate.fogworld"
    private static let backgroundTrackingKey = "backgroundTrackingEnabled"
    private static let cachedTileCountKey = "cachedTileCount"
    private static let fogEffectsEnabledKey = "fogEffectsEnabled"

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

    // 霧のエフェクト (境界ソフト化 + 新タイル解禁アニメ) の一括 ON/OFF。
    // 未設定時は true (有効) をデフォルトにする。
    static var fogEffectsEnabled: Bool {
        get {
            if defaults.object(forKey: fogEffectsEnabledKey) == nil { return true }
            return defaults.bool(forKey: fogEffectsEnabledKey)
        }
        set { defaults.set(newValue, forKey: fogEffectsEnabledKey) }
    }

    // MARK: - Stationary Detection State

    private static let isBackgroundStationaryKey = "isBackgroundStationary"
    private static let stationaryCenterLatKey = "stationaryCenterLat"
    private static let stationaryCenterLonKey = "stationaryCenterLon"

    static var isBackgroundStationary: Bool {
        get { defaults.bool(forKey: isBackgroundStationaryKey) }
        set { defaults.set(newValue, forKey: isBackgroundStationaryKey) }
    }

    static var stationaryCenterLat: Double? {
        get { defaults.object(forKey: stationaryCenterLatKey) as? Double }
        set {
            if let v = newValue { defaults.set(v, forKey: stationaryCenterLatKey) }
            else { defaults.removeObject(forKey: stationaryCenterLatKey) }
        }
    }

    static var stationaryCenterLon: Double? {
        get { defaults.object(forKey: stationaryCenterLonKey) as? Double }
        set {
            if let v = newValue { defaults.set(v, forKey: stationaryCenterLonKey) }
            else { defaults.removeObject(forKey: stationaryCenterLonKey) }
        }
    }

    // 旧バージョンが UserDefaults.standard に保存していた設定値をApp Groupへ移行する。
    // App Group側に値が無く、Standard側にだけある場合のみコピー。
    static func migrateStandardDefaultsIfNeeded() {
        if defaults.object(forKey: backgroundTrackingKey) == nil {
            if UserDefaults.standard.object(forKey: backgroundTrackingKey) != nil {
                defaults.set(
                    UserDefaults.standard.bool(forKey: backgroundTrackingKey),
                    forKey: backgroundTrackingKey
                )
            } else {
                defaults.set(true, forKey: backgroundTrackingKey)
            }
        }
    }
}

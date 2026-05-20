# Fog of World

地図が霧に覆われた世界を、実際に歩いて探索するiOSアプリ。訪れた場所の霧が晴れていく。

## Features

- 現在地を追跡して、訪れたエリアの霧を自動で除去
- バックグラウンド位置情報追跡（オプション）
- 探索済み面積の統計表示（タイル数・km²/m²）
- 霧の精度・追跡距離のカスタマイズ

## Requirements

- iOS 17.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Setup

```bash
# XcodeGenをインストール（未インストールの場合）
brew install xcodegen

# Xcodeプロジェクトを生成
xcodegen generate

# Xcodeで開く
open FogOfWorld.xcodeproj
```

`project.yml` の `DEVELOPMENT_TEAM` を自分のApple Developer Team IDに変更してからビルドしてください。

## Architecture

```
FogOfWorld/
├── App/                  # アプリエントリーポイント
├── Map/                  # 地図表示・霧オーバーレイ描画
│   ├── FogOverlay        # MKOverlay実装
│   ├── FogOverlayRenderer# 霧の描画ロジック
│   └── MapViewRepresentable # UIKit↔SwiftUI ブリッジ
├── Model/                # データモデル・ビジネスロジック
│   ├── ExplorationManager# 位置追跡・タイル管理
│   ├── TileCoord         # 緯度経度→タイル座標変換
│   └── TrackingSettings  # 追跡設定
├── Views/                # SwiftUI画面
└── Resources/            # アセット
```

## 位置追跡・バッテリー最適化ロジック

全ロジックは `ExplorationManager` に集約されている。

### タイル座標系

緯度・経度を 0.001° 刻みのグリッドに分割（`TileCoord.size = 0.001`）。赤道で約111m、日本の緯度（約35°N）で約111m×91m。`floor(coordinate / size)` で整数タイル座標に変換する。

### CLLocationManager 基本設定

| 設定 | 値 | 理由 |
|---|---|---|
| `distanceFilter` | 5m | 静止時の無駄な更新を抑制。タイル（約100m）内の微動では通知不要 |
| `activityType` | `.other` | 歩行/車両を兼ねる汎用モード。iOSの省電力判断に使われる |
| `pausesLocationUpdatesAutomatically` | フォアグラウンド: `false`, バックグラウンド: `true` | バックグラウンドで静止時にiOSがGPSを自動停止。フォアグラウンドでは即応性を優先 |

### 精度レベル（ユーザー選択）

| レベル | CLLocationAccuracy | 補間 | 目安 |
|---|---|---|---|
| 高 (`best`) | `kCLLocationAccuracyBest` | あり（60km/h以上） | 約200km/hまで隙間なし |
| 中 (`high`) | `kCLLocationAccuracyNearestTenMeters` | あり（60km/h以上） | 約80km/hまで隙間なし |
| 低 (`standard`) | `kCLLocationAccuracyHundredMeters` | なし | 約20km/hまで隙間なし |

### 位置更新の処理フロー (`didUpdateLocations`)

```
1. backgroundStationary 中に受信 → SLC由来。resumeFromStationary() して return
2. horizontalAccuracy < 0 または >= 100m → 破棄
3. awaitingFullAccuracyFix 中 → horizontalAccuracy < 20m になるまでスキップ
4. RecordedPoint を記録（座標・速度・精度・方角・isAutomotive）
5. 高速移動時のタイル補間（以下のいずれかで発動）:
   - speed >= 60km/h かつ accuracy が standard 以外
   - CMMotionActivity が automotive
   - 前回fixからの推定速度 >= 60km/h かつ距離 <= 2km
   → 前回座標から現在座標までの直線上のタイルを補間挿入
6. 現在座標のタイルを挿入
7. adjustAccuracyForProximity: 未知タイル近接チェック
8. evaluateStationaryConditions: 静止判定（バックグラウンドのみ）
9. 変更があれば scheduleSave（3秒デバウンス）
```

### バッテリー最適化 — 4層構造

#### 第1層: distanceFilter（常時）

`distanceFilter = 5` により、5m未満の移動ではGPS通知が発生しない。GPSチップがスリープに入れる頻度が上がる。

#### 第2層: 未知タイル近接による動的accuracy切替（常時）

`adjustAccuracyForProximity` が毎回の位置更新で実行される。

1. 現在のタイル + 隣接8タイル（3×3 = 9タイル）を走査
2. 未訪問タイルごとに、ユーザーの `MKMapPoint` からタイル矩形の最近接点までの距離を計算
3. 最近接の未訪問タイルが **50m未満** → ユーザー設定の accuracy を維持
4. **50m以上** → `kCLLocationAccuracyHundredMeters` に下げる

ユーザー設定が `standard`（既に最低）の場合はスキップ。

#### 第3層: pausesLocationUpdatesAutomatically（バックグラウンド）

バックグラウンド遷移時に `true` に設定。iOSが静止を検出するとGPS更新を自動で一時停止する。フォアグラウンド復帰時に `false` に戻す。

#### 第4層: 静止検出とジオフェンス待機（バックグラウンド）

最も効果が大きい省電力機構。バックグラウンドで連続GPSを完全に停止し、ジオフェンスで待機する。

**状態遷移**

```
                     全条件120秒充足
[moving] ──────────────────────────────→ [backgroundStationary]
    ↑                                           │
    │  ジオフェンスexit / SLC発火 /              │
    │  フォアグラウンド復帰                      │
    └───────────────────────────────────────────┘
```

**停止確定の条件（`evaluateStationaryConditions`）**

バックグラウンド・`backgroundTrackingEnabled` が true・`trackingState == .moving` の時のみ評価。以下を **全て同時に120秒間**維持した場合に確定する:

| 条件 | 閾値 | 判定方法 |
|---|---|---|
| CMMotionActivity | `stationary` かつ `confidence != .low` | `isMotionStationary` フラグ |
| GPS速度 | `speed >= 0` かつ `< 1.0 m/s` | `CLLocation.speed` |
| 変位 | 始点→現在点の直線距離 < 30m | `horizontalAccuracy < 20m` のfixのみで計測 |
| 経過時間 | 確認ウィンドウ開始から >= 120秒 | `stationaryCheckStart` からの経過 |

条件が1つでも崩れた場合（speed上昇・motion非stationary・変位超過）、確認ウィンドウは即座にリセットされる。`horizontalAccuracy >= 20m` のfixは変位計測に使わないが、ウィンドウはリセットしない（精度が悪いだけで動いたとは限らない）。

**停止確定時の処理 (`transitionToBackgroundStationary`)**

1. `trackingState = .backgroundStationary`
2. `clManager.stopUpdatingLocation()` — 連続GPS停止
3. 現在地を中心に半径100mの `CLCircularRegion` を登録（`notifyOnExit = true`）
4. 状態を `SharedSettings` に永続化（`isBackgroundStationary`, 中心座標）
5. `saveSynchronously()` で未保存データを即書き出し

SLC（`startMonitoringSignificantLocationChanges`）と Visits監視は `applyTrackingMode` で既に開始済みのため、バックアップとして自動的に機能する。

**復帰トリガーと処理 (`resumeFromStationary`)**

| トリガー | 経路 | 精度 |
|---|---|---|
| ジオフェンスexit | `didExitRegion` → `resumeFromStationary()` | WiFi/セル（粗い） |
| SLC発火 | `didUpdateLocations` → `resumeFromStationary()` | セルタワー変更（粗い） |
| フォアグラウンド復帰 | `appWillEnterForeground` → `resumeFromStationary()` | — |

復帰時の処理:
1. `trackingState = .moving`, `awaitingFullAccuracyFix = true`
2. ジオフェンス監視を停止
3. `desiredAccuracy` を復元し `startUpdatingLocation()` で連続GPS再開
4. `SharedSettings` の永続化状態をクリア

**復帰直後のタイル記録保護**

`awaitingFullAccuracyFix = true` の間、`didUpdateLocations` は位置を記録しない。SLC/ジオフェンス由来の粗いfixからタイルを塗ることを防ぐ。`horizontalAccuracy < 20m` の最初のGPS fixが届いた時点でフラグを解除し、そのfixから記録を開始する。

復帰時の取りこぼしは約100〜150m（ジオフェンス半径 + GPS cold start）。タイル1〜2個分で、バッテリー節約とのトレードオフとして許容する設計。

**アプリ終了・再起動時の復元**

`SharedSettings.isBackgroundStationary` と中心座標を永続化しているため、OSによるアプリ終了後もジオフェンス/SLC起床で再起動した際に状態を復元できる。iOSはアプリ終了後もリージョン監視を継続する（ユーザーの強制終了時を除く）。`init()` で `isBackgroundStationary` をチェックし、`true` なら `trackingState = .backgroundStationary` + `awaitingFullAccuracyFix = true` に復元する。

### CMMotionActivity の役割

`CMMotionActivityManager.startActivityUpdates` で2つの情報を取得:

| フラグ | 用途 |
|---|---|
| `isAutomotive` | 車両乗車中のタイル補間を発動させる |
| `isMotionStationary` | 静止判定の必須条件（`stationary` かつ `confidence != .low`） |

CMMotionActivity は**補助シグナル**であり、これ単独でGPSを停止しない。GPSの speed・変位と組み合わせて初めて停止判定に使う。

### フォアグラウンド/バックグラウンド遷移

**バックグラウンド遷移時 (`appDidEnterBackground`)**
1. `pausesLocationUpdatesAutomatically = true`
2. `backgroundTrackingEnabled` が false なら `stopUpdatingLocation()`
3. `saveSynchronously()` — iOSがsuspendする前にデータを確実に書き出す

**フォアグラウンド復帰時 (`appWillEnterForeground`)**
1. `pausesLocationUpdatesAutomatically = false`
2. `backgroundStationary` なら `resumeFromStationary()`
3. 静止確認ウィンドウをリセット
4. ウィジェット経由の設定変更を反映
5. `desiredAccuracy` を復元し `startUpdatingLocation()`

### 保存 (`scheduleSave`)

位置更新ごとに `scheduleSave()` が呼ばれるが、3秒の `DispatchWorkItem` デバウンスにより実際の書き込みは間引かれる。バックグラウンド遷移時と静止確定時は `saveSynchronously()` で即時書き込み。

### 定数一覧

| 定数 | 値 | 場所 |
|---|---|---|
| `TileCoord.size` | 0.001° | `TileCoord.swift` |
| `distanceFilter` | 5m | `ExplorationManager.init` |
| `interpolationSpeedThreshold` | 60 km/h (16.67 m/s) | `ExplorationManager` |
| 未知タイル近接閾値 | 50m | `adjustAccuracyForProximity` |
| `stationaryConfirmationInterval` | 120秒 | `ExplorationManager` |
| `stationaryDisplacementThreshold` | 30m | `ExplorationManager` |
| `stationarySpeedThreshold` | 1.0 m/s | `ExplorationManager` |
| `stationaryGeofenceRadius` | 100m | `ExplorationManager` |
| awaitingFullAccuracyFix 解除閾値 | `horizontalAccuracy < 20m` | `didUpdateLocations` |
| 位置フィルタ | `horizontalAccuracy < 100m` | `didUpdateLocations` |
| 変位計測用精度フィルタ | `horizontalAccuracy < 20m` | `evaluateStationaryConditions` |
| 保存デバウンス | 3秒 | `scheduleSave` |

## License

[AGPL-3.0](LICENSE)

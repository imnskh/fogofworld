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

## License

[AGPL-3.0](LICENSE)

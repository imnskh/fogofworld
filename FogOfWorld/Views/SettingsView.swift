import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var explorationManager: ExplorationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("前面の追跡") {
                    Picker("更新距離", selection: $explorationManager.trackingSettings.foregroundDistance) {
                        ForEach(TrackingSettings.foregroundOptions, id: \.self) { dist in
                            Text("\(Int(dist))m").tag(dist)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("移動するたびに記録する最小距離")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("バックグラウンドの追跡") {
                    Picker("更新距離", selection: $explorationManager.trackingSettings.backgroundDistance) {
                        ForEach(TrackingSettings.backgroundOptions, id: \.self) { dist in
                            Text("\(Int(dist))m").tag(dist)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("小さい値 = 精密だがバッテリー消費多い")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("精度") {
                    Picker("GPS精度", selection: $explorationManager.trackingSettings.accuracy) {
                        ForEach(TrackingSettings.AccuracyLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("探索タイル数")
                        Spacer()
                        Text("\(explorationManager.totalTiles)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("探索面積")
                        Spacer()
                        Text(explorationManager.exploredAreaFormatted)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

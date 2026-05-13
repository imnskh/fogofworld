import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var explorationManager: ExplorationManager
    @Environment(\.dismiss) var dismiss
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingImportConfirm = false
    @State private var pendingImportURL: URL?
    @State private var alertMessage: String?
    @State private var showingAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("バックグラウンドの追跡") {
                    Toggle("バックグラウンド追跡", isOn: $explorationManager.backgroundTrackingEnabled)
                }

                Section("更新頻度") {
                    Picker("更新頻度", selection: $explorationManager.trackingSettings.accuracy) {
                        ForEach(TrackingSettings.AccuracyLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(explorationManager.trackingSettings.accuracy.descriptionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                Section("データ") {
                    Button {
                        showingExporter = true
                    } label: {
                        Label("データをエクスポート", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("データをインポート", systemImage: "square.and.arrow.down")
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
            .fileExporter(
                isPresented: $showingExporter,
                document: explorationManager.exportDocument(),
                contentType: .json,
                defaultFilename: "FogOfWorld_\(Self.dateString()).json"
            ) { result in
                switch result {
                case .success:
                    alertMessage = "エクスポート完了（\(explorationManager.totalTiles)タイル）"
                case .failure(let error):
                    alertMessage = "エクスポート失敗: \(error.localizedDescription)"
                }
                showingAlert = true
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    pendingImportURL = url
                    showingImportConfirm = true
                case .failure(let error):
                    alertMessage = "ファイル読み込み失敗: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
            .confirmationDialog(
                "インポート方法",
                isPresented: $showingImportConfirm,
                titleVisibility: .visible
            ) {
                Button("既存データとマージ") {
                    performImport(mode: .merge)
                }
                Button("既存データを置き換え", role: .destructive) {
                    performImport(mode: .replace)
                }
                Button("キャンセル", role: .cancel) {
                    pendingImportURL = nil
                }
            } message: {
                Text("インポートしたデータをどう扱いますか？")
            }
            .alert("データ", isPresented: $showingAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func performImport(mode: ExplorationManager.ImportMode) {
        guard let url = pendingImportURL else { return }
        defer { pendingImportURL = nil }

        do {
            let added = try explorationManager.importTiles(from: url, mode: mode)
            switch mode {
            case .merge:
                alertMessage = "マージ完了（\(added)タイル追加、合計\(explorationManager.totalTiles)タイル）"
            case .replace:
                alertMessage = "置き換え完了（\(explorationManager.totalTiles)タイル）"
            }
        } catch {
            alertMessage = "インポート失敗: \(error.localizedDescription)"
        }
        showingAlert = true
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}

import WidgetKit
import SwiftUI

struct ExplorationSnapshot {
    let tileCount: Int
    let backgroundTrackingEnabled: Bool

    var areaFormatted: String {
        SharedTileStore.areaFormatted(tileCount: tileCount)
    }

    // 次のマイルストーン（達成目標）。tileCount を超える最小の値を返す。
    // 100,000 を超えた場合は 1 万単位で繰り上げる。
    private static let milestoneSteps: [Int] = [
        50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000,
    ]

    var nextMilestone: Int {
        if let next = Self.milestoneSteps.first(where: { $0 > tileCount }) {
            return next
        }
        return (tileCount / 10000 + 1) * 10000
    }

    var previousMilestone: Int {
        Self.milestoneSteps.last(where: { $0 <= tileCount }) ?? 0
    }

    var milestoneProgress: Double {
        let span = nextMilestone - previousMilestone
        guard span > 0 else { return 0 }
        return min(1, max(0, Double(tileCount - previousMilestone) / Double(span)))
    }

    var remainingToNextMilestone: Int {
        max(0, nextMilestone - tileCount)
    }

    static let empty = ExplorationSnapshot(tileCount: 0, backgroundTrackingEnabled: false)

    static func placeholder(tileCount: Int = 128) -> ExplorationSnapshot {
        ExplorationSnapshot(tileCount: tileCount, backgroundTrackingEnabled: true)
    }
}

struct ExplorationEntry: TimelineEntry {
    let date: Date
    let snapshot: ExplorationSnapshot
}

struct ExplorationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExplorationEntry {
        ExplorationEntry(date: Date(), snapshot: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (ExplorationEntry) -> Void) {
        let snapshot: ExplorationSnapshot
        if context.isPreview {
            snapshot = .placeholder()
        } else {
            snapshot = currentSnapshot()
        }
        completion(ExplorationEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExplorationEntry>) -> Void) {
        let entry = ExplorationEntry(date: Date(), snapshot: currentSnapshot())
        // 1時間後に再読込。実際は本体アプリ側から WidgetCenter.reloadAllTimelines() で更新される。
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentSnapshot() -> ExplorationSnapshot {
        // 件数は SharedSettings にキャッシュ済みのものを直接読む。
        // JSON 全件デコードを回避し、Widget の実行時間/メモリ予算に余裕を持たせる。
        return ExplorationSnapshot(
            tileCount: SharedSettings.cachedTileCount,
            backgroundTrackingEnabled: SharedSettings.backgroundTrackingEnabled
        )
    }
}

struct FogOfWorldWidget: Widget {
    let kind = "FogOfWorldWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExplorationProvider()) { entry in
            FogOfWorldWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.16, blue: 0.28), Color(red: 0.05, green: 0.07, blue: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("探索状況")
        .description("これまでに霧を晴らしたエリアを表示します")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

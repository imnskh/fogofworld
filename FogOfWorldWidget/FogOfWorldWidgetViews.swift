import WidgetKit
import SwiftUI

struct FogOfWorldWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ExplorationEntry

    var body: some View {
        // バックグラウンド更新が無効な場合、統計表示は意味がないので警告のみ表示する。
        if !entry.snapshot.backgroundTrackingEnabled {
            disabledView
        } else {
            enabledView
        }
    }

    @ViewBuilder
    private var enabledView: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumWidgetView(snapshot: entry.snapshot)
        case .accessoryInline:
            InlineWidgetView(snapshot: entry.snapshot)
        case .accessoryCircular:
            CircularWidgetView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            RectangularWidgetView(snapshot: entry.snapshot)
        default:
            SmallWidgetView(snapshot: entry.snapshot)
        }
    }

    @ViewBuilder
    private var disabledView: some View {
        switch family {
        case .accessoryInline:
            DisabledInlineView()
        case .accessoryCircular:
            DisabledCircularView()
        case .accessoryRectangular:
            DisabledRectangularView()
        default:
            DisabledHomeView()
        }
    }
}

// MARK: - Home screen widgets (enabled)

private struct SmallWidgetView: View {
    let snapshot: ExplorationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "map.fill")
                    .font(.caption2)
                Text("Fog of World")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 0)

            Text("\(snapshot.tileCount)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("タイル")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: "square.dashed")
                    .font(.caption2)
                Text(snapshot.areaFormatted)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumWidgetView: View {
    let snapshot: ExplorationSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.caption2)
                    Text("Fog of World")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white.opacity(0.7))

                Spacer(minLength: 0)

                Text("\(snapshot.tileCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("探索タイル")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))

                Spacer(minLength: 0)

                Label(snapshot.areaFormatted, systemImage: "square.dashed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("次の目標")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))

                Text("\(snapshot.nextMilestone)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer(minLength: 0)

                MilestoneProgressBar(progress: snapshot.milestoneProgress)
                    .frame(height: 6)

                Text("あと \(snapshot.remainingToNextMilestone) タイル")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// 次のマイルストーンまでの進捗を示すバー。
private struct MilestoneProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                Capsule()
                    .fill(Color(red: 0.45, green: 0.85, blue: 1.0))
                    .frame(width: geo.size.width * progress)
            }
        }
    }
}

// MARK: - Lock screen / StandBy widgets (enabled)

private struct InlineWidgetView: View {
    let snapshot: ExplorationSnapshot

    var body: some View {
        Text("\(Image(systemName: "map.fill")) \(snapshot.tileCount)タイル · \(snapshot.areaFormatted)")
    }
}

private struct CircularWidgetView: View {
    let snapshot: ExplorationSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "map.fill")
                    .font(.caption2)
                Text("\(snapshot.tileCount)")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .widgetAccentable()
    }
}

private struct RectangularWidgetView: View {
    let snapshot: ExplorationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "map.fill")
                Text("Fog of World")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .widgetAccentable()

            Text("\(snapshot.tileCount) タイル")
                .font(.headline)
            Text(snapshot.areaFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Disabled state views

// バックグラウンド更新OFF時はsystemSmall/systemMedium共通の警告画面を出す。
// ウィジェットをタップすれば自動で本体アプリが開くので、ユーザはそこで設定を変更できる。
private struct DisabledHomeView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)

            Text("バックグラウンド更新が無効です")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("アプリで有効にしてください")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DisabledInlineView: View {
    var body: some View {
        Text("\(Image(systemName: "location.slash")) 追跡OFF")
    }
}

private struct DisabledCircularView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "location.slash")
                .font(.title3)
        }
        .widgetAccentable()
    }
}

private struct DisabledRectangularView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("追跡OFF", systemImage: "location.slash")
                .font(.headline)
                .widgetAccentable()
            Text("アプリで有効にしてください")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

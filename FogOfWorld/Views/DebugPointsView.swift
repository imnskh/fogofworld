import SwiftUI

struct DebugPointsView: View {
    @EnvironmentObject var explorationManager: ExplorationManager

    private var points: [RecordedPoint] {
        explorationManager.recordedPoints.reversed()
    }

    var body: some View {
        List(Array(points.enumerated()), id: \.offset) { _, point in
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.formatDate(point.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    label("速度", value: Self.formatSpeed(point))
                    label("精度", value: Self.formatAccuracy(point))
                    label("方角", value: Self.formatCourse(point))
                }
                .font(.caption)

                HStack(spacing: 12) {
                    label("車両", value: Self.formatAutomotive(point))
                    label("緯度", value: String(format: "%.5f", point.latitude))
                    label("経度", value: String(format: "%.5f", point.longitude))
                }
                .font(.caption)
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("記録ポイント")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ title: String, value: String) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm:ss"
        return f.string(from: date)
    }

    private static func formatSpeed(_ point: RecordedPoint) -> String {
        guard let kmh = point.speedKmh else { return "--" }
        return String(format: "%.0f km/h", kmh)
    }

    private static func formatAccuracy(_ point: RecordedPoint) -> String {
        guard let acc = point.horizontalAccuracy else { return "--" }
        return String(format: "%.0fm", acc)
    }

    private static func formatCourse(_ point: RecordedPoint) -> String {
        guard let course = point.course, course >= 0 else { return "--" }
        return String(format: "%.0f°", course)
    }

    private static func formatAutomotive(_ point: RecordedPoint) -> String {
        guard let auto = point.isAutomotive else { return "--" }
        return auto ? "YES" : "NO"
    }
}

import SwiftUI
import CoreLocation

struct DebugStatusView: View {
    @EnvironmentObject var explorationManager: ExplorationManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let info = explorationManager.captureDebugInfo()
            List {
                trackingStateSection(info)
                locationManagerSection(info)
                motionSection(info)
                lastLocationSection(info)
                stationaryCheckSection(info)
                geofenceSection(info)
                dataSection(info)
            }
        }
        .navigationTitle("トラッキング状態")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func trackingStateSection(_ info: ExplorationManager.DebugInfo) -> some View {
        Section("状態") {
            Toggle("バックグラウンド模擬", isOn: $explorationManager.debugSimulateBackground)
                .font(.caption)
            row("trackingState", info.trackingState)
            row("isInForeground (実際)", info.isInForeground)
            row("effectivelyInForeground", info.isInForeground && !info.debugSimulateBackground)
            row("awaitingFullAccuracyFix", info.awaitingFullAccuracyFix)
            row("backgroundTrackingEnabled", info.backgroundTrackingEnabled)
            row("accuracySetting", info.accuracySetting)
        }
    }

    private func locationManagerSection(_ info: ExplorationManager.DebugInfo) -> some View {
        Section("CLLocationManager") {
            row("desiredAccuracy", accuracyLabel(info.desiredAccuracy))
            row("distanceFilter", String(format: "%.0fm", info.distanceFilter))
            row("activityType", info.activityType)
            row("pausesAutomatically", info.pausesAutomatically)
            row("allowsBackground", info.allowsBackground)
            row("authorizationStatus", info.authorizationStatus)
        }
    }

    private func motionSection(_ info: ExplorationManager.DebugInfo) -> some View {
        Section("CMMotionActivity") {
            row("isMotionStationary", info.isMotionStationary)
            row("isAutomotive", info.isAutomotive)
        }
    }

    private func lastLocationSection(_ info: ExplorationManager.DebugInfo) -> some View {
        Section("最終位置") {
            if let coord = info.lastCoordinate {
                row("座標", String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
            } else {
                row("座標", "--")
            }
            if let speed = info.lastSpeed, speed >= 0 {
                row("速度", String(format: "%.1f m/s (%.0f km/h)", speed, speed * 3.6))
            } else {
                row("速度", "--")
            }
            if let acc = info.lastHorizontalAccuracy, acc >= 0 {
                row("精度", String(format: "%.1fm", acc))
            } else {
                row("精度", "--")
            }
            if let ts = info.lastTimestamp {
                row("時刻", formatDate(ts))
                row("経過", String(format: "%.0f秒前", Date().timeIntervalSince(ts)))
            } else {
                row("時刻", "--")
            }
        }
    }

    private func stationaryCheckSection(_ info: ExplorationManager.DebugInfo) -> some View {
        Section("静止判定ウィンドウ") {
            row("チェック中", info.stationaryCheckActive)
            if let elapsed = info.stationaryCheckElapsed {
                row("経過", String(format: "%.0f / 120秒", elapsed))
            }
        }
    }

    private func geofenceSection(_ info: ExplorationManager.DebugInfo) -> some View {
        Section("ジオフェンス") {
            row("アクティブ", info.geofenceActive)
            if let center = info.geofenceCenter {
                row("中心", String(format: "%.5f, %.5f", center.latitude, center.longitude))
            }
            if let radius = info.geofenceRadius {
                row("半径", String(format: "%.0fm", radius))
            }
            row("監視リージョン数", "\(info.monitoredRegionCount)")
        }
    }

    private func dataSection(_ info: ExplorationManager.DebugInfo) -> some View {
        Section("データ") {
            row("タイル数", "\(info.tileCount)")
            row("ポイント数", "\(info.pointCount)")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func row(_ label: String, _ value: Bool) -> some View {
        row(label, value ? "YES" : "NO")
    }

    private func accuracyLabel(_ accuracy: CLLocationAccuracy) -> String {
        switch accuracy {
        case kCLLocationAccuracyBest: return "best"
        case kCLLocationAccuracyNearestTenMeters: return "10m"
        case kCLLocationAccuracyHundredMeters: return "100m"
        case kCLLocationAccuracyKilometer: return "1km"
        default: return String(format: "%.1f", accuracy)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

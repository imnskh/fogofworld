import SwiftUI

struct HistoryControlBar: View {
    @Binding var sliderValue: Double
    let pointCount: Int
    let startLabel: String
    let endLabel: String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(startLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if pointCount >= 2 {
                    Slider(value: $sliderValue, in: 0...Double(pointCount - 1), step: 1)
                } else {
                    // 0 or 1 件: スライド不可。プレースホルダで枠を保つ。
                    Slider(value: .constant(0), in: 0...1)
                        .disabled(true)
                }
                Text(endLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2)
                Text("\(pointCount)件")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var explorationManager: ExplorationManager
    @State private var zoomDelta = 0
    @State private var showSettings = false

    var body: some View {
        ZStack {
            MapViewRepresentable(explorationManager: explorationManager, zoomDelta: zoomDelta)
                .ignoresSafeArea()

            VStack {
                Spacer()

                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        settingsButton
                        zoomButtons
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 100)
            }

            VStack {
                Spacer()
                if explorationManager.authorizationDenied {
                    permissionDeniedBanner
                } else {
                    statsBar
                }
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 12) {
            Label(
                "\(explorationManager.totalTiles)",
                systemImage: "square.grid.3x3.fill"
            )
            .font(.caption)

            Text("·")
                .foregroundStyle(.secondary)

            Label(
                explorationManager.exploredAreaFormatted,
                systemImage: "map.fill"
            )
            .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 44)
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .frame(width: 44, height: 44)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(explorationManager)
        }
    }

    private var zoomButtons: some View {
        VStack(spacing: 0) {
            Button {
                zoomDelta += 1
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            Divider()
            Button {
                zoomDelta -= 1
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(width: 44)
    }

    private var permissionDeniedBanner: some View {
        VStack(spacing: 8) {
            Text("位置情報の許可が必要です")
                .font(.headline)
            Text("設定アプリから位置情報を許可してください")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 60)
        .padding(.horizontal, 20)
    }
}

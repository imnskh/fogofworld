import SwiftUI

@main
struct FogOfWorldApp: App {
    @StateObject private var explorationManager = ExplorationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(explorationManager)
        }
    }
}

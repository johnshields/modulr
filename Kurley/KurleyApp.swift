import SwiftUI

@main
struct KurleyApp: App {
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

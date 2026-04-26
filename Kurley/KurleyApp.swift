import SwiftUI

@main
struct KurleyApp: App {
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        Window("Kurley", id: "main") {
            ContentView()
                .environmentObject(player)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {} // disable File > New Window
        }
    }
}

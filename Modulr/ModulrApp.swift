import SwiftUI

@main
struct ModulrApp: App {
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        Window("Modulr", id: "main") {
            ContentView()
                .environmentObject(player)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {} // disable File > New Window
        }
    }
}

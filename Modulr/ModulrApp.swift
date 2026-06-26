import SwiftUI
import AppKit

@main
struct ModulrApp: App {
    private static let helpURL = URL(string: "https://github.com/johnshields/modulr")!

    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        Window("Modulr", id: "main") {
            ContentView()
                .environmentObject(player)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {} // disable File > New Window
            CommandGroup(replacing: .appInfo) {
                Button("About Modulr") { showAbout() }
            }
            CommandGroup(replacing: .help) {
                Button("Modulr Help") {
                    NSWorkspace.shared.open(Self.helpURL)
                }
            }
        }
    }

    private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Open-source DJ companion. Analyse, tag, mix.\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        credits.append(NSAttributedString(
            string: "View on GitHub",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: Self.helpURL]
        ))
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

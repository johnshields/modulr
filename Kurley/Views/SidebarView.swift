import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var library: Library

    var body: some View {
        List {
            Section("Favorites") {
                Text(library.favorites.isEmpty ? "No favorites yet" : "\(library.favorites.count) tracks")
                    .foregroundStyle(.secondary)
            }
            Section("Folders") {
                Button("Open Folder…", action: pickFolder)
            }
            Section("Playlists") {
                Text("No playlists yet").foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            library.openFolder(url)
        }
    }
}

import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyze: Bool

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Favorites") {
                    Text(library.favorites.isEmpty ? "No favorites yet" : "\(library.favorites.count) tracks")
                        .foregroundStyle(.secondary)
                }
                Section("Folders") {
                    Button("Open Folder…", action: pickFolder)
                    if let cur = library.currentFolder {
                        Label(cur.lastPathComponent, systemImage: "folder.fill")
                            .help(cur.path)
                    }
                }
                Section("Recent") {
                    if library.recents.isEmpty {
                        Text("No recents").foregroundStyle(.secondary)
                    } else {
                        ForEach(library.recents, id: \.self) { url in
                            Button {
                                library.openFolder(url)
                            } label: {
                                Label(url.lastPathComponent, systemImage: "clock")
                            }
                            .buttonStyle(.plain)
                            .help(url.path)
                        }
                    }
                }
                Section("Playlists") {
                    Text("No playlists yet").foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)

        }
        .frame(minWidth: 220)
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

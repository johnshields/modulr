import SwiftUI
import AppKit

/**
 * SidebarView
 * Sidebar listing favourite folders (starred), the current folder with a star
 * toggle, and recents. Folder favourites persist via RecentsStore.
 */
struct SidebarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyze: Bool

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Favourites") {
                    if library.favouriteFolders.isEmpty {
                        Text("Star a folder to pin it here")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(library.favouriteFolders, id: \.self) { url in
                            folderRow(url, icon: "star.fill")
                        }
                    }
                }

                Section("Folder") {
                    Button("Open Folder…", action: pickFolder)
                    if let cur = library.currentFolder {
                        HStack(spacing: 6) {
                            Label(cur.lastPathComponent, systemImage: "folder.fill")
                                .help(cur.path)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                library.toggleFavouriteFolder(cur)
                            } label: {
                                Image(systemName: library.isFavouriteFolder(cur)
                                      ? "star.fill" : "star")
                                    .foregroundStyle(library.isFavouriteFolder(cur)
                                                     ? Theme.accent : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(library.isFavouriteFolder(cur)
                                  ? "Remove from favourites" : "Add to favourites")
                        }
                    }
                }

                Section("Recent") {
                    if library.recents.isEmpty {
                        Text("No recents").foregroundStyle(.secondary)
                    } else {
                        ForEach(library.recents, id: \.self) { url in
                            folderRow(url, icon: "clock")
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

    @ViewBuilder
    private func folderRow(_ url: URL, icon: String) -> some View {
        Button {
            library.openFolder(url)
        } label: {
            Label(url.lastPathComponent, systemImage: icon)
        }
        .buttonStyle(.plain)
        .help(url.path)
        .contextMenu {
            if library.isFavouriteFolder(url) {
                Button("Remove from favourites") {
                    library.toggleFavouriteFolder(url)
                }
            } else {
                Button("Add to favourites") {
                    library.toggleFavouriteFolder(url)
                }
            }
        }
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

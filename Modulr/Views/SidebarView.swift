import SwiftUI
import AppKit

/**
 * SidebarView
 * Sidebar listing favourite folders, the current folder + star toggle, recents
 * and a Playlists placeholder. Section expansion state persists per section via
 * `@AppStorage` so the layout survives relaunches.
 */
struct SidebarView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyze: Bool

    @AppStorage("modulr.sidebar.favourites.open")  private var favouritesOpen  = true
    @AppStorage("modulr.sidebar.folder.open")      private var folderOpen      = true
    @AppStorage("modulr.sidebar.playlists.open")   private var playlistsOpen   = true

    @State private var newPlaylistName = ""
    @State private var showNewPlaylistAlert = false
    @State private var renamingPlaylist: Playlist?
    @State private var renamingName = ""
    @State private var consolidating = false
    @State private var consolidateSummary: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                DisclosureGroup(isExpanded: $favouritesOpen) {
                    favouriteTracksRow
                    if library.favouriteFolders.isEmpty {
                        Text("Star a folder to pin it here")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(library.favouriteFolders, id: \.self) { url in
                            folderRow(url, icon: "star.fill")
                        }
                    }
                } label: { sectionLabel("Favourites") }

                DisclosureGroup(isExpanded: $folderOpen) {
                    Button("Open Folder…", action: pickFolder)
                    if let cur = library.currentFolder {
                        currentFolderRow(cur)
                    }
                    let rest = library.recents.filter { $0 != library.currentFolder }
                    if !rest.isEmpty {
                        ForEach(rest, id: \.self) { url in
                            folderRow(url, icon: "clock")
                        }
                    }
                } label: { sectionLabel("Folder") }

                DisclosureGroup(isExpanded: $playlistsOpen) {
                    Button("New Playlist…") {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    }

                    if library.playlists.isEmpty {
                        Text("No playlists yet")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(library.playlists) { playlist in
                            playlistRow(playlist)
                        }
                    }
                } label: { sectionLabel("Playlists") }
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    let p = library.createPlaylist(name: newPlaylistName)
                    library.openPlaylist(p)
                }
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .alert("Move Complete",
                   isPresented: Binding(
                    get: { consolidateSummary != nil },
                    set: { if !$0 { consolidateSummary = nil } }
                   )) {
                Button("OK", role: .cancel) { consolidateSummary = nil }
            } message: {
                Text(consolidateSummary ?? "")
            }
            .alert("Rename Playlist",
                   isPresented: Binding(
                    get: { renamingPlaylist != nil },
                    set: { if !$0 { renamingPlaylist = nil } }
                   )) {
                TextField("Name", text: $renamingName)
                Button("Save") {
                    if let p = renamingPlaylist {
                        library.renamePlaylist(id: p.id, to: renamingName)
                    }
                    renamingPlaylist = nil
                }
                Button("Cancel", role: .cancel) { renamingPlaylist = nil }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func currentFolderRow(_ cur: URL) -> some View {
        HStack(spacing: 6) {
            Button {
                library.openFolder(cur)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Theme.accent)
                    Text(cur.lastPathComponent)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .help(cur.path)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                library.toggleFavouriteFolder(cur)
            } label: {
                Image(systemName: library.isFavouriteFolder(cur) ? "star.fill" : "star")
                    .foregroundStyle(library.isFavouriteFolder(cur) ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .help(library.isFavouriteFolder(cur)
                  ? "Remove from favourites" : "Add to favourites")
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        let active = library.currentPlaylist?.id == playlist.id
        Button {
            library.openPlaylist(playlist)
        } label: {
            Label(playlist.name, systemImage: "music.note.list")
                .foregroundStyle(active ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
        .help("\(playlist.trackURLs.count) tracks")
        .dropDestination(for: URL.self) { urls, _ in
            library.addToPlaylist(playlist.id, trackURLs: urls)
            return !urls.isEmpty
        }
        .contextMenu {
            Button("Rename…") {
                renamingPlaylist = playlist
                renamingName = playlist.name
            }
            Button("Move tracks to folder…") {
                consolidatePlaylist(id: playlist.id)
            }
            .disabled(playlist.trackURLs.isEmpty || consolidating)
            Button("Delete", role: .destructive) {
                library.deletePlaylist(id: playlist.id)
            }
        }
    }

    private func consolidatePlaylist(id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        panel.message = "Choose a folder to move all playlist tracks into"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        consolidating = true
        DispatchQueue.main.async {
            let r = library.consolidatePlaylist(id: id, to: dest)
            consolidating = false
            var parts: [String] = []
            if r.moved > 0 { parts.append("Moved \(r.moved)") }
            if r.alreadyThere > 0 { parts.append("\(r.alreadyThere) already there") }
            if r.renamed > 0 { parts.append("\(r.renamed) renamed to avoid conflict") }
            if r.failed > 0 { parts.append("\(r.failed) failed") }
            consolidateSummary = parts.isEmpty ? "Nothing to move." : parts.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var favouriteTracksRow: some View {
        Button {
            library.openFavourites()
        } label: {
            HStack {
                Label("Tracks", systemImage: "star.square.on.square")
                Spacer()
                if !library.favouriteTracks.isEmpty {
                    Text("\(library.favouriteTracks.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(library.source == .favourites ? Theme.accent : .primary)
    }

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

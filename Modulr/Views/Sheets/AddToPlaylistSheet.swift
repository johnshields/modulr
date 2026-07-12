import SwiftUI
import AppKit

/**
 * AddToPlaylistSheet
 * Bulk-add modal: choose a source folder, pick tracks, add them to the playlist.
 * Tracks already in the playlist are hidden. Mirrors MoveSheet's selection UI.
 */
struct AddToPlaylistSheet: View {
    let playlistID: String
    let playlistName: String
    let existingURLs: Set<URL>
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var source: URL?
    @State private var candidates: [Track] = []
    @State private var selected: Set<Track.ID> = []
    @State private var scanning = false

    private var selectedTracks: [Track] {
        candidates.filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sourceSection
            TrackSelectList(
                tracks: candidates, selected: $selected, tint: Theme.playlist,
                scanning: scanning,
                emptyText: source == nil ? "Choose a folder to add tracks from."
                                         : "No new tracks in this folder."
            )
            footer
        }
        .padding(20)
        .frame(width: 600, height: 540)
        .tint(Theme.playlist)
        .overlay(alignment: .topTrailing) {
            MacCloseButton { dismiss() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(.title2)
                .foregroundStyle(Theme.playlist)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Tracks")
                    .font(.headline)
                Text(playlistName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOURCE FOLDER")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(source == nil ? .secondary : Theme.playlist)
                Text(source?.path ?? "No folder chosen")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(source == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(source == nil ? "Choose…" : "Change") { chooseFolder() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                add()
            } label: {
                Label("Add \(selected.count)", systemImage: "text.badge.plus")
                    .padding(.horizontal, 6).padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.playlist)
            .disabled(selected.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder to add tracks from"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        source = url
        scan(url)
    }

    private func scan(_ folder: URL) {
        scanning = true
        candidates = []
        selected = []
        Task {
            let found = await LibraryScanner.scan(folder)
                .filter { !existingURLs.contains($0.url) }
            await MainActor.run {
                candidates = found
                selected = Set(found.map(\.id))
                scanning = false
            }
        }
    }

    private func add() {
        let urls = selectedTracks.map(\.url)
        guard !urls.isEmpty else { return }
        library.addToPlaylist(playlistID, trackURLs: urls)
        dismiss()
    }
}

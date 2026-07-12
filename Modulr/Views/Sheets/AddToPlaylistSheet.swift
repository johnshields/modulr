import SwiftUI
import AppKit

/**
 * AddToPlaylistSheet
 * Bulk-add modal: choose a source folder, pick tracks, add them to the playlist.
 * Tracks already in the playlist are hidden. Mirrors MoveSheet's selection UI.
 */
struct AddToPlaylistSheet: View {
    let playlistID: UUID
    let playlistName: String
    let existingURLs: Set<URL>
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var source: URL?
    @State private var candidates: [Track] = []
    @State private var selected: Set<Track.ID> = []
    @State private var scanning = false
    @State private var artCache: [URL: NSImage] = [:]

    private var selectedTracks: [Track] {
        candidates.filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sourceSection
            selectionToolbar
            trackList
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

    private var selectionToolbar: some View {
        HStack(spacing: 8) {
            Text("\(selected.count) of \(candidates.count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("All") { selected = Set(candidates.map(\.id)) }
                .controlSize(.small)
                .disabled(candidates.isEmpty || selected.count == candidates.count)
            Button("None") { selected.removeAll() }
                .controlSize(.small)
                .disabled(selected.isEmpty)
        }
    }

    private var trackList: some View {
        ScrollView {
            if scanning {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.top, 40)
            } else if candidates.isEmpty {
                Text(source == nil ? "Choose a folder to add tracks from."
                                   : "No new tracks in this folder.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(candidates) { t in row(t) }
                }
                .padding(8)
            }
        }
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(_ t: Track) -> some View {
        let isOn = selected.contains(t.id)
        HStack(spacing: 10) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Theme.playlist : .secondary)
                .frame(width: 18)
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.4))
                if let img = artCache[t.url] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .task { await loadArt(t.url) }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).lineLimit(1)
                Text(t.url.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let bpm = t.bpm { Text("\(bpm)").font(.caption).foregroundStyle(.secondary) }
            if let k = t.key { Text(KeyNormalizer.toMusical(k)).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isOn ? Theme.playlist.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { toggle(t.id) }
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

    private func toggle(_ id: Track.ID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
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

    private func loadArt(_ url: URL) async {
        guard artCache[url] == nil, let img = await ArtworkLoader.load(url) else { return }
        artCache[url] = img
    }
}

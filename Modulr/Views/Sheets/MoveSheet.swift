import SwiftUI
import AppKit

/**
 * MoveSheet
 * Bulk-move modal: pick a destination folder, select tracks, move, report outcome.
 */
struct MoveSheet: View {
    let playlistID: UUID
    let playlistName: String
    let tracks: [Track]
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<Track.ID>
    @State private var destination: URL?
    @State private var result: Library.ConsolidateResult?

    init(playlistID: UUID, playlistName: String, tracks: [Track]) {
        self.playlistID = playlistID
        self.playlistName = playlistName
        self.tracks = tracks
        _selected = State(initialValue: Set(tracks.map(\.id)))
    }

    private var selectedTracks: [Track] {
        tracks.filter { selected.contains($0.id) }
    }

    private var canMove: Bool {
        destination != nil && !selected.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let result {
                summarySection(result)
            } else {
                destinationSection
                TrackSelectList(
                    tracks: tracks, selected: $selected, tint: Theme.accent,
                    subtitle: { $0.url.deletingLastPathComponent().lastPathComponent }
                )
                footer
            }
        }
        .padding(20)
        .frame(width: 600, height: 540)
        .tint(Theme.accent)
        .overlay(alignment: .topTrailing) {
            MacCloseButton { dismiss() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: result == nil ? "folder.badge.gearshape" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(result == nil ? Theme.accent : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text(result == nil ? "Move Tracks" : "Move Complete")
                    .font(.headline)
                Text(result == nil ? playlistName : "Files moved on disk and playlist paths updated")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESTINATION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(destination == nil ? .secondary : Theme.accent)
                Text(destination?.path ?? "No folder chosen")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(destination == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(destination == nil ? "Choose…" : "Change") { chooseFolder() }
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
                move()
            } label: {
                Label("Move \(selected.count)", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 6).padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!canMove)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func summarySection(_ r: Library.ConsolidateResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statRow("Moved", r.moved, .green)
            statRow("Already there", r.alreadyThere, .gray)
            statRow("Renamed to avoid conflict", r.renamed, Theme.accent)
            statRow("Failed", r.failed, .red)
            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func statRow(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.callout)
            Spacer()
            Text("\(count)").font(.callout.bold().monospacedDigit()).foregroundStyle(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder to move the selected tracks into"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url
    }

    private func move() {
        guard let dest = destination else { return }
        result = library.consolidatePlaylist(
            id: playlistID,
            to: dest,
            urls: selectedTracks.map(\.url)
        )
    }
}

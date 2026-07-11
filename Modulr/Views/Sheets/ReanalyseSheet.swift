import SwiftUI
import AppKit

/**
 * ReanalyseSheet
 * Bulk re-analyse modal: pick tracks, write a filename backup CSV, then force
 * fresh BPM + key detection. The CSV preserves the pre-rename names so an
 * external library can be repaired after the files are renamed.
 */
struct ReanalyseSheet: View {
    let tracks: [Track]
    let onConfirm: ([Track]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<Track.ID>
    @State private var artCache: [URL: NSImage] = [:]
    @State private var backupError: String?

    init(tracks: [Track], onConfirm: @escaping ([Track]) -> Void) {
        self.tracks = tracks
        self.onConfirm = onConfirm
        _selected = State(initialValue: Set(tracks.map(\.id)))
    }

    private var selectedTracks: [Track] {
        tracks.filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            backupNotice
            selectionToolbar
            trackList
            footer
        }
        .padding(20)
        .frame(width: 600, height: 540)
        .tint(Theme.accent)
        .overlay(alignment: .topTrailing) {
            MacCloseButton { dismiss() }
        }
        .alert("Backup failed",
               isPresented: Binding(get: { backupError != nil },
                                    set: { if !$0 { backupError = nil } })) {
            Button("OK", role: .cancel) { backupError = nil }
        } message: {
            Text(backupError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Re-analyse Tracks")
                    .font(.headline)
                Text("Overwrites BPM and key with fresh detection, then re-formats filenames")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var backupNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(Theme.accent)
            Text("Current filenames are saved to a CSV beside the tracks, so an external library can be repaired later.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var selectionToolbar: some View {
        HStack(spacing: 8) {
            Text("\(selected.count) of \(tracks.count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("All") { selected = Set(tracks.map(\.id)) }
                .controlSize(.small)
                .disabled(selected.count == tracks.count)
            Button("None") { selected.removeAll() }
                .controlSize(.small)
                .disabled(selected.isEmpty)
        }
    }

    private var trackList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(tracks) { t in
                    row(t)
                }
            }
            .padding(8)
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
                .foregroundStyle(isOn ? Theme.accent : .secondary)
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
        .background(isOn ? Theme.accent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { toggle(t.id) }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                run()
            } label: {
                Label("Re-analyse \(selected.count)", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 6).padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(selected.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func toggle(_ id: Track.ID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func run() {
        let items = selectedTracks
        guard !items.isEmpty else { return }
        do {
            try writeBackup(items)
        } catch {
            backupError = error.localizedDescription
            return
        }
        onConfirm(items)
        dismiss()
    }

    /// Write a CSV of the current names + tags beside the tracks, before any rename.
    private func writeBackup(_ items: [Track]) throws {
        guard let dir = items.first?.url.deletingLastPathComponent() else { return }
        let stamp = Self.stampFormatter.string(from: Date())
        let url = dir.appendingPathComponent("modulr-reanalyse-backup-\(stamp).csv")
        var csv = "filename,key,bpm,title,artist,path\n"
        for t in items {
            let fields = [
                t.url.lastPathComponent,
                t.key ?? "",
                t.bpm.map(String.init) ?? "",
                t.title,
                t.artist ?? "",
                t.url.path,
            ]
            csv += fields.map(Self.csvEscape).joined(separator: ",") + "\n"
        }
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f
    }()

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func loadArt(_ url: URL) async {
        guard artCache[url] == nil, let img = await ArtworkLoader.load(url) else { return }
        artCache[url] = img
    }
}

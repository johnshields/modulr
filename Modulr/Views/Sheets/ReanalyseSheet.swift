import SwiftUI

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
            TrackSelectList(tracks: tracks, selected: $selected, tint: Theme.accent)
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
}

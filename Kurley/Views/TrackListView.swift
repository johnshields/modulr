import SwiftUI
import AppKit

struct TrackListView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @Binding var showAnalyze: Bool
    let onPlay: (URL) -> Void

    @State private var selection: Track.ID?
    @State private var sortOrder: [KeyPathComparator<Track>] = [.init(\.title)]
    @State private var tagTrack: Track?
    @State private var deleteTrack: Track?

    @State private var editMode = false
    @State private var editItems: [Track] = []
    @State private var dragID: UUID?
    @State private var padding: Int = 3

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    private var sorted: [Track] { library.tracks.sorted(using: sortOrder) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if editMode { editBody } else { tableBody }
        }
        .tint(Self.accent)
        .sheet(item: $tagTrack) { t in TagEditSheet(track: t).environmentObject(library) }
        .sheet(item: $deleteTrack) { t in
            DeleteSheet(
                track: t,
                accent: Self.accent,
                onTrashRenumber: {
                    deleteAndRenumber(t)
                    deleteTrack = nil
                },
                onTrash: {
                    try? library.deleteTrack(t.id)
                    deleteTrack = nil
                },
                onCancel: { deleteTrack = nil }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(library.tracks.count) tracks")
                .font(.caption).foregroundStyle(.secondary)

            if editMode {
                Picker("", selection: $padding) {
                    Text("01").tag(2); Text("001").tag(3); Text("0001").tag(4)
                }
                .pickerStyle(.segmented).fixedSize()

                Menu("Sort") {
                    Button("BPM ascending") { withAnimation { editItems.sort { ($0.bpm ?? 0) < ($1.bpm ?? 0) } } }
                    Button("BPM descending") { withAnimation { editItems.sort { ($0.bpm ?? 0) > ($1.bpm ?? 0) } } }
                    Button("Key") { withAnimation { editItems.sort { ($0.key ?? "") < ($1.key ?? "") } } }
                    Button("Title") { withAnimation { editItems.sort { $0.title < $1.title } } }
                    Button("Reverse") { withAnimation { editItems.reverse() } }
                }
                .fixedSize()
            }

            Spacer()

            if editMode {
                Button("Cancel") { editMode = false }
                Button("Apply") { applyEdit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editItems.isEmpty)
            } else {
                Button {
                    editItems = sorted
                    editMode = true
                } label: { Label("Edit Order", systemImage: "list.number") }
                .controlSize(.small)
                .disabled(library.tracks.isEmpty)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var tableBody: some View {
        Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.title) { t in
                HStack {
                    Button {
                        library.toggleFavorite(t.id)
                    } label: {
                        Image(systemName: library.favorites.contains(t.id) ? "star.fill" : "star")
                    }.buttonStyle(.borderless)
                    Text(t.title).lineLimit(1)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Artist", value: \.artistSort) { t in
                Text(t.artistDisplay)
                    .lineLimit(1)
                    .foregroundStyle(t.artist == nil ? .secondary : .primary)
            }
            .width(min: 140, ideal: 200)

            TableColumn("BPM", value: \.bpmSort) { t in Text(t.bpmDisplay) }
                .width(min: 50, ideal: 60, max: 80)

            TableColumn("Key", value: \.keySort) { t in Text(t.keyDisplay) }
                .width(min: 50, ideal: 60, max: 80)

            TableColumn("Duration", value: \.duration) { t in Text(format(t.duration)) }
                .width(min: 70, ideal: 80, max: 100)

            TableColumn("Type", value: \.fileType) { t in Text(t.fileType) }
                .width(min: 50, ideal: 60, max: 80)
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            if let id = ids.first, let t = sorted.first(where: { $0.id == id }) {
                menu(for: t)
            }
        }
        .onChange(of: selection) { _, new in
            guard let id = new, let t = sorted.first(where: { $0.id == id }) else { return }
            play(t)
        }
    }

    private var editBody: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(editItems.enumerated()), id: \.element.id) { idx, t in
                    editRow(idx: idx, t: t)
                        .onDrag {
                            dragID = t.id
                            return NSItemProvider(object: t.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: RowDropDelegate(
                            target: t, items: $editItems, dragID: $dragID
                        ))
                }
            }
            .padding(8)
        }
        .background(Color.black.opacity(0.2))
    }

    @ViewBuilder
    private func editRow(idx: Int, t: Track) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 16)
            Text(String(format: "%0\(padding)d", idx + 1))
                .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).lineLimit(1)
                if let a = t.artist {
                    Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let bpm = t.bpm { Text("\(bpm)").font(.caption).foregroundStyle(.secondary) }
            if let k = t.key { Text(KeyNormalizer.toMusical(k)).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dragID == t.id ? Self.accent.opacity(0.25) : Color.white.opacity(idx % 2 == 0 ? 0.04 : 0))
        )
        .opacity(dragID == t.id ? 0.5 : 1)
    }

    @ViewBuilder
    private func menu(for t: Track) -> some View {
        Button { play(t) } label: { Label("Play", systemImage: "play.fill") }
        Button { tagTrack = t } label: { Label("Edit Track Info…", systemImage: "info.circle") }
            .disabled(!TagIO.isMP3(t.url))
        Button {
            analyzer.analyzeFile(t.url) {}
            showAnalyze = true
        } label: { Label("Analyze BPM/Key", systemImage: "waveform.badge.magnifyingglass") }
            .disabled(!TagIO.isMP3(t.url))
        Divider()
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([t.url])
        } label: { Label("Show in Finder", systemImage: "folder") }
        Button(role: .destructive) { deleteTrack = t } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private func play(_ t: Track) {
        onPlay(t.url)
    }

    private func deleteAndRenumber(_ t: Track) {
        let remainingIDs = sorted.filter { $0.id != t.id }.map(\.id)
        do {
            try library.deleteTrack(t.id)
            try library.renumber(orderedIDs: remainingIDs, padding: padding)
        } catch {
            print("delete+renumber fail: \(error)")
        }
    }

    private func applyEdit() {
        try? library.renumber(orderedIDs: editItems.map(\.id), padding: padding)
        editMode = false
    }

    private struct DeleteSheet: View {
        let track: Track
        let accent: Color
        let onTrashRenumber: () -> Void
        let onTrash: () -> Void
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.title2).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move to Trash?").font(.headline)
                        Text(track.url.lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    Button(action: onTrashRenumber) {
                        Label("Move to Trash & Renumber", systemImage: "list.number")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)

                    Button(role: .destructive, action: onTrash) {
                        Label("Move to Trash", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }

    private func format(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}

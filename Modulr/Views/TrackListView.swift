import SwiftUI
import AppKit

struct TrackListView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var analyzer: Analyzer
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var quality: QualityCache
    @Binding var showAnalyze: Bool
    @Binding var editingOrder: Bool
    let onPlay: (URL) -> Void

    @State private var selection: Track.ID?
    @State private var sortOrder: [KeyPathComparator<Track>] = [.init(\.title)]
    @State private var tagTrack: Track?
    @State private var spectrumTrack: Track?
    @State private var convertTrack: Track?
    @State private var brightenTrack: Track?
    @State private var loudnessTrack: Track?
    @State private var deleteTrack: Track?
    @State private var search = ""
    @State private var unanalysedOnly = false

    @State private var editItems: [Track] = []
    @State private var dragID: UUID?
    @State private var applying = false
    @State private var applyProgress: (done: Int, total: Int) = (0, 0)
    @State private var artCache: [URL: NSImage] = [:]

    private static let accent = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)
    private static let compatTint = Color(red: 0x7d/255, green: 0x77/255, blue: 0xfb/255)

    private var sorted: [Track] { library.tracks.sorted(using: sortOrder) }

    private var visible: [Track] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        var pool = sorted
        if unanalysedOnly {
            pool = pool.filter { $0.bpm == nil || $0.key == nil }
        }
        guard !q.isEmpty else { return pool }
        return pool.filter { t in
            if t.title.lowercased().contains(q) { return true }
            if let a = t.artist, a.lowercased().contains(q) { return true }
            if let k = t.key {
                if k.lowercased() == q { return true }
                if KeyNormalizer.toMusical(k).lowercased() == q { return true }
            }
            if let b = t.bpm, String(b) == q { return true }
            return false
        }
    }

    private var unanalysedCount: Int {
        library.tracks.filter { $0.bpm == nil || $0.key == nil }.count
    }

    private var currentKey: String? {
        guard let url = player.currentURL,
              let t = library.tracks.first(where: { $0.url == url }),
              let k = t.key else { return nil }
        return k
    }

    private var compatKeys: Set<String> {
        guard let k = currentKey else { return [] }
        return KeyNormalizer.compatibleMusicals(of: k)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if editingOrder { editBody } else { tableBody }
        }
        .tint(Self.accent)
        .sheet(item: $tagTrack) { t in TagEditSheet(track: t).environmentObject(library) }
        .sheet(item: $spectrumTrack) { t in SpectrumSheet(trackURL: t.url) }
        .sheet(item: $convertTrack) { t in
            ConvertSheet(track: t)
                .environmentObject(library)
                .environmentObject(analyzer)
                .environmentObject(player)
                .environmentObject(quality)
        }
        .sheet(item: $brightenTrack) { t in
            BrightenSheet(track: t)
                .environmentObject(library)
                .environmentObject(analyzer)
                .environmentObject(player)
                .environmentObject(quality)
        }
        .sheet(item: $loudnessTrack) { t in
            LoudnessSheet(track: t)
                .environmentObject(library)
                .environmentObject(analyzer)
                .environmentObject(player)
                .environmentObject(quality)
        }
        .sheet(item: $deleteTrack) { t in
            DeleteSheet(
                track: t,
                accent: Self.accent,
                onTrash: {
                    try? library.deleteTrack(t.id)
                    deleteTrack = nil
                },
                onCancel: { deleteTrack = nil }
            )
        }
    }

    private var totalDurationDisplay: String {
        let total = Int(library.tracks.reduce(0) { $0 + $1.duration }.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? "\(h)h \(m)m \(s)s" : "\(m)m \(s)s"
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("\(library.tracks.count) tracks")
                if library.source == .playlist && !library.tracks.isEmpty {
                    Text("|").foregroundStyle(.tertiary)
                    Text(totalDurationDisplay)
                }
            }
            .font(.caption).foregroundStyle(.secondary)

            if !editingOrder {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 10))
                    TextField("Search title, key, BPM…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(minWidth: 180, maxWidth: 240)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
            }

            if editingOrder {
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

            if !editingOrder && library.source == .playlist && !library.tracks.isEmpty {
                Button {
                    editItems = sorted
                    editingOrder = true
                } label: {
                    Label("Edit Order", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Drag to reorder. Apply writes track numbers.")
            }

            if !editingOrder && library.source == .folder {
                Toggle(isOn: $unanalysedOnly) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.badge.exclamationmark")
                        Text("Un-analysed\(unanalysedCount > 0 ? " (\(unanalysedCount))" : "")")
                    }
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show only tracks missing BPM or key")

                if unanalysedOnly && unanalysedCount > 0 {
                    Button {
                        guard let cur = library.currentFolder else { return }
                        analyzer.analyzeFolder(cur,
                                               rename: analyzer.renameAfter,
                                               onlyUntagged: true) {}
                        showAnalyze = true
                    } label: {
                        Label("Analyse \(unanalysedCount)",
                              systemImage: "waveform.badge.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    .help("Detect BPM and key for the un-analysed tracks in this folder")
                }
            }

            if editingOrder {
                Button("Cancel") { editingOrder = false }.disabled(applying)
                Button(applying ? "Applying…" : "Apply") { applyEdit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editItems.isEmpty || applying)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var tableBody: some View {
        Table(visible, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("#", value: \.trackNumberSort) { t in
                Text(t.trackNumberDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 32, ideal: 40, max: 56)
            .defaultVisibility(library.source == .playlist ? .visible : .hidden)

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

            TableColumn("Key", value: \.keySort) { t in
                let musical = t.key.map { KeyNormalizer.toMusical($0) } ?? ""
                let isCompat = !musical.isEmpty && compatKeys.contains(musical)
                Text(t.keyDisplay)
                    .foregroundStyle(isCompat ? Self.compatTint : .primary)
                    .fontWeight(isCompat ? .semibold : .regular)
            }
            .width(min: 50, ideal: 60, max: 80)

            TableColumn("Duration", value: \.duration) { t in Text(Formatters.mmss(t.duration)) }
                .width(min: 70, ideal: 80, max: 100)

            TableColumn("Type", value: \.fileType) { t in
                HStack(spacing: 6) {
                    Text(t.fileType)
                    if let kbps = t.bitrate {
                        Text("\(kbps)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let v = quality.verdicts[t.url] {
                        Text(v.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(v.color)
                            .help(v.detail)
                    }
                }
                .onAppear { quality.requestVerdict(t.url) }
            }
            .width(min: 130, ideal: 170, max: 220)

            TableColumn("Added", value: \.dateAddedSort) { t in
                Text(t.dateAddedDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120, max: 150)
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
        ZStack {
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
            .disabled(applying)
            .opacity(applying ? 0.4 : 1)

            if applying {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Applying \(applyProgress.done) / \(applyProgress.total)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func editRow(idx: Int, t: Track) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .cursor(.openHand)
            Text(String(format: "%03d", idx + 1))
                .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.4))
                if let img = artCache[t.url] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .task { await loadArt(t.url) }
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
        .cursor(dragID == t.id ? .closedHand : .openHand)
    }

    @ViewBuilder
    private func menu(for t: Track) -> some View {
        Button { play(t) } label: { Label("Play", systemImage: "play.fill") }
        Button { tagTrack = t } label: { Label("Edit Track Info…", systemImage: "info.circle") }
            .disabled(!TagIO.supportsTags(t.url))
        Button {
            analyzer.analyzeFile(t.url, rename: analyzer.renameAfter) {}
            showAnalyze = true
        } label: { Label("Analyse BPM/Key", systemImage: "waveform.badge.magnifyingglass") }
            .disabled(!TagIO.supportsTags(t.url))
        Button { spectrumTrack = t } label: {
            Label("Show Spectrum", systemImage: "waveform.path")
        }
        Button { convertTrack = t } label: {
            Label("Convert to MP3…", systemImage: "waveform.path.badge.plus")
        }
        .disabled(t.url.pathExtension.lowercased() == "mp3")
        Button { brightenTrack = t } label: {
            Label("Brighten Track…", systemImage: "sparkles")
        }
        Button { loudnessTrack = t } label: {
            Label("Normalise Loudness…", systemImage: "speaker.wave.3.fill")
        }
        Divider()
        Menu {
            ForEach(library.playlists) { p in
                Button(p.name) {
                    library.addToPlaylist(p.id, trackURLs: [t.url])
                }
            }
            if !library.playlists.isEmpty { Divider() }
            Button("New Playlist…") {
                let p = library.createPlaylist(name: "New Playlist")
                library.addToPlaylist(p.id, trackURLs: [t.url])
            }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
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

    private func loadArt(_ url: URL) async {
        guard artCache[url] == nil, let img = await ArtworkLoader.load(url) else { return }
        artCache[url] = img
    }

    private func applyEdit() {
        let ids = editItems.map(\.id)
        let urls = editItems.map(\.url)
        let lib = library
        let inPlaylist = library.source == .playlist
        applyProgress = (0, ids.count)
        applying = true
        DispatchQueue.global(qos: .userInitiated).async {
            if inPlaylist {
                DispatchQueue.main.sync { lib.reorderCurrentPlaylist(orderedURLs: urls) }
            }
            lib.renumberByTag(orderedIDs: ids) { done, total in
                DispatchQueue.main.async { applyProgress = (done, total) }
            }
            DispatchQueue.main.async {
                applying = false
                editingOrder = false
            }
        }
    }

    private struct DeleteSheet: View {
        let track: Track
        let accent: Color
        let onTrash: () -> Void
        let onCancel: () -> Void
        var playlistMemberships: () -> [String] = { [] }

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

                let memberships = playlistMemberships()
                if !memberships.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Used in: \(memberships.joined(separator: ", ")). Will be removed from those playlists.")
                            .font(.caption).foregroundStyle(.yellow)
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    Button(role: .destructive, action: onTrash) {
                        Label("Move to Trash", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(20)
            .frame(width: 380)
            .overlay(alignment: .topTrailing) {
                MacCloseButton(action: onCancel)
            }
        }
    }

}

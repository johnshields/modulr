import SwiftUI
import AppKit

/**
 * TrackSelectList
 * Shared selection UI for the bulk sheets: an All/None toolbar with a count over
 * a scrollable checkbox list of tracks. Callers bind the selection and style the
 * tint; the subtitle, empty text and a scanning state are configurable.
 */
struct TrackSelectList: View {
    enum SortKey: String, CaseIterable { case added = "Added", title = "Title", artist = "Artist", bpm = "BPM" }

    let tracks: [Track]
    @Binding var selected: Set<Track.ID>
    var tint: Color = Theme.accent
    var scanning: Bool = false
    var emptyText: String = "No tracks."
    var subtitle: (Track) -> String = { $0.url.lastPathComponent }

    @State private var artCache: [URL: NSImage] = [:]
    @State private var sortKey: SortKey = .added

    private var sortedTracks: [Track] {
        switch sortKey {
        case .added:  return tracks.sorted { $0.dateAddedSort > $1.dateAddedSort }
        case .title:  return tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: return tracks.sorted { $0.artistSort.localizedCaseInsensitiveCompare($1.artistSort) == .orderedAscending }
        case .bpm:    return tracks.sorted { $0.bpmSort < $1.bpmSort }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            list
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("\(selected.count) of \(tracks.count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(SortKey.allCases, id: \.self) { key in
                    Button {
                        sortKey = key
                    } label: {
                        if sortKey == key { Label(key.rawValue, systemImage: "checkmark") }
                        else { Text(key.rawValue) }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
            .disabled(tracks.isEmpty)
            Button("All") { selected = Set(tracks.map(\.id)) }
                .controlSize(.small)
                .disabled(tracks.isEmpty || selected.count == tracks.count)
            Button("None") { selected.removeAll() }
                .controlSize(.small)
                .disabled(selected.isEmpty)
        }
    }

    private var list: some View {
        ScrollView {
            if scanning {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.top, 40)
            } else if tracks.isEmpty {
                Text(emptyText)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(sortedTracks) { row($0) }
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
                .foregroundStyle(isOn ? tint : .secondary)
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
                Text(subtitle(t))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let bpm = t.bpm { Text("\(bpm)").font(.caption).foregroundStyle(.secondary) }
            if let k = t.key { Text(KeyNormalizer.toMusical(k)).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isOn ? tint.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { toggle(t.id) }
    }

    private func toggle(_ id: Track.ID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func loadArt(_ url: URL) async {
        guard artCache[url] == nil, let img = await ArtworkLoader.load(url) else { return }
        artCache[url] = img
    }
}

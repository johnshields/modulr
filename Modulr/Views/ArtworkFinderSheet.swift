import SwiftUI
import AppKit

struct ArtworkFinderSheet: View {
    let track: Track
    let onPicked: (Data, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var artistQuery: String = ""
    @State private var candidates: [ArtworkCandidate] = []
    @State private var loading = false
    @State private var thumbCache: [URL: NSImage] = [:]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Artwork").font(.headline)
            HStack {
                TextField("Title", text: $query)
                TextField("Artist", text: $artistQuery)
                Button("Search") { Task { await runSearch() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.isEmpty)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(candidates) { c in
                        thumb(c)
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 360)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if loading { ProgressView().controlSize(.large) }
                else if candidates.isEmpty && !query.isEmpty {
                    Text("No results").foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 540)
        .tint(Theme.accent)
        .onAppear {
            query = sanitise(track.title)
            artistQuery = track.artist ?? ""
            Task { await runSearch() }
        }
    }

    /**
     * Strip NNN_ prefix, _KEY_BPM suffix, replace separators with spaces.
     */
    private func sanitise(_ raw: String) -> String {
        var s = raw

        // Drop leading NNN_
        s = s.replacingOccurrences(of: #"^\d{2,4}[_-]"#, with: "", options: .regularExpression)

        // Drop trailing _KEY_BPM (repeat for stacked)
        while true {
            let next = s.replacingOccurrences(
                of: #"[_-][A-Za-z#]{1,6}[_-]\d{2,3}$"#,
                with: "",
                options: .regularExpression
            )
            if next == s { break }
            s = next
        }

        // Separators -> spaces
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "-", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder
    private func thumb(_ c: ArtworkCandidate) -> some View {
        Button {
            Task { await pick(c) }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.4))
                    if let img = thumbCache[c.thumbURL] {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 100, height: 100)
                .task { await loadThumb(c.thumbURL) }

                Text(c.title)
                    .font(.caption2).lineLimit(1).foregroundStyle(.primary)
                Text(c.artist)
                    .font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            }
            .frame(width: 110)
        }
        .buttonStyle(.plain)
    }

    private func runSearch() async {
        loading = true
        candidates = []
        candidates = await ArtworkFinder.search(title: query, artist: artistQuery)
        loading = false
    }

    private func loadThumb(_ url: URL) async {
        guard thumbCache[url] == nil,
              let data = await ArtworkFinder.download(url),
              let img = NSImage(data: data) else { return }
        thumbCache[url] = img
    }

    private func pick(_ c: ArtworkCandidate) async {
        guard let data = await ArtworkFinder.download(c.highResURL) else { return }
        let mime = c.highResURL.absoluteString.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
        onPicked(data, mime)
        dismiss()
    }
}

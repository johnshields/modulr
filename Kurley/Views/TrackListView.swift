import SwiftUI

struct TrackListView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: AudioPlayer
    @State private var selection: UUID?

    var body: some View {
        Table(library.tracks, selection: $selection) {
            TableColumn("Name") { t in
                HStack {
                    Button {
                        library.toggleFavorite(t.id)
                    } label: {
                        Image(systemName: library.favorites.contains(t.id) ? "star.fill" : "star")
                    }.buttonStyle(.borderless)
                    Text(t.title)
                }
            }
            TableColumn("Duration") { t in Text(format(t.duration)) }
            TableColumn("Type") { t in Text(t.fileType) }
        }
        .onChange(of: selection) { _, new in
            guard let id = new, let track = library.tracks.first(where: { $0.id == id }) else { return }
            player.load(track.url)
            player.play()
        }
    }

    private func format(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var player: AudioPlayer
    @StateObject private var library = Library()
    @StateObject private var analyzer = Analyzer()
    @State private var showAnalyze = false
    @State private var artwork: NSImage?

    var windowTitle: String {
        guard let url = player.currentURL else { return "Kurley" }
        let name = url.deletingPathExtension().lastPathComponent
        return "Now Playing — \(name)"
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(showAnalyze: $showAnalyze)
                .environmentObject(library)
                .environmentObject(analyzer)
        } detail: {
            VStack(spacing: 0) {
                WaveformView(monitor: player.monitor)
                    .environmentObject(library)
                TransportView(showAnalyze: $showAnalyze)
                    .environmentObject(library)
                    .environmentObject(analyzer)
                Divider()
                TrackListView(showAnalyze: $showAnalyze, onPlay: { url in
                    player.load(url)
                    player.play()
                })
                    .environmentObject(library)
                    .environmentObject(analyzer)
            }
        }
        .sheet(isPresented: $showAnalyze) {
            AnalyzeSheet(analyzer: analyzer) {
                if let f = library.currentFolder { library.openFolder(f) }
            }
        }
        .navigationTitle(windowTitle)
        .onAppear {
            NowPlaying.shared.setup(player: player, onNext: nextTrack, onPrev: prevTrack)
        }
        .onChange(of: player.currentURL) { _, url in
            updateNowPlaying(url: url)
        }
        .onChange(of: player.isPlaying) { _, _ in
            NowPlaying.shared.updatePlaybackState()
        }
    }

    private func updateNowPlaying(url: URL?) {
        guard let url else {
            artwork = nil
            NowPlaying.shared.clear()
            return
        }
        let track = library.tracks.first(where: { $0.url == url })
        let title = track?.title ?? url.deletingPathExtension().lastPathComponent
        let artist = track?.artist
        Task {
            let art = await ArtworkLoader.load(url)
            await MainActor.run {
                self.artwork = art
                NowPlaying.shared.update(title: title, artist: artist, artwork: art)
            }
        }
    }

    private func nextTrack() {
        let tracks = library.tracks
        guard !tracks.isEmpty else { return }
        let next: Track
        if player.isShuffled {
            next = tracks.randomElement()!
        } else if let url = player.currentURL,
                  let i = tracks.firstIndex(where: { $0.url == url }),
                  i + 1 < tracks.count {
            next = tracks[i + 1]
        } else {
            next = tracks[0]
        }
        player.load(next.url)
        player.play()
    }

    private func prevTrack() {
        let tracks = library.tracks
        guard !tracks.isEmpty else { return }
        if player.currentTime > 3 { player.seek(to: 0); return }
        let prev: Track
        if let url = player.currentURL,
           let i = tracks.firstIndex(where: { $0.url == url }),
           i > 0 {
            prev = tracks[i - 1]
        } else {
            prev = tracks.last!
        }
        player.load(prev.url)
        player.play()
    }
}


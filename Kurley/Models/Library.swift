import Foundation
import AVFoundation
import Combine

/**
 * Library
 * Tracks list, folder open, favorites, playlists
 */
final class Library: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var favorites: Set<UUID> = []
    @Published var recents: [URL] = []

    private let supportedExt: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac", "aac"]

    func openFolder(_ url: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        var found: [Track] = []
        for case let file as URL in enumerator {
            guard supportedExt.contains(file.pathExtension.lowercased()) else { continue }
            let asset = AVURLAsset(url: file)
            let dur = CMTimeGetSeconds(asset.duration)
            found.append(Track(url: file, title: file.deletingPathExtension().lastPathComponent, duration: dur))
        }
        tracks = found
    }

    func toggleFavorite(_ id: UUID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }
}

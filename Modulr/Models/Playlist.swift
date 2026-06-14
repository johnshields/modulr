import Foundation

/**
 * Playlist
 * Ordered curation of track URLs. Tracks themselves live in folders; the
 * playlist just references them. Order is the playlist's responsibility now
 * that TRCK / trkn writing is reserved for playlist Edit Order.
 */
struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var trackURLs: [URL]

    init(id: UUID = UUID(), name: String, trackURLs: [URL] = []) {
        self.id = id
        self.name = name
        self.trackURLs = trackURLs
    }
}

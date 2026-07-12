import Foundation

/**
 * PlaylistStore
 * SQLite persistence for playlists in `~/Library/Application Support/Modulr/`.
 * Playlists and their ordered track URLs live in two tables.
 */
final class PlaylistStore {
    private let db: Database

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("Modulr", isDirectory: true)
        self.db = Database(path: root.appendingPathComponent("modulr.sqlite"))
        db.execScript(PlaylistSchema.sql)
    }

    func loadAll() -> [Playlist] {
        db.fetchAll(PlaylistQueries.findAll).compactMap { row in
            guard let uidString = row["uid"] as? String,
                  let id = UUID(uuidString: uidString),
                  let name = row["name"] as? String else { return nil }
            let urls = db.fetchAll(PlaylistQueries.tracksFor, [.text(uidString)])
                .compactMap { ($0["track_url"] as? String).flatMap(URL.init(string:)) }
            return Playlist(id: id, name: name, trackURLs: urls)
        }
    }

    func save(_ playlist: Playlist) {
        let uid = playlist.id.uuidString
        db.transaction {
            db.exec(PlaylistQueries.upsertPlaylist, [.text(uid), .text(playlist.name)])
            db.exec(PlaylistQueries.clearTracks, [.text(uid)])
            for (position, url) in playlist.trackURLs.enumerated() {
                db.exec(PlaylistQueries.insertTrack,
                        [.text(UUID().uuidString), .text(uid), .text(url.absoluteString), .int(position)])
            }
        }
    }

    func delete(id: UUID) {
        db.exec(PlaylistQueries.softDelete, [.text(id.uuidString)])
    }
}

import Foundation

/**
 * PlaylistQueries
 * Named SQL for the playlists + playlist_tracks tables. Soft delete via
 * deleted_at throughout.
 */
enum PlaylistQueries {
    static let findAll = """
        SELECT uid, name FROM playlists
        WHERE deleted_at IS NULL
        ORDER BY name COLLATE NOCASE ASC
    """

    static let tracksFor = """
        SELECT track_url FROM playlist_tracks
        WHERE playlist_uid = ?
        ORDER BY position ASC
    """

    static let upsertPlaylist = """
        INSERT INTO playlists (uid, name) VALUES (?, ?)
        ON CONFLICT(uid) DO UPDATE SET name = excluded.name
    """

    static let clearTracks = """
        DELETE FROM playlist_tracks WHERE playlist_uid = ?
    """

    static let insertTrack = """
        INSERT INTO playlist_tracks (playlist_uid, track_url, position)
        VALUES (?, ?, ?)
    """

    static let softDelete = """
        UPDATE playlists
        SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE uid = ? AND deleted_at IS NULL
    """
}
